import Foundation
import Testing

@testable import KumaKit

@Suite struct DisplayOptionsTests {
    /// Mirrors the real page that prompted this: a healthy first group, and a
    /// down monitor in the middle of a later one.
    let snapshot: StatusSnapshot = {
        func monitor(_ id: Int, _ status: MonitorStatus) -> MonitorSnapshot {
            MonitorSnapshot(id: id, name: "m\(id)", status: status)
        }
        return StatusSnapshot(
            title: "Lab", pageURL: URL(string: "https://kuma.test/status/lab")!, fetchedAt: .now,
            groups: [
                GroupSnapshot(id: 1, name: "Infrastructure", monitors: [monitor(1, .up), monitor(2, .up)]),
                GroupSnapshot(id: 2, name: "Maintenance", monitors: [monitor(3, .maintenance)]),
                GroupSnapshot(
                    id: 3, name: "Homelab",
                    monitors: [monitor(4, .up), monitor(5, .pending), monitor(6, .down), monitor(7, .up)]),
                GroupSnapshot(id: 4, name: "Arr", monitors: [monitor(8, .unknown), monitor(9, .up)]),
            ])
    }()

    func layout(_ groups: [GroupSnapshot]) -> [String] {
        groups.map { "\($0.name): " + $0.monitors.map { String($0.id) }.joined(separator: ",") }
    }

    @Test func putsProblemGroupsAndMonitorsFirst() {
        #expect(
            layout(snapshot.displayGroups()) == [
                "Homelab: 6,5,4,7",
                "Arr: 8,9",
                "Maintenance: 3",
                "Infrastructure: 1,2",
            ])
    }

    @Test func hidingUpMonitorsLeavesOnlyProblems() {
        let options = DisplayOptions(hiddenStatuses: [.up])
        #expect(layout(snapshot.displayGroups(options)) == ["Homelab: 6,5", "Arr: 8", "Maintenance: 3"])
        #expect(snapshot.displayMonitors(options).map(\.id) == [6, 5, 8, 3])
        #expect(snapshot.filteredOut(options).map(\.id) == [1, 2, 4, 7, 9])
    }

    @Test func downMonitorsCannotBeHidden() {
        let options = DisplayOptions(hiddenStatuses: Set(MonitorStatus.allCases))
        #expect(options.hiddenStatuses == [.up, .pending, .maintenance, .unknown])
        #expect(layout(snapshot.displayGroups(options)) == ["Homelab: 6"])
    }

    @Test func filteringDoesNotChangeTheSummary() {
        let options = DisplayOptions(hiddenStatuses: [.up, .pending])
        _ = snapshot.displayGroups(options)
        #expect(snapshot.summary.total == 9)
        #expect(snapshot.summary.down == 1)
    }

    @Test func aMonitorInTwoGroupsIsListedOnceInTheFlatList() {
        var shared = snapshot
        shared.groups[0].monitors.append(MonitorSnapshot(id: 6, name: "m6", status: .down))
        #expect(shared.displayMonitors().filter { $0.id == 6 }.count == 1)
        #expect(layout(shared.displayGroups()).first == "Infrastructure: 6,1,2")
    }

    @Test func persistsAndIgnoresAStoredHiddenDown() throws {
        let defaults = try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
        let store = ConfigurationStore(defaults: defaults)
        #expect(store.loadDisplay() == .default)

        store.saveDisplay(DisplayOptions(hiddenStatuses: [.up, .maintenance]))
        #expect(store.loadDisplay().hiddenStatuses == [.up, .maintenance])

        defaults.set(Data(#"{"hiddenStatuses":[0,1]}"#.utf8), forKey: "display")
        #expect(store.loadDisplay().hiddenStatuses == [.up])
    }
}
