import Foundation
import Observation
import Photos
import UIKit

/// What opens a culling pass: the photos, and where to start.
struct CullRequest: Identifiable, Equatable {
    let id = UUID()
    let assetIds: [String]
    /// Cull From Here: the photo the viewer is on. Nil → the first unflagged.
    var startId: String?
}

/// Screen-sized renditions for the pass — never the original (FS-01.12b §2,
/// AC-8). A protocol so a test can count what was asked for.
@MainActor
protocol CullImageLoading: AnyObject {
    /// One rendition at `targetSize`, network allowed; `completion` may run
    /// twice (a quick degraded frame, then the final one).
    func requestImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?, Bool) -> Void) -> PHImageRequestID
    func cancel(_ request: PHImageRequestID)
    func preheat(_ assets: [PHAsset], targetSize: CGSize)
    func stopPreheating(_ assets: [PHAsset], targetSize: CGSize)
}

extension PhotoLibraryService: CullImageLoading {
    func requestImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?, Bool) -> Void) -> PHImageRequestID {
        requestDetailImage(for: asset, targetSize: targetSize, allowNetwork: true, progress: { _ in }, completion: completion)
    }

    func cancel(_ request: PHImageRequestID) {
        guard request != PHInvalidImageRequestID else { return }
        imageManager.cancelImageRequest(request)
    }

    func preheat(_ assets: [PHAsset], targetSize: CGSize) {
        startCachingDetailImages(for: assets, targetSize: targetSize)
    }

    func stopPreheating(_ assets: [PHAsset], targetSize: CGSize) {
        stopCachingDetailImages(for: assets, targetSize: targetSize)
    }
}

/// The culling pass (FS-01.12b): one photo at a time in capture order, a
/// tap, a key or a swipe per photo. Marks go through `PhotoMarks` the moment
/// they are set — there is no Save.
@MainActor
@Observable
final class CullModel {
    private(set) var session: CullSession
    private(set) var image: UIImage?
    var isSummaryPresented = false
    /// The pass's own zoom: vertical swipes flag only at 1× (AC-2).
    var zoomScale: CGFloat = 1
    /// Bumped by `Z`: fit ↔ zoomed, as a double tap does.
    private(set) var zoomToggleToken = 0

    func toggleZoom() { zoomToggleToken += 1 }

    /// One key in the pass (FS-01.12b §2): the mark keys of FS-01.12 §6,
    /// plus ←/→ and Z. ⌘Z and Esc are the Undo and ✕ buttons' own.
    func handle(_ key: CullKey) async {
        switch key {
        case .mark(let action): await apply(action)
        case .previous: previous()
        case .next: next()
        case .zoom: toggleZoom()
        }
    }

    @ObservationIgnored let marks: PhotoMarks
    @ObservationIgnored private let loader: CullImageLoading
    @ObservationIgnored private var assets: [String: PHAsset]
    @ObservationIgnored private var request: PHImageRequestID = PHInvalidImageRequestID
    @ObservationIgnored private var preheated: [PHAsset] = []
    @ObservationIgnored var targetSize: CGSize = CGSize(width: 1_200, height: 1_200)
    /// Asked whether the photo on screen has its original only in iCloud —
    /// a probe, never a download (AC-8).
    @ObservationIgnored private let originalFetcher: (any OriginalFetching)?
    @ObservationIgnored private var probeTask: Task<Void, Never>?
    /// The original of the photo on screen is only in iCloud: what shows is
    /// the device's copy, and the glyph says so.
    private(set) var isOriginalInCloud = false

