import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct OnCloudDestination: Hashable {}

/// One cloud folder, pushed from On Cloud.
struct CloudBrowseRoute: Hashable {
    let connectionId: String
}

/// Collections → Utilities → On Cloud (FS-17.05 §2): folders of Dropbox,
/// Google Drive, OneDrive, iCloud Drive… picked in the Files app, each used
/// like a connection. Tier A.
struct OnCloudScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var isPicking = false
    @State private var pending: PendingFolder?
    @State private var renaming: FileServer?
    @State private var typedName = ""
    @State private var removing: FileServer?
    @State private var saveError: String?

    struct PendingFolder: Identifiable {
        let id = UUID()
        let draft: FileServerDraft
    }

    private var folders: [FileServer] {
        dependencies.fileServerCatalog.servers.filter { $0.transferProtocol == .files }
    }

    var body: some View {
        List {
            if folders.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Browse and import photos from Dropbox, Google Drive, OneDrive or iCloud Drive, and upload to them. The service's app must be installed.")
                            .foregroundStyle(.secondary)
                        Button {
                            isPicking = true
                        } label: {
                            Label("Add Cloud Folder", systemImage: "plus.circle.fill")
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Section {
                    ForEach(folders) { server in
                        folderRow(server)
                    }
                } header: {
                    Text("Cloud Folders")
                } footer: {
                    Text("ShotDex can open only the folders you add here.")
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
        .navigationTitle("Cloud")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPicking = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Cloud Folder")
            }
        }
        .task { dependencies.fileServerCatalog.reload() }
        .navigationDestination(for: CloudBrowseRoute.self) { route in
            if let server = folders.first(where: { $0.id == route.connectionId }) {
                // Its own login each visit: a bookmark is cheap to open.
                ServerBrowserHost(server: server, start: "")
            } else {
                ContentUnavailableView("Folder Removed", systemImage: "folder")
            }
        }
        .sheet(isPresented: $isPicking) {
            FolderPicker { url in
                isPicking = false
                if let url { pending = Self.pendingFolder(for: url) }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $pending) { pending in
            SaveConnectionSheet(
                name: pending.draft.server.name,
                folder: pending.draft.server.folderDescription,
                placeholder: pending.draft.server.share
            ) { name, addsTile in
                var draft = pending.draft
                draft.server.name = name
                self.pending = nil
                do {
                    try ConnectionSaver.save(draft, addsTile: addsTile, servers: dependencies.fileServers, shortcuts: dependencies.serverShortcuts)
                    dependencies.fileServerCatalog.reload()
                } catch {
                    saveError = error.localizedDescription
                }
            }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { server in
            TextField("Name", text: $typedName)
            Button("Rename") {
                var renamed = server
                renamed.name = typedName.trimmingCharacters(in: .whitespaces)
                try? dependencies.fileServers.save(renamed, password: nil)
                dependencies.fileServerCatalog.reload()
            }
            .disabled(typedName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Only the name in ShotDex changes. The folder in the cloud keeps its name.", comment: "Rename a cloud folder connection")
        }
        .confirmationDialog(
            removing.map { "Remove \($0.name)?" } ?? "",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { server in
            Button("Remove", role: .destructive) {
                try? dependencies.fileServers.delete(id: server.id)
                dependencies.fileServerCatalog.reload()
                dependencies.serverShortcuts.reload()
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("ShotDex stops using this folder. Nothing in the cloud or in your library is deleted.")
        }
        .alert(
            "Couldn't Save Folder",
            isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } }),
            presenting: saveError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    private func folderRow(_ server: FileServer) -> some View {
        NavigationLink(value: CloudBrowseRoute(connectionId: server.id)) {
            FileServerRow(server: server, showsChevron: false)
        }
        .contextMenu {
            Button {
                typedName = server.name
                renaming = server
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                removing = server
            } label: {
                Label("Remove", systemImage: "minus.circle")
            }
        }
        .swipeActions {
            Button("Remove", role: .destructive) { removing = server }
            Button("Rename") {
                typedName = server.name
                renaming = server
            }
        }
    }

    /// The picked folder as a Files connection, not yet saved: the
    /// bookmark keeps access across launches (FS-17.05 §2).
    private static func pendingFolder(for url: URL) -> PendingFolder? {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? url.bookmarkData() else { return nil }
        let described = FilesFolderClient.describe(url)
        var draft = FileServerDraft()
        draft.server = FileServer(
            name: described.folder, transferProtocol: .files, host: described.service,
            username: "", share: described.folder, bookmark: bookmark
        )
        return PendingFolder(draft: draft)
    }
}

/// The system's folder picker (Files): every provider the user has.
struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}
