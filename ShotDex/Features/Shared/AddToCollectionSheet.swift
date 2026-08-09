import Photos
import SwiftUI

/// A pending "Add to Collection" request — the assets to add, wrapped so a
/// screen can drive the sheet with `.sheet(item:)`.
struct AddToCollectionPresentation: Identifiable {
    let id = UUID()
    let assets: [PHAsset]
}

/// Album picker for the selection ⋯ menu's "Add to Collection". Lists the user's
/// own albums (smart/shared excluded) and a "New Album…" row; picking one adds
/// every selected asset to it. PhotoKit keeps album membership a set, so adding
/// an asset already in the album is a harmless no-op.
struct AddToCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let assets: [PHAsset]
    let photoLibrary: PhotoLibraryService
    /// Called after a successful add so the host can leave selection mode.
    var onAdded: () -> Void

    @State private var albums: [PHAssetCollection] = []
    @State private var hasLoaded = false
    @State private var isBusy = false
    @State private var isNamingNewAlbum = false
    @State private var newAlbumName = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        newAlbumName = ""
                        isNamingNewAlbum = true
                    } label: {
                        Label("New Album…", systemImage: "plus.rectangle.on.rectangle")
                    }
                    .disabled(isBusy)
                }

                if albums.isEmpty && hasLoaded {
                    Section {
                        Text("No albums yet. Create one to add these photos.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Your Albums") {
                        ForEach(albums, id: \.localIdentifier) { album in
                            Button {
                                add(to: album)
                            } label: {
                                HStack {
                                    Label(album.localizedTitle ?? "Untitled", systemImage: "rectangle.stack")
                                    Spacer()
                                    if album.estimatedAssetCount != NSNotFound {
                                        Text(album.estimatedAssetCount.formatted())
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                }
                            }
                            .disabled(isBusy)
                        }
                    }
                }
            }
            .navigationTitle("Add to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                if isBusy {
                    ToolbarItem(placement: .topBarTrailing) { ProgressView() }
                }
            }
            .overlay {
                if !hasLoaded { ProgressView() }
            }
            .alert("New Album", isPresented: $isNamingNewAlbum) {
                TextField("Album Name", text: $newAlbumName)
                Button("Cancel", role: .cancel) {}
                Button("Create") { createAlbum() }
                    .disabled(newAlbumName.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("These \(assets.count) \(assets.count == 1 ? "item" : "items") will be added to the new album.")
            }
            .alert(
                "Couldn't Add to Album",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .task {
            guard !hasLoaded else { return }
            albums = PhotoLibraryService.fetchUserAlbums()
            hasLoaded = true
        }
    }

    private func add(to album: PHAssetCollection) {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await photoLibrary.addAssets(assets, to: album)
                onAdded()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func createAlbum() {
        let name = newAlbumName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let album = try await photoLibrary.createAlbum(named: name)
                try await photoLibrary.addAssets(assets, to: album)
                onAdded()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
