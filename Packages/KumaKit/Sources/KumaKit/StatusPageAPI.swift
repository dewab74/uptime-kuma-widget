import Foundation

/// Wire format of Uptime Kuma's public status page API (1.23 and 2.x).
///
/// Only the fields the widget uses are decoded, and every one that is not
/// needed to place a monitor is optional, so a server that adds or drops a
/// field does not break decoding.
enum StatusPageAPI {
    /// `GET /api/status-page/<slug>`: page config, groups and their monitors.
    struct Page: Decodable {
        struct Config: Decodable {
            var title: String?
        }

        struct Group: Decodable {
            var id: Int
            var name: String?
            var monitorList: [Monitor]?
        }

        struct Monitor: Decodable {
            var id: Int
            var name: String?
        }

        struct Incident: Decodable {
            var title: String?
        }

        struct Maintenance: Decodable {
            var title: String?
        }

        var config: Config?
        var publicGroupList: [Group]?
        /// 1.x: one pinned incident or null.
        var incident: Incident?
        /// 2.x: every pinned incident.
        var incidents: [Incident]?
        var maintenanceList: [Maintenance]?
    }

    /// `GET /api/status-page/heartbeat/<slug>`: recent heartbeats (oldest
    /// first, up to 100) and 24 h uptime per monitor. The server caches this
    /// for one minute, so polling faster than that only returns the same data.
    struct Heartbeats: Decodable {
        struct Beat: Decodable {
            var status: Int?
            var time: String?
            var ping: Double?
        }

        var heartbeatList: [String: [Beat]]?
        /// Keyed `"<monitor id>_24"`.
        var uptimeList: [String: Double]?
    }

    /// Kuma writes heartbeat times in UTC without a zone: `2026-11-24 09:30:00`
    /// in 1.x, with milliseconds in 2.x. ISO 8601 is accepted too.
    static func parseTime(_ text: String?) -> Date? {
        guard var text, !text.isEmpty else { return nil }
        if let date = try? Date(text, strategy: .iso8601) { return date }
        text = text.replacingOccurrences(of: " ", with: "T")
        if !text.hasSuffix("Z") { text += "Z" }
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return (try? fractional.parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text))
    }

    static func makeSnapshot(page: Page, beats: Heartbeats, pageURL: URL, fetchedAt: Date) -> StatusSnapshot {
        let groups = (page.publicGroupList ?? []).map { group in
            GroupSnapshot(
                id: group.id,
                name: group.name ?? "",
                monitors: (group.monitorList ?? []).map { monitor in
                    let list = beats.heartbeatList?[String(monitor.id)] ?? []
                    let last = list.last
                    return MonitorSnapshot(
                        id: monitor.id,
                        name: monitor.name ?? "Monitor \(monitor.id)",
                        status: MonitorStatus(kumaValue: last?.status),
                        lastCheck: parseTime(last?.time),
                        ping: last?.ping,
                        uptime24h: beats.uptimeList?["\(monitor.id)_24"],
                        history: list.suffix(MonitorSnapshot.historyLength).map { MonitorStatus(kumaValue: $0.status) }
                    )
                }
            )
        }
        let incident = (page.incidents?.first ?? page.incident)?.title
        return StatusSnapshot(
            title: page.config?.title ?? "Status",
            pageURL: pageURL,
            fetchedAt: fetchedAt,
            groups: groups,
            incident: incident,
            maintenance: (page.maintenanceList ?? []).compactMap(\.title)
        )
    }
}
