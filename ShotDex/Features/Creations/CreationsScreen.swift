import Photos
import SwiftUI
import UIKit

/// Route to one kind of creation, pushed from the Collections tab. Collages
/// and videos are separate destinations: "Creations" as a single row said
/// nothing about what was in it, and the two are made by different editors
/// from different starting points.
struct CreationsDestination: Hashable {
    let kind: Creation.Kind
}

/// Everything ShotDex has made — collages and videos — most recently edited
/// first, and each one openable back into the editor that made it.
///
/// The exported photo already sits in the library, so this list is not another
/// way to look at it. It is the only way back to the *recipe*: which photos
/// went in, where the caption sat, how long the clip ran. Without it a collage
/// you want to change by one photo is a collage you make again from the start.
struct CreationsScreen: View {
    let kind: Creation.Kind

    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary

    @State private var creations: [Creation] = []
    @State private var isLoading = true
    @State private var reopening: ReopenRequest?
    /// A brand-new collage or video, opened on the photos just picked.
    @State private var starting: NewProject?
    @State private var isPickerPresented = false
    /// A creation whose recipe no longer decodes, or whose source photos are
    /// all gone — named in an alert rather than failing silently on tap.
    @State private var unopenableMessage: String?

    /// The photos a new project starts from, wrapped so `fullScreenCover`
    /// has something identifiable to present on.
    private struct NewProject: Identifiable {
        let assets: [PHAsset]
        let id = UUID()
    }

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
        .navigationTitle(listTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPickerPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .tint(.primary)
                .accessibilityLabel(newLabel)
            }
        }
        .task(id: photoLibrary.assetChangeToken) { load() }
        .fullScreenCover(item: $reopening) { request in
            editor(for: request)
        }
        .fullScreenCover(item: $starting) { project in
            newEditor(with: project.assets)
        }
        .sheet(isPresented: $isPickerPresented) {
            VideoMediaPicker(
                selectionLimit: kind == .collage ? CollageEditorModel.slotRange.upperBound : 0,
                filter: kind == .collage ? .images : .any(of: [.images, .videos])
            ) { picks in
                start(with: picks.map(\.assetID))
            }
            .ignoresSafeArea()
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
                            Label(removeLabel, systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.Size.screenMargin)
            .padding(.vertical, AppTheme.Spacing.lg)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: kind == .collage ? "square.grid.2x2" : "film")
        } description: {
            Text(emptyDescription)
        } actions: {
            // System tint, not the app accent: `DESIGN.md` §10.6 leaves
            // standard controls at their iOS default, and no other primary
            // button in the app overrides it.
            Button(newLabel) { isPickerPresented = true }
                .buttonStyle(.borderedProminent)
        }
    }

    /// **"Video Projects", not "Videos".** Media Types already has a Videos
    /// album and it means the footage the user shot — PhotoKit names that one
    /// and we cannot rename it. These are the things the Video Studio made,
    /// and "project" is the word every video editor uses for the thing you
    /// reopen and keep working on, which is exactly what this row leads to.
    /// Collages needs no such qualifier: nothing else in the tab is called
    /// that.
    private var listTitle: String {
        switch kind {
        case .collage: String(localized: "Collages", comment: "Title of the list of collages this app made")
        case .video: String(localized: "Video Projects", comment: "Title of the list of videos this app made, distinct from the Videos media-type album of footage the user shot")
        }
    }

    /// Named after the list it removes from, not after the type. "Creations"
    /// was rejected as a word the user would recognise, so the one
    /// destructive action here must not be the place it comes back.
    private var removeLabel: String {
        switch kind {
        case .collage: String(localized: "Remove from Collages", comment: "Removes a saved collage from the Collages list — the exported photo stays in the library")
        case .video: String(localized: "Remove from Video Projects", comment: "Removes a saved video project from the Video Projects list — the exported video stays in the library")
        }
    }

    private var newLabel: String {
        switch kind {
        case .collage: String(localized: "New Collage", comment: "Button that starts a new collage")
        case .video: String(localized: "New Video Project", comment: "Button that starts a new video in the Video Studio")
        }
    }

    private var emptyTitle: String {
        switch kind {
        case .collage: String(localized: "No Collages Yet")
        case .video: String(localized: "No Video Projects Yet")
        }
    }

    private var emptyDescription: String {
        switch kind {
        case .collage:
            String(localized: "Collages you export show up here, with the photos and layout that made them — so you can open one again and change it.")
        case .video:
            String(localized: "Videos you make in the Video Studio show up here, with the clips and edits behind them — so you can open one again and change it.")
        }
    }

    /// A brand-new project on the photos just picked. Same editors the
    /// selection bar opens, entered from the list of what they have made
    /// rather than from a selection in the library.
    @ViewBuilder
    private func newEditor(with assets: [PHAsset]) -> some View {
        switch kind {
        case .collage:
            CollageScreen(assets: assets)
        case .video:
            VideoStudioScreen(
                assets: assets,
                mode: assets.count == 1 && assets[0].mediaType == .video ? .singleVideo : .multiClip,
                onSaved: { _ in }
            )
        }
    }

    private func start(with ids: [String]) {
        isPickerPresented = false
        guard !ids.isEmpty else { return }
        let found = PhotoLibraryService.fetchAssets(ids: ids)
        guard !found.isEmpty else { return }
        let byId = Dictionary(uniqueKeysWithValues: found.map { ($0.localIdentifier, $0) })
        starting = NewProject(assets: ids.compactMap { byId[$0] })
    }

    private func load() {
        creations = (try? dependencies.creations.fetchOrdered(kind: kind)) ?? []
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
                localized: "This was made by an older version of ShotDex and its settings can't be read. Remove it from the list, or make a new one.",
                comment: "Alert when a saved creation's stored recipe cannot be decoded"
            )
            return
        }
        let found = PhotoLibraryService.fetchAssets(ids: ids)
        guard found.count == ids.count else {
            unopenableMessage = String(
                localized: "Some of the photos this was made from are no longer in your library. Remove it from the list, or start a new one with the photos you still have.",
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
        case .video: String(localized: "Video Project", comment: "Kind of thing in the Creations list — said out loud by VoiceOver, so it must not collide with the Videos album of footage the user shot")
        }
    }

    private var kindSymbol: String {
        switch creation.kind {
        case .collage: "square.grid.2x2"
        case .video: "film"
        }
    }

    /// The date is the title here, not the kind: the list is already one
    /// kind, and a column of rows all saying "Collage" says nothing.
    private var dateLabel: String {
        Date(timeIntervalSince1970: TimeInterval(creation.updatedAt))
            .formatted(date: .abbreviated, time: .shortened)
    }

    private var subtitle: String {
        photoCountLabel(creation.sourceAssetIds.count)
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
                Text(dateLabel)
                    .font(.headline)
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
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
        .accessibilityLabel("\(kindLabel), \(dateLabel), \(subtitle)")
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
    /// The same breakpoint `StatisticsScreen` uses for "how wide before this
    /// gets its own column" (`DESIGN.md` §10.1c). One number for one
    /// question, rather than a second one that reads like a typo later.
    static let minimumWidth: CGFloat = 320
}
