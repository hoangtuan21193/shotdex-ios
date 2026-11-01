import SwiftUI

/// Add Connection / Edit Connection on the Mac (board `MAC_ServerForm`,
/// FS-15.01, FS-18.04 §3): a 520-wide sheet — Nearby, Name, Protocol, Host
/// and Port, Username, Password, Folder with Choose…, Test Connection.
struct MacServerFormSheet: View {
    var saved: (FileServer) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(MacDependencies.self) private var dependencies
    @State private var draft: FileServerDraft
    @State private var discovery: ServerDiscoveryModel?
    @State private var test = TestState.idle
    @State private var untrustedFingerprint: String?
    @State private var saveError: String?
    @State private var choosingFolder = false
    /// Show in Sidebar (board): the connection's folder becomes a source.
    @State private var showsInSidebar = true

    enum TestState: Equatable {
        case idle, running, passed
        case failed(String)
    }

    init(editing server: FileServer? = nil, saved: @escaping (FileServer) -> Void) {
        self.saved = saved
        _draft = State(initialValue: server.map(FileServerDraft.init(server:)) ?? FileServerDraft())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.isNew ? String(localized: "Add Connection", comment: "Mac server form title")
                                 : String(localized: "Edit Connection", comment: "Mac server form title: editing"))
                    .font(.headline)
                Text("Upload originals to a NAS or another computer, and browse the photos on it.",
                     comment: "Mac server form: one-line explanation")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding([.horizontal, .top], 24)
            .padding(.bottom, 8)
            Form {
                if draft.isNew, let discovery { nearby(discovery) }
                Section {
                    TextField(String(localized: "Name:", comment: "Mac server form row"), text: $draft.server.name,
                              prompt: Text(draft.server.host.isEmpty ? "NAS Home" : draft.server.host))
                    Picker(String(localized: "Protocol:", comment: "Mac server form row"), selection: $draft.server.transferProtocol) {
                        ForEach(FileServer.TransferProtocol.network, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent(String(localized: "Host:", comment: "Mac server form row")) {
                        HStack {
                            TextField(String(localized: "Host", comment: "Mac server form field"), text: $draft.server.host,
                                      prompt: Text(verbatim: "nas-home.local"))
                                .labelsHidden()
                            TextField(String(localized: "Port", comment: "Mac server form field"), text: $draft.portText,
                                      prompt: Text(verbatim: String(draft.server.defaultPort)))
                                .labelsHidden()
                                .frame(width: 64)
                        }
                    }
                    if draft.server.transferProtocol == .webdav {
                        TextField(String(localized: "Path:", comment: "Mac server form row: WebDAV path"), text: $draft.server.share)
                    }
                    TextField(String(localized: "Username:", comment: "Mac server form row"), text: $draft.server.username)
                    SecureField(String(localized: "Password:", comment: "Mac server form row"), text: $draft.password,
                                prompt: draft.hasSavedPassword ? Text("Saved", comment: "Mac server form: a password is stored") : nil)
                    LabeledContent(String(localized: "Folder:", comment: "Mac server form row")) {
                        HStack {
                            TextField(String(localized: "Folder", comment: "Mac server form field"), text: $draft.server.folder,
                                      prompt: Text(verbatim: "Photos/2026"))
                                .labelsHidden()
                            Button(String(localized: "Choose…", comment: "Mac server form: browse the server for a folder")) { choosingFolder = true }
                                .disabled(draft.server.host.isEmpty || draft.server.username.isEmpty)
                        }
                    }
                    Toggle(String(localized: "Show in Sidebar", comment: "Mac server form: add the folder as a source"), isOn: $showsInSidebar)
                } footer: {
                    Text("Choose… signs in and lists the folders this computer shares. Show in Sidebar adds a row for this folder under Sources.",
                         comment: "Mac server form: folder footer")
                }
                Section {
                    HStack(spacing: 12) {
                        Button(String(localized: "Test Connection", comment: "File server form: try the connection")) { runTest() }
                            .disabled(!draft.canSave || test == .running)
                        testStatus
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                if let saveError { Text(saveError).foregroundStyle(.red).lineLimit(2) }
                Spacer()
                Button(String(localized: "Cancel", comment: "Mac sheet: cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(draft.isNew ? String(localized: "Add Connection", comment: "Mac server form: save a new connection")
                                   : String(localized: "Save", comment: "Mac server form: save changes")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.canSave)
            }
            .padding(20)
        }
        .frame(width: 520, height: 600)
        .tint(MacTheme.accent)
        .task {
            if !draft.isNew {
                showsInSidebar = ((try? SourceStore(database: dependencies.database).serverSourceId(connectionId: draft.server.id)) ?? nil) != nil
            }
            guard draft.isNew, discovery == nil else { return }
            let model = ServerDiscoveryModel(browser: BonjourServerBrowser(), scanner: SubnetSMBScanner())
            discovery = model
            model.start()
        }
        .onDisappear { discovery?.stop() }
        .sheet(isPresented: $choosingFolder) {
            MacServerFolderPicker(server: draft.normalized, password: effectivePassword, start: draft.server.folder) {
                draft.server.folder = $0
            }
        }
        .alert(String(localized: "Trust this server?", comment: "SFTP host key not yet trusted"),
               isPresented: Binding(get: { untrustedFingerprint != nil }, set: { if !$0 { untrustedFingerprint = nil } }),
               presenting: untrustedFingerprint) { fingerprint in
            Button(String(localized: "Trust", comment: "SFTP: trust the host key")) {
                draft.server.trustedFingerprint = fingerprint
                runTest()
            }
            Button(String(localized: "Cancel", comment: "Mac sheet: cancel"), role: .cancel) {}
        } message: { fingerprint in
            Text(fingerprint).monospaced()
        }
    }

    /// Nearby (board): a popup of the machines found on this network;
    /// picking one fills its name, protocol and address.
    private func nearby(_ discovery: ServerDiscoveryModel) -> some View {
        Section {
            switch discovery.state {
            case .searching:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for servers…", comment: "Mac server form: discovery running").foregroundStyle(.secondary)
                }
            case .found(let servers):
                Picker(String(localized: "Nearby:", comment: "Mac server form row: servers found on the network"),
                       selection: Binding<String?>(get: { nil }, set: { id in
                           if let server = servers.first(where: { $0.id == id }) { fill(from: server) }
                       })) {
                    Text("Choose a Server", comment: "Mac server form: Nearby popup placeholder").tag(String?.none)
                    ForEach(servers) { server in
                        Text(verbatim: "\(server.name) — \(server.protocolSummary)").tag(Optional(server.id))
                    }
                }
            case .none:
                Text("No servers found. Enter the address below.", comment: "Mac server form: discovery found nothing")
                    .foregroundStyle(.secondary)
            case .denied:
                Text("ShotDex can't look for servers because Local Network access is off.",
                     comment: "Mac server form: local network permission denied")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            if case .found(let servers) = discovery.state {
                Text(discovery.isSearching
                     ? String(localized: "\(servers.count) found on this network · still looking. Picking one fills in its address.", comment: "Mac server form: Nearby footer while searching")
                     : String(localized: "\(servers.count) found on this network. Picking one fills in its address.", comment: "Mac server form: Nearby footer"))
            }
        }
    }

    @ViewBuilder
    private var testStatus: some View {
        switch test {
        case .idle: EmptyView()
        case .running: ProgressView().controlSize(.small)
        case .passed:
            Label(String(localized: "Connected. Ready to upload.", comment: "File server Test Connection succeeded"), systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red).lineLimit(2)
        }
    }

    private func fill(from server: DiscoveredServer) {
        guard let offer = server.offers.first else { return }
        draft.server.name = server.name
        draft.server.transferProtocol = offer.service.transferProtocol
        draft.server.usesTLS = offer.service != .webdav
        draft.server.host = offer.host
        draft.portText = offer.port == draft.server.defaultPort ? "" : String(offer.port)
        test = .idle
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
            switch await FileServerConnectionCheck.run(client: client, folder: server.folder) {
            case .connected:
                test = .passed
            case .failed(_, .hostKeyUntrusted(let fingerprint)):
                test = .idle
                untrustedFingerprint = fingerprint
            case .failed(_, let error):
                test = .failed(error.localizedDescription)
            }
        }
    }

    private func save() {
        let row = draft.normalized
        do {
            try dependencies.fileServers.save(row, password: draft.password.isEmpty ? nil : draft.password)
            // The store numbers a taken name; read back what it kept.
            let kept = (try? dependencies.fileServers.fetch(id: row.id)) ?? row
            let (sources, isSource) = (dependencies.sourcesModel, showsInSidebar)
            Task { await sources.setServerSource(isSource, connection: kept) }
            saved(kept)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
