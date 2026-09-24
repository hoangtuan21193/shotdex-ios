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
    /// What is in the Port field. Empty means the protocol's default, which
    /// the field shows as its placeholder — nobody has to delete a 445 to
    /// type a 4450.
    var portText = ""

    var id: String { server.id }

    init() {
        server = FileServer(name: "", transferProtocol: .smb, host: "", username: "")
        isNew = true
    }

    init(server: FileServer) {
        self.server = server
        isNew = false
        portText = server.port == server.transferProtocol.defaultPort ? "" : String(server.port)
    }

    /// The port the form stands for: typed, or the protocol's default.
    var port: Int? {
        let text = portText.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? server.transferProtocol.defaultPort : Int(text)
    }

    var canSave: Bool {
        !server.host.trimmingCharacters(in: .whitespaces).isEmpty
            && !server.username.trimmingCharacters(in: .whitespaces).isEmpty
            && port.map { (1...65_535).contains($0) } == true
            && (server.transferProtocol == .sftp || !server.share.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// The row as saved: trimmed, a blank name falls back to the host, the
    /// share is dropped for SFTP.
    var normalized: FileServer {
        var row = server
        row.port = port ?? row.transferProtocol.defaultPort
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
    @FocusState private var focus: Field?
    /// Called after a save, with the saved row — the upload sheet uses it to
    /// select a server it just made.
    var onSaved: ((FileServer) -> Void)?

    /// Return moves to the next field, in the order they are drawn.
    enum Field: Hashable {
        case name, host, port, username, password, share, folder
    }

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
                // Every field says what it is on the left, the way Settings
                // does: a placeholder alone is gone the moment you type, and
                // "Photos" in an empty box reads as a value, not a hint.
                Section {
                    field("Name", text: $draft.server.name, prompt: draft.server.host.isEmpty ? "My NAS" : draft.server.host, focus: .name)
                    Picker("Protocol", selection: protocolBinding) {
                        ForEach(FileServer.TransferProtocol.allCases) { Text($0.title).tag($0) }
                    }
                    field("Host", text: $draft.server.host, prompt: "nas.local", focus: .host)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                    LabeledContent("Port") {
                        TextField("Port", text: $draft.portText, prompt: Text(verbatim: String(draft.server.transferProtocol.defaultPort)))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focus, equals: .port)
                    }
                }
                Section {
                    field("Username", text: $draft.server.username, prompt: "Required", focus: .username)
                        .textContentType(.username)
                    // Not LabeledContent: an empty SecureField there collapses to
                    // no width on iOS 26 — no prompt, nothing to tap.
                    HStack {
                        Text("Password")
                        SecureField("Password", text: $draft.password, prompt: Text(draft.hasSavedPassword ? "Saved" : "Required"))
                            .textContentType(.password)
                            .multilineTextAlignment(.trailing)
                            .focused($focus, equals: .password)
                            .submitLabel(.next)
                            .onSubmit { focus = next(after: .password) }
                    }
                }
                Section {
                    if draft.server.transferProtocol == .smb {
                        field("Share", text: $draft.server.share, prompt: "Required", focus: .share)
                    }
                    field("Folder", text: $draft.server.folder, prompt: "Optional", focus: .folder)
                } footer: {
                    Text(draft.server.transferProtocol == .smb
                         ? "The share is the shared folder's name on the server. Photos go into year and day folders inside Folder, by the date they were taken."
                         : "Folder is relative to your home folder on the server. Photos go into year and day folders inside it, by the date they were taken.")
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

    /// A labelled text row: the name on the left, the value typed on the right.
    private func field(_ title: LocalizedStringKey, text: Binding<String>, prompt: String, focus field: Field) -> some View {
        LabeledContent(title) {
            TextField(title, text: text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: field)
                .submitLabel(field == .folder ? .done : .next)
                .onSubmit { focus = next(after: field) }
        }
    }

    /// The field after `field` on screen; Share is skipped for SFTP.
    private func next(after field: Field) -> Field? {
        switch field {
        case .name: .host
        case .host: .port
        case .port: .username
        case .username: .password
        case .password: draft.server.transferProtocol == .smb ? .share : .folder
        case .share: .folder
        case .folder: nil
        }
    }

    // MARK: Bindings

    private var protocolBinding: Binding<FileServer.TransferProtocol> {
        Binding(
            get: { draft.server.transferProtocol },
            set: { newValue in
                draft.server.transferProtocol = newValue
                test = .idle
            }
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
