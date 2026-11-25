import SwiftUI

/// Pairs this install with a bike: the bike shows a 6-digit code on its display, which is typed here.
struct PairingView: View {
    @State private var viewModel: PairingViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: PairingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
            Section {
                Text("Pairing lets this app read \(viewModel.bike.displayName)'s battery over the cellular connection. You only need to do it once.")
            }

            switch viewModel.step {
            case .instructions:
                Section("Before you start") {
                    Label("Sit at the bike with the ignition on", systemImage: "key")
                    Label("Not in propulsion mode, and not charging", systemImage: "bolt.slash")
                    Label("The bike needs cellular reception", systemImage: "antenna.radiowaves.left.and.right")
                }
                Section {
                    Button("Show the code on the bike") { Task { await viewModel.requestCode() } }
                        .disabled(viewModel.isWorking)
                    if viewModel.isWorking {
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
                    TextField("6-digit code", text: $viewModel.code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.title2.monospacedDigit())
                    Button("Pair") { Task { await viewModel.verify() } }
                        .disabled(!viewModel.canVerify)
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

            if let message = viewModel.message {
                Section { Text(message).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Pair bike")
        .navigationBarTitleDisplayMode(.inline)
    }
}
