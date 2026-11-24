import KumaKit
import KumaUI
import SwiftUI
import WidgetKit

@main
struct KumaStatusWidgetBundle: WidgetBundle {
    var body: some Widget {
        KumaStatusWidget()
    }
}

struct KumaStatusWidget: Widget {
    static let kind = "KumaStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: Provider()) { entry in
            StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Uptime Kuma")
        .description("Up and down at a glance, mirrored from your Uptime Kuma status page.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct StatusEntry: TimelineEntry {
    var date: Date
    var state: SharedState?
    var configured: Bool
    /// Age after which the data is shown as out of date.
    var staleLimit: TimeInterval
    /// Which monitors the lists show (the app's Display settings).
    var options: DisplayOptions = .default

}

/// WidgetKit hands over a non-Sendable completion handler; it is safe to call
/// from the task that produced the timeline.
private struct Completion<T>: @unchecked Sendable {
    let call: (T) -> Void
}

struct Provider: TimelineProvider {
    /// How long the widget waits before asking for a new timeline on its own.
    /// The menu bar app reloads it sooner whenever a status changes.
    static let refresh: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> StatusEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        if context.isPreview {
            completion(.preview)
            return
        }
        let configuration = AppGroup.configurationStore.load()
        completion(
            StatusEntry(
                date: .now, state: AppGroup.stateStore?.load(), configured: configuration != nil,
                staleLimit: Self.staleLimit(configuration), options: AppGroup.configurationStore.loadDisplay()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let done = Completion(call: completion)
        Task {
            done.call(await Self.timeline())
        }
    }

    static func staleLimit(_ configuration: KumaConfiguration?) -> TimeInterval {
        max(3 * (configuration?.pollInterval ?? KumaConfiguration.defaultPollInterval), 300)
    }

    /// Uses what the app saved. If the app is not running and that is out of
    /// date, fetches once itself (the widget may reach the network; WidgetKit
    /// limits how often it gets here).
    static func timeline() async -> Timeline<StatusEntry> {
        let configuration = AppGroup.configurationStore.load()
        let options = AppGroup.configurationStore.loadDisplay()
        let store = AppGroup.stateStore
        var state = store?.load()
        let limit = staleLimit(configuration)
        let now = Date.now

        if let configuration, state?.isStale(at: now, limit: limit) ?? true {
            let poller = Poller(
                store: store,
                fetch: { configuration throws(FetchError) in try await StatusPageClient().fetch(configuration) },
                report: { _, _ in })
            state = await poller.poll(configuration)
        }

        // One entry a minute keeps "updated 3 min ago" honest without reloads,
        // and an entry at the moment the data goes stale greys it out on time.
        var dates = stride(from: 0, through: refresh, by: 60).map { now.addingTimeInterval($0) }
        if let fetchedAt = state?.snapshot?.fetchedAt, fetchedAt.addingTimeInterval(limit) > now {
            dates.append(fetchedAt.addingTimeInterval(limit + 1))
            dates.sort()
        }
        let entries = dates.map {
            StatusEntry(
                date: $0, state: state, configured: configuration != nil, staleLimit: limit, options: options)
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(refresh)))
    }
}

extension StatusEntry {
    static let preview = StatusEntry(
        date: .now, state: SharedState(snapshot: SampleData.snapshot()), configured: true, staleLimit: 300)
}
