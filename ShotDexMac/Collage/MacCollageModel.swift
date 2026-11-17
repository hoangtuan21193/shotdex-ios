import AppKit
import Photos
import ShotDexKit
import SwiftUI

/// The Mac collage (board `MAC_Collage`, FS-18.04 §4c, behaviour of FS-11):
/// the recipe the canvas and the export both read, Set Aside, undo and
/// export. A Mac copy of the iOS `CollageEditorModel` (Features is not in
/// the Mac target) without what the Mac has no use for — the drop import
/// into Photos, server runs, the RAW embedded-preview path. Pictures are
/// `CGImage`s, decoded off the main actor; the canvas is the compositor's
/// own render, so what is on screen is what Export writes.
@MainActor
@Observable
final class MacCollageModel: Identifiable {
    let id = UUID()
    private(set) var photos: [PhotoEditOrigin]
    /// File names by photo id, for the export's name and VoiceOver.
    let names: [String: String]
    var recipe: CollageRecipe
    /// Photos brought along but not in a cell (FS-11 §3).
    private(set) var unplaced: [String]
    var selectedCell: Int?
    /// The long edge the collage is exported at; the short edge follows the
    /// aspect ratio. The inspector's Size.
    var longEdge: Int = 2048
    /// The inspector, kept with the collage while it is open (⌥⌘I).
    var showsInspector = true
    /// Held while the Show Original button is down: the canvas shows the
    /// photos without border, spacing, corners or text.
    var isShowingOriginal = false {
        didSet { if isShowingOriginal != oldValue { scheduleRender() } }
    }

    /// Screen pictures by photo id, 1200 px; the export decodes its own.
    private(set) var images: [String: CGImage] = [:]
    /// The canvas: the compositor's render of the recipe at screen size.
    private(set) var canvas: CGImage?
    private(set) var isExporting = false
    /// Where the last export went: a file, or Photos.
    private(set) var saved: Saved?
    var errorMessage: String?
    /// Photos of the selection that are not here: videos, cloud copies,
    /// past 30 (said once in the panel, never dropped silently).
    var leftOutNote: String?
    /// "3 of 9" while an export reads its photos.
    private(set) var exportProgress: (done: Int, total: Int)?

    enum Saved: Equatable {
        case file(URL)
        case photos(String)
        /// Reopened from Collages, unchanged since its export.
        case restored
    }

    private let photoLibrary: PhotoLibraryService
    private let presetStore: CollagePresetStore
    /// Where an exported collage is recorded (Collages, FS-18.04 §1.5), and
    /// this collage's row: exporting a reopened collage again updates it.
    private let creationStore: CreationStore?
    let creationID: String
    /// Open the Export sheet as soon as the page shows (Collages › Export…).
    var exportsOnOpen = false
    /// Cells a reopened collage had photos in that are not here now: the
    /// record keeps those photos while their cells stay empty, so a photo
    /// that comes back is not lost from the collage.
    private var missingOnRestore: [Int: String] = [:]
    private var renderTask: Task<Void, Never>?
    private var renderGeneration = 0
    private var isRendering = false
    private var needsRender = false
    /// The page went: nothing more is loaded or drawn.
    private var isClosed = false
    /// Pictures asked for and not yet in, so a second appear does not ask again.
    private var loading: Set<String> = []

    // MARK: Undo

    private struct Snapshot: Equatable {
        var recipe: CollageRecipe
        var unplaced: [String]
        var longEdge: Int
    }
    private var current: Snapshot { Snapshot(recipe: recipe, unplaced: unplaced, longEdge: longEdge) }
    /// A run of colour-well changes is one undo step; any other edit ends it.
    private var isPickingColor = false
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    static let slotRange = CollageTemplateCatalog.supportedCounts

