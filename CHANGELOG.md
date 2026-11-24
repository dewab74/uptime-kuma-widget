# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Kuma Status, a menu bar app that polls an Uptime Kuma status page (public
  API, no login) every 30 s to 10 min, with exponential backoff up
  to 10 min while the server fails, and a refresh on wake from sleep.
- A WidgetKit widget in small, medium and large sizes: overall verdict,
  problem monitors first, heartbeat bars, 24-hour uptime, pinned incident or
  maintenance, light and dark. Data older than three poll intervals (at least
  5 minutes) is dimmed and marked offline.
- The app reloads the widget as soon as a monitor changes state; the widget
  fetches by itself when the app is not running.
- Settings: server address (a pasted status page link fills in the slug),
  slug, interval, open at login, and a connection test.
- `kuma-render`, a development tool that renders the widget sizes to PNG.
- CI builds Debug and Release and runs the tests; `scripts/release.sh`
  publishes a signed zip with its SHA256 and checks the upload.
