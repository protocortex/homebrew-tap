#!/usr/bin/env bash
# Move the stable block of a formula to a liam release.
# Usage: bump-formula.sh <version-without-v> [formula-path]
#
# The url and sha256 come from the release's own SHA256SUMS. Nothing is
# hand-edited. Only the stable url and sha256 change. The head block, the
# livecheck block, the caveats and the tests are left as they are, and the
# script refuses to write when the head block would differ after the rewrite.
# If the release also publishes the per-asset .sha256 file, the two must agree.
#
# DOWNLOAD_BASE reads the checksums from another place, such as a file://
# folder in a local test. The formula url keeps the real release address.
set -euo pipefail

version="${1:?usage: bump-formula.sh <version> [formula-path]}"
formula="${2:-Formula/liam.rb}"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "::error::refusing unexpected version '${version}'" >&2
  exit 1
fi
if [[ ! -f "$formula" ]]; then
  echo "::error::${formula} does not exist" >&2
  exit 1
fi

tag="v${version}"
asset="liam-${tag}-aarch64-apple-darwin-netinstall.tar.gz"
base="https://github.com/protocortex/liam/releases/download/${tag}"
fetch_base="${DOWNLOAD_BASE:-$base}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL --retry 3 --retry-delay 5 -o "$tmp/SHA256SUMS" "${fetch_base}/SHA256SUMS" \
  || { echo "::error::could not read SHA256SUMS of ${tag}. Refusing to write." >&2; exit 1; }

# A line is "<sha256>  <name>", or "<sha256> *<name>" in binary mode.
sha="$(awk -v f="$asset" '{ n = $2; sub(/^\*/, "", n) } n == f { print $1 }' "$tmp/SHA256SUMS")"
if [[ ! "$sha" =~ ^[0-9a-f]{64}$ ]]; then
  echo "::error::missing or malformed checksum for ${asset} in ${tag} SHA256SUMS. Refusing to write." >&2
  exit 1
fi

# The per-asset .sha256 file is optional, but if it is there it must agree.
# curl -f turns a 404 into exit 22, which means "not published". Any other
# failure stops the script, so a network error cannot skip the check.
rc=0
curl -fsSL --retry 3 --retry-delay 5 -o "$tmp/asset.sha256" "${fetch_base}/${asset}.sha256" 2>/dev/null || rc=$?
if [[ "$rc" -eq 0 ]]; then
  other="$(cut -d' ' -f1 <"$tmp/asset.sha256")"
  if [[ "$other" != "$sha" ]]; then
    echo "::error::SHA256SUMS says ${sha} but ${asset}.sha256 says ${other}. Refusing to write." >&2
    exit 1
  fi
elif [[ "$rc" -ne 22 && "$rc" -ne 37 ]]; then
  echo "::error::could not read ${asset}.sha256 (curl exit ${rc}). Refusing to write." >&2
  exit 1
fi

# The head block, from "  head do" to its closing "  end".
head_block() { awk '$0 == "  head do" { on = 1 } on { print } on && $0 == "  end" { exit }' "$1"; }

# Rewrite the two-space-indented stable url, and the sha256 line after it.
# The head block's url is indented four spaces, so it never matches.
awk -v url="  url \"${base}/${asset}\"" -v sha="  sha256 \"${sha}\"" '
  /^  url "https:\/\/github\.com\/protocortex\/liam\/releases\/download\// && !seen_url { print url; seen_url = 1; want = 1; next }
  want && /^  sha256 "/ { print sha; want = 0; next }
  { print }
' "$formula" >"$tmp/new.rb"

stable_urls="$(grep -c "^  url \"${base}/${asset}\"\$" "$tmp/new.rb" || true)"
stable_shas="$(grep -c "^  sha256 \"${sha}\"\$" "$tmp/new.rb" || true)"
if [[ "$stable_urls" -ne 1 || "$stable_shas" -ne 1 ]]; then
  echo "::error::expected one stable url and one sha256 for ${tag}, found ${stable_urls} and ${stable_shas}. The formula layout changed. Refusing to write." >&2
  exit 1
fi
if [[ -z "$(head_block "$formula")" ]] || [[ "$(head_block "$formula")" != "$(head_block "$tmp/new.rb")" ]]; then
  echo "::error::the head block is missing or changed by the rewrite. Refusing to write." >&2
  exit 1
fi

cp "$tmp/new.rb" "$formula"
echo "${formula} now points at ${tag} (${sha})."
