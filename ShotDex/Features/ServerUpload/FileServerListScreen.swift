import SwiftUI

/// Settings → File Servers (FS-15.01 §2): the servers originals can be
/// uploaded to. Tier A.
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
                        Text("Add a server to upload originals to your NAS or computer.")
                            .foregroundStyle(.secondary)
                        Button {
                            editing = FileServerDraft()
                        } label: {
                            Label("Add Server", systemImage: "plus.circle.fill")
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
                    }
                } footer: {
                    Text("Uploads send the original files over SMB or SFTP. Passwords are kept in the Keychain on this device.")
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
                .accessibilityLabel("Add Server")
            }
        }
        .sheet(item: $editing, onDismiss: reload) { draft in
            FileServerFormScreen(draft: draft)
        }
        .confirmationDialog(
            pendingDelete.map { "Delete \($0.name)?" } ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { server in
            Button("Delete Server", role: .destructive) {
                try? dependencies.fileServers.delete(id: server.id)
                reload()
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The upload history is kept, and nothing on the server or in your library is deleted.")
        }
        .task { reload() }
    }

    private func reload() {
        servers = (try? dependencies.fileServers.fetchAll()) ?? []
    }
}

/// One server in a list: name, protocol, where.
struct FileServerRow: View {
    let server: FileServer

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .foregroundStyle(.primary)
                Text("\(server.transferProtocol.title) · \(server.locationDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
