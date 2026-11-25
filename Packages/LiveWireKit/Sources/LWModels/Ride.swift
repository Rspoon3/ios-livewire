import Foundation

/// A recorded or planned ride.
///
/// **Provisional.** The ride response shape has not been confirmed against live traffic yet, so
/// every field here is a best guess read out of `raw` with several candidate keys. The full JSON is
/// always kept in `raw` and written to the log file, so the real shape can be pulled off a device
/// and this type tightened (see `docs/logging.md`).
public struct RideSummary: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String?
    public var raw: JSONValue

    public init(id: String, name: String?, raw: JSONValue) {
        self.id = id
        self.name = name
        self.raw = raw
    }

    public init?(json: JSONValue) {
        guard let id = json.first(of: ["id", "rideId", "_id", "uuid"])?.textValue else { return nil }
        self.init(
            id: id,
            name: json.first(of: ["name", "title", "rideName"])?.textValue,
            raw: json
        )
    }

    public var displayName: String { name ?? "Ride \(id.prefix(8))" }

    public var subType: String? { raw.first(of: ["subType", "type"])?.textValue }

    public var startDate: Date? {
        raw.first(of: ["startTime", "startDate", "startedAt", "createdTime", "createdAt", "date"])?
            .textValue
            .flatMap(LenientDate.parse)
    }

    /// Distance as reported; the unit depends on the request's units parameter and is unconfirmed.
    public var distance: Double? {
        raw.first(of: ["distance", "totalDistance", "distanceInMiles", "distanceInKm"])?.doubleValue
    }
}

public enum LenientDate {
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Accepts ISO 8601 with or without fractional seconds, and the app's `+0000` offsets.
    public static func parse(_ text: String) -> Date? {
        if let date = withFraction.date(from: text) { return date }
        if let date = plain.date(from: text) { return date }
        let normalized = text.replacingOccurrences(
            of: #"([+-]\d{2})(\d{2})$"#,
            with: "$1:$2",
            options: .regularExpression
        )
        return plain.date(from: normalized) ?? withFraction.date(from: normalized)
    }
}
