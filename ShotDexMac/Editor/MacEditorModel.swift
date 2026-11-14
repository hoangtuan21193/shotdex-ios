import CoreGraphics
import CoreImage
import Foundation
import GRDB
import ShotDexKit

/// One editing session on the Mac (board `MAC_Edit`, FS-18.03): the photos
/// it can step through, the one open, its recipe and history, the preview,
/// the histogram and the save. File photos save on their own a moment after
/// each change (D16); a Photos library picture is row 40's (Done).
@MainActor
@Observable
final class MacEditorModel {
    enum Load: Equatable {
        case loading
        case ready
        /// Why this photo cannot be edited here, said on the canvas.
        case unavailable(String)
    }

    /// The tool the toolbar's capsule has on (rows 31–32; Mask, Heal and
    /// Markup are rows 34–36).
    enum Tool: String, CaseIterable, Identifiable {
        case adjust, crop
        var id: String { rawValue }
    }

    enum SaveState: Equatable {
        case unchanged
        case saving
        case saved
        case failed
    }

    /// What the toolbar's subtitle says of the photo open.
    struct Details: Equatable, Sendable {
        var fileName = ""
        var sourceName: String?
        var camera: String?
        var lens: String?
        var iso: Int?
        var focalLength: Double?
        var aperture: Double?
        var shutter: String?
    }

    let ids: [String]
    private(set) var index: Int
    var currentId: String { ids[index] }

    private(set) var load = Load.loading
    private(set) var details = Details()
    private(set) var recipe = PhotoEditRecipe.identity
    private(set) var history = PhotoEditHistory()
    private(set) var preview: CGImage?
    private(set) var histogram: PhotoHistogram?
    private(set) var clipping: CGImage?
    private(set) var saveState = SaveState.unchanged
    /// A render failed: the last good frame stays, with a line over it.
    private(set) var renderFailed = false
    /// Photos whose last write failed: their tile says so, and leaving or
    /// a click on "Couldn't Save" tries again.
    private(set) var failedIds: Set<String> = []
    /// Photos of the strip with a saved edit: their badge.
    private(set) var editedIds: Set<String> = []
    private(set) var isRAW = false
    /// The original's pixel size: Actual Size is drawn from it, not from
    /// whichever preview is up.
    private(set) var sourceSize = CGSize.zero

    /// Before and After (\): the original while held on.
    /// Crop shows the whole straightened photo with the frame over it; the
    /// render leaves the frame out (FS-18.03 §1b).
    var tool = Tool.adjust {
        didSet {
            guard tool != oldValue else { return }
            isStraightening = false
            render(interactive: false)
        }
    }
    /// Straighten Tool: a line dragged over the photo levels it.
    var isStraightening = false
    /// An Upright or Auto pass is reading the photo.
    private(set) var isAnalyzing = false
    /// Which control started it: its spinner, not the other's.
    private(set) var analyzingUpright = false
    /// Said under Straighten or Upright when its pass found nothing to go on.
    private(set) var straightenNote: String?
    private(set) var uprightNote: String?

    var showsBefore = false { didSet { if showsBefore != oldValue { render(interactive: false) } } }
    var showsHighlightClipping = false { didSet { updateClipping() } }
    var showsShadowClipping = false { didSet { updateClipping() } }

