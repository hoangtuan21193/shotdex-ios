import SwiftUI

/// + › Add a Source… (FS-23.01 §2, board `PH_MoviesAdd`): a folder on one
/// of the user's connections or in Files, or a Plex server.
struct AddMovieSourceSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @State private var path: [FolderPickerRoute] = []
    @State private var isPickingFilesFolder = false
    @State private var isAdding = false
    @State private var failure: String?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(networkServers) { server in
                        Button { chooseFolder(on: server) } label: {
                            row(
                                title: server.name,
                                detail: String(localized: "\(server.transferProtocol.title) · Choose a folder", comment: "Add a Source: a connection row; the protocol, then what tapping does"),
                                systemImage: "server.rack", tint: .blue
                            )
                        }
                    }
                    Button { isPickingFilesFolder = true } label: {
                        row(
                            title: String(localized: "Files", comment: "Add a Source: folders from the Files app"),
                            detail: String(localized: "iCloud Drive, external drives", comment: "Add a Source: what the Files row reaches"),
                            systemImage: "folder", tint: .gray
                        )
                    }
                } header: {
                    Text(String(localized: "Folder", comment: "Add a Source: section of folder sources"))
                } footer: {
                    Text(String(localized: "Every movie in the folder and its subfolders appears in Movies. They stream at home; download the ones you want to take with you.", comment: "Add a Source: what adding a folder does"))
                }

                Section {
                    // Plex sign-in arrives with plan task 30.
                    row(
                        title: String(localized: "Plex Server", comment: "Add a Source: a Plex Media Server"),
                        detail: String(localized: "Sign in with your Plex account", comment: "Add a Source: what the Plex row asks for"),
                        systemImage: "play.fill", tint: .purple
                    )
                } header: {
                    Text(String(localized: "Media Server", comment: "Add a Source: section of media servers"))
                } footer: {
                    Text(MoviesCountText.addFilesInstead())
                }
            }
            .tint(.primary)
            .disabled(isAdding)
            .overlay {
                if isAdding {
                    ProgressView(String(localized: "Looking for movies…", comment: "Add a Source: listing the chosen folder"))
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
                }
            }
            .navigationTitle(String(localized: "Add a Source", comment: "Add a Source sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Add a Source: close without adding")) { dismiss() }
                }
            }
            .navigationDestination(for: FolderPickerRoute.self) { route in
                ServerBrowserScreen(model: route.model) { chosen in
                    path = []
                    Task {
                        await route.model.session.close()
                        await add(chosen, on: route.model.session.server)
                    }
                }
            }
            .sheet(isPresented: $isPickingFilesFolder) {
                FolderPicker { url in
                    isPickingFilesFolder = false
                    guard let url else { return }
                    Task { await addFilesFolder(url) }
                }
                .ignoresSafeArea()
            }
            .alert(
                String(localized: "Couldn't Add the Folder", comment: "Add a Source: listing failed"),
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
                presenting: failure
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { Text($0) }
            .task { dependencies.fileServerCatalog.reload() }
        }
    }

    private var networkServers: [FileServer] {
        dependencies.fileServerCatalog.servers.filter(\.transferProtocol.isNetwork)
    }

    private func chooseFolder(on server: FileServer) {
        let session = ServerBrowseSession(server: server, client: RemoteFileClientFactory.make(
            for: server, password: dependencies.fileServers.password(for: server.id) ?? ""
        ))
        let dependencies = dependencies
        let picker = ServerBrowserModel(session: session, start: server.folder, mode: .chooseFolder) { folder in
            ServerFolderModel(
                session: session, folder: folder, cache: dependencies.serverThumbnails,
                downloads: dependencies.serverDownloads,
                existingAssetIds: { PhotoKitAssetCreator.existingAssetIds($0) }
            )
        }
        path.append(FolderPickerRoute(model: picker))
    }

    /// A folder picked in Files becomes a Files connection (FS-17.05 §2),
    /// then a source on it.
    private func addFilesFolder(_ url: URL) async {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? url.bookmarkData() else {
            failure = String(localized: "ShotDex can't keep access to that folder.", comment: "Add a Source: no bookmark for a Files folder")
            return
        }
        let described = FilesFolderClient.describe(url)
        let server = FileServer(
            name: described.folder, transferProtocol: .files, host: described.service,
            username: "", share: described.folder, bookmark: bookmark
        )
        do {
            try dependencies.fileServers.save(server, password: nil)
            dependencies.fileServerCatalog.reload()
        } catch {
            failure = error.localizedDescription
            return
        }
        await add("", on: server)
    }

    private func add(_ folder: String, on server: FileServer) async {
        isAdding = true
        defer { isAdding = false }
        do {
            try await dependencies.movieSync.addFolder(folder, on: server)
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Tile, name and what tapping does, with a chevron: every row leads
    /// somewhere (board `PH_MoviesAdd`).
    private func row(title: String, detail: String, systemImage: String, tint: SettingsTint) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            SettingsTileIcon(systemImage: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
