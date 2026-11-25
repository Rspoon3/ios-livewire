import Foundation
import LWFileSystem
import LWLogging
import LWModels
import Testing

@testable import LWFeatures

struct FakeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class FakeAuth: SigningIn {
    var failure: FakeError?
    private(set) var calls: [(email: String, password: String)] = []

    func signIn(email: String, password: String) async throws {
        calls.append((email, password))
        if let failure { throw failure }
    }
}

@MainActor
final class FakePairing: BikePairing {
    var requestFailure: FakeError?
    var verifyFailure: FakeError?
    var finishFailure: FakeError?
    var confirms = true
    private(set) var sentCodes: [String] = []

    func requestPairingCode(bikeID: String) async throws {
        if let requestFailure { throw requestFailure }
    }

    func verifyPairingCode(bikeID: String, code: String) async throws {
        sentCodes.append(code)
        if let verifyFailure { throw verifyFailure }
    }

    func finishPairing(bikeID: String) async throws -> Bool {
        if let finishFailure { throw finishFailure }
        return confirms
    }
}

private let logExport = LogExport(
    locations: LogLocations(documents: URL(filePath: "/memory/Documents"), sharedContainer: nil),
    fileSystem: InMemoryFileSystem()
)

@MainActor
@Suite struct SignInViewModelTests {
    @Test func needsAnEmailAndAPassword() {
        let model = SignInViewModel(auth: FakeAuth(), logExport: logExport)
        #expect(!model.canSubmit)
        model.email = "rider@example.com"
        #expect(!model.canSubmit)
        model.password = "secret"
        #expect(model.canSubmit)
    }

    @Test func submitsTheCredentialsAndForgetsThePassword() async {
        let auth = FakeAuth()
        let model = SignInViewModel(auth: auth, logExport: logExport)
        model.email = "rider@example.com"
        model.password = "secret"

        await model.submit()

        #expect(auth.calls.count == 1)
        #expect(auth.calls.first?.email == "rider@example.com")
        #expect(auth.calls.first?.password == "secret")
        #expect(model.password.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(!model.isSigningIn)
    }

    @Test func aFailureIsShownAndThePasswordIsStillForgotten() async {
        let auth = FakeAuth()
        auth.failure = FakeError(message: "Wrong email or password")
        let model = SignInViewModel(auth: auth, logExport: logExport)
        model.email = "rider@example.com"
        model.password = "nope"

        await model.submit()

        #expect(model.errorMessage == "Wrong email or password")
        #expect(model.password.isEmpty)
        #expect(!model.isSigningIn)
    }
}

@MainActor
@Suite struct PairingViewModelTests {
    private func model(_ pairing: FakePairing) -> PairingViewModel {
        PairingViewModel(bike: Bike(id: "7", name: "Test Bike"), pairing: pairing)
    }

    @Test func theHappyPath() async {
        let pairing = FakePairing()
        let model = model(pairing)
        #expect(model.step == .instructions)

        await model.requestCode()
        #expect(model.step == .enterCode)

        model.code = " 123456 "
        await model.verify()
        #expect(model.step == .done)
        #expect(pairing.sentCodes == ["123456"], "the code is trimmed")
        #expect(model.message == nil)
        #expect(!model.isWorking)
    }

    @Test func aBikeThatDoesNotAnswerStaysOnTheInstructions() async {
        let pairing = FakePairing()
        pairing.requestFailure = FakeError(message: "The bike did not answer in time.")
        let model = model(pairing)

        await model.requestCode()

        #expect(model.step == .instructions)
        #expect(model.message == "The bike did not answer in time.")
        #expect(!model.isWorking)
    }

    @Test func aWrongCodeLetsYouTryAgain() async {
        let pairing = FakePairing()
        pairing.verifyFailure = FakeError(message: "That code is wrong.")
        let model = model(pairing)
        await model.requestCode()
        model.code = "000000"

        await model.verify()

        #expect(model.step == .enterCode)
        #expect(model.message == "That code is wrong.")
    }

    @Test func aBikeThatNeverConfirmsReturnsToTheCodeEntry() async {
        let pairing = FakePairing()
        pairing.confirms = false
        let model = model(pairing)
        await model.requestCode()
        model.code = "123456"

        await model.verify()

        #expect(model.step == .enterCode)
        #expect(model.message?.contains("did not confirm") == true)
    }

    @Test func aFailureWhileWaitingReturnsToTheCodeEntry() async {
        let pairing = FakePairing()
        pairing.finishFailure = FakeError(message: "Offline")
        let model = model(pairing)
        await model.requestCode()
        model.code = "123456"

        await model.verify()

        #expect(model.step == .enterCode)
        #expect(model.message == "Offline")
    }

    @Test func aShortCodeCannotBeSent() async {
        let pairing = FakePairing()
        let model = model(pairing)
        await model.requestCode()
        model.code = "12"
        #expect(!model.canVerify)
        await model.verify()
        #expect(pairing.sentCodes.isEmpty)
    }
}

@MainActor
@Suite struct DashboardFormattingTests {
    @Test func theStatusLine() {
        let charging = ChargingStatus(bikeID: "1", isCharging: true, range: Measurement(value: 73, unit: .miles))
        #expect(DashboardViewModel.statusLine(charging).hasPrefix("Charging · "))

        let plugged = ChargingStatus(bikeID: "1", isPluggedIn: true)
        #expect(DashboardViewModel.statusLine(plugged) == "Plugged in")

        #expect(DashboardViewModel.statusLine(ChargingStatus(bikeID: "1")) == "No data")
    }
}
