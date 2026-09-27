import SwiftUI

struct OnServerDestination: Hashable {}

/// One visit to a connection's files, pushed in the Collections stack; the
/// browser moves between folders itself (FS-17.01 §2a).
struct ServerBrowseRoute: Hashable {
    let connectionId: String
}

/// Collections → Utilities → On Server (FS-17.01 §1): the connections to
/// browse, and the photos already uploaded from this device. Tier A.
struct OnServerScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var editing: FileServerDraft?
    /// One login per connection, made on first push and kept for as long
    /// as On Server is — a plain class, so filling it while SwiftUI builds a
    /// destination does not invalidate the view.
    @State private var store = BrowseStore()

    final class BrowseStore {
        var sessions: [String: ServerBrowseSession] = [:]
    }

    private var servers: [FileServer] { dependencies.fileServerCatalog.servers }

    var body: some View {
        List {
            if servers.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Add a connection to browse and download photos from your NAS or computer.")
                            .foregroundStyle(.secondary)
                        Button {
                            editing = FileServerDraft()
                        } label: {
                            Label("Add Connection", systemImage: "plus.circle.fill")
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Section("Connections") {
                    ForEach(servers) { server in
                        NavigationLink(value: ServerBrowseRoute(connectionId: server.id)) {
                            FileServerRow(server: server, showsChevron: false)
                        }
                    }
                }
            }
            if !dependencies.serverUploadIndex.assetIds.isEmpty {
                Section {
                    NavigationLink(value: UploadedToServerDestination()) {
                        HStack {
                            Label("Uploaded from This Device", systemImage: "externaldrive.fill.badge.checkmark")
                            Spacer()
                            Text(dependencies.serverUploadIndex.assetIds.count, format: .number)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("On Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = FileServerDraft()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Connection")
            }
        }
        .sheet(item: $editing) { draft in
            FileServerFormScreen(draft: draft)
        }
        .navigationDestination(for: ServerBrowseRoute.self) { route in
            if let server = servers.first(where: { $0.id == route.connectionId }) {
                ServerBrowserHost(server: server, session: session(for: server))
            } else {
                ContentUnavailableView("Connection Removed", systemImage: "server.rack")
            }
        }
    }

    private func session(for server: FileServer) -> ServerBrowseSession {
        if let session = store.sessions[server.id] {
            if session.server == server { return session }
            // The connection was edited: its old login is stale.
            Task { await session.close() }
        }
        let session = ServerBrowseSession(
            server: server,
            client: RemoteFileClientFactory.make(for: server, password: dependencies.fileServers.password(for: server.id) ?? "")
        )
        store.sessions[server.id] = session
        return session
    }
}

/// Makes a fresh browser for each push — the history starts over on every
/// visit (FS-17.01 §2a) — on the connection's shared login.
struct ServerBrowserHost: View {
    @Environment(AppDependencies.self) private var dependencies
    let server: FileServer
    let session: ServerBrowseSession
    @State private var model: ServerBrowserModel?

    var body: some View {
        Group {
            if let model {
                ServerBrowserScreen(model: model)
            } else {
                Color.clear
            }
        }
        .onAppear {
            guard model == nil else { return }
            let dependencies = dependencies
            let session = session
            model = ServerBrowserModel(
                session: session,
                start: server.folder,
                fileHistory: dependencies.serverFileHistory,
                onUploadsForgotten: { dependencies.serverUploadIndex.reload() }
            ) { path in
                ServerFolderModel(
                    session: session,
                    folder: path,
                    cache: dependencies.serverThumbnails,
                    downloads: dependencies.serverDownloads,
                    existingAssetIds: { PhotoKitAssetCreator.existingAssetIds($0) }
                )
            }
        }
    }
}
