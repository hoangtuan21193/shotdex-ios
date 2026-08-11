import Photos
import SwiftUI

/// State holder for the collage editor. Owns the recipe (the single source of
/// truth the canvas and the exporter both read), the unplaced tray, the preview
/// images, the undo/redo history and the export flow. Presentation-only state
/// (which cell is selected, which panel group is open) lives here too — the
/// screen stays a thin layout shell.
@MainActor @Observable
final class CollageEditorModel {
    enum PanelGroup: String, CaseIterable, Identifiable {
        case layout, style, text
        var id: String { rawValue }
        var title: String {
            switch self {
            case .layout: String(localized: "Layout")
            case .style: String(localized: "Style")
            case .text: String(localized: "Text")
            }
        }
        var systemImage: String {
            switch self {
            case .layout: "rectangle.split.2x2"
            case .style: "slider.horizontal.3"
            case .text: "textformat"
            }
        }
    }

    /// The photo pool brought over from the library — the union of everything
    /// ever placed or set aside. Slots reference these by id. It grows as the
    /// picker pulls in photos beyond the originals (`ingest`), so a slot can hold
    /// any library asset, and its preview/export can always find the pixels.
    private(set) var assets: [PHAsset]
    private let photoLibrary: PhotoLibraryService
    private let indexPipeline: IndexPipeline
    private let overlayFontRecents: OverlayFontRecentsStore
    private let presetStore: CollagePresetStore

    var recipe: CollageRecipe
    /// Asset ids carried over from the library but not currently in a slot (§3).
    private(set) var unplaced: [String]
    var selectedCellIndex: Int?
    var selectedOverlayID: UUID?
    var panelGroup: PanelGroup = .layout
    /// Held while the "view original" band button is pressed: the canvas hides
    /// overlays and borders so the bare photos can be judged.
    var isShowingOriginal = false

    /// The cell currently lifted by a hold-drag (§7). Non-nil the instant the
    /// hold completes — before any movement — so the tray can expand and the HUD
    /// appear immediately. The canvas owns the floating snapshot; this flag is
    /// what the tray and HUD read.
    var liftedCellIndex: Int?
    var isLiftingCell: Bool { liftedCellIndex != nil }

    /// A one-shot undo prompt for a destructive-looking move (a photo set aside).
    /// The screen shows a toast with an Undo button while this is set.
    var undoToastMessage: String?
    /// Bumped whenever the tray should flash its border once (a photo just
    /// arrived). The tray view watches this and pulses.
    private(set) var trayFlashToken = 0

    /// Preview images keyed by asset id — swap and replace move cells around,
    /// the pixels follow the asset, not the slot.
    private(set) var imagesByAsset: [String: UIImage] = [:]
    private(set) var isExporting = false
    private(set) var didSave = false
    /// The saved collage's asset id, so the screen can open its detail (§12).
    private(set) var didSaveAssetID: String?
    var errorMessage: String?

    /// The last font/fill the user chose, seeded into the next new text layer.
    var lastFont = OverlayFontChoice.system
    var lastFill = OverlayColor.white

    // MARK: Undo / redo

    /// One point-in-time the whole editable state can be restored to. Only the
    /// recipe and the tray change under edits, so those two are the snapshot.
    private struct Snapshot: Equatable {
        var recipe: CollageRecipe
        var unplaced: [String]
    }
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasEdits: Bool { !undoStack.isEmpty }

    /// Photo counts the collage supports (also the counter's clamp).
    static let slotRange = CollageTemplateCatalog.supportedCounts

    init(
        assets: [PHAsset],
        photoLibrary: PhotoLibraryService,
        indexPipeline: IndexPipeline,
        overlayFontRecents: OverlayFontRecentsStore,
        presetStore: CollagePresetStore
    ) {
        self.assets = assets
        self.photoLibrary = photoLibrary
        self.indexPipeline = indexPipeline
        self.overlayFontRecents = overlayFontRecents
        self.presetStore = presetStore
        let template = CollageTemplateCatalog.templates(for: assets.count).first
        self.recipe = CollageRecipe(
            templateID: template?.id ?? "",
            cells: assets.map { CollageCell(assetID: $0.localIdentifier) }
        )
        self.unplaced = []
    }

