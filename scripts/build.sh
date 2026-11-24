#!/usr/bin/env bash
# Generate the Xcode project from project.yml and build the app with its
# widget.
#
#   scripts/build.sh            Debug build, signed if Config/Signing.xcconfig exists
#   scripts/build.sh --release  Release build into artifacts/ (signed; see CONTRIBUTING.md)
#   scripts/build.sh --check    Unsigned Debug build, warnings as errors (pre-commit, CI)
#
# Output: build/ (DerivedData) and, for --release, artifacts/Kuma Status.app.

set -euo pipefail
cd "$(dirname "$0")/.."

mode=debug
case "${1:-}" in
  --release) mode=release ;;
  --check) mode=check ;;
  "") ;;
  *)
    echo "usage: $0 [--release|--check]" >&2
    exit 2
    ;;
esac

command -v xcodegen >/dev/null || {
  echo "XcodeGen is required: brew install xcodegen" >&2
  exit 1
}
xcodegen generate --quiet

args=(-project KumaStatus.xcodeproj -scheme KumaStatus -destination 'generic/platform=macOS'
  -derivedDataPath build -quiet)

case "$mode" in
  check)
    xcodebuild "${args[@]}" -configuration Debug \
      CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" build
    ;;
  debug)
    xcodebuild "${args[@]}" -configuration Debug -allowProvisioningUpdates build
    echo "Built: build/Build/Products/Debug/Kuma Status.app"
    ;;
  release)
    [[ -f Config/Signing.xcconfig ]] || {
      echo "Config/Signing.xcconfig is missing; a widget only loads from a signed app." >&2
      exit 1
    }
    xcodebuild "${args[@]}" -configuration Release -allowProvisioningUpdates build
    mkdir -p artifacts
    rm -rf "artifacts/Kuma Status.app"
    cp -R "build/Build/Products/Release/Kuma Status.app" artifacts/
    codesign --verify --deep --strict "artifacts/Kuma Status.app"
    echo "Built: artifacts/Kuma Status.app"
    ;;
esac
