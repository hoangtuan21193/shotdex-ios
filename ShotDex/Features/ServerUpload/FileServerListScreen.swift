import SwiftUI

/// Settings → File Servers (FS-15.01 §2): the connections originals can
/// be uploaded to. Tier A.
struct FileServerListScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var servers: [FileServer] = []
    @State private var editing: FileServerDraft?
    @State private var pendingDelete: FileServer?

    var body: some View {
        List {
            if servers.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Add a connection to upload originals to your NAS or computer. Add the same server more than once to keep a connection per folder.")
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
                Section {
                    ForEach(servers) { server in
                        Button {
                            editing = FileServerDraft(server: server)
                        } label: {
                            FileServerRow(server: server)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", role: .destructive) { pendingDelete = server }
                        }
                        // A pointer has no swipe: the same action on right-click.
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingDelete = server
                            } label: {
                                Label("Delete Connection", systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    Text("Uploads send the original files to the folder under each name. Passwords are kept in the Keychain on this device.")
                }
            }
        }
        .navigationTitle("File Servers")
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
        .formSheet(item: $editing, onDismiss: reload) { draft in
            FileServerFormScreen(draft: draft)
        }
        .deleteConnectionAlert($pendingDelete, dependencies: dependencies, onDelete: reload)
        .task { reload() }
    }

    private func reload() {
        // Cloud folders are added and renamed in Collections → On Cloud;
        // this form is for servers typed in by address.
        servers = ((try? dependencies.fileServers.fetchAll()) ?? []).filter { $0.transferProtocol.isNetwork }
    }
}

/// One connection in a list: its name and the folder it points at — what
/// tells two connections to one server apart (FS-15.01 §2).
struct FileServerRow: View {
    let server: FileServer
    /// Off inside a `NavigationLink`, which draws its own.
    var showsChevron = true

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .foregroundStyle(.primary)
                Text(server.folderDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Delete Connection, here and in Collections › Local Network: the
/// connection's source goes first — its photos leave ShotDex — then the
/// connection, as on the Mac (FS-18.04 §3 AC-77). Before 2026-11-11 only the
/// connection went, and its source stayed in Settings › Sources with no way
/// to remove it.
extension View {
    func deleteConnectionAlert(_ pending: Binding<FileServer?>, dependencies: AppDependencies,
                               onDelete: @escaping () -> Void = {}) -> some View {
        modifier(DeleteConnectionAlert(pending: pending, dependencies: dependencies, onDelete: onDelete))
    }
}

private struct DeleteConnectionAlert: ViewModifier {
    @Binding var pending: FileServer?
    let dependencies: AppDependencies
    let onDelete: () -> Void
    @State private var failure: String?

    private var deletion: ServerConnectionDeletion {
        ServerConnectionDeletion(database: dependencies.database, servers: dependencies.fileServers)
    }

    func body(content: Content) -> some View {
        content
            // `.alert`: on iOS 26 a confirmation dialog hides Cancel (DESIGN.md §10.5).
            .alert(pending.map { String(localized: "Delete “\($0.name)”?", comment: "File Servers: delete connection alert title") } ?? "",
                   isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                   presenting: pending) { server in
                Button(String(localized: "Cancel", comment: "File Servers: keep the connection"), role: .cancel) {}
                Button(String(localized: "Delete Connection", comment: "File Servers: confirm delete"), role: .destructive) { delete(server) }
            } message: { server in
                Text(ServerConnectionText.deleteMessage((try? deletion.impact(of: server.id))
                                                        ?? .init(sourceId: nil, photoCount: 0, backupJobs: 0, shortcuts: 0)))
            }
            .alert(String(localized: "Couldn’t Delete the Connection", comment: "File Servers: delete failed"),
                   isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button(String(localized: "OK", comment: "File Servers: dismiss an error")) {}
            } message: {
                Text(failure ?? "")
            }
    }

    private func delete(_ server: FileServer) {
        do {
            try deletion.delete(connectionId: server.id, readingSourceId: dependencies.sources.readingSourceId)
        } catch ServerConnectionDeletion.Failure.sourceBusy {
            failure = String(localized: "“\(server.name)” is being read. Delete it when the read finishes.",
                             comment: "File Servers: delete while its source reads")
        } catch {
            failure = error.localizedDescription
        }
        dependencies.fileServerCatalog.reload()
        dependencies.sources.refresh()
        dependencies.onServerCheck.onBatch?()
        onDelete()
    }
}
