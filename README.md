# protocortex/homebrew-tap

Homebrew tap for [LIAM](https://github.com/protocortex/liam), bi-temporal memory for AI agents.
Apple Silicon macOS only, like LIAM itself.

## Install

```sh
brew tap protocortex/tap
brew install liam              # prebuilt binaries from the latest tagged release
brew install --HEAD liam       # builds liam's main branch from source with cargo
```

See [Trust the tap](#trust-the-tap) if Homebrew refuses to load the formula.

Both install `liamd` (the daemon) and `liam` (the CLI), built with the `local` and `llama`
features so embeddings and generation are real, not mock. The HEAD build compiles llama.cpp
through CMake and takes a long time on a cold build.

The stable formula points at the release archive
`liam-vX.Y.Z-aarch64-apple-darwin-netinstall.tar.gz` and its published sha256. Until a newer
tag is cut it is v0.1.1, which is older than main.

## Trust the tap

Recent Homebrew versions (checked on 7.0.12) refuse to load formulae from a tap you have not
trusted. Trust is stored in `~/.homebrew/trust.json`, or in `$XDG_CONFIG_HOME/homebrew/trust.json`
when that variable is set. Official taps are always trusted.

- `brew install protocortex/tap/liam` trusts only that formula. A later `brew upgrade liam` by short
  name then works. Without that, Homebrew stops with `Refusing to load formula ... from untrusted
  tap` and names the command to run.
- `brew tap protocortex/tap` alone does not trust anything. After it, `brew info liam` is refused
  until you run `brew trust --formula protocortex/tap/liam`.
- `brew trust protocortex/tap` trusts the whole tap, including formulae added later. The `--tap`
  flag is optional.
- `brew trust` lists what you trust. `brew untrust protocortex/tap` and
  `brew untrust --formula protocortex/tap/liam` remove an entry.

## After install

Install never downloads models (several gigabytes). The caveats Homebrew prints tell you to:

1. Create `~/.liam` and copy the config template into it without overwriting an existing file:
   `cp -n $(brew --prefix)/opt/liam/share/liam/liam.toml ~/.liam/liam.toml`
2. Fetch the models: `liam fetch-models --config ~/.liam/liam.toml`
3. Start the daemon with `brew services start liam`, or by hand with
   `liamd --config ~/.liam/liam.toml serve`
4. Point an MCP client at the proxy:
   `{ "command": "liamd", "args": ["--config", "/Users/YOU/.liam/liam.toml", "proxy"] }`

The brew service starts the daemon at load. The launchd job shipped in the LIAM repo starts it
on the first connection instead (socket activation), but Homebrew services cannot declare a
Unix socket, so the formula does not use that.

## Upgrade

```sh
brew update
brew upgrade liam
brew services restart liam     # if you run it as a service
```

`brew upgrade --fetch-HEAD liam` rebuilds a HEAD install from the latest main. Your
`~/.liam/liam.toml` is never touched. Compare it with the new template in
`$(brew --prefix)/opt/liam/share/liam/liam.toml` after an upgrade, and rerun `liam fetch-models`
if the model settings changed.

## Uninstall

```sh
brew services stop liam
brew uninstall liam
brew untap protocortex/tap
```

`~/.liam` (config, database, event log, cached models) is yours and stays. Delete it by hand if
you want the data gone.

## Maintainers

Do not edit the stable `url` or `sha256` by hand. A release of LIAM opens a pull request here that
rewrites them from the release's `SHA256SUMS` with `.github/scripts/bump-formula.sh`. See
[docs/release-automation.md](docs/release-automation.md) for the flow, the credentials it needs, and
how to run it by hand. The checks are in `.github/workflows/tests.yml` (syntax, the bump script,
and an install of the stable build on two macOS versions) and `.github/workflows/head.yml` (the
slow HEAD build).

## Security

See [SECURITY.md](SECURITY.md).
