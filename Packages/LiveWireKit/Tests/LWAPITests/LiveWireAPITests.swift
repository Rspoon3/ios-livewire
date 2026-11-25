import Foundation
import LWModels
import LWSecureStorage
import Testing

@testable import LWAPI

private let config = APIConfiguration(gigyaAPIKey: "TEST_KEY")

/// Routes the happy path: Gigya, session, then whatever `api` returns for the path.
private func router(
    api: @escaping @Sendable (String, Int) -> (status: Int, body: String)
) -> MockTransport.Handler {
    { request, index in
        let url = request.url!.absoluteString
        if url.contains("accounts.login") { return (200, Fixture.gigyaOK) }
        if url.contains("/session") { return (200, Fixture.session(Fixture.jwt1)) }
        return api(url, index)
    }
}

@Suite struct SignInTests {
    @Test func storesUIDAndTokenButNeverThePassword() async throws {
        let secrets = InMemorySecretStore()
        let transport = MockTransport(router { _, _ in (200, "{}") })
        let api = LiveWireAPI(configuration: config, secrets: secrets, transport: transport)

        try await api.signIn(email: "rider@example.com", password: "p@ss+word&1")

        #expect(try secrets.string(for: .gigyaUID) == "test-uid-123")
        #expect(try secrets.string(for: .sessionToken) == Fixture.jwt1)
        #expect(try secrets.string(for: .deviceUUID) != nil)
        #expect(await api.isSignedIn())

        let gigya = try #require(transport.requests(containing: "accounts.login").first)
        let gigyaData = try #require(gigya.httpBody)
        let body = String(decoding: gigyaData, as: UTF8.self)
        #expect(body.contains("apiKey=TEST_KEY"))
        #expect(body.contains("loginID=rider%40example.com"))
        #expect(body.contains("password=p%40ss%2Bword%261"), "special characters must be form-encoded")
        #expect(gigya.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")

        let session = try #require(transport.requests(containing: "/session").first)
        #expect(session.url?.query?.contains("brand=LiveWire") == true)
        let sessionData = try #require(session.httpBody)
        let sessionBody = try #require(JSONSerialization.jsonObject(with: sessionData) as? [String: String])
        let storedUUID = try secrets.string(for: .deviceUUID)
        #expect(sessionBody["UID"] == "test-uid-123")
        #expect(sessionBody["dataCenter"] == "us1")
        #expect(sessionBody["deviceUUID"] == storedUUID)
    }

    @Test func wrongPasswordIsAnInvalidCredentialsError() async throws {
        let transport = MockTransport { _, _ in (200, Fixture.gigyaBadPassword) }
        let api = LiveWireAPI(configuration: config, secrets: InMemorySecretStore(), transport: transport)
        await #expect(throws: LiveWireAPIError.self) {
            try await api.signIn(email: "a@b.c", password: "bad")
        }
        #expect(await api.isSignedIn() == false)
    }

    @Test func signOutKeepsTheDeviceUUIDSoPairingSurvives() async throws {
        let secrets = InMemorySecretStore()
        let api = LiveWireAPI(configuration: config, secrets: secrets, transport: MockTransport(router { _, _ in (200, "{}") }))
        try await api.signIn(email: "a@b.c", password: "x")
        let uuid = try secrets.string(for: .deviceUUID)
        try await api.signOut()
        #expect(try secrets.string(for: .gigyaUID) == nil)
        #expect(try secrets.string(for: .sessionToken) == nil)
        #expect(try secrets.string(for: .deviceUUID) == uuid)
    }

    @Test func theAppMakesItsOwnLowercaseDeviceUUIDAndKeepsIt() async throws {
        let secrets = InMemorySecretStore()
        let api = LiveWireAPI(configuration: config, secrets: secrets, transport: MockTransport(router { _, _ in (200, "{}") }))
        let first = try await api.deviceUUID()
        #expect(first == first.lowercased())
        #expect(UUID(uuidString: first) != nil)
        #expect(try await api.deviceUUID() == first)
        #expect(try secrets.string(for: .deviceUUID) == first)
    }

    @Test func anUppercaseUUIDFromAnEarlyBuildIsReplaced() async throws {
        let old = "F341AF78-7CB8-444C-B4AA-6D497500F6FA"
        let secrets = InMemorySecretStore([.deviceUUID: old])
        let api = LiveWireAPI(configuration: config, secrets: secrets, transport: MockTransport(router { _, _ in (200, "{}") }))
        let replaced = try await api.deviceUUID()
        #expect(replaced == replaced.lowercased())
        #expect(replaced != old.lowercased())
        #expect(try await api.deviceUUID() == replaced)
    }

    @Test func callsWithoutSigningInFail() async {
        let api = LiveWireAPI(configuration: config, secrets: InMemorySecretStore(), transport: MockTransport { _, _ in (200, "{}") })
        await #expect(throws: LiveWireAPIError.notSignedIn) { try await api.bikes() }
    }
}

