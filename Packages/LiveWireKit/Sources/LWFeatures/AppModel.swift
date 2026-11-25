import Foundation
import LWAPI
import LWLogging
import LWModels
import LWServices
import LWStore
import Observation
import WidgetKit

/// The ride and charging analytics of one bike. Either half can be missing when its request failed.
public struct AnalyticsReport: Sendable {
    public var rides: RideAnalytics?
    public var charging: ChargingAnalytics?
    public var ridesError: String?
    public var chargingError: String?
}

/// State and actions behind every screen. Views read it; they never touch the API or the Keychain.
@MainActor
@Observable
public final class AppModel {
    public enum Phase: Equatable {
        case launching
        case signedOut
        case ready
    }

    public private(set) var phase: Phase = .launching
    public private(set) var snapshot = Snapshot()
    public private(set) var isRefreshing = false
    /// Per-bike problems from the last refresh (for example "not paired").
    public private(set) var statusErrors: [String: String] = [:]
    public var errorMessage: String?

    /// Ride and charging analytics per bike id.
    public private(set) var analytics: [String: AnalyticsReport] = [:]
    public private(set) var isLoadingAnalytics = false

    /// Last reported position per bike id. Kept in memory only: it is not written to the snapshot file
    /// that the widget reads, or anywhere else on disk.
    public private(set) var locations: [String: BikeLocation] = [:]
    /// Per-bike problems from the last location request.
    public private(set) var locationErrors: [String: String] = [:]
    private var locationRequests: Set<String> = []

    public let configuration: RuntimeConfiguration
    private let service: LiveWireService
    private let log = LWLogger("app")

    public init(configuration: RuntimeConfiguration) {
        self.configuration = configuration
        service = LiveWireService.live(configuration: configuration)
    }

    // MARK: Lifecycle

    public func start() async {
        snapshot = await service.cachedSnapshot()
        if await service.isSignedIn() {
            phase = .ready
            await refresh()
        } else {
            phase = .signedOut
        }
    }

    /// Call when the app returns to the foreground.
    public func didBecomeActive() async {
        logExport.syncWidgetLogs()
        if phase == .ready { await refresh() }
    }

    // MARK: Session

    public func signIn(email: String, password: String) async throws {
        do {
            try await service.signIn(email: email, password: password)
        } catch {
            log.warning("Sign-in failed: \(error)")
            throw error
        }
        phase = .ready
        await refresh()
    }

    public func signOut() async {
        do { try await service.signOut() } catch { log.error("Sign-out failed: \(error)") }
        snapshot = Snapshot()
        statusErrors = [:]
        analytics = [:]
        locations = [:]
        locationErrors = [:]
        locationRequests = []
        phase = .signedOut
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Bikes

    public var pairedBikes: [Bike] { snapshot.pairedBikes }

    /// Fetches the bike list and the status of every paired bike.
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        errorMessage = nil

        do {
            try await service.refreshBikes()
        } catch {
            handle(error, context: "bike list")
            snapshot = await service.cachedSnapshot()
            return
        }
        snapshot = await service.cachedSnapshot()

        let service = service
        let log = log
        // One request per paired bike, in parallel. Most accounts have one; this is ready for more.
        let results = await withTaskGroup(of: (String, String?).self) { group in
            for bike in snapshot.pairedBikes {
                group.addTask {
                    do {
                        _ = try await service.refreshStatus(bikeID: bike.id)
                        return (bike.id, nil)
                    } catch {
                        log.error("Status refresh failed for bike \(bike.id): \(error)")
                        return (bike.id, error.localizedDescription)
                    }
                }
            }
            var collected: [String: String?] = [:]
            for await (id, message) in group { collected[id] = message }
            return collected
        }
        statusErrors = results.compactMapValues { $0 }
        snapshot = await service.cachedSnapshot()
        WidgetCenter.shared.reloadAllTimelines()
    }

    public func select(bikeID: String?) async {
        await service.selectBike(bikeID)
        snapshot = await service.cachedSnapshot()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Pairing

    public func requestPairingCode(bikeID: String) async throws {
        do { try await service.requestPairingCode(bikeID: bikeID) } catch {
            log.error("Requesting a pairing code failed for bike \(bikeID): \(error)")
            throw error
        }
    }

    public func verifyPairingCode(bikeID: String, code: String) async throws {
        do { try await service.verifyPairingCode(bikeID: bikeID, code: code) } catch {
            log.error("Verifying the pairing code failed for bike \(bikeID): \(error)")
            throw error
        }
    }

    /// Waits for the backend to confirm the pairing, then refreshes everything.
    public func finishPairing(bikeID: String) async throws -> Bool {
        let paired: Bool
        do { paired = try await service.waitUntilPaired(bikeID: bikeID) } catch {
            log.error("Waiting for pairing failed for bike \(bikeID): \(error)")
            throw error
        }
        if paired { await refresh() }
        return paired
    }

    // MARK: Analytics

    /// Fetches the ride and charging analytics of every paired bike. Each call is logged by the HTTP
    /// layer, and a failure of one does not stop the others.
    public func loadAnalytics() async {
        let service = service
        let log = log
        let bikes = snapshot.pairedBikes
        isLoadingAnalytics = true
        defer { isLoadingAnalytics = false }

        let reports = await withTaskGroup(of: (String, AnalyticsReport).self) { group in
            for bike in bikes {
                group.addTask {
                    var report = AnalyticsReport()
                    do { report.rides = try await service.api.rideAnalytics(bikeID: bike.id) } catch {
                        log.error("Ride analytics failed for bike \(bike.id): \(error)")
                        report.ridesError = error.localizedDescription
                    }
                    do { report.charging = try await service.api.chargingAnalytics(bikeID: bike.id) } catch {
                        log.error("Charging analytics failed for bike \(bike.id): \(error)")
                        report.chargingError = error.localizedDescription
                    }
                    return (bike.id, report)
                }
            }
            var collected: [String: AnalyticsReport] = [:]
            for await (id, report) in group { collected[id] = report }
            return collected
        }
        analytics = reports
    }

    // MARK: Location

    /// Fetches where the bike last reported itself. A failure is shown on the bike's screen and logged.
    public func loadLocation(bikeID: String) async {
        defer { locationRequests.insert(bikeID) }
        do {
            locations[bikeID] = try await service.api.bikeLocation(bikeID: bikeID)
            locationErrors[bikeID] = nil
        } catch {
            log.error("Loading the location failed for bike \(bikeID): \(error)")
            locationErrors[bikeID] = error.localizedDescription
        }
    }

    /// Whether a location request has finished for this bike, so "no position yet" is not shown while loading.
    public func hasLoadedLocation(bikeID: String) -> Bool { locationRequests.contains(bikeID) }

    // MARK: Logs

    var logExport: LogExport { configuration.logExport() }

    public func clearLogs() {
        logExport.clear()
        log.info("Logs cleared by the user")
    }

    public var logFileCount: Int { logExport.logFileCount }

    // MARK: Errors

    private func handle(_ error: Error, context: String) {
        log.error("Refreshing the \(context) failed: \(error)")
        if case LiveWireAPIError.notSignedIn = error {
            phase = .signedOut
        } else {
            errorMessage = error.localizedDescription
        }
    }
}

extension AppModel: SigningIn, BikePairing {}
