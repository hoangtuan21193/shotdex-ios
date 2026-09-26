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
        portText = server.port == server.defaultPort ? "" : String(server.port)
    }

    /// The port the form stands for: typed, or the protocol's default.
    var port: Int? {
        let text = portText.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? server.defaultPort : Int(text)
    }

    var canSave: Bool {
        !server.host.trimmingCharacters(in: .whitespaces).isEmpty
            && !server.username.trimmingCharacters(in: .whitespaces).isEmpty
            && port.map { (1...65_535).contains($0) } == true
            && (server.transferProtocol != .smb || !server.share.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// The row as saved: trimmed, a blank name falls back to the host, the
    /// share is dropped for SFTP.
    var normalized: FileServer {
        var row = server
        row.port = port ?? row.defaultPort
        row.host = row.host.trimmingCharacters(in: .whitespaces)
        row.username = row.username.trimmingCharacters(in: .whitespaces)
        switch row.transferProtocol {
        case .smb: row.share = row.share.trimmingCharacters(in: .whitespaces)
        case .webdav: row.share = ServerUploadPath.normalizedFolder(row.share)
        case .sftp: row.share = ""
        }
        row.folder = ServerUploadPath.normalizedFolder(row.folder)
        let name = row.name.trimmingCharacters(in: .whitespaces)
        row.name = name.isEmpty ? row.host : name
        return row
    }
}

/// Add or edit one connection (FS-15.01 §3), with Test Connection.
struct FileServerFormScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var draft: FileServerDraft
    @State private var test: TestState = .idle
    @State private var untrustedFingerprint: String?
    @State private var saveError: String?
    /// Add Connection only: the servers found on the network (FS-15.04).
    @State private var discovery: ServerDiscoveryModel?
    @State private var shares: [String]?
    @State private var isLoadingShares = false
    @State private var shareError: String?
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
        if draft.isNew {
            _discovery = State(initialValue: ServerDiscoveryModel(browser: BonjourServerBrowser()))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let discovery {
                    foundServersSection(discovery)
                }
                // Every field says what it is on the left, the way Settings
                // does: a placeholder alone is gone the moment you type, and
                // "Photos" in an empty box reads as a value, not a hint.
                Section {
                    field("Name", text: $draft.server.name, prompt: draft.server.host.isEmpty ? "My NAS" : draft.server.host, focus: .name)
                    Picker("Protocol", selection: protocolBinding) {
                        ForEach(FileServer.TransferProtocol.allCases) { Text($0.title).tag($0) }
                    }
                    protocolOptions
                    field("Host", text: $draft.server.host, prompt: "nas.local", focus: .host)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                    LabeledContent("Port") {
                        TextField("Port", text: $draft.portText, prompt: Text(verbatim: String(draft.server.defaultPort)))
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
                        shareRow
                    }
                    if draft.server.transferProtocol == .webdav {
                        field("Path", text: $draft.server.share, prompt: "Optional", focus: .share)
                    }
                    field("Folder", text: $draft.server.folder, prompt: "Optional", focus: .folder)
                } footer: {
                    Text(folderFooter)
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
                    if let fingerprint = draft.server.trustedFingerprint, draft.server.hasTrustedIdentity {
                        Text("Trusted key \(fingerprint)")
                            .font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle(draft.isNew ? "Add Connection" : "Edit Connection")
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
                "Couldn't Save Connection",
                isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } }),
                presenting: saveError
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { Text($0) }
            .confirmationDialog(
                "Choose a Share",
                isPresented: Binding(get: { shares != nil }, set: { if !$0 { shares = nil } }),
                titleVisibility: .visible,
                presenting: shares
            ) { names in
                ForEach(names, id: \.self) { name in
                    Button(name) { draft.server.share = name }
                }
                Button("Cancel", role: .cancel) {}
            } message: { names in
                if names.isEmpty { Text("This server doesn't share any folders with this account.") }
            }
            .task {
                if !draft.isNew {
                    draft.hasSavedPassword = dependencies.fileServers.password(for: draft.server.id) != nil
                }
            }
            // Opening the form is what starts the search — and so what asks
            // for Local Network access, with the reason on screen.
            .onAppear { discovery?.start() }
            .onDisappear { discovery?.stop() }
        }
    }

    // MARK: Found servers

    /// "Servers Found on This Network" (FS-15.04 §2): the header and footer
    /// are what say these are machines the app just found nearby, not a list
    /// it came with.
    @ViewBuilder
    private func foundServersSection(_ discovery: ServerDiscoveryModel) -> some View {
        Section {
            switch discovery.state {
            case .searching:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Looking for servers…")
                        .foregroundStyle(.secondary)
                }
            case .found(let servers):
                ForEach(servers) { server in
                    foundServerRow(server)
                }
            case .none:
                Text("No servers found. Enter the address below.")
                    .foregroundStyle(.secondary)
            case .denied:
                Text("ShotDex can't look for servers because Local Network access is off.")
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        } header: {
            HStack(spacing: 6) {
                Text("Servers Found on This Network")
                if case .found = discovery.state, discovery.isSearching {
                    ProgressView().controlSize(.mini)
                }
            }
        } footer: {
            Text("Computers and NAS drives sharing files on the same network as this device. Tap one to fill in its address.")
        }
    }

    @ViewBuilder
    private func foundServerRow(_ server: DiscoveredServer) -> some View {
        let label = HStack(spacing: 12) {
            Image(systemName: Self.symbol(for: server.kind))
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .foregroundStyle(.primary)
                Text(server.protocolSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isFilled(from: server) {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Selected")
            }
        }
        .contentShape(Rectangle())
        if server.offers.count == 1, let offer = server.offers.first {
            Button { fill(offer, from: server) } label: { label }
                .buttonStyle(.plain)
        } else {
            Menu {
                ForEach(server.offers, id: \.self) { offer in
                    Button(offer.service.title) { fill(offer, from: server) }
                }
            } label: { label }
                .buttonStyle(.plain)
        }
    }

    private func fill(_ offer: DiscoveredServer.Offer, from server: DiscoveredServer) {
        draft.apply(offer, from: server)
        test = .idle
        focus = .username
    }

    private func isFilled(from server: DiscoveredServer) -> Bool {
        server.offers.contains { offer in
            offer.host == draft.server.host && offer.service.transferProtocol == draft.server.transferProtocol
        }
    }

    private static func symbol(for kind: DiscoveredServer.Kind) -> String {
        switch kind {
        case .laptop: "laptopcomputer"
        case .desktop: "desktopcomputer"
        case .nas: "externaldrive.connected.to.line.below"
        }
    }

    // MARK: Share

    /// Share, typed or picked from the server's own list (FS-15.04 §5).
    private var shareRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Not LabeledContent: it merges its children into one
            // accessibility element, and Choose… could not be reached on its
            // own — by VoiceOver or by a UI test.
            HStack(spacing: 8) {
                Text("Share")
                TextField("Share", text: $draft.server.share, prompt: Text("Required"))
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .share)
                    .submitLabel(.next)
                    .onSubmit { focus = next(after: .share) }
                if isLoadingShares {
                    ProgressView()
                } else {
                    Button("Choose…") { loadShares() }
                        // A button in a row with a text field: only the
                        // button's own frame answers the tap.
                        .buttonStyle(.borderless)
                        .disabled(!canListShares)
                }
            }
            if let shareError {
                Text(shareError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var canListShares: Bool {
        !draft.server.host.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.server.username.trimmingCharacters(in: .whitespaces).isEmpty
            && !effectivePassword.isEmpty
            && draft.port != nil
    }

    private func loadShares() {
        let server = draft.normalized
        let password = effectivePassword
        isLoadingShares = true
        shareError = nil
        Task {
            defer { isLoadingShares = false }
            do {
                shares = try await SMBFileClient.shareNames(
                    host: server.host, port: server.port, username: server.username, password: password
                )
            } catch {
                shareError = error.localizedDescription
            }
        }
    }

    // MARK: Protocol options

    /// The rows only some protocols have (FS-15.05 §1, §3).
    @ViewBuilder
    private var protocolOptions: some View {
        switch draft.server.transferProtocol {
        case .webdav:
            Toggle("Use HTTPS", isOn: Binding(get: { draft.server.usesTLS }, set: { draft.server.usesTLS = $0; test = .idle }))
        case .smb, .sftp:
            EmptyView()
        }
        if draft.server.isUnencrypted {
            Label("Passwords and photos are sent unencrypted. Use this only on your home network.", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    private var folderFooter: String {
        switch draft.server.transferProtocol {
        case .smb:
            String(localized: "The share is the shared folder on the server — Choose… lists them once the username and password are in. Folder is where uploads start; you can pick another each time.")
        case .sftp:
            String(localized: "Folder is relative to your home folder on the server. It is where uploads start; you can pick another each time.")
        case .webdav:
            String(localized: "Path is the WebDAV address on the server, such as remote.php/dav/files/you for Nextcloud. Folder is where uploads start, inside Path.")
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
        case .password: [.smb, .webdav].contains(draft.server.transferProtocol) ? .share : .folder
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
        draft.server.trustedFingerprint = fingerprint
        if !draft.isNew {
            try? dependencies.fileServers.setHostKeyFingerprint(fingerprint, for: draft.server.id)
        }
        runTest()
    }

    private func forgetKey() {
        draft.server.trustedFingerprint = nil
        if !draft.isNew {
            try? dependencies.fileServers.setHostKeyFingerprint(nil, for: draft.server.id)
        }
        test = .idle
    }

    private func save() {
        let row = draft.normalized
        do {
            try dependencies.fileServers.save(row, password: draft.password.isEmpty ? nil : draft.password)
            dependencies.fileServerCatalog.reload()
            onSaved?((try? dependencies.fileServers.fetch(id: row.id)) ?? row)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
