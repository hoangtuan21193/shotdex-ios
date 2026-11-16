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
        case adjust, crop, mask, heal
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
            isPickingColor = false
            if tool != .mask { thumbnailTask?.cancel() }
            if tool != .heal {
                visualizesSpots = false
                // Back in Heal later starts neutral: nothing picked, the brush is for new spots.
                selectedSpotId = nil
                selectedRedEyeId = nil
            }
            render(interactive: false)
        }
    }
    /// Straighten Tool: a line dragged over the photo levels it.
    var isStraightening = false
    /// Point Color's eyedropper: the canvas shows a loupe, a click adds a colour.
    var isPickingColor = false { didSet { if isPickingColor { showsBefore = false } } }
    /// The Point Color whose sliders show.
    var selectedPointColorId: UUID?
    /// An Upright or Auto pass is reading the photo.
    private(set) var isAnalyzing = false
    /// Which control started it: its spinner, not the other's.
    private(set) var analyzingUpright = false
    /// Said under Straighten or Upright when its pass found nothing to go on.
    private(set) var straightenNote: String?
    private(set) var uprightNote: String?

    var showsBefore = false {
        didSet {
            guard showsBefore != oldValue else { return }
            // The eyedropper reads the edited frame: it does not stay out over the original.
            if showsBefore { isPickingColor = false }
            render(interactive: false)
        }
    }
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
    @ObservationIgnored private var wanted: (recipe: PhotoEditRecipe, interactive: Bool, overlay: UUID?)?
    @ObservationIgnored private var isRendering = false
    /// A drag's starting recipe, recorded once the drag changes something.
    @ObservationIgnored private var dragStart: PhotoEditRecipe?
    /// The recipe when the drag began, kept until it ends: a straighten drag
    /// fits the frame from where it was, not from where the last frame left it.
    @ObservationIgnored private(set) var dragBase: PhotoEditRecipe?
    /// The last recipe sent to the renderer: a crop drag changes no pixel
    /// while Crop shows the whole photo, so it renders nothing.
    @ObservationIgnored private var lastRequested: (recipe: PhotoEditRecipe, interactive: Bool, overlay: UUID?)?
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
        isPickingColor = false
        activeStroke = nil
        thumbnailKey = nil
        brushErases = false
        resolvedAutoAreas = []
        emptyAutoAreas = []
        selectedPointColorId = nil
        selectedSpotId = nil
        selectedRedEyeId = nil
        selectedMaskId = nil
        selectedComponentId = nil
        maskThumbnails = [:]
        hiddenSpotIds = []
        offeredSources = [:]
        spotMap = nil
        healNote = nil
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
        reconcileSelection()
        render(interactive: false)
        scheduleSave()
    }

    func redo() {
        straightenBase = nil
        guard let next = history.redo(current: recipe) else { return }
        recipe = next
        reconcileSelection()
        render(interactive: false)
        scheduleSave()
    }

    /// After Undo or Redo: a picked spot, eye or colour that is no longer there is not picked.
    private func reconcileSelection() {
        activeStroke = nil
        if let id = selectedSpotId, !recipe.healing.contains(where: { $0.id == id }) { selectedSpotId = nil }
        if let id = selectedRedEyeId, !recipe.redEyes.contains(where: { $0.id == id }) { selectedRedEyeId = nil }
        if let id = selectedPointColorId, !recipe.color.points.contains(where: { $0.id == id }) { selectedPointColorId = nil }
        if let id = selectedMaskId, !recipe.masks.contains(where: { $0.id == id }) { selectMask(nil) }
        if selectedMaskId != nil, let id = selectedComponentId, selectedMask?.components.contains(where: { $0.id == id }) != true {
            selectedComponentId = selectedMask?.components.last?.id
        }
    }

    /// Revert to Original…: the photo as it came, kept undoable.
    func revert() {
        apply { $0 = .identity }
    }

    // MARK: Color (FS-18.03 §1c)

    /// The edited frame as the canvas shows it, for the eyedropper: the
    /// colour picked is the colour seen (Lightroom; the iPhone does the same).
    var samplingImage: CGImage? { cleanImage }

    var selectedPointColor: PointColorAdjustment? {
        recipe.color.points.first { $0.id == selectedPointColorId } ?? recipe.color.points.last
    }

    var canAddPointColor: Bool { recipe.color.points.count < PointColorAdjustment.maximumCount }

    /// A click with the eyedropper: the colour under it becomes a new point,
    /// selected; the eyedropper puts itself away.
    func addPointColor(at point: NormalizedPoint) {
        // Nothing to read yet (the frame is still drawing): the eyedropper stays out.
        guard canAddPointColor, let image = cleanImage,
              let rgb = MacColorSampler.color(in: image, at: point) else { return }
        isPickingColor = false
        let hsv = ColorRenderMath.hsv(fromRed: rgb.x, green: rgb.y, blue: rgb.z)
        let added = PointColorAdjustment(referenceHue: hsv.hue, referenceSaturation: hsv.saturation, referenceValue: hsv.value)
        apply { $0.color.points.append(added) }
        selectedPointColorId = added.id
    }

    func removeSelectedPointColor() {
        guard let id = selectedPointColor?.id else { return }
        apply { $0.color.points.removeAll { $0.id == id } }
        selectedPointColorId = recipe.color.points.last?.id
    }

    /// One slider of the selected point (a drag step or a typed value).
    func changeSelectedPointColor(inOneStep: Bool = false, _ body: @escaping (inout PointColorAdjustment) -> Void) {
        guard let id = selectedPointColor?.id else { return }
        let update: (inout PhotoEditRecipe) -> Void = { recipe in
            if let index = recipe.color.points.firstIndex(where: { $0.id == id }) { body(&recipe.color.points[index]) }
        }
        if inOneStep { apply(update) } else { change(update) }
    }

    // MARK: Mask (FS-18.03 §1e)

    var selectedMaskId: UUID? { didSet { if selectedMaskId != oldValue { render(interactive: false) } } }
    var selectedComponentId: UUID?
    /// The picked mask in red over the photo (board: on by default).
    var showsMaskOverlay = true { didSet { render(interactive: false) } }
    var brushErases = false
    /// Brush diameter as a fraction of the short edge, feather, flow (the iPhone's units).
    var brushSize = 0.12
    var brushFeather = 0.45
    var brushFlow = 0.8
    /// Automatic areas (Subject, Sky, Object, People, Depth) the renderer has
    /// worked out, and those that came back empty: "detecting…", "nothing found".
    private(set) var resolvedAutoAreas: Set<UUID> = []
    private(set) var emptyAutoAreas: Set<UUID> = []
    /// A mask slider is held: the red steps aside so the change is seen.
    var hidesOverlayWhileAdjusting = false { didSet { if hidesOverlayWhileAdjusting != oldValue { render(interactive: false) } } }
    /// Each mask's shape, small, for the list.
    private(set) var maskThumbnails: [UUID: CGImage] = [:]
    @ObservationIgnored private var thumbnailTask: Task<Void, Never>?
    /// The stroke being painted, by its owner — not whatever area is picked when the next point comes.
    @ObservationIgnored private var activeStroke: (mask: UUID, component: UUID, index: Int)?
    /// The mask shapes the thumbnails were made for: they are made again only when one changes.
    @ObservationIgnored private var thumbnailKey: [PhotoMask]?

    var selectedMask: PhotoMask? { recipe.masks.first { $0.id == selectedMaskId } }
    var selectedComponent: PhotoMaskComponent? { selectedMask?.components.first { $0.id == selectedComponentId } }
    private var maskIndex: Int? { recipe.masks.firstIndex { $0.id == selectedMaskId } }

    /// + › a kind: a new mask "Mask n" with that one area, picked.
    func addMask(_ option: EditorNewMaskOption) {
        var component = PhotoMaskComponent(kind: option.componentKind)
        // Background is Subject inverted — on the area, not the mask: an inverted
        // mask would invert every area added to it later as well.
        component.isInverted = option.startsInverted
        let mask = PhotoMask(name: String(localized: "Mask \(recipe.masks.count + 1)", comment: "Mac editor mask: a new mask's name"),
                             component: component)
        apply { $0.masks.append(mask) }
        selectedMaskId = mask.id
        selectedComponentId = component.id
    }

    /// Add / Subtract / Intersect › a kind: one more area in the picked mask
    /// (a new mask when none is picked — the first area always adds).
    func addArea(_ option: EditorNewMaskOption, _ operation: MaskBlendOperation) {
        guard let index = maskIndex else { addMask(option); return }
        var component = PhotoMaskComponent(kind: option.componentKind, operation: operation)
        component.isInverted = option.startsInverted
        apply { $0.masks[index].components.append(component) }
        selectedComponentId = component.id
    }

    /// Delete / ⌘⌫ in Mask: the picked area, or the mask when it is the last one.
    func deleteSelectedMaskPart() {
        guard let mask = selectedMask else { return }
        if let component = selectedComponentId, mask.components.count > 1 {
            deleteComponent(component, in: mask.id)
        } else {
            deleteMask(mask.id)
        }
    }

    func selectMask(_ id: UUID?) {
        selectedMaskId = id
        selectedComponentId = selectedMask?.components.last?.id
    }

    func selectComponent(_ id: UUID, in mask: UUID) {
        selectedMaskId = mask
        selectedComponentId = id
    }

    func updateMask(_ id: UUID, inOneStep: Bool = true, _ body: @escaping (inout PhotoMask) -> Void) {
        let update: (inout PhotoEditRecipe) -> Void = { recipe in
            if let index = recipe.masks.firstIndex(where: { $0.id == id }) { body(&recipe.masks[index]) }
        }
        if inOneStep { apply(update) } else { change(update) }
    }

    func updateComponent(inOneStep: Bool = false, _ body: @escaping (inout PhotoMaskComponent) -> Void) {
        guard let maskId = selectedMaskId, let componentId = selectedComponentId else { return }
        updateMask(maskId, inOneStep: inOneStep) { mask in
            if let index = mask.components.firstIndex(where: { $0.id == componentId }) { body(&mask.components[index]) }
        }
    }

    func renameMask(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateMask(id) { $0.name = trimmed }
    }

    func duplicateMask(_ id: UUID) {
        guard var copy = recipe.masks.first(where: { $0.id == id }) else { return }
        copy.id = UUID()
        copy.components = copy.components.map { var c = $0; c.id = UUID(); return c }
        copy.name = String(localized: "\(copy.name) Copy", comment: "Mac editor mask: a duplicated mask's name")
        let duplicate = copy
        apply { recipe in
            let at = (recipe.masks.firstIndex { $0.id == id } ?? recipe.masks.count - 1) + 1
            recipe.masks.insert(duplicate, at: at)
        }
        selectMask(duplicate.id)
    }

    func deleteMask(_ id: UUID) {
        apply { $0.masks.removeAll { $0.id == id } }
        if selectedMaskId == id { selectMask(nil) }
    }

    func deleteComponent(_ id: UUID, in maskId: UUID) {
        guard let mask = recipe.masks.first(where: { $0.id == maskId }) else { return }
        // The last area goes with its mask: a mask with no area masks nothing.
        if mask.components.count <= 1 { deleteMask(maskId); return }
        updateMask(maskId) { $0.components.removeAll { $0.id == id } }
        if selectedComponentId == id { selectedComponentId = recipe.masks.first { $0.id == maskId }?.components.last?.id }
    }

    /// The picked brush area: a stroke starts where the pointer went down.
    func beginBrushStroke(at point: NormalizedPoint) {
        guard let component = selectedComponent, component.kind == .brush, let maskId = selectedMaskId else { return }
        beginChange()
        let stroke = BrushStroke(points: [point], size: brushSize, feather: brushFeather, flow: brushFlow, isEraser: brushErases)
        updateComponent { $0.brushStrokes.append(stroke) }
        activeStroke = (maskId, component.id, component.brushStrokes.count)
    }

    func continueBrushStroke(at point: NormalizedPoint) {
        guard let active = activeStroke,
              let component = recipe.masks.first(where: { $0.id == active.mask })?.components.first(where: { $0.id == active.component }),
              let stroke = component.brushStrokes[safe: active.index] else { return }
        if let last = stroke.points.last, hypot(point.x - last.x, point.y - last.y) <= 0.002 { return }
        updateMask(active.mask, inOneStep: false) { mask in
            guard let c = mask.components.firstIndex(where: { $0.id == active.component }),
                  mask.components[c].brushStrokes.indices.contains(active.index) else { return }
            mask.components[c].brushStrokes[active.index].points.append(point)
        }
    }

    func endBrushStroke() {
        guard activeStroke != nil else { return }
        activeStroke = nil
        endChange()
    }

    /// A drag over the photo for a gradient: linear from start to end;
    /// radial centred on the start, the drag giving its two radii.
    func setGradient(start: NormalizedPoint, end: NormalizedPoint) {
        guard let kind = selectedComponent?.kind else { return }
        switch kind {
        case .linearGradient:
            updateComponent { $0.startPoint = start; $0.endPoint = end }
        case .radialGradient:
            updateComponent {
                $0.center = start
                $0.radiusX = min(1, max(0.02, abs(end.x - start.x)))
                $0.radiusY = min(1, max(0.02, abs(end.y - start.y)))
            }
        default:
            break
        }
    }

    /// Object: the click picks it. Color Range: the click samples the colour shown.
    func setMaskPoint(_ point: NormalizedPoint) {
        guard let kind = selectedComponent?.kind else { return }
        switch kind {
        case .object:
            updateComponent(inOneStep: true) { $0.objectPoint = point }
        case .colorRange:
            guard let image = cleanImage, let rgb = MacColorSampler.color(in: image, at: point) else { return }
            updateComponent(inOneStep: true) { $0.sampledRed = rgb.x; $0.sampledGreen = rgb.y; $0.sampledBlue = rgb.z }
        default:
            break
        }
    }

    /// The masks' shapes for the list, made off the main actor after a settled frame.
    private func refreshMaskThumbnails() {
        guard tool == .mask, !recipe.masks.isEmpty, let source else { return }
        // Only a change of shape: a mask's sliders, tint or curve do not move it.
        let key = recipe.masks.map { mask -> PhotoMask in
            var shape = mask
            shape.adjustments = .zero
            shape.tint = nil
            shape.curve = nil
            shape.pointColors = nil
            shape.name = ""
            return shape
        }
        guard key != thumbnailKey else { return }
        thumbnailKey = key
        thumbnailTask?.cancel()
        let recipe = self.recipe, renderer = self.renderer, generation = self.generation
        thumbnailTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let images = try? await renderer.maskThumbnails(source: source, recipe: recipe, maximumDimension: 80)
            guard let self, !Task.isCancelled, generation == self.generation, let images else { return }
            self.maskThumbnails = images.images
        }
    }

    // MARK: Heal (FS-18.03 §1d)

    enum HealMode: String, CaseIterable, Identifiable {
        case heal, clone, redEye
        var id: String { rawValue }
        var spotMode: PhotoHealingMode? { self == .heal ? .heal : self == .clone ? .clone : nil }
    }

    /// What a click or a stroke on the photo makes; also the selected spot's mode.
    private(set) var healMode = HealMode.heal
    /// A new spot's size (fraction of the short edge), feather and opacity;
    /// the sliders show the selected spot's own once one is picked.
    var healRadius = 0.03
    var healFeather = 0.5
    var healOpacity = 1.0
    var redEyePupil = 0.5
    var redEyeDarken = 0.5
    var selectedSpotId: UUID?
    var selectedRedEyeId: UUID?
    /// Spots whose outline is switched off with the eye in the list (the
    /// spot still heals: a picture that differs from the saved one would lie).
    private(set) var hiddenSpotIds: Set<UUID> = []
    var showsSpotPins = true
    /// Visualize Spots: the photo as an edge map where dust shows white.
    var visualizesSpots = false { didSet { updateSpotMap() } }
    var spotThreshold = 0.5 { didSet { updateSpotMap() } }
    private(set) var spotMap: CGImage?
    /// "No other source found", "No red eyes found": said under the list.
    private(set) var healNote: String?
    @ObservationIgnored private var offeredSources: [UUID: [NormalizedPoint]] = [:]
    /// A New Source is being worked out: a second press waits for it.
    private(set) var isFindingSource = false
    @ObservationIgnored private var spotMapTask: Task<Void, Never>?

    var selectedSpot: PhotoHealingSpot? { recipe.healing.first { $0.id == selectedSpotId } }
    var selectedRedEye: PhotoRedEyeSpot? { recipe.redEyes.first { $0.id == selectedRedEyeId } }

    /// The cropped frame's short edge in the original's pixels: Size reads in these.
    var healShortEdgePixels: Double {
        guard let editing = cropEditing else { return 1000 }
        let size = editing.pixelSize(of: recipe.crop.rect)
        return Double(max(1, min(size.width, size.height)))
    }

    /// Width over height of the frame the spots sit on (the cropped photo).
    var healAspect: Double {
        guard let preview, preview.height > 0 else { return 1.5 }
        return Double(preview.width) / Double(preview.height)
    }

    func setHealMode(_ mode: HealMode) {
        healMode = mode
        healNote = nil
        if let spotMode = mode.spotMode, let id = selectedSpotId {
            updateSpot(id, inOneStep: true) { $0.mode = spotMode }
        }
    }

    /// Size, Feather, Opacity, Pupil, Darken: the next spot's, and the selected one's.
    func setHealValue(_ key: ReferenceWritableKeyPath<MacEditorModel, Double>, _ value: Double, inOneStep: Bool) {
        self[keyPath: key] = value
        switch key {
        case \MacEditorModel.healRadius: if let id = selectedSpotId { updateSpot(id, inOneStep: inOneStep) { $0.radius = value } }
        case \MacEditorModel.healFeather: if let id = selectedSpotId { updateSpot(id, inOneStep: inOneStep) { $0.feather = value } }
        case \MacEditorModel.healOpacity: if let id = selectedSpotId { updateSpot(id, inOneStep: inOneStep) { $0.opacity = value } }
        case \MacEditorModel.redEyePupil: if let id = selectedRedEyeId { updateRedEye(id, inOneStep: inOneStep) { $0.pupilSize = value } }
        case \MacEditorModel.redEyeDarken: if let id = selectedRedEyeId { updateRedEye(id, inOneStep: inOneStep) { $0.darken = value } }
        default: break
        }
    }

    /// A click on the photo: a spot filled from beside it, selected.
    func addSpot(at center: NormalizedPoint) {
        guard let mode = healMode.spotMode else { return }
        let spot = PhotoHealingSpot(
            mode: mode, center: center,
            source: PhotoHealingSpot.suggestedSource(for: center, radius: healRadius, aspectRatio: healAspect),
            radius: healRadius, feather: healFeather, opacity: healOpacity)
        apply { $0.healing.append(spot) }
        selectedSpotId = spot.id
        healNote = nil
    }

    /// A drag over the photo: a brush-stroke spot along it (points 0…1 over
    /// the cropped frame), thinned to one point every half radius.
    func addStroke(through points: [NormalizedPoint]) {
        guard let mode = healMode.spotMode else { return }
        let aspect = healAspect
        let shortOverWidth = aspect >= 1 ? 1 / aspect : 1, shortOverHeight = aspect >= 1 ? 1 : aspect
        var thinned: [NormalizedPoint] = []
        for point in points {
            if let last = thinned.last {
                let dx = (point.x - last.x) / shortOverWidth, dy = (point.y - last.y) / shortOverHeight
                guard (dx * dx + dy * dy).squareRoot() >= healRadius / 2 else { continue }
            }
            thinned.append(point)
        }
        if let last = points.last, thinned.last != last { thinned.append(last) }
        // At most 128 points, taken evenly along the whole stroke — never its first part only.
        if thinned.count > 128 {
            let step = Double(thinned.count - 1) / 127
            thinned = (0..<128).map { thinned[min(thinned.count - 1, Int((Double($0) * step).rounded()))] }
        }
        guard let spot = PhotoHealingSpot.stroke(through: thinned, mode: mode, radius: healRadius,
                                                  feather: healFeather, opacity: healOpacity, aspectRatio: aspect) else { return }
        apply { $0.healing.append(spot) }
        selectedSpotId = spot.id
        healNote = nil
    }

    func selectSpot(_ id: UUID?) {
        selectedSpotId = id
        healNote = nil
        guard let spot = selectedSpot else { return }
        // The sliders follow the spot, so they say what it is.
        healMode = spot.mode == .heal ? .heal : .clone
        healRadius = spot.radius
        healFeather = spot.feather
        healOpacity = spot.opacity
    }

    func selectRedEye(_ id: UUID?) {
        selectedRedEyeId = id
        guard let eye = selectedRedEye else { return }
        redEyePupil = eye.pupilSize
        redEyeDarken = eye.darken
    }

    /// One spot changed: a drag step, or one undo step.
    func updateSpot(_ id: UUID, inOneStep: Bool = false, _ body: @escaping (inout PhotoHealingSpot) -> Void) {
        let update: (inout PhotoEditRecipe) -> Void = { recipe in
            if let index = recipe.healing.firstIndex(where: { $0.id == id }) { body(&recipe.healing[index]) }
        }
        if inOneStep { apply(update) } else { change(update) }
    }

    func updateRedEye(_ id: UUID, inOneStep: Bool = false, _ body: @escaping (inout PhotoRedEyeSpot) -> Void) {
        let update: (inout PhotoEditRecipe) -> Void = { recipe in
            if let index = recipe.redEyes.firstIndex(where: { $0.id == id }) { body(&recipe.redEyes[index]) }
        }
        if inOneStep { apply(update) } else { change(update) }
    }

    func deleteSelectedSpot() {
        if healMode == .redEye {
            guard let id = selectedRedEyeId else { return }
            apply { $0.redEyes.removeAll { $0.id == id } }
            selectedRedEyeId = nil
        } else {
            guard let id = selectedSpotId else { return }
            apply { $0.healing.removeAll { $0.id == id } }
            hiddenSpotIds.remove(id)
            selectedSpotId = nil
        }
    }

    /// Clear All…, confirmed: the list on show (spots, or red eyes), one undo step.
    func clearAllSpots() {
        if healMode == .redEye {
            apply { $0.redEyes = [] }
            selectedRedEyeId = nil
        } else {
            apply { $0.healing = [] }
            selectedSpotId = nil
            hiddenSpotIds = []
        }
    }

    func toggleHidden(_ id: UUID) {
        if hiddenSpotIds.contains(id) { hiddenSpotIds.remove(id) } else { hiddenSpotIds.insert(id) }
    }

    /// New Source: the selected spot's source moves to the next best place
    /// around it, never back to one already offered. Scored off the main actor.
    func findNewSource() {
        guard let id = selectedSpotId, let spot = selectedSpot else { return }
        guard let image = cleanImage else { healNote = Self.stillLoadingNote; return }
        guard !isFindingSource else { return }
        var offered = offeredSources[id] ?? []
        if !offered.contains(spot.source) { offered.append(spot.source) }
        isFindingSource = true
        let box = ImageBox(image)
        let generation = self.generation
        let seen = offered
        Task { [weak self] in
            let next: NormalizedPoint? = await Task.detached(priority: .userInitiated) {
                guard let picture = HealingSourceFinder.Picture(box.image) else { return nil }
                let aspect = Double(picture.width) / Double(picture.height)
                let shortOverWidth = aspect >= 1 ? 1 / aspect : 1, shortOverHeight = aspect >= 1 ? 1 : aspect
                return HealingSourceFinder.candidates(for: spot, in: picture).first { point in
                    seen.allSatisfy { other in
                        let dx = (point.x - other.x) / shortOverWidth, dy = (point.y - other.y) / shortOverHeight
                        return (dx * dx + dy * dy).squareRoot() >= spot.radius
                    }
                }
            }.value
            guard let self else { return }
            self.isFindingSource = false
            guard generation == self.generation else { return }
            // The spot moved or changed while the places were scored: that answer was for the old one.
            guard let now = self.recipe.healing.first(where: { $0.id == id }),
                  now.center == spot.center, now.radius == spot.radius, now.stroke == spot.stroke else {
                self.healNote = String(localized: "The spot changed while looking — try New Source again.", comment: "Mac editor heal: a stale New Source")
                return
            }
            guard let next else {
                self.healNote = String(localized: "No other source found for this spot.", comment: "Mac editor heal: New Source found nothing")
                return
            }
            self.offeredSources[id] = seen + [next]
            self.updateSpot(id, inOneStep: true) { $0.source = next }
        }
    }

    /// Red Eye: a click makes an eye on the pupil Vision finds near it (or
    /// right there); Fix Red Eye does every red pupil at once.
    private static var stillLoadingNote: String {
        String(localized: "The photo is still loading — try again in a moment.", comment: "Mac editor heal: nothing to read yet")
    }

    /// Fix Red Eye or a click on a pupil is being worked out.
    private(set) var isLocatingEyes = false

    func addRedEye(at point: NormalizedPoint) {
        // A click on an eye already there picks it, rather than stacking a second.
        let aspect0 = healAspect
        let shortOverWidth0 = aspect0 >= 1 ? 1 / aspect0 : 1, shortOverHeight0 = aspect0 >= 1 ? 1 : aspect0
        if let existing = recipe.redEyes.first(where: { eye in
            let dx = (eye.center.x - point.x) / shortOverWidth0, dy = (eye.center.y - point.y) / shortOverHeight0
            return (dx * dx + dy * dy).squareRoot() <= eye.radius
        }) {
            selectRedEye(existing.id)
            return
        }
        guard !isLocatingEyes else { return }
        guard let image = cleanImage else { healNote = Self.stillLoadingNote; return }
        isLocatingEyes = true
        let box = ImageBox(image), aspect = healAspect, pupil = redEyePupil, darken = redEyeDarken, generation = self.generation
        Task { [weak self] in
            let pupils = await Task.detached(priority: .userInitiated) { RedEyeLocator.pupils(in: box.image) }.value
            guard let self else { return }
            self.isLocatingEyes = false
            guard generation == self.generation else { return }
            var eye = RedEyeLocator.spot(forTapAt: point, pupils: pupils, aspect: aspect)
            eye.pupilSize = pupil
            eye.darken = darken
            self.apply { $0.redEyes.append(eye) }
            self.selectedRedEyeId = eye.id
            self.healNote = nil
        }
    }

    func fixRedEyes() {
        guard !isLocatingEyes else { return }
        guard let image = cleanImage else { healNote = Self.stillLoadingNote; return }
        isLocatingEyes = true
        let box = ImageBox(image), aspect = healAspect, pupil = redEyePupil, darken = redEyeDarken, generation = self.generation
        Task { [weak self] in
            let red: [RedEyeLocator.Pupil] = await Task.detached(priority: .userInitiated) {
                guard let picture = HealingSourceFinder.Picture(box.image, side: 1024) else { return [] }
                return RedEyeLocator.redPupils(RedEyeLocator.pupils(in: box.image), in: picture)
            }.value
            guard let self else { return }
            self.isLocatingEyes = false
            guard generation == self.generation else { return }
            let shortOverWidth = aspect >= 1 ? 1 / aspect : 1, shortOverHeight = aspect >= 1 ? 1 : aspect
            let fresh = red.filter { found in
                !self.recipe.redEyes.contains { eye in
                    let dx = (eye.center.x - found.center.x) / shortOverWidth, dy = (eye.center.y - found.center.y) / shortOverHeight
                    return (dx * dx + dy * dy).squareRoot() <= eye.radius
                }
            }
            guard !fresh.isEmpty else {
                self.healNote = String(localized: "No red eyes found.", comment: "Mac editor heal: Fix Red Eye found nothing")
                return
            }
            var eyes: [PhotoRedEyeSpot] = []
            for found in fresh {
                var eye = RedEyeLocator.spot(forTapAt: found.center, pupils: [found], aspect: aspect)
                eye.pupilSize = pupil
                eye.darken = darken
                eyes.append(eye)
            }
            self.apply { $0.redEyes.append(contentsOf: eyes) }
            self.selectRedEye(eyes.last?.id)
            self.healNote = nil
        }
    }

    nonisolated private static let spotMapContext = CIContext(options: [.cacheIntermediates: false])

    /// The edge map for Visualize Spots, made off the main actor from the frame shown.
    private func updateSpotMap() {
        spotMapTask?.cancel()
        guard visualizesSpots, let image = cleanImage else { spotMap = nil; return }
        let box = ImageBox(image), threshold = spotThreshold, generation = self.generation
        spotMapTask = Task { [weak self] in
            // A Threshold drag asks every tick: only the last one is drawn.
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            let map = await Task.detached(priority: .userInitiated) { () -> ImageBox? in
                let map = SpotVisualizer.map(of: CIImage(cgImage: box.image), threshold: threshold)
                return Self.spotMapContext.createCGImage(map, from: map.extent).map(ImageBox.init)
            }.value
            guard let self, generation == self.generation, self.visualizesSpots, self.spotThreshold == threshold else { return }
            self.spotMap = map?.image
        }
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
        // Mask: the picked mask in red over the frame shown (never the clean one).
        let overlay = tool == .mask && showsMaskOverlay && !showsBefore && !hidesOverlayWhileAdjusting ? selectedMaskId : nil
        if let last = lastRequested, last.recipe == drawn, last.overlay == overlay, !(last.interactive && !interactive) { return }
        lastRequested = (drawn, interactive, overlay)
        wanted = (drawn, interactive, overlay)
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
                ? renderer.renderInteractivePreviewImages(source: source, recipe: next.recipe, maximumDimension: 1000, cachesBase: true,
                                                          showsMaskOverlay: next.overlay != nil, selectedMaskID: next.overlay)
                : renderer.renderPreviewImages(source: source, recipe: next.recipe, maximumDimension: 2400,
                                               showsMaskOverlay: next.overlay != nil, selectedMaskID: next.overlay))
            var histogram: PhotoHistogram?
            if let images, !next.interactive { histogram = await renderer.histogram(of: images.cleanImage) }
            guard let self else { return }
            self.isRendering = false
            if generation == self.generation {
                if let images {
                    self.renderFailed = false
                    self.preview = images.displayImage
                    self.cleanImage = images.cleanImage
                    if self.visualizesSpots, !next.interactive { self.updateSpotMap() }
                    if !next.interactive {
                        self.refreshMaskThumbnails()
                        if !next.recipe.masks.isEmpty {
                            Task { [weak self] in
                                let resolved = await renderer.resolvedAutomaticMaskComponentIDs()
                                let empty = await renderer.emptyAutomaticMaskComponentIDs()
                                guard let self, generation == self.generation else { return }
                                self.resolvedAutoAreas = resolved
                                self.emptyAutoAreas = empty
                            }
                        }
                    }
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

/// Reads pixels off the shown frame for the eyedropper and its loupe.
enum MacColorSampler {
    /// `side`×`side` pixels around `point` (normalized), row by row from the
    /// top, as 0…1 sRGB; fewer at the photo's edge.
    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB)

    static func pixels(in image: CGImage, at point: NormalizedPoint, side: Int)
        -> (pixels: [SIMD3<Double>], width: Int, pointer: (column: Int, row: Int))? {
        // The pixel under the pointer, kept inside the image (x = 1 is the last column).
        let px = min(image.width - 1, max(0, Int((point.x * Double(image.width)).rounded(.down))))
        let py = min(image.height - 1, max(0, Int((point.y * Double(image.height)).rounded(.down))))
        let rect = CGRect(x: px - side / 2, y: py - side / 2, width: side, height: side)
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !rect.isEmpty, let crop = image.cropping(to: rect) else { return nil }
        let width = crop.width, height = crop.height
        guard let space = srgb else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        // The context writes into the buffer only while the buffer is lent to it.
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let pixels = (0..<(width * height)).map { i in
            SIMD3(Double(bytes[i * 4]) / 255, Double(bytes[i * 4 + 1]) / 255, Double(bytes[i * 4 + 2]) / 255)
        }
        return (pixels, width, (px - Int(rect.minX), py - Int(rect.minY)))
    }

    /// The pixel under `point`.
    static func color(in image: CGImage, at point: NormalizedPoint) -> SIMD3<Double>? {
        pixels(in: image, at: point, side: 1)?.pixels.first
    }

    /// "#6E8FA8".
    static func hex(_ rgb: SIMD3<Double>) -> String {
        String(format: "#%02X%02X%02X", Int((rgb.x * 255).rounded()), Int((rgb.y * 255).rounded()), Int((rgb.z * 255).rounded()))
    }
}

/// A rendered frame handed across a detached task or queue: `CGImage` is an
/// immutable CF type, never changed after it is made — that is the guard.
private struct ImageBox: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}



private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
