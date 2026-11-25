import Foundation
import LWModels
import Testing

@testable import LWStore

@Suite struct SnapshotStoreTests {
    private func makeStore() -> (SnapshotStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lw-store-\(UUID().uuidString)", isDirectory: true)
        return (SnapshotStore(directory: directory), directory)
    }

    @Test func roundTrip() async {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        await store.update {
            $0.bikes = [Bike(id: "1", name: "A", isPaired: true)]
            $0.statuses["1"] = ChargingStatus(bikeID: "1", batteryLevel: 55, isCharging: true)
            $0.selectedBikeID = "1"
        }
        let loaded = await store.load()
        #expect(loaded.bikes.map(\.id) == ["1"])
        #expect(loaded.statuses["1"]?.batteryLevel == 55)
        #expect(loaded.selectedBikeID == "1")
        #expect(loaded.updatedAt != nil)
    }

    @Test func emptyWhenMissingOrCorrupt() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(await store.load() == Snapshot())

        try Data("not json".utf8).write(to: directory.appendingPathComponent("snapshot.json"))
        #expect(await store.load() == Snapshot())
    }

    @Test func clearRemovesTheFile() async {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        await store.update { $0.selectedBikeID = "9" }
        await store.clear()
        #expect(await store.load() == Snapshot())
    }
}

@Suite struct EffectiveBikeTests {
    @Test func prefersSelectedThenPrimaryThenFirstPaired() {
        let bikes = [
            Bike(id: "1", isPaired: false),
            Bike(id: "2", isPaired: true),
            Bike(id: "3", isPrimary: true, isPaired: true),
        ]
        #expect(Snapshot(bikes: bikes, selectedBikeID: "2").effectiveBikeID == "2")
        #expect(Snapshot(bikes: bikes).effectiveBikeID == "3")
        #expect(Snapshot(bikes: [bikes[0], bikes[1]]).effectiveBikeID == "2")
        #expect(Snapshot(bikes: [bikes[0]]).effectiveBikeID == "1")
        #expect(Snapshot(bikes: bikes, selectedBikeID: "gone").effectiveBikeID == "3")
        #expect(Snapshot().effectiveBikeID == nil)
    }
}
