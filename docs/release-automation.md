# Release automation

How the formula follows releases of `protocortex/liam`. Do not edit the stable `url` or `sha256` in
`Formula/liam.rb` by hand.

## Flow

1. A `vX.Y.Z` tag in `protocortex/liam` runs its `Release` workflow. After the soak gate, it builds
   the Apple Silicon archive and publishes it with a `.sha256` file and a `SHA256SUMS` file.
2. The same workflow downloads the published archive again and checks it against both files.
3. The `formulas` job there has no secrets. It checks out this repository, runs
   `.github/scripts/bump-formula.sh X.Y.Z`, and hands the changed formula to the next job as text.
4. The `downstream` job holds the token. It runs nothing from this repository. It opens the pull
   request `release/vX.Y.Z` here with that text, waits for the `tests` checks, and squash merges.
5. When the pull request merges, `.github/workflows/release-tag.yml` tags the merge commit `vX.Y.Z`
   and publishes a release listing the formula version.

`release-tag.yml` acts only on a merged pull request from the `igorjs[bot]` app, from a `release/v*`
branch in this repository, that changes only `Formula/*.rb`, with a merge commit on `main`. It
refuses to move an existing tag and uses only `GITHUB_TOKEN`.

This repository has no branch protection or ruleset, so the `downstream` job itself waits for the
checks before it merges. `head.yml` does not run on `release/v*` pull requests: the bump script
changes only the stable block and fails if the head block would differ.

## Credential

The `downstream` job needs a short-lived token that can write contents and pull requests in this
repository. It gets it from a GitHub App through `actions/create-github-app-token`, asking for only
this repository and only those two permissions.

| Where | Name | What |
|---|---|---|
| `protocortex` organization secret | `BOT_APP_CLIENT_ID` | Client ID of the GitHub App |
| `protocortex` organization secret | `BOT_APP_PRIVATE_KEY` | A private key of that App (PEM) |

The names were read from the organization on 2026-11-06 and are visible to all repositories. The
App installed there is `igorjs`. Its installation covers all repositories and can write contents and
pull requests, so the token request narrows it. If you replace it, create an App owned by
`protocortex` with repository permissions Contents: read and write, Pull requests: read and write
(Metadata read is implied), install it on this repository only, and store its Client ID and a
generated private key as the two secrets. The pull request author must stay `igorjs[bot]`, or
`release-tag.yml` ignores it. Change its `if` to the new App's login if you rename it.

A fine-grained personal access token would also work, but it is long lived, tied to a person, and
needs owner approval. A pull request opened with `GITHUB_TOKEN` does not start the `tests`
workflow, so that token is not an option here.

## Dry run

```sh
gh workflow run release.yml --repo protocortex/liam -f tag=vX.Y.Z -f dry_run=true
```

It plans, writes the formula change into the run summary, and opens nothing. It reads the real
`SHA256SUMS` of an existing release, or placeholders when the release has none.

## If a release stopped half way

Finish the tap step for a published release without rebuilding it:

```sh
gh workflow run release.yml --repo protocortex/liam -f tag=vX.Y.Z
```

To bump by hand, run `.github/scripts/bump-formula.sh X.Y.Z` in a checkout, and open the pull
request yourself. Nothing tags such a pull request, because `release-tag.yml` only trusts the App.

## Tests

`tests.yml` runs on every push to `main`, every pull request, weekly, and by hand:

- `syntax`: `brew test-bot --only-tap-syntax`.
- `bump-script`: `.github/scripts/test-bump-formula.sh`, then a style check of the formula it writes.
- `install`: `brew audit --strict --online`, `brew install`, `brew test` and `brew uninstall` on
  macOS 15 and 26, both Apple Silicon.
- `current`: scheduled runs only. Fails when a newer liam release exists and no `release/v*` pull
  request is open for it.

`head.yml` builds liam `main` from source (about 13 minutes). It runs for pull requests that touch
`Formula/**`, except `release/v*`, and on pushes to `main` that touch it, weekly, and by hand.
