#!/usr/bin/env bash
# Tests bump-formula.sh against release folders built here and read through
# DOWNLOAD_BASE, and latest-release.sh against a stub gh, so nothing touches
# the network.
# Usage: test-bump-formula.sh [--keep]
# With --keep, Formula/liam.rb is left as a bump to 9.0.0 writes it, so that a
# style check can run on it. Use it in a throwaway checkout only.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$root/.github/scripts/bump-formula.sh"
latest="$root/.github/scripts/latest-release.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
# check "name" command...: the command must succeed.
check() { local name="$1"; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }

# release VERSION [flags]: a release folder for liam vVERSION.
#   nosha256   leave out the per-asset .sha256 file
#   badsha256  write a .sha256 file that disagrees with SHA256SUMS
#   binary     write the SHA256SUMS line in binary mode ("<sha> *<name>")
#   noasset    leave the archive out of SHA256SUMS
#   badsum     write a malformed checksum
#   nosums     publish no SHA256SUMS at all
release() {
  local v="$1" flags=" ${*:2} " dir name sha
  dir="$work/rel-$v-${2:-plain}"
  name="liam-v${v}-aarch64-apple-darwin-netinstall.tar.gz"
  rm -rf "$dir"
  mkdir -p "$dir"
  printf 'archive %s\n' "$v" >"$dir/$name"
  sha="$(shasum -a 256 "$dir/$name" | cut -d' ' -f1)"
  if [[ "$flags" != *" nosums "* ]]; then
    if [[ "$flags" == *" noasset "* ]]; then
      printf '%s  other.tar.gz\n' "$sha" >"$dir/SHA256SUMS"
    elif [[ "$flags" == *" badsum "* ]]; then
      printf 'nothex  %s\n' "$name" >"$dir/SHA256SUMS"
    elif [[ "$flags" == *" binary "* ]]; then
      printf '%s *%s\n' "$sha" "$name" >"$dir/SHA256SUMS"
    else
      printf '%s  %s\n' "$sha" "$name" >"$dir/SHA256SUMS"
    fi
  fi
  if [[ "$flags" == *" badsha256 "* ]]; then
    printf '%064d  %s\n' 0 "$name" >"$dir/$name.sha256"
  elif [[ "$flags" != *" nosha256 "* ]]; then
    printf '%s  %s\n' "$sha" "$name" >"$dir/$name.sha256"
  fi
  printf '%s' "$dir"
}
sha_of() { shasum -a 256 "$1/liam-v$2-aarch64-apple-darwin-netinstall.tar.gz" | cut -d' ' -f1; }
# bump DIR VERSION FORMULA: run the script against a release folder.
bump() { DOWNLOAD_BASE="file://$1" bash "$script" "$2" "$3" >"$work/out" 2>"$work/err"; }
head_of() { awk '$0 == "  head do" { on = 1 } on { print } on && $0 == "  end" { exit }' "$1"; }
fresh() { cp "$root/Formula/liam.rb" "$1"; }

mkdir -p "$work/f"
f="$work/f/liam.rb"

# A normal bump rewrites the stable url and sha256 and nothing else.
fresh "$f"
dir="$(release 9.0.0)"
sha="$(sha_of "$dir" 9.0.0)"
ok=false
if bump "$dir" 9.0.0 "$f" \
  && grep -qxF "  url \"https://github.com/protocortex/liam/releases/download/v9.0.0/liam-v9.0.0-aarch64-apple-darwin-netinstall.tar.gz\"" "$f" \
  && grep -qxF "  sha256 \"${sha}\"" "$f" \
  && [[ "$(grep -c 'releases/download/v' "$f")" -eq 1 ]] \
  && ruby -c "$f" >/dev/null; then ok=true; fi
check "a bump rewrites the stable url and sha256" $ok

check "a bump leaves the head block byte for byte as it was" \
  test "$(head_of "$f")" = "$(head_of "$root/Formula/liam.rb")" -a -n "$(head_of "$f")"

# Everything outside the two lines is unchanged.
check "a bump changes exactly the url and sha256 lines" \
  test "$(diff "$root/Formula/liam.rb" "$f" | grep -c '^[<>]')" -eq 4

cp "$f" "$work/f/first.rb"
second_bump_is_a_noop() { bump "$dir" 9.0.0 "$f" && cmp -s "$f" "$work/f/first.rb"; }
check "a second bump of the same release changes nothing" second_bump_is_a_noop

dir="$(release 9.1.0)"
moves_on() { bump "$dir" 9.1.0 "$f" && grep -q "download/v9.1.0/liam-v9.1.0-" "$f" && ! grep -q "v9.0.0" "$f"; }
check "a bump from a bumped formula moves to the newer release" moves_on

# Layout and livecheck survive a bump.
check "a bump keeps the livecheck block" grep -q 'strategy :github_releases' "$f"

fresh "$f"
dir="$(release 9.2.0 nosha256)"
check "a release without a .sha256 file is accepted" bump "$dir" 9.2.0 "$f"
fresh "$f"
dir="$(release 9.2.1 binary)"
check "a binary mode SHA256SUMS line is accepted" bump "$dir" 9.2.1 "$f"

