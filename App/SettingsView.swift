import KumaKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
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
        .frame(width: 460)
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
