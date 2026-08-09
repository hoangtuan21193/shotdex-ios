import Photos
import SwiftUI

/// State holder for the collage editor. Owns the recipe (the single source of
/// truth the canvas and the exporter both read), the preview images, and the
/// export flow. Presentation-only state (which cell is selected, which panel
/// group is open) lives here too — the screen stays a thin layout shell.
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

    /// Images only, pick order — the presenting screen already filtered.
    let assets: [PHAsset]
    private let photoLibrary: PhotoLibraryService
    private let indexPipeline: IndexPipeline
    private let overlayFontRecents: OverlayFontRecentsStore

    var recipe: CollageRecipe
    var selectedCellIndex: Int?
    var selectedOverlayID: UUID?
    var panelGroup: PanelGroup = .layout
    /// Set on the first mutation; drives the discard confirmation.
    private(set) var hasEdits = false

    /// Preview images keyed by asset id — swap and replace move cells around,
    /// the pixels follow the asset, not the slot.
    private(set) var imagesByAsset: [String: UIImage] = [:]
    private(set) var isExporting = false
    private(set) var didSave = false
    var errorMessage: String?

    /// The last font/fill the user chose, seeded into the next new text layer.
    var lastFont = OverlayFontChoice.system
    var lastFill = OverlayColor.white

    init(
        assets: [PHAsset],
        photoLibrary: PhotoLibraryService,
        indexPipeline: IndexPipeline,
        overlayFontRecents: OverlayFontRecentsStore
    ) {
        self.assets = assets
        self.photoLibrary = photoLibrary
        self.indexPipeline = indexPipeline
        self.overlayFontRecents = overlayFontRecents
        let template = CollageTemplateCatalog.templates(for: assets.count).first
        self.recipe = CollageRecipe(
            templateID: template?.id ?? "",
            cells: assets.map { CollageCell(assetID: $0.localIdentifier) }
        )
    }

    var template: CollageTemplate? {
        CollageTemplateCatalog.template(id: recipe.templateID)
    }

    var availableTemplates: [CollageTemplate] {
        CollageTemplateCatalog.templates(for: assets.count)
    }

    var selectedOverlay: PhotoOverlay? {
        guard let selectedOverlayID else { return nil }
        return recipe.overlays.first { $0.id == selectedOverlayID }
    }

    func image(for cellIndex: Int) -> UIImage? {
        guard recipe.cells.indices.contains(cellIndex) else { return nil }
        return imagesByAsset[recipe.cells[cellIndex].assetID]
    }

    // MARK: - Loading

    /// Screen-quality previews for every selected asset. One request per asset,
    /// opportunistic — a degraded rendition fills the cell immediately and the
    /// final replaces it in place. 1200pt is enough headroom for a zoomed cell
    /// on the interactive canvas; the export requests its own pixels.
    func loadPreviews() {
        let targetSize = CGSize(width: 1200, height: 1200)
        for asset in assets {
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

    // MARK: - Mutations

    func selectTemplate(_ id: String) {
        guard recipe.templateID != id else { return }
        recipe.templateID = id
        hasEdits = true
    }

    func selectAspect(_ aspect: CollageAspect) {
        guard recipe.aspect != aspect else { return }
        recipe.aspect = aspect
        hasEdits = true
    }

    func setGutter(_ value: Double) {
        recipe.gutter = min(max(value, CollageRecipe.gutterRange.lowerBound), CollageRecipe.gutterRange.upperBound)
        hasEdits = true
    }

    func setCornerRadius(_ value: Double) {
        recipe.cornerRadius = min(
            max(value, CollageRecipe.cornerRadiusRange.lowerBound),
            CollageRecipe.cornerRadiusRange.upperBound
        )
        hasEdits = true
    }

    func setBackground(_ color: OverlayColor) {
        recipe.background = color
        hasEdits = true
    }

    func swapCells(_ first: Int, _ second: Int) {
        guard first != second,
              recipe.cells.indices.contains(first),
              recipe.cells.indices.contains(second)
        else { return }
        recipe.cells.swapAt(first, second)
        hasEdits = true
    }

    /// Replaces one cell's photo with another from the selected set (duplicates
    /// allowed) and resets that cell's pan/zoom — the old transform was framed
    /// for the old picture.
    func replaceCell(_ index: Int, with assetID: String) {
        guard recipe.cells.indices.contains(index) else { return }
        recipe.cells[index] = CollageCell(assetID: assetID)
        hasEdits = true
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
        hasEdits = true
    }

    // MARK: - Overlays

    func addTextOverlay(_ text: String) {
        var overlay = PhotoOverlay.text()
        overlay.text = text
        overlay.fontPostScriptName = lastFont.postScriptName
        overlay.fontFamilyName = lastFont.familyName
        overlay.fill = lastFill
        recipe.overlays.append(overlay)
        selectedOverlayID = overlay.id
        hasEdits = true
    }

    func updateSelectedOverlay(_ mutate: (inout PhotoOverlay) -> Void) {
        guard let selectedOverlayID,
              let index = recipe.overlays.firstIndex(where: { $0.id == selectedOverlayID })
        else { return }
        mutate(&recipe.overlays[index])
        hasEdits = true
    }

    func deleteSelectedOverlay() {
        guard let selectedOverlayID else { return }
        recipe.overlays.removeAll { $0.id == selectedOverlayID }
        self.selectedOverlayID = nil
        hasEdits = true
    }

    func rememberFont(_ font: OverlayFontChoice) {
        lastFont = font
        overlayFontRecents.remember(font)
    }

    // MARK: - Export

    /// Renders at full quality and saves a new asset. Sources are requested at
    /// cell size × zoom (PhotoKit downscales for us) and loaded sequentially so
    /// nine 48MP originals never coexist in memory; composition runs detached.
    func export() async {
        guard !isExporting, let template else { return }
        isExporting = true
        defer { isExporting = false }

        let pixelSize = CollageGeometry.outputSize(
            ratio: recipe.aspect.ratio,
            longEdge: CollageCompositor.exportLongEdge
        )
        let gutter = CollageGeometry.gutterPixels(recipe.gutter, canvasSize: pixelSize)
        let frames = CollageGeometry.cellFrames(
            template: template,
            canvasSize: pixelSize,
            gutter: gutter
        )

        var images: [Int: CGImage] = [:]
        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) })
        for (index, cell) in recipe.cells.enumerated() {
            guard let asset = assetsByID[cell.assetID], frames.indices.contains(index) else { continue }
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

        let recipe = recipe
        let rendered = await Task.detached(priority: .userInitiated) { () -> Data? in
            guard let cgImage = CollageCompositor.render(
                recipe: recipe,
                template: template,
                images: images,
                pixelSize: pixelSize
            ) else { return nil }
            return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.95)
        }.value

        guard let rendered else {
            errorMessage = String(localized: "Couldn't render the collage.")
            return
        }

        do {
            let filename = PhotoOutputFilename.make(
                original: nil,
                suffix: "collage",
                index: 1,
                format: .jpeg
            )
            let assetID = try await photoLibrary.saveImage(rendered, filename: filename)
            _ = await indexPipeline.indexSingle(assetId: assetID)
            photoLibrary.publishAppCreatedAsset()
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

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
