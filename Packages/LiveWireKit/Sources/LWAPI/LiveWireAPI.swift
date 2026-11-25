import Foundation
import LWLogging
import LWModels
import LWSecureStorage

/// Client of the LiveWire mobile API.
///
/// Endpoint paths and behavior come from the Android app as documented by
/// [py-livewire](https://github.com/hass-livewire/py-livewire); the iOS app's Info.plist confirms
/// the same backend and login provider. Nothing here has been verified against the iOS app's own
/// code (it is FairPlay-encrypted), so treat `docs/api.md` as the source of truth and the log files
/// as the evidence.
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
        guard let list = response.body["bikes"]?.arrayValue else {
            throw LiveWireAPIError.unexpectedResponse("getAllbikes/pairingStatus has no \"bikes\" array")
        }
        return list.compactMap(Bike.init(json:))
    }

    /// `GET bikes/pairing/status/{id}`
    public func isPaired(bikeID: String) async throws -> Bool {
        let deviceUUID = try await auth.deviceUUID()
        let response = try await call(
            "GET", "bikes/pairing/status/\(bikeID)",
            query: [("deviceUUID", deviceUUID)]
        )
        return response.body["pairingStatus"]?.boolValue ?? false
    }

    /// A read-only GET that returns the body as is, without checking the error envelope. For diagnostics:
    /// the exchange is logged by `Wire`, so the log shows exactly what the backend said.
    public func probe(_ path: String, query: [(String, String)] = []) async throws -> JSONValue {
        try await call("GET", path, query: query, checkEnvelope: false).body
    }

    /// This install's device UUID (not a secret; the backend gets it in every URL).
    public func currentDeviceUUID() async throws -> String {
        try await auth.deviceUUID()
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
        if let status = response.body["status"]?.intValue, status != 200 {
            throw LiveWireAPIError.pairing(Self.pairingFailureMessage(status: status, body: response.body))
        }
    }

    /// Turns the backend's pairing failure into something a person can act on.
    ///
    /// Real example (status 402): `{"command_name":"C_pairing_code","detail":"{\"reason\":\"DEVICE_TIMEOUT\",
    /// \"message\":\"Device did not respond in time\"}","pairedUserCount":0,"status":402}`. The backend
    /// waits about a minute for the bike to answer, so 402 means the bike never replied, not necessarily
    /// that it has no cellular connection.
    static func pairingFailureMessage(status: Int, body: JSONValue) -> String {
        let detail = body["detail"]?.textValue.map { JSONValue(data: Data($0.utf8)) }
        let reason = detail?["reason"]?.textValue
        let backendMessage = detail?["message"]?.textValue
            ?? body.path("error", "description")?.textValue

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
            body: .object(["code": .string(code)]),
            redactRequestKeys: ["code"],
            checkEnvelope: false
        )
        let result = response.body["code"]?.intValue ?? response.body.path("error", "code")?.intValue
        switch result {
        case 4003: throw LiveWireAPIError.pairing("Too many wrong codes. Request a new one.")
        case 4004: throw LiveWireAPIError.pairing("That code is wrong.")
        default: try Self.validate(response, okCodes: ["0"])
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
        return ChargingStatus(bikeID: bikeID, json: response.body)
    }

    // MARK: Rides

    /// `GET rides?type=CUSTOM`: rides the user recorded or planned.
    public func myRides(units: String = "imperial") async throws -> [RideSummary] {
        let response = try await call(
            "GET", "rides",
            query: [("type", "CUSTOM"), ("includeWeather", units)]
        )
        guard let list = response.body["rides"]?.arrayValue else {
            throw LiveWireAPIError.unexpectedResponse("rides has no \"rides\" array")
        }
        return list.compactMap(RideSummary.init(json:))
    }

    /// `GET rides/{id}`
    public func ride(id: String, includeLocationHistory: Bool = false) async throws -> JSONValue {
        let response = try await call(
            "GET", "rides/\(id)",
            query: [("includeLocationHistory", includeLocationHistory ? "true" : "false")]
        )
        return response.body["ride"] ?? response.body
    }

    /// `GET bikes/{id}/ride/analytics`: rides, distance and efficiency for the week, month, 3 and 6 months.
    public func rideAnalytics(bikeID: String) async throws -> RideAnalytics {
        let response = try await call(
            "GET", "bikes/\(bikeID)/ride/analytics",
            query: [("date", Self.now())]
        )
        guard let analytics = RideAnalytics(json: response.body) else {
            throw LiveWireAPIError.unexpectedResponse("ride/analytics has no \"periods\" array")
        }
        return analytics
    }

    /// `GET bikes/{id}/charging/analytics`: charging sessions and energy for the same periods.
    public func chargingAnalytics(bikeID: String) async throws -> ChargingAnalytics {
        let response = try await call(
            "GET", "bikes/\(bikeID)/charging/analytics",
            query: [("date", Self.now())]
        )
        guard let analytics = ChargingAnalytics(json: response.body) else {
            throw LiveWireAPIError.unexpectedResponse("charging/analytics has no \"periods\" array")
        }
        return analytics
    }

    // MARK: Plumbing

    /// Sends an authenticated request, signs in again once on a 401, and checks the error envelope.
    private func call(
        _ method: String,
        _ path: String,
        query: [(String, String)] = [],
        body: JSONValue? = nil,
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
        body: JSONValue?,
        token: String,
        redactRequestKeys: Set<String>,
        timeout: TimeInterval? = nil
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
        if let error = response.body["error"]?.objectValue, !error.isEmpty {
            let code = error["code"]?.textValue ?? "nil"
            if !okCodes.contains(code) {
                let message = error["description"]?.textValue
                    ?? error["message"]?.textValue
                    ?? "Unknown error"
                if code == "3000" {
                    throw LiveWireAPIError.notPaired(
                        "\(message): this device is not paired with the bike, or the bike is not reachable."
                    )
                }
                throw LiveWireAPIError.api(code: code, message: message, status: response.status)
            }
        }
        if response.status >= 400 {
            let message = response.body.first(of: ["description", "detail", "message", "title"])?.textValue
                ?? response.body.path("error", "description")?.textValue
                ?? "HTTP \(response.status)"
            throw LiveWireAPIError.http(status: response.status, message: message)
        }
    }

    static func now() -> String {
        Date().formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
