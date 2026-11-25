import Foundation

/// Display text, built with Foundation's format styles.
public enum Display {
    /// `68%` from `68`. Battery levels and limits are percentages in the 0...100 range.
    public static func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    /// A distance in the reader's units (miles in the US, kilometres elsewhere).
    public static func distance(_ distance: Measurement<UnitLength>, fractionDigits: Int = 0) -> String {
        distance.formatted(.measurement(
            width: .abbreviated,
            usage: .road,
            numberFormatStyle: .number.precision(.fractionLength(0...fractionDigits))
        ))
    }

    public static func energy(_ energy: Measurement<UnitEnergy>, fractionDigits: Int = 0) -> String {
        energy.formatted(.measurement(
            width: .abbreviated,
            usage: .asProvided,
            numberFormatStyle: .number.precision(.fractionLength(0...fractionDigits))
        ))
    }

    /// A speed in the reader's units: mph in the US, km/h elsewhere.
    public static func speed(_ speed: Measurement<UnitSpeed>) -> String {
        let unit: UnitSpeed = Locale.current.measurementSystem == .us ? .milesPerHour : .kilometersPerHour
        return speed.converted(to: unit).formatted(.measurement(
            width: .abbreviated,
            usage: .asProvided,
            numberFormatStyle: .number.precision(.fractionLength(0))
        ))
    }

    /// `2 hours ago`
    public static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }

    /// `4 hr, 9 min`
    public static func duration(_ duration: Duration) -> String {
        duration.formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }
}
