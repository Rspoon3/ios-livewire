import SwiftUI

struct SignInView: View {
    let model: AppModel
    @State private var email = ""
    @State private var password = ""
    @State private var isSigningIn = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("LiveWire account")
                } footer: {
                    Text("Your password is sent to LiveWire's sign-in provider and is not stored. Only a sign-in token is kept, in the Keychain.")
                }

                if let message = model.errorMessage {
                    Section { Text(message).foregroundStyle(.red) }
                }

                Section {
                    Button {
                        isSigningIn = true
                        Task {
                            _ = await model.signIn(email: email, password: password)
                            password = ""
                            isSigningIn = false
                        }
                    } label: {
                        HStack {
                            Text("Sign in")
                            if isSigningIn { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(email.isEmpty || password.isEmpty || isSigningIn)
                }

                Section {
                    Text("Unofficial. Not affiliated with LiveWire or Harley-Davidson. It uses an undocumented API that can change at any time.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Sign in")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { LogShareButton(model: model).labelStyle(.iconOnly) } }
        }
    }
}
