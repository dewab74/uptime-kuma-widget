# Security policy

## Reporting a vulnerability

Please report security problems privately through
[GitHub private vulnerability reporting](https://github.com/dewab74/uptime-kuma-widget/security/advisories/new),
not in a public issue. Expect an acknowledgement within a week.

## What counts

- The app or widget connecting anywhere other than the Uptime Kuma address
  the user entered, or sending anything but `GET` requests to its public
  status page API.
- A crafted status page answer that makes the app or widget crash, hang, run
  code, or read or write files outside its sandbox containers.
- The sandbox, the hardened runtime, or the entitlements (outgoing network
  and the App Group only) being weakened.

Out of scope: the app allows plain `http://` (App Transport Security is
relaxed) because many Uptime Kuma servers run on a LAN without TLS. Use an
`https://` address when your server has one.

## Supported versions

Only the latest release is supported.