    /// `placed`: the first photos go into cells (up to the count the
    /// layouts take); the rest start in Set Aside.
    init(photos: [PhotoEditOrigin], names: [String: String], placed: Int,
         photoLibrary: PhotoLibraryService, presetStore: CollagePresetStore,
         creationStore: CreationStore? = nil, restoring: Creation? = nil) {
        self.photos = photos
        self.names = names
        self.photoLibrary = photoLibrary
        self.presetStore = presetStore
        self.creationStore = creationStore
        creationID = restoring?.id ?? UUID().uuidString
        if let restoring, var stored = restoring.collageRecipe {
            // A photo no longer here leaves its cell empty, never another photo in it.
            let here = Set(photos.map(\.id))
            var missing: [Int: String] = [:]
            for index in stored.cells.indices {
                if let id = stored.cells[index].assetID, !here.contains(id) {
                    missing[index] = id
                    stored.cells[index] = CollageCell(assetID: nil)
                }
            }
            recipe = stored
            unplaced = []
            missingOnRestore = missing
            if !missing.isEmpty {
                leftOutNote = MacInflect.string("^[\(missing.count) photo](inflect: true) of this collage isn’t here any more — deleted, or its original is gone. Its cell is empty.",
                                                comment: "Mac Collage: reopened with photos missing")
            }
            // Exported as it is: "Saved" until it changes.
            saved = restoring.exportedAt == nil ? nil : .restored
            return
        }
        let count = min(max(placed, Self.slotRange.lowerBound), min(Self.slotRange.upperBound, photos.count))
        let template = CollageTemplateCatalog.templates(for: count).first
        recipe = CollageRecipe(templateID: template?.id ?? "",
                               cells: photos.prefix(count).map { CollageCell(assetID: $0.id) })
        unplaced = photos.dropFirst(count).map(\.id)
    }

    var template: CollageTemplate? { CollageTemplateCatalog.template(id: recipe.templateID) }
    var availableTemplates: [CollageTemplate] { CollageTemplateCatalog.templates(for: slotCount) }
    var slotCount: Int { recipe.cells.count }
    var placedCount: Int { recipe.cells.reduce(0) { $0 + ($1.isEmpty ? 0 : 1) } }
    var hasEdits: Bool { !undoStack.isEmpty }

    var aspectLabel: String {
        recipe.aspectPreset?.displayName ?? String(localized: "Custom", comment: "Collage aspect ratio that matches no preset")
    }

    /// The export's pixel size: Size's long edge on the aspect ratio.
    var outputSize: CGSize {
        CollageGeometry.outputSize(ratio: recipe.aspectRatio, longEdge: CGFloat(longEdge))
    }

    func name(of id: String) -> String { names[id] ?? id }

    // MARK: Loading

    /// Screen pictures for every photo, decoded off the main actor; the
    /// canvas redraws as each one lands.
    func loadPictures() {
        for photo in photos where images[photo.id] == nil && !loading.contains(photo.id) { load(photo) }
    }