    private let dependencies: MacDependencies
    private let renderer = PhotoRenderService()
    @ObservationIgnored private var source: PhotoRenderSourceInfo?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var openTask: Task<Void, Never>?
    /// Writes go one after another (a save, then a flush, never reversed).
    @ObservationIgnored private var writeTask: Task<Void, Never>?
    /// Recipes written or on their way, by photo: a photo opened again reads
    /// these before the database, which may not have them yet.
    @ObservationIgnored private var written: [String: PhotoEditRecipe] = [:]
    /// Which opening a render or clipping belongs to: older ones are dropped.
    @ObservationIgnored private var generation = 0
    /// The render wanted next, and whether one is running: latest wins, at
    /// most one in flight (the renderer's work cannot be cancelled midway).
    @ObservationIgnored private var wanted: (recipe: PhotoEditRecipe, interactive: Bool)?
    @ObservationIgnored private var isRendering = false
    /// A drag's starting recipe, recorded once the drag changes something.
    @ObservationIgnored private var dragStart: PhotoEditRecipe?
    /// The recipe when the drag began, kept until it ends: a straighten drag
    /// fits the frame from where it was, not from where the last frame left it.
    @ObservationIgnored private(set) var dragBase: PhotoEditRecipe?
    /// The last recipe sent to the renderer: a crop drag changes no pixel
    /// while Crop shows the whole photo, so it renders nothing.
    @ObservationIgnored private var lastRequested: (recipe: PhotoEditRecipe, interactive: Bool)?
    /// The original, small, for Upright and Auto to read; made once a photo.
    @ObservationIgnored private var analysisImage: CGImage?
    /// The frame as it was before the photo was tilted: every angle fits it
    /// afresh, so turning back (or ↺) gives the frame its size back. Dropped
    /// once the frame itself changes.
    @ObservationIgnored private var straightenBase: NormalizedRect?
    /// Each photo's Undo, kept for the whole session: back on a photo, ⌘Z
    /// still reaches what was done to it.
    @ObservationIgnored private var histories: [String: PhotoEditHistory] = [:]
    @ObservationIgnored private var cleanImage: CGImage?
    /// A slider is held: frames render small and fast until it lets go.
    @ObservationIgnored private var isDragging = false
    /// The recipe last written: Saved means this equals the recipe.
    @ObservationIgnored private var savedRecipe = PhotoEditRecipe.identity

    init(ids: [String], start: String, dependencies: MacDependencies) {
        // The photo the viewer showed is the one edited, wherever it is.
        let ids = ids.contains(start) ? ids : [start]
        self.ids = ids
        index = ids.firstIndex(of: start) ?? 0
        self.dependencies = dependencies
    }

    // MARK: Opening

    func open() {
        open(at: index)
        loadEditedIds()
    }

    /// Steps to another photo of the strip; the one left has saved already.
    func open(at newIndex: Int) {
        guard ids.indices.contains(newIndex) else { return }
        flushSave()
        histories[currentId] = history
        generation += 1
        renderTask?.cancel()
        wanted = nil
        index = newIndex
        load = .loading
        preview = nil
        histogram = nil
        clipping = nil
        cleanImage = nil
        source = nil
        straightenBase = nil
        analysisImage = nil
        lastRequested = nil
        straightenNote = nil
        uprightNote = nil
        analysisTask?.cancel()
        isAnalyzing = false
        analyzingUpright = false
        isStraightening = false
        dragStart = nil
        dragBase = nil
        isDragging = false
        history = histories[ids[newIndex]] ?? PhotoEditHistory()
        renderFailed = false
        saveState = .unchanged
        showsBefore = false
        let id = currentId
        let generation = self.generation
        let pending = written[id]
        let database = dependencies.database
        let dependencies = self.dependencies
        let renderer = self.renderer
        openTask?.cancel()
        openTask = Task { [weak self] in
            let read = await Task.detached(priority: .userInitiated) { () -> (PhotoEditRecipe?, Details) in
                let recipe = try? PhotoRecipeStore(database: database).recipe(photoId: id)
                return (recipe, Self.readDetails(id, database: database))
            }.value
            guard let self, !Task.isCancelled, generation == self.generation else { return }
            self.details = read.1
            let recipe = pending ?? read.0 ?? .identity
            self.recipe = recipe
            self.savedRecipe = recipe
            self.saveState = self.failedIds.contains(id) ? .failed : (recipe == .identity ? .unchanged : .saved)
            guard let url = await Self.sourceURL(id, dependencies: dependencies) else {
                let reason = await Self.unavailableReason(id, dependencies: dependencies)
                guard !Task.isCancelled, generation == self.generation else { return }
                self.load = .unavailable(reason)
                return
            }
            do {
                let info = try await renderer.inspectSource(at: url)
                guard !Task.isCancelled, generation == self.generation else { return }
                self.source = info
                self.isRAW = info.isRAW
                self.sourceSize = CGSize(width: info.pixelWidth, height: info.pixelHeight)
                self.load = .ready
                self.render(interactive: false)
            } catch {
                guard !Task.isCancelled, generation == self.generation else { return }
                self.load = .unavailable(String(localized: "ShotDex can't read this file.", comment: "Mac editor: the original could not be decoded"))
            }
        }
    }

    func step(by offset: Int) { open(at: index + offset) }

