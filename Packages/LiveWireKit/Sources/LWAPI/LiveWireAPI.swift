import Foundation
import LWLogging
import LWModels
import LWSecureStorage

/// Client of the LiveWire mobile API.
///
/// Endpoint paths and behavior come from the Android app as documented by
/// [py-livewire](https://github.com/hass-livewire/py-livewire), and every response shape used here was
/// confirmed against a real bike. `docs/api.md` is the reference; the wire types are in `WireTypes.swift`.
public final class LiveWireAPI: Sendable {
    private let configuration: APIConfiguration
    private let auth: AuthSession
    private let wire: Wire
    private let log = LWLogger("api")

    public init(
        configuration: APIConfiguration,
        secrets: any SecretStore,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.configuration = configuration
        let wire = Wire(transport: transport, log: LWLogger("http"))
        self.wire = wire
        self.auth = AuthSession(configuration: configuration, secrets: secrets, wire: wire)
    }

    // MARK: Session

    public func isSignedIn() async -> Bool {
        await auth.hasCredentials()
    }

    /// This install's device UUID (not a secret; the backend gets it in every URL).
    public func deviceUUID() async throws -> String {
        try await auth.deviceUUID()
    }

    public func signIn(email: String, password: String) async throws {
        try await auth.signIn(email: email, password: password)
    }

    public func signOut() async throws {
        try await auth.signOut()
    }

    // MARK: Bikes and pairing

    /// The account's bikes, each with whether this device is paired.
    public func bikes() async throws -> [Bike] {
        let uuid = try await auth.deviceUUID()
        return try await send(ListBikes(deviceUUID: uuid)).bikes.map(\.bike)
    }

    public func isPaired(bikeID: String) async throws -> Bool {
        let uuid = try await auth.deviceUUID()
        return try await send(PairingStatus(bikeID: bikeID, deviceUUID: uuid)).pairingStatus
    }

    /// Makes the bike show a 6-digit code on its display.
    ///
    /// The bike must be on, not in propulsion mode, not charging, and have cellular reception.
    public func requestPairingCode(bikeID: String) async throws {
        let uuid = try await auth.deviceUUID()
        let answer = try await send(RequestPairingCode(bikeID: bikeID, deviceUUID: uuid))
        if let status = answer.status, status != 200 {
            throw LiveWireAPIError.pairing(Self.pairingFailureMessage(answer, status: status))
        }
    }

    /// Turns the backend's pairing failure into something a person can act on.
    ///
    /// Real example (status 402): `{"command_name":"C_pairing_code","detail":"{\"reason\":\"DEVICE_TIMEOUT\",
    /// \"message\":\"Device did not respond in time\"}","pairedUserCount":0,"status":402}`. The backend
    /// waits about a minute for the bike to answer, so 402 means the bike never replied, not necessarily
    /// that it has no cellular connection.
    static func pairingFailureMessage(_ answer: PairingCommandResponse, status: Int) -> String {
        let reason = answer.parsedDetail?.reason
        let backendMessage = answer.parsedDetail?.message

        let advice: String = switch (status, reason) {
        case (_, "DEVICE_TIMEOUT"):
            "The bike did not answer in time. Check that the ignition is on, the bike is not charging or in propulsion mode, and it has cellular signal."
        case (400, _):
            "The bike must be switched on, not in propulsion mode and not charging."
        case (402, _):
            "The bike did not respond, or has no cellular connection."
        default:
            backendMessage ?? "Pairing request failed."
        }
        let facts = [String(status), reason, backendMessage].compactMap { $0 }.joined(separator: ": ")
        return "\(advice) (\(facts))"
    }

    /// Sends back the code the bike shows on its display.
    public func verifyPairingCode(bikeID: String, code: String) async throws {
        let uuid = try await auth.deviceUUID()
        let response = try await perform(VerifyPairingCode(bikeID: bikeID, deviceUUID: uuid, code: code))
        let answer = try? response.decode(PairingCommandResponse.self)
        let envelopeCode = (try? response.decode(ErrorEnvelope.self))?.error?.code.flatMap { Int($0) }
        switch answer?.code ?? envelopeCode {
        case 4003: throw LiveWireAPIError.pairing("Too many wrong codes. Request a new one.")
        case 4004: throw LiveWireAPIError.pairing("That code is wrong.")
        default: try response.validate(okCodes: ["0"])
        }
        if let answer, let status = answer.status, status != 200 {
            throw LiveWireAPIError.pairing(Self.pairingFailureMessage(answer, status: status))
        }
    }

    // MARK: Battery

    /// Battery, charging, range and odometer.
    ///
    /// Throws `LiveWireAPIError.notPaired` (code 3000) when this device UUID is not paired with the
    /// bike or the bike cannot be reached.
    public func chargingStatus(bikeID: String) async throws -> ChargingStatus {
        try await send(ChargingStatusRequest(bikeID: bikeID)).status(bikeID: bikeID)
    }

    // MARK: Analytics

    /// Rides, distance and efficiency for the week, month, 3 and 6 months.
    public func rideAnalytics(bikeID: String) async throws -> RideAnalytics {
        try await send(RideAnalyticsRequest(bikeID: bikeID, date: Date()))
    }

    /// Charging sessions and energy for the same periods.
    public func chargingAnalytics(bikeID: String) async throws -> ChargingAnalytics {
        try await send(ChargingAnalyticsRequest(bikeID: bikeID, date: Date()))
    }

    // MARK: Sending

    /// Sends an endpoint and decodes its response.
    private func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        try await perform(endpoint).decode(E.Response.self)
    }

    /// Sends an authenticated call, renews the session token once on a 401, and checks the error
    /// envelope unless the endpoint opts out.
    private func perform<E: Endpoint>(_ endpoint: E) async throws -> Wire.Response {
        var token = try await auth.token()
        var response = try await wire.send(endpoint, using: configuration, token: token)

        if response.status == 401 {
            log.info("401 from \(endpoint.path); renewing the session token")
            token = try await auth.renew(rejected: token)
            response = try await wire.send(endpoint, using: configuration, token: token)
        }

        if let okCodes = endpoint.okCodes { try response.validate(okCodes: okCodes) }
        return response
    }
}
