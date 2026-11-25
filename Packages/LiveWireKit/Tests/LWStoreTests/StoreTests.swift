import Foundation
import LWFileSystem
import LWModels
import Testing

@testable import LWStore

@Suite struct SnapshotStoreTests {
    private let directory = URL(filePath: "/memory/Group/Snapshot", directoryHint: .isDirectory)

    private func makeStore(_ files: InMemoryFileSystem = InMemoryFileSystem()) -> SnapshotStore {
        SnapshotStore(directory: directory, fileSystem: files)
    }

    @Test func roundTrip() async {
        let store = makeStore()
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

    @Test func twoStoresOnTheSameFileSeeTheSameData() async {
        // The app and the widget are two processes with one file.
        let files = InMemoryFileSystem()
        await makeStore(files).update { $0.selectedBikeID = "9" }
        #expect(await makeStore(files).load().selectedBikeID == "9")
    }

    @Test func emptyWhenMissingOrCorrupt() async throws {
        let files = InMemoryFileSystem()
        let store = makeStore(files)
        #expect(await store.load() == Snapshot())

        try files.write(Data("not json".utf8), to: directory.appendingPathComponent("snapshot.json"))
        #expect(await store.load() == Snapshot())
    }

    @Test func aFailedWriteLeavesTheOldSnapshotInPlace() async {
        let files = InMemoryFileSystem()
        let store = makeStore(files)
        await store.update { $0.selectedBikeID = "1" }

        files.failNext(.write, with: CocoaError(.fileWriteOutOfSpace))
        await store.update { $0.selectedBikeID = "2" }

        #expect(await store.load().selectedBikeID == "1")
    }

    @Test func clearRemovesTheFile() async {
        let files = InMemoryFileSystem()
        let store = makeStore(files)
        await store.update { $0.selectedBikeID = "9" }
        await store.clear()
        #expect(await store.load() == Snapshot())
        #expect(!files.fileExists(at: directory.appendingPathComponent("snapshot.json")))
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
