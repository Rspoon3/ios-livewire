import SwiftUI

struct SignInView: View {
    @State private var viewModel: SignInViewModel

    init(model: AppModel) {
        _viewModel = State(initialValue: SignInViewModel(auth: model, logExport: model.logExport))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $viewModel.email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.password)
                } header: {
                    Text("LiveWire account")
                } footer: {
                    Text("Your password is sent to LiveWire's sign-in provider and is not stored. Only a sign-in token is kept, in the Keychain.")
                }

                if let message = viewModel.errorMessage {
                    Section { Text(message).foregroundStyle(.red) }
                }

                Section {
                    Button {
                        Task { await viewModel.submit() }
                    } label: {
                        HStack {
                            Text("Sign in")
                            if viewModel.isSigningIn { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                }

                Section {
                    Text("Unofficial. Not affiliated with LiveWire or Harley-Davidson. It uses an undocumented API that can change at any time.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Sign in")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    LogShareButton(export: viewModel.logExport).labelStyle(.iconOnly)
                }
            }
        }
    }
}