    init(
        request: CullRequest, marks: PhotoMarks, loader: CullImageLoading, assets: [PHAsset],
        originalFetcher: (any OriginalFetching)? = nil
    ) {
        self.marks = marks
        self.loader = loader
        self.originalFetcher = originalFetcher
        self.assets = Dictionary(assets.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        let items = assets.map { CullSession.Item(id: $0.localIdentifier, captureDate: $0.creationDate) }
        self.session = CullSession.start(items: items, flagged: { marks.flag(for: $0) != nil }, startId: request.startId)
    }

    // MARK: Reads

    var currentId: String? { session.currentId }
    var currentAsset: PHAsset? { currentId.flatMap { assets[$0] } }
    var isCurrentVideo: Bool { currentAsset?.mediaType == .video }

    func asset(for id: String) -> PHAsset? { assets[id] }

    /// Marks of a photo in the pass, as the screen draws them.
    func marks(for id: String) -> PhotoMarkSummary {
        _ = marks.version
        return marks.summary(for: id, photosRating: assets[id]?.photosStarRating)
    }

    var currentMarks: PhotoMarkSummary { currentId.map(marks(for:)) ?? PhotoMarkSummary(rating: 0, flag: nil) }

    var summary: CullSummary {
        _ = marks.version
        return CullSummary(ids: session.ids, flag: marks.flag(for:))
    }

    // MARK: Moving

    func show(index: Int) {
        session.move(to: index)
        loadCurrent()
    }

    func next() {
        guard !session.isLast else { return }
        session.next()
        loadCurrent()
    }

    func previous() {
        guard session.index > 0 else { return }
        session.previous()
        loadCurrent()
    }

    // MARK: Marking

    /// Pick / Reject / Clear Flag on the current photo, then the next one —
    /// or the summary after the last (FS-01.12b §5).
    func setFlag(_ flag: PhotoFlag?) async {
        guard let id = currentId else { return }
        // A light tap per flag: the hand should feel the photo go by
        // without looking (FS-01.12b §2).
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let change = await marks.setFlag(flag, ids: [id])
        switch session.didSetFlag(change) {
        case .summary: isSummaryPresented = true
        case .next, .stay: loadCurrent()
        }
    }

    /// Stars on the current photo; the pass stays on it.
    func setRating(_ stars: Int) async {
        guard let id = currentId else { return }
        let change = await marks.setRating(stars, ids: [id], photosRatings: assets[id]?.photosStarRating.map { [id: $0] })
        _ = session.didSetRating(change)
    }

    func apply(_ action: MarkKeyAction) async {
        switch action {
        case .rate(let stars): await setRating(stars)
        case .flag(let flag): await setFlag(flag)
        }
    }

    /// Takes back the last mark and goes back to its photo (AC-1).
    func undo() async {
        guard let change = session.undo() else { return }
        isSummaryPresented = false
        await marks.undo(change)
        loadCurrent()
    }

    var canUndo: Bool { session.canUndo }

    /// A swipe on the photo (FS-01.12b §5), through `CullGesturePolicy`.
    func handle(_ swipe: CullGesturePolicy.Swipe) async {
        switch CullGesturePolicy.action(for: swipe, zoomScale: zoomScale) {
        case .flag(let flag): await setFlag(flag)
        case .next: next()
        case .previous: previous()
        case nil: break
        }
    }

    // MARK: The end of the pass (FS-01.12b §2)

    /// Review Unflagged: the same pass over the photos still without a
    /// flag. A new pass — its undo starts empty.
    func reviewUnflagged() {
        let ids = CullSummary.unflaggedIds(session.ids, flag: marks.flag(for:))
        guard !ids.isEmpty else { return }
        let items = ids.compactMap { id in assets[id].map { CullSession.Item(id: id, captureDate: $0.creationDate) } }
        session = CullSession.start(items: items, flagged: { _ in false })
        isSummaryPresented = false
        loadCurrent()
    }

    /// Photos the system deleted from the pass (Delete N Rejected…): out of
    /// the set and its undo; the summary stays, now with nothing rejected.
    func removeDeleted(_ ids: [String]) {
        let gone = Set(ids)
        let items = session.ids.filter { !gone.contains($0) }.compactMap { id in
            assets[id].map { CullSession.Item(id: id, captureDate: $0.creationDate) }
        }
        let current = session.currentId.flatMap { gone.contains($0) ? nil : $0 }
        session = CullSession.start(items: items, flagged: { _ in true }, startId: current)
        for id in gone { assets[id] = nil }
        if session.ids.isEmpty { image = nil } else if !isSummaryPresented { loadCurrent() }
    }

    /// The pass's Rejected photos, in pass order — what Delete N Rejected…
    /// sends to the system's deletion (FS-01.12b §3).
    var rejectedIds: [String] {
        _ = marks.version
        return CullSummary.rejectedIds(session.ids, flag: marks.flag(for:))
    }

    // MARK: Images

    /// The current page at screen size, network allowed; ±2 pages warm.
    func loadCurrent() {
        loader.cancel(request)
        request = PHInvalidImageRequestID
        guard let asset = currentAsset else {
            image = nil
            return
        }
        let id = asset.localIdentifier
        request = loader.requestImage(for: asset, targetSize: targetSize) { [weak self] image, _ in
            guard let self, self.currentId == id, let image else { return }
            self.image = image
        }
        probeOriginal(asset)
        let warm = CullImagePolicy.warmRange(index: session.index, count: session.ids.count)
            .map { range in range.compactMap { assets[session.ids[$0]] } } ?? []
        let stale = preheated.filter { old in !warm.contains { $0.localIdentifier == old.localIdentifier } }
        loader.stopPreheating(stale, targetSize: targetSize)
        loader.preheat(warm, targetSize: targetSize)
        preheated = warm
    }

    private func probeOriginal(_ asset: PHAsset) {
        probeTask?.cancel()
        isOriginalInCloud = false
        guard let originalFetcher, asset.mediaType == .image else { return }
        let id = asset.localIdentifier
        let item = OriginalItem(id: id, filename: "", photo: PixelSize(width: asset.pixelWidth, height: asset.pixelHeight))
        probeTask = Task { [weak self] in
            let availability = await originalFetcher.probe(item)
            guard !Task.isCancelled, let self, self.currentId == id else { return }
            self.isOriginalInCloud = availability == .inCloud
        }
    }

    func stop() {
        probeTask?.cancel()
        loader.cancel(request)
        loader.stopPreheating(preheated, targetSize: targetSize)
        preheated = []
    }
}
