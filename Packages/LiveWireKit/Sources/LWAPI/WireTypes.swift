import Foundation
import LWModels

// The JSON the backend sends and receives, as plain `Codable` structs. Each type is the shape that
// was seen on a real bike (see docs/api.md), and `Wire.Response.decode` turns a mismatch into a
// `LiveWireAPIError.unexpectedResponse` that names the field.

extension KeyedDecodingContainer {
    /// A number the backend sends either as a JSON number or as a string (`"10"`, `"0.0"`).
    /// Returns `nil` when the key is missing or null, and throws when the text is not a number.
    func decodeNumberIfPresent(forKey key: Key) throws -> Double? {
        if let number = try? decode(Double.self, forKey: key) { return number }
        guard let text = try decodeIfPresent(String.self, forKey: key) else { return nil }
        guard let number = Double(text.trimmingCharacters(in: .whitespaces)) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "\"\(text)\" is not a number")
        }
        return number
    }
}

// MARK: Errors

/// `{"error": {"code": "3000", "description": "..."}}`, which usually arrives with HTTP 200.
struct ErrorEnvelope: Decodable, Sendable {
    struct Detail: Decodable, Sendable {
        let code: String?
        let description: String?
        let message: String?

        private enum CodingKeys: String, CodingKey { case code, description, message }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // The code is a string ("3000") but has been seen as a number elsewhere.
            if let text = try? container.decodeIfPresent(String.self, forKey: .code) {
                code = text
            } else if let number = try? container.decodeIfPresent(Int.self, forKey: .code) {
                code = String(number)
            } else {
                code = nil
            }
            description = try? container.decodeIfPresent(String.self, forKey: .description)
            message = try? container.decodeIfPresent(String.self, forKey: .message)
        }
    }

    let error: Detail?
}

/// The fields an HTTP error body may carry its explanation in.
struct HTTPErrorBody: Decodable, Sendable {
    let description: String?
    let detail: String?
    let message: String?
    let title: String?

    var text: String? { description ?? detail ?? message ?? title }
}

// MARK: Sign-in

struct GigyaLoginResponse: Decodable, Sendable {
    let errorCode: Int?
    let errorMessage: String?
    let uid: String?

    private enum CodingKeys: String, CodingKey {
        case errorCode, errorMessage
        case uid = "UID"
    }
}

struct SessionRequest: Encodable, Sendable {
    let uid: String
    let deviceUUID: String
    let dataCenter: String

    private enum CodingKeys: String, CodingKey {
        case uid = "UID"
        case deviceUUID, dataCenter
    }
}

struct SessionResponse: Decodable, Sendable {
    let jwt: String?
    let termsAccepted: Bool?
}

// MARK: Bikes and pairing

struct BikesResponse: Decodable, Sendable {
    let bikes: [BikeResponse]
}

/// One bike in `getAllbikes/pairingStatus`.
struct BikeResponse: Decodable, Sendable {
    let id: String
    let vin: String?
    let name: String?
    let make: String?
    let model: String?
    let modelCode: String?
    let modelNumber: String?
    let year: Int?
    let color: String?
    let primaryBike: Bool?
    /// Whether **this device UUID** is paired, not whether the bike has any pairing.
    let pairingStatus: Bool?

    var bike: Bike {
        Bike(
            id: id, vin: vin, name: name, make: make, model: model, modelCode: modelCode,
            modelNumber: modelNumber, year: year, color: color,
            isPrimary: primaryBike ?? false, isPaired: pairingStatus
        )
    }
}

struct PairingStatusResponse: Decodable, Sendable {
    let pairingStatus: Bool
}

struct VerifyCodeRequest: Encodable, Sendable {
    let code: String
}

/// The answer to a pairing command: `pair` and `verify/code` both use it. `status` is 200 when the
/// bike took the command and 402 when it did not answer. `code` is only sent for a wrong code (4004)
/// or too many tries (4003).
struct PairingCommandResponse: Decodable, Sendable {
    let commandName: String?
    /// A JSON document inside a string; see `PairingDetail`.
    let detail: String?
    let pairedUserCount: Int?
    let status: Int?
    let code: Int?

    private enum CodingKeys: String, CodingKey {
        case commandName = "command_name"
        case detail, pairedUserCount, status, code
    }

    var parsedDetail: PairingDetail? {
        detail.flatMap { try? JSONDecoder().decode(PairingDetail.self, from: Data($0.utf8)) }
    }
}

struct PairingDetail: Decodable, Sendable {
    let reason: String?
    let message: String?
}

// MARK: Location

/// `{"data": {"latitude": …, "longitude": …, "altitude": …, "speed_km": …, "gps_time": …,
/// "tcu_timestamp": …, "fix_type": …}}`, confirmed on a real bike. The response also carries `vin`,
/// `iccid` and `viot_timestamp`, which are not decoded. Every field but the two coordinates may be
/// missing, because a bike that has not reported yet may have no `data`.
struct LocationResponse: Decodable, Sendable {
    struct Reading: Decodable, Sendable {
        let latitude: Double?
        let longitude: Double?
        let altitude: Double?
        let speedKmh: Double?
        let gpsTime: Date?
        let reportedAt: Date?
        let fixType: Int?

