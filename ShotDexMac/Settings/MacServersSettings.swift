import SwiftUI

/// Settings › Servers (board `MAC_SettingsServers`, AC-77): every connection
/// with its address and what it is used for, Add, Edit, Test and Delete;
/// and the server part of the preview cache.
struct MacServersSettings: View {
    @Environment(MacDependencies.self) private var dependencies
    @State private var rows: [ConnectionRow] = []
    @State private var selection: String?
    @State private var tests: [String: TestState] = [:]
    @State private var deleting: (server: FileServer, impact: ServerConnectionDeletion.Impact)?
    @State private var failure: String?
    @State private var form: FormRequest?
    @State private var thumbnailBytes: Int64?
    /// Bonjour only, no subnet sweep: enough to learn whether Local Network
    /// access is on. Made once, when the pane first shows.
    @State private var discovery: ServerDiscoveryModel?

    enum TestState: Equatable {
        case running
        case passed
        case failed(String)
    }

    /// A connection with what it is for and how its source is, read once per reload.
    struct ConnectionRow: Identifiable {
        let server: FileServer
        let sourceId: String?
        let sourceStatus: SourceRowText.Status?
        var id: String { server.id }
    }

    struct FormRequest: Identifiable {
        let id = UUID()
        var editing: FileServer?
    }

