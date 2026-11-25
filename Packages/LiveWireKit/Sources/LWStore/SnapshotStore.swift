import Foundation
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

public enum AppGroup {
    /// The App Group's shared container, or `nil` when the entitlement is missing.
    public static func containerURL(identifier: String?) -> URL? {
        guard let identifier, !identifier.isEmpty else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

public actor SnapshotStore {
    private let fileURL: URL
    private let log = LWLogger("store")

    /// - Parameter directory: where `snapshot.json` lives. In the app this is inside the App Group
    ///   container so the widget reads the same file.
    public init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("snapshot.json")
    }

    public func load() -> Snapshot {
        guard let data = try? Data(contentsOf: fileURL) else { return Snapshot() }
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
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            log.error("Could not write the snapshot: \(error)")
        }
        return snapshot
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
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
