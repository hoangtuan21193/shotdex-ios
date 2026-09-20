import Photos
import SwiftUI
import UIKit

/// Route to the Creations list, pushed from the Collections tab.
struct CreationsDestination: Hashable {}

/// Everything ShotDex has made — collages and videos — most recently edited
/// first, and each one openable back into the editor that made it.
///
/// The exported photo already sits in the library, so this list is not another
/// way to look at it. It is the only way back to the *recipe*: which photos
/// went in, where the caption sat, how long the clip ran. Without it a collage
/// you want to change by one photo is a collage you make again from the start.
struct CreationsScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary

    @State private var creations: [Creation] = []
    @State private var isLoading = true
    @State private var reopening: ReopenRequest?
    /// A creation whose recipe no longer decodes, or whose source photos are
    /// all gone — named in an alert rather than failing silently on tap.
    @State private var unopenableMessage: String?

    /// A creation being reopened, with its source assets already fetched.
    private struct ReopenRequest: Identifiable {
        let creation: Creation
        let assets: [PHAsset]
        var id: String { creation.id }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if creations.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Creations")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: photoLibrary.assetChangeToken) { load() }
        .fullScreenCover(item: $reopening) { request in
            editor(for: request)
        }
        .alert(
            "Can't Reopen This",
            isPresented: Binding(
                get: { unopenableMessage != nil },
                set: { if !$0 { unopenableMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(unopenableMessage ?? "")
        }
    }

    @ViewBuilder
    private func editor(for request: ReopenRequest) -> some View {
        switch request.creation.kind {
        case .collage:
            CollageScreen(assets: request.assets, restoring: request.creation)
        case .video:
            VideoStudioScreen(
                assets: request.assets,
                mode: request.assets.count == 1 && request.assets[0].mediaType == .video
                    ? .singleVideo
                    : .multiClip,
                onSaved: { _ in },
                restoring: request.creation
            )
        }
    }

    private var list: some View {
        ScrollView {
            // Columns rather than one very wide row, for the reason the
            // Collections lists use a grid: a wide window gets more content,
            // not a row stretched across it.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: CreationCardMetrics.minimumWidth), spacing: AppTheme.Spacing.md)],
                alignment: .leading,
                spacing: AppTheme.Spacing.md
            ) {
                ForEach(creations) { creation in
                    Button {
                        reopen(creation)
                    } label: {
                        CreationCard(creation: creation)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            delete(creation)
                        } label: {
                            Label("Remove from Creations", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.Size.screenMargin)
            .padding(.vertical, AppTheme.Spacing.lg)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Creations Yet",
            systemImage: "wand.and.stars",
            description: Text(
                "Collages and videos you export show up here, with the photos and settings that made them — so you can open one again and change it."
            )
        )
    }

    private func load() {
        creations = (try? dependencies.creations.fetchAllOrdered()) ?? []
        isLoading = false
    }

    /// Fetches the recipe's source photos, then opens the editor on them.
    ///
    /// The sources are fetched rather than stored: a `PHAsset` cannot be
    /// persisted, and an id that no longer resolves means the user deleted
    /// that photo — which has to be said, not silently worked around with a
    /// collage that comes back a photo short.
    private func reopen(_ creation: Creation) {
        let ids = creation.sourceAssetIds
        guard !ids.isEmpty else {
            unopenableMessage = String(
                localized: "This was made by an older version of ShotDex and its settings can't be read.",
                comment: "Alert when a saved creation's stored recipe cannot be decoded"
            )
            return
        }
        let found = PhotoLibraryService.fetchAssets(ids: ids)
        guard found.count == ids.count else {
            unopenableMessage = String(
                localized: "Some of the photos this was made from are no longer in your library.",
                comment: "Alert when reopening a creation whose source photos were deleted"
            )
            return
        }
        // Back into the editor in the recipe's own order, not PhotoKit's.
        let byId = Dictionary(uniqueKeysWithValues: found.map { ($0.localIdentifier, $0) })
        reopening = ReopenRequest(
            creation: creation,
            assets: ids.compactMap { byId[$0] }
        )
    }

    private func delete(_ creation: Creation) {
        try? dependencies.creations.delete(id: creation.id)
        load()
    }
}

/// One creation: the exported picture, what it is, and when it was last
/// changed.
private struct CreationCard: View {
    let creation: Creation

    @Environment(PhotoLibraryService.self) private var photoLibrary

    @State private var thumbnail: UIImage?

    private var kindLabel: String {
        switch creation.kind {
        case .collage: String(localized: "Collage", comment: "Kind of thing in the Creations list")
        case .video: String(localized: "Video", comment: "Kind of thing in the Creations list")
        }
    }

    private var kindSymbol: String {
        switch creation.kind {
        case .collage: "square.grid.2x2"
        case .video: "film"
        }
    }

    private var subtitle: String {
        let date = Date(timeIntervalSince1970: TimeInterval(creation.updatedAt))
            .formatted(date: .abbreviated, time: .shortened)
        let count = creation.sourceAssetIds.count
        return "\(date) · \(photoCountLabel(count))"
    }

    private func photoCountLabel(_ count: Int) -> String {
        String(
            localized: "\(count) photos",
            comment: "How many photos a saved collage or video was made from"
        )
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            cover

            VStack(alignment: .leading, spacing: 2) {
                Text(kindLabel)
                    .font(.headline)
                    .foregroundStyle(Color(.label))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(AppTheme.Spacing.md)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
        )
        .task(id: creation.assetId) { await loadThumbnail() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kindLabel), \(subtitle)")
        .accessibilityHint(Text("Opens in the editor", comment: "VoiceOver hint on a row in the Creations list"))
        .accessibilityAddTraits(.isButton)
    }

    private var cover: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
            .fill(Color(.tertiarySystemBackground))
            .frame(width: CreationCardMetrics.coverSide, height: CreationCardMetrics.coverSide)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    // No cover once the export has been deleted from Photos —
                    // the recipe is still here, and that is what the row is
                    // for, so it shows what it is rather than an error.
                    Image(systemName: kindSymbol)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
    }

    private func loadThumbnail() async {
        guard let assetId = creation.assetId,
              let asset = PhotoLibraryService.fetchAssets(ids: [assetId]).first
        else {
            thumbnail = nil
            return
        }
        let side = CreationCardMetrics.coverSide * ActiveDisplay.scale
        thumbnail = await withCheckedContinuation { continuation in
            var resumed = false
            _ = photoLibrary.requestThumbnail(
                for: asset,
                targetSize: CGSize(width: side, height: side)
            ) { image, delivery in
                guard !resumed, !delivery.isDegraded else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }
}

enum CreationCardMetrics {
    /// Square cover, the same idea as an album token's well but big enough
    /// that a collage's layout is readable in it.
    static let coverSide: CGFloat = 64
    /// Narrowest a card may be, and so how many columns a window gets. Wider
    /// than a Collections row because this card carries a date and a count on
    /// its second line.
    static let minimumWidth: CGFloat = 360
}
