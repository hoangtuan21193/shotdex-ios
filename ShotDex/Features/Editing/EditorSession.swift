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
    let photos: [PhotoEditOrigin]
    /// Which asset is on the canvas.
    var index: Int

    /// Edits made in this session but not yet written to Photos, by asset id.
    private(set) var drafts: [String: PhotoEditRecipe] = [:]
    /// Assets this session has already written.
    private(set) var savedIDs: Set<String> = []
    /// The recipe each photo was last written with by Save Changes.
    private var savedRecipes: [String: PhotoEditRecipe] = [:]
    /// Bumped whenever any draft changes, so the preview preloader can redraw
    /// the photos whose next open will look different (FS-03.09b §2).
    private(set) var draftRevision = 0

    init(photos: [PhotoEditOrigin], startIndex: Int = 0) {
        self.photos = photos
        self.index = min(max(startIndex, 0), max(photos.count - 1, 0))
    }

    // MARK: Originals in iCloud (FS-02.06 AC-13)

    /// Where a filmstrip photo's original is, as far as this run knows.
    enum OriginalState: Equatable {
        case inCloud
        /// The preloader is bringing it down: 0…1.
        case downloading(Double)
        case local
    }

    /// Per photo, asked once a run with the network off, lazily as cells
    /// appear — never stored past the run (§7).
    private(set) var originalStates: [String: OriginalState] = [:]
    @ObservationIgnored var originalFetcher: (any OriginalFetching)?
    @ObservationIgnored private var probing: Set<String> = []

    /// Asks about one photo the first time its cell appears.
    func probeOriginal(of photo: PhotoEditOrigin) {
        guard let fetcher = originalFetcher, let asset = photo.asset, asset.mediaType == .image,
              originalStates[photo.id] == nil, !probing.contains(photo.id) else { return }
        probing.insert(photo.id)
        let item = OriginalItem(id: asset.localIdentifier, filename: "",
                                photo: PixelSize(width: asset.pixelWidth, height: asset.pixelHeight))
        Task { [weak self] in
            let availability = await fetcher.probe(item)
            guard let self else { return }
            self.probing.remove(photo.id)
            // A download that started meanwhile says more than the probe.
            if self.originalStates[photo.id] == nil {
                self.originalStates[photo.id] = availability == .local ? .local : .inCloud
            }
        }
    }

    /// The preloader's progress on one photo's original.
    func reportOriginalDownload(_ id: String, fraction: Double) {
        guard originalStates[id] != .local else { return }
        originalStates[id] = .downloading(fraction)
    }

    /// The photo's original is here (its session opened).
    func markOriginalLocal(_ id: String) {
        originalStates[id] = .local
    }

    /// The download stopped short: back to the glyph.
    func markOriginalDownloadEnded(_ id: String) {
        if case .downloading = originalStates[id] { originalStates[id] = .inCloud }
    }

    var current: PhotoEditOrigin? {
        photos.indices.contains(index) ? photos[index] : nil
    }

    /// A filmstrip only earns its space when there is more than one photo in it.
    var isMultiPhoto: Bool { photos.count > 1 }

    /// Server photos (FS-17.06 §5): exported, never saved back to Photos.
    var isServerRun: Bool { photos.first?.isServerFile == true }

    func draft(for photo: PhotoEditOrigin) -> PhotoEditRecipe? {
        drafts[photo.id]
    }

    /// Remembers where a photo was left. A recipe with nothing to write is
    /// dropped rather than stored: identity is the same as never having touched
    /// the photo, and the recipe a Save Changes just wrote is the same as the
    /// library's copy. Keeping either would badge the thumbnail as edited and
    /// count the photo in Save All again (FS-03.09b AC-5).
    func store(_ recipe: PhotoEditRecipe, for photo: PhotoEditOrigin) {
        store(recipe, forID: photo.id)
    }

    /// `store(_:for:)` by asset id, so the rule is testable without PhotoKit.
    func store(_ recipe: PhotoEditRecipe, forID id: String) {
        let before = drafts[id]
        let isUnchanged = savedRecipes[id].map { recipe == $0 } ?? recipe.isIdentity
        if isUnchanged {
            drafts.removeValue(forKey: id)
        } else {
            drafts[id] = recipe
        }
        if drafts[id] != before { draftRevision += 1 }
    }

    /// Lightroom's Sync Settings: hand this recipe to every *other* photo in the
    /// run. The photo it came from is left alone — it already has it, and writing
    /// it back would replace the live controller's state behind its back.
    func syncToAll(_ recipe: PhotoEditRecipe, from photo: PhotoEditOrigin, scope: EditorSyncScope) {
        for other in photos where other.id != photo.id {
            let base = drafts[other.id] ?? .identity
            store(scope.apply(recipe, onto: base), for: other)
        }
    }

    /// `recipe`: what Save Changes wrote to this photo, so leaving it untouched
    /// afterwards does not park the same edit as a draft again. Nil for a Save
    /// Copy, which leaves the photo itself as it was.
    func markSaved(_ assetID: String, recipe: PhotoEditRecipe? = nil) {
        savedIDs.insert(assetID)
        if let recipe { savedRecipes[assetID] = recipe }
        if drafts.removeValue(forKey: assetID) != nil { draftRevision += 1 }
    }

    func hasDraft(_ photo: PhotoEditOrigin) -> Bool {
        drafts[photo.id] != nil
    }

    func isSaved(_ photo: PhotoEditOrigin) -> Bool {
        savedIDs.contains(photo.id)
    }

    /// How many photos are carrying unsaved edits, for the sync/save wording.
    var draftCount: Int { drafts.count }

    /// What Export… sends from a server run (FS-17.06 §5), after the canvas
    /// photo's `canvasRecipe` has been parked: every photo carrying an edit,
    /// or — alone in its run — the photo as it is, so a RAW can be exported
    /// as a JPEG without touching a slider.
    func exportSelection(canvasRecipe: PhotoEditRecipe) -> [(photo: FetchedServerPhoto, recipe: PhotoEditRecipe)] {
        if let current { store(canvasRecipe, for: current) }
        let edited = photos.compactMap { photo -> (photo: FetchedServerPhoto, recipe: PhotoEditRecipe)? in
            guard let file = photo.serverFile, let draft = drafts[photo.id] else { return nil }
            return (file, draft)
        }
        if edited.isEmpty, !isMultiPhoto, let file = current?.serverFile {
            return [(file, canvasRecipe)]
        }
        return edited
    }

    /// Whether leaving now would throw work away: the photo on the canvas
    /// (`canvasHasChanges`, which only its controller knows) or a draft parked
    /// on any other photo by Sync, Paste Edits or a switch. False means the
    /// editor closes without asking — and a server run's copies are deleted
    /// with nothing lost (FS-17.06 §5).
    func hasUnsavedWork(canvasHasChanges: Bool) -> Bool {
        canvasHasChanges || !drafts.isEmpty
    }

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

    /// The frame pinned beside the canvas to match against — Lightroom's
    /// Reference View. Nil when nothing is pinned.
    ///
    /// The whole point of a big screen: matching forty frames to a hero frame is
    /// the actual job of a multi-photo edit, and "make it look like that one" is
    /// impossible when only one photo is on screen. Meaningless on a phone,
    /// where there is no room for two.
    var referenceIndex: Int?

    var referencePhoto: PhotoEditOrigin? {
        guard let referenceIndex, photos.indices.contains(referenceIndex) else { return nil }
        return photos[referenceIndex]
    }

    /// Whether the reference follows the canvas's zoom and pan — Lightroom's
    /// Link Focus. On by default: the reason to zoom into a photo while a
    /// reference is up is to compare the same detail in both, and doing that by
    /// hand twice is the kind of work a computer should be doing.
    var isReferenceLocked = true

    /// Pins a frame, or unpins it when it is already the reference.
    func toggleReference(at index: Int) {
        referenceIndex = referenceIndex == index ? nil : index
    }

    /// The photo the canvas was on before this one, for "apply previous".
    private(set) var previousIndex: Int?

    func moveToPhoto(at index: Int) {
        guard photos.indices.contains(index), index != self.index else { return }
        previousIndex = self.index
        self.index = index
    }

    /// Where Skip goes from a photo the editor can't open (FS-03.04b Q7):
    /// the next photo, or the one before when it is the last.
    var skipTarget: Int? {
        if photos.indices.contains(index + 1) { return index + 1 }
        if photos.indices.contains(index - 1) { return index - 1 }
        return nil
    }

    /// The edit on the photo the user just came from, if it has one.
    var previousRecipe: PhotoEditRecipe? {
        guard let previousIndex, photos.indices.contains(previousIndex) else { return nil }
        return drafts[photos[previousIndex].id]
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
    /// Pins or unpins a frame as the reference. Nil on the phone, where there
    /// is no room to show one.
    var toggleReference: ((Int) -> Void)?
    /// Shorter frames beside a wide canvas. The sidebar already spends the
    /// window's width; the strip should not also spend a tenth of its height,
    /// and at 56pt a frame is still large enough to pick between two takes —
    /// which is the only reason the run is on screen. The phone keeps 96,
    /// where the strip is the only way back to the other photos.
    var isCompact = false
    var select: (Int) -> Void

    private var thumbnailSide: CGFloat {
        isCompact
            ? EditorLayoutMetrics.wideFilmstripThumbnailSide
            : EditorLayoutMetrics.filmstripThumbnailSide
    }

    private var stripHeight: CGFloat {
        isCompact
            ? EditorLayoutMetrics.wideFilmstripHeight
            : EditorLayoutMetrics.filmstripHeight
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(Array(session.photos.enumerated()), id: \.offset) { index, photo in
                        thumbnail(photo, index: index)
                            .id(index)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
            }
            .frame(height: stripHeight)
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

    private func thumbnail(_ photo: PhotoEditOrigin, index: Int) -> some View {
        let isCurrent = index == session.index
        let isEdited = isCurrent ? currentHasEdits : session.hasDraft(photo)
        return Button {
            select(index)
        } label: {
            EditorFilmstripThumbnail(photo: photo, photoLibrary: photoLibrary, original: session.originalStates[photo.id])
                .frame(width: thumbnailSide, height: thumbnailSide)
                .onAppear { session.probeOriginal(of: photo) }
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
                        Image(systemName: session.isSaved(photo)
                            ? "checkmark.circle.fill"
                            : "slider.horizontal.3")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(3)
                            .background(EditorTheme.accent, in: Circle())
                            .padding(3)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if session.referenceIndex == index {
                        Image(systemName: "rectangle.on.rectangle")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(3)
                            .background(.white, in: Circle())
                            .padding(3)
                    }
                }
                .opacity(isCurrent ? 1 : 0.72)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .contextMenu {
            if let toggleReference {
                Button {
                    toggleReference(index)
                } label: {
                    Label(
                        session.referenceIndex == index ? "Clear Reference" : "Use as Reference",
                        systemImage: session.referenceIndex == index ? "rectangle.slash" : "rectangle.on.rectangle"
                    )
                }
            }
        }
        .accessibilityLabel("Photo \(index + 1) of \(session.photos.count)")
        .accessibilityAddTraits(isCurrent ? [.isSelected, .isButton] : .isButton)
    }
}

/// One filmstrip thumbnail. Its own view so the request is cancelled when the
/// cell scrolls away, rather than every photo in a long selection being fetched
/// the moment the editor opens.
struct EditorFilmstripThumbnail: View {
    let photo: PhotoEditOrigin
    let photoLibrary: PhotoLibraryService
    /// Where the original is (FS-02.06 AC-13): a glyph while it is only in
    /// iCloud, a ring with no number while the preloader brings it down.
    var original: EditorSession.OriginalState?

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?
    @State private var isFetchingFromCloud = false

    var body: some View {
        Rectangle()
            .fill(EditorTheme.control)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if isFetchingFromCloud {
                    ProgressView()
                        .tint(EditorTheme.secondaryText)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 18))
                        .foregroundStyle(EditorTheme.dimText)
                }
            }
            .clipped()
            .overlay(alignment: .topTrailing) { originalBadge }
            .onAppear(perform: load)
            .onDisappear(perform: cancel)
    }

    @ViewBuilder private var originalBadge: some View {
        switch original {
        case .inCloud?:
            Image(systemName: "icloud")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(.black.opacity(0.55)))
                .padding(2)
                .accessibilityLabel(String(localized: "Original in iCloud"))
        case .downloading(let fraction)?:
            ICloudDownloadRing(progress: fraction)
                .tint(EditorTheme.accent)
                .scaleEffect(0.73)
                .frame(width: 16, height: 16)
                .background(Circle().fill(.black.opacity(0.55)))
                .padding(2)
        default:
            EmptyView()
        }
    }

    /// Local first, then iCloud. With Optimize Storage on — which is the normal
    /// state of a full library — a local-only request returns nothing for most
    /// frames, and the strip was a row of blank grey tiles with no way to tell
    /// whether they were loading or broken.
    private func load() {
        cancel()
        let side = EditorLayoutMetrics.filmstripThumbnailSide * 3
        if let url = photo.localFileURL {
            // Already on disk: ImageIO's thumbnail, off the main thread.
            Task {
                let thumbnail = await Task.detached {
                    EmbeddedPreview.thumbnail(ofFileAt: url, maxPixelSize: Int(side))?.image
                }.value
                if let thumbnail { image = UIImage(cgImage: thumbnail) }
            }
            return
        }
        guard let asset = photo.asset else { return }
        let size = CGSize(width: side, height: side)
        requestID = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: size,
            allowNetwork: false
        ) { result in
            if let result {
                image = result
                return
            }
            isFetchingFromCloud = true
            requestID = photoLibrary.requestThumbnail(
                for: asset,
                targetSize: size,
                allowNetwork: true
            ) { downloaded in
                isFetchingFromCloud = false
                if let downloaded { image = downloaded }
            }
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
