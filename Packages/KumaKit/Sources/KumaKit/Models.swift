import Foundation

/// A monitor's state, as Uptime Kuma numbers it in a heartbeat
/// (`0` down, `1` up, `2` pending, `3` maintenance).
public enum MonitorStatus: Int, Codable, Sendable, CaseIterable {
    case down = 0
    case up = 1
    case pending = 2
    case maintenance = 3
    /// No heartbeat yet, or a value this version does not know.
    case unknown = -1

    public init(kumaValue: Int?) {
        self = kumaValue.flatMap(MonitorStatus.init(rawValue:)) ?? .unknown
    }

    /// Worst first: the order a list of monitors is sorted in when problems lead.
    public var severity: Int {
        switch self {
        case .down: 4
        case .pending: 3
        case .unknown: 2
        case .maintenance: 1
        case .up: 0
        }
    }

    public var label: String {
        switch self {
        case .down: "Down"
        case .up: "Up"
        case .pending: "Pending"
        case .maintenance: "Maintenance"
        case .unknown: "No data"
        }
    }
}

/// One monitor on the status page, reduced to what the widget shows.
public struct MonitorSnapshot: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String
    public var status: MonitorStatus
    /// Time of the latest heartbeat.
    public var lastCheck: Date?
    /// Response time of the latest heartbeat, in milliseconds.
    public var ping: Double?
    /// 24-hour uptime, 0...1.
    public var uptime24h: Double?
    /// Most recent heartbeats, oldest first (at most `MonitorSnapshot.historyLength`).
    public var history: [MonitorStatus]

    public static let historyLength = 30

    public init(
        id: Int, name: String, status: MonitorStatus, lastCheck: Date? = nil, ping: Double? = nil,
        uptime24h: Double? = nil, history: [MonitorStatus] = []
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.lastCheck = lastCheck
        self.ping = ping
        self.uptime24h = uptime24h
        self.history = history
    }
}

public struct GroupSnapshot: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String
    public var monitors: [MonitorSnapshot]

    public init(id: Int, name: String, monitors: [MonitorSnapshot]) {
        self.id = id
        self.name = name
        self.monitors = monitors
    }
}

/// The whole status page at one moment.
public struct StatusSnapshot: Codable, Sendable, Equatable {
    public var title: String
    public var pageURL: URL
    public var fetchedAt: Date
    public var groups: [GroupSnapshot]
    /// Title of a pinned incident, if the page shows one.
    public var incident: String?
    /// Titles of maintenance windows active now.
    public var maintenance: [String]

    public init(
        title: String, pageURL: URL, fetchedAt: Date, groups: [GroupSnapshot], incident: String? = nil,
        maintenance: [String] = []
    ) {
        self.title = title
        self.pageURL = pageURL
        self.fetchedAt = fetchedAt
        self.groups = groups
        self.incident = incident
        self.maintenance = maintenance
    }

    /// Every monitor once, in page order. A monitor can sit in several groups.
    public var monitors: [MonitorSnapshot] {
        var seen = Set<Int>()
        return groups.flatMap(\.monitors).filter { seen.insert($0.id).inserted }
    }

    /// Monitors with problems first, then page order.
    public var monitorsByUrgency: [MonitorSnapshot] {
        monitors.enumerated()
            .sorted { lhs, rhs in
                lhs.element.status.severity != rhs.element.status.severity
                    ? lhs.element.status.severity > rhs.element.status.severity
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    public var summary: Summary { Summary(monitors: monitors) }

    /// What decides whether the widget must be redrawn now: the set of
    /// monitors and each one's state. Ping and uptime drift every poll and can
    /// wait for the widget's own schedule.
    public var statusSignature: [Int: MonitorStatus] {
        Dictionary(monitors.map { ($0.id, $0.status) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Counts and the overall verdict for a set of monitors.
public struct Summary: Sendable, Equatable {
    public enum Overall: Sendable, Equatable {
        case allUp
        /// Something is pending or has no data, nothing is down.
        case degraded
        /// At least one monitor is down, at least one is up.
        case partialOutage
        /// Every monitor that reports is down.
        case majorOutage
        case maintenance
        case empty
    }

    public var up = 0
    public var down = 0
    public var pending = 0
    public var maintenance = 0
    public var unknown = 0

    public init(monitors: [MonitorSnapshot]) {
        for monitor in monitors {
            switch monitor.status {
            case .up: up += 1
            case .down: down += 1
            case .pending: pending += 1
            case .maintenance: maintenance += 1
            case .unknown: unknown += 1
            }
        }
    }

    public var total: Int { up + down + pending + maintenance + unknown }

    /// Monitors that need attention.
    public var problems: Int { down + pending }

    public var overall: Overall {
        if total == 0 { return .empty }
        if down > 0 { return up + pending + maintenance > 0 ? .partialOutage : .majorOutage }
        if pending + unknown > 0 { return .degraded }
        if maintenance > 0 && up == 0 { return .maintenance }
        return .allUp
    }

    public var headline: String {
        switch overall {
        case .allUp: "All systems up"
        case .degraded: pending > 0 ? "\(pending) pending" : "\(unknown) without data"
        case .partialOutage, .majorOutage: "\(down) down"
        case .maintenance: "Maintenance"
        case .empty: "No monitors"
        }
    }
}
