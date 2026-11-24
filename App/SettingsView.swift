import KumaKit
import KumaUI
import ServiceManagement
import SwiftUI

/// The Settings window: where to read from, and what the lists show.
struct SettingsView: View {
    var body: some View {
        TabView {
            ServerSettings()
                .tabItem { Label("Server", systemImage: "server.rack") }
            DisplaySettings()
                .tabItem { Label("Display", systemImage: "line.3.horizontal.decrease.circle") }
        }
        .frame(width: 460)
    }
}

private struct ServerSettings: View {
    @Environment(AppModel.self) private var model

    @State private var address = ""
    @State private var slug = ""
    @State private var interval = KumaConfiguration.defaultPollInterval
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var test: TestResult?
    @State private var isTesting = false

    private enum TestResult {
        case success(String)
        case failure(String)
    }

    private static let intervals: [(String, TimeInterval)] = [
        ("30 seconds", 30), ("1 minute", 60), ("2 minutes", 120), ("5 minutes", 300), ("10 minutes", 600),
    ]

    var body: some View {
        Form {
            Section {
                TextField("Server", text: $address, prompt: Text("https://status.example.com"))
                TextField("Status page", text: $slug, prompt: Text("default"))
            } header: {
                Text("Uptime Kuma")
            } footer: {
                Text(
                    "The page's slug is the last part of its link, /status/<slug>. "
                        + "You can paste the whole status page link into Server. "
                        + "Only monitors on a published status page are shown."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Picker("Check every", selection: $interval) {
                    ForEach(Self.intervals, id: \.1) { Text($0.0).tag($0.1) }
                }
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            }

            Section {
                HStack {
                    resultView
                    Spacer()
                    Button("Test") { runTest() }
                        .disabled(address.isEmpty || isTesting)
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(address.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: load)
    }

    @ViewBuilder
    private var resultView: some View {
        if isTesting {
            ProgressView().controlSize(.small)
        } else if let test {
            switch test {
            case .success(let text):
                Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(MonitorStatus.up.colorForText)
            case .failure(let text):
                Label(text, systemImage: "xmark.circle.fill").foregroundStyle(.red)
            }
        }
    }

    private func load() {
        guard let configuration = model.configuration else { return }
        address = configuration.baseURL.absoluteString
        slug = configuration.slug
        interval = configuration.pollInterval
    }

    private func parsed() -> KumaConfiguration? {
        do {
            let configuration = try KumaConfiguration.parse(address: address, slug: slug, pollInterval: interval)
            address = configuration.baseURL.absoluteString
            slug = configuration.slug
            return configuration
        } catch {
            test = .failure(error.localizedDescription)
            return nil
        }
    }

    private func runTest() {
        guard let configuration = parsed() else { return }
        isTesting = true
        Task {
            do {
                let snapshot = try await StatusPageClient().fetch(configuration)
                let count = snapshot.monitors.count
                test = .success("\(snapshot.title): \(count) monitor\(count == 1 ? "" : "s")")
            } catch {
                test = .failure(error.localizedDescription)
            }
            isTesting = false
        }
    }

    private func save() {
        guard let configuration = parsed() else { return }
        model.apply(configuration)
        test = .success("Saved")
        NSApp.keyWindow?.close()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            test = .failure("Open at login: \(error.localizedDescription)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

extension MonitorStatus {
    /// Kuma's green is too light for text on a light background.
    fileprivate var colorForText: Color { Color(nsColor: .systemGreen) }
}

/// Which monitors the popover and the widget list. Applies at once.
private struct DisplaySettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Toggle(isOn: .constant(true)) { row(.down, note: "Always shown") }
                    .disabled(true)
                ForEach(DisplayOptions.hideableStatuses, id: \.self) { status in
                    Toggle(isOn: binding(for: status)) { row(status, note: nil) }
                }
            } header: {
                Text("Show in lists")
            } footer: {
                Text(
                    "Applies to the menu bar list and the widget. Problems are always listed first. "
                        + "Headlines and counts still include every monitor."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Problems Only") {
                        model.applyDisplay(DisplayOptions(hiddenStatuses: [.up, .maintenance]))
                    }
                    Button("Show All") { model.applyDisplay(.default) }
                        .disabled(!model.display.isFiltering)
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ status: MonitorStatus, note: String?) -> some View {
        HStack(spacing: 8) {
            StatusDot(status, size: 8)
            Text(status.label)
            if let note {
                Text(note).foregroundStyle(.secondary)
            }
        }
    }

    private func binding(for status: MonitorStatus) -> Binding<Bool> {
        Binding(
            get: { model.display.shows(status) },
            set: { show in
                var options = model.display
                if show {
                    options.hiddenStatuses.remove(status)
                } else {
                    options.hiddenStatuses.insert(status)
                }
                model.applyDisplay(options)
            })
    }
}
