import AppKit
import KumaKit
import Observation
import WidgetKit
import os

/// Owns the poll loop. Every result updates the menu, is saved for the
/// widget, and, when a monitor changed state, reloads the widget at once.
@MainActor @Observable
final class AppModel {
    private(set) var configuration: KumaConfiguration?
    private(set) var state: SharedState?
    private(set) var isRefreshing = false
    /// Which monitors the popover and the widget list (Settings › Display).
    private(set) var display: DisplayOptions

    @ObservationIgnored private let configurationStore = AppGroup.configurationStore
    @ObservationIgnored private var poller: Poller?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    static let log = Logger(subsystem: "io.github.dewab74.KumaStatus", category: "poll")

    init() {
        configuration = configurationStore.load()
        display = configurationStore.loadDisplay()
        #if DEBUG
            if let launch = DebugSupport.launchConfiguration {
                configurationStore.save(launch)
                configuration = launch
            }
        #endif
        let poller = Poller(
            store: Self.makeStateStore(),
            fetch: { configuration throws(FetchError) in try await StatusPageClient().fetch(configuration) },
            report: { [weak self] state, changed in await self?.receive(state, visiblyChanged: changed) })
        self.poller = poller
        Task { [weak self] in
            let saved = await poller.current
            self?.state = self?.state ?? saved
        }
        // After sleep or a network change the data is old; ask at once.
        let center = NSWorkspace.shared.notificationCenter
        observers.append(
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        start()
    }

    var isStale: Bool {
        guard let configuration else { return false }
        return state?.isStale(at: .now, limit: max(3 * configuration.pollInterval, 300)) ?? true
    }

    func apply(_ configuration: KumaConfiguration) {
        let pageChanged = configuration.statusPageURL != self.configuration?.statusPageURL
        configurationStore.save(configuration)
        self.configuration = configuration
        if pageChanged { state = nil }
        start()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func applyDisplay(_ options: DisplayOptions) {
        guard options != display else { return }
        display = options
        configurationStore.saveDisplay(options)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refresh() {
        guard let configuration, let poller, !isRefreshing else { return }
        isRefreshing = true
        Task {
            await poller.poll(configuration)
            isRefreshing = false
        }
    }

    func openStatusPage() {
        guard let url = configuration?.statusPageURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func start() {
        loop?.cancel()
        guard let configuration, let poller else { return }
        Self.log.info("Polling \(configuration.statusPageURL, privacy: .private) every \(configuration.pollInterval)s")
        loop = Task { await poller.run(configuration) }
    }

    private func receive(_ state: SharedState, visiblyChanged: Bool) {
        self.state = state
        if let error = state.lastError {
            Self.log.error("Poll failed: \(error, privacy: .public)")
        }
        if visiblyChanged {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// The App Group container, which the widget reads. An unsigned build has
    /// no App Group; it keeps its state in Application Support so the menu
    /// still works (the widget then fetches on its own).
    private static func makeStateStore() -> SharedStateStore? {
        if let store = AppGroup.stateStore { return store }
        Self.log.notice("No App Group container; the widget will not see the app's data")
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            .map { SharedStateStore(directory: $0.appending(path: "KumaStatus")) }
    }
}
