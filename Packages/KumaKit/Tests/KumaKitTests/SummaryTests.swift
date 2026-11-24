import Foundation
import Testing

@testable import KumaKit

@Suite struct SummaryTests {
    func summary(_ statuses: [MonitorStatus]) -> Summary {
        Summary(monitors: statuses.enumerated().map { MonitorSnapshot(id: $0.offset, name: "m", status: $0.element) })
    }

    @Test func overallVerdicts() {
        #expect(summary([]).overall == .empty)
        #expect(summary([.up, .up]).overall == .allUp)
        #expect(summary([.up, .maintenance]).overall == .allUp)
        #expect(summary([.maintenance]).overall == .maintenance)
        #expect(summary([.up, .pending]).overall == .degraded)
        #expect(summary([.up, .unknown]).overall == .degraded)
        #expect(summary([.up, .down]).overall == .partialOutage)
        #expect(summary([.down, .pending]).overall == .partialOutage)
        #expect(summary([.down, .down]).overall == .majorOutage)
        #expect(summary([.down, .unknown]).overall == .majorOutage)
    }

    @Test func headlines() {
        #expect(summary([.up]).headline == "All systems up")
        #expect(summary([.up, .down, .down]).headline == "2 down")
        #expect(summary([.up, .pending]).headline == "1 pending")
        #expect(summary([.up, .unknown]).headline == "1 without data")
        #expect(summary([.down, .pending]).problems == 2)
    }
}
