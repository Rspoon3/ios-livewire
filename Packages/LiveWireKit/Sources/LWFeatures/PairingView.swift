import LWLogging
import LWModels
import LWServices
import SwiftUI

/// Pairs this install with a bike: the bike shows a 6-digit code on its display, which is typed here.
struct PairingView: View {
    let bike: Bike
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    private enum Step { case instructions, enterCode, finishing, done }

    @State private var step = Step.instructions
    @State private var code = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var diagnostics: [DiagnosticLine] = []
    @State private var isDiagnosing = false

    var body: some View {
        Form {
            Section {
                Text("Pairing lets this app read \(bike.displayName)'s battery over the cellular connection. You only need to do it once.")
            }

            switch step {
            case .instructions:
                Section("Before you start") {
                    Label("Sit at the bike with the ignition on", systemImage: "key")
                    Label("Not in propulsion mode, and not charging", systemImage: "bolt.slash")
                    Label("The bike needs cellular reception", systemImage: "antenna.radiowaves.left.and.right")
                }
                Section {
                    Button("Show the code on the bike") { request() }.disabled(isWorking)
                    if isWorking {
                        HStack {
                            ProgressView()
                            Text("Waiting for the bike. This takes about a minute. Keep the ignition on and stay on this screen.")
                                .font(.footnote)
                                .padding(.leading, 8)
                        }
                    }
                }
            case .enterCode:
                Section {
                    TextField("6-digit code", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.title2.monospacedDigit())
                    Button("Pair") { verify() }.disabled(code.count < 4 || isWorking)
                } header: {
                    Text("Code from the bike's display")
                } footer: {
                    Text("Did the code not appear? Go back and try again. An unused code expires by itself.")
                }
            case .finishing:
                Section { HStack { ProgressView(); Text("Waiting for the bike to confirm…").padding(.leading, 8) } }
            case .done:
                Section { Label("Paired", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                Section { Button("Done") { dismiss() } }
            }

            if let message {
                Section { Text(message).foregroundStyle(.red) }
            }

            Section {
                Button {
                    isDiagnosing = true
                    Task {
                        diagnostics = await model.runDiagnostics(bike: bike)
                        isDiagnosing = false
                    }
                } label: {
                    HStack {
                        Label("Check what LiveWire can see", systemImage: "stethoscope")
                        if isDiagnosing { Spacer(); ProgressView() }
                    }
                }
                .disabled(isDiagnosing)
                ForEach(diagnostics) { line in
                    LabeledContent(line.name) {
                        Text(line.outcome)
                            .font(.footnote)
                            .foregroundStyle(line.isOK ? Color.green : Color.red)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } header: {
                Text("Troubleshooting")
            } footer: {
                Text("Read-only. Everything is written to the log, so Share logs afterwards.")
            }
        }
        .navigationTitle("Pair bike")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func request() {
        run {
            try await model.requestPairingCode(bikeID: bike.id)
            step = .enterCode
        }
    }

    private func verify() {
        run {
            try await model.verifyPairingCode(bikeID: bike.id, code: code.trimmingCharacters(in: .whitespaces))
            step = .finishing
            if try await model.finishPairing(bikeID: bike.id) {
                step = .done
            } else {
                step = .enterCode
                message = "The bike did not confirm the pairing in time. Try again."
            }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isWorking = true
        message = nil
        Task {
            do { try await work() } catch {
                message = error.localizedDescription
                if step == .finishing { step = .enterCode }
            }
            isWorking = false
        }
    }
}
