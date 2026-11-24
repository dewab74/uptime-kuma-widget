import Foundation

/// What the monitor lists show, set in the app's Display settings and shared
/// with the widget. Headlines and counts always cover every monitor; these
/// options only decide which monitors are listed.
public struct DisplayOptions: Codable, Sendable, Equatable {
    /// Statuses left out of the lists. Down monitors are always listed.
    public var hiddenStatuses: Set<MonitorStatus>

    public init(hiddenStatuses: Set<MonitorStatus> = []) {
        self.hiddenStatuses = hiddenStatuses.subtracting([.down])
    }

    public static let `default` = DisplayOptions()

    /// Statuses a person can choose to hide, in the order Settings lists them.
    public static let hideableStatuses: [MonitorStatus] = [.up, .pending, .maintenance, .unknown]

    public func shows(_ status: MonitorStatus) -> Bool {
        status == .down || !hiddenStatuses.contains(status)
    }

    public func shows(_ monitor: MonitorSnapshot) -> Bool { shows(monitor.status) }

    public var isFiltering: Bool { !hiddenStatuses.isEmpty }

    // Decoding goes through init so a stored "hide down" can never take effect.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(hiddenStatuses: try container.decodeIfPresent(Set<MonitorStatus>.self, forKey: .hiddenStatuses) ?? [])
    }
}

extension StatusSnapshot {
    /// Groups as the lists show them: filtered by `options`, groups with the
    /// worst problems first, and within a group the worst monitors first.
    /// Ties keep the status page's order. Empty groups are dropped.
    public func displayGroups(_ options: DisplayOptions = .default) -> [GroupSnapshot] {
        let filtered = groups.map { group in
            GroupSnapshot(
                id: group.id, name: group.name,
                monitors: Self.bySeverity(group.monitors.filter(options.shows)))
        }
        .filter { !$0.monitors.isEmpty }
        let worst = { (group: GroupSnapshot) in group.monitors.map(\.status.severity).max() ?? -1 }
        return filtered.enumerated()
            .sorted { lhs, rhs in
                worst(lhs.element) != worst(rhs.element)
                    ? worst(lhs.element) > worst(rhs.element) : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Every listed monitor once, worst first, then page order.
    public func displayMonitors(_ options: DisplayOptions = .default) -> [MonitorSnapshot] {
        monitorsByUrgency.filter(options.shows)
    }

    /// Monitors the options leave out of the lists, each once.
    public func filteredOut(_ options: DisplayOptions) -> [MonitorSnapshot] {
        monitors.filter { !options.shows($0) }
    }

    private static func bySeverity(_ monitors: [MonitorSnapshot]) -> [MonitorSnapshot] {
        monitors.enumerated()
            .sorted { lhs, rhs in
                lhs.element.status.severity != rhs.element.status.severity
                    ? lhs.element.status.severity > rhs.element.status.severity : lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
