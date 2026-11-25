import Foundation

/// A loosely typed JSON value.
///
/// The LiveWire backend is undocumented and inconsistent: numbers often arrive as strings,
/// booleans as `"true"`, and errors as HTTP 200 envelopes. Models in this package therefore
/// parse from `JSONValue` with lenient accessors instead of strict `Codable` synthesis, and keep
/// the original value around (`raw`) so nothing is lost while the API is still being mapped.
public enum JSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: Codable

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    // MARK: Parsing

    /// Parses JSON bytes. Empty input is `.null`; text that is not JSON becomes `.string`.
    public init(data: Data) {
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
            self = .null
        } else if let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
            self = value
        } else {
            self = .string(String(decoding: data, as: UTF8.self))
        }
    }

    // MARK: Navigation

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    public subscript(index: Int) -> JSONValue? {
        if case .array(let array) = self, array.indices.contains(index) { return array[index] }
        return nil
    }

    /// Walks nested objects: `value.path("bikeChargingData", "batteryPercentage")`.
    public func path(_ keys: String...) -> JSONValue? {
        var current: JSONValue? = self
        for key in keys {
            current = current?[key]
        }
        return current
    }

    /// First present value among several candidate keys. Used where field names are not yet confirmed.
    public func first(of keys: [String]) -> JSONValue? {
        for key in keys {
            if let value = self[key], value != .null { return value }
        }
        return nil
    }

    // MARK: Lenient accessors

    public var isNull: Bool { self == .null }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    /// A string for strings, numbers and booleans. `nil` for everything else, and for empty strings.
    public var textValue: String? {
        switch self {
        case .string(let value): value.isEmpty ? nil : value
        case .number(let value): Self.format(value)
        case .bool(let value): value ? "true" : "false"
        default: nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .number(let value): value
        case .string(let value): Double(value.trimmingCharacters(in: .whitespaces))
        case .bool(let value): value ? 1 : 0
        default: nil
        }
    }

    public var intValue: Int? {
        guard let value = doubleValue, value.isFinite else { return nil }
        return Int(value)
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let value): value
        case .number(let value): value != 0
        case .string(let value):
            switch value.lowercased() {
            case "true", "yes", "1", "y": true
            case "false", "no", "0", "n": false
            default: nil
            }
        default: nil
        }
    }

    // MARK: Output

    public var compactString: String { render(pretty: false) }
    public var prettyString: String { render(pretty: true) }

    private func render(pretty: Bool) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 { return String(Int64(value)) }
        return String(value)
    }
}
