# protocortex/homebrew-tap

Homebrew tap for [LIAM](https://github.com/protocortex/liam), bi-temporal memory for AI agents.
Apple Silicon macOS only, like LIAM itself.

## Install

```sh
brew tap protocortex/tap
brew install liam              # prebuilt binaries from the latest tagged release
brew install --HEAD liam       # builds liam's main branch from source with cargo
```

Recent Homebrew versions refuse to load formulae from a tap you have not trusted. If you see
"Refusing to load formula ... from untrusted tap", run `brew trust protocortex/tap` and retry.

Both install `liamd` (the daemon) and `liam` (the CLI), built with the `local` and `llama`
features so embeddings and generation are real, not mock. The HEAD build compiles llama.cpp
through CMake and takes a long time on a cold build.

The stable formula points at the release archive
`liam-vX.Y.Z-aarch64-apple-darwin-netinstall.tar.gz` and its published sha256. Until a newer
tag is cut it is v0.1.1, which is older than main.

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

### CI

`.github/workflows/ci.yml` runs on macOS arm64: `brew style`, `brew audit --strict --online`,
`brew test-bot --only-tap-syntax`, then `brew install` plus `brew test` for the stable build and
for `--HEAD --build-from-source`.

### Automatic bump on a liam release

1. liam's `Homebrew bump` workflow runs after its `Release` workflow succeeds on a `vX.Y.Z` tag
   and sends a `repository_dispatch` (event type `liam-release`, payload `tag`) to this repo.
2. `.github/workflows/bump.yml` downloads the release archive and its `.sha256`, checks they
   agree, then runs `brew bump-formula-pr` to open a PR updating the url and sha256. CI runs on
   that PR. A daily schedule and a manual run (optional `tag` input) cover a missed dispatch.

Two secrets must be created by hand. They do not exist until someone makes them:

| Where | Secret name | Token | Permissions |
|---|---|---|---|
| `protocortex/liam` | `HOMEBREW_TAP_DISPATCH_TOKEN` | Fine-grained PAT, resource owner `protocortex`, only repository `protocortex/homebrew-tap` | Contents: Read and write (needed to call the repository dispatch API) |
| `protocortex/homebrew-tap` | `TAP_BUMP_TOKEN` | Fine-grained PAT, resource owner `protocortex`, only repository `protocortex/homebrew-tap` | Contents: Read and write, Pull requests: Read and write |

One PAT with all three permissions can back both secrets. A PAT is used rather than
`GITHUB_TOKEN` because pull requests opened with `GITHUB_TOKEN` do not start the CI workflow.
The organization must allow fine-grained PATs, and the owner may need to approve the token.