    var template: CollageTemplate? {
        CollageTemplateCatalog.template(id: recipe.templateID)
    }

    var availableTemplates: [CollageTemplate] {
        CollageTemplateCatalog.templates(for: slotCount)
    }

    var slotCount: Int { recipe.cells.count }
    var placedCount: Int { recipe.cells.reduce(0) { $0 + ($1.isEmpty ? 0 : 1) } }

    /// Band status readout: `2 of 3 · 4:5`.
    var statusText: String {
        "\(placedCount) of \(slotCount) · \(aspectLabel)"
    }

    var aspectLabel: String {
        recipe.aspectPreset?.displayName ?? String(localized: "Custom")
    }

    var selectedOverlay: PhotoOverlay? {
        guard let selectedOverlayID else { return nil }
        return recipe.overlays.first { $0.id == selectedOverlayID }
    }

    func image(for cellIndex: Int) -> UIImage? {
        guard recipe.cells.indices.contains(cellIndex),
              let id = recipe.cells[cellIndex].assetID
        else { return nil }
        return imagesByAsset[id]
    }

    func image(forAsset id: String) -> UIImage? { imagesByAsset[id] }

    func asset(id: String) -> PHAsset? {
        assets.first { $0.localIdentifier == id }
    }

    // MARK: - Loading

    /// Screen-quality previews for every selected asset. One request per asset,
    /// opportunistic — a degraded rendition fills the cell immediately and the
    /// final replaces it in place. 1200pt is enough headroom for a zoomed cell
    /// on the interactive canvas; the export requests its own pixels.
    func loadPreviews() { loadPreviews(for: assets) }

    private func loadPreviews(for subset: [PHAsset]) {
        let targetSize = CGSize(width: 1200, height: 1200)
        for asset in subset {
            let id = asset.localIdentifier
            _ = photoLibrary.requestDetailImage(
                for: asset,
                targetSize: targetSize,
                allowNetwork: true,
                progress: { _ in }
            ) { [weak self] image, degraded in
                guard let self, let image else { return }
                // Never let a late degraded callback overwrite the final.
                if degraded && self.imagesByAsset[id] != nil { return }
                self.imagesByAsset[id] = image
            }
        }
    }

    /// Pulls any ids not yet in the pool from the library and starts their
    /// previews, so a photo picked from Recents/Favorites/Screenshots (§6) has
    /// pixels for both the canvas and the export.
    private func ingest(_ ids: [String]) {
        let known = Set(assets.map(\.localIdentifier))
        let newIDs = ids.filter { !known.contains($0) }
        guard !newIDs.isEmpty else { return }
        let fetched = PhotoLibraryService.fetchAssets(ids: newIDs)
        assets.append(contentsOf: fetched)
        loadPreviews(for: fetched)
    }

    // MARK: - Undo history

    private func snapshot() -> Snapshot { Snapshot(recipe: recipe, unplaced: unplaced) }