    /// The file the editor renders: the demo's picture, or a file photo's
    /// original when it is on this Mac. Photos library pictures come with
    /// row 40 (Done writes them back to Photos).
    private static func sourceURL(_ id: String, dependencies: MacDependencies) async -> URL? {
        #if DEBUG
        if MacDemoLibrary.isOn, let url = await Task.detached(operation: { MacDemoLibrary.pictureFiles(for: [id]).first }).value { return url }
        #endif
        guard let file = await MacPhotoFiles.resolve(id, dependencies: dependencies), !file.isPlaceholder else { return nil }
        return file.url
    }

    private static func unavailableReason(_ id: String, dependencies: MacDependencies) async -> String {
        if let file = await MacPhotoFiles.resolve(id, dependencies: dependencies), file.isPlaceholder {
            return String(localized: "This photo is in iCloud Drive and not on this Mac yet. Download it in Finder, then edit it.",
                          comment: "Mac editor: the original is not on this Mac")
        }
        if await isPhotosOnly(id, database: dependencies.database) {
            return String(localized: "Photos library pictures can't be edited here yet. Photos in your folders and drives can.",
                          comment: "Mac editor: a Photos library picture")
        }
        return String(localized: "The file isn't reachable. Connect its drive or server, then edit it.",
                      comment: "Mac editor: a file photo whose drive or server is away")
    }

