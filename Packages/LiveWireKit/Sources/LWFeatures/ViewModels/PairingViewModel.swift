import LWModels
import Observation

/// Pairs this install with a bike: the bike shows a 6-digit code on its display, which is typed in.
@MainActor
@Observable
final class PairingViewModel {
    enum Step: Equatable {
        case instructions
        case enterCode
        case finishing
        case done
    }

    let bike: Bike
    private(set) var step = Step.instructions
    var code = ""
    private(set) var isWorking = false
    private(set) var message: String?

    @ObservationIgnored private let pairing: any BikePairing

    init(bike: Bike, pairing: any BikePairing) {
        self.bike = bike
        self.pairing = pairing
    }

    var canVerify: Bool { code.trimmingCharacters(in: .whitespaces).count >= 4 && !isWorking }

    /// Asks the bike to show a code. The backend holds the request for about a minute while it waits.
    func requestCode() async {
        await run {
            try await pairing.requestPairingCode(bikeID: bike.id)
            step = .enterCode
        }
    }

    /// Sends the typed code back, then waits for the bike to confirm.
    func verify() async {
        guard canVerify else { return }
        await run {
            try await pairing.verifyPairingCode(bikeID: bike.id, code: code.trimmingCharacters(in: .whitespaces))
            step = .finishing
            if try await pairing.finishPairing(bikeID: bike.id) {
                step = .done
            } else {
                step = .enterCode
                message = "The bike did not confirm the pairing in time. Try again."
            }
        }
    }

    private func run(_ work: () async throws -> Void) async {
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            try await work()
        } catch {
            message = error.localizedDescription
            if step == .finishing { step = .enterCode }
        }
    }
}
