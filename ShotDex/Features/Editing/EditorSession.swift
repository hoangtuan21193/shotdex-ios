import Photos
import ShotDexKit
import SwiftUI

/// A run of photos opened in the editor together, the way Lightroom's filmstrip
/// holds the selection while one photo at a time is on the canvas.
///
/// The editor itself still edits exactly one photo: `PhotoEditorController` owns
/// a single asset and a single render session, and multiplying that by twenty
/// selected photos would mean twenty open originals. What the session keeps
/// instead is the *recipe* of every photo that has been touched — a small value
/// type — so switching away and back restores the edit without having kept the
/// pixels alive.
@MainActor
@Observable
final class EditorSession {
    let assets: [PHAsset]
    /// Which asset is on the canvas.
    var index: Int

    /// Edits made in this session but not yet written to Photos, by asset id.
    private(set) var drafts: [String: PhotoEditRecipe] = [:]
    /// Assets this session has already written.
    private(set) var savedIDs: Set<String> = []

    init(assets: [PHAsset], startIndex: Int = 0) {
        self.assets = assets
        self.index = min(max(startIndex, 0), max(assets.count - 1, 0))
    }

    var current: PHAsset? {
        assets.indices.contains(index) ? assets[index] : nil
    }

    /// A filmstrip only earns its space when there is more than one photo in it.
    var isMultiPhoto: Bool { assets.count > 1 }

    func draft(for asset: PHAsset) -> PhotoEditRecipe? {
        drafts[asset.localIdentifier]
    }

    /// Remembers where a photo was left. An identity recipe is dropped rather
    /// than stored: it is the same as never having touched the photo, and
    /// keeping it would badge the thumbnail as edited.
    func store(_ recipe: PhotoEditRecipe, for asset: PHAsset) {
        if recipe.isIdentity {
            drafts.removeValue(forKey: asset.localIdentifier)
        } else {
            drafts[asset.localIdentifier] = recipe
        }
    }

    /// Lightroom's Sync Settings: hand this recipe to every *other* photo in the
    /// run. The photo it came from is left alone — it already has it, and writing
    /// it back would replace the live controller's state behind its back.
    func syncToAll(_ recipe: PhotoEditRecipe, from asset: PHAsset, scope: EditorSyncScope) {
        for other in assets where other.localIdentifier != asset.localIdentifier {
            let base = drafts[other.localIdentifier] ?? .identity
            store(scope.apply(recipe, onto: base), for: other)
        }
    }

    func markSaved(_ assetID: String) {
        savedIDs.insert(assetID)
        drafts.removeValue(forKey: assetID)
    }

    func hasDraft(_ asset: PHAsset) -> Bool {
        drafts[asset.localIdentifier] != nil
    }

    func isSaved(_ asset: PHAsset) -> Bool {
        savedIDs.contains(asset.localIdentifier)
    }

    /// How many photos are carrying unsaved edits, for the sync/save wording.
    var draftCount: Int { drafts.count }

    /// Lightroom's Auto Sync: while this is on, every committed change lands on
    /// the rest of the run as well.
    ///
    /// Shown as a lit control, never a hidden mode. Lightroom's is a ⌥-click on
    /// the Sync button and fifteen years of users have pasted one photo's edit
    /// over a shoot without knowing it was on; an iPad has no ⌥-click to reveal
    /// it, so the state has to be on screen.
    var isAutoSyncing = false
    /// What `scope` an Auto Sync propagation uses — the last scope the user
    /// picked from the Sync menu.
    var autoSyncScope: EditorSyncScope = .look

    /// The photo the canvas was on before this one, for "apply previous".
    private(set) var previousIndex: Int?

    func moveToPhoto(at index: Int) {
        guard assets.indices.contains(index), index != self.index else { return }
        previousIndex = self.index
        self.index = index
    }

    /// The edit on the photo the user just came from, if it has one.
    var previousRecipe: PhotoEditRecipe? {
        guard let previousIndex, assets.indices.contains(previousIndex) else { return nil }
        return drafts[assets[previousIndex].localIdentifier]
    }
}