    /// The photo has no copy but the Photos library's.
    static func isPhotosOnly(_ id: String, database: AppDatabase) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let kinds = (try? database.reader.read { db in
                try String.fetchAll(db, sql: "SELECT kind FROM photo_copies WHERE photoId = ? AND missingSince IS NULL", arguments: [id])
            }) ?? []
            return !kinds.isEmpty && kinds.allSatisfy { $0 == "photos" }
        }.value
    }

    nonisolated private static func readDetails(_ id: String, database: AppDatabase) -> Details {
        (try? database.reader.read { db -> Details in
            var details = Details()
            if let row = try Row.fetchOne(db, sql: """
                SELECT originalFilename, COALESCE(normalizedCameraModel, cameraModel) AS camera,
                       COALESCE(normalizedLensModel, lensModel) AS lens, iso, focalLength, aperture, shutterSpeedDisplay
                FROM photo_metadata WHERE assetId = ?
                """, arguments: [id]) {
                details.fileName = row["originalFilename"] ?? ""
                details.camera = row["camera"]
                details.lens = row["lens"]
                details.iso = row["iso"]
                details.focalLength = row["focalLength"]
                details.aperture = row["aperture"]
                details.shutter = row["shutterSpeedDisplay"]
            }
            details.sourceName = try String.fetchOne(db, sql: """
                SELECT s.name FROM photo_copies c JOIN sources s ON s.id = c.sourceId
                WHERE c.photoId = ? AND c.missingSince IS NULL ORDER BY c.kind = 'photos' LIMIT 1
                """, arguments: [id])
            return details
        }) ?? Details()
    }

    private func loadEditedIds() {
        let database = dependencies.database
        let ids = self.ids
        Task { [weak self] in
            let edited = await Task.detached(priority: .utility) { () -> Set<String> in
                let found = (try? database.reader.read { db in try String.fetchAll(db, sql: "SELECT photoId FROM photo_recipes") }) ?? []
                return Set(found).intersection(ids)
            }.value
            self?.editedIds = edited
        }
    }

    // MARK: Changing

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    /// A slider is grabbed: one history step for the whole drag.
    func beginChange() {
        dragStart = recipe
        dragBase = recipe
        isDragging = true
        // An edit is seen as it is made: Before gives way.
        showsBefore = false
    }

    /// While dragging: small fast frames. The drag's undo step is taken on
    /// its first real change, so a click that moves nothing leaves none.
    func set(_ kind: PhotoAdjustmentKind, to value: Double) {
        change { $0.adjustments[kind] = value }
    }

    /// A step of a drag (a slider, the crop frame): previewed, recorded once.
    func change(_ body: (inout PhotoEditRecipe) -> Void) {
        var next = recipe
        body(&next)
        guard next != recipe else { return }
        if let start = dragStart {
            history.record(start)
            dragStart = nil
        }
        recipe = next
        render(interactive: isDragging)
    }

    /// The slider let go: the full preview, then the save.
    func endChange() {
        let moved = dragStart == nil
        dragStart = nil
        dragBase = nil
        isDragging = false
        guard moved else { return }
        render(interactive: false)
        scheduleSave()
    }

    /// A change made in one step (a typed value, Reset, a menu).
    func apply(_ change: (inout PhotoEditRecipe) -> Void) {
        var next = recipe
        change(&next)
        guard next != recipe else { return }
        showsBefore = false
        history.record(recipe)
        recipe = next
        render(interactive: false)
        scheduleSave()
    }

    func undo() {
        straightenBase = nil
        guard let previous = history.undo(current: recipe) else { return }
        recipe = previous
        render(interactive: false)
        scheduleSave()
    }

    func redo() {
        straightenBase = nil
        guard let next = history.redo(current: recipe) else { return }
        recipe = next
        render(interactive: false)
        scheduleSave()
    }

    /// Revert to Original…: the photo as it came, kept undoable.
    func revert() {
        apply { $0 = .identity }
    }

    // MARK: Crop (FS-18.03 §1b)

    /// The crop's arithmetic for the photo open, at the recipe's angle.
    var cropEditing: CropFrameEditing? {
        guard let source else { return nil }
        return Self.cropEditing(source, recipe.crop)
    }

    private static func cropEditing(_ source: PhotoRenderSourceInfo, _ crop: PhotoCropRecipe) -> CropFrameEditing {
        CropFrameEditing(
            photoSize: CropFrameEditing.photoSize(pixelWidth: source.pixelWidth, pixelHeight: source.pixelHeight,
                                                  orientation: source.orientation, quarterTurns: crop.quarterTurns),
            degrees: crop.straightenDegrees)
    }

    /// A handle dragged by `dx`, `dy` (normalized) from where the drag began.
    func dragCrop(_ handle: CropFrameEditing.Handle, from start: NormalizedRect, dx: Double, dy: Double) {
        guard let editing = cropEditing else { return }
        let ratio = editing.ratio(of: recipe.crop.aspect)
        straightenBase = nil
        change { $0.crop.rect = editing.dragged(start, handle: handle, dx: dx, dy: dy, ratio: ratio) }
    }

    /// The lock: on holds the last ratio chosen (the photo's own at first),
    /// off lets the frame go free.
    @ObservationIgnored private var lastLockedAspect = CropAspect.original
    var isAspectLocked: Bool { recipe.crop.aspect != .free }

    /// Aspect ▾: the frame takes the ratio about its centre, keeping its area.
    func chooseAspect(_ aspect: CropAspect) {
        guard let editing = cropEditing else { return }
        straightenBase = nil
        apply { recipe in
            recipe.crop.aspect = aspect
            if let ratio = editing.ratio(of: aspect) { recipe.crop.rect = editing.reshaped(recipe.crop.rect, toRatio: ratio) }
        }
        if aspect != .free { lastLockedAspect = aspect }
    }

    /// Locking a free frame holds the ratio it has, when that ratio has a
    /// name; otherwise the last one chosen.
    func toggleAspectLock() {
        guard !isAspectLocked else { chooseAspect(.free); return }
        if let editing = cropEditing {
            let rect = recipe.crop.rect
            let ratio = rect.width * Double(editing.frameSize.width) / max(1, rect.height * Double(editing.frameSize.height))
            if let preset = CropFrameEditing.preset(matching: ratio) { chooseAspect(preset); return }
            if abs(ratio - editing.photoAspect) / editing.photoAspect < 0.01 { chooseAspect(.original); return }
        }
        chooseAspect(lastLockedAspect)
    }

    /// ⇅: the same ratio on its other side; nil when there is none (1:1).
    var swappedAspect: CropAspect? {
        let aspect = recipe.crop.aspect
        if aspect == .free { return .free }
        if aspect == .original, let editing = cropEditing {
            // A square photo's own ratio has no other side.
            guard abs(editing.photoAspect - 1) > 0.01 else { return nil }
            return CropFrameEditing.preset(matching: 1 / editing.photoAspect)
        }
        return aspect.swapped
    }

    func swapAspect() {
        guard let editing = cropEditing, let swapped = swappedAspect else { return }
        if swapped == .free {
            // A free frame turns on its centre: its pixel width becomes its height.
            let rect = recipe.crop.rect
            let ratio = (rect.height * Double(editing.frameSize.height)) / max(1, rect.width * Double(editing.frameSize.width))
            apply { $0.crop.rect = editing.reshaped(rect, toRatio: ratio) }
        } else {
            chooseAspect(swapped)
        }
    }

    /// Rotate Left / Right: the photo a quarter turn, the frame with it.
    func turn(clockwise: Bool) {
        straightenBase = nil
        apply { recipe in
            recipe.crop.quarterTurns = (recipe.crop.quarterTurns + (clockwise ? 1 : 3)) % 4
            recipe.crop.rect = CropFrameEditing.turned(recipe.crop.rect, clockwise: clockwise)
            if let swapped = recipe.crop.aspect.swapped { recipe.crop.aspect = swapped }
        }
        if let swapped = lastLockedAspect.swapped { lastLockedAspect = swapped }
    }

    /// Flip Horizontal / Vertical: the frame mirrored with the photo.
    func flip(vertically: Bool) {
        straightenBase = nil
        apply { recipe in
            recipe.crop.flippedHorizontally.toggle()
            // The flip runs before the angle: mirrored, a tilt to the left is
            // one to the right, or the horizon the user levelled tips twice over.
            recipe.crop.straightenDegrees = -recipe.crop.straightenDegrees
            if vertically {
                // A half turn and a mirror: the photo upside down, not round.
                recipe.crop.quarterTurns = (recipe.crop.quarterTurns + 2) % 4
                recipe.crop.rect = CropFrameEditing.mirroredVertically(recipe.crop.rect)
            } else {
                recipe.crop.rect = CropFrameEditing.mirroredHorizontally(recipe.crop.rect)
            }
        }
    }

    /// Crop ↺: the whole photo, unturned and unmirrored, free; the angle stays.
    func resetCrop() {
        guard let source else { return }
        straightenBase = nil
        apply { recipe in
            let degrees = recipe.crop.straightenDegrees
            recipe.crop = .identity
            recipe.crop.straightenDegrees = degrees
            recipe.crop.rect = Self.cropEditing(source, recipe.crop).fitted(.full)
        }
    }

    /// The angle, with the frame kept on the photo — fitted from where the
    /// frame was when the drag began, so turning back regrows it.
    func straighten(to degrees: Double, inOneStep: Bool = false) {
        guard let source else { return }
        let clamped = min(45, max(-45, degrees))
        let base = straightenBase ?? (dragBase ?? recipe).crop.rect
        straightenBase = base
        let body: (inout PhotoEditRecipe) -> Void = { recipe in
            recipe.crop.straightenDegrees = clamped
            let editing = Self.cropEditing(source, recipe.crop)
            // A new angle changes the frame's own shape: a locked ratio is
            // laid out again in pixels before the frame is fitted.
            if let ratio = editing.ratio(of: recipe.crop.aspect) {
                recipe.crop.rect = editing.reshaped(base, toRatio: ratio)
            } else {
                recipe.crop.rect = editing.fitted(base)
            }
        }
        if inOneStep { apply(body) } else { change(body) }
        straightenNote = nil
    }

    /// Straighten ↺: level again, the frame back to what fits.
    func resetStraighten() {
        straighten(to: 0, inOneStep: true)
    }

    /// The Straighten Tool's line, let go: the photo turns by what levels it.
    func straighten(byRuler correction: Double) {
        straighten(to: StraightenToolMath.angle(current: recipe.crop.straightenDegrees, adding: correction), inOneStep: true)
        isStraightening = false
    }

    /// Straighten › Auto: Upright's Level pass, written into the angle.
    func autoStraighten() {
        straightenNote = nil
        analyze(.level) { [weak self] suggestion in
            guard let self else { return }
            guard let suggestion, abs(suggestion.rotate) > 0.001 else {
                self.straightenNote = self.analysisReadFailed
                    ? Self.readFailedNote
                    : String(localized: "No level line found in this photo.", comment: "Mac editor: Straighten Auto found nothing")
                return
            }
            // The analysis reads the photo before the flip; the angle turns what is shown.
            let degrees = self.recipe.crop.flippedHorizontally ? -suggestion.rotationDegrees : suggestion.rotationDegrees
            if abs(degrees - self.recipe.crop.straightenDegrees) < 0.05 {
                self.straightenNote = String(localized: "Already level.", comment: "Mac editor: Straighten Auto found the photo level already")
                return
            }
            self.straighten(to: degrees, inOneStep: true)
        }
    }

    /// Upright ▾: Off clears it; the others read the photo once and keep
    /// the solved correction apart from the Geometry sliders. The popup is
    /// off while a pass runs; Off still wins over one in flight.
    func setUpright(_ mode: PhotoUprightMode) {
        uprightNote = nil
        guard mode != .off, let analysisMode = UprightMode(rawValue: mode.rawValue) else {
            // Off stops an Upright pass still reading (an Auto pass runs on).
            if analyzingUpright { analysisToken += 1; analysisTask?.cancel(); isAnalyzing = false; analyzingUpright = false }
            apply { $0.upright = .identity }
            return
        }
        guard !isAnalyzing else { return }
        analyzingUpright = true
        analyze(analysisMode) { [weak self] suggestion in
            guard let self else { return }
            guard let suggestion else {
                self.uprightNote = self.analysisReadFailed
                    ? Self.readFailedNote
                    : String(localized: "No straight lines found in this photo.", comment: "Mac editor: Upright found nothing")
                return
            }
            self.apply { $0.upright.mode = mode; $0.upright.solved = suggestion.transform(for: analysisMode) }
        }
    }

    private static var readFailedNote: String {
        String(localized: "ShotDex couldn't read this photo. Try again.", comment: "Mac editor: Upright or Auto could not render the original")
    }

    /// Which request a pass answers: Off, a new photo or a newer pick drops it.
    @ObservationIgnored private var analysisToken = 0
    /// The last pass had no picture to read (not: found no lines).
    @ObservationIgnored private var analysisReadFailed = false

    /// Upright reads one 1024px bitmap at a time, on its own serial queue —
    /// never a concurrency-pool thread held by a GPU readback — with the
    /// queue as the context's only user.
    nonisolated private static let analysisQueue = DispatchQueue(label: "shotdex.mac.editor.upright", qos: .userInitiated)
    nonisolated private static let analysisContext = CIContext(options: [.useSoftwareRenderer: false])
    @ObservationIgnored private var analysisTask: Task<Void, Never>?

    /// Reads the original (never the edited frame, or a second pass corrects
    /// the first again), off the main actor.
    private func analyze(_ mode: UprightMode, then: @escaping (UprightSuggestion?) -> Void) {
        guard let source, !isAnalyzing else { analyzingUpright = false; return }
        isAnalyzing = true
        analysisToken += 1
        let token = analysisToken
        let generation = self.generation
        let renderer = self.renderer
        let cached = analysisImage.map(ImageBox.init)
        analysisTask = Task { [weak self] in
            var box = cached
            if box == nil, let images = try? await renderer.renderPreviewImages(source: source, recipe: .identity, maximumDimension: 1024) {
                box = ImageBox(images.cleanImage)
            }
            guard !Task.isCancelled else { return }
            let found = box
            let suggestion: UprightSuggestion? = await withCheckedContinuation { continuation in
                Self.analysisQueue.async {
                    continuation.resume(returning: found.flatMap {
                        UprightAnalyzer.analyze(CIImage(cgImage: $0.image), mode: mode, context: Self.analysisContext)
                    })
                }
            }
            guard let self, generation == self.generation, token == self.analysisToken else { return }
            self.isAnalyzing = false
            self.analyzingUpright = false
            if self.analysisImage == nil { self.analysisImage = found?.image }
            self.analysisReadFailed = found == nil
            then(suggestion)
        }
    }

    // MARK: Rendering

    /// The canvas's frame: small while a slider moves, full 90 ms after the
    /// last change. Latest wins: a request made while one renders replaces
    /// any other waiting, and runs when that one is done.
    private func render(interactive: Bool) {
        guard source != nil else { return }
        var drawn = showsBefore ? PhotoEditRecipe.identity : recipe
        if tool == .crop {
            // The frame is drawn over the whole straightened photo; masks and
            // layers sit in the cropped frame's space and would land wrong.
            drawn.crop.rect = .full
            drawn.crop.aspect = .free
            drawn.masks = []
            drawn.overlays = []
        }
        // Nothing new to draw (a crop drag while Crop shows the whole photo).
        if let last = lastRequested, last.recipe == drawn, !(last.interactive && !interactive) { return }
        lastRequested = (drawn, interactive)
        wanted = (drawn, interactive)
        if interactive {
            renderTask?.cancel()
            pump()
        } else {
            renderTask?.cancel()
            renderTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }
                self?.pump()
            }
        }
    }

    private func pump() {
        guard !isRendering, let next = wanted, let source else { return }
        wanted = nil
        isRendering = true
        let generation = self.generation
        let renderer = self.renderer
        Task { [weak self] in
            let images = try? await (next.interactive
                ? renderer.renderInteractivePreviewImages(source: source, recipe: next.recipe, maximumDimension: 1000, cachesBase: true)
                : renderer.renderPreviewImages(source: source, recipe: next.recipe, maximumDimension: 2400))
            var histogram: PhotoHistogram?
            if let images, !next.interactive { histogram = await renderer.histogram(of: images.cleanImage) }
            guard let self else { return }
            self.isRendering = false
            if generation == self.generation {
                if let images {
                    self.renderFailed = false
                    self.preview = images.displayImage
                    self.cleanImage = images.cleanImage
                    if let histogram { self.histogram = histogram; self.updateClipping() }
                } else if self.wanted == nil {
                    // The last good frame stays; Undo or another change renders again.
                    self.renderFailed = true
                    // Asking again for the same picture must draw, not be skipped.
                    self.lastRequested = nil
                }
            }
            self.pump()
        }
    }

    /// The red/blue clipped pixels over the photo, made off the main actor.
    private func updateClipping() {
        guard showsHighlightClipping || showsShadowClipping, let image = cleanImage else { clipping = nil; return }
        let highlights = showsHighlightClipping, shadows = showsShadowClipping
        let box = ImageBox(image)
        let generation = self.generation
        Task { [weak self] in
            let overlay = await Task.detached(priority: .userInitiated) {
                ClippingOverlay.make(from: box.image, highlights: highlights, shadows: shadows).map(ImageBox.init)
            }.value
            guard let self, generation == self.generation else { return }
            self.clipping = overlay?.image
        }
    }

    // MARK: Saving (D16)

    /// File photos save on their own 400 ms after the last change.
    private func scheduleSave() {
        saveTask?.cancel()
        saveState = recipe == savedRecipe ? (recipe == .identity ? .unchanged : .saved) : .saving
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    /// Leaving the photo or the editor: what is pending is written now —
    /// a failed save is tried again here too.
    func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        guard recipe != savedRecipe else { return }
        write(recipe, id: currentId)
    }

    /// ⌘Q: the write cannot wait for a task the app will not run.
    func flushNow() {
        saveTask?.cancel()
        saveTask = nil
        guard recipe != savedRecipe else { return }
        try? PhotoRecipeStore(database: dependencies.database).save(recipe, photoId: currentId)
        savedRecipe = recipe
    }

    /// "Couldn't Save", clicked: the photo open is written again.
    func retrySave() {
        write(recipe, id: currentId)
    }

    private func save() async {
        saveTask = nil
        guard recipe != savedRecipe else { return }
        write(recipe, id: currentId)
    }

    /// One write after the other, in the order asked.
    private func write(_ recipe: PhotoEditRecipe, id: String) {
        let store = PhotoRecipeStore(database: dependencies.database)
        let sidecars = dependencies.sidecarQueue
        written[id] = recipe
        saveState = .saving
        let previous = writeTask
        writeTask = Task { [weak self] in
            await previous?.value
            let ok = await Task.detached(priority: .userInitiated) { (try? store.save(recipe, photoId: id)) != nil }.value
            // The sidecar carries the recipe on to the folder (FS-19).
            if ok { await sidecars.schedule([id]) }
            guard let self else { return }
            if ok {
                if recipe == .identity { self.editedIds.remove(id) } else { self.editedIds.insert(id) }
                self.failedIds.remove(id)
            } else {
                self.failedIds.insert(id)
                if self.written[id] == recipe { self.written[id] = nil }
            }
            guard id == self.currentId else { return }
            if ok { self.savedRecipe = recipe }
            self.saveState = !ok ? .failed : (self.recipe == recipe ? (recipe == .identity ? .unchanged : .saved) : .saving)
        }
    }
}

/// A rendered frame handed across a detached task or queue: `CGImage` is an
/// immutable CF type, never changed after it is made — that is the guard.
private struct ImageBox: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

