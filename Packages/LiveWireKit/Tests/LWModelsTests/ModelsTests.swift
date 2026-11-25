import Foundation
import Testing

@testable import LWModels

@Suite struct JSONValueTests {
    @Test func lenientAccessorsReadStringsAsNumbersAndBooleans() {
        let json = JSONValue(data: Data(#"{"a":"82","b":"true","c":1,"d":"0","e":"x"}"#.utf8))
        #expect(json["a"]?.doubleValue == 82)
        #expect(json["a"]?.intValue == 82)
        #expect(json["b"]?.boolValue == true)
        #expect(json["c"]?.boolValue == true)
        #expect(json["d"]?.boolValue == false)
        #expect(json["e"]?.boolValue == nil)
    }

    @Test func emptyAndNonJSONInput() {
        #expect(JSONValue(data: Data()) == .null)
        #expect(JSONValue(data: Data("  \n".utf8)) == .null)
        #expect(JSONValue(data: Data("<html>".utf8)) == .string("<html>"))
    }

    @Test func pathAndFirstOf() {
        let json = JSONValue(data: Data(#"{"x":{"y":{"z":3}},"id":null,"rideId":"r1"}"#.utf8))
        #expect(json.path("x", "y", "z")?.intValue == 3)
        #expect(json.path("x", "nope", "z") == nil)
        #expect(json.first(of: ["id", "rideId"])?.textValue == "r1")
    }

    @Test func numbersPrintWithoutTrailingZero() {
        #expect(JSONValue.number(100).textValue == "100")
        #expect(JSONValue.number(12.5).textValue == "12.5")
    }
}

@Suite struct ChargingStatusTests {
    @Test func parsesTheDocumentedShape() {
        let json = JSONValue(data: Data("""
        {"error":{"code":"0"},
         "trackingStatus":"SAFE",
         "bikeChargingData":{"batteryPercentage":"82","chargingStatus":"true","pluggedIn":true,
           "maxLimit":"90","timeToMaxLimit":"45","range":"112.4","odometer":"1840.2",
           "durationElapsed":"12","durationUnit":"MINUTES"}}
        """.utf8))
        let status = ChargingStatus(bikeID: "1", json: json)
        #expect(status.batteryLevel == 82)
        #expect(status.isCharging)
        #expect(status.isPluggedIn)
        #expect(status.chargeLimit == 90)
        #expect(status.minutesToLimit == 45)
        #expect(status.rangeMiles == 112.4)
        #expect(abs((status.rangeKilometers ?? 0) - 180.9) < 0.1)
        #expect(status.dataAge == 720)
        #expect(status.trackingStatus == "SAFE")
    }

    @Test func missingDataDoesNotCrash() {
        let status = ChargingStatus(bikeID: "1", json: .null)
        #expect(status.batteryLevel == nil)
        #expect(!status.isCharging)
        #expect(status.chargeLimit == nil)
    }

    @Test func zeroChargeLimitMeansUnset() {
        let json = JSONValue(data: Data(#"{"bikeChargingData":{"maxLimit":"0"}}"#.utf8))
        #expect(ChargingStatus(bikeID: "1", json: json).chargeLimit == nil)
    }
}

@Suite struct BikeAndRideTests {
    @Test func bikeParsesNumbersAndPairing() {
        let json = JSONValue(data: Data(#"{"id":42,"vin":"TESTVIN0000000001","name":"Test Bike","year":"2024","primaryBike":"true","pairingStatus":false}"#.utf8))
        let bike = Bike(json: json)
        #expect(bike?.id == "42")
        #expect(bike?.year == 2024)
        #expect(bike?.isPrimary == true)
        #expect(bike?.isPaired == false)
        #expect(bike?.displayName == "Test Bike")
    }

    @Test func bikeWithoutIdIsRejected() {
        #expect(Bike(json: JSONValue(data: Data(#"{"name":"x"}"#.utf8))) == nil)
    }

    @Test func displayNameFallsBack() {
        #expect(Bike(id: "7", make: "LiveWire", model: "S2").displayName == "LiveWire S2")
        #expect(Bike(id: "7").displayName == "Bike 7")
    }

    @Test func rideKeepsRawAndGuessesFields() {
        let json = JSONValue(data: Data(#"{"rideId":"abc","name":"Morning loop","createdTime":"2026-01-02T03:04:05+0000","distance":"12.5"}"#.utf8))
        let ride = RideSummary(json: json)
        #expect(ride?.id == "abc")
        #expect(ride?.displayName == "Morning loop")
        #expect(ride?.distance == 12.5)
        #expect(ride?.startDate == Date(timeIntervalSince1970: 1_767_323_045))
        #expect(ride?.raw == json)
    }

    @Test func lenientDates() {
        #expect(LenientDate.parse("2026-01-02T03:04:05Z") != nil)
        #expect(LenientDate.parse("2026-01-02T03:04:05.123Z") != nil)
        #expect(LenientDate.parse("2026-01-02T03:04:05+0000") != nil)
        #expect(LenientDate.parse("not a date") == nil)
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
        let analytics = try #require(RideAnalytics(json: JSONValue(data: Data(Self.rides.utf8))))
        #expect(analytics.bikeID == "1")
        #expect(analytics.periods.count == 3)

        let month = try #require(analytics.period(.month))
        #expect(month.granularity == .week)
        #expect(month.buckets.count == 2)
        #expect(month.buckets[0].efficiencyKWhPerKm == nil)
        #expect(month.buckets[1].rideCount == 4)
        #expect(month.buckets[1].start != nil)
        #expect(month.totals.distanceMiles == 30)
        #expect(month.totals.durationSeconds == 3600)
        // 0.1 kWh/km is 160.9 Wh/mi.
        #expect(abs((month.totals.efficiencyWhPerMile ?? 0) - 160.9344) < 0.001)
    }

    @Test func unknownPeriodsAndGranularitiesAreKeptNotDropped() throws {
        let analytics = try #require(RideAnalytics(json: JSONValue(data: Data(Self.rides.utf8))))
        let unknown = try #require(analytics.periods.last)
        #expect(unknown.rawType == "SOMETHING_NEW")
        #expect(unknown.period == nil)
        #expect(unknown.granularity == nil)
        // An empty summary is zeros, not a failure.
        #expect(unknown.totals.rideCount == 0)
    }

    @Test func chargingAnalyticsParse() throws {
        let analytics = try #require(ChargingAnalytics(json: JSONValue(data: Data(Self.charging.utf8))))
        let sixMonths = try #require(analytics.period(.sixMonths))
        #expect(sixMonths.totals.sessionCount == 1)
        #expect(sixMonths.totals.energyAddedKWh == 2)
        #expect(sixMonths.totals.chargeTimeSeconds == 1958)
        #expect(sixMonths.buckets.first?.batteryAddedPercent == 19)
    }

    @Test func aResponseWithoutPeriodsIsNotAnalytics() {
        #expect(RideAnalytics(json: JSONValue(data: Data(#"{"error":{"code":"3000"}}"#.utf8))) == nil)
    }

    @Test func chargingStatusUnitsSeenOnARealBike() {
        #expect(ChargingStatus.age(amount: 10, unit: "seconds") == 10)
        #expect(ChargingStatus.age(amount: 1, unit: "minute") == 60)
    }
}