# Refusals leave the formula unchanged.
refuse() { # name dir version expected-error-text
  fresh "$f"
  if ! bump "$2" "$3" "$f" && grep -q "$4" "$work/err" && cmp -s "$f" "$root/Formula/liam.rb"; then
    pass "$1"
  else
    fail "$1"
  fi
}
refuse "a .sha256 file that disagrees is refused" "$(release 9.3.0 badsha256)" 9.3.0 'sha256 says'
refuse "a SHA256SUMS without the archive is refused" "$(release 9.3.1 noasset)" 9.3.1 'missing or malformed checksum'
refuse "a malformed checksum is refused" "$(release 9.3.2 badsum)" 9.3.2 'missing or malformed checksum'
refuse "a release without SHA256SUMS is refused" "$(release 9.3.3 nosums)" 9.3.3 'could not read SHA256SUMS'

good="$(release 9.4.0)"
for v in 1.2 v1.2.3 1.2.3-rc1 '1.2.3; rm -rf /' '1.2.3/../4' '' ' 1.2.3' '01.2.3 x'; do
  fresh "$f"
  if ! DOWNLOAD_BASE="file://$good" bash "$script" "$v" "$f" >/dev/null 2>"$work/err" \
    && cmp -s "$f" "$root/Formula/liam.rb"; then
    pass "version '${v}' is refused"
  else
    fail "version '${v}' is refused"
  fi
done

# A formula whose layout changed is refused rather than half rewritten.
sed 's|^  url "https://github.com/protocortex/liam/releases|  # url "https://github.com/protocortex/liam/releases|' "$root/Formula/liam.rb" >"$f"
cp "$f" "$work/f/nourl.rb"
if ! bump "$good" 9.4.0 "$f" && cmp -s "$f" "$work/f/nourl.rb"; then
  pass "a formula without a stable url is refused and left unchanged"
else
  fail "a formula without a stable url is refused and left unchanged"
fi
if ! bump "$good" 9.4.0 "$work/f/missing.rb"; then
  pass "a missing formula file is refused"
else
  fail "a missing formula file is refused"
fi

# latest-release.sh against a stub gh. GH_RELEASES is the release list as JSON,
# and GH_ASSETS_<tag with _> the asset names of one release.
mkdir -p "$work/bin"
cat >"$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
jq_filter=""; tag=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) [ "$2" = protocortex/liam ] || { echo "unexpected repo $2" >&2; exit 1; }; shift ;;
    --jq) jq_filter="$2"; shift ;;
    release|list|view|--json|--limit) ;;
    tagName,isDraft,isPrerelease|assets|100) ;;
    *) tag="$1" ;;
  esac
  shift
done
if [ -z "$tag" ]; then
  jq -r "$jq_filter" <<<"$GH_RELEASES"
else
  var="GH_ASSETS_${tag//./_}"
  printf '%s\n' ${!var:-}
fi
STUB
chmod +x "$work/bin/gh"
releases='[{"tagName":"v9.5.0","isDraft":true,"isPrerelease":false},
  {"tagName":"v9.4.0","isDraft":false,"isPrerelease":true},
  {"tagName":"v9.3.0","isDraft":false,"isPrerelease":false},
  {"tagName":"v9.2.0","isDraft":false,"isPrerelease":false},
  {"tagName":"v9.1.0","isDraft":false,"isPrerelease":false},
  {"tagName":"nightly","isDraft":false,"isPrerelease":false}]'
a() { printf 'liam-%s-aarch64-apple-darwin-netinstall.tar.gz\n' "$1"; }
lookup() { PATH="$work/bin:$PATH" GH_RELEASES="$releases" bash "$latest" 2>"$work/err"; }
assets() { printf '%s\n%s\n' "$(a "$1")" "${2:-}"; }
GH_ASSETS_v9_5_0="$(assets v9.5.0 SHA256SUMS)"
GH_ASSETS_v9_4_0="$(assets v9.4.0 SHA256SUMS)"
GH_ASSETS_v9_3_0="$(assets v9.3.0)"
GH_ASSETS_v9_2_0="$(assets v9.2.0 SHA256SUMS)"
GH_ASSETS_v9_1_0="$(assets v9.1.0 SHA256SUMS)"
export GH_ASSETS_v9_5_0 GH_ASSETS_v9_4_0 GH_ASSETS_v9_3_0 GH_ASSETS_v9_2_0 GH_ASSETS_v9_1_0
check "latest-release.sh skips drafts, prereleases and odd tags, and a release without SHA256SUMS" \
  test "$(lookup)" = "9.2.0"
GH_ASSETS_v9_2_0="SHA256SUMS"
GH_ASSETS_v9_1_0="$(assets v9.1.0)"
export GH_ASSETS_v9_2_0 GH_ASSETS_v9_1_0
check "latest-release.sh prints nothing when no release can be bumped" test -z "$(lookup)"

if [[ "${1:-}" = "--keep" ]]; then
  cp "$work/f/first.rb" "$root/Formula/liam.rb"
  printf 'Left Formula/liam.rb as a bump to 9.0.0 writes it, for the style check.\n'
fi

if [[ "$failures" -ne 0 ]]; then
  printf '%d failed\n' "$failures"
  exit 1
fi
printf 'all passed\n'