    private func load(_ photo: PhotoEditOrigin) {
        let id = photo.id
        loading.insert(id)
        switch photo {
        case .asset(let asset):
            _ = photoLibrary.requestDetailImage(for: asset, targetSize: CGSize(width: 1200, height: 1200),
                                                allowNetwork: true, progress: { _ in }) { [weak self] image, degraded in
                guard let self, !self.isClosed, let image else { return }
                if degraded && self.images[id] != nil { return }
                // NSImage → CGImage can decode: off the main actor, on a copy
                // (the library's cache keeps the original and others draw it).
                let box = MacCollageNSImageBox(image: image.copy() as? NSImage ?? image)
                Task { [weak self] in
                    let converted = await Task.detached(priority: .userInitiated) {
                        MacCollageImageBox(image: box.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
                    }.value
                    guard let self, !self.isClosed, let cgImage = converted.image else { return }
                    if degraded && self.images[id] != nil { return }
                    self.images[id] = cgImage
                    if !degraded { self.loading.remove(id) }
                    self.scheduleRender()
                }
            }
        case .fileCopy, .serverFile:
            guard let url = photo.localFileURL else { return }
            Task { [weak self] in
                let image = await Task.detached(priority: .userInitiated) {
                    MacCollageImageBox(image: PhotoOriginFile.image(at: url, maxPixelSize: 1200))
                }.value
                guard let self else { return }
                self.loading.remove(id)
                guard !self.isClosed, let cgImage = image.image else { return }
                self.images[id] = cgImage
                self.scheduleRender()
            }
        }
    }

    // MARK: Canvas

    /// The canvas size the last render was asked for, in pixels.
    private var canvasLongEdge: CGFloat = 1400

    /// Redraws the canvas at `longEdge` px from the screen pictures: the
    /// compositor runs off the main actor, a newer change drops an older
    /// render's result.
    func scheduleRender(longEdge: CGFloat? = nil) {
        guard !isClosed else { return }
        if let longEdge { canvasLongEdge = longEdge }
        renderGeneration += 1
        guard let template else { canvas = nil; return }
        // One render at a time: a change during it renders again once it ends,
        // with the newest recipe (a drag does not stack renders up).
        guard !isRendering else { needsRender = true; return }
        let generation = renderGeneration
        var recipe = recipe
        if isShowingOriginal {
            recipe.gutter = 0
            recipe.borderWidth = 0
            recipe.cornerRadius = 0
            recipe.overlays = []
            recipe.isPolaroid = false
        }
        var pictures: [Int: CGImage] = [:]
        for (index, cell) in recipe.cells.enumerated() {
            if let id = cell.assetID, let image = images[id] { pictures[index] = image }
        }
        let size = CollageGeometry.outputSize(ratio: recipe.aspectRatio, longEdge: canvasLongEdge)
        let box = MacCollagePictures(images: pictures)
        isRendering = true
        renderTask = Task { [weak self] in
            let rendered = await Task.detached(priority: .userInitiated) {
                MacCollageImageBox(image: CollageCompositor.render(recipe: recipe, template: template, images: box.images, pixelSize: size))
            }.value
            guard let self else { return }
            self.isRendering = false
            if !Task.isCancelled, generation == self.renderGeneration { self.canvas = rendered.image }
            if self.needsRender, !Task.isCancelled {
                self.needsRender = false
                self.scheduleRender()
            }
        }
    }

    /// Cell frames in canvas pixels (the render's own space).
    func cellFrames(in size: CGSize) -> [CGRect] {
        guard let template else { return [] }
        let gutter = isShowingOriginal ? 0 : CollageGeometry.gutterPixels(recipe.gutter, canvasSize: size)
        return CollageGeometry.cellFrames(template: template, canvasSize: size, gutter: gutter, overrides: recipe.dividerWeights)
    }

    func dividers() -> [CollageDivider] {
        template?.dividers(overrides: recipe.dividerWeights) ?? []
    }

    func imageSize(ofCell index: Int) -> CGSize? {
        guard recipe.cells.indices.contains(index), let id = recipe.cells[index].assetID, let image = images[id] else { return nil }
        return CGSize(width: image.width, height: image.height)
    }

    // MARK: Undo

    private func checkpoint() {
        undoStack.append(current)
        redoStack.removeAll()
        saved = nil
        isPickingColor = false
    }

    /// One undoable step for a drag (a seam, a pan, a slider): call at its
    /// start, and `endEdit` at its end — a drag that changed nothing leaves
    /// no step and keeps "Saved".
    func beginEdit() {
        savedBeforeEdit = saved
        checkpoint()
    }

    func endEdit() {
        guard let last = undoStack.last, last == current else { return }
        undoStack.removeLast()
        saved = savedBeforeEdit
    }
    private var savedBeforeEdit: Saved?

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(current)
        apply(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(current)
        apply(next)
    }

    private func apply(_ snapshot: Snapshot) {
        recipe = snapshot.recipe
        unplaced = snapshot.unplaced
        longEdge = snapshot.longEdge
        isPickingColor = false
        if let index = selectedCell, !recipe.cells.indices.contains(index) { selectedCell = nil }
        saved = nil
        scheduleRender()
    }

    /// Every recipe change goes through here: checkpoint (unless a drag
    /// already took one), change, redraw.
    private func edit(checkpointing: Bool = true, _ change: (inout CollageRecipe) -> Void) {
        if checkpointing { checkpoint() } else { saved = nil }
        change(&recipe)
        scheduleRender()
    }

    // MARK: Layout

    func selectTemplate(_ id: String) {
        guard recipe.templateID != id else { return }
        edit {
            $0.templateID = id
            $0.dividerWeights = [:]
        }
    }

    var canAddSlot: Bool { slotCount < Self.slotRange.upperBound }
    var canRemoveSlot: Bool { slotCount > Self.slotRange.lowerBound }

    /// One more cell: filled from Set Aside when it has a photo, else empty.
    func addSlot() {
        guard canAddSlot else { return }
        checkpoint()
        if let id = unplaced.first {
            unplaced.removeFirst()
            recipe.cells.append(CollageCell(assetID: id))
        } else {
            recipe.cells.append(CollageCell(assetID: nil))
        }
        retargetTemplate()
        scheduleRender()
    }

    /// One cell fewer: its photo goes to Set Aside, never away (FS-11 §4).
    func removeSlot() {
        guard canRemoveSlot else { return }
        checkpoint()
        let removed = recipe.cells.removeLast()
        if let id = removed.assetID { unplaced.insert(id, at: 0) }
        if let index = selectedCell, index >= recipe.cells.count { selectedCell = nil }
        retargetTemplate()
        scheduleRender()
    }

    private func retargetTemplate() {
        if template?.cellCount != slotCount {
            recipe.templateID = CollageTemplateCatalog.templates(for: slotCount).first?.id ?? ""
            recipe.dividerWeights = [:]
        }
    }

    func setDivider(_ nodeID: String, weights: [Double]) {
        edit(checkpointing: false) { $0.dividerWeights[nodeID] = weights }
    }

    func resetDivider(_ nodeID: String) {
        guard recipe.dividerWeights[nodeID] != nil else { return }
        edit { $0.dividerWeights[nodeID] = nil }
    }

    // MARK: Cells ↔ Set Aside

    /// A Set Aside photo dropped on a cell: whatever the cell held goes to Set Aside.
    func fill(_ index: Int, with id: String) {
        // Only from Set Aside: a stale drag must not put one photo in two cells.
        guard recipe.cells.indices.contains(index), unplaced.contains(id) else { return }
        checkpoint()
        if let displaced = recipe.cells[index].assetID, displaced != id { unplaced.insert(displaced, at: 0) }
        unplaced.removeAll { $0 == id }
        recipe.cells[index] = CollageCell(assetID: id)
        scheduleRender()
    }

    func setAside(_ index: Int) {
        guard recipe.cells.indices.contains(index), let id = recipe.cells[index].assetID else { return }
        checkpoint()
        recipe.cells[index] = CollageCell(assetID: nil)
        unplaced.insert(id, at: 0)
        scheduleRender()
    }

    func swap(_ first: Int, _ second: Int) {
        guard first != second, recipe.cells.indices.contains(first), recipe.cells.indices.contains(second) else { return }
        edit { $0.cells.swapAt(first, second) }
        selectedCell = second
    }

    /// A pan or zoom inside a cell, clamped so the photo always covers it.
    func setContent(cell index: Int, scale: Double, offset: NormalizedPoint, cellFrame: CGRect) {
        guard let imageSize = imageSize(ofCell: index) else { return }
        let clamped = CollageGeometry.clampedContent(imageSize: imageSize, cellFrame: cellFrame, scale: scale, offset: offset)
        edit(checkpointing: false) {
            $0.cells[index].contentScale = clamped.scale
            $0.cells[index].contentOffset = clamped.offset
        }
    }

    func resetContent(cell index: Int) {
        guard recipe.cells.indices.contains(index) else { return }
        edit {
            $0.cells[index].contentScale = 1
            $0.cells[index].contentOffset = NormalizedPoint(x: 0, y: 0)
        }
    }

    // MARK: Inspector

    func selectAspect(_ aspect: CollageAspect) {
        guard recipe.aspectPreset != aspect else { return }
        edit {
            $0.aspectPreset = aspect
            $0.aspectRatio = aspect.ratio
        }
    }

    /// Size W × H typed in: the long edge, and the ratio when it no longer
    /// matches (a custom ratio, FS-11 §5).
    func setSize(width: Int, height: Int) {
        let width = min(max(width, 200), 8192), height = min(max(height, 200), 8192)
        let ratio = min(max(Double(width) / Double(height), CollageRecipe.aspectRatioRange.lowerBound),
                        CollageRecipe.aspectRatioRange.upperBound)
        let ratioChanges = abs(ratio - recipe.aspectRatio) > 0.001
        guard ratioChanges || max(width, height) != longEdge else { return }
        checkpoint()
        longEdge = max(width, height)
        if ratioChanges {
            recipe.aspectRatio = ratio
            recipe.aspectPreset = CollageAspect.matching(ratio: ratio)
        }
        scheduleRender()
    }

    func setBorder(_ value: Double) {
        edit(checkpointing: false) { $0.borderWidth = min(max(value, CollageRecipe.borderWidthRange.lowerBound), CollageRecipe.borderWidthRange.upperBound) }
    }

    func setSpacing(_ value: Double) {
        edit(checkpointing: false) { $0.gutter = min(max(value, CollageRecipe.gutterRange.lowerBound), CollageRecipe.gutterRange.upperBound) }
    }

    func setCorners(_ value: Double) {
        edit(checkpointing: false) { $0.cornerRadius = min(max(value, CollageRecipe.cornerRadiusRange.lowerBound), CollageRecipe.cornerRadiusRange.upperBound) }
    }

    /// The title's ink follows the background it sits on.
    private static func retint(_ recipe: inout CollageRecipe) {
        let ink = titleInk(for: recipe)
        for index in recipe.overlays.indices where recipe.overlays[index].kind == .text { recipe.overlays[index].fill = ink }
    }

    func setFill(_ mode: CollageBackgroundMode) {
        if recipe.backgroundMode == mode {
            // Already blurred: "Use as Blurred Background" still picks the source.
            guard mode == .blurredPhoto, let selectedCell, recipe.backgroundSourceIndex != selectedCell else { return }
            edit { $0.backgroundSourceIndex = selectedCell }
            return
        }
        let source = selectedCell
        edit {
            $0.backgroundMode = mode
            if mode == .blurredPhoto {
                $0.backgroundSourceIndex = source ?? $0.cells.firstIndex { !$0.isEmpty }
            }
            Self.retint(&$0)
        }
    }

    func setBackground(_ color: OverlayColor) {
        guard color != recipe.background else { return }
        let opens = !isPickingColor
        edit(checkpointing: opens) {
            $0.background = color
            $0.borderColor = color
            Self.retint(&$0)
        }
        isPickingColor = true
    }

    func setBlur(_ value: Double) {
        edit(checkpointing: false) { $0.backgroundBlur = min(max(value, CollageRecipe.backgroundBlurRange.lowerBound), CollageRecipe.backgroundBlurRange.upperBound) }
    }

    func setDim(_ value: Double) {
        edit(checkpointing: false) { $0.backgroundDarken = min(max(value, CollageRecipe.backgroundDarkenRange.lowerBound), CollageRecipe.backgroundDarkenRange.upperBound) }
    }

    func setPolaroid(_ on: Bool) {
        guard recipe.isPolaroid != on else { return }
        edit { $0.isPolaroid = on }
    }

    func setCaption(_ index: Int, _ text: String) {
        guard recipe.cells.indices.contains(index), recipe.cells[index].caption != text else { return }
        edit { $0.cells[index].caption = text }
    }

    /// The title: one text layer across the top. Empty removes it.
    var title: String { recipe.overlays.first { $0.kind == .text }?.text ?? "" }

    func setTitle(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != title else { return }
        edit {
            if let index = $0.overlays.firstIndex(where: { $0.kind == .text }) {
                if trimmed.isEmpty { $0.overlays.remove(at: index) } else { $0.overlays[index].text = trimmed }
            } else if !trimmed.isEmpty {
                var overlay = PhotoOverlay.text()
                overlay.text = trimmed
                overlay.fill = Self.titleInk(for: $0)
                $0.overlays.append(overlay)
            }
        }
    }

    /// Black on a light flat background, white on a dark one or on a
    /// blurred photo (dimmed).
    nonisolated static func titleInk(for recipe: CollageRecipe) -> OverlayColor {
        guard recipe.backgroundMode == .color else { return .white }
        let c = recipe.background
        return 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue > 0.6 ? .black : .white
    }

    // MARK: Presets (FS-11 §8)

    var presets: [CollagePreset] { presetStore.presets }

    /// The preset this collage matches now, for the popup's title.
    var currentPreset: CollagePreset? {
        presets.first { preset in
            preset.templateID == recipe.templateID && preset.aspectRatio == recipe.aspectRatio
                && preset.gutter == recipe.gutter && preset.cornerRadius == recipe.cornerRadius
                && preset.borderWidth == recipe.borderWidth && preset.background == recipe.background
                && preset.backgroundMode == recipe.backgroundMode && preset.isPolaroid == recipe.isPolaroid
        }
    }

    func savePreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        presetStore.save(CollagePreset(name: trimmed, recipe: recipe))
    }

