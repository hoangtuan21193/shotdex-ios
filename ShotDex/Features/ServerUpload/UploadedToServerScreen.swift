import SwiftUI

struct UploadedToServerDestination: Hashable {}

/// Collections → Utilities → Uploaded to Server (FS-15.02 §8): every photo
/// still in the library with a verified copy on at least one server, newest
/// upload first, and the "free up space later" half of the delete offer.
struct UploadedToServerScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var assetIds: [String]?
    @State private var deletable: [String] = []
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        Group {
            if let assetIds {
                PhotoListScreen(
                    title: String(localized: "Uploaded to Server"),
                    subtitle: String(localized: "\(assetIds.count) photos", comment: "Uploaded to Server subtitle: how many photos have a copy on a server"),
                    assetIds: assetIds
                )
                .id(assetIds)
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
        assetIds = ids.filter { present.contains($0) }
        deletable = verdict.deletable
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