    /// Records the current state so the next mutation can be undone. Call before
    /// a discrete edit; continuous gestures commit once at the end.
    private func checkpoint() {
        undoStack.append(snapshot())
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot())
        apply(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot())
        apply(next)
    }

    private func apply(_ snapshot: Snapshot) {
        recipe = snapshot.recipe
        unplaced = snapshot.unplaced
        if let index = selectedCellIndex, !recipe.cells.indices.contains(index) {
            selectedCellIndex = nil
        }
        if let id = selectedOverlayID, !recipe.overlays.contains(where: { $0.id == id }) {
            selectedOverlayID = nil
        }
    }

    // MARK: - Layout / aspect

    func selectTemplate(_ id: String) {
        guard recipe.templateID != id else { return }
        checkpoint()
        recipe.templateID = id
        // A new template is a different tree; its seams don't carry over (§9).
        recipe.dividerWeights = [:]
    }

    // MARK: - Divider drag (§9)

    /// Opens one undoable step for a divider drag. The drag itself streams weights
    /// through `setDividerWeights` without further checkpoints.
    func beginDividerEdit() { checkpoint() }

    func setDividerWeights(_ nodeID: String, _ weights: [Double]) {
        recipe.dividerWeights[nodeID] = weights
    }

    /// Double-tap: drop a seam's override so it returns to the template's own
    /// proportion.
    func resetDivider(_ nodeID: String) {
        guard recipe.dividerWeights[nodeID] != nil else { return }
        checkpoint()
        recipe.dividerWeights[nodeID] = nil
    }

    // MARK: - Presets (§8)

    var presets: [CollagePreset] { presetStore.presets }

    func saveCurrentAsPreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        presetStore.save(CollagePreset(name: trimmed, recipe: recipe))
    }

    func renamePreset(_ id: UUID, to name: String) { presetStore.rename(id, to: name) }
    func deletePreset(_ id: UUID) { presetStore.delete(id) }

    /// Stamps a preset's frame + style onto the current photos (§8). Text is
    /// untouched; the template only applies when its cell count matches the
    /// slots, so the photos never desync from the layout.
    func applyPreset(_ preset: CollagePreset) {
        checkpoint()
        recipe.aspectRatio = preset.aspectRatio
        recipe.aspectPreset = preset.aspectPreset
        recipe.gutter = preset.gutter
        recipe.cornerRadius = preset.cornerRadius
        recipe.borderWidth = preset.borderWidth
        recipe.borderColor = preset.borderColor
        recipe.background = preset.background
        if let template = CollageTemplateCatalog.template(id: preset.templateID),
           template.cellCount == slotCount {
            recipe.templateID = preset.templateID
            recipe.dividerWeights = preset.dividerWeights
        }
    }

    func selectAspect(_ aspect: CollageAspect) {
        guard recipe.aspectPreset != aspect else { return }
        checkpoint()
        recipe.aspectPreset = aspect
        recipe.aspectRatio = aspect.ratio
    }

    /// Applies a free ratio from the custom popover, remembering the matching
    /// preset if the numbers happen to land on a named one.
    func applyCustomAspect(ratio: Double) {
        let clamped = min(max(ratio, CollageRecipe.aspectRatioRange.lowerBound),
                          CollageRecipe.aspectRatioRange.upperBound)
        checkpoint()
        recipe.aspectRatio = clamped
        recipe.aspectPreset = CollageAspect.matching(ratio: clamped)
    }

    /// Live preview while the popover's fields change — no checkpoint, so the
    /// popover's own Apply is the single undoable step.
    func previewAspect(ratio: Double) {
        let clamped = min(max(ratio, CollageRecipe.aspectRatioRange.lowerBound),
                          CollageRecipe.aspectRatioRange.upperBound)
        recipe.aspectRatio = clamped
        recipe.aspectPreset = CollageAspect.matching(ratio: clamped)
    }

    // MARK: - Photo count

    var canAddSlot: Bool { slotCount < Self.slotRange.upperBound }
    var canRemoveSlot: Bool { slotCount > Self.slotRange.lowerBound }

    /// Grows the layout by one **empty** slot — it never pulls a photo from the
    /// tray on its own (§4). The user fills it by tapping it.
    func addSlot() {
        guard canAddSlot else { return }
        checkpoint()
        recipe.cells.append(CollageCell(assetID: nil))
        retargetTemplate()
    }

    /// Removes the last slot; its photo, if any, is set aside into the tray
    /// rather than deleted (§4). The screen animates the fly-into-tray; the model
    /// only moves the id.
    func removeSlot() {
        guard canRemoveSlot else { return }
        checkpoint()
        let removed = recipe.cells.removeLast()
        if let id = removed.assetID {
            unplaced.insert(id, at: 0)
            flashTray()
            undoToastMessage = String(localized: "Photo set aside")
        }
        retargetTemplate()
    }

    /// Pulses the tray border once — a photo just landed there.
    private func flashTray() { trayFlashToken &+= 1 }

    /// Picks a template for the current slot count after the count changed.
    private func retargetTemplate() {
        if CollageTemplateCatalog.template(id: recipe.templateID)?.cellCount != slotCount {
            recipe.templateID = CollageTemplateCatalog.templates(for: slotCount).first?.id ?? ""
            recipe.dividerWeights = [:]
        }
    }

    // MARK: - Slots ↔ tray

    /// Fills a slot from the picker/tray. Any photo already there is set aside so
    /// nothing is silently lost. Duplicates are allowed on purpose.
    func fillSlot(_ index: Int, with assetID: String) {
        guard recipe.cells.indices.contains(index) else { return }
        ingest([assetID])
        checkpoint()
        if let displaced = recipe.cells[index].assetID, displaced != assetID {
            unplaced.insert(displaced, at: 0)
        }
        unplaced.removeAll { $0 == assetID }
        recipe.cells[index] = CollageCell(assetID: assetID)
    }

    var emptySlotCount: Int { recipe.cells.reduce(0) { $0 + ($1.isEmpty ? 1 : 0) } }

    /// Fills the tapped slot and then the remaining empty slots, in order, from
    /// the picker's selection (§6). One undoable step. Extra ids are dropped —
    /// the picker already caps the selection at the empty-slot count.
    func fillSlots(startingAt tapped: Int, with assetIDs: [String]) {
        guard !assetIDs.isEmpty, recipe.cells.indices.contains(tapped) else { return }
        ingest(assetIDs)
        checkpoint()
        var targets = [tapped]
        targets.append(contentsOf: recipe.cells.indices.filter { $0 != tapped && recipe.cells[$0].isEmpty })
        for (assetID, target) in zip(assetIDs, targets) {
            if let displaced = recipe.cells[target].assetID, displaced != assetID {
                unplaced.insert(displaced, at: 0)
            }
            unplaced.removeAll { $0 == assetID }
            recipe.cells[target] = CollageCell(assetID: assetID)
        }
    }

    /// Sends a slot's photo to the tray, leaving an empty slot behind (§7).
    func setAside(_ index: Int) {
        guard recipe.cells.indices.contains(index),
              let id = recipe.cells[index].assetID else { return }
        checkpoint()
        recipe.cells[index].assetID = nil
        recipe.cells[index].contentScale = 1
        recipe.cells[index].contentOffset = NormalizedPoint(x: 0, y: 0)
        unplaced.insert(id, at: 0)
        flashTray()
        undoToastMessage = String(localized: "Photo set aside")
    }

    func swapCells(_ first: Int, _ second: Int) {
        guard first != second,
              recipe.cells.indices.contains(first),
              recipe.cells.indices.contains(second)
        else { return }
        checkpoint()
        recipe.cells.swapAt(first, second)
    }

    // MARK: - Style

    func setGutter(_ value: Double) {
        recipe.gutter = min(max(value, CollageRecipe.gutterRange.lowerBound), CollageRecipe.gutterRange.upperBound)
    }

    func setCornerRadius(_ value: Double) {
        recipe.cornerRadius = min(
            max(value, CollageRecipe.cornerRadiusRange.lowerBound),
            CollageRecipe.cornerRadiusRange.upperBound
        )
    }

    func setBackground(_ color: OverlayColor) {
        recipe.background = color
        recipe.backgroundMode = .color
    }

    func setBorderWidth(_ value: Double) {
        recipe.borderWidth = min(
            max(value, CollageRecipe.borderWidthRange.lowerBound),
            CollageRecipe.borderWidthRange.upperBound
        )
    }

    func setBorderColor(_ color: OverlayColor) { recipe.borderColor = color }

    /// Switches to the blurred-photo background (§10), sourcing the blur from the
    /// selected cell — or the first photo if nothing is selected.
    func enableBlurredBackground() {
        checkpoint()
        recipe.backgroundMode = .blurredPhoto
        recipe.backgroundSourceIndex = selectedCellIndex
            ?? recipe.cells.firstIndex(where: { !$0.isEmpty })
    }

    func setBackgroundBlur(_ value: Double) {
        recipe.backgroundBlur = min(max(value, CollageRecipe.backgroundBlurRange.lowerBound),
                                    CollageRecipe.backgroundBlurRange.upperBound)
    }

    func setBackgroundDarken(_ value: Double) {
        recipe.backgroundDarken = min(max(value, CollageRecipe.backgroundDarkenRange.lowerBound),
                                      CollageRecipe.backgroundDarkenRange.upperBound)
    }

    func setPolaroid(_ on: Bool) {
        guard recipe.isPolaroid != on else { return }
        checkpoint()
        recipe.isPolaroid = on
    }

    func setCaption(_ index: Int, _ text: String) {
        guard recipe.cells.indices.contains(index) else { return }
        checkpoint()
        recipe.cells[index].caption = text
    }

    /// Commits a pan/zoom gesture, clamped so the cell never shows background.
    func commitContentGesture(
        cell index: Int,
        scale: Double,
        offset: NormalizedPoint,
        cellFrame: CGRect
    ) {
        guard recipe.cells.indices.contains(index),
              let image = image(for: index)
        else { return }
        let clamped = CollageGeometry.clampedContent(
            imageSize: image.size,
            cellFrame: cellFrame,
            scale: scale,
            offset: offset
        )
        recipe.cells[index].contentScale = clamped.scale
        recipe.cells[index].contentOffset = clamped.offset
    }

    // MARK: - Overlays

    func addTextOverlay(_ text: String) {
        checkpoint()
        var overlay = PhotoOverlay.text()
        overlay.text = text
        overlay.fontPostScriptName = lastFont.postScriptName
        overlay.fontFamilyName = lastFont.familyName
        overlay.fill = lastFill
        recipe.overlays.append(overlay)
        selectedOverlayID = overlay.id
    }

    func updateSelectedOverlay(_ mutate: (inout PhotoOverlay) -> Void) {
        guard let selectedOverlayID,
              let index = recipe.overlays.firstIndex(where: { $0.id == selectedOverlayID })
        else { return }
        mutate(&recipe.overlays[index])
    }

    func deleteSelectedOverlay() {
        guard let selectedOverlayID else { return }
        checkpoint()
        recipe.overlays.removeAll { $0.id == selectedOverlayID }
        self.selectedOverlayID = nil
    }

    func rememberFont(_ font: OverlayFontChoice) {
        lastFont = font
        overlayFontRecents.remember(font)
    }

    // MARK: - Export

    /// Output pixel size for the chosen size cap — also the Export screen's
    /// dimensions readout.
    func outputPixelSize(for size: CollageExportSize) -> CGSize {
        CollageGeometry.outputSize(ratio: recipe.aspectRatio, longEdge: size.longEdge)
    }

    /// Rough byte estimate for the Export screen's "Estimated size" row (§12).
    func estimatedBytes(for options: CollageExportOptions) -> Int {
        CollageImageEncoder.estimatedBytes(
            pixelSize: outputPixelSize(for: options.size),
            format: options.format,
            quality: options.quality
        )
    }

    /// A modest-resolution composite from the previews already in memory, for the
    /// Export screen's live preview — no new PhotoKit fetch.
    func renderPreview(longEdge: CGFloat = 1400) async -> UIImage? {
        guard let template else { return nil }
        let pixelSize = CollageGeometry.outputSize(ratio: recipe.aspectRatio, longEdge: longEdge)
        var images: [Int: CGImage] = [:]
        for (index, cell) in recipe.cells.enumerated() {
            if let id = cell.assetID, let cg = imagesByAsset[id]?.cgImage { images[index] = cg }
        }
        let recipe = recipe
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let cgImage = CollageCompositor.render(
                recipe: recipe, template: template, images: images, pixelSize: pixelSize
            ) else { return nil }
            return UIImage(cgImage: cgImage)
        }.value
    }

    /// Renders at the chosen size/quality/format and saves a new asset (§12).
    /// Sources are requested at cell size × zoom (PhotoKit downscales for us) and
    /// loaded sequentially so nine 48MP originals never coexist in memory;
    /// composition and encoding run detached.
    func export(_ options: CollageExportOptions) async {
        guard !isExporting, let template else { return }
        isExporting = true
        defer { isExporting = false }

        let pixelSize = outputPixelSize(for: options.size)
        let gutter = CollageGeometry.gutterPixels(recipe.gutter, canvasSize: pixelSize)
        let frames = CollageGeometry.cellFrames(
            template: template,
            canvasSize: pixelSize,
            gutter: gutter,
            overrides: recipe.dividerWeights
        )

        var images: [Int: CGImage] = [:]
        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) })
        var firstPlacedAsset: PHAsset?
        for (index, cell) in recipe.cells.enumerated() {
            guard let assetID = cell.assetID,
                  let asset = assetsByID[assetID],
                  frames.indices.contains(index) else { continue }
            if firstPlacedAsset == nil { firstPlacedAsset = asset }
            let frame = frames[index]
            // 1.5× headroom over the placed size keeps the clipped region sharp
            // after the aspect-fill crop without pulling the full original.
            let side = max(frame.width, frame.height) * CGFloat(cell.contentScale) * 1.5
            let image = await requestExportImage(
                asset: asset,
                targetSize: CGSize(width: side, height: side)
            )
            if let cgImage = image?.cgImage {
                images[index] = cgImage
            }
        }

        guard !images.isEmpty else {
            errorMessage = String(localized: "Couldn't load the photos for this collage.")
            return
        }

        var metadata: [CFString: Any]?
        if options.keepFirstPhotoEXIF, let firstPlacedAsset {
            metadata = await photoLibrary.imageProperties(for: firstPlacedAsset)
        }

        let recipe = recipe
        let metadataCopy = metadata
        let rendered = await Task.detached(priority: .userInitiated) { () -> Data? in
            guard let cgImage = CollageCompositor.render(
                recipe: recipe,
                template: template,
                images: images,
                pixelSize: pixelSize
            ) else { return nil }
            return CollageImageEncoder.encode(
                cgImage, format: options.format, quality: options.quality, metadata: metadataCopy
            )
        }.value

        guard let rendered else {
            errorMessage = String(localized: "Couldn't render the collage.")
            return
        }

        do {
            let filename = "collage-\(Int(pixelSize.width))x\(Int(pixelSize.height)).\(options.format.fileExtension)"
            let assetID = try await photoLibrary.saveImage(rendered, filename: filename)
            _ = await indexPipeline.indexSingle(assetId: assetID)
            await addToCollagesAlbum(assetID)
            photoLibrary.publishAppCreatedAsset()
            didSaveAssetID = assetID
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Finds or creates the auto-updating `Collages` user album and files the new
    /// collage into it (§13). Failure here never fails the save — the photo is
    /// already in the library.
    private func addToCollagesAlbum(_ assetID: String) async {
        guard let asset = PhotoLibraryService.fetchAssets(ids: [assetID]).first else { return }
        do {
            let existing = PhotoLibraryService.fetchUserAlbums()
                .first { $0.localizedTitle == Self.collagesAlbumName }
            let album: PHAssetCollection
            if let existing {
                album = existing
            } else {
                album = try await photoLibrary.createAlbum(named: Self.collagesAlbumName)
            }
            try await photoLibrary.addAssets([asset], to: album)
        } catch {
            // Non-fatal: the collage saved; only the album filing failed.
        }
    }

    private static let collagesAlbumName = "Collages"

    /// One final (non-degraded) rendition, or nil on failure. Degraded
    /// callbacks are skipped — export must never bake a blurry rendition in.
    private func requestExportImage(asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            var resumed = false
            _ = photoLibrary.requestDetailImage(
                for: asset,
                targetSize: targetSize,
                allowNetwork: true,
                progress: { _ in }
            ) { image, degraded in
                guard !resumed, !degraded else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }
}
