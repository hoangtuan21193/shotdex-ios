import ImageIO
import Photos
import ShotDexKit
import SwiftUI

/// The state behind a Focus Stack or Stack Exposures screen: frames loaded
/// once, the preview for the mode in hand, and the save that turns it into a
/// new photo. The screen only draws it.
@MainActor
@Observable
final class PhotoStackModel {
    /// What went wrong, and when. The phase decides the alert title: a preview
    /// that failed has nothing to save yet, so it must not say "Couldn't Save".
    enum Failure: Equatable {
        case load(String)
        case save(String)

        var title: String {
            switch self {
            case .load: String(localized: "Couldn't Load Photos", comment: "Alert title: the frames for a stack could not be loaded or combined for the preview")
            case .save: String(localized: "Couldn't Save", comment: "Alert title: the combined photo could not be rendered or saved")
            }
        }

        var message: String {
            switch self {
            case .load(let text), .save(let text): text
            }
        }
    }

    let purpose: CombinePurpose
    let assets: [PHAsset]

    var mode: PhotoStackMode {
        didSet { if mode != oldValue { renderPreview() } }
    }
    /// Method, Radius and Smoothing of a focus stack. Picking a method resets
    /// the two sliders to that method's starting values (FS-01.10 §3).
    var focusOptions = FocusStackOptions.standard {
        didSet { if focusOptions != oldValue { renderPreview() } }
    }
    private(set) var preview: UIImage?
    private(set) var isWorking = false
    private(set) var statusText: String?
    var failure: Failure?
    /// Frames the last combine left out because they would not line up
    /// (focus stack only), as indices into `loadedAssets`.
    private(set) var excludedFrames: [Int] = []
    /// How many of `assets` could not be loaded — an iCloud-only original with
    /// no network, most often. Said on the panel with a Retry, never dropped
    /// quietly (FS-01.10 §4, AC-12).
    private(set) var missingFrameCount = 0
    /// The assets whose preview did load, in stacking order. Save combines
    /// these and no others, so it saves what the preview showed.
    private(set) var loadedAssets: [PHAsset] = []
    /// Set once the new asset is saved, indexed and visible to the grid.
    private(set) var savedAssetID: String?

    /// Source frames at preview resolution, loaded once and reused for every
    /// mode change — reloading eight originals per picker tap is the difference
    /// between instant and unusable.
    private var previewFrames: [CIImage] = []
    /// The preview bracket, lined up once; every method or slider change
    /// re-stacks it instead of registering the frames again.
    private var preparedFocus: PreparedFocusStack?
    /// The stack for the current options, rendered once, so a retouch stroke
    /// only blends over it instead of re-stacking every frame.
    private var stackedBase: (options: FocusStackOptions, image: CGImage)?
    private var renderTask: Task<Void, Never>?
    private let renderer = PhotoStackRenderer()
    private let photoLibrary: PhotoLibraryService
    private let indexPipeline: IndexPipeline

    init(purpose: CombinePurpose, assets: [PHAsset], photoLibrary: PhotoLibraryService, indexPipeline: IndexPipeline) {
        self.purpose = purpose
        // A focus stack registers neighbour to neighbour, so it runs in the
        // order the bracket was shot; the blend modes do not care.
        self.assets = purpose == .focusStack ? Self.shootingOrder(assets) : assets
        self.mode = purpose.defaultMode ?? .average
        self.photoLibrary = photoLibrary
        self.indexPipeline = indexPipeline
    }

    var canSave: Bool { preview != nil && !isWorking }

    /// "2 of 40 frames couldn't be lined up and were left out." — nil when every
    /// frame made it in (FS-01.10 §4).
    var excludedFramesMessage: String? {
        guard !excludedFrames.isEmpty else { return nil }
        return String(
            localized: "\(excludedFrames.count) of \(previewFrames.count) frames couldn't be lined up and were left out.",
            comment: "Focus Stack panel: frames dropped because alignment failed. First number is dropped frames, second is all frames."
        )
    }

