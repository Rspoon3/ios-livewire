import Foundation
import LWAPI
import LWLogging
import LWModels
import LWSecureStorage
import LWStore

/// Everything the app and the widget do with the backend, in one place.
///
/// It talks to the API, keeps the shared snapshot up to date, and logs what happens. Views never
/// touch the API or the Keychain directly.
public final class LiveWireService: Sendable {
    public let api: LiveWireAPI
    public let store: SnapshotStore
    public let configuration: RuntimeConfiguration
    private let log = LWLogger("service")

    public init(api: LiveWireAPI, store: SnapshotStore, configuration: RuntimeConfiguration) {
        self.api = api
        self.store = store
        self.configuration = configuration
    }

    /// The real thing: Keychain secrets, App Group snapshot, URLSession transport.
    public static func live(configuration: RuntimeConfiguration) -> LiveWireService {
        let secrets = KeychainSecretStore(appGroupIdentifier: configuration.appGroupIdentifier)
        let api = LiveWireAPI(configuration: APIConfiguration(), secrets: secrets)
        let store = SnapshotStore(directory: configuration.snapshotDirectory())
        return LiveWireService(api: api, store: store, configuration: configuration)
    }

    // MARK: Session

    public func isSignedIn() async -> Bool {
        await api.isSignedIn()
    }

    public func signIn(email: String, password: String) async throws {
        try await api.signIn(email: email, password: password)
        log.info("Signed in")
    }

    public func signOut() async throws {
        try await api.signOut()
        await store.clear()
        log.info("Signed out and cleared the snapshot")
    }

    // MARK: Data

    public func cachedSnapshot() async -> Snapshot {
        await store.load()
    }

    /// Fetches the bike list and saves it. Bikes that disappeared are dropped, along with their status.
    @discardableResult
    public func refreshBikes() async throws -> [Bike] {
        let bikes = try await api.bikes()
        log.info("Fetched \(bikes.count) bike(s): " + bikes.map { "\($0.id) paired=\($0.isPaired.map(String.init(describing:)) ?? "?")" }.joined(separator: ", "))
        await store.update { snapshot in
            snapshot.bikes = bikes
            let ids = Set(bikes.map(\.id))
            snapshot.statuses = snapshot.statuses.filter { ids.contains($0.key) }
            if let selected = snapshot.selectedBikeID, !ids.contains(selected) { snapshot.selectedBikeID = nil }
        }
        return bikes
    }

    /// Fetches the battery and charging status of one bike and saves it.
    @discardableResult
    public func refreshStatus(bikeID: String) async throws -> ChargingStatus {
        let status = try await api.chargingStatus(bikeID: bikeID)
        log.info("Bike \(bikeID): battery \(status.batteryLevel.map { String($0) } ?? "?")% charging=\(status.isCharging) plugged=\(status.isPluggedIn) range=\(status.rangeMiles.map { String($0) } ?? "?") mi")
        await store.update { $0.statuses[bikeID] = status }
        return status
    }

    public func selectBike(_ bikeID: String?) async {
        await store.update { $0.selectedBikeID = bikeID }
    }

    // MARK: Pairing

    public func requestPairingCode(bikeID: String) async throws {
        try await api.requestPairingCode(bikeID: bikeID)
        log.info("Pairing code requested for bike \(bikeID)")
    }

    public func verifyPairingCode(bikeID: String, code: String) async throws {
        try await api.verifyPairingCode(bikeID: bikeID, code: code)
        log.info("Pairing code accepted for bike \(bikeID)")
    }

    /// Polls until the backend reports the bike as paired, or the timeout passes.
    public func waitUntilPaired(bikeID: String, timeout: Duration = .seconds(60), interval: Duration = .seconds(3)) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if try await api.isPaired(bikeID: bikeID) {
                try await refreshBikes()
                return true
            }
            try await Task.sleep(for: interval)
        }
        log.warning("Bike \(bikeID) did not report as paired within \(timeout)")
        return false
    }
}
