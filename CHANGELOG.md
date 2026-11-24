# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-24

First release.

### Added

- **Kuma Status**, a menu bar app that mirrors an Uptime Kuma status page
  through its public API (no login). It polls every 30 s to 10 min, backs off
  exponentially up to 10 min while the server fails, and polls again on wake
  from sleep. The menu bar icon shows the overall state and the number of
  problems; its popover lists every monitor.
- A **WidgetKit widget** in small, medium and large sizes: overall verdict,
  heartbeat bars, 24-hour uptime, and a pinned incident or active
  maintenance, in light and dark. Data older than three poll intervals (at
  least 5 minutes) is dimmed and marked offline, so a dead server never shows
  green. Clicking it opens the status page.
- The app reloads the widget as soon as a monitor changes state; the widget
  fetches by itself when the app is not running.
- **Problems first** everywhere: groups with problems lead, and within a
  group monitors are ordered down, pending, no data, maintenance, up.
- **Settings › Connection**: the Kuma **URL** (a pasted status page link fills
  in the slug; a port such as `http://kuma.lan:3001` or `[fd00::5]:3001` is
  kept, and an invalid one is refused), the status page slug, the poll
  interval, open at login, and a connection test.
- **Verify TLS certificate** (on by default). Off, any certificate the
  configured host presents is accepted, for a Kuma with a self-signed or
  private-CA certificate; other hosts, such as a redirect target, are still
  checked. A certificate failure says so and points at the switch.
- **Settings › Display**: choose which statuses the lists show (Up, Pending,
  Maintenance, No data), with a **Problems Only** shortcut. Down monitors are
  always shown, and headlines and counts include every monitor. An emptied
  list says so ("All 100 up"); the widget counts what it hides ("100 up
  hidden").
- `kuma-render`, a development tool that renders the widget sizes to PNG from
  sample data or a live page (`--hide`, `--insecure`).
- CI builds Debug and Release and runs the tests; `scripts/release.sh`
  publishes a signed zip with its SHA256 and checks the upload.

[Unreleased]: https://github.com/dewab74/uptime-kuma-widget/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/dewab74/uptime-kuma-widget/releases/tag/v0.1.0
