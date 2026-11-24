import KumaKit
import KumaUI
import SwiftUI

/// The popover under the menu bar icon.
struct MenuContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.configuration == nil {
                welcome
            } else if let snapshot = model.state?.snapshot {
                header(snapshot)
                    .padding(14)
                if let notice = snapshot.incident ?? snapshot.maintenance.first {
                    Label(notice, systemImage: snapshot.incident != nil ? "exclamationmark.bubble.fill" : "wrench.fill")
                        .font(.caption)
                        .foregroundStyle(snapshot.incident != nil ? MonitorStatus.pending.color : .blue)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                }
                Divider()
                MonitorList(snapshot: snapshot)
                    .opacity(model.isStale ? 0.6 : 1)
            } else {
                waiting
            }
            Divider()
            footer
        }
        .frame(width: 340)
    }

    private func header(_ snapshot: StatusSnapshot) -> some View {
        let summary = snapshot.summary
        return HStack(spacing: 12) {
            StatusBadge(overall: summary.overall, size: 22, dimmed: model.isStale)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.title)
                    .font(.system(.headline, design: .rounded))
                Text(model.isStale ? "Out of date" : summary.headline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(summary.up)/\(summary.total) up")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var welcome: some View {
        VStack(spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("Mirror an Uptime Kuma status page")
                .font(.headline)
            Text("Enter your server and status page, then add the widget from the desktop's Edit Widgets.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Set Up…", action: showSettings)
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }

    private var waiting: some View {
        VStack(spacing: 8) {
            if let error = model.state?.lastError {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 26))
                    .foregroundStyle(MonitorStatus.down.color)
                Text("Can't reach the status page")
                    .font(.headline)
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView()
                Text("Loading…").foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                status(at: context.date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(model.state?.lastError ?? "")
            }
            Spacer()
            if model.configuration != nil {
                IconButton("arrow.clockwise", help: "Refresh now", spinning: model.isRefreshing) {
                    model.refresh()
                }
                IconButton("safari", help: "Open status page") { model.openStatusPage() }
            }
            IconButton("gearshape", help: "Settings…", action: showSettings)
            IconButton("power", help: "Quit Kuma Status") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private func status(at date: Date) -> some View {
        if let error = model.state?.lastError, model.state?.snapshot != nil {
            Label(error, systemImage: "exclamationmark.triangle.fill")
        } else if let fetchedAt = model.state?.snapshot?.fetchedAt {
            if date.timeIntervalSince(fetchedAt) < 60 {
                Text("Updated just now")
            } else {
                Text("Updated \(fetchedAt.formatted(.relative(presentation: .named)))")
            }
        }
    }

    private func showSettings() {
        NSApp.activate()
        openSettings()
    }
}

private struct MonitorList: View {
    let snapshot: StatusSnapshot

    var body: some View {
        let groups = snapshot.groups.filter { !$0.monitors.isEmpty }
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(groups) { group in
                    if groups.count > 1 {
                        Text(group.name.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                            .padding(.top, group.id == groups.first?.id ? 0 : 8)
                            .padding(.bottom, 2)
                    }
                    ForEach(group.monitors) { monitor in
                        MonitorRow(monitor: monitor)
                    }
                }
            }
            .padding(14)
        }
        .frame(maxHeight: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MonitorRow: View {
    let monitor: MonitorSnapshot

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(monitor.status, size: 8)
            Text(monitor.name)
                .fontWeight(monitor.status == .up ? .regular : .semibold)
                .foregroundStyle(monitor.status == .down ? monitor.status.color : .primary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 6)
            if let ping = Format.ping(monitor.ping), monitor.status == .up {
                Text(ping)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            HeartbeatBar(monitor.history, slots: 16, spacing: 1.5)
                .frame(width: 70, height: 12)
            Text(Format.uptime(monitor.uptime24h))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .help(help)
    }

    private var help: String {
        var parts = [monitor.status.label]
        if let lastCheck = monitor.lastCheck {
            parts.append("checked \(lastCheck.formatted(.relative(presentation: .named)))")
        }
        if let uptime = monitor.uptime24h { parts.append("\(Format.uptime(uptime)) over 24 h") }
        return parts.joined(separator: ", ")
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    var spinning = false
    let action: () -> Void

    init(_ symbol: String, help: String, spinning: Bool = false, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.spinning = spinning
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if spinning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: symbol)
                }
            }
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}
