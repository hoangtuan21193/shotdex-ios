import SwiftUI

/// Connect As (FS-15.04 §3): a server found on the network, how to
/// connect, the login, and Connect — a real sign-in whose failure shows
/// right here. Signed in, it hands the login to the folder picker; its
/// Choose opens Save Connection, where the name is set. Tier A.
struct ConnectAsScreen: View {
    @Bindable var model: ConnectAsModel
    let onSignedIn: (ServerBrowseSession) -> Void
    @FocusState private var focus: Field?

    enum Field: Hashable {
        case username, password
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: FileServerFormScreen.symbol(for: model.found.kind))
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.found.name)
                            .font(.headline)
                        Text(model.offer.host)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                if model.showsProtocolChoice {
                    Picker("Connect Using", selection: $model.offer) {
                        ForEach(model.offers, id: \.self) { offer in
                            Text(offer.service.title).tag(offer)
                        }
                    }
                }
            }
            Section {
                LabeledContent("Username") {
                    TextField("Username", text: $model.username, prompt: Text("Required"))
                        .multilineTextAlignment(.trailing)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                }
                // Not LabeledContent: an empty SecureField there collapses to
                // no width on iOS 26 — no prompt, nothing to tap.
                HStack {
                    Text("Password")
                    SecureField("Password", text: $model.password, prompt: Text("Required"))
                        .multilineTextAlignment(.trailing)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { connect() }
                }
            } footer: {
                if let error = model.signIn.error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        // The same full-width button as the picker's Choose at the next
        // step, where a thumb reaches it.
        .safeAreaInset(edge: .bottom) {
            Button {
                connect()
            } label: {
                HStack(spacing: 8) {
                    if model.signIn.isConnecting { ProgressView().tint(.white) }
                    Text("Connect")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canConnect)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        // Not `.disabled` on the whole form while connecting: re-enabling
        // it left the password field blank on screen (value still there)
        // and unable to take focus back (measured on 26.5). Connect itself
        // is off while a sign-in runs.
        .navigationTitle(Text("Connect to “\(model.found.name)”", comment: "Connect As screen title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if model.username.isEmpty { focus = .username } }
        .alert(
            "Trust This Server?",
            isPresented: Binding(get: { model.signIn.untrustedFingerprint != nil }, set: { if !$0 { model.signIn.untrustedFingerprint = nil } }),
            presenting: model.signIn.untrustedFingerprint
        ) { fingerprint in
            Button("Trust") {
                Task {
                    if let session = await model.trust(fingerprint) { onSignedIn(session) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { fingerprint in
            Text("ShotDex hasn't connected to \(model.offer.host) before. Check that this fingerprint matches the one your server shows:\n\n\(fingerprint)")
        }
    }

    private func connect() {
        guard model.canConnect else { return }
        focus = nil
        Task {
            if let session = await model.connect() {
                onSignedIn(session)
            } else if model.signIn.error != nil {
                // Most often the password: back to it, text kept.
                focus = .password
            }
        }
    }
}
