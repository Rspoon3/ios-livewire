import Foundation

public enum LiveWireAPIError: Error, Equatable, Sendable, LocalizedError {
    /// No stored credentials. Sign in first.
    case notSignedIn
    /// Gigya rejected the email or password (or the account still needs setup).
    case invalidCredentials(String)
    /// Gigya failed for another reason (rate limit, captcha, outage). Retrying later may work.
    case gigya(code: Int, message: String)
    /// The session endpoint did not return a token.
    case sessionFailed(String)
    /// HTTP-level failure.
    case http(status: Int, message: String)
    /// The backend's error envelope: `{"error": {"code": …, "description": …}}`, usually with HTTP 200.
    case api(code: String, message: String, status: Int)
    /// Code 3000: this device UUID is not paired with the bike, or the bike is unreachable.
    case notPaired(String)
    /// Pairing flow failure (wrong code, bike not ready, no cellular signal, …).
    case pairing(String)
    /// The response did not look like what the endpoint is documented to return.
    case unexpectedResponse(String)
    case secureStorage(String)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn: "You are not signed in."
        case .invalidCredentials(let message): message
        case .gigya(_, let message): "Sign-in service error: \(message)"
        case .sessionFailed(let message): "Could not start a session: \(message)"
        case .http(let status, let message): "HTTP \(status): \(message)"
        case .api(let code, let message, _): "\(message) (code \(code))"
        case .notPaired(let message): message
        case .pairing(let message): message
        case .unexpectedResponse(let message): "Unexpected response: \(message)"
        case .secureStorage(let message): message
        }
    }
}
