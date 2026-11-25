import Foundation

/// The last GPS position the bike reported, from `bike/{id}/location`.
///
/// Confirmed against a real bike on 2026-11-25 (see docs/api.md).
public struct BikeLocation: Codable, Sendable, Hashable {
    public var latitude: Double
    public var longitude: Double
    public var altitude: Measurement<UnitLength>?
    public var speed: Measurement<UnitSpeed>?
    /// When the GPS took the fix.
    public var gpsTime: Date?
    /// When the bike's modem sent the report. How stale the position is.
    public var reportedAt: Date?
    public var fixType: Int?

    public init(
        latitude: Double,
        longitude: Double,
        altitude: Measurement<UnitLength>? = nil,
        speed: Measurement<UnitSpeed>? = nil,
        gpsTime: Date? = nil,
        reportedAt: Date? = nil,
        fixType: Int? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speed = speed
        self.gpsTime = gpsTime
        self.reportedAt = reportedAt
        self.fixType = fixType
    }

    /// The best statement of when the bike was at this position.
    public var lastSeen: Date? { gpsTime ?? reportedAt }
}
