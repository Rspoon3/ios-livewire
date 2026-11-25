import Foundation
import LWFileSystem
import LWLogging
import LWModels

/// Non-secret data the app and the widget share: the bike list, the last status of each bike and the
/// selected bike. Secrets never go here (see `LWSecureStorage`).
///
/// It contains the VIN and the last known battery state, so the file is protected until first unlock
/// and is never written anywhere but the App Group container.
public struct Snapshot: Codable, Sendable, Equatable {
    public var bikes: [Bike]
    public var statuses: [String: ChargingStatus]
    public var selectedBikeID: String?
    public var updatedAt: Date?

    public init(
        bikes: [Bike] = [],
        statuses: [String: ChargingStatus] = [:],
        selectedBikeID: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.bikes = bikes
        self.statuses = statuses
        self.selectedBikeID = selectedBikeID
        self.updatedAt = updatedAt
    }

    public var pairedBikes: [Bike] { bikes.filter { $0.isPaired == true } }

    /// The bike to show by default: the selected one, else the primary, else the first paired.
    public var effectiveBikeID: String? {
        if let selectedBikeID, bikes.contains(where: { $0.id == selectedBikeID }) { return selectedBikeID }
        return (pairedBikes.first(where: \.isPrimary) ?? pairedBikes.first ?? bikes.first)?.id
    }
}

public actor SnapshotStore {
    private let fileURL: URL
    private let fileSystem: any FileSystem
    private let log = LWLogger("store")

    /// - Parameters:
    ///   - directory: where `snapshot.json` lives. In the app this is inside the App Group container
    ///     so the widget reads the same file.
    ///   - fileSystem: the disk, or an in-memory stand-in in tests.
    public init(directory: URL, fileSystem: any FileSystem = DiskFileSystem()) {
        self.fileSystem = fileSystem
        try? fileSystem.createDirectory(at: directory)
        fileURL = directory.appendingPathComponent("snapshot.json")
    }

    public func load() -> Snapshot {
        guard let data = try? fileSystem.read(fileURL) else { return Snapshot() }
        do {
            return try Self.decoder.decode(Snapshot.self, from: data)
        } catch {
            log.error("Could not read the snapshot, starting empty: \(error)")
            return Snapshot()
        }
    }

    /// Reads, changes and writes the snapshot. The write is atomic, so the widget never sees a
    /// half-written file. If both processes write at once, the later write wins.
    @discardableResult
    public func update(_ change: (inout Snapshot) -> Void) -> Snapshot {
        var snapshot = load()
        change(&snapshot)
        snapshot.updatedAt = Date()
        do {
            let data = try Self.encoder.encode(snapshot)
            try fileSystem.write(data, to: fileURL, protection: .untilFirstUserAuthentication)
        } catch {
            log.error("Could not write the snapshot: \(error)")
        }
        return snapshot
    }

    public func clear() {
        try? fileSystem.remove(fileURL)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
