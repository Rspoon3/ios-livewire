import Foundation
import LWModels

/// Removes secrets and personal data from anything that is about to be written to a log file.
///
/// Masked: credentials and tokens, the VIN, and GPS positions. Everything else in a response is kept,
/// because the log exists so the API can be mapped from real responses.
///
/// Response bodies are logged on purpose (that is how the API gets mapped), so redaction is the
/// safety net: known secret keys are masked structurally, and anything shaped like a JWT or a
/// bearer token is masked wherever it appears in free text.
public enum Redactor {
    public static let mask = "<redacted>"

    /// Lowercased JSON keys whose values are never logged.
    public static let sensitiveKeys: Set<String> = [
        "password", "newpassword", "passwd",
        "jwt", "token", "accesstoken", "idtoken", "id_token", "refreshtoken",
        "sessiontoken", "sessionsecret", "cookievalue", "logintoken",
        "uid", "uidsignature", "signature",
        "authorization", "apikey", "secret", "cookie",
        "email", "loginid",
        // Identifies the bike, and so its owner.
        "vin",
        // Where the bike is, or has been.
        "latitude", "longitude", "lat", "lng", "lon", "coordinates", "polyline", "geometry",
        "locationhistory", "location",
    ]

    /// Largest body written to a log line. Larger bodies are cut and marked.
    public static let maxBodyCharacters = 64_000

    /// Masks sensitive keys at any depth. `extraKeys` are matched case-insensitively.
    public static func redact(_ value: JSONValue, extraKeys: Set<String> = []) -> JSONValue {
        let keys = sensitiveKeys.union(extraKeys.map { $0.lowercased() })
        return redact(value, keys: keys)
    }

    private static func redact(_ value: JSONValue, keys: Set<String>) -> JSONValue {
        switch value {
        case .object(let object):
            var result: [String: JSONValue] = [:]
            for (key, child) in object {
                result[key] = keys.contains(key.lowercased()) ? .string(mask) : redact(child, keys: keys)
            }
            return .object(result)
        case .array(let array):
            return .array(array.map { redact($0, keys: keys) })
        case .string(let text):
            return .string(scrubTokens(text))
        default:
            return value
        }
    }

    /// Compact, redacted, size-limited text for a request or response body.
    public static func redactedBody(
        _ data: Data,
        extraKeys: Set<String> = [],
        limit: Int = maxBodyCharacters
    ) -> String {
        if data.isEmpty { return "<empty>" }
        let text: String
        if let node = try? JSONDecoder().decode(JSONValue.self, from: data) {
            text = redact(node, extraKeys: extraKeys).compactString
        } else if let plain = String(data: data, encoding: .utf8) {
            text = scrubTokens(plain)
        } else {
            return "<\(data.count) bytes of binary data>"
        }
        if text.count > limit {
            return String(text.prefix(limit)) + "…<truncated \(text.count - limit) characters>"
        }
        return text
    }

    /// Masks JWTs and `Bearer` credentials in free text.
    public static func scrubTokens(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: #"eyJ[A-Za-z0-9_\-]{5,}\.[A-Za-z0-9_\-]{5,}\.[A-Za-z0-9_\-]*"#,
            with: mask,
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)bearer\s+[A-Za-z0-9._~+/=\-]{8,}"#,
            with: "Bearer \(mask)",
            options: .regularExpression
        )
        return result
    }
}
