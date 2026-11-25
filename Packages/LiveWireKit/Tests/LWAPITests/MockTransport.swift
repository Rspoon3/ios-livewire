import Foundation

@testable import LWAPI

/// Answers requests from a closure and records them. All fixtures in these tests are invented.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest, Int) -> (status: Int, body: String)

    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let handler: Handler

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    var requests: [URLRequest] { lock.withLock { recorded } }

    func requests(containing path: String) -> [URLRequest] {
        requests.filter { $0.url?.absoluteString.contains(path) == true }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let index = lock.withLock { () -> Int in
            recorded.append(request)
            return recorded.count - 1
        }
        let answer = handler(request, index)
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: nil, headerFields: nil)!
        return (Data(answer.body.utf8), response)
    }
}

enum Fixture {
    /// A made-up JWT (header.payload.signature) that is not valid for anything.
    static let jwt1 = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0LXVzZXItMSJ9.c2lnbmF0dXJlMQ"
    static let jwt2 = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0LXVzZXItMSJ9.c2lnbmF0dXJlMg"

    static let gigyaOK = #"{"errorCode":0,"UID":"test-uid-123","profile":{"email":"rider@example.com"},"sessionInfo":{"sessionToken":"gigya-session-secret"}}"#
    static let gigyaBadPassword = #"{"errorCode":403042,"errorMessage":"invalid loginID or password"}"#
    static func session(_ jwt: String) -> String { #"{"jwt":"\#(jwt)","termsAccepted":true}"# }

    /// The shapes are the ones a real bike returned on 2026-11-25; the values are invented.
    static let bikes = #"""
    {"bikes":[
      {"id":"101","vin":"TESTVIN0000000001","name":"Test Bike One","make":"LiveWire","model":"S2 Del Mar","modelCode":"X1","modelNumber":"0001","year":2024,"color":"Blue","colorCode":"B1","brandShortName":"LW","primaryBike":true,"pairingStatus":true,"createdTime":"2026-01-01 00:00:00+0000","modifiedTime":"2026-01-01 00:00:00+0000"},
      {"id":"102","vin":"TESTVIN0000000002","make":"LiveWire","model":"S2 Mulholland","year":2025,"primaryBike":false,"pairingStatus":false}
    ]}
    """#

    static let chargingOK = #"""
    {"bikeChargingData":{"batteryPercentage":82,"chargingStatus":false,"durationElapsed":"12","durationUnit":"minute",
      "maxLimit":80,"odometer":1840.2,"pluggedIn":false,"range":112.4,"timeToMaxLimit":"0.0"},"trackingStatus":"SAFE"}
    """#

    static let chargingPartial = #"""
    {"error":{"code":"-300","description":"Partial data"},"bikeChargingData":{"batteryPercentage":40}}
    """#

    static let notPaired = #"{"error":{"code":"3000","description":"Command manager api failed"}}"#
}
