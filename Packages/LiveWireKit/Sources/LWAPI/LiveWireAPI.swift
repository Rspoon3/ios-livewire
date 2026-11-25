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

    /// `GET getAllbikes/pairingStatus`: the account's bikes, each with whether this device is paired.
    public func bikes() async throws -> [Bike] {
        let deviceUUID = try await auth.deviceUUID()
        let response = try await call(
            "GET", "getAllbikes/pairingStatus",
            query: [("deviceUUID", deviceUUID)]
        )
        return try response.decode(BikesResponse.self).bikes.map(\.bike)
    }

    /// `GET bikes/pairing/status/{id}`
    public func isPaired(bikeID: String) async throws -> Bool {
        let deviceUUID = try await auth.deviceUUID()
        let response = try await call(
            "GET", "bikes/pairing/status/\(bikeID)",
            query: [("deviceUUID", deviceUUID)]
        )
        return try response.decode(PairingStatusResponse.self).pairingStatus
    }

    static let pairingRequestTimeout: TimeInterval = 120

    /// `POST bikes/{id}/pair`: makes the bike show a 6-digit code on its display.
    ///
    /// The bike must be on, not in propulsion mode, not charging, and have cellular reception.
    public func requestPairingCode(bikeID: String) async throws {
        let deviceUUID = try await auth.deviceUUID()
        let response = try await call(
            "POST", "bikes/\(bikeID)/pair",
            query: [("deviceUUID", deviceUUID)],
            // The backend holds this request for about a minute while it waits for the bike.
            timeout: Self.pairingRequestTimeout
        )
        let answer = try response.decode(PairingCommandResponse.self)
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

    /// `POST bikes/{id}/verify/code` with the code shown on the bike's display.
    public func verifyPairingCode(bikeID: String, code: String) async throws {
        let deviceUUID = try await auth.deviceUUID()
        let response = try await call(
            "POST", "bikes/\(bikeID)/verify/code",
            query: [("deviceUUID", deviceUUID)],
            body: VerifyCodeRequest(code: code),
            redactRequestKeys: ["code"],
            checkEnvelope: false
        )
        let answer = try? response.decode(PairingCommandResponse.self)
        let envelopeCode = (try? response.decode(ErrorEnvelope.self))?.error?.code.flatMap { Int($0) }
        switch answer?.code ?? envelopeCode {
        case 4003: throw LiveWireAPIError.pairing("Too many wrong codes. Request a new one.")
        case 4004: throw LiveWireAPIError.pairing("That code is wrong.")
        default: try Self.validate(response, okCodes: ["0"])
        }
        if let answer, let status = answer.status, status != 200 {
            throw LiveWireAPIError.pairing(Self.pairingFailureMessage(answer, status: status))
        }
    }

    // MARK: Charging

    /// `GET bikes/{id}/charging/status`: battery, charging, range, odometer.
    ///
    /// Throws `LiveWireAPIError.notPaired` (code 3000) when this device UUID is not paired with the
    /// bike or the bike cannot be reached. Code -300 is a partial answer that still carries data.
    public func chargingStatus(bikeID: String) async throws -> ChargingStatus {
        let response = try await call(
            "GET", "bikes/\(bikeID)/charging/status",
            okCodes: ["0", "-300"]
        )
        return try response.decode(ChargingStatusResponse.self).status(bikeID: bikeID)
    }

    // MARK: Analytics

    /// `GET bikes/{id}/ride/analytics`: rides, distance and efficiency for the week, month, 3 and 6 months.
    public func rideAnalytics(bikeID: String) async throws -> RideAnalytics {
        let response = try await call(
            "GET", "bikes/\(bikeID)/ride/analytics",
            query: [("date", Self.now())]
        )
        return try response.decode(RideAnalytics.self)
    }

    /// `GET bikes/{id}/charging/analytics`: charging sessions and energy for the same periods.
    public func chargingAnalytics(bikeID: String) async throws -> ChargingAnalytics {
        let response = try await call(
            "GET", "bikes/\(bikeID)/charging/analytics",
            query: [("date", Self.now())]
        )
        return try response.decode(ChargingAnalytics.self)
    }

    // MARK: Plumbing

    /// Sends an authenticated request, signs in again once on a 401, and checks the error envelope.
    private func call(
        _ method: String,
        _ path: String,
        query: [(String, String)] = [],
        body: (any Encodable & Sendable)? = nil,
        okCodes: Set<String> = ["0"],
        redactRequestKeys: Set<String> = [],
        checkEnvelope: Bool = true,
        timeout: TimeInterval? = nil
    ) async throws -> Wire.Response {
        var token = try await auth.token()
        var response = try await send(method, path, query: query, body: body, token: token, redactRequestKeys: redactRequestKeys, timeout: timeout)

        if response.status == 401 {
            log.info("401 from \(path); renewing the session token")
            token = try await auth.renew(rejected: token)
            response = try await send(method, path, query: query, body: body, token: token, redactRequestKeys: redactRequestKeys, timeout: timeout)
        }

        if checkEnvelope { try Self.validate(response, okCodes: okCodes) }
        return response
    }

    private func send(
        _ method: String,
        _ path: String,
        query: [(String, String)],
        body: (any Encodable & Sendable)?,
        token: String,
        redactRequestKeys: Set<String>,
        timeout: TimeInterval?
    ) async throws -> Wire.Response {
        var components = URLComponents(url: configuration.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = (query + [("brand", configuration.brand)]).map { URLQueryItem(name: $0.0, value: $0.1) }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        if let timeout { request.timeoutInterval = timeout }
        for (name, value) in configuration.identity.headers { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = try JSONEncoder().encode(body) }

        let queryText = (query.isEmpty ? "" : "?" + query.map { "\($0.0)=\($0.1)" }.joined(separator: "&"))
        return try await wire.perform(
            request,
            label: "\(method) \(path)\(queryText)",
            redactRequestKeys: redactRequestKeys
        )
    }

    /// Errors mostly arrive with HTTP 200 as `{"error": {"code": …, "description": …}}`.
    static func validate(_ response: Wire.Response, okCodes: Set<String>) throws {
        if let error = (try? response.decode(ErrorEnvelope.self))?.error, let code = error.code, !okCodes.contains(code) {
            let message = error.description ?? error.message ?? "Unknown error"
            if code == "3000" {
                throw LiveWireAPIError.notPaired(
                    "\(message): this device is not paired with the bike, or the bike is not reachable."
                )
            }
            throw LiveWireAPIError.api(code: code, message: message, status: response.status)
        }
        if response.status >= 400 {
            let body = try? response.decode(HTTPErrorBody.self)
            let message = body?.text
                ?? (try? response.decode(ErrorEnvelope.self))?.error?.description
                ?? "HTTP \(response.status)"
            throw LiveWireAPIError.http(status: response.status, message: message)
        }
    }

    static func now() -> String {
        Date().formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