    func deletePreset(_ id: UUID) { presetStore.delete(id) }

    /// The frame and style of a preset; its layout only when it has as many
    /// cells as this collage, so photos never fall out (FS-11 §8).
    func applyPreset(_ preset: CollagePreset) {
        // Read before `edit`: the closure holds `recipe` inout.
        let count = slotCount
        edit {
            $0.aspectRatio = preset.aspectRatio
            $0.aspectPreset = preset.aspectPreset
            $0.gutter = preset.gutter
            $0.cornerRadius = preset.cornerRadius
            $0.borderWidth = preset.borderWidth
            $0.borderColor = preset.borderColor
            $0.background = preset.background
            $0.backgroundMode = preset.backgroundMode
            $0.backgroundBlur = preset.backgroundBlur
            $0.backgroundDarken = preset.backgroundDarken
            $0.isPolaroid = preset.isPolaroid
            if let template = CollageTemplateCatalog.template(id: preset.templateID), template.cellCount == count {
                $0.templateID = preset.templateID
                $0.dividerWeights = preset.dividerWeights
            }
        }
    }

    // MARK: Export

    /// "~3.3 MB" for the inspector's Export Size.
    func estimatedBytes(_ options: CollageExportOptions) -> Int {
        CollageImageEncoder.estimatedBytes(pixelSize: outputSize, format: options.format, quality: options.quality)
    }

