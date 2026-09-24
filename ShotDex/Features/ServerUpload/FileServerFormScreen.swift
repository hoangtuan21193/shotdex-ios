import SwiftUI

/// What the form edits: the row, plus a password that is only sent to the
/// Keychain when the user typed one.
struct FileServerDraft: Identifiable {
    var server: FileServer
    let isNew: Bool
    var password = ""
    /// Whether a password is already saved — the field then reads "Saved"
    /// and leaving it empty keeps it.
    var hasSavedPassword = false
    /// The port was typed by hand, so switching protocol leaves it alone.
    var portEdited = false

    var id: String { server.id }

    init() {
        server = FileServer(name: "", transferProtocol: .smb, host: "", username: "")
        isNew = true
    }

    init(server: FileServer) {
        self.server = server
        isNew = false
        portEdited = server.port != server.transferProtocol.defaultPort
    }

    var canSave: Bool {
        !server.host.trimmingCharacters(in: .whitespaces).isEmpty
            && !server.username.trimmingCharacters(in: .whitespaces).isEmpty
            && (1...65_535).contains(server.port)
            && (server.transferProtocol == .sftp || !server.share.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// The row as saved: trimmed, a blank name falls back to the host, the
    /// share is dropped for SFTP.
    var normalized: FileServer {
        var row = server
        row.host = row.host.trimmingCharacters(in: .whitespaces)
        row.username = row.username.trimmingCharacters(in: .whitespaces)
        row.share = row.transferProtocol == .smb ? row.share.trimmingCharacters(in: .whitespaces) : ""
        row.folder = ServerUploadPath.normalizedFolder(row.folder)
        let name = row.name.trimmingCharacters(in: .whitespaces)
        row.name = name.isEmpty ? row.host : name
        return row
    }
}

/// Add or edit one server (FS-15.01 §3), with Test Connection.
struct FileServerFormScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var draft: FileServerDraft
    @State private var test: TestState = .idle
    @State private var untrustedFingerprint: String?
    @State private var saveError: String?
    /// Called after a save, with the saved row — the upload sheet uses it to
    /// select a server it just made.
    var onSaved: ((FileServer) -> Void)?

    enum TestState: Equatable {
        case idle
        case running
        case passed
        case failed(RemoteFileError)
    }

    init(draft: FileServerDraft, onSaved: ((FileServer) -> Void)? = nil) {
        _draft = State(initialValue: draft)
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.server.name, prompt: Text(draft.server.host.isEmpty ? "My NAS" : draft.server.host))
                    Picker("Protocol", selection: protocolBinding) {
                        ForEach(FileServer.TransferProtocol.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Host", text: $draft.server.host, prompt: Text("nas.local or 192.168.1.10"))
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    LabeledContent("Port") {
                        TextField("Port", value: portBinding, format: .number.grouping(.never))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section {
                    TextField("Username", text: $draft.server.username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $draft.password, prompt: Text(draft.hasSavedPassword ? "Saved" : "Required"))
                        .textContentType(.password)
                }
                Section {
                    if draft.server.transferProtocol == .smb {
                        TextField("Share", text: $draft.server.share, prompt: Text("Photos"))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    TextField("Folder", text: $draft.server.folder, prompt: Text("Optional, e.g. RAW/iPhone"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Photos go into year and day folders inside this folder, by the date they were taken.")
                }
                Section {
                    Button {
                        runTest()
                    } label: {
                        HStack {
                            Text("Test Connection")
                            Spacer()
                            testIndicator
                        }
                    }
                    .disabled(!draft.canSave || test == .running)
                    if let message = testMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(test == .passed ? Color.secondary : Color.red)
                    }
                    if case .failed(.localNetworkDenied) = test {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                    if case .failed(.hostKeyChanged) = test {
                        Button("Forget Saved Key", role: .destructive) { forgetKey() }
                    }
                } footer: {
                    if let fingerprint = draft.server.hostKeyFingerprint, draft.server.transferProtocol == .sftp {
                        Text("Trusted key \(fingerprint)")
                            .font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle(draft.isNew ? "Add Server" : "Edit Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!draft.canSave || (draft.isNew && draft.password.isEmpty))
                }
            }
            .alert(
                "Trust This Server?",
                isPresented: Binding(get: { untrustedFingerprint != nil }, set: { if !$0 { untrustedFingerprint = nil } }),
                presenting: untrustedFingerprint
            ) { fingerprint in
                Button("Trust") { trust(fingerprint) }
                Button("Cancel", role: .cancel) {}
            } message: { fingerprint in
                Text("ShotDex hasn't connected to \(draft.server.host) before. Check that this fingerprint matches the one your server shows:\n\n\(fingerprint)")
            }
            .alert(
                "Couldn't Save Server",
                isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } }),
                presenting: saveError
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { Text($0) }
            .task {
                if !draft.isNew {
                    draft.hasSavedPassword = dependencies.fileServers.password(for: draft.server.id) != nil
                }
            }
        }
    }

    // MARK: Bindings

    private var protocolBinding: Binding<FileServer.TransferProtocol> {
        Binding(
            get: { draft.server.transferProtocol },
            set: { newValue in
                draft.server.transferProtocol = newValue
                if !draft.portEdited { draft.server.port = newValue.defaultPort }
                test = .idle
            }
        )
    }

    private var portBinding: Binding<Int> {
        Binding(
            get: { draft.server.port },
            set: { draft.server.port = $0; draft.portEdited = true }
        )
    }

    // MARK: Test

    @ViewBuilder
    private var testIndicator: some View {
        switch test {
        case .idle: EmptyView()
        case .running: ProgressView()
        case .passed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                .accessibilityLabel("Connected")
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                .accessibilityLabel("Failed")
        }
    }

    private var testMessage: String? {
        switch test {
        case .idle, .running: nil
        case .passed: String(localized: "Connected. Ready to upload.", comment: "File server Test Connection succeeded")
        case .failed(let error): error.localizedDescription
        }
    }

    private var effectivePassword: String {
        if !draft.password.isEmpty { return draft.password }
        return dependencies.fileServers.password(for: draft.server.id) ?? ""
    }

    private func runTest() {
        test = .running
        let server = draft.normalized
        let client = RemoteFileClientFactory.make(for: server, password: effectivePassword)
        Task {
            let outcome = await FileServerConnectionCheck.run(client: client, folder: server.folder)
            switch outcome {
            case .connected:
                test = .passed
            case .failed(_, .hostKeyUntrusted(let fingerprint)):
                test = .idle
                untrustedFingerprint = fingerprint
            case .failed(_, let error):
                test = .failed(error)
            }
        }
    }

    private func trust(_ fingerprint: String) {
        draft.server.hostKeyFingerprint = fingerprint
        if !draft.isNew {
            try? dependencies.fileServers.setHostKeyFingerprint(fingerprint, for: draft.server.id)
        }
        runTest()
    }

    private func forgetKey() {
        draft.server.hostKeyFingerprint = nil
        if !draft.isNew {
            try? dependencies.fileServers.setHostKeyFingerprint(nil, for: draft.server.id)
        }
        test = .idle
    }

    private func save() {
        let row = draft.normalized
        do {
            try dependencies.fileServers.save(row, password: draft.password.isEmpty ? nil : draft.password)
            onSaved?((try? dependencies.fileServers.fetch(id: row.id)) ?? row)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