    var body: some View {
        Form {
            Section {
                connectionsTable
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Connections", comment: "Mac Settings › Servers group")
                    Spacer()
                    Text(verbatim: "SMB · SFTP · WebDAV").font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text("A connection added as a source is indexed like a folder and shows under Sources; the others are upload destinations. Passwords are kept in your Keychain. Deleting a connection never deletes anything on the server.",
                     comment: "Mac Settings › Servers footer")
                    .foregroundStyle(.secondary)
            }
            localNetworkSection
            thumbnailsSection
        }
        .formStyle(.grouped)
        .task {
            reload()
            if discovery == nil {
                let model = ServerDiscoveryModel(browser: BonjourServerBrowser())
                discovery = model
                model.start()
            }
            await measureThumbnails()
        }
        .onDisappear {
            discovery?.stop()
            discovery = nil
        }
        // The prompt closed, or the user is back from System Settings: a refusal is looked at again.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            discovery?.appBecameActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macServersChanged)) { _ in reload() }
        .onChange(of: dependencies.sourcesModel.readCount) { _, _ in reload() }
        .onChange(of: dependencies.sourcesModel.readingSourceId) { _, _ in reload() }
        .sheet(item: $form) { request in
            MacServerFormSheet(editing: request.editing) { saved in
                tests[saved.id] = nil
                reload()
                NotificationCenter.default.post(name: .macServersChanged, object: nil)
            }
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { target in
            Button(String(localized: "Delete Connection", comment: "Mac Settings › Servers: confirm delete"), role: .destructive) {
                delete(target.server)
            }
            Button(String(localized: "Cancel", comment: "Mac Settings › Servers: keep the connection"), role: .cancel) {}
        } message: { target in
            Text(ServerConnectionText.deleteMessage(target.impact))
        }
        .alert(String(localized: "The Connection Was Not Deleted", comment: "Mac Settings › Servers: delete failed"),
               isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button(String(localized: "OK", comment: "Mac Settings › Servers: dismiss an error")) {}
        } message: {
            Text(failure ?? "")
        }
    }

    // MARK: Table

    private var connectionsTable: some View {
        VStack(spacing: 6) {
            Table(rows, selection: $selection) {
                TableColumn(String(localized: "Name", comment: "Mac Settings › Servers column")) { row in
                    Label(row.server.name, systemImage: symbol(row.server)).lineLimit(1)
                }
                TableColumn(String(localized: "Host", comment: "Mac Settings › Servers column")) { row in
                    Text(row.server.host).foregroundStyle(.secondary).lineLimit(1)
                }
                TableColumn(String(localized: "Protocol", comment: "Mac Settings › Servers column")) { row in
                    Text(row.server.transferProtocol.title).foregroundStyle(.secondary)
                }
                .width(70)
                TableColumn(String(localized: "Folder", comment: "Mac Settings › Servers column")) { row in
                    Text(row.server.folder.isEmpty ? "/" : row.server.folder).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                TableColumn(String(localized: "Status", comment: "Mac Settings › Servers column")) { row in
                    status(row)
                }
                .width(min: 120, ideal: 150)
            }
            .alternatingRowBackgrounds()
            .frame(height: CGFloat(28 + max(rows.count, 2) * 24))
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let row = rows.first(where: { $0.id == id }) {
                    Button(String(localized: "Test", comment: "Mac Settings › Servers: test a connection")) { test(row.server) }
                    Button(String(localized: "Edit…", comment: "Mac Settings › Servers: edit a connection")) { form = FormRequest(editing: row.server) }
                    Divider()
                    Button(String(localized: "Delete…", comment: "Mac Settings › Servers: delete a connection"), role: .destructive) { askDelete(row) }
                        .disabled(isReading(row))
                }
            } primaryAction: { ids in
                if let id = ids.first, let row = rows.first(where: { $0.id == id }) { form = FormRequest(editing: row.server) }
            }
            .onDeleteCommand { if let selected { askDelete(selected) } }
            HStack(spacing: 8) {
                Button(String(localized: "Add Connection", comment: "Mac Settings › Servers: new connection"), systemImage: "plus") {
                    form = FormRequest(editing: nil)
                }
                .labelStyle(.iconOnly)
                .help(String(localized: "Add Connection", comment: "Mac Settings › Servers: + help"))
                Button(String(localized: "Delete Connection", comment: "Mac Settings › Servers: delete the selected connection"), systemImage: "minus") {
                    if let selected { askDelete(selected) }
                }
                .labelStyle(.iconOnly)
                .disabled(selected == nil || selected.map(isReading) == true)
                .help(String(localized: "Delete Connection", comment: "Mac Settings › Servers: − help"))
                Spacer()
                Button(String(localized: "Test", comment: "Mac Settings › Servers: test the selected connection")) {
                    if let selected { test(selected.server) }
                }
                .disabled(selected == nil || tests[selection ?? ""] == .running)
                Button(String(localized: "Edit…", comment: "Mac Settings › Servers: edit the selected connection")) {
                    form = FormRequest(editing: selected?.server)
                }
                .disabled(selected == nil)
            }
        }
    }

    /// AC-78: whether macOS lets ShotDex see the network, and where to change it.
    private var localNetworkSection: some View {
        let line = discovery.map {
            LocalNetworkAccessLine.from(isSearching: $0.state == .searching, isDenied: $0.state == .denied,
                                        refusedBeforePrompt: $0.deniedWhilePrompting)
        } ?? .checking
        let open = Button(String(localized: "Open Privacy Settings…", comment: "Mac Settings › Servers: open Local Network privacy")) {
            NSWorkspace.shared.open(LocalNetworkAccessLine.privacySettingsURL)
        }
        return Section {
            LabeledContent {
                // Prominent only when it is the way out; quiet otherwise (the only way to revoke).
                if line == .off {
                    open.buttonStyle(.borderedProminent).tint(MacTheme.accent)
                } else {
                    open.disabled(line == .checking)
                }
            } label: {
                Text("Local Network Access", comment: "Mac Settings › Servers row")
                HStack(spacing: 5) {
                    Circle().fill(line == .off ? Color.orange : line == .allowed ? .green : .gray)
                        .frame(width: 7, height: 7).accessibilityHidden(true)
                    Text(line.text).foregroundStyle(line == .off ? Color.orange : .secondary)
                }
            }
        } header: {
            Text("On This Network", comment: "Mac Settings › Servers group")
        }
    }

    private var thumbnailsSection: some View {
        Section {
            LabeledContent {
                HStack(spacing: 12) {
                    Text(thumbnailBytes.map { $0 == 0 ? String(localized: "Empty", comment: "Mac Settings › Servers: no thumbnails cached")
                                                      : $0.formatted(.byteCount(style: .file)) } ?? "—")
                        .foregroundStyle(.secondary).monospacedDigit()
                    Button(String(localized: "Clear Cache", comment: "Mac Settings › Servers: drop server thumbnails")) {
                        Task {
                            await Task.detached { RemoteThumbnailCache.standard.removeAll() }.value
                            await measureThumbnails()
                        }
                    }
                    .disabled(thumbnailBytes == nil || thumbnailBytes == 0)
                }
            } label: {
                Text("Thumbnail Cache", comment: "Mac Settings › Servers row")
                Text("Previews of indexed server photos, for browsing while the server is off", comment: "Mac Settings › Servers row explanation")
            }
        } header: {
            Text("Server Thumbnails", comment: "Mac Settings › Servers group")
        } footer: {
            Text("Part of the Preview Cache; its size limit is in Sources. Originals are never stored here; they download when you open, edit or export a photo.",
                 comment: "Mac Settings › Servers footer")
                .foregroundStyle(.secondary)
        }
    }

    private var selected: ConnectionRow? { rows.first { $0.id == selection } }

    private func isReading(_ row: ConnectionRow) -> Bool {
        row.sourceId != nil && dependencies.sourcesModel.readingSourceId == row.sourceId
    }

    private func status(_ row: ConnectionRow) -> some View {
        let line = statusLine(row)
        return HStack(spacing: 5) {
            Circle().fill(line.color).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(line.text).lineLimit(1)
        }
        .foregroundStyle(line.color == .red ? Color.red : .primary)
        .help(line.text)
    }

    /// A test just run says how it went; otherwise what the connection is for
    /// and, for a source, how its last read went. Green only when known good.
    private func statusLine(_ row: ConnectionRow) -> (text: String, color: Color) {
        switch tests[row.id] {
        case .running: return (String(localized: "Testing…", comment: "Mac Settings › Servers: a test runs"), .gray)
        case .passed: return (String(localized: "Connected", comment: "Mac Settings › Servers: the test went through"), .green)
        case .failed(let message): return (message, .red)
        case nil: break
        }
        guard row.sourceId != nil else {
            return (String(localized: "Upload only", comment: "Mac Settings › Servers: a connection that is not a source"), .gray)
        }
        switch row.sourceStatus {
        case .passwordRejected: return (String(localized: "Password rejected", comment: "Mac Settings › Servers status"), .red)
        case .offline: return (String(localized: "Not reachable", comment: "Mac Settings › Servers status"), .gray)
        case .reading: return (String(localized: "Reading…", comment: "Mac Settings › Servers: its source is being read"), .gray)
        default: return (String(localized: "Source · indexed", comment: "Mac Settings › Servers: a connection read as a source"), .green)
        }
    }

    private func symbol(_ server: FileServer) -> String {
        switch server.transferProtocol {
        case .webdav: "globe"
        case .sftp: "laptopcomputer"
        default: "server.rack"
        }
    }

    // MARK: Actions

    /// Runs on every source read's tick: the servers and their source ids
    /// are read off the main actor (hang report 2026-11-08).
    private func reload() {
        let store = SourceStore(database: dependencies.database)
        let fileServers = dependencies.fileServers
        let statuses = Dictionary(dependencies.sourcesModel.rows.map { ($0.id, $0.text.status) }) { first, _ in first }
        Task {
            // A Files connection (iPhone and iPad) has no place on the Mac.
            let read = await Task.detached(priority: .userInitiated) {
                ((try? fileServers.fetchAll()) ?? []).filter { $0.transferProtocol.isNetwork }.map { server in
                    (server, (try? store.serverSourceId(connectionId: server.id)) ?? nil)
                }
            }.value
            rows = read.map { server, sourceId in
                ConnectionRow(server: server, sourceId: sourceId, sourceStatus: sourceId.flatMap { statuses[$0] })
            }
            if let selection, !rows.contains(where: { $0.id == selection }) { self.selection = nil }
            if selection == nil { selection = rows.first?.id }
            tests = tests.filter { id, _ in rows.contains { $0.id == id } }
        }
    }

    private func test(_ server: FileServer) {
        tests[server.id] = .running
        let client = RemoteFileClientFactory.make(for: server, password: dependencies.fileServers.password(for: server.id) ?? "")
        Task {
            let outcome = await FileServerConnectionCheck.run(client: client, folder: server.folder)
            // Deleted meanwhile: the answer has nowhere to go.
            guard rows.contains(where: { $0.id == server.id }) else { return }
            switch outcome {
            case .connected:
                tests[server.id] = .passed
            case .failed(_, .hostKeyUntrusted):
                tests[server.id] = .failed(String(localized: "Not trusted yet — trust its key in Edit…", comment: "Mac Settings › Servers: an SFTP key to trust"))
            case .failed(_, let error):
                tests[server.id] = .failed(error.localizedDescription)
            }
        }
    }

    private var deleteTitle: String {
        guard let deleting else { return "" }
        return String(localized: "Delete “\(deleting.server.name)”?", comment: "Mac Settings › Servers: delete dialog title")
    }

    private func askDelete(_ row: ConnectionRow) {
        guard !isReading(row) else { return }
        do {
            deleting = (row.server, try deletion.impact(of: row.id))
        } catch {
            failure = error.localizedDescription
        }
    }

    private var deletion: ServerConnectionDeletion {
        ServerConnectionDeletion(database: dependencies.database, servers: dependencies.fileServers)
    }

    /// Its source first (the photos leave ShotDex), then the connection, its
    /// password and what hangs off it; stops at the first step that fails.
    private func delete(_ server: FileServer) {
        do {
            try deletion.delete(connectionId: server.id, readingSourceId: dependencies.sourcesModel.readingSourceId)
        } catch ServerConnectionDeletion.Failure.sourceBusy {
            failure = String(localized: "“\(server.name)” is being read. Delete it when the read finishes.",
                             comment: "Mac Settings › Servers: delete while its source reads")
        } catch {
            failure = error.localizedDescription
        }
        tests[server.id] = nil
        dependencies.sourcesModel.load()
        dependencies.backupControl.sourcesChanged()
        NotificationCenter.default.post(name: .macServersChanged, object: nil)
        reload()
    }

    private func measureThumbnails() async {
        thumbnailBytes = await Task.detached {
            PreviewCacheStore(directory: RemoteThumbnailCache.standard.directory).usage()
        }.value
    }
}
