import CoreGraphics
import CoreImage
import Foundation
import Photos
import ShotDexKit

/// One photo the Watermark screen previews: its picture at preview size, the
/// size it will be written at, and its token values (FS-05.04 §4).
struct WatermarkPreviewPage: Identifiable {
    let id: String
    let filename: String
    /// The file's size in pixels, as the form will write it — what Size's
    /// `px` counts.
    let exportSize: CGSize
    let tokens: OverlayTokenValues
    /// The picture without the stamp, at preview size, cropped as the export
    /// crops it. Nil when it cannot be read.
    let load: @MainActor () async -> CGImage?
}

/// The Watermark screen (FS-05.04 §4): one remembered configuration, edited
/// for every form, previewed on the photos of the batch.
@MainActor
@Observable
final class WatermarkModel {
    let settings: WatermarkSettingsStore
    let presets: SignaturePresetStore
    let pages: [WatermarkPreviewPage]
    /// The form this screen was opened from, for the back button: "Resize".
    let formTitle: String
    /// Whether a logo file is still there (FS-05.04 §5).
    @ObservationIgnored let imageExists: (UUID) -> Bool

    var currentIndex = 0 {
        didSet { if currentIndex != oldValue { renderCurrent() } }
    }

    /// Pictures without the stamp, per page.
    private(set) var bases: [String: CGImage] = [:]
    /// The current page with the stamp, as the file will have it.
    private(set) var stamped: [String: CGImage] = [:]

    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private let renderer = WatermarkPreviewRenderer()

    init(
        settings: WatermarkSettingsStore,
        presets: SignaturePresetStore,
        pages: [WatermarkPreviewPage],
        formTitle: String,
        imageExists: @escaping (UUID) -> Bool = { OverlayImageStore().imageExists(id: $0) }
    ) {
        self.settings = settings
        self.presets = presets
        self.pages = pages
        self.formTitle = formTitle
        self.imageExists = imageExists
    }

    /// Whether a preset can be stamped: Missing file is not selectable,
    /// Unavailable (a font fell back) is.
    func availability(of preset: SignaturePreset) -> WatermarkAvailability {
        WatermarkAvailability.of(preset, imageExists: imageExists)
    }

    /// The presets a switched-on watermark may fall to.
    private var selectablePresets: [SignaturePreset] {
        presets.presets.filter { availability(of: $0).isSelectable }
    }

    // MARK: State

    var hasPresets: Bool { !presets.presets.isEmpty }

    var isEnabled: Bool { settings.settings.isEnabled && selectedPreset != nil }

    /// The remembered preset, if it still exists and can be stamped.
    var selectedPreset: SignaturePreset? {
        settings.formPreset(in: presets.presets) { availability(of: $0).isSelectable }
    }

    var placement: WatermarkPlacement { settings.settings.placement }

    var currentPage: WatermarkPreviewPage? { pages.indices.contains(currentIndex) ? pages[currentIndex] : nil }

    /// Size as a fraction of the short edge: the remembered one, or the
    /// preset's own.
    var sizeFraction: Double {
        if let size = placement.size { return size }
        guard let preset = selectedPreset else { return 0.04 }
        let natural = PhotoRenderService.watermarkNaturalSize(WatermarkStamp(preset: preset, placement: placement))
        return min(max(natural ?? 0.04, WatermarkPlacement.sizeRange.lowerBound), WatermarkPlacement.sizeRange.upperBound)
    }

    /// The short edge of the photo being previewed, as written.
    var previewShortEdge: CGFloat {
        currentPage.map { min($0.exportSize.width, $0.exportSize.height) } ?? 1000
    }

    /// Size as the stepper reads it: pixels of the photo being previewed.
    var sizePixels: Int { WatermarkLayout.pixels(forSize: sizeFraction, shortEdge: previewShortEdge) }

    // MARK: Changes

    func setEnabled(_ enabled: Bool) {
        settings.update { settings in
            settings.isEnabled = enabled
            // Turning it on with nothing chosen picks the newest preset, so
            // the switch never reads On over a blank preview.
            if enabled, settings.presetID.flatMap({ id in selectablePresets.first { $0.id == id } }) == nil {
                settings.presetID = selectablePresets.first?.id
                settings.placement.size = nil
            }
        }
        renderCurrent()
    }

    func choose(_ preset: SignaturePreset) {
        guard availability(of: preset).isSelectable else { return }
        settings.update { settings in
            if settings.presetID != preset.id {
                // Another preset starts at its own saved size.
                settings.placement.size = nil
            }
            settings.presetID = preset.id
            settings.isEnabled = true
        }
        renderCurrent()
    }

    func setAnchor(_ anchor: WatermarkAnchor) {
        settings.update { $0.placement.anchor = anchor }
        renderCurrent()
    }

    func setMargin(_ margin: Double) {
        let stepped = (margin / WatermarkPlacement.marginStep).rounded() * WatermarkPlacement.marginStep
        settings.update { $0.placement = WatermarkPlacement(
            anchor: $0.placement.anchor, margin: stepped, size: $0.placement.size, opacity: $0.placement.opacity
        ) }
        renderCurrent()
    }

