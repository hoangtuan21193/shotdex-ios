import SwiftUI

struct OnServerDestination: Hashable {}

/// One folder of one connection, pushed in the Collections stack.
struct ServerFolderRoute: Hashable {
    let connectionId: String
    let path: String
}

/// Collections → Utilities → On Server (FS-17.01 §1): the connections to
/// browse, and the photos already uploaded from this device. Tier A.
struct OnServerScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var editing: FileServerDraft?
    /// One login per connection and one model per folder, made on first
    /// push and kept — a plain class, so filling it while SwiftUI builds a
    /// destination does not invalidate the view.
    @State private var store = BrowseStore()

    final class BrowseStore {
        var sessions: [String: ServerBrowseSession] = [:]
        var folderModels: [ServerFolderRoute: ServerFolderModel] = [:]
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
                        NavigationLink(value: ServerFolderRoute(connectionId: server.id, path: "")) {
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
        .navigationDestination(for: ServerFolderRoute.self) { route in
            if let model = folderModel(for: route) {
                ServerBrowserScreen(model: model)
            } else {
                ContentUnavailableView("Connection Removed", systemImage: "server.rack")
            }
        }
    }

    private func folderModel(for route: ServerFolderRoute) -> ServerFolderModel? {
        if let model = store.folderModels[route] { return model }
        guard let server = servers.first(where: { $0.id == route.connectionId }) else { return nil }
        let session = store.sessions[server.id] ?? ServerBrowseSession(
            server: server,
            client: RemoteFileClientFactory.make(for: server, password: dependencies.fileServers.password(for: server.id) ?? "")
        )
        store.sessions[server.id] = session
        let model = ServerFolderModel(
            session: session,
            folder: route.path,
            cache: dependencies.serverThumbnails,
            downloads: dependencies.serverDownloads,
            existingAssetIds: { PhotoKitAssetCreator.existingAssetIds($0) }
        )
        store.folderModels[route] = model
        return model
    }
}
