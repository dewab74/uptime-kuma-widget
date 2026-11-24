# Contributing

Thanks for helping. Issues and pull requests are welcome.

## Setup

1. Install Xcode 16 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
   and [pre-commit](https://pre-commit.com/):

   ```bash
   brew install xcodegen pre-commit
   ```

2. Clone, then install the git hooks. Hooks live in `.git/hooks/`, which is not
   cloned, so this is needed once per clone:

   ```bash
   pre-commit install
   pre-commit run --all-files
   ```

3. Test and build:

   ```bash
   swift test --package-path Packages/KumaKit
   scripts/build.sh --check    # unsigned, warnings as errors
   ```

To run the app with its widget you need a signed build: copy
`Config/Signing.example.xcconfig` to `Config/Signing.xcconfig` (gitignored),
fill in your team id, and run `scripts/build.sh`. A free personal team works.
`scripts/build.sh` regenerates `KumaStatus.xcodeproj` from `project.yml` each
time; edit `project.yml`, never the generated project.

### Running against a test server

Debug builds accept the configuration as launch arguments, which skips the
Settings window (the App Group container cannot be written from outside the
app):

```bash
open "build/Build/Products/Debug/Kuma Status.app" --args \
  -KumaServer http://127.0.0.1:3001 -KumaSlug home -KumaInterval 30
```

`kuma-render` draws every widget size to PNG from sample data or a live page,
which is the quickest way to check a layout change:

```bash
swift run --package-path Packages/KumaKit kuma-render /tmp/widgets [server [slug]]
```

Logs: `log stream --predicate 'subsystem == "io.github.dewab74.KumaStatus"' --info`.

## Rules

- **Conventional Commits** (`feat: ...`, `fix: ...`, `docs: ...`). The
  commit-msg hook enforces it; the changelog is built from it.
- The hooks run `swift format lint --strict`, the KumaKit tests, an unsigned
  `xcodebuild` with warnings as errors, markdownlint, shellcheck, shfmt,
  gitleaks and detect-secrets. Do not bypass them with `--no-verify`. If a
  secret scanner fires on a real credential, rotate it.
- Formatting: `swift format --in-place --recursive App Widget Packages scripts`.
  `Packages/KumaKit/Tests/.swift-format` repeats the root settings (nested
  configs do not inherit) and only allows force unwraps in tests.
- Never commit `Config/Signing.xcconfig`, the generated `.xcodeproj`, or
  `build/` and `artifacts/` output.
- New behaviour comes with tests. Logic goes in `KumaKit`, where it can be
  tested without WidgetKit; the app and the widget stay thin.
- Update `CHANGELOG.md` under `[Unreleased]`.

## Releasing

There are no binary releases yet: a widget only loads from a signed app, and a
build that runs on other Macs needs a notarized Developer ID signature. Until
then a release is a tag:

1. Build with `scripts/build.sh --release`, install it, add the widget in all
   three sizes, and check it against a real Kuma: an outage shows within one
   poll interval, and stopping the server greys the widget out.
2. In `CHANGELOG.md`, rename `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD`, set
   `MARKETING_VERSION` in `Config/Base.xcconfig`, and commit
   (`chore(release): X.Y.Z`).
3. Tag `vX.Y.Z`, push it, and create the GitHub release from the changelog
   section.
