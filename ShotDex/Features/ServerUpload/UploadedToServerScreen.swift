import Photos
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
    /// Server sources the deletable photos stay in (FS-19.03 §8).
    @State private var keepingSources: [String] = []
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if let assetIds {
                Group {
                    if horizontalSizeClass == .regular {
                        folderCards(assetIds: assetIds)
                    } else {
                        folderList(assetIds: assetIds)
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
                        keepingSources = (try? dependencies.serverUploads.keepingSources(assetIds: deletable)) ?? []
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
            Text(FreeUpSpaceNote.message(
                String(localized: "Only photos whose every original file is verified on a server are included. They move to Recently Deleted and free up space after 30 days, or when you empty it in Photos. If iCloud Photos is on, they are also deleted from iCloud and your other devices."),
                keepingSources: keepingSources
            ))
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

    private func folderList(assetIds: [String]) -> some View {
        List {
            Section {
                ForEach(destinations) { destination in
                    NavigationLink {
                        folderPhotos(destination)
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
                    allPhotos(assetIds)
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
    }

    /// Regular width: each folder is a card with three of its photos, three
    /// or more across (board `DI_UploadedToServer`). The phone's one-column
    /// list stretched over 867pt was mostly empty row.
    private func folderCards(assetIds: [String]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Where They Are")
                        .textCase(.uppercase)
                    Spacer()
                    Text(folderSummary)
                        .monospacedDigit()
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, AppTheme.Spacing.lg)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240), spacing: AppTheme.Spacing.md)],
                    spacing: AppTheme.Spacing.md
                ) {
                    NavigationLink {
                        allPhotos(assetIds)
                    } label: {
                        UploadedFolderCard(
                            title: String(localized: "All Uploaded Photos"),
                            detail: String(localized: "Every folder", comment: "Uploaded to Server, wide layout: under the card that holds every uploaded photo"),
                            count: assetIds.count,
                            systemImage: "photo.on.rectangle",
                            isFeatured: true,
                            assetIds: Array(assetIds.prefix(3))
                        )
                    }
                    ForEach(destinations) { destination in
                        NavigationLink {
                            folderPhotos(destination)
                        } label: {
                            UploadedFolderCard(
                                title: destination.connectionName,
                                detail: destination.folder.isEmpty ? "/" : destination.folder,
                                count: destination.assetIds.count,
                                systemImage: "externaldrive.connected.to.line.below",
                                isFeatured: false,
                                assetIds: Array(destination.assetIds.prefix(3))
                            )
                        }
                    }
                }
                .buttonStyle(.plain)
                Text("Each photo is listed under every server folder it was uploaded to.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppTheme.Spacing.lg)
            }
            .padding(.horizontal, AppTheme.Spacing.xl)
            .padding(.vertical, AppTheme.Spacing.sm)
        }
        .background(Color(.systemGroupedBackground))
    }

    /// "4 folders on 2 servers".
    private var folderSummary: String {
        let servers = Set(destinations.map(\.connectionName)).count
        return String(AttributedString(
            localized: "^[\(destinations.count) folder](inflect: true) on ^[\(servers) server](inflect: true)",
            comment: "Uploaded to Server, wide layout: how many folders hold copies, on how many servers"
        ).characters)
    }

    private func folderPhotos(_ destination: UploadDestination) -> some View {
        PhotoListScreen(
            title: destination.connectionName,
            subtitle: destination.folder.isEmpty ? "/" : destination.folder,
            assetIds: destination.assetIds,
            showsMakeVideo: false
        )
    }

    private func allPhotos(_ assetIds: [String]) -> some View {
        PhotoListScreen(
            title: String(localized: "Uploaded to Server"),
            subtitle: String(AttributedString(localized: "^[\(assetIds.count) photo](inflect: true)", comment: "Uploaded to Server subtitle: how many photos have a copy on a server").characters),
            assetIds: assetIds,
            showsMakeVideo: false
        )
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

/// One folder on the wide layout: three of its photos over its name, path
/// and count.
private struct UploadedFolderCard: View {
    let title: String
    let detail: String
    let count: Int
    let systemImage: String
    let isFeatured: Bool
    let assetIds: [String]

    @Environment(PhotoLibraryService.self) private var photoLibrary
    @State private var assets: [PHAsset] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Color(.tertiarySystemFill)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if index < assets.count {
                                UploadedFolderThumbnail(asset: assets[index], photoLibrary: photoLibrary)
                            }
                        }
                        .clipped()
                }
            }
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(isFeatured ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(detail)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Text(verbatim: "· \(count.formatted())")
                            .monospacedDigit()
                            .fixedSize()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, 10)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle.app(AppTheme.Radius.lg))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(title), \(detail)"))
        .accessibilityValue(Text("^[\(count) photo](inflect: true)"))
        .task(id: assetIds) {
            let fetched = PhotoLibraryService.fetchAssets(ids: assetIds)
            // PhotoKit returns its own order; keep the ids' — newest first.
            let byId = Dictionary(fetched.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
            assets = assetIds.compactMap { byId[$0] }
        }
    }
}

private struct UploadedFolderThumbnail: View {
    let asset: PHAsset
    let photoLibrary: PhotoLibraryService
    @State private var image: UIImage?
    @State private var request: PHImageRequestID?

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .onAppear { load(side: proxy.size.width) }
        }
        .onDisappear {
            if let request { photoLibrary.cancelThumbnailRequest(request) }
        }
    }

    private func load(side: CGFloat) {
        guard image == nil, side > 0 else { return }
        let pixels = side * ActiveDisplay.scale
        request = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: pixels, height: pixels)
        ) { image in
            if let image { self.image = image }
        }
    }
}
