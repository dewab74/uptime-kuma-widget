import KumaKit
import SwiftUI
import WidgetKit

/// The widget's sizes, named here so the app can render them too.
public enum WidgetSize: CaseIterable, Sendable {
    case small, medium, large

    /// Point size of each family on macOS, for rendering outside WidgetKit.
    public var pointSize: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        }
    }
}

/// Everything the widget draws inside its container. WidgetKit supplies the
/// margins and the background (`WidgetBackground`); the widget extension
/// only wraps this.
public struct WidgetContent: View {
    let state: SharedState?
    let configured: Bool
    let date: Date
    let isStale: Bool
    let size: WidgetSize

    public init(state: SharedState?, configured: Bool, date: Date, staleLimit: TimeInterval, size: WidgetSize) {
        self.state = state
        self.configured = configured
        self.date = date
        self.isStale = state?.isStale(at: date, limit: staleLimit) ?? true
        self.size = size
    }

    /// The colour the background is washed with.
    public var backgroundStatus: MonitorStatus {
        guard let snapshot = state?.snapshot, !isStale else { return .unknown }
        return snapshot.summary.overall.representative
    }

    public var body: some View {
        if let snapshot = state?.snapshot {
            let footer = Footer(date: date, fetchedAt: snapshot.fetchedAt, isStale: isStale)
            Group {
                switch size {
                case .small: SmallView(snapshot: snapshot, footer: footer)
                case .medium: MediumView(snapshot: snapshot, footer: footer)
                case .large: LargeView(snapshot: snapshot, footer: footer)
                }
            }
            .opacity(isStale ? 0.55 : 1)
        } else {
            EmptyStateView(configured: configured, error: state?.lastError)
        }
    }
}

// MARK: - Families

private struct SmallView: View {
    let snapshot: StatusSnapshot
    let footer: Footer

