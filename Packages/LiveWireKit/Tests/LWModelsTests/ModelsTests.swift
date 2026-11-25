import Foundation
import Testing

@testable import LWModels

@Suite struct BikeTests {
    @Test func displayNameFallsBack() {
        #expect(Bike(id: "7", name: "Mine").displayName == "Mine")
        #expect(Bike(id: "7", make: "LiveWire", model: "S2").displayName == "LiveWire S2")
        #expect(Bike(id: "7").displayName == "Bike 7")
    }

    @Test func roundTripsThroughTheSnapshotFile() throws {
        let bike = Bike(id: "7", vin: "TESTVIN", year: 2024, isPrimary: true, isPaired: true)
        let data = try JSONEncoder().encode(bike)
        #expect(try JSONDecoder().decode(Bike.self, from: data) == bike)
    }
}

@Suite struct ChargingStatusTests {
    @Test func reportAgeUnitsSeenOnARealBike() {
        #expect(ChargingStatus.age(amount: 10, unit: "seconds") == .seconds(10))
        #expect(ChargingStatus.age(amount: 1, unit: "minute") == .seconds(60))
        #expect(ChargingStatus.age(amount: 2, unit: "hours") == .seconds(7200))
        #expect(ChargingStatus.age(amount: 1, unit: "fortnight") == nil)
        #expect(ChargingStatus.age(amount: nil, unit: "minute") == nil)
    }

    @Test func survivesTheSnapshotFile() throws {
        let status = ChargingStatus(
            bikeID: "1", batteryLevel: 68, isCharging: true, chargeLimit: 80,
            timeToLimit: .seconds(2700),
            range: Measurement(value: 73, unit: .miles),
            odometer: Measurement(value: 162.2, unit: .miles),
            dataAge: .seconds(60), trackingStatus: "SAFE",
            fetchedAt: Date(timeIntervalSince1970: 1_767_323_045)
        )
        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(ChargingStatus.self, from: data)
        #expect(decoded == status)
        #expect(decoded.range?.unit == .miles)
    }

    @Test func distancesConvertWithMeasurement() {
        let status = ChargingStatus(bikeID: "1", range: Measurement(value: 100, unit: .miles))
        let kilometres = status.range?.converted(to: .kilometers).value ?? 0
        #expect(abs(kilometres - 160.9344) < 0.0001)
    }
}

@Suite struct DisplayTests {
    @Test func percent() {
        #expect(Display.percent(68) == "68%")
        #expect(Display.percent(67.6) == "68%")
    }

    @Test func duration() {
        #expect(Display.duration(.seconds(3600 * 4 + 60 * 9)).contains("4"))
    }
}

/// Invented numbers in the shape a real account returned on 2026-11-25.
@Suite struct AnalyticsTests {
    private static let rides = #"""
    {"bikeId":"1","vin":"TESTVIN","periods":[
      {"type":"MONTH","granularity":"WEEK","buckets":[
        {"bucketStart":"2026-11-01","rideCount":0,"sumBatteryUsedPercent":0,"totalDistance":0,"totalEfficiencykWhPerKm":null},
        {"bucketStart":"2026-11-08","rideCount":4,"sumBatteryUsedPercent":40,"totalDistance":30,"totalEfficiencykWhPerKm":0.1}],
       "summary":{"rideCount":4,"totalBatteryUsedPercent":40,"totalDistance":30,"totalDurationSeconds":3600,"totalEfficiencykWhPerKm":0.1}},
      {"type":"WEEK","granularity":"DAY","buckets":[],"summary":{"rideCount":0}},
      {"type":"SOMETHING_NEW","granularity":"HOUR","buckets":[],"summary":{}}
    ]}
    """#

    private static let charging = #"""
    {"bikeId":"1","periods":[
      {"type":"6M","granularity":"MONTH","buckets":[
        {"bucketStart":"2026-10-01","energyAddedKwh":2,"energyLostKwh":1,"sessionCount":1,"sumBatteryAddedPercent":19}],
       "summary":{"energyAddedKwh":2,"energyLostKwh":1,"sessionCount":1,"totalBatteryAddedPercent":19,"totalChargeTime":1958}}
    ]}
    """#

    @Test func rideAnalyticsParse() throws {
        let analytics = try JSONDecoder().decode(RideAnalytics.self, from: Data(Self.rides.utf8))
        #expect(analytics.bikeID == "1")
        #expect(analytics.periods.count == 3)

        let month = try #require(analytics.period(.month))
        #expect(month.bucketSize == .week)
        #expect(month.buckets.count == 2)
        #expect(month.buckets[0].efficiencyKWhPerKm == nil)
        #expect(month.buckets[1].rideCount == 4)
        #expect(month.buckets[1].start != nil)
        #expect(month.totals.distanceMiles == 30)
        #expect(month.totals.durationSeconds == 3600)
        // 0.1 kWh per km is 16.09344 kWh per 100 miles.
        let per100Miles = try #require(month.totals.energyPer100Miles)
        #expect(per100Miles.unit == .kilowattHours)
        #expect(abs(per100Miles.value - 16.09344) < 0.0001)
        #expect(month.totals.duration == .seconds(3600))
        #expect(month.totals.distance == Measurement(value: 30, unit: .miles))
    }

    @Test func unknownPeriodsAndGranularitiesAreKeptNotDropped() throws {
        let analytics = try JSONDecoder().decode(RideAnalytics.self, from: Data(Self.rides.utf8))
        let unknown = try #require(analytics.periods.last)
        #expect(unknown.type == "SOMETHING_NEW")
        #expect(unknown.period == nil)
        #expect(unknown.bucketSize == nil)
        // An empty summary is zeros, not a failure.
        #expect(unknown.totals.rideCount == 0)
    }

    @Test func chargingAnalyticsParse() throws {
        let analytics = try JSONDecoder().decode(ChargingAnalytics.self, from: Data(Self.charging.utf8))
        let sixMonths = try #require(analytics.period(.sixMonths))
        #expect(sixMonths.totals.sessionCount == 1)
        #expect(sixMonths.totals.energyAddedKWh == 2)
        #expect(sixMonths.totals.chargeTimeSeconds == 1958)
        #expect(sixMonths.buckets.first?.batteryAddedPercent == 19)
    }

    @Test func bucketDatesAreMidnightInTheCurrentTimeZone() throws {
        let date = try #require(AnalyticsDate.day("2026-11-01"))
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        #expect(parts.year == 2026 && parts.month == 11 && parts.day == 1)
        #expect(parts.hour == 0 && parts.minute == 0)
        #expect(AnalyticsDate.day("not a date") == nil)
    }

    @Test func aResponseWithoutPeriodsIsNotAnalytics() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RideAnalytics.self, from: Data(#"{"error":{"code":"3000"}}"#.utf8))
        }
    }
}
