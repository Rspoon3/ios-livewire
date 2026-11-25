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

    static let bikes = #"""
    {"bikes":[
      {"id":101,"vin":"TESTVIN0000000001","name":"Test Bike One","make":"LiveWire","model":"S2 Del Mar","modelCode":"X1","year":"2024","primaryBike":true,"pairingStatus":true},
      {"id":102,"vin":"TESTVIN0000000002","make":"LiveWire","model":"S2 Mulholland","year":2025,"primaryBike":false,"pairingStatus":"false"}
    ]}
    """#

    static let chargingOK = #"""
    {"error":{"code":"0","description":"Success"},"trackingStatus":"SAFE",
     "bikeChargingData":{"batteryPercentage":"82","chargingStatus":"false","pluggedIn":"false","maxLimit":"100",
       "timeToMaxLimit":"0","range":"112.4","odometer":"1840.2","durationElapsed":"12","durationUnit":"MINUTES"}}
    """#

    static let chargingPartial = #"""
    {"error":{"code":"-300","description":"Partial data"},"bikeChargingData":{"batteryPercentage":"40"}}
    """#

    static let notPaired = #"{"error":{"code":"3000","description":"Command manager api failed"}}"#

    static let rides = #"""
    {"rides":[{"id":"ride-1","name":"Morning loop","type":"CUSTOM","subType":"RECORDED","distance":12.5},{"rideId":"ride-2"}]}
    """#
}
