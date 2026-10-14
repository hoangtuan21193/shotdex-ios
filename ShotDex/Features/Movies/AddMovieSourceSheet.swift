import SwiftUI

/// + › Add a Source… (FS-23.01 §2, board `PH_MoviesAdd`): a folder on one
/// of the user's connections or in Files, or a Plex server.
struct AddMovieSourceSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(networkServers) { server in
                        row(
                            title: server.name,
                            detail: String(localized: "\(server.transferProtocol.title) · Choose a folder", comment: "Add a Source: a connection row; the protocol, then what tapping does"),
                            systemImage: "server.rack"
                        )
                    }
                    row(
                        title: String(localized: "Files", comment: "Add a Source: folders from the Files app"),
                        detail: String(localized: "iCloud Drive, external drives", comment: "Add a Source: what the Files row reaches"),
                        systemImage: "folder"
                    )
                } header: {
                    Text(String(localized: "Folder", comment: "Add a Source: section of folder sources"))
                } footer: {
                    Text(String(localized: "Every movie in the folder and its subfolders appears in Movies. They stream at home; download the ones you want to take with you.", comment: "Add a Source: what adding a folder does"))
                }

                Section {
                    row(
                        title: String(localized: "Plex Server", comment: "Add a Source: a Plex Media Server"),
                        detail: String(localized: "Sign in with your Plex account", comment: "Add a Source: what the Plex row asks for"),
                        systemImage: "play.tv"
                    )
                } header: {
                    Text(String(localized: "Media Server", comment: "Add a Source: section of media servers"))
                } footer: {
                    Text(MoviesCountText.addFilesInstead())
                }
            }
            .navigationTitle(String(localized: "Add a Source", comment: "Add a Source sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Add a Source: close without adding")) { dismiss() }
                }
            }
            .task { dependencies.fileServerCatalog.reload() }
        }
    }

    private var networkServers: [FileServer] {
        dependencies.fileServerCatalog.servers.filter(\.transferProtocol.isNetwork)
    }

    /// Wired to the folder browser and Plex sign-in in plan tasks 9 and 30.
    private func row(title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
