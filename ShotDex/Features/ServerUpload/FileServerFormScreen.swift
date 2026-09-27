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
            // SMB files live inside a shared folder: the first folder of the
            // path (FS-15.01 §3a).
            && (server.transferProtocol != .smb || !ServerUploadPath.normalizedFolder(server.folder.trimmingCharacters(in: .whitespaces)).isEmpty)
    }

    /// The row as saved: trimmed, a blank name falls back to the host; only
    /// WebDAV keeps the share column, as its Path.
    var normalized: FileServer {
        var row = server
        row.port = port ?? row.defaultPort
        row.host = row.host.trimmingCharacters(in: .whitespaces)
        row.username = row.username.trimmingCharacters(in: .whitespaces)
        switch row.transferProtocol {
        case .webdav: row.share = ServerUploadPath.normalizedFolder(row.share)
        case .smb, .sftp: row.share = ""
        }
        row.folder = ServerUploadPath.normalizedFolder(row.folder.trimmingCharacters(in: .whitespaces))
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft: FileServerDraft
    @State private var test: TestState = .idle
    @State private var untrustedFingerprint: String?
    @State private var saveError: String?
    /// Add Connection only: the servers found on the network (FS-15.04).
    @State private var discovery: ServerDiscoveryModel?
    @State private var path: [Route] = []
    /// The folder picker's login, closed with the form.
    @State private var pickerSession: ServerBrowseSession?
    /// Choose… signs in first; its failure shows under the Folder row.
    @State private var folderSignIn = ServerSignIn()
    /// Add to Collections for the Folder (FS-17.04 §1); on edit, whether it
    /// already has a tile.
    @State private var addsTile = false
    /// Connect As picked a folder: Save Connection is up (FS-15.04 §3).
    @State private var pendingSave: PendingSave?
    /// Choose… stopped at the Trust alert and resumes after it.
    @State private var resumesChooseAfterTrust = false
    @FocusState private var focus: Field?
    /// Called after a save, with the saved row — the upload sheet uses it to
    /// select a server it just made.
    var onSaved: ((FileServer) -> Void)?

    /// The screens the form pushes carry their models: a destination
    /// closure reading `@State` outside `body` gets a stale value.
    struct PendingSave: Identifiable {
        let id = UUID()
        let draft: FileServerDraft
    }

    enum Route: Hashable {
        case connectAs(ConnectAsModel)
        case folderPicker(ServerBrowserModel, feeds: PickerFeeds)

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.connectAs(let a), .connectAs(let b)): a === b
            case (.folderPicker(let a, _), .folderPicker(let b, _)): a === b
            default: false
            }
        }

        func hash(into hasher: inout Hasher) {
            switch self {
            case .connectAs(let model): hasher.combine(ObjectIdentifier(model))
            case .folderPicker(let model, _): hasher.combine(ObjectIdentifier(model))
            }
        }
    }

    /// Where the picked folder goes: a whole form filled from Connect As,
    /// or just the Folder field.
    enum PickerFeeds {
        case connectAs(ConnectAsModel)
        case form
    }

    /// Return moves to the next field, in the order they are drawn.
    enum Field: Hashable {
        case name, host, port, username, password, share, folder
    }

    enum TestState: Equatable {
        case idle
        case running
        case passed
        /// Connect As logged in; the write test has not run.
        case signedIn
        case failed(RemoteFileError)
    }

    init(draft: FileServerDraft, onSaved: ((FileServer) -> Void)? = nil) {
        _draft = State(initialValue: draft)
        self.onSaved = onSaved
        if draft.isNew {
            _discovery = State(initialValue: ServerDiscoveryModel(browser: BonjourServerBrowser(), scanner: SubnetSMBScanner()))
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
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
                    if draft.server.transferProtocol == .webdav {
                        field("Path", text: $draft.server.share, prompt: "Optional", focus: .share)
                    }
                    folderRow
                } footer: {
                    Text(folderFooter)
                }
                Section {
                    Toggle(isOn: $addsTile) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add to Collections")
                            Text(ConnectionSaver.tileExplanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                            .foregroundStyle(test == .passed || test == .signedIn ? Color.secondary : Color.red)
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
            .sheet(item: $pendingSave) { pending in
                SaveConnectionSheet(
                    name: pending.draft.server.name,
                    folder: pending.draft.normalized.folderDescription,
                    placeholder: pending.draft.server.host
                ) { name, addsTile in
                    var filled = pending.draft
                    filled.server.name = name
                    saveFromConnectAs(filled, addsTile: addsTile)
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .connectAs(let model):
                    ConnectAsScreen(model: model) { session in
                        openPicker(session, at: "", feeding: .connectAs(model))
                    }
                case .folderPicker(let picker, let feeds):
                    ServerBrowserScreen(model: picker) { chosen in choose(chosen, feeds: feeds) }
                }
            }
            // What the Choose… error is about changed: it no longer applies.
            .onChange(of: draft.server.host) { folderSignIn.error = nil }
            .onChange(of: draft.server.username) { folderSignIn.error = nil }
            .onChange(of: draft.password) { folderSignIn.error = nil }
            .onChange(of: draft.portText) { folderSignIn.error = nil }
            .onChange(of: draft.server.transferProtocol) { folderSignIn.error = nil }
            .task {
                if !draft.isNew {
                    draft.hasSavedPassword = dependencies.fileServers.password(for: draft.server.id) != nil
                    dependencies.serverShortcuts.reload()
                    addsTile = dependencies.serverShortcuts.shortcut(serverId: draft.server.id, path: draft.server.folder) != nil
                }
            }
            // Opening the form is what starts the search — and so what asks
            // for Local Network access, with the reason on screen.
            .onAppear { discovery?.start() }
            .onDisappear {
                discovery?.stop()
                if let pickerSession { Task { await pickerSession.close() } }
            }
            // The Local Network prompt (or a trip to Settings) takes the app
            // out of active; coming back is when to search again.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { discovery?.appBecameActive() }
            }
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
            Text("Computers and NAS drives sharing files on the same network as this device. Tap one to sign in.")
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
        Button { startConnectAs(server) } label: { label }
            .buttonStyle(.plain)
            .accessibilityHint("Sign in to this server")
    }

    /// Tapping a found server signs in there, the way Finder's Connect As
    /// does (FS-15.04 §3).
    private func startConnectAs(_ server: DiscoveredServer) {
        focus = nil
        path = [.connectAs(ConnectAsModel(found: server))]
    }

    private func isFilled(from server: DiscoveredServer) -> Bool {
        server.offers.contains { offer in
            offer.host == draft.server.host && offer.service.transferProtocol == draft.server.transferProtocol
        }
    }

    static func symbol(for kind: DiscoveredServer.Kind) -> String {
        switch kind {
        case .laptop: "laptopcomputer"
        case .desktop: "desktopcomputer"
        case .nas: "externaldrive.connected.to.line.below"
        case .pc: "pc"
        }
    }

    // MARK: Folder

    /// Folder, typed or picked on the server after signing in (FS-15.04 §5).
    /// For SMB its first folder is the shared folder (FS-15.01 §3a).
    private var folderRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Not LabeledContent: it merges its children into one
            // accessibility element, and Choose… could not be reached on its
            // own — by VoiceOver or by a UI test.
            HStack(spacing: 8) {
                Text("Folder")
                TextField("Folder", text: $draft.server.folder, prompt: Text(draft.server.transferProtocol == .smb ? "Required" : "Optional"))
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .folder)
                    .submitLabel(.done)
                    .onSubmit { focus = nil }
                if folderSignIn.isConnecting {
                    ProgressView()
                } else {
                    Button("Choose…") { chooseFolder() }
                        // A button in a row with a text field: only the
                        // button's own frame answers the tap.
                        .buttonStyle(.borderless)
                        .disabled(!canBrowse)
                }
            }
            if let error = folderSignIn.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var canBrowse: Bool {
        !draft.server.host.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.server.username.trimmingCharacters(in: .whitespaces).isEmpty
            && !effectivePassword.isEmpty
            && draft.port != nil
    }

    /// Signs in with what the form holds, then opens the picker at the typed
    /// folder; a failure stays under the row.
    private func chooseFolder() {
        focus = nil
        let server = draft.normalized
        let password = effectivePassword
        Task {
            if let session = await folderSignIn.signIn(to: server, password: password) {
                openPicker(session, at: server.folder, feeding: .form)
            } else if let fingerprint = folderSignIn.untrustedFingerprint {
                resumesChooseAfterTrust = true
                untrustedFingerprint = fingerprint
            }
        }
    }

    private func openPicker(_ session: ServerBrowseSession, at folder: String, feeding: PickerFeeds) {
        if let old = pickerSession, old !== session { Task { await old.close() } }
        pickerSession = session
        let dependencies = dependencies
        let picker = ServerBrowserModel(session: session, start: folder, mode: .chooseFolder) { path in
            ServerFolderModel(
                session: session,
                folder: path,
                cache: dependencies.serverThumbnails,
                downloads: dependencies.serverDownloads,
                existingAssetIds: { PhotoKitAssetCreator.existingAssetIds($0) }
            )
        }
        path.append(.folderPicker(picker, feeds: feeding))
    }

    /// The picker's Choose: from Connect As it saves the connection; from
    /// Choose… it fills the Folder field.
    private func choose(_ folder: String, feeds: PickerFeeds) {
        switch feeds {
        case .connectAs(let model):
            // Signed in and a folder picked: that is a whole connection. Ask
            // for its name and whether to tile the folder, then save — no
            // trip back to the form to press Save again (FS-15.04 §3).
            pendingSave = PendingSave(draft: model.draft(folder: folder))
            return
        case .form:
            draft.server.folder = folder
        }
        path = []
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
            String(localized: "Choose… signs in and shows the folders this computer shares. The first folder is the shared folder, such as Photos. Uploads start in Folder; you can pick another each time.")
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

    /// The field after `field` on screen; Path is WebDAV's only.
    private func next(after field: Field) -> Field? {
        switch field {
        case .name: .host
        case .host: .port
        case .port: .username
        case .username: .password
        case .password: draft.server.transferProtocol == .webdav ? .share : .folder
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
        case .passed, .signedIn:
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
        case .signedIn: String(localized: "Signed in.", comment: "File server form: Connect As logged in; the write test has not run")
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
        if resumesChooseAfterTrust {
            resumesChooseAfterTrust = false
            chooseFolder()
        } else {
            runTest()
        }
    }

    private func forgetKey() {
        draft.server.trustedFingerprint = nil
        if !draft.isNew {
            try? dependencies.fileServers.setHostKeyFingerprint(nil, for: draft.server.id)
        }
        test = .idle
    }

    /// Save Connection's Save. A failure leaves the filled form showing,
    /// with the reason, so nothing typed is lost.
    private func saveFromConnectAs(_ filled: FileServerDraft, addsTile: Bool) {
        pendingSave = nil
        do {
            let saved = try ConnectionSaver.save(filled, addsTile: addsTile, servers: dependencies.fileServers, shortcuts: dependencies.serverShortcuts)
            dependencies.fileServerCatalog.reload()
            onSaved?(saved)
            dismiss()
        } catch {
            draft = filled
            test = .signedIn
            path = []
            saveError = error.localizedDescription
        }
    }

    private func save() {
        do {
            let saved = try ConnectionSaver.save(draft, addsTile: addsTile, servers: dependencies.fileServers, shortcuts: dependencies.serverShortcuts)
            dependencies.fileServerCatalog.reload()
            onSaved?(saved)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