    /// "3 photos couldn't be downloaded." — nil when every frame loaded.
    var missingFramesMessage: String? {
        guard missingFrameCount > 0 else { return nil }
        return String(
            localized: "\(missingFrameCount) photos couldn't be downloaded.",
            comment: "Stack screen: frames that could not be loaded, usually iCloud originals with no network. Shown with a Retry button."
        )
    }

    /// Loads every frame once at preview resolution. Full resolution is left
    /// until Save: a thirty-frame macro stack at 48 megapixels is gigabytes, and
    /// nobody needs that to choose between Average and Lighten.
    ///
    /// Also what Retry calls: it starts over from every selected photo.
    func loadFrames() async {
        renderTask?.cancel()
        isWorking = true
        statusText = String(localized: "Loading \(assets.count) photos…", comment: "Stack screen status while the preview frames load")
        defer { isWorking = false }

        var frames: [CIImage] = []
        var loaded: [PHAsset] = []
        for asset in assets {
            guard let image = await Self.previewImage(for: asset, photoLibrary: photoLibrary),
                  let ciImage = CIImage(image: image) else { continue }
            frames.append(ciImage)
            loaded.append(asset)
        }
        previewFrames = frames
        loadedAssets = loaded
        missingFrameCount = assets.count - loaded.count
        preparedFocus = nil
        stackedBase = nil
        retouchStrokes = []
        retouchFrame = nil
        excludedFrames = []
        guard frames.count >= CombinePurpose.minimumPhotoCount else {
            preview = nil
            // A missing frame is already on the panel with its Retry; an alert
            // on top would say the same thing twice.
            if missingFrameCount == 0 {
                failure = .load(PhotoStackError.needsTwoImages.localizedDescription)
            }
            return
        }
        await render()
    }

    func retryMissingFrames() {
        renderTask?.cancel()
        renderTask = Task { await loadFrames() }
    }

    func cancel() { renderTask?.cancel() }

    /// Switches method and puts Radius and Smoothing back to its defaults.
    func selectFocusMethod(_ method: FocusStackOptions.Method) {
        guard method != focusOptions.method else { return }
        requestFocusOptions(.defaults(for: method))
    }

    /// Applies new Method, Radius or Smoothing — unless there are retouch
    /// strokes, which were painted over the stack those options made. Then it
    /// waits for the user to agree to lose them (FS-01.10 §5).
    func requestFocusOptions(_ options: FocusStackOptions) {
        guard options != focusOptions else { return }
        if retouchStrokes.isEmpty {
            focusOptions = options
        } else {
            pendingFocusOptions = options
        }
    }

    func confirmPendingFocusOptions() {
        guard let pendingFocusOptions else { return }
        self.pendingFocusOptions = nil
        retouchStrokes = []
        focusOptions = pendingFocusOptions
    }

    // MARK: Retouch

    /// Painting over the stack from one frame (FS-01.10 §5).
    private(set) var isRetouching = false
    /// In painting order. Only for this session: they are not saved anywhere
    /// but into the photo.
    private(set) var retouchStrokes: [FocusStackRetouchStroke] = []
    /// The frame the brush paints from, as an index into `loadedAssets`. Nil
    /// until the first stroke picks one.
    private(set) var retouchFrame: Int?
    /// True once the user picked a frame in the strip; until then every
    /// stroke paints from the frame sharpest where it starts.
    private(set) var picksFrameAutomatically = true
    /// Brush width as a fraction of the picture's short edge.
    var brushSize = 0.06
    /// Options waiting on "this clears your retouch" (see `requestFocusOptions`).
    var pendingFocusOptions: FocusStackOptions?

    static let brushSizeRange = 0.01...0.25

    /// The frames a stroke can paint from — the ones that lined up — as
    /// indices into `loadedAssets`.
    var retouchableFrames: [Int] { preparedFocus?.inputIndices ?? [] }

    var canRetouch: Bool { mode == .focusStack && preparedFocus != nil && preview != nil }

    func beginRetouch() {
        guard canRetouch else { return }
        isRetouching = true
    }

    /// Leaves the brush; the strokes stay in the picture.
    func endRetouch() { isRetouching = false }

    func pickRetouchFrame(_ index: Int?) {
        if let index {
            retouchFrame = index
            picksFrameAutomatically = false
        } else {
            picksFrameAutomatically = true
        }
    }