    /// Whether the collage goes into Photos: its first photo is a Photos
    /// library picture (as on iPhone). Otherwise it is a file beside the
    /// first photo, or in a chosen folder.
    var firstPlaced: PhotoEditOrigin? {
        recipe.cells.lazy.compactMap(\.assetID).compactMap { id in self.photos.first { $0.id == id } }.first
    }

    var savesToPhotos: Bool {
        if case .asset = firstPlaced { return true }
        return false
    }

    /// "DSC04111 (Collage).jpg".
    func fileName(_ format: CollageExportFormat) -> String {
        let first = firstPlaced.map { name(of: $0.id) } ?? "Collage"
        let stem = (first as NSString).deletingPathExtension
        return String(localized: "\(stem) (Collage)", comment: "Mac Collage: the exported file's name, after the first photo")
            + "." + format.fileExtension
    }

    /// Renders at the output size and writes it: each cell decoded at its
    /// placed size (× zoom, with headroom), one at a time, so nine large
    /// originals never sit in memory together; drawing and encoding off the
    /// main actor. `folder` nil: beside the first photo (or Photos).
    @discardableResult
    func export(_ options: CollageExportOptions, folder: MacResizeFolder?) async -> Bool {
        guard !isExporting, let template else { return false }
        isExporting = true
        errorMessage = nil
        saved = nil
        defer { isExporting = false }
        let recipe = recipe
        guard let data = await renderData(options, recipe: recipe, template: template) else { return false }
        guard !Task.isCancelled else { return false }
        let name = fileName(options.format)
        if folder == nil, savesToPhotos {
            do {
                let assetId = try await photoLibrary.saveImage(data, filename: name)
                photoLibrary.publishAppCreatedAsset()
                saved = .photos(name)
                await record(assetId: assetId, recipe: recipe)
                return true
            } catch {
                errorMessage = String(localized: "Photos didn’t take the collage. Choose a folder and export again.", comment: "Mac Collage: Photos save failed")
                return false
            }
        }
        let beside = firstPlaced?.localFileURL?.deletingLastPathComponent()
        do {
            let url = try await Task.detached(priority: .userInitiated) { () -> URL in
                // A bookmark resolves off the main actor: a sleeping drive must not hold the window.
                guard let target = folder.map({ $0.resolved() }) ?? beside else { throw CocoaError(.fileNoSuchFile) }
                let isAccessing = target.startAccessingSecurityScopedResource()
                defer { if isAccessing { target.stopAccessingSecurityScopedResource() } }
                let existing = Set(((try? FileManager.default.contentsOfDirectory(atPath: target.path)) ?? []).map { $0.lowercased() })
                var final = name
                if existing.contains(name.lowercased()) {
                    let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
                    let number = FileExportPlan.firstFreeNumber { existing.contains("\(base) (\($0)).\(ext)".lowercased()) }
                    final = "\(base) (\(number)).\(ext)"
                }
                let url = target.appendingPathComponent(final)
                try data.write(to: url, options: .withoutOverwriting)
                return url
            }.value
            saved = .file(url)
            await record(assetId: nil, recipe: recipe)
            return true
        } catch {
            errorMessage = String(localized: "ShotDex couldn’t write the collage there. Choose another folder and export again.",
                                  comment: "Mac Collage: writing the file failed")
            return false
        }
    }