/// The strip of the session's photos under the canvas.
struct EditorFilmstrip: View {
    let session: EditorSession
    let photoLibrary: PhotoLibraryService
    /// The photo being edited right now carries the live recipe, which the
    /// session has not been handed yet — the strip asks for it to badge the
    /// current thumbnail correctly.
    let currentHasEdits: Bool
    var select: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(Array(session.assets.enumerated()), id: \.offset) { index, asset in
                        thumbnail(asset, index: index)
                            .id(index)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
            }
            .frame(height: EditorLayoutMetrics.filmstripHeight)
            .background(EditorTheme.panelSolid)
            .overlay(alignment: .top) {
                Rectangle().fill(EditorTheme.panelTopHairline).frame(height: 1)
            }
            .onChange(of: session.index) { _, new in
                withAnimation(EditorTheme.animation) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
    }

    private func thumbnail(_ asset: PHAsset, index: Int) -> some View {
        let isCurrent = index == session.index
        let isEdited = isCurrent ? currentHasEdits : session.hasDraft(asset)
        return Button {
            select(index)
        } label: {
            EditorFilmstripThumbnail(asset: asset, photoLibrary: photoLibrary)
                .frame(
                    width: EditorLayoutMetrics.filmstripThumbnailSide,
                    height: EditorLayoutMetrics.filmstripThumbnailSide
                )
                .clipShape(RoundedRectangle.app(AppTheme.Radius.sm))
                .overlay {
                    RoundedRectangle.app(AppTheme.Radius.sm)
                        .strokeBorder(
                            isCurrent ? EditorTheme.accent : Color.clear,
                            lineWidth: 2
                        )
                }
                .overlay(alignment: .topTrailing) {
                    // Same meaning as Lightroom's badge: this frame carries
                    // develop settings that the file on disk does not.
                    if isEdited {
                        Image(systemName: session.isSaved(asset)
                            ? "checkmark.circle.fill"
                            : "slider.horizontal.3")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(3)
                            .background(EditorTheme.accent, in: Circle())
                            .padding(3)
                    }
                }
                .opacity(isCurrent ? 1 : 0.72)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Photo \(index + 1) of \(session.assets.count)")
        .accessibilityAddTraits(isCurrent ? [.isSelected, .isButton] : .isButton)
    }
}

/// One filmstrip thumbnail. Its own view so the request is cancelled when the
/// cell scrolls away, rather than every photo in a long selection being fetched
/// the moment the editor opens.
private struct EditorFilmstripThumbnail: View {
    let asset: PHAsset
    let photoLibrary: PhotoLibraryService

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .onAppear(perform: load)
            .onDisappear(perform: cancel)
    }

    private func load() {
        cancel()
        let side = EditorLayoutMetrics.filmstripThumbnailSide * 3
        requestID = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: side, height: side),
            allowNetwork: false
        ) { result in
            if let result { image = result }
        }
    }

    private func cancel() {
        if let requestID { photoLibrary.cancelThumbnailRequest(requestID) }
        requestID = nil
    }
}

/// What a multi-photo edit is opened with. A struct carrying its own data, like
/// `CompressionPresentation`, so the cover never reads selection state that has
/// already been cleared behind it.
struct MultiEditPresentation: Identifiable {
    let assets: [PHAsset]
    let first: PHAsset

    var id: String { first.localIdentifier }
}

extension View {
    /// Presents the multi-photo editor. A modifier rather than a `fullScreenCover`
    /// written out at each of the four selection hosts: their bodies are already
    /// long enough that one more inline cover tips the type-checker over.
    func multiEditCover(
        _ presentation: Binding<MultiEditPresentation?>,
        sourceAlbum: PHAssetCollection?,
        onDismiss: @escaping () -> Void
    ) -> some View {
        fullScreenCover(item: presentation, onDismiss: onDismiss) { presentation in
            PhotoEditorScreen(
                asset: presentation.first,
                siblings: presentation.assets,
                sourceAlbum: sourceAlbum
            )
        }
    }
}
