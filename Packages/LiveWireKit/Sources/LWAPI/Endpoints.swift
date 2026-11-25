import Foundation
import LWModels

// Every call this client makes, as a value. The wire types they return are in `WireTypes.swift`
// and the endpoints are documented in docs/api.md.

// MARK: Sign-in

/// `POST accounts.login` at Gigya. Returns the account's `UID`.
struct GigyaLogin: Endpoint {
    typealias Response = GigyaLoginResponse

    let apiKey: String
    let email: String
    let password: String

    var host: Host { .gigya }
    var method: HTTPMethod { .post }
    var path: String { "accounts.login" }
    var isAuthorized: Bool { false }
    var okCodes: Set<String>? { nil }
    var logPolicy: LogPolicy { .outcomeOnly }
    var body: RequestBody {
        .form([
            .init("apiKey", apiKey),
            .init("loginID", email),
            .init("password", password),
            .init("include", "profile,data"),
            .init("format", "json"),
        ])
    }
}

/// `POST session`: swaps the Gigya `UID` for a LiveWire session token.
struct CreateSession: Endpoint {
    typealias Response = SessionResponse

    let request: SessionRequest

    var method: HTTPMethod { .post }
    var path: String { "session" }
    var isAuthorized: Bool { false }
    var okCodes: Set<String>? { nil }
    var body: RequestBody { .json(request) }
}

// MARK: Bikes and pairing

/// `GET getAllbikes/pairingStatus`: the account's bikes and whether this device is paired with each.
struct ListBikes: Endpoint {
    typealias Response = BikesResponse

    let deviceUUID: String

    var method: HTTPMethod { .get }
    var path: String { "getAllbikes/pairingStatus" }
    var query: [URLQueryItem] { [.init(name: "deviceUUID", value: deviceUUID)] }
}

/// `GET bikes/pairing/status/{id}`
struct PairingStatus: Endpoint {
    typealias Response = PairingStatusResponse

    let bikeID: String
    let deviceUUID: String

    var method: HTTPMethod { .get }
    var path: String { "bikes/pairing/status/\(bikeID)" }
    var query: [URLQueryItem] { [.init(name: "deviceUUID", value: deviceUUID)] }
}

/// `POST bikes/{id}/pair`: makes the bike show a 6-digit code on its display.
struct RequestPairingCode: Endpoint {
    typealias Response = PairingCommandResponse

    let bikeID: String
    let deviceUUID: String

    var method: HTTPMethod { .post }
    var path: String { "bikes/\(bikeID)/pair" }
    var query: [URLQueryItem] { [.init(name: "deviceUUID", value: deviceUUID)] }
    /// The backend holds this request for about a minute while it waits for the bike.
    var timeout: TimeInterval? { 120 }
}

/// `POST bikes/{id}/verify/code`: sends back the code the bike shows.
struct VerifyPairingCode: Endpoint {
    typealias Response = PairingCommandResponse

    let bikeID: String
    let deviceUUID: String
    let code: String

    var method: HTTPMethod { .post }
    var path: String { "bikes/\(bikeID)/verify/code" }
    var query: [URLQueryItem] { [.init(name: "deviceUUID", value: deviceUUID)] }
    var body: RequestBody { .json(VerifyCodeRequest(code: code)) }
    /// A wrong code is reported in a top-level `code`, not in the error envelope.
    var okCodes: Set<String>? { nil }
    var logPolicy: LogPolicy { LogPolicy(redactedRequestKeys: ["code"]) }
}

// MARK: Battery

/// `GET bikes/{id}/charging/status`. Code `-300` is a partial answer that still carries data.
struct ChargingStatusRequest: Endpoint {
    typealias Response = ChargingStatusResponse

    let bikeID: String

    var method: HTTPMethod { .get }
    var path: String { "bikes/\(bikeID)/charging/status" }
    var okCodes: Set<String>? { ["0", "-300"] }
}

// MARK: Location

/// `GET bike/{id}/location`: the last GPS position the bike reported. Note `bike`, not `bikes`.
struct BikeLocationRequest: Endpoint {
    typealias Response = LocationResponse

    let bikeID: String

    var method: HTTPMethod { .get }
    var path: String { "bike/\(bikeID)/location" }
}

// MARK: Analytics

/// `GET bikes/{id}/ride/analytics`: totals for the week, month, 3 and 6 months up to `date`.
struct RideAnalyticsRequest: Endpoint {
    typealias Response = RideAnalytics

    let bikeID: String
    let date: Date

    var method: HTTPMethod { .get }
    var path: String { "bikes/\(bikeID)/ride/analytics" }
    var query: [URLQueryItem] { [.init(name: "date", value: date.formatted(.iso8601WithMilliseconds))] }
}

/// `GET bikes/{id}/charging/analytics`: the same periods, for charging.
struct ChargingAnalyticsRequest: Endpoint {
    typealias Response = ChargingAnalytics

    let bikeID: String
    let date: Date

    var method: HTTPMethod { .get }
    var path: String { "bikes/\(bikeID)/charging/analytics" }
    var query: [URLQueryItem] { [.init(name: "date", value: date.formatted(.iso8601WithMilliseconds))] }
}

extension FormatStyle where Self == Date.ISO8601FormatStyle {
    /// `2026-11-25T18:17:49.062Z`, the form the app sends.
    static var iso8601WithMilliseconds: Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    }
}