        private enum CodingKeys: String, CodingKey {
            case latitude, longitude, altitude
            case speedKmh = "speed_km"
            case gpsTime = "gps_time"
            case reportedAt = "tcu_timestamp"
            case fixType = "fix_type"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            latitude = try container.decodeNumberIfPresent(forKey: .latitude)
            longitude = try container.decodeNumberIfPresent(forKey: .longitude)
            altitude = try container.decodeNumberIfPresent(forKey: .altitude)
            speedKmh = try container.decodeNumberIfPresent(forKey: .speedKmh)
            gpsTime = try container.decodeTimeIfPresent(forKey: .gpsTime)
            reportedAt = try container.decodeTimeIfPresent(forKey: .reportedAt)
            fixType = try container.decodeNumberIfPresent(forKey: .fixType).map { Int($0) }
        }
    }

    let data: Reading?

    /// `nil` when the bike has not reported a position.
    var location: BikeLocation? {
        guard let reading = data, let latitude = reading.latitude, let longitude = reading.longitude else { return nil }
        return BikeLocation(
            latitude: latitude,
            longitude: longitude,
            altitude: reading.altitude.map { Measurement(value: $0, unit: UnitLength.meters) },
            speed: reading.speedKmh.map { Measurement(value: $0, unit: UnitSpeed.kilometersPerHour) },
            gpsTime: reading.gpsTime,
            reportedAt: reading.reportedAt,
            fixType: reading.fixType
        )
    }
}

extension KeyedDecodingContainer {
    /// A point in time that may be text (`2026-11-25T18:00:00Z`, `2026-11-19 03:02:28+0000`) or a number
    /// of seconds or milliseconds since 1970. Returns `nil` when the key is missing, null, or not a
    /// time this recognizes.
    func decodeTimeIfPresent(forKey key: Key) throws -> Date? {
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            return WireDate.parse(text)
        }
        if let number = try? decodeIfPresent(Double.self, forKey: key) {
            // Anything past the year 5138 in seconds is really milliseconds.
            let seconds = number > 100_000_000_000
                ? Measurement(value: number, unit: UnitDuration.milliseconds).converted(to: .seconds).value
                : number
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }
}

enum WireDate {
    private static let dateTimeWithOffset = Date.ISO8601FormatStyle()
        .year().month().day()
        .dateTimeSeparator(.space)
        .time(includingFractionalSeconds: false)
        .timeZone(separator: .omitted)

    /// The forms the backend has used for times: ISO 8601 with or without fractional seconds, and the
    /// `2026-11-19 03:02:28+0000` form seen in the bike list.
    static func parse(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle()) { return date }
        return try? Date(text, strategy: dateTimeWithOffset)
    }
}

// MARK: Charging status

struct ChargingStatusResponse: Decodable, Sendable {
    struct Reading: Decodable, Sendable {
        let batteryPercentage: Double?
        let chargingStatus: Bool?
        let pluggedIn: Bool?
        /// Percent. 0 means no limit was reported.
        let maxLimit: Int?
        let timeToMaxLimit: Double?
        let range: Double?
        let odometer: Double?
        /// How old the bike's own report was, with its unit in `durationUnit`.
        let durationElapsed: Double?
        let durationUnit: String?

        private enum CodingKeys: String, CodingKey {
            case batteryPercentage, chargingStatus, pluggedIn, maxLimit, timeToMaxLimit
            case range, odometer, durationElapsed, durationUnit
        }

        // The backend sends `durationElapsed` and `timeToMaxLimit` as strings, and may do the same
        // for the other numbers, so they go through `decodeNumberIfPresent`.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            batteryPercentage = try container.decodeNumberIfPresent(forKey: .batteryPercentage)
            chargingStatus = try container.decodeIfPresent(Bool.self, forKey: .chargingStatus)
            pluggedIn = try container.decodeIfPresent(Bool.self, forKey: .pluggedIn)
            maxLimit = try container.decodeNumberIfPresent(forKey: .maxLimit).map { Int($0.rounded()) }
            timeToMaxLimit = try container.decodeNumberIfPresent(forKey: .timeToMaxLimit)
            range = try container.decodeNumberIfPresent(forKey: .range)
            odometer = try container.decodeNumberIfPresent(forKey: .odometer)
            durationElapsed = try container.decodeNumberIfPresent(forKey: .durationElapsed)
            durationUnit = try container.decodeIfPresent(String.self, forKey: .durationUnit)
        }
    }

    let bikeChargingData: Reading?
    let trackingStatus: String?

    func status(bikeID: String, fetchedAt: Date = Date()) -> ChargingStatus {
        let reading = bikeChargingData
        return ChargingStatus(
            bikeID: bikeID,
            batteryLevel: reading?.batteryPercentage,
            isCharging: reading?.chargingStatus ?? false,
            isPluggedIn: reading?.pluggedIn ?? false,
            chargeLimit: reading?.maxLimit.flatMap { $0 == 0 ? nil : $0 },
            timeToLimit: reading?.timeToMaxLimit.map { Duration(Measurement(value: $0, unit: UnitDuration.minutes)) },
            range: reading?.range.map { Measurement(value: $0, unit: UnitLength.miles) },
            odometer: reading?.odometer.map { Measurement(value: $0, unit: UnitLength.miles) },
            dataAge: ChargingStatus.age(amount: reading?.durationElapsed, unit: reading?.durationUnit),
            trackingStatus: trackingStatus,
            fetchedAt: fetchedAt
        )
    }
}