    /// Adds one stroke, painted through `points` (normalized, top-left
    /// origin), and re-renders.
    func addRetouchStroke(points: [NormalizedPoint]) {
        guard let first = points.first, let prepared = preparedFocus else { return }
        renderTask?.cancel()
        renderTask = Task {
            let frame: Int
            if !picksFrameAutomatically, let retouchFrame {
                frame = retouchFrame
            } else {
                frame = await renderer.sharpestFrame(in: prepared, at: first, radius: focusOptions.radius)
                retouchFrame = frame
            }
            retouchStrokes.append(FocusStackRetouchStroke(
                frame: frame,
                brush: BrushStroke(points: points, size: brushSize, feather: 0.3, flow: 1, isEraser: false)
            ))
            await render()
        }
    }

    var canUndoRetouch: Bool { !retouchStrokes.isEmpty }

    func undoRetouchStroke() {
        guard !retouchStrokes.isEmpty else { return }
        retouchStrokes.removeLast()
        renderPreview()
    }

    private func renderPreview() {
        renderTask?.cancel()
        renderTask = Task { await render() }
    }

    private func render() async {
        guard previewFrames.count >= CombinePurpose.minimumPhotoCount else { return }
        isWorking = true
        statusText = workingText
        defer { isWorking = false }
        do {
            let cgImage: CGImage
            if mode == .focusStack {
                let prepared: PreparedFocusStack
                if let preparedFocus {
                    prepared = preparedFocus
                } else {
                    prepared = try await renderer.prepareFocusStack(images: previewFrames)
                    preparedFocus = prepared
                }
                excludedFrames = prepared.excludedFrames
                let base: CGImage
                if let stackedBase, stackedBase.options == focusOptions {
                    base = stackedBase.image
                } else {
                    base = try await renderer.render(renderer.focusStack(prepared, options: focusOptions))
                    guard !Task.isCancelled else { return }
                    stackedBase = (focusOptions, base)
                }
                if retouchStrokes.isEmpty {
                    cgImage = base
                } else {
                    let retouched = await renderer.retouched(CIImage(cgImage: base), prepared: prepared, strokes: retouchStrokes)
                    cgImage = try await renderer.render(retouched)
                }
            } else {
                cgImage = try await renderer.render(renderer.combine(images: previewFrames, mode: mode))
            }
            guard !Task.isCancelled else { return }
            preview = UIImage(cgImage: cgImage)
        } catch {
            failure = .load(error.localizedDescription)
        }
    }

    private var workingText: String {
        mode.needsAlignment
            ? String(localized: "Lining frames up…", comment: "Stack screen status while frames are aligned")
            : String(localized: "Combining…", comment: "Stack screen status while frames are combined")
    }

    /// JPEG quality of a saved combine (FS-01.10 §6).
    static let jpegQuality = 0.95

    /// Re-runs the combine at full resolution and writes a new asset, then
    /// indexes it and tells the grid, so the viewer can open it straight away.
    /// The preview is not saved: it is a 1600pt proxy, and a photographer
    /// stacking macro frames wants every pixel they shot.
    ///
    /// Originals go to a session folder one at a time and are read back lazily
    /// from there, so only one original's bytes are in memory while they load.
    /// The folder is gone when the save ends, cancelled or not.
    func save() {
        renderTask?.cancel()
        let assets = loadedAssets
        renderTask = Task {
            isWorking = true
            statusText = String(localized: "Loading full-resolution frames…", comment: "Stack screen status while originals load for saving")
            defer { isWorking = false }
            var session: PhotoStackSession?
            defer { session?.remove() }
            do {
                session = try PhotoStackSession()
                var frames: [CIImage] = []
                var urls: [URL] = []
                var firstFrameProperties: [String: Any] = [:]
                var missing = 0
                for (index, asset) in assets.enumerated() {
                    try Task.checkCancellation()
                    statusText = String(localized: "Loading \(index + 1) of \(assets.count)…", comment: "Stack screen status while originals load, one by one")
                    guard let data = await Self.originalData(for: asset),
                          let url = try session?.store(data, index: index),
                          let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true])
                    else { missing += 1; continue }
                    if frames.isEmpty, let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                        firstFrameProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
                    }
                    frames.append(image)
                    urls.append(url)
                }
                // The preview had these frames; a save with fewer would not be
                // the picture the user chose to keep.
                guard missing == 0 else {
                    throw StackSaveError.framesMissing(missing)
                }

