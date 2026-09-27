import SwiftUI

struct UploadedToServerDestination: Hashable {}

/// Collections → Utilities → Uploaded to Server (FS-15.02 §8): where the
/// copies are — one row per connection and folder, each opening its photos —
/// and the "free up space later" half of the delete offer.
struct UploadedToServerScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var assetIds: [String]?
    @State private var destinations: [UploadDestination] = []
    @State private var deletable: [String] = []
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        Group {
            if let assetIds {
                List {
                    Section {
                        ForEach(destinations) { destination in
                            NavigationLink {
                                PhotoListScreen(
                                    title: destination.connectionName,
                                    subtitle: destination.folder.isEmpty ? "/" : destination.folder,
                                    assetIds: destination.assetIds,
                                    showsMakeVideo: false
                                )
                            } label: {
                                destinationRow(destination)
                            }
                        }
                    } header: {
                        Text("Where They Are")
                    } footer: {
                        Text("Each photo is listed under every server folder it was uploaded to.")
                    }
                    Section {
                        NavigationLink {
                            PhotoListScreen(
                                title: String(localized: "Uploaded to Server"),
                                subtitle: String(localized: "\(assetIds.count) photos", comment: "Uploaded to Server subtitle: how many photos have a copy on a server"),
                                assetIds: assetIds,
                                showsMakeVideo: false
                            )
                        } label: {
                            HStack {
                                Label("All Uploaded Photos", systemImage: "photo.on.rectangle")
                                Spacer()
                                Text(assetIds.count, format: .number)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle("Uploaded to Server")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ProgressView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete \(deletable.count) from This Device", systemImage: "trash")
                    }
                    .disabled(deletable.isEmpty || isDeleting)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .tint(.primary)
                .accessibilityLabel("More")
            }
        }
        .alert(
            String(localized: "Delete \(deletable.count) Photos from This Device?", comment: "Uploaded to Server: confirm deleting every fully uploaded photo"),
            isPresented: $isConfirmingDelete
        ) {
            Button("Delete", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only photos whose every original file is verified on a server are included. They move to Recently Deleted and free up space after 30 days, or when you empty it in Photos. If iCloud Photos is on, they are also deleted from iCloud and your other devices.")
        }
        .alert(
            "Couldn't Delete Photos",
            isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } }),
            presenting: deleteError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
        .task { await load() }
    }

    private func load() async {
        let store = dependencies.serverUploads
        let ids = await Task.detached(priority: .userInitiated) {
            (try? store.uploadedAssetIdsNewestFirst()) ?? []
        }.value
        let verdict = await Task.detached(priority: .utility) {
            let entries = PhotoKitOriginalExporter.entries(for: ids)
            let keys = (try? store.uploadedFileKeys(assetIds: entries.map(\.assetId))) ?? [:]
            return ServerUploadEligibility.evaluate(assets: entries.map { ($0.assetId, $0.files) }, uploadedKeys: keys)
        }.value
        // Photos no longer in the library drop out here, not only in the grid.
        let present = Set(verdict.deletable).union(verdict.missing.keys)
        let rows = await Task.detached(priority: .userInitiated) { (try? store.destinationRows()) ?? [] }.value
        destinations = UploadDestinations.group(rows, present: present)
        assetIds = ids.filter { present.contains($0) }
        deletable = verdict.deletable
    }

    /// Connection name, the folder under it, how many photos.
    private func destinationRow(_ destination: UploadDestination) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(destination.connectionName)
                Text(destination.folder.isEmpty ? "/" : destination.folder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            Text(destination.assetIds.count, format: .number)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func delete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await dependencies.photoLibrary.deleteAssets(PhotoLibraryService.fetchAssets(ids: deletable))
            try? dependencies.metadataStore.deleteAssets(ids: deletable)
            assetIds = nil
            await load()
        } catch {
            let nsError = error as NSError
            // Declining the system's confirmation is a cancel.
            if nsError.domain == "PHPhotosErrorDomain", nsError.code == 3072 { return }
            deleteError = error.localizedDescription
        }
    }
}
