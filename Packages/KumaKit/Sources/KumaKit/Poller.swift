import Foundation

/// Polls a status page on a schedule, keeps `SharedState` current in the
/// store, and reports each result, saying whether it changes what the widget
/// shows (the app then asks WidgetKit to redraw right away instead of waiting
/// for the widget's own, budgeted refresh).
public actor Poller {
    public typealias Fetch = @Sendable (KumaConfiguration) async throws(FetchError) -> StatusSnapshot
    public typealias Sleep = @Sendable (TimeInterval) async throws -> Void
    public typealias Report = @Sendable (_ state: SharedState, _ visiblyChanged: Bool) async -> Void

    /// Longest wait between attempts while the server keeps failing.
    public static let maximumBackoff: TimeInterval = 600

    private let store: SharedStateStore?
    private let fetch: Fetch
    private let sleep: Sleep
    private let now: @Sendable () -> Date
    private let report: Report
    private var state: SharedState?
    private var consecutiveFailures = 0

    public init(
        store: SharedStateStore?,
        fetch: @escaping Fetch,
        sleep: @escaping Sleep = { try await Task.sleep(for: .seconds($0)) },
        now: @escaping @Sendable () -> Date = { Date() },
        report: @escaping Report
    ) {
        self.store = store
        self.fetch = fetch
        self.sleep = sleep
        self.now = now
        self.report = report
        state = store?.load()
    }

    public var current: SharedState? { state }

    /// Wait before the next attempt: the poll interval, doubled for each
    /// failure after the first, up to `maximumBackoff`.
    public static func delay(interval: TimeInterval, consecutiveFailures failures: Int) -> TimeInterval {
        guard failures > 1 else { return interval }
        let factor = pow(2, Double(min(failures - 1, 16)))
        return min(interval * factor, max(interval, maximumBackoff))
    }

    /// Polls until the calling task is cancelled.
    public func run(_ configuration: KumaConfiguration) async {
        while !Task.isCancelled {
            await poll(configuration)
            let wait = Self.delay(interval: configuration.pollInterval, consecutiveFailures: consecutiveFailures)
            do { try await sleep(wait) } catch { return }
        }
    }

    /// One attempt. A failure keeps the last good snapshot and records why.
    @discardableResult
    public func poll(_ configuration: KumaConfiguration) async -> SharedState {
        let previous = state
        var next = previous ?? SharedState()
        // A snapshot from another page must not be shown as stale data for this one.
        if let old = next.snapshot, old.pageURL != configuration.statusPageURL { next.snapshot = nil }
        next.lastAttempt = now()
        do {
            next.snapshot = try await fetch(configuration)
            next.lastError = nil
            consecutiveFailures = 0
        } catch {
            next.lastError = error.errorDescription ?? "Unknown error"
            consecutiveFailures += 1
        }
        if Task.isCancelled { return next }
        state = next
        try? store?.save(next)
        await report(next, next.differsVisibly(from: previous))
        return next
    }

    /// Forgets everything, e.g. after the configuration is removed.
    public func reset() {
        state = nil
        consecutiveFailures = 0
        store?.clear()
    }
}