    func setOpacity(_ opacity: Double) {
        let stepped = (opacity / WatermarkPlacement.opacityStep).rounded() * WatermarkPlacement.opacityStep
        settings.update { $0.placement = WatermarkPlacement(
            anchor: $0.placement.anchor, margin: $0.placement.margin, size: $0.placement.size, opacity: stepped
        ) }
        renderCurrent()
    }

    /// One step of Size: 1% of the short edge.
    func stepSize(by steps: Int) {
        let current = (sizeFraction / WatermarkPlacement.sizeStep).rounded() * WatermarkPlacement.sizeStep
        setSize(current + Double(steps) * WatermarkPlacement.sizeStep)
    }

    /// Size typed as pixels of the photo being previewed.
    func setSizePixels(_ pixels: Int) {
        setSize(WatermarkLayout.size(forPixels: pixels, shortEdge: previewShortEdge))
    }

    private func setSize(_ size: Double) {
        let clamped = min(max(size, WatermarkPlacement.sizeRange.lowerBound), WatermarkPlacement.sizeRange.upperBound)
        settings.update { $0.placement.size = clamped }
        renderCurrent()
    }

    // MARK: Preview

    /// The stamp for a page, tokens filled; nil when the watermark is off.
    func stamp(for page: WatermarkPreviewPage) -> WatermarkStamp? {
        guard settings.settings.isEnabled, let preset = selectedPreset else { return nil }
        var placement = placement
        placement.size = sizeFraction
        return WatermarkStamp(preset: preset, placement: placement).resolved(with: page.tokens)
    }

    /// What the preview shows for a page: stamped when ready, else the bare
    /// picture.
    func image(for page: WatermarkPreviewPage) -> CGImage? {
        stamped[page.id] ?? bases[page.id]
    }

    func load(_ page: WatermarkPreviewPage) async {
        if bases[page.id] == nil, let image = await page.load() {
            bases[page.id] = image
        }
        if page.id == currentPage?.id { renderCurrent() }
    }

    /// Re-stamps the current page. The last change wins: a slider drag
    /// cancels the render it overtakes.
    func renderCurrent() {
        guard let page = currentPage, let base = bases[page.id] else { return }
        let stamp = stamp(for: page)
        renderTask?.cancel()
        let renderer = renderer
        renderTask = Task { [weak self] in
            let image = await renderer.stamped(base, stamp: stamp)
            guard !Task.isCancelled, let self else { return }
            self.stamped[page.id] = image
        }
    }

    /// Where the block's centre lands on a preview `displaySize` points big
    /// showing a picture of `imageSize` pixels fitted — the number AC-2 holds
    /// against the export's.
    static func previewBoxCentre(_ stamp: WatermarkStamp, imageSize: CGSize, displaySize: CGSize) -> CGPoint? {
        guard let frame = PhotoRenderService.watermarkFrame(stamp, imageSize: imageSize) else { return nil }
        let scale = min(displaySize.width / imageSize.width, displaySize.height / imageSize.height)
        let offset = CGPoint(
            x: (displaySize.width - imageSize.width * scale) / 2,
            y: (displaySize.height - imageSize.height * scale) / 2
        )
        return CGPoint(x: offset.x + frame.box.midX * scale, y: offset.y + frame.box.midY * scale)
    }
}

/// Composites a stamp on a preview picture off the main actor, through the
/// same raster as the export.
final class WatermarkPreviewRenderer: Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false, .name: "ShotDex Watermark Preview"])

    func stamped(_ base: CGImage, stamp: WatermarkStamp?) async -> CGImage {
        guard let stamp, stamp.hasVisibleLayers else { return base }
        let context = context
        return await Task.detached(priority: .userInitiated) {
            let image = CIImage(cgImage: base)
            let composite = PhotoRenderService.applyWatermark(stamp, to: image)
            return context.createCGImage(
                composite, from: image.extent,
                format: .RGBA8, colorSpace: base.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
            ) ?? base
        }.value
    }
}

extension ResizePreset {
    /// The pixel size a photo of `source` is written at — Fit scales into
    /// the box, Fill fills it, the rest is `targetPixelSize`.
    func outputPixelSize(source: CGSize) -> CGSize {
        let target = targetPixelSize(sourceWidth: Int(source.width), sourceHeight: Int(source.height))
        guard kind == .exact, cropMode == .fit, source.width > 0, source.height > 0 else { return target }
        let scale = min(target.width / source.width, target.height / source.height)
        return CGSize(width: max(1, (source.width * scale).rounded()), height: max(1, (source.height * scale).rounded()))
    }
}

extension WatermarkModel: Hashable {
    nonisolated static func == (lhs: WatermarkModel, rhs: WatermarkModel) -> Bool { lhs === rhs }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

extension PhotoLibraryService {
    /// A photo's display picture, `longEdge` big, once — the final one, not
    /// PhotoKit's early degraded pass.
    func detailCGImage(for asset: PHAsset, longEdge: CGFloat) async -> CGImage? {
        await withCheckedContinuation { continuation in
            final class Once { var done = false }
            let once = Once()
            _ = requestDetailImage(
                for: asset,
                targetSize: CGSize(width: longEdge, height: longEdge),
                progress: { _ in }
            ) { image, degraded in
                guard !once.done, !degraded || image == nil else { return }
                once.done = true
                continuation.resume(returning: image?.cgImage)
            }
        }
    }
}
