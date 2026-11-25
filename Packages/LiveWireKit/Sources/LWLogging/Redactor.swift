import Foundation

/// Removes secrets and personal data from anything that is about to be written to a log file.
///
/// Masked: credentials and tokens, the VIN, cellular identifiers (the SIM's ICCID), and GPS positions. Everything else in a response is kept,
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
        // Identifies the bike, and so its owner, and the SIM card in its modem.
        "vin", "iccid", "imei", "imsi", "msisdn",
        // Where the bike is, or has been.
        "latitude", "longitude", "lat", "lng", "lon", "coordinates", "polyline", "geometry",
        "locationhistory", "location",
    ]

    /// Largest body written to a log line. Larger bodies are cut and marked.
    public static let maxBodyCharacters = 64_000

    /// Compact, redacted, size-limited text for a request or response body.
    ///
    /// JSON is masked structurally: sensitive keys are replaced at any depth, and strings are scrubbed
    /// for tokens. `extraKeys` are matched case-insensitively. Anything that is not JSON is scrubbed as text.
    public static func redactedBody(
        _ data: Data,
        extraKeys: Set<String> = [],
        limit: Int = maxBodyCharacters
    ) -> String {
        if data.isEmpty { return "<empty>" }
        let text: String
        if let tree = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            let keys = sensitiveKeys.union(extraKeys.map { $0.lowercased() })
            let masked = redact(tree, keys: keys)
            let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
            guard let output = try? JSONSerialization.data(withJSONObject: masked, options: options) else {
                return "<unprintable JSON, \(data.count) bytes>"
            }
            text = String(decoding: output, as: UTF8.self)
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

    private static func redact(_ value: Any, keys: Set<String>) -> Any {
        switch value {
        case let object as [String: Any]:
            return object.reduce(into: [String: Any]()) { result, pair in
                result[pair.key] = keys.contains(pair.key.lowercased()) ? mask : redact(pair.value, keys: keys)
            }
        case let array as [Any]:
            return array.map { redact($0, keys: keys) }
        case let text as String:
            return scrubTokens(text)
        default:
            return value
        }
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