@Suite struct EndpointTests {
    private func signedInAPI(_ api: @escaping @Sendable (String, Int) -> (status: Int, body: String)) async throws -> (LiveWireAPI, MockTransport, InMemorySecretStore) {
        let secrets = InMemorySecretStore()
        let transport = MockTransport(router(api: api))
        let client = LiveWireAPI(configuration: config, secrets: secrets, transport: transport)
        try await client.signIn(email: "a@b.c", password: "x")
        return (client, transport, secrets)
    }

    @Test func bikesSendsDeviceUUIDAndParsesBothBikes() async throws {
        let (api, transport, secrets) = try await signedInAPI { _, _ in (200, Fixture.bikes) }
        let bikes = try await api.bikes()
        #expect(bikes.map(\.id) == ["101", "102"])
        #expect(bikes[0].isPaired == true)
        #expect(bikes[1].isPaired == false)
        #expect(bikes[0].isPrimary)

        let request = try #require(transport.requests(containing: "getAllbikes/pairingStatus").first)
        let query = request.url?.query ?? ""
        let deviceUUID = try #require(try secrets.string(for: .deviceUUID))
        #expect(query.contains("deviceUUID=\(deviceUUID)"))
        #expect(query.contains("brand=LiveWire"))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Fixture.jwt1)")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Android")
    }

    @Test func chargingStatusParses() async throws {
        let (api, transport, _) = try await signedInAPI { _, _ in (200, Fixture.chargingOK) }
        let status = try await api.chargingStatus(bikeID: "101")
        #expect(status.batteryLevel == 82)
        #expect(status.isCharging == false)
        #expect(status.chargeLimit == 80)
        #expect(status.rangeMiles == 112.4)
        #expect(status.dataAge == 720)
        #expect(transport.requests(containing: "bikes/101/charging/status").count == 1)
    }

    @Test func partialAnswerCode300StillReturnsData() async throws {
        let (api, _, _) = try await signedInAPI { _, _ in (200, Fixture.chargingPartial) }
        #expect(try await api.chargingStatus(bikeID: "101").batteryLevel == 40)
    }

    @Test func code3000MeansNotPaired() async throws {
        let (api, _, _) = try await signedInAPI { _, _ in (200, Fixture.notPaired) }
        do {
            _ = try await api.chargingStatus(bikeID: "101")
            Issue.record("expected notPaired")
        } catch let error as LiveWireAPIError {
            guard case .notPaired = error else { Issue.record("wrong error: \(error)"); return }
        }
    }

