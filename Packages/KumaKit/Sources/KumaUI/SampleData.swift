import Foundation
import KumaKit

/// A plausible status page for previews and the widget gallery.
public enum SampleData {
    public static func snapshot(at date: Date = .now) -> StatusSnapshot {
        func monitor(
            _ id: Int, _ name: String, _ status: MonitorStatus, ping: Double, uptime: Double
        )
            -> MonitorSnapshot
        {
            var history = Array(repeating: MonitorStatus.up, count: MonitorSnapshot.historyLength)
            if status != .up {
                history.replaceSubrange((history.count - 3)..., with: [status, status, status])
            }
            return MonitorSnapshot(
                id: id, name: name, status: status, lastCheck: date, ping: ping, uptime24h: uptime, history: history)
        }
        return StatusSnapshot(
            title: "Home Lab",
            pageURL: URL(string: "https://status.example.com/status/home") ?? URL(fileURLWithPath: "/"),
            fetchedAt: date,
            groups: [
                GroupSnapshot(
                    id: 1, name: "Network",
                    monitors: [
                        monitor(1, "Router", .up, ping: 2, uptime: 1),
                        monitor(2, "Pi-hole", .up, ping: 11, uptime: 0.9998),
                    ]),
                GroupSnapshot(
                    id: 2, name: "Apps",
                    monitors: [
                        monitor(3, "Home Assistant", .up, ping: 48, uptime: 0.9991),
                        monitor(4, "Plex", .down, ping: 0, uptime: 0.962),
                        monitor(5, "Nextcloud", .up, ping: 120, uptime: 0.9995),
                        monitor(6, "Grafana", .up, ping: 35, uptime: 1),
                    ]),
            ])
    }
}
