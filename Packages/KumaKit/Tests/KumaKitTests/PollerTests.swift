import Foundation
import Testing

@testable import KumaKit

/// Hands out scripted fetch results in order and records reports.
actor Script {
    var results: [Result<StatusSnapshot, FetchError>]
    var reports: [(SharedState, Bool)] = []
    var sleeps: [TimeInterval] = []

    init(_ results: [Result<StatusSnapshot, FetchError>]) { self.results = results }

    func next() throws(FetchError) -> StatusSnapshot {
        guard !results.isEmpty else { throw .transport("script exhausted") }
        return try results.removeFirst().get()
    }

    func record(_ state: SharedState, _ changed: Bool) { reports.append((state, changed)) }
    func slept(_ seconds: TimeInterval) { sleeps.append(seconds) }
}

@Suite struct PollerTests {
    let configuration = KumaConfiguration(baseURL: URL(string: "https://kuma.test")!, slug: "home")
    let clock = Date(timeIntervalSince1970: 1_800_000_000)

    func snapshot(_ statuses: [MonitorStatus], pingBase: Double = 1) -> StatusSnapshot {
        let monitors = statuses.enumerated().map {
            MonitorSnapshot(
                id: $0.offset, name: "m\($0.offset)", status: $0.element, ping: pingBase + Double($0.offset))
        }
        return StatusSnapshot(
            title: "Lab", pageURL: configuration.statusPageURL, fetchedAt: clock,
            groups: [GroupSnapshot(id: 1, name: "g", monitors: monitors)])
    }

    func makePoller(_ script: Script, store: SharedStateStore? = nil) -> Poller {
        let clock = clock
        return Poller(
            store: store,
            fetch: { _ throws(FetchError) in try await script.next() },
            sleep: { await script.slept($0) },
            now: { clock },
            report: { await script.record($0, $1) })
    }

    @Test func reportsAVisibleChangeOnlyWhenAStatusChanges() async {
        let script = Script([
            .success(snapshot([.up, .up])),
            .success(snapshot([.up, .up], pingBase: 40)),  // ping drift only
            .success(snapshot([.up, .down])),
        ])
        let poller = makePoller(script)

        for _ in 0..<3 { await poller.poll(configuration) }

        let changed = await script.reports.map(\.1)
        #expect(changed == [true, false, true])
    }

    @Test func keepsTheLastGoodSnapshotThroughAFailure() async {
        let script = Script([.success(snapshot([.up])), .failure(.http(status: 502)), .success(snapshot([.up]))])
        let poller = makePoller(script)

        await poller.poll(configuration)
        let failed = await poller.poll(configuration)
        #expect(failed.snapshot?.monitors.first?.status == .up)
        #expect(failed.lastError == "The server answered HTTP 502.")
        #expect(failed.isStale(at: clock, limit: 300))

        let recovered = await poller.poll(configuration)
        #expect(recovered.lastError == nil)
        #expect(!recovered.isStale(at: clock, limit: 300))
        // Going unreachable and coming back are both visible.
        #expect(await script.reports.map(\.1) == [true, true, true])
    }

    @Test func dropsASnapshotOfAnotherPage() async {
        let script = Script([.success(snapshot([.up])), .failure(.transport("offline"))])
        let poller = makePoller(script)
        await poller.poll(configuration)

        let other = KumaConfiguration(baseURL: URL(string: "https://other.test")!, slug: "home")
        let state = await poller.poll(other)

        #expect(state.snapshot == nil)
        #expect(state.lastError == "offline")
    }

    @Test func persistsStateForTheWidget() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SharedStateStore(directory: directory)
        let script = Script([.success(snapshot([.up, .pending]))])

        await makePoller(script, store: store).poll(configuration)

        let loaded = try #require(store.load())
        #expect(loaded.snapshot == snapshot([.up, .pending]))
        #expect(loaded.lastAttempt == clock)
        // A new poller (an app restart) starts from what is on disk.
        let restarted = makePoller(Script([]), store: store)
        #expect(await restarted.current == loaded)
    }

    @Test func backsOffWhileFailing() {
        #expect(Poller.delay(interval: 60, consecutiveFailures: 0) == 60)
        #expect(Poller.delay(interval: 60, consecutiveFailures: 1) == 60)
        #expect(Poller.delay(interval: 60, consecutiveFailures: 2) == 120)
        #expect(Poller.delay(interval: 60, consecutiveFailures: 3) == 240)
        #expect(Poller.delay(interval: 60, consecutiveFailures: 5) == 600)
        #expect(Poller.delay(interval: 60, consecutiveFailures: 500) == 600)
        // An interval above the cap is never shortened.
        #expect(Poller.delay(interval: 900, consecutiveFailures: 3) == 900)
    }

    @Test func runSleepsBetweenPollsAndStopsWhenCancelled() async {
        let script = Script([.success(snapshot([.up])), .failure(.notKuma), .failure(.notKuma)])
        let poller = makePoller(script)
        let task = Task { await poller.run(configuration) }
        while await script.reports.count < 3 { await Task.yield() }
        task.cancel()
        await task.value

        let sleeps = await script.sleeps
        #expect(Array(sleeps.prefix(3)) == [60, 60, 120])
    }
}
