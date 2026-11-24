# Design: Uptime Kuma macOS widget

Status: **v0.1.0 in development** (2026-11-24). The core package, menu bar app
and widget are built and tested against a mock of the Kuma API; not yet
checked against a real Kuma server or on the desktop over days. Written as a
plan on 2026-11-24 and kept current here; update it when the design changes.

## Why

No native macOS desktop widget for Uptime Kuma exists (checked 2026-11-24):

- KumaBar (paid, Mac App Store, macOS 26+) and
  `unicornops/uptime-kuma-notifier` (open source) are menu bar apps, not
  widgets.
- `mariogarridopt/xBar-Uptime-Kuma` is an xbar plugin for the menu bar.
- KumaAlert, Wuma and Uptime Kuma Manager have iPhone/iPad widgets. Since
  macOS 14 an iPhone's widgets can be placed on the Mac desktop, but they are
  built for the phone, and the iPhone has to be nearby.

## Product

**Kuma Status**: a sandboxed menu bar app with a WidgetKit extension. Read
only, no account, one status page.

## Data source

Uptime Kuma's public status page API, read from the 1.23 and 2.x server
source (`server/routers/status-page-router.js`, `server/model/*.js`):

- `GET /api/status-page/<slug>`: `config.title`, `publicGroupList[]` (`id`,
  `name`, `monitorList[]` with `id`, `name`, `type`), `incident` (1.x, single
  object or null) or `incidents[]` (2.x), `maintenanceList[]`. Unknown slug:
  HTTP 404 with `{"ok":false,"msg":...}`. Cached 5 min by the server.
- `GET /api/status-page/heartbeat/<slug>`: `heartbeatList` keyed by monitor id,
  up to 100 beats, **oldest first**, each `{status, time, msg:"", ping}`;
  `uptimeList` keyed `"<id>_24"`, 0...1. Cached **1 min** by the server.
- Status values: 0 down, 1 up, 2 pending, 3 maintenance.
- Times are UTC without a zone: `YYYY-MM-DD HH:mm:ss`, with `.SSS` in 2.x.

Why this and not the alternatives:

- Socket.IO (what Kuma's own dashboard uses) needs the admin login stored on
  the Mac, is not a documented API, and sees every monitor, which is more
  than a glanceable widget needs. Possible later as an option.
- `/metrics` (Prometheus) needs an API key and has no grouping or history.
- Push from Kuma (a webhook notification to the Mac) needs the Mac reachable
  from the server; a polling client works anywhere.

Limitation: only monitors on a published status page are visible. A private,
unshared page works for a personal dashboard.

## Refresh model

WidgetKit gives a widget a refresh budget (roughly every 15 min) and no
timer. The design splits the work:

- The **app** polls (`Poller`, an actor). Default 60 s, minimum 30 s
  (polling faster than Kuma's 60 s cache only repeats data). After a failure
  the wait doubles per further failure up to 10 min. Also polls on wake.
- Each result is saved as `SharedState` (last good snapshot, last error,
  last attempt) in `state.json` in the App Group container, written
  atomically.
- The app calls `WidgetCenter.reloadAllTimelines()` only when the result is
  **visibly different**: a monitor's status, the monitor set, the title,
  incident or maintenance, or the error state flipping. Ping and uptime drift
  do not trigger reloads.
- The **widget's** timeline has one entry per minute for 15 min (so "updated
  3 min ago" stays honest without reloads) plus one at the moment the data
  goes stale, then asks again. If the saved state is stale it fetches itself,
  which covers the app not running.
- Stale: last attempt failed, or the snapshot is older than
  max(3 × interval, 5 min). Stale data is dimmed, marked "Offline", and the
  background loses its status colour, so a dead server is never shown green.

## Structure

- `KumaKit` (Swift package, no UI): `KumaConfiguration` (parsing what a person
  types, URL building), `StatusPageAPI` (wire format, tolerant decoding),
  `StatusPageClient`, `Poller`, `SharedState`/`SharedStateStore`,
  `ConfigurationStore`, `Summary`. All tested with Swift Testing and a stub
  `URLProtocol`; no network.
- `KumaUI`: colours (Kuma's own), `StatusDot`, `HeartbeatBar`, `StatusBadge`,
  and `WidgetContent`, every widget layout. In the package rather than the
  extension so `kuma-render` and the app can draw it.
- `App/`: `AppModel` (poll loop, reload decisions), popover, settings.
- `Widget/`: `TimelineProvider` and the WidgetKit wrapper only.
- `project.yml`: XcodeGen; the project is generated, never committed.

## Signing and the App Group

The app and widget share `$(TeamIdentifierPrefix)io.github.dewab74.KumaStatus`.
On macOS a team-prefixed group needs no portal registration, so a free
personal team signs it. The group id reaches code through the `KumaAppGroup`
Info.plist key. An unsigned build (hooks, CI) has no container: the app falls
back to Application Support so it still runs, and the widget does not load.

Releases are cut locally (`scripts/release.sh`, as in launchbox-mqtt): the
signing identity stays on the developer's Mac, and CI builds unsigned in Debug
and Release only to prove the code compiles. The release zip is development
signed, not notarized; users approve the first open in Privacy & Security.
Not yet checked: that a development-signed build from one Mac runs, and its
widget loads, on another.

Contents of the group container are protected from other processes
(including Terminal) on current macOS, so debug builds take
`-KumaServer/-KumaSlug/-KumaInterval` launch arguments instead of
`defaults write`.

## Decisions

- **Plain HTTP allowed** (`NSAllowsArbitraryLoads`): homelab Kuma is often
  `http://` on a LAN name. The app only connects to the one address entered.
- **Click opens the status page** through `kumastatus://open`: a widget's URL
  goes to its containing app, which opens the configured page in the default
  browser (or Settings when nothing is configured).
- **One status page**. Several pages would need an App Intent configuration
  per widget; deferred until asked for.
- **No notifications** in v0.1: Kuma already notifies. A "notify on change"
  option is easy to add to `AppModel.receive`.

## Milestones

1. ✅ Repo and baseline (pre-commit, lint, secret scanning, CI backstop).
2. ✅ `KumaKit` with tests; API shape checked against Kuma's source.
3. ✅ Menu bar app and widget; signed build registers the widget; app polls
   a mock server end to end.
4. ☐ Verified against a real Kuma 1.23 and 2.x, and on the desktop for a day
   (reload timing, stale handling after sleep).
5. ☐ Optional: notifications on change, several pages, Socket.IO login mode.