    @Test func otherEnvelopeErrorsAreReported() async throws {
        let (api, _, _) = try await signedInAPI { _, _ in (200, #"{"error":{"code":"9999","description":"Boom"}}"#) }
        await #expect(throws: LiveWireAPIError.api(code: "9999", message: "Boom", status: 200)) {
            try await api.bikes()
        }
    }

    @Test func expiredTokenIsRenewedOnceAndTheRequestRetried() async throws {
        let counter = Counter()
        let secrets = InMemorySecretStore()
        let transport = MockTransport { request, _ in
            let url = request.url!.absoluteString
            if url.contains("accounts.login") { return (200, Fixture.gigyaOK) }
            if url.contains("/session") {
                return (200, Fixture.session(counter.next() == 0 ? Fixture.jwt1 : Fixture.jwt2))
            }
            // The first token is rejected, the second accepted.
            let auth = request.value(forHTTPHeaderField: "Authorization")
            return auth == "Bearer \(Fixture.jwt2)" ? (200, Fixture.bikes) : (401, #"{"message":"expired"}"#)
        }
        let api = LiveWireAPI(configuration: config, secrets: secrets, transport: transport)
        try await api.signIn(email: "a@b.c", password: "x")

        let bikes = try await api.bikes()
        #expect(bikes.count == 2)
        #expect(transport.requests(containing: "/session").count == 2)
        #expect(transport.requests(containing: "accounts.login").count == 1, "renewal must not need the password")
        #expect(try secrets.string(for: .sessionToken) == Fixture.jwt2)
    }

    @Test func pairingFlow() async throws {
        let (api, transport, _) = try await signedInAPI { url, _ in
            if url.contains("101/pair?") { return (200, #"{"status":200}"#) }
            if url.contains("verify/code") { return (200, #"{"error":{"code":"0"}}"#) }
            return (200, #"{"pairingStatus":true}"#)
        }
        try await api.requestPairingCode(bikeID: "101")
        try await api.verifyPairingCode(bikeID: "101", code: "123456")
        #expect(try await api.isPaired(bikeID: "101"))

        let verify = try #require(transport.requests(containing: "verify/code").first)
        let verifyData = try #require(verify.httpBody)
        let body = try JSONSerialization.jsonObject(with: verifyData) as? [String: String]
        #expect(body == ["code": "123456"])
        #expect(verify.httpMethod == "POST")
    }

    @Test func pairingTimeoutFromTheBikeIsExplained() async throws {
        let body = #"{"command_name":"C_pairing_code","detail":"{\"reason\":\"DEVICE_TIMEOUT\",\"message\":\"Device did not respond in time\"}","pairedUserCount":0,"status":402}"#
        let (api, _, _) = try await signedInAPI { _, _ in (200, body) }
        do {
            try await api.requestPairingCode(bikeID: "1")
            Issue.record("expected a pairing error")
        } catch LiveWireAPIError.pairing(let message) {
            #expect(message.contains("did not answer in time"))
            #expect(message.contains("DEVICE_TIMEOUT"))
            #expect(!message.contains("no cellular"))
        }
    }

    @Test func pairingErrorsAreExplained() async throws {
        let (noCell, _, _) = try await signedInAPI { _, _ in (200, #"{"status":402}"#) }
        await #expect(throws: LiveWireAPIError.self) { try await noCell.requestPairingCode(bikeID: "1") }

        let (wrong, _, _) = try await signedInAPI { _, _ in (200, #"{"code":4004}"#) }
        do {
            try await wrong.verifyPairingCode(bikeID: "1", code: "000000")
            Issue.record("expected a pairing error")
        } catch LiveWireAPIError.pairing(let message) {
            #expect(message.contains("wrong"))
        }
    }

    @Test func analyticsDecodeFromTheResponse() async throws {
        let rides = #"{"bikeId":"101","periods":[{"type":"WEEK","granularity":"DAY","buckets":[{"bucketStart":"2026-11-23","rideCount":3,"sumBatteryUsedPercent":25,"totalDistance":21,"totalEfficiencykWhPerKm":0.0763}],"summary":{"rideCount":3,"totalBatteryUsedPercent":25,"totalDistance":21,"totalDurationSeconds":3811,"totalEfficiencykWhPerKm":0.0763}}]}"#
        let (api, transport, _) = try await signedInAPI { _, _ in (200, rides) }
        let analytics = try await api.rideAnalytics(bikeID: "101")
        #expect(analytics.period(.week)?.totals.rideCount == 3)
        let request = try #require(transport.requests(containing: "ride/analytics").first)
        #expect(request.url?.query?.contains("date=") == true)
    }

    @Test func aBodyThatDoesNotMatchNamesTheMissingField() async throws {
        let (api, _, _) = try await signedInAPI { _, _ in (200, #"{"bikes":[{"name":"no id"}]}"#) }
        do {
            _ = try await api.bikes()
            Issue.record("expected an error")
        } catch LiveWireAPIError.unexpectedResponse(let message) {
            #expect(message.contains("bikes[0].id is missing"), "\(message)")
        }
    }

    @Test func formEncodingEscapesReservedCharacters() {
        let data = AuthSession.formEncoded([("a b", "x+y&z=1")])
        #expect(String(decoding: data, as: UTF8.self) == "a%20b=x%2By%26z%3D1")
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { defer { value += 1 }; return value } }
}

@Suite struct WireTypesTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    @Test func numbersThatArriveAsStringsAreAccepted() throws {
        let reading = try decode(ChargingStatusResponse.self, #"{"bikeChargingData":{"batteryPercentage":"82","range":"112.4","maxLimit":"90","timeToMaxLimit":"45","durationElapsed":"12","durationUnit":"MINUTES"}}"#)
        let status = reading.status(bikeID: "1")
        #expect(status.batteryLevel == 82)
        #expect(status.rangeMiles == 112.4)
        #expect(status.chargeLimit == 90)
        #expect(status.minutesToLimit == 45)
        #expect(status.dataAge == 720)
    }

    @Test func aZeroChargeLimitMeansNone() throws {
        let response = try decode(ChargingStatusResponse.self, #"{"bikeChargingData":{"maxLimit":0}}"#)
        #expect(response.status(bikeID: "1").chargeLimit == nil)
    }

    @Test func aMissingReadingDoesNotCrash() throws {
        let status = try decode(ChargingStatusResponse.self, "{}").status(bikeID: "1")
        #expect(status.batteryLevel == nil)
        #expect(!status.isCharging)
    }

    @Test func aTextWhereANumberShouldBeIsAnError() {
        #expect(throws: DecodingError.self) {
            try decode(ChargingStatusResponse.self, #"{"bikeChargingData":{"batteryPercentage":"full"}}"#)
        }
    }

    @Test func bikesMapToTheDomainModel() throws {
        let response = try decode(BikesResponse.self, Fixture.bikes)
        let bikes = response.bikes.map(\.bike)
        #expect(bikes.map(\.id) == ["101", "102"])
        #expect(bikes[0].isPrimary)
        #expect(bikes[0].isPaired == true)
        #expect(bikes[1].isPaired == false)
        #expect(bikes[0].year == 2024)
        #expect(bikes[0].displayName == "Test Bike One")
    }

    @Test func pairingAnswerWithADetailDocumentInsideAString() throws {
        let answer = try decode(PairingCommandResponse.self, #"{"command_name":"C_pairing_code","detail":"{\"reason\":\"DEVICE_TIMEOUT\",\"message\":\"Device did not respond in time\"}","pairedUserCount":0,"status":402}"#)
        #expect(answer.status == 402)
        #expect(answer.commandName == "C_pairing_code")
        #expect(answer.parsedDetail?.reason == "DEVICE_TIMEOUT")
        #expect(answer.parsedDetail?.message == "Device did not respond in time")
    }

    @Test func errorCodesMayBeStringsOrNumbers() throws {
        #expect(try decode(ErrorEnvelope.self, #"{"error":{"code":"3000"}}"#).error?.code == "3000")
        #expect(try decode(ErrorEnvelope.self, #"{"error":{"code":3000}}"#).error?.code == "3000")
        #expect(try decode(ErrorEnvelope.self, "{}").error == nil)
    }
}
