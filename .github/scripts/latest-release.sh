#!/usr/bin/env bash
# Print the version (without the v) of the newest liam release that a bump can
# use: published, not a prerelease, tagged vX.Y.Z, and carrying both the
# netinstall archive and a SHA256SUMS file. Releases before SHA256SUMS existed
# are skipped, because bump-formula.sh needs it. Prints nothing when there is
# none. Only the five newest releases are checked for assets, which bounds the
# API calls of a scheduled run.
# Usage: latest-release.sh
set -euo pipefail

repo="protocortex/liam"
tags="$(gh release list --repo "$repo" --limit 100 --json tagName,isDraft,isPrerelease \
  --jq '.[] | select(.isDraft == false and .isPrerelease == false) | .tagName | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))')"

checked=0
while IFS= read -r tag; do
  [ -n "$tag" ] || continue
  checked=$((checked + 1))
  [ "$checked" -le 5 ] || break
  assets="$(gh release view "$tag" --repo "$repo" --json assets --jq '.assets[].name')"
  grep -qx "liam-${tag}-aarch64-apple-darwin-netinstall.tar.gz" <<<"$assets" || continue
  grep -qx 'SHA256SUMS' <<<"$assets" || continue
  printf '%s\n' "${tag#v}"
  exit 0
done <<<"$tags"
