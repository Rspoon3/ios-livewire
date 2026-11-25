import Foundation
import LWLogging

/// Sends one request and writes the exchange to the log file.
///
/// This is where the "feed the logs back to me" loop is fed: every request and every response body
/// goes to the persistent log, with secrets masked by `Redactor`.
struct Wire: Sendable {
    let transport: any HTTPTransport
    let log: LWLogger

    struct Response: Sendable {
        let status: Int
        let data: Data
        /// What the request was, for error messages, e.g. `GET bikes/123/charging/status`.
        let label: String

        /// Decodes the body, or explains which part of it did not match.
        func decode<T: Decodable>(_ type: T.Type = T.self) throws -> T {
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch let error as DecodingError {
                throw LiveWireAPIError.unexpectedResponse("\(label): \(error.summary)")
            }
        }
    }

    /// - Parameters:
    ///   - label: what to print, e.g. `GET bikes/123/charging/status`. Must not contain secrets.
    ///   - redactRequestKeys: extra JSON keys to mask in the request body (e.g. `code` while pairing).
    ///   - logBodies: set to `false` for Gigya, whose responses carry session secrets and profile data.
    func perform(
        _ request: URLRequest,
        label: String,
        redactRequestKeys: Set<String> = [],
        logBodies: Bool = true
    ) async throws -> Response {
        var line = "→ \(label)"
        if logBodies, let body = request.httpBody {
            line += " body=\(Redactor.redactedBody(body, extraKeys: redactRequestKeys))"
        }
        log.debug(line)

        let clock = ContinuousClock()
        let start = clock.now
        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await transport.send(request)
        } catch is CancellationError {
            log.warning("✗ \(label) cancelled after \(Self.milliseconds(since: start, clock: clock)) ms (no response received)")
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            log.warning("✗ \(label) cancelled after \(Self.milliseconds(since: start, clock: clock)) ms (no response received)")
            throw error
        } catch {
            log.error("✗ \(label) failed after \(Self.milliseconds(since: start, clock: clock)) ms: \(error)")
            throw error
        }

        let elapsed = Self.milliseconds(since: start, clock: clock)
        if logBodies {
            log.info("← \(http.statusCode) \(label) (\(elapsed) ms) body=\(Redactor.redactedBody(data))")
        } else {
            log.info("← \(http.statusCode) \(label) (\(elapsed) ms) [\(data.count) bytes, body not logged]")
        }
        return Response(status: http.statusCode, data: data, label: label)
    }

    private static func milliseconds(since start: ContinuousClock.Instant, clock: ContinuousClock) -> Int {
        let duration = start.duration(to: clock.now)
        return Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }
}

extension DecodingError {
    /// A one-line description with the path to the field, e.g. `bikes[0].id is missing`.
    var summary: String {
        func path(_ context: Context) -> String {
            context.codingPath.reduce("") { text, key in
                if let index = key.intValue { return text + "[\(index)]" }
                return text.isEmpty ? key.stringValue : text + "." + key.stringValue
            }
        }
        switch self {
        case .keyNotFound(let key, let context):
            let parent = path(context)
            return "\(parent.isEmpty ? "" : parent + ".")\(key.stringValue) is missing"
        case .valueNotFound(_, let context):
            return "\(path(context)) is null"
        case .typeMismatch(_, let context):
            return "\(path(context)) has the wrong type"
        case .dataCorrupted(let context):
            let where_ = path(context)
            return where_.isEmpty ? "the body is not valid JSON" : "\(where_) is not valid"
        @unknown default:
            return "could not be decoded"
        }
    }
}
