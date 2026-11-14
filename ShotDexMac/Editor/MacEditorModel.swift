import CoreGraphics
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
        if MacDemoLibrary.isOn, let url = await Task.detached { MacDemoLibrary.pictureFiles(for: [id]).first }.value { return url }
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
        isDragging = true
        // An edit is seen as it is made: Before gives way.
        showsBefore = false
    }

    /// While dragging: small fast frames. The drag's undo step is taken on
    /// its first real change, so a click that moves nothing leaves none.
    func set(_ kind: PhotoAdjustmentKind, to value: Double) {
        guard recipe.adjustments[kind] != value else { return }
        if let start = dragStart {
            history.record(start)
            dragStart = nil
        }
        recipe.adjustments[kind] = value
        render(interactive: isDragging)
    }

    /// The slider let go: the full preview, then the save.
    func endChange() {
        let moved = dragStart == nil
        dragStart = nil
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
        guard let previous = history.undo(current: recipe) else { return }
        recipe = previous
        render(interactive: false)
        scheduleSave()
    }

    func redo() {
        guard let next = history.redo(current: recipe) else { return }
        recipe = next
        render(interactive: false)
        scheduleSave()
    }

    /// Revert to Original…: the photo as it came, kept undoable.
    func revert() {
        apply { $0 = .identity }
    }

    // MARK: Rendering

    /// The canvas's frame: small while a slider moves, full 90 ms after the
    /// last change. Latest wins: a request made while one renders replaces
    /// any other waiting, and runs when that one is done.
    private func render(interactive: Bool) {
        guard source != nil else { return }
        wanted = (showsBefore ? PhotoEditRecipe.identity : recipe, interactive)
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

/// A rendered frame handed across a detached task (`CGImage` is immutable).
private struct ImageBox: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

