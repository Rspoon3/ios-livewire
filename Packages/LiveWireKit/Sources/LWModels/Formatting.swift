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

    /// `4 hr, 9 min`
    public static func duration(_ duration: Duration) -> String {
        duration.formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }
}
