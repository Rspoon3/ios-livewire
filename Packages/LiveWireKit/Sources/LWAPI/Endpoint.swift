import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
}

/// The server a call goes to.
enum Host: Sendable {
    /// `mobileapi.livewire.com/api`
    case liveWire
    /// The Gigya identity provider that signs people in.
    case gigya
}

enum RequestBody: Sendable {
    case none
    case json(any Encodable & Sendable)
    /// `application/x-www-form-urlencoded`, which Gigya expects.
    case form([FormField])

    struct FormField: Sendable {
        let name: String
        let value: String
        init(_ name: String, _ value: String) {
            self.name = name
            self.value = value
        }
    }

    /// `+` and `&` in a password must be escaped, which `URLComponents` does not do for
    /// query-style bodies.
    static func formEncoded(_ fields: [FormField]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let text = fields
            .map { field in
                let name = field.name.addingPercentEncoding(withAllowedCharacters: allowed) ?? field.name
                let value = field.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? field.value
                return "\(name)=\(value)"
            }
            .joined(separator: "&")
        return Data(text.utf8)
    }
}

/// What gets written to the log for a call. Bodies are logged so the API can be mapped from real
/// runs; `Redactor` masks the secrets in them.
struct LogPolicy: Sendable {
    var logsBodies = true
    /// Extra JSON keys to mask in the request body, for example the pairing `code`.
    var redactedRequestKeys: Set<String> = []

    static let standard = LogPolicy()
    /// Gigya's replies carry session secrets and profile data, so only the outcome is logged.
    static let outcomeOnly = LogPolicy(logsBodies: false)
}

/// One call to a server: where it goes, what it sends and what comes back.
///
/// Each call is a small struct (see `Endpoints.swift`), so the path, query and body are written once,
/// next to the type of the response, and tests can inspect the request without a network.
protocol Endpoint: Sendable {
    associatedtype Response: Decodable & Sendable

    var host: Host { get }
    var method: HTTPMethod { get }
    /// Relative to the host's base URL, without a leading slash.
    var path: String { get }
    var query: [URLQueryItem] { get }
    var body: RequestBody { get }
    /// Whether the call carries the session's bearer token.
    var isAuthorized: Bool { get }
    /// The `error.code` values that count as success. `nil` skips the check, for calls that report
    /// failure some other way (Gigya, the pairing code check).
    var okCodes: Set<String>? { get }
    /// Overrides the default request timeout.
    var timeout: TimeInterval? { get }
    var logPolicy: LogPolicy { get }
}

extension Endpoint {
    var host: Host { .liveWire }
    var query: [URLQueryItem] { [] }
    var body: RequestBody { .none }
    var isAuthorized: Bool { true }
    var okCodes: Set<String>? { ["0"] }
    var timeout: TimeInterval? { nil }
    var logPolicy: LogPolicy { .standard }

    /// What shows in the log and in error messages, e.g. `GET bikes/1/charging/status?date=…`. The
    /// `brand` parameter that every call carries is left out.
    var label: String {
        let queryText = query.isEmpty ? "" : "?" + query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        let server = host == .gigya ? "gigya " : ""
        return "\(method.rawValue) \(server)\(path)\(queryText)"
    }
}

extension APIConfiguration {
    /// Builds the request for an endpoint. `token` is added when the endpoint is authorized.
    func urlRequest<E: Endpoint>(for endpoint: E, token: String?) throws -> URLRequest {
        let base: URL
        var items = endpoint.query
        switch endpoint.host {
        case .liveWire:
            base = baseURL
            items.append(URLQueryItem(name: "brand", value: brand))
        case .gigya:
            base = gigyaURL
        }

        var components = URLComponents(url: base.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: false)!
        if !items.isEmpty { components.queryItems = items }

        var request = URLRequest(url: components.url!)
        request.httpMethod = endpoint.method.rawValue
        if let timeout = endpoint.timeout { request.timeoutInterval = timeout }

        switch endpoint.host {
        case .liveWire:
            for (name, value) in identity.headers { request.setValue(value, forHTTPHeaderField: name) }
        case .gigya:
            request.setValue(identity.userAgent, forHTTPHeaderField: "User-Agent")
        }
        if endpoint.isAuthorized, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        switch endpoint.body {
        case .none:
            break
        case .json(let value):
            request.httpBody = try JSONEncoder().encode(value)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        case .form(let fields):
            request.httpBody = RequestBody.formEncoded(fields)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}

extension Wire {
    /// Builds, sends and logs one call.
    func send<E: Endpoint>(_ endpoint: E, using configuration: APIConfiguration, token: String? = nil) async throws -> Response {
        let request = try configuration.urlRequest(for: endpoint, token: token)
        return try await perform(
            request,
            label: endpoint.label,
            redactRequestKeys: endpoint.logPolicy.redactedRequestKeys,
            logBodies: endpoint.logPolicy.logsBodies
        )
    }
}