    var body: some View {
        let summary = snapshot.summary
        let overall = summary.overall
        VStack(alignment: .leading, spacing: 0) {
            PageTitle(snapshot.title)
            Spacer(minLength: 6)
            StatusGlyph(overall: overall, size: 30)
            Spacer(minLength: 6)
            Text(summary.headline)
                .font(.system(.headline, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let worst = snapshot.monitorsByUrgency.first, worst.status == .down || worst.status == .pending {
                Text(names(with: worst.status))
                    .font(.caption)
                    .foregroundStyle(worst.status.color)
                    .lineLimit(1)
            } else {
                Text("\(summary.up) of \(summary.total) monitors")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func names(with status: MonitorStatus) -> String {
        snapshot.monitors.filter { $0.status == status }
            .map(\.name).formatted(.list(type: .and, width: .narrow))
    }
}

private struct MediumView: View {
    let snapshot: StatusSnapshot
    let footer: Footer

    var body: some View {
        let summary = snapshot.summary
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                PageTitle(snapshot.title)
                Spacer(minLength: 4)
                StatusGlyph(overall: summary.overall, size: 28)
                Spacer(minLength: 4)
                Text(summary.headline)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Counts(summary: summary)
                Spacer(minLength: 4)
                footer
            }
            .frame(width: 118, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                let rows = snapshot.monitorsByUrgency
                ForEach(rows.prefix(rows.count > 5 ? 4 : 5)) { monitor in
                    MonitorRow(monitor: monitor, slots: 12, showUptime: false)
                }
                if rows.count > 5 {
                    MoreLabel(hidden: Array(rows.dropFirst(4)))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct LargeView: View {
    let snapshot: StatusSnapshot
    let footer: Footer

    /// Rows that fit under the header, counting a group heading as a row.
    private let capacity = 12

    var body: some View {
        let summary = snapshot.summary
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                StatusGlyph(overall: summary.overall, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.title)
                        .font(.system(.headline, design: .rounded))
                        .lineLimit(1)
                    Text(summary.headline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Counts(summary: summary)
            }
            if let notice = snapshot.incident ?? snapshot.maintenance.first {
                Notice(text: notice, isIncident: snapshot.incident != nil)
            }
            VStack(alignment: .leading, spacing: 6) {
                let layout = rows(capacity: capacity - (snapshot.incident ?? snapshot.maintenance.first == nil ? 0 : 2))
                ForEach(layout.items, id: \.id) { item in
                    switch item.kind {
                    case .group(let name):
                        Text(name.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                            .padding(.top, item.id == layout.items.first?.id ? 0 : 3)
                    case .monitor(let monitor):
                        MonitorRow(monitor: monitor, slots: 24, showUptime: true)
                    }
                }
                if !layout.hidden.isEmpty {
                    MoreLabel(hidden: layout.hidden)
                }
            }
            Spacer(minLength: 0)
            footer
        }
    }

    private struct Item {
        enum Kind {
            case group(String)
            case monitor(MonitorSnapshot)
        }
        var id: String
        var kind: Kind
    }

    /// Group headings and monitors in page order. When everything does not
    /// fit, problem monitors are kept and healthy ones are dropped first.
    private func rows(capacity: Int) -> (items: [Item], hidden: [MonitorSnapshot]) {
        let groups = snapshot.groups.filter { !$0.monitors.isEmpty }
        let all = groups.flatMap(\.monitors)
        let showHeadings = groups.count > 1
        func build(keeping keep: Set<String>?) -> [Item] {
            var items: [Item] = []
            for group in groups {
                let monitors = group.monitors.filter { keep?.contains("\(group.id)-\($0.id)") ?? true }
                guard !monitors.isEmpty else { continue }
                if showHeadings { items.append(Item(id: "g\(group.id)", kind: .group(group.name))) }
                items += monitors.map { Item(id: "\(group.id)-\($0.id)", kind: .monitor($0)) }
            }
            return items
        }
        let full = build(keeping: nil)
        if full.count <= capacity { return (full, []) }

        // Rank every (group, monitor) by urgency and keep as many as fit,
        // leaving room for headings and the "more" line.
        let ranked = groups.flatMap { group in group.monitors.map { (group.id, $0) } }
            .enumerated()
            .sorted {
                $0.element.1.status.severity != $1.element.1.status.severity
                    ? $0.element.1.status.severity > $1.element.1.status.severity : $0.offset < $1.offset
            }
            .map { "\($0.element.0)-\($0.element.1.id)" }
        var keep = Set<String>()
        var items: [Item] = []
        for key in ranked {
            var candidate = keep
            candidate.insert(key)
            let built = build(keeping: candidate)
            if built.count > capacity - 1 { break }
            keep = candidate
            items = built
        }
        let shown = Set(
            items.compactMap { item -> Int? in
                if case .monitor(let monitor) = item.kind { return monitor.id }
                return nil
            })
        var seen = Set<Int>()
        let hidden = all.filter { !shown.contains($0.id) && seen.insert($0.id).inserted }
        return (items, hidden)
    }
}

// MARK: - Pieces

private struct PageTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private struct StatusGlyph: View {
    let overall: Summary.Overall
    let size: CGFloat

    var body: some View {
        StatusBadge(overall: overall, size: size)
            .widgetAccentable()
    }
}

private struct Counts: View {
    let summary: Summary

    var body: some View {
        HStack(spacing: 8) {
            count(summary.up, .up)
            if summary.down > 0 { count(summary.down, .down) }
            if summary.pending > 0 { count(summary.pending, .pending) }
            if summary.maintenance > 0 { count(summary.maintenance, .maintenance) }
        }
        .font(.caption.monospacedDigit())
        .padding(.top, 2)
    }

    private func count(_ value: Int, _ status: MonitorStatus) -> some View {
        HStack(spacing: 3) {
            Circle().fill(status.color).frame(width: 6, height: 6)
            Text("\(value)").foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(status.label)")
    }
}

private struct MonitorRow: View {
    let monitor: MonitorSnapshot
    let slots: Int
    let showUptime: Bool

    var body: some View {
        HStack(spacing: 7) {
            StatusDot(monitor.status, size: 7)
            Text(monitor.name)
                .font(.system(size: 12, weight: monitor.status == .up ? .regular : .semibold))
                .foregroundStyle(monitor.status == .down ? monitor.status.color : .primary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 4)
            HeartbeatBar(monitor.history, slots: slots, spacing: 1.5)
                .frame(width: CGFloat(slots) * 4.2, height: 11)
            if showUptime {
                Text(Format.uptime(monitor.uptime24h))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}

private struct MoreLabel: View {
    let hidden: [MonitorSnapshot]

    var body: some View {
        Text(hidden.allSatisfy { $0.status == .up } ? "+\(hidden.count) more, all up" : "+\(hidden.count) more")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

private struct Notice: View {
    let text: String
    let isIncident: Bool

    var body: some View {
        Label(text, systemImage: isIncident ? "exclamationmark.bubble.fill" : "wrench.and.screwdriver.fill")
            .font(.caption)
            .lineLimit(1)
            .foregroundStyle(isIncident ? MonitorStatus.pending.color : MonitorStatus.maintenance.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct Footer: View {
    let date: Date
    let fetchedAt: Date
    let isStale: Bool

    var body: some View {
        HStack(spacing: 4) {
            if isStale {
                Image(systemName: "wifi.slash")
                Text("Offline · \(age)")
            } else {
                Text("Updated \(age)")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var age: String {
        if date.timeIntervalSince(fetchedAt) < 60 { return "just now" }
        return fetchedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}

private struct EmptyStateView: View {
    let configured: Bool
    let error: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: configured ? "wifi.exclamationmark" : "gauge.with.dots.needle.67percent")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.secondary)
            Text(configured ? "Can't reach Uptime Kuma" : "Set up Kuma Status")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .multilineTextAlignment(.center)
            Text(configured ? (error ?? "Waiting for the first update.") : "Click to choose a status page.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A quiet wash of the overall colour over the system background.
public struct WidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let status: MonitorStatus

    public init(status: MonitorStatus) {
        self.status = status
    }

    public var body: some View {
        ZStack {
            Rectangle().fill(.background)
            RadialGradient(
                colors: [status.color.opacity(colorScheme == .dark ? 0.28 : 0.18), .clear],
                center: .topLeading, startRadius: 0, endRadius: 260)
        }
    }
}
