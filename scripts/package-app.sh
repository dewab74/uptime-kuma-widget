#!/usr/bin/env bash
# Build the signed app and package it as a release zip with a SHA256 file.
#
#   scripts/package-app.sh [version]
#
# Needs Config/Signing.xcconfig (a widget only loads from a signed app). The
# zip is made with ditto, which keeps the code signature and extended
# attributes that a plain `zip` would break.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-0.0.0-dev}"
out="$root/artifacts"
app="$out/Kuma Status.app"
zip="$out/kuma-status-$version.zip"

rm -f "$zip" "$zip.sha256"
VERSION="$version" "$root/scripts/build.sh" --release

# Validate the output rather than trusting the exit code.
die() {
  echo "error: $*" >&2
  exit 1
}
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"; }
widget="$app/Contents/PlugIns/KumaStatusWidget.appex"
[[ -d $widget ]] || die "the widget extension is missing from the app"
[[ "$(plist "$app" CFBundleShortVersionString)" == "$version" ]] || die "the app is not stamped with version $version"
[[ "$(plist "$widget" CFBundleShortVersionString)" == "$version" ]] || die "the widget is not stamped with version $version"
codesign --verify --deep --strict "$app" || die "the code signature does not verify"
team="$(codesign -dv "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
[[ -n $team && $team != "not set" ]] || die "the app is not signed with a team"
codesign -d --entitlements - --xml "$widget" 2>/dev/null | grep -q "$team.io.github" \
  || die "the widget is not entitled to the $team App Group"

cp "$root/LICENSE" "$out/LICENSE.txt"
(cd "$out" && ditto -c -k --keepParent "Kuma Status.app" "$(basename "$zip")")
(cd "$out" && shasum -a 256 "$(basename "$zip")" >"$(basename "$zip").sha256")

echo "Packaged $zip (team $team)"
cat "$zip.sha256"
