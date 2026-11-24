#!/usr/bin/env bash
# Cut a release: tag vX.Y.Z and publish the signed app zip + SHA256 as a
# GitHub Release.
#
#   scripts/release.sh X.Y.Z --tested-with "macOS 15.2, Uptime Kuma 2.0.2" [--dry-run]
#
# Runs locally because the app must be signed with a developer identity,
# which is not put in CI (see docs/design.md, "Signing and the App Group").
# --tested-with is the macOS and Uptime Kuma versions you actually ran this
# build against; it goes into the release notes, so do not guess it.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

version=""
tested=""
dry_run=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tested-with)
      tested="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    *)
      version="$1"
      shift
      ;;
  esac
done

die() {
  echo "error: $*" >&2
  exit 1
}

[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || die "usage: $0 X.Y.Z --tested-with '<macOS and Kuma versions>' [--dry-run]"
[[ -n $tested ]] || die "--tested-with '<macOS and Kuma versions>' is required"
tag="v$version"

# ---- Preconditions --------------------------------------------------------
# A dry run may precede pushing the release commit, so these only warn there.
require() {
  if $dry_run; then
    echo "warning (dry run): $*" >&2
  else
    die "$*"
  fi
}
[[ "$(git rev-parse --abbrev-ref HEAD)" == main ]] || require "not on main"
[[ -z "$(git status --porcelain)" ]] || require "working tree is not clean"
git fetch --quiet origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || require "main is not in sync with origin/main"
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null || git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null; then
  die "tag $tag already exists"
fi

notes="$(awk -v v="$version" '
  $0 ~ "^## \\[" v "\\]" { on = 1; next }
  on && /^## \[/ { exit }
  on && /^\[[^]]+\]: / { next }
  on { print }
' CHANGELOG.md)"
[[ -n "${notes//[[:space:]]/}" ]] || die "CHANGELOG.md has no '## [$version]' section"

# ---- Build and verify -----------------------------------------------------
grep -q "^MARKETING_VERSION = $version\$" Config/Base.xcconfig \
  || require "Config/Base.xcconfig does not set MARKETING_VERSION = $version"
swift test --package-path Packages/KumaKit
scripts/package-app.sh "$version"
zip="artifacts/kuma-status-$version.zip"
(cd artifacts && shasum -a 256 -c "$(basename "$zip").sha256")

notes_file="artifacts/release-notes-$version.md"
{
  echo "$notes"
  echo
  echo "Tested with $tested."
  echo
  echo "Install: unzip, move \`Kuma Status.app\` to Applications and open it. The app is signed with a development certificate and not notarized, so macOS blocks the first open: choose System Settings > Privacy & Security > Open Anyway. Then add the widget from the desktop's Edit Widgets. See the [README](https://github.com/dewab74/uptime-kuma-widget#install)."
  echo
  echo "SHA256: \`$(cut -d' ' -f1 "$zip.sha256")\`"
} >"$notes_file"

if $dry_run; then
  echo "Dry run: would tag $tag at $(git rev-parse --short HEAD) and publish $zip with these notes:"
  cat "$notes_file"
  exit 0
fi

# ---- Publish --------------------------------------------------------------
git tag -a "$tag" -m "uptime-kuma-widget $version"
git push origin "$tag"
gh release create "$tag" "$zip" "$zip.sha256" --title "Kuma Status $version" --notes-file "$notes_file" --verify-tag

# Verify what was published, not what we meant to publish.
check="$(mktemp -d)"
gh release download "$tag" --dir "$check" --pattern "*.zip" --pattern "*.sha256"
(cd "$check" && shasum -a 256 -c "kuma-status-$version.zip.sha256")
cmp "$check/kuma-status-$version.zip" "$zip" || die "the downloaded asset differs from the local build"
rm -rf "$check"
echo "Released $tag: $(gh release view "$tag" --json url -q .url)"