    /// Files the exported collage under Collages with its recipe, so it can
    /// be reopened. A failure never fails the export: the picture is written.
    private func record(assetId: String?, recipe: CollageRecipe) async {
        guard let creationStore else { return }
        var kept = recipe
        // A missing photo's cell left empty keeps its photo in the record.
        for (index, id) in missingOnRestore where kept.cells.indices.contains(index) && kept.cells[index].isEmpty {
            kept.cells[index] = CollageCell(assetID: id)
        }
        guard let creation = try? Creation.collage(recipe: kept, assetId: assetId, id: creationID) else { return }
        let id = creationID
        let wrote = await Task.detached(priority: .utility) { () -> Bool in
            // The newest export is the collage's picture: a file export leaves
            // no Photos picture to show (Show in Library shows its photos).
            _ = id
            return (try? creationStore.upsert(creation)) != nil
        }.value
        if !wrote {
            leftOutNote = String(localized: "Exported, but it couldn’t be added to Collages. Export again to try once more.",
                                 comment: "Mac Collage: the record of the export failed")
        }
    }

    /// The first photo's camera details without what describes its own
    /// pixels (orientation, size, colour model).
    nonisolated static func cameraDetails(from properties: [CFString: Any]) -> [CFString: Any] {
        var kept = properties
        for key in [kCGImagePropertyOrientation, kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight,
                    kCGImagePropertyDepth, kCGImagePropertyColorModel, kCGImagePropertyProfileName] {
            kept[key] = nil
        }
        if var tiff = kept[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = nil
            kept[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = kept[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = nil
            exif[kCGImagePropertyExifPixelYDimension] = nil
            kept[kCGImagePropertyExifDictionary] = exif
        }
        return kept
    }

    /// The collage at the output size, encoded: each cell decoded at its
    /// placed size (× zoom, with headroom), one at a time, so nine large
    /// originals never sit in memory together; drawing and encoding off the
    /// main actor. Nil (with `errorMessage`) on a cell it could not read.
    private func renderData(_ options: CollageExportOptions, recipe: CollageRecipe, template: CollageTemplate) async -> Data? {
        let pixelSize = outputSize
        let frames = CollageGeometry.cellFrames(template: template, canvasSize: pixelSize,
                                                gutter: CollageGeometry.gutterPixels(recipe.gutter, canvasSize: pixelSize),
                                                overrides: recipe.dividerWeights)
        let byId = Dictionary(photos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var pictures: [Int: CGImage] = [:]
        var unread: [String] = []
        let total = recipe.cells.filter { !$0.isEmpty }.count
        exportProgress = (0, total)
        defer { exportProgress = nil }
        for (index, cell) in recipe.cells.enumerated() {
            // Cancel in the sheet: nothing is written.
            guard !Task.isCancelled else { return nil }
            guard let id = cell.assetID, let photo = byId[id], frames.indices.contains(index) else { continue }
            exportProgress = (pictures.count + unread.count, total)
            let side = Int((max(frames[index].width, frames[index].height) * CGFloat(cell.contentScale) * 1.5).rounded(.up))
            if let image = await fullImage(photo, side: side) { pictures[index] = image } else { unread.append(name(of: id)) }
        }
        // A cell that could not be read would come out blank: nothing is written.
        guard unread.isEmpty, !pictures.isEmpty else {
            errorMessage = String(localized: "ShotDex couldn’t read \(unread.joined(separator: ", ")). Nothing was exported.",
                                  comment: "Mac Collage: export could not read some photos")
            return nil
        }
        var metadata: [CFString: Any]?
        if options.keepFirstPhotoEXIF, let first = firstPlaced {
            switch first {
            case .asset(let asset): metadata = await photoLibrary.imageProperties(for: asset)
            case .fileCopy, .serverFile:
                if let url = first.localFileURL {
                    metadata = await Task.detached { MacCollageMetadataBox(properties: PhotoOriginFile.properties(at: url)) }.value.properties
                }
            }
        }
        let box = MacCollagePictures(images: pictures)
        // The pixels are already upright and the size is the collage's: the
        // first photo's orientation and dimensions must not come along.
        metadata = metadata.map(Self.cameraDetails(from:))
        let meta = MacCollageMetadataBox(properties: metadata)
        guard let data = await Task.detached(priority: .userInitiated, operation: { () -> Data? in
            guard let image = CollageCompositor.render(recipe: recipe, template: template, images: box.images, pixelSize: pixelSize) else { return nil }
            return CollageImageEncoder.encode(image, format: options.format, quality: options.quality, metadata: meta.properties)
        }).value else {
            errorMessage = String(localized: "ShotDex couldn’t draw the collage. Try a smaller Size.", comment: "Mac Collage: render failed")
            return nil
        }
        return data
    }

    /// Share… from Collages: the collage as a JPEG in a temporary folder.
    func renderTemporaryFile() async -> URL? {
        guard let template else { return nil }
        guard let data = await renderData(CollageExportOptions(), recipe: recipe, template: template) else { return nil }
        let name = fileName(.jpeg)
        return await Task.detached(priority: .userInitiated) { () -> URL? in
            // One folder, emptied each time: shares never pile up in temp.
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ShotDexShare", isDirectory: true)
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(name)
            return (try? data.write(to: url)) == nil ? nil : url
        }.value
    }

    /// One photo at `side` px: a file decoded off the main actor, a Photos
    /// picture's final rendition (never a degraded one).
    private func fullImage(_ photo: PhotoEditOrigin, side: Int) async -> CGImage? {
        switch photo {
        case .asset(let asset):
            let box: MacCollageNSImageBox? = await withCheckedContinuation { continuation in
                var resumed = false
                _ = photoLibrary.requestDetailImage(for: asset, targetSize: CGSize(width: side, height: side),
                                                    allowNetwork: true, progress: { _ in }) { image, degraded in
                    guard !resumed, !degraded else { return }
                    resumed = true
                    // A copy: the library's cache keeps the original.
                    continuation.resume(returning: image.map { MacCollageNSImageBox(image: $0.copy() as? NSImage ?? $0) })
                }
            }
            guard let box else { return nil }
            // NSImage → CGImage decodes: off the main actor.
            return await Task.detached(priority: .userInitiated) {
                MacCollageImageBox(image: box.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            }.value.image
        case .fileCopy, .serverFile:
            guard let url = photo.localFileURL else { return nil }
            return await Task.detached(priority: .userInitiated) {
                MacCollageImageBox(image: PhotoOriginFile.image(at: url, maxPixelSize: side))
            }.value.image
        }
    }

    /// Leaving: a render under way is dropped.
    func close() {
        isClosed = true
        renderTask?.cancel()
        renderGeneration += 1
    }
}

/// CGImages carried into and out of detached work; immutable once made.
struct MacCollageImageBox: @unchecked Sendable {
    let image: CGImage?
}

/// A Photos rendition handed to the detached conversion; not touched after.
struct MacCollageNSImageBox: @unchecked Sendable {
    let image: NSImage
}

struct MacCollagePictures: @unchecked Sendable {
    let images: [Int: CGImage]
}

/// ImageIO properties carried across a detached task; read-only.
struct MacCollageMetadataBox: @unchecked Sendable {
    let properties: [CFString: Any]?
}
