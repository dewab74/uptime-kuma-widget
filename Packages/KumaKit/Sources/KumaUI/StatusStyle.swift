import KumaKit
import SwiftUI

/// Uptime Kuma's own status colours, so the widget reads like the status page.
extension MonitorStatus {
    public var color: Color {
        switch self {
        case .up: Color(red: 0.36, green: 0.87, blue: 0.55)  // #5CDD8B
        case .down: Color(red: 0.86, green: 0.21, blue: 0.27)  // #DC3545
        case .pending: Color(red: 0.97, green: 0.64, blue: 0.02)  // #F8A306
        case .maintenance: Color(red: 0.09, green: 0.28, blue: 0.96)  // #1747F5
        case .unknown: Color.secondary.opacity(0.35)
        }
    }

    public var symbol: String {
        switch self {
        case .up: "checkmark.circle.fill"
        case .down: "xmark.octagon.fill"
        case .pending: "clock.badge.exclamationmark.fill"
        case .maintenance: "wrench.and.screwdriver.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }
}

extension Summary.Overall {
    /// The status that stands for the page as a whole.
    public var representative: MonitorStatus {
        switch self {
        case .allUp: .up
        case .degraded: .pending
        case .partialOutage, .majorOutage: .down
        case .maintenance: .maintenance
        case .empty: .unknown
        }
    }

    public var symbol: String {
        switch self {
        case .allUp: "checkmark.circle.fill"
        case .degraded: "exclamationmark.circle.fill"
        case .partialOutage: "exclamationmark.triangle.fill"
        case .majorOutage: "xmark.octagon.fill"
        case .maintenance: "wrench.and.screwdriver.fill"
        case .empty: "circle.dashed"
        }
    }

    /// Template symbol for the menu bar, where colour is not used.
    public var menuBarSymbol: String {
        switch self {
        case .allUp: "checkmark.circle"
        case .degraded: "exclamationmark.circle"
        case .partialOutage: "exclamationmark.triangle.fill"
        case .majorOutage: "xmark.octagon.fill"
        case .maintenance: "wrench.and.screwdriver"
        case .empty: "circle.dashed"
        }
    }
}

/// A small filled circle with a soft halo, the list's status marker.
public struct StatusDot: View {
    let status: MonitorStatus
    var size: CGFloat

    public init(_ status: MonitorStatus, size: CGFloat = 8) {
        self.status = status
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
            .background(Circle().fill(status.color.opacity(0.25)).frame(width: size * 1.9, height: size * 1.9))
            .frame(width: size * 1.9, height: size * 1.9)
            .accessibilityLabel(status.label)
    }
}

/// Recent heartbeats as a row of rounded bars, newest on the right, like the
/// status page's beat bar. Pads on the left when there is less history.
public struct HeartbeatBar: View {
    let history: [MonitorStatus]
    let slots: Int
    var spacing: CGFloat

    public init(_ history: [MonitorStatus], slots: Int = 20, spacing: CGFloat = 1.5) {
        self.history = history
        self.slots = slots
        self.spacing = spacing
    }

    public var body: some View {
        let beats = Array(history.suffix(slots))
        let padding = slots - beats.count
        HStack(spacing: spacing) {
            ForEach(0..<slots, id: \.self) { index in
                let status = index < padding ? MonitorStatus.unknown : beats[index - padding]
                Capsule(style: .continuous)
                    .fill(index < padding ? Color.secondary.opacity(0.12) : status.color)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Recent checks")
        .accessibilityValue(beats.map(\.label).suffix(5).joined(separator: ", "))
    }
}

public enum Format {
    /// "99.95%", "100%", or an en dash when unknown.
    public static func uptime(_ value: Double?) -> String {
        guard let value else { return "–" }
        let percent = value * 100
        if percent >= 99.995 { return "100%" }
        return percent.formatted(.number.precision(.fractionLength(percent >= 99 ? 2 : 1))) + "%"
    }

    /// "42 ms", "1.2 s", or nil.
    public static func ping(_ value: Double?) -> String? {
        guard let value else { return nil }
        if value >= 1000 { return (value / 1000).formatted(.number.precision(.fractionLength(1))) + " s" }
        return "\(Int(value.rounded())) ms"
    }
}

/// The overall verdict as a white symbol on a solid, softly glowing disc.
public struct StatusBadge: View {
    let overall: Summary.Overall
    let size: CGFloat
    var dimmed: Bool

    public init(overall: Summary.Overall, size: CGFloat, dimmed: Bool = false) {
        self.overall = overall
        self.size = size
        self.dimmed = dimmed
    }

    public var body: some View {
        let color = dimmed ? Color.gray : overall.representative.color
        ZStack {
            Circle()
                .fill(color.gradient)
                .shadow(color: color.opacity(0.5), radius: size / 4)
            Image(systemName: dimmed ? "wifi.slash" : overall.badgeSymbol)
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size * 1.35, height: size * 1.35)
        .accessibilityElement()
        .accessibilityLabel(dimmed ? "Out of date" : overall.representative.label)
    }
}

extension Summary.Overall {
    /// Bare symbol drawn inside `StatusBadge`.
    public var badgeSymbol: String {
        switch self {
        case .allUp: "checkmark"
        case .degraded: "ellipsis"
        case .partialOutage, .majorOutage: "exclamationmark"
        case .maintenance: "wrench.and.screwdriver"
        case .empty: "minus"
        }
    }
}
