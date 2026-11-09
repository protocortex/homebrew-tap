class Liam < Formula
  desc "Bi-temporal memory for AI agents, served over MCP"
  homepage "https://github.com/protocortex/liam"
  # The stable tarball is the release's prebuilt Apple Silicon netinstall
  # archive (liamd and liam). Do not edit
  # the url or sha256 by hand: .github/scripts/bump-formula.sh writes them from
  # the release's SHA256SUMS.
  url "https://github.com/protocortex/liam/releases/download/v0.1.1/liam-v0.1.1-aarch64-apple-darwin-netinstall.tar.gz"
  sha256 "f79e25dc0612641bca61a2495a54117778b7ae363c761fc425406fe5bc9f62ca"
  license "Apache-2.0"

  livecheck do
    url :stable
    strategy :github_releases
    regex(/^v(\d+(?:\.\d+)+)$/i)
  end

  # Mirrors the build flags in liam's release workflow: `local` supplies the
  # real embedder and reranker, `llama` supplies generation. llama-cpp-sys-2
  # compiles llama.cpp through CMake, so a HEAD build is slow on a cold cache.
  head do
    url "https://github.com/protocortex/liam.git", branch: "main"

    depends_on "cmake" => :build
    depends_on "rust" => :build
  end

  depends_on arch: :arm64
  depends_on :macos

  def install
    if build.head?
      # Homebrew's OpenSSL on the build machine breaks llama.cpp's CMake and
      # its HTTPS support is unused. Same workaround as the release workflow.
      ENV["CMAKE_DISABLE_FIND_PACKAGE_OpenSSL"] = "ON"
      # llama.cpp's CMake wires in sccache or ccache when it finds one under
      # /opt/homebrew, but the brew build PATH hides it and every compile fails
      # with "sccache: command not found". llama-cpp-sys-2 forwards GGML_*.
      ENV["GGML_CCACHE"] = "OFF"
      # The cc crate takes its deployment target from `xcrun --show-sdk-version`,
      # which can be newer than the SDK brew compiles against (26.2 on a macOS 15
      # host). llama.cpp's vendored subprocess.h then calls an API only that newer
      # SDK declares. Pin the target to the running OS.
      ENV["MACOSX_DEPLOYMENT_TARGET"] = MacOS.version.to_s
      system "cargo", "install", *std_cargo_args(path: "crates/liam-daemon")
      (pkgshare/"liam.toml").write release_config(File.read("liam.toml"))
    else
      bin.install "liamd", "liam"
      pkgshare.install "liam.toml"
    end
  end

  # The repo's liam.toml is the dev config, with both providers set to "mock".
  # Shipping it beside real binaries would serve random embeddings and
  # fabricated answers without any error, so derive the shipped config the same
  # way the release workflow does: rewrite `provider` inside [embedder] and
  # [llm] only, then fail the build if the result is not what we expect.
  def release_config(source)
    wanted = { "embedder" => "local", "llm" => "llama-cpp" }
    section = nil
    config = source.lines.map do |line|
      if (header = line.match(/\A\s*\[([^\]]+)\]/))
        section = header[1]
      elsif wanted.key?(section) && line.match?(/\A\s*provider\s*=/)
        line = line.sub('"mock"', "\"#{wanted.fetch(section)}\"")
      end
      line
    end.join
    odie "release config still selects a mock provider" if config.match?(/^provider\s*=\s*"mock"/)
    odie "release config lacks the local embedder" unless config.match?(/^provider\s*=\s*"local"/)
    odie "release config lacks the llama-cpp llm" unless config.match?(/^provider\s*=\s*"llama-cpp"/)
    config
  end

  def caveats
    text = <<~EOS
      Models are not downloaded by the install (several gigabytes). To finish setup:

        mkdir -p ~/.liam
        cp -n #{opt_pkgshare}/liam.toml ~/.liam/liam.toml
        liam fetch-models --config ~/.liam/liam.toml

      Then either run the daemon in the background:

        brew services start liam

      or in a terminal:

        liamd --config ~/.liam/liam.toml serve

      Point an MCP client at the daemon through the proxy, for example:

        { "command": "liamd", "args": ["--config", "#{Dir.home}/.liam/liam.toml", "proxy"] }

      Your config and data live in ~/.liam and are kept on upgrade and uninstall.
      The shipped config template is at #{opt_pkgshare}/liam.toml.

      The launchd job from the brew service starts the daemon at load rather than
      on the first connection, because Homebrew services cannot hand launchd a
      Unix socket. Run `brew services stop liam` to stop it.
    EOS
    # A HEAD build has no release, so it gets no release notes link.
    return text if build.head?

    text + "\nRelease notes: https://github.com/protocortex/liam/releases/tag/v#{version}\n"
  end

  service do
    run [opt_bin/"liamd", "--config", "#{Dir.home}/.liam/liam.toml", "serve"]
    keep_alive crashed: true
    working_dir "#{Dir.home}/.liam"
    error_log_path "#{Dir.home}/.liam/liamd.log"
  end

  test do
    assert_match "liamd", shell_output("#{bin}/liamd --version")
    assert_match "liam", shell_output("#{bin}/liam --version")
    unless build.head?
      # Stable binaries must report the formula version. The v0.1.1 release was
      # tagged without bumping Cargo.toml, so its binaries still print 0.1.0.
      # This exception goes away with the next bump, since the check only
      # applies while the formula is at 0.1.1.
      expected = (version.to_s == "0.1.1") ? "0.1.0" : version.to_s
      assert_match expected, shell_output("#{bin}/liamd --version")
      assert_match expected, shell_output("#{bin}/liam --version")
    end
    assert_match "serve", shell_output("#{bin}/liamd --help")
    assert_match "fetch-models", shell_output("#{bin}/liam --help")
    assert_path_exists pkgshare/"liam.toml"

    # MCP initialize round trip over stdio. The mock providers keep it free of
    # model downloads, and the store lives in the test's temp directory.
    (testpath/"liam.toml").write <<~TOML
      database_path = "#{testpath}/liam.db"
      [embedder]
      provider = "mock"
      [llm]
      provider = "mock"
    TOML
    request = {
      jsonrpc: "2.0",
      id:      1,
      method:  "initialize",
      params:  {
        protocolVersion: "2025-06-18",
        capabilities:    {},
        clientInfo:      { name: "brew-test", version: "0" },
      },
    }.to_json
    output = pipe_output("#{bin}/liamd --config #{testpath}/liam.toml", "#{request}\n", 0)
    response = JSON.parse(output.lines.first)
    assert_equal 1, response["id"]
    assert_predicate response.dig("result", "serverInfo", "name"), :present?
  end
end
