# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Settings › Display: choose which statuses the menu bar list and the widget
  show (Up, Pending, Maintenance, No data), with a **Problems Only** shortcut.
  Down monitors are always shown; headlines and counts still include every
  monitor. A list left empty by the filter says so ("All 100 up"), and the
  widget's last line counts what it hides ("100 up hidden").
- Problems first everywhere: groups with problems lead, and within a group
  monitors are ordered down, pending, no data, maintenance, up. Before, the
  large widget and the menu bar list kept the status page's order.
- `kuma-render --hide <statuses>` renders the widget as the Display settings
  would.
- **Verify TLS certificate** (on by default) in Settings › Connection. Off, any
  certificate the configured host presents is accepted, for a Kuma with a
  self-signed or private-CA certificate; other hosts, such as a redirect
  target, are still checked. A certificate failure now says so and points at
  the switch. Debug builds take `-KumaVerifyCertificate NO`; `kuma-render`
  takes `--insecure`.

### Changed

- Settings: the **Server** field is now **URL**, and its tab **Connection**. A
  port in the URL (`http://kuma.lan:3001`, `[fd00::5]:3001`) is kept for
  every request and for the status page link; a port outside 1–65535 or not
  a number is refused with a message saying so.

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