                try Task.checkCancellation()
                statusText = workingText
                let cgImage: CGImage
                if mode == .focusStack {
                    // Streamed from the session folder, one frame decoded at a
                    // time, so a long bracket costs no more memory than a short
                    // one (FS-01.10 §6). Same frames, same order as the
                    // preview, so every stroke's frame index names the same
                    // photo at full resolution.
                    frames = []
                    let files = urls
                    let stacked = try await renderer.streamedFocusStack(
                        frameCount: files.count,
                        frame: { CIImage(contentsOf: files[$0], options: [.applyOrientationProperty: true]) },
                        options: focusOptions,
                        strokes: retouchStrokes,
                        progress: { [weak self] done, total in
                            Task { @MainActor in
                                // A percentage, not "frame N of M": Weighted
                                // reads every frame twice.
                                self?.statusText = String(
                                    localized: "Stacking… \(done * 100 / max(1, total))%",
                                    comment: "Focus Stack status while saving: how far the full-resolution stack has got, as a percentage"
                                )
                            }
                        }
                    )
                    cgImage = stacked.image
                } else {
                    cgImage = try await renderer.render(renderer.combine(images: frames, mode: mode))
                }

                try Task.checkCancellation()
                statusText = String(localized: "Saving…", comment: "Stack screen status while the new photo is written")
                guard let data = StackedPhotoMetadata.jpegData(
                    cgImage,
                    properties: StackedPhotoMetadata.properties(fromFirstFrame: firstFrameProperties),
                    quality: Self.jpegQuality
                ) else {
                    throw PhotoStackError.renderFailed
                }
                try Task.checkCancellation()
                let name = "ShotDex-\(mode.rawValue)-\(Int(Date().timeIntervalSince1970)).jpg"
                let assetID = try await photoLibrary.saveImage(data, filename: name)
                _ = await indexPipeline.indexSingle(assetId: assetID)
                photoLibrary.publishAppCreatedAsset()
                savedAssetID = assetID
            } catch is CancellationError {
                // Cancel closed the screen; nothing to report and nothing saved.
            } catch {
                failure = .save(error.localizedDescription)
            }
        }
    }
}

/// Why a save stopped before it wrote anything.
enum StackSaveError: LocalizedError, Equatable {
    case framesMissing(Int)

    var errorDescription: String? {
        switch self {
        case .framesMissing(let count):
            String(
                localized: "\(count) photos couldn't be downloaded. Check the connection and try again.",
                comment: "Stack save failed: some full-resolution originals could not be downloaded (usually iCloud)."
            )
        }
    }
}

extension PhotoStackModel {
    /// Capture time, then original file name (FS-01.10 §4).
    static func shootingOrder(_ assets: [PHAsset]) -> [PHAsset] {
        let frames = assets.map { asset in
            FocusStackOrder.Frame(
                id: asset.localIdentifier,
                captureDate: asset.creationDate,
                fileName: PHAssetResource.assetResources(for: asset).first?.originalFilename
            )
        }
        let byID = Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) })
        return FocusStackOrder.sorted(frames).compactMap { byID[$0] }
    }

    /// One frame at proxy resolution, through the viewer's own request path so
    /// an iCloud-only original is fetched rather than skipped.
    static func previewImage(for asset: PHAsset, photoLibrary: PhotoLibraryService) async -> UIImage? {
        await withCheckedContinuation { continuation in
            var hasResumed = false
            _ = photoLibrary.requestDetailImage(
                for: asset,
                targetSize: CGSize(width: 1600, height: 1600),
                allowNetwork: true,
                progress: { _ in }
            ) { image, isDegraded in
                // The request calls back more than once as better data lands;
                // take the first final one and ignore the rest.
                guard !isDegraded, !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: image)
            }
        }
    }

    /// The original file's bytes, for the full-resolution pass at save time.
    static func originalData(for asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
