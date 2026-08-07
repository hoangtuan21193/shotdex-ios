import Photos
import SwiftUI
import UIKit

enum PhotoEditorTool: String, CaseIterable, Identifiable {
    case adjust
    /// The old single Color tab, split into its three Lightroom blocks so each is
    /// one tap rather than a tap plus a section switch. The three sit together,
    /// right of Adjust, where Color used to be — the eighth tab is what pushed the
    /// bar to scroll horizontally (`PhotoEditorScreen.tabBar`).
    case colorMixer
    case pointColor
    case colorGrading
    case filters
    /// The Markup tab: text, image and signature-preset layers plus freehand
    /// drawing. The raw value stays `markup` for a clean identifier; the tab used
    /// to be "Text" before it grew image layers and a pencil.
    case markup
    case crop
    case masks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adjust: "Adjust"
        case .colorMixer: "Mixer"
        case .pointColor: "Point"
        case .colorGrading: "Grading"
        case .filters: "Filters"
        case .markup: "Markup"
        case .crop: "Crop"
        case .masks: "Masks"
        }
    }

    var systemImage: String {
        switch self {
        case .adjust: "slider.horizontal.3"
        case .colorMixer: "circle.hexagongrid"
        case .pointColor: "eyedropper"
        case .colorGrading: "paintpalette"
        case .filters: "camera.filters"
        case .markup: "pencil.tip.crop.circle"
        case .crop: "crop.rotate"
        case .masks: "circle.dashed"
        }
    }
}

/// The 28c bottom nav: one chip per editing group. Finer than `PhotoEditorTool` —
/// Light / Color / Effects / Detail / Optics / Geo all drive the single global
/// `.adjust` tool but show different rows — so the group is its own selection,
/// held on `EditorChromeModel.selectedGroup`. The chip order is the nav order.
enum EditorGroup: String, CaseIterable, Identifiable {
    case light
    case color
    case pointColor
    case grade
    case effects
    case detail
    case optics
    case geo
    case crop
    case mask
    case markup
    case presets

    var id: String { rawValue }

    /// Plain (not upper-cased) chip title, per 28c §5.
    var title: String {
        switch self {
        case .light: "Light"
        case .color: "Color"
        case .pointColor: "Point"
        case .grade: "Grade"
        case .effects: "Effects"
        case .detail: "Detail"
        case .optics: "Optics"
        case .geo: "Geo"
        case .crop: "Crop"
        case .mask: "Mask"
        case .markup: "Markup"
        case .presets: "Presets"
        }
    }

    /// The tool this group activates. The six adjustment-style groups share the
    /// global `.adjust` tool; the rest map one-to-one. (Optics and Geo have no
    /// parameters yet, so they sit on `.adjust` and show a placeholder.)
    var tool: PhotoEditorTool {
        switch self {
        case .light, .color, .effects, .detail, .optics, .geo: .adjust
        case .pointColor: .pointColor
        case .grade: .colorGrading
        case .crop: .crop
        case .mask: .masks
        case .markup: .markup
        case .presets: .filters
        }
    }
}

@MainActor
@Observable
final class PhotoEditorController {
    // Curve setters live in an extension at the end of this file.
    let asset: PHAsset
    let sourceAlbum: PHAssetCollection?
    /// What `{camera}`-style tokens in a text layer expand to. Resolved once from
    /// the indexed row the caller already had — this is the whole reason the
    /// editor takes a `PhotoMetadata` at all.
    let overlayTokens: OverlayTokenValues

    private let service: PhotoEditingService
    private(set) var session: PhotoEditingSession?
    private(set) var loadedSource: LoadedPhotoEditSource?
    private(set) var selectedSourceOption: PhotoEditSourceOption?

    var recipe = PhotoEditRecipe.identity
    private(set) var editedPreviewImage: UIImage?
    private(set) var originalPreviewImage: UIImage?
    private(set) var histogram = PhotoHistogram.empty
    private(set) var maskThumbnails: [UUID: UIImage] = [:]
    /// The photo through each film look, at swatch size. Filled one category at a
    /// time — fifty swatches means fifty lookup tables, and only one strip is ever
    /// on screen.
    private(set) var filterThumbnails: [PhotoFilter: UIImage] = [:]
    @ObservationIgnored private var colorSamplingImage: CGImage?
    @ObservationIgnored private var maskThumbnailSignature = ""
    @ObservationIgnored private var maskThumbnailTask: Task<Void, Never>?
    @ObservationIgnored private var filterThumbnailSignature = ""
    @ObservationIgnored private var filterThumbnailTask: Task<Void, Never>?
    /// Which strip the Filters tab is showing. Session state, like the selected
    /// adjustment: it starts on the category the recipe's own look belongs to and is
    /// the user's business after that.
    private(set) var selectedFilterCategory: FilmLookCategory = .basic
    /// Crop is the one modal tool: entering it opens a draft session and leaving it
    /// any way other than `Done` throws the framing away, so every tool switch has
    /// to run through here rather than assigning the stored property.
    var selectedTool: PhotoEditorTool {
        get { currentTool }
        set {
            guard newValue != currentTool else { return }
            if currentTool == .crop { cancelCropSession() }
            currentTool = newValue
            if newValue == .crop { beginCropSession() }
        }
    }

    private var currentTool: PhotoEditorTool = .adjust
    var selectedAdjustment: PhotoAdjustmentKind = .exposure
    var selectedMaskID: UUID?
    var selectedComponentID: UUID?
    var selectedPointColorID: UUID?
    /// On whenever the user is working on the mask's shape, off the moment they
    /// start adjusting its effect — the red tint covers the pixels being judged.
    /// One rule, no exceptions: even an overlay switched on by hand yields to a
    /// slider drag, because a red-tinted photo makes every adjustment unreadable.
    private(set) var showsMaskOverlay = false
    var showsOriginal = false
    /// Whether new mask regions and brush strokes add to or subtract from the
    /// selected mask. Lives here because the Add/Sub control in the action row and
    /// the brush both read it.
    var maskOperation: MaskBlendOperation = .add {
        didSet {
            brushIsEraser = maskOperation == .subtract
            guard maskOperation != oldValue else { return }
            revealMaskShape()
        }
    }
    private(set) var usesMaskAdjustmentScope = false

    /// A quarter of the image's short edge, like Lightroom's default: the first
    /// stroke should read as "I am painting a region", not a pen line.
    var brushSize = 0.25
    var brushFeather = 0.45
    var brushFlow = 0.8
    var brushIsEraser = false

    // Text/signature session state. Which layer is being worked on, and the look a
    // *new* layer inherits — tool-level, like the brush's size: a layer captures
    // them when it is created, and changing them afterwards is not an edit to the
    // photo.
    var selectedOverlayID: UUID?
    /// Whether the selected layer's *detail* panel is up. Separate from selection:
    /// a selected layer can be moved / resized / rotated on the photo while the list
    /// is still showing. Detail (fine sliders, content, font) is opened explicitly
    /// from a row's chevron.
    var showsOverlayDetail = false
    var lastFont = OverlayFontChoice.system
    var lastFill = OverlayColor.white

    private(set) var isLoading = true
    private(set) var isRendering = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var didFallbackToJPEG = false
    private(set) var savedAssetID: String?

    @ObservationIgnored private var history = PhotoEditHistory()
    @ObservationIgnored private var cropSession: CropSession?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var interactiveRenderTask: Task<Void, Never>?
    @ObservationIgnored private var interactiveRenderPending = false
    @ObservationIgnored private var renderGeneration = 0
    @ObservationIgnored private var isContinuousChange = false
    /// A drag, pinch or slider sweep on an overlay layer is in progress. Its own
    /// flag rather than `isContinuousChange` because an overlay gesture must not
    /// drive the render loop at all — see `beginOverlayGesture`.
    @ObservationIgnored private var isOverlayGesture = false
    /// Pixels the photo is drawn at right now — the interactive render's target.
    /// Starts at the old flat ceiling and is replaced by the real stage size on
    /// first layout, so a controller nobody measured still renders something.
    @ObservationIgnored private var displayEdge: CGFloat = 1_024
    /// The size every frame of the gesture in progress renders at. Held so the
    /// resolution cannot change mid-drag.
    @ObservationIgnored private var frozenInteractiveEdge: CGFloat?
    /// Floor for a very small stage only. Nothing lowers the interactive render
    /// below the display size: a drag must never soften the photo.
    private static let minimumInteractiveEdge: CGFloat = 768
    private static let rawDemosaicEdge: CGFloat = 768
    /// Nonisolated so it can be a default argument — the settle render's size is a
    /// constant, not actor state.
    nonisolated private static let settleEdge: CGFloat = 2_400
    /// Ceiling for the settle render once the photo is pinched open. 2400 is about
    /// the pixels a whole photo needs on a phone at 100%; at 400% the same photo is
    /// being drawn four times that, so a flat 2400 made the picture soft exactly
    /// when the user zoomed in to look closely. Capped rather than uncapped:
    /// following an 800% zoom literally would ask Core Image for a 9600px frame.
    private static let zoomedSettleEdge: CGFloat = 4_800
    @ObservationIgnored private var activeBrushStrokeIndex: Int?
    @ObservationIgnored private var sessionBaselineRecipe = PhotoEditRecipe.identity
    /// Gradient components added this session that have never been placed. Only
    /// these take the drag-to-place gesture; once a gradient exists, a drag on
    /// the photo *moves* it (Snapseed-style) instead of silently rebuilding it
    /// from scratch. Session state on purpose — a component that came back from
    /// a saved recipe has a real shape, so it is by definition placed.
    @ObservationIgnored private var unplacedComponentIDs: Set<UUID> = []

    init(
        asset: PHAsset,
        sourceAlbum: PHAssetCollection?,
        service: PhotoEditingService,
        metadata: PhotoMetadata? = nil
    ) {
        self.asset = asset
        self.sourceAlbum = sourceAlbum
        self.service = service
        overlayTokens = OverlayTokenValues(metadata: metadata)
    }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    var recalledRecipe: PhotoEditRecipe? { session?.recalledRecipe }
    var canRecall: Bool { recalledRecipe != nil && recipe != recalledRecipe }
    var hasSessionChanges: Bool { recipe != sessionBaselineRecipe }
    var sourceOptions: [PhotoEditSourceOption] { session?.sourceOptions ?? [] }
    var isRAWSource: Bool { loadedSource?.info.isRAW == true }
    var supportsHEICEditOutput: Bool {
        guard let session else { return false }
        return service.supportsEditOutputFormat(.heic, in: session)
    }

    var selectedMask: PhotoMask? {
        guard let selectedMaskID else { return nil }
        return recipe.masks.first { $0.id == selectedMaskID }
    }

    var selectedComponent: PhotoMaskComponent? {
        guard let selectedMask, let selectedComponentID else { return nil }
        return selectedMask.components.first { $0.id == selectedComponentID }
    }

    var editingMaskAdjustments: Bool {
        usesMaskAdjustmentScope && selectedMaskID != nil
    }

    var historyTimeline: [PhotoEditRecipe] { history.timeline(current: recipe) }
    var historyCurrentIndex: Int { history.currentIndex }

    var previewImage: UIImage? {
        showsOriginal ? originalPreviewImage ?? editedPreviewImage : editedPreviewImage
    }

    /// Shape of the previewed photo, held stable while only the render *size*
    /// changes. The stage lays out from this rather than from the bitmap, so a
    /// re-render at a different resolution cannot nudge the photo or the guides
    /// over it — a nudge that is a fraction of a point at 1× and eight times that
    /// at 800%, where it reads as the picture jumping.
    private(set) var previewAspectRatio: CGFloat = 1
    /// Everything about the recipe that changes the *shape* of the output. When
    /// this is unchanged, the aspect is reused verbatim.
    @ObservationIgnored private var previewAspectSignature = ""

    func load() async {
        guard session == nil else { return }
        isLoading = true
        errorMessage = nil
        do {
            let session = try await service.beginSession(for: asset)
            self.session = session
            let option = session.preferredSource(for: session.recalledRecipe)
            guard let option else { throw PhotoEditingError.missingSource }
            try await selectSource(option, renders: false)

            // Photos gives ShotDex the immutable source plus our adjustment
            // data when `canHandleAdjustmentData` succeeds. Start from that
            // recipe so reopening an edited asset shows its latest crop and
            // adjustments instead of silently returning to the source image.
            var initialRecipe = session.recalledRecipe ?? .identity
            initialRecipe.source = option.source
            initialRecipe.sourceFilename = option.filename
            recipe = initialRecipe
            sessionBaselineRecipe = initialRecipe
            history.clear()
            selectedMaskID = initialRecipe.masks.first?.id
            selectedComponentID = initialRecipe.masks.first?.components.first?.id
            selectedFilterCategory = initialRecipe.filter.category
            await renderNow()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func close() {
        renderTask?.cancel()
        interactiveRenderTask?.cancel()
        maskThumbnailTask?.cancel()
        filterThumbnailTask?.cancel()
        if let session {
            service.endSession(session)
        }
    }

    func selectSource(
        _ option: PhotoEditSourceOption,
        renders: Bool = true
    ) async throws {
        guard let session else { throw PhotoEditingError.unavailable }
        isLoading = true
        defer { isLoading = false }
        let loaded = try await service.loadSource(option, in: session)
        selectedSourceOption = option
        loadedSource = loaded
        recipe.source = option.source
        recipe.sourceFilename = option.filename
        await renderOriginal()
        if renders { await renderNow() }
    }

    func recallLastEdit() {
        guard let recalledRecipe else { return }
        recordHistory()
        recipe = recalledRecipe
        if let session,
           let option = session.preferredSource(for: recalledRecipe),
           option.id != selectedSourceOption?.id {
            Task {
                do {
                    try await selectSource(option, renders: false)
                    scheduleRender()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } else {
            scheduleRender()
        }
    }

    func reset() {
        recordHistory()
        let source = recipe.source
        let filename = recipe.sourceFilename
        let sourceAssetIdentifier = recipe.sourceAssetIdentifier
        recipe = .identity
        recipe.source = source
        recipe.sourceFilename = filename
        recipe.sourceAssetIdentifier = sourceAssetIdentifier
        selectedMaskID = nil
        selectedComponentID = nil
        selectedOverlayID = nil
        showsOverlayDetail = false
        isEditingText = false
        scheduleRender()
    }

    func undo() {
        guard let previous = history.undo(current: recipe) else { return }
        recipe = previous
        repairSelection()
        scheduleRender()
    }

    func redo() {
        guard let next = history.redo(current: recipe) else { return }
        recipe = next
        repairSelection()
        scheduleRender()
    }

    func beginContinuousChange() {
        guard !isContinuousChange else { return }
        history.record(recipe)
        isContinuousChange = true
        scheduleInteractiveRender()
    }

    func endContinuousChange() {
        guard isContinuousChange else { return }
        isContinuousChange = false
        // Next gesture re-picks its resolution from what this one measured.
        frozenInteractiveEdge = nil
        interactiveRenderPending = true
        if interactiveRenderTask == nil {
            scheduleRender(delay: .zero)
        }
    }

    var currentAdjustments: PhotoAdjustments {
        if let index = selectedMaskIndex, editingMaskAdjustments {
            return recipe.masks[index].adjustments
        }
        return recipe.adjustments
    }

    func adjustmentValue(_ kind: PhotoAdjustmentKind) -> Double {
        currentAdjustments[kind]
    }

    func setAdjustment(_ kind: PhotoAdjustmentKind, value: Double) {
        if !isContinuousChange { recordHistory() }
        writeAdjustment(kind, value: value)
        scheduleRender()
    }

    private func writeAdjustment(_ kind: PhotoAdjustmentKind, value: Double) {
        if let index = selectedMaskIndex, editingMaskAdjustments {
            recipe.masks[index].adjustments[kind] = value
            hideMaskShapeForAdjustment()
        } else {
            recipe.adjustments[kind] = value
        }
    }

    func chooseFilter(_ filter: PhotoFilter) {
        guard recipe.filter != filter else { return }
        recordHistory()
        recipe.filter = filter
        scheduleRender()
    }

    func chooseFilterCategory(_ category: FilmLookCategory) {
        guard selectedFilterCategory != category else { return }
        selectedFilterCategory = category
        refreshFilterThumbnails()
    }

    func editGlobalAdjustments() {
        usesMaskAdjustmentScope = false
        selectedTool = .adjust
        scheduleRender()
    }

    /// Enters the single-mask editor: the panel keeps showing the Masks tab, but
    /// every slider now writes into that mask.
    func editSelectedMaskAdjustments() {
        guard selectedMaskID != nil else { return }
        usesMaskAdjustmentScope = true
        selectedTool = .masks
        selectedAdjustment = .exposure
        revealMaskShape()
        // The overlay only draws inside this editor, so entering it changes the
        // render even when `revealMaskShape` found the flag already on and
        // scheduled nothing.
        scheduleRender(delay: .zero)
    }

    /// The eye in the action row.
    func setMaskOverlay(_ shows: Bool) {
        showsMaskOverlay = shows
        scheduleRender(delay: .zero)
    }

    /// Turns the red overlay on because the user is working on the mask's *shape* —
    /// creating or opening a mask, painting, placing a gradient, inverting, changing
    /// a shape. The shape is what they are looking at, so it stays on screen until
    /// they move to the adjustments; there is no timer taking it away mid-stroke.
    func revealMaskShape() {
        guard !showsMaskOverlay else { return }
        showsMaskOverlay = true
        scheduleRender(delay: .zero)
    }

    /// The moment the user starts dialling the mask's effect, the red tint is in the
    /// way of the only thing that matters — what the adjustment looks like — so it
    /// gets out of the way by itself, no matter how it was turned on.
    private func hideMaskShapeForAdjustment() {
        guard showsMaskOverlay else { return }
        showsMaskOverlay = false
    }

    /// Leaves the single-mask editor and returns to the mask list.
    func closeSelectedMaskAdjustments() {
        usesMaskAdjustmentScope = false
        scheduleRender()
    }

    func setFilterIntensity(_ value: Double) {
        if !isContinuousChange { recordHistory() }
        recipe.filterIntensity = min(1, max(0, value))
        scheduleRender()
    }

    /// `Reset` in a group header: clears just that group's sliders.
    func resetAdjustments(_ kinds: [PhotoAdjustmentKind]) {
        recordHistory()
        let defaults = PhotoAdjustments()
        for kind in kinds {
            writeAdjustment(kind, value: defaults[kind])
        }
        scheduleRender()
    }

    func resetAdjustment(_ kind: PhotoAdjustmentKind) {
        recordHistory()
        writeAdjustment(kind, value: PhotoAdjustments()[kind])
        scheduleRender()
    }

    /// `Auto` in the Light header. The suggestion comes from the histogram the
    /// editor already has, so it costs no extra render.
    func applyAutoTone() {
        recordHistory()
        let suggestion = EditorAutoTone.suggestion(
            for: currentAdjustments,
            histogram: histogram
        )
        for kind in [PhotoAdjustmentKind.exposure, .contrast, .whites] {
            writeAdjustment(kind, value: suggestion[kind])
        }
        scheduleRender()
    }

    func jumpToHistoryStep(_ index: Int) {
        guard let recipe = history.jump(to: index, current: recipe) else { return }
        self.recipe = recipe
        repairSelection()
        scheduleRender()
    }

    // MARK: - Color tab (global-only: mixer, point color, grading)

    func mixerValue(band: ColorMixerBand, property: ColorMixerProperty) -> Double {
        recipe.color.mixer[band][property]
    }

    func setMixerValue(_ value: Double, band: ColorMixerBand, property: ColorMixerProperty) {
        if !isContinuousChange { recordHistory() }
        recipe.color.mixer[band][property] = min(1, max(-1, value))
        scheduleRender()
    }

    /// `nil` resets all 24 sliders, a property resets its 8.
    func resetColorMixer(property: ColorMixerProperty?) {
        recordHistory()
        if let property {
            for band in ColorMixerBand.allCases {
                recipe.color.mixer[band][property] = 0
            }
        } else {
            recipe.color.mixer = .identity
        }
        scheduleRender()
    }

    var pointColors: [PointColorAdjustment] { recipe.color.points }

    var selectedPointColor: PointColorAdjustment? {
        recipe.color.points.first { $0.id == selectedPointColorID }
    }

    var canAddPointColor: Bool {
        recipe.color.points.count < PointColorAdjustment.maximumCount
    }

    /// Samples the edited preview at the tapped spot (Lightroom semantics: you
    /// pick the color you currently see; the reference is never resampled when
    /// upstream edits change) and starts a new point selected.
    func addPointColor(sampledAt point: NormalizedPoint) {
        guard canAddPointColor,
              let sample = samplePreviewColor(at: point)
        else { return }
        recordHistory()
        let hsv = ColorRenderMath.hsv(
            fromRed: sample.red,
            green: sample.green,
            blue: sample.blue
        )
        let pointColor = PointColorAdjustment(
            referenceHue: hsv.hue,
            referenceSaturation: hsv.saturation,
            referenceValue: hsv.value
        )
        recipe.color.points.append(pointColor)
        selectedPointColorID = pointColor.id
        scheduleRender()
    }

    func removePointColor(id: UUID) {
        guard recipe.color.points.contains(where: { $0.id == id }) else { return }
        recordHistory()
        recipe.color.points.removeAll { $0.id == id }
        if selectedPointColorID == id {
            selectedPointColorID = recipe.color.points.last?.id
        }
        scheduleRender()
    }

    func updateSelectedPointColor(_ mutate: (inout PointColorAdjustment) -> Void) {
        guard let index = recipe.color.points.firstIndex(where: {
            $0.id == selectedPointColorID
        }) else { return }
        if !isContinuousChange { recordHistory() }
        mutate(&recipe.color.points[index])
        scheduleRender()
    }

    /// Live readout under the eyedropper, for the loupe: the color itself and its
    /// sRGB hex, read in one pass so a dragging finger never decodes the same
    /// pixel twice a frame.
    func previewColorReadout(at point: NormalizedPoint) -> (color: Color, hex: String)? {
        guard let sample = samplePreviewColor(at: point) else { return nil }
        let byte = { (value: Double) in Int((min(1, max(0, value)) * 255).rounded()) }
        return (
            Color(red: sample.red, green: sample.green, blue: sample.blue),
            String(format: "#%02X%02X%02X", byte(sample.red), byte(sample.green), byte(sample.blue))
        )
    }

    func gradingWheel(_ region: ColorGradingRegion) -> ColorGradingAdjustments.Wheel {
        recipe.color.grading[region]
    }

    func setGradingHueSat(region: ColorGradingRegion, hue: Double, saturation: Double) {
        if !isContinuousChange { recordHistory() }
        recipe.color.grading[region].hue = min(360, max(0, hue))
        recipe.color.grading[region].saturation = min(1, max(0, saturation))
        scheduleRender()
    }

    func setGradingLuminance(region: ColorGradingRegion, _ value: Double) {
        if !isContinuousChange { recordHistory() }
        recipe.color.grading[region].luminance = min(1, max(-1, value))
        scheduleRender()
    }

    func setGradingBlending(_ value: Double) {
        if !isContinuousChange { recordHistory() }
        recipe.color.grading.blending = min(1, max(0, value))
        scheduleRender()
    }

    func setGradingBalance(_ value: Double) {
        if !isContinuousChange { recordHistory() }
        recipe.color.grading.balance = min(1, max(-1, value))
        scheduleRender()
    }

    func resetColorGrading(region: ColorGradingRegion) {
        recordHistory()
        recipe.color.grading[region] = .identity
        scheduleRender()
    }

    /// Whole Color tab back to identity in one history step.
    func resetColor() {
        guard !recipe.color.isIdentity else { return }
        recordHistory()
        recipe.color = .identity
        selectedPointColorID = nil
        scheduleRender()
    }

    func chooseCropAspect(_ aspect: CropAspect, imageAspect _: Double?) {
        guard recipe.crop.aspect != aspect else { return }
        recordHistory()
        recipe.crop.aspect = aspect
        switch aspect {
        case .free:
            // Unlocking a ratio leaves the frame alone; there is nothing to fit.
            break
        case .original:
            // `Original` means the whole frame back, the way Photos reads it —
            // fitting the image's own ratio inside whatever frame was there just
            // made the chip a shrink button.
            recipe.crop.rect = .full
        default:
            guard let ratio = aspect.ratio, ratio > 0 else { break }
            // Equal area, not inscribed: see `CropFrameGeometry`.
            recipe.crop.rect = CropFrameGeometry.rect(
                matchingRatio: ratio,
                keepingAreaOf: recipe.crop.rect,
                imageAspect: effectiveImageAspect
            )
        }
        scheduleRender()
    }

    func setCropRect(_ rect: NormalizedRect) {
        if !isContinuousChange { recordHistory() }
        recipe.crop.rect = constrainedCropRect(rect)
        scheduleRender()
    }

    /// Updates a corner while keeping its opposite corner fixed. The previous
    /// crop implementation constrained every drag around the moving rectangle's
    /// center, which made both sides drift and could make the frame jump across
    /// the image while a finger was still down.
    func setCropCorner(
        _ point: NormalizedPoint,
        fixedAnchor: NormalizedPoint,
        movesRight: Bool,
        movesDown: Bool
    ) {
        if !isContinuousChange { recordHistory() }

        let horizontalDirection = movesRight ? 1.0 : -1.0
        let verticalDirection = movesDown ? 1.0 : -1.0
        let maximumWidth = movesRight ? 1 - fixedAnchor.x : fixedAnchor.x
        let maximumHeight = movesDown ? 1 - fixedAnchor.y : fixedAnchor.y
        var width = min(
            maximumWidth,
            max(0.05, (point.x - fixedAnchor.x) * horizontalDirection)
        )
        var height = min(
            maximumHeight,
            max(0.05, (point.y - fixedAnchor.y) * verticalDirection)
        )

        if let ratio = requestedCropRatio {
            let normalizedRatio = ratio / max(0.0001, effectiveImageAspect)
            if width / max(0.0001, height) > normalizedRatio {
                height = width / normalizedRatio
            } else {
                width = height * normalizedRatio
            }
            let scale = min(
                1,
                min(
                    maximumWidth / max(0.0001, width),
                    maximumHeight / max(0.0001, height)
                )
            )
            width *= scale
            height *= scale
        }

        recipe.crop.rect = NormalizedRect(
            x: movesRight ? fixedAnchor.x : fixedAnchor.x - width,
            y: movesDown ? fixedAnchor.y : fixedAnchor.y - height,
            width: width,
            height: height
        )
        scheduleRender()
    }

    /// Drags one edge of the crop frame, keeping the opposite edge where it is.
    /// `position` is the new edge position in normalized image coordinates.
    func setCropEdge(_ edge: CropEdge, position: Double) {
        if !isContinuousChange { recordHistory() }
        let current = recipe.crop.rect
        let minimum = 0.05
        var rect = current
        switch edge {
        case .left:
            let maximumX = current.x + current.width - minimum
            let x = min(maximumX, max(0, position))
            rect.x = x
            rect.width = current.x + current.width - x
        case .right:
            let maximumEdge = min(1, max(current.x + minimum, position))
            rect.width = maximumEdge - current.x
        case .top:
            let maximumY = current.y + current.height - minimum
            let y = min(maximumY, max(0, position))
            rect.y = y
            rect.height = current.y + current.height - y
        case .bottom:
            let maximumEdge = min(1, max(current.y + minimum, position))
            rect.height = maximumEdge - current.y
        }

        // With a locked ratio, trimming one side has to resize the other axis
        // too. The axis that was not dragged grows or shrinks around its centre
        // and is then clamped back inside the image.
        if let ratio = requestedCropRatio {
            let normalizedRatio = ratio / max(0.0001, effectiveImageAspect)
            if edge.isHorizontal {
                let height = min(1, rect.width / normalizedRatio)
                let centerY = current.y + current.height / 2
                rect.height = height
                rect.y = min(1 - height, max(0, centerY - height / 2))
                rect.width = height * normalizedRatio
                if edge == .left { rect.x = current.x + current.width - rect.width }
            } else {
                let width = min(1, rect.height * normalizedRatio)
                let centerX = current.x + current.width / 2
                rect.width = width
                rect.x = min(1 - width, max(0, centerX - width / 2))
                rect.height = width / normalizedRatio
                if edge == .top { rect.y = current.y + current.height - rect.height }
            }
        }

        recipe.crop.rect = clampedInsideImage(rect)
        scheduleRender()
    }

    /// Moves the whole crop frame without resizing it — dragging inside the frame,
    /// the way Photos does it.
    func moveCropRect(dx: Double, dy: Double) {
        if !isContinuousChange { recordHistory() }
        var rect = recipe.crop.rect
        rect.x = min(1 - rect.width, max(0, rect.x + dx))
        rect.y = min(1 - rect.height, max(0, rect.y + dy))
        recipe.crop.rect = rect
        scheduleRender()
    }

    private func clampedInsideImage(_ rect: NormalizedRect) -> NormalizedRect {
        var result = rect
        result.width = min(1, max(0.05, result.width))
        result.height = min(1, max(0.05, result.height))
        result.x = min(1 - result.width, max(0, result.x))
        result.y = min(1 - result.height, max(0, result.y))
        return result
    }

    func setStraighten(_ degrees: Double) {
        if !isContinuousChange { recordHistory() }
        recipe.crop.straightenDegrees = min(45, max(-45, degrees))
        scheduleRender()
    }

    /// The framing the Crop tab opened on, plus how deep the undo stack was then —
    /// a cancelled session has to drop its own history entries too, or undo would
    /// step back into frames that no longer exist.
    private struct CropSession {
        let crop: PhotoCropRecipe
        let undoDepth: Int
    }

    /// Opened on entry to the Crop tab. Drags keep writing straight into the recipe
    /// so the preview stays live; the snapshot is what makes leaving reversible.
    private func beginCropSession() {
        guard cropSession == nil else { return }
        cropSession = CropSession(crop: recipe.crop, undoDepth: history.undoDepth)
    }

    /// `Done`, and any save: the draft framing is the framing from now on.
    func commitCropSession() {
        cropSession = nil
    }

    /// Leaving Crop any other way — another tab, or the session being closed under
    /// it — puts the framing back. A crop the user never confirmed must not ride
    /// along into the saved image. Only `crop` is restored: anything else the session
    /// touched (an undo that reached back past the frame) is the user's, not ours.
    func cancelCropSession() {
        guard let session = cropSession else { return }
        cropSession = nil
        history.rewind(toUndoDepth: session.undoDepth)
        guard recipe.crop != session.crop else { return }
        recipe.crop = session.crop
        scheduleRender()
    }

    /// Clears frame, straighten, rotation and flip in one step, back to how the
    /// photo came in — one tap instead of undoing every drag of the session.
    func resetCrop() {
        guard recipe.crop != .identity else { return }
        recordHistory()
        recipe.crop = .identity
        scheduleRender()
    }

    func rotate() {
        recordHistory()
        recipe.crop.quarterTurns = (recipe.crop.quarterTurns + 1) % 4
        scheduleRender()
    }

    func flip() {
        recordHistory()
        recipe.crop.flippedHorizontally.toggle()
        scheduleRender()
    }

    // MARK: Text and signature layers

    var selectedOverlay: PhotoOverlay? {
        guard let selectedOverlayID else { return nil }
        return recipe.overlays.first { $0.id == selectedOverlayID }
    }

    /// True while a layer is selected in the Markup tab, which is also what tells the
    /// stage to hand its gestures to the layer instead of the photo.
    var isEditingOverlay: Bool {
        selectedTool == .markup && selectedOverlayID != nil
    }

    /// What a text layer actually renders, tokens expanded. The panel rows, the
    /// on-canvas proxy and the bake all read this, so the three can never disagree
    /// about what the caption says.
    func resolvedText(for overlay: PhotoOverlay) -> String {
        guard overlay.kind == .text else { return "" }
        return OverlayTokenResolver.resolve(overlay.text, values: overlayTokens)
    }

    func addTextOverlay() {
        recordHistory()
        var overlay = PhotoOverlay.text()
        overlay.fontPostScriptName = lastFont.postScriptName
        overlay.fontFamilyName = lastFont.familyName
        overlay.fill = lastFill
        recipe.overlays.append(overlay)
        selectedOverlayID = overlay.id
        // A new caption opens straight into its detail so it can be styled once the
        // words are in.
        showsOverlayDetail = true
        selectedTool = .markup
        scheduleRender()
    }

    // MARK: Inline text entry

    /// Whether the on-photo text field is up. Like `isEditingDrawing`, a light modal
    /// sub-mode of Markup: the words are typed straight over the photo, Snapseed
    /// style, instead of in a sheet that hides the picture.
    var isEditingText = false

    /// Opens the on-photo field for the selected text layer. No history step — the
    /// commit records one.
    func beginTextEntry() {
        guard selectedOverlay?.kind == .text else { return }
        isEditingText = true
    }

    /// Writes the typed words to the selected layer and closes the field.
    func commitText(_ text: String) {
        isEditingText = false
        guard let overlay = selectedOverlay, overlay.kind == .text, overlay.text != text
        else { return }
        updateSelectedOverlay { $0.text = text }
    }

    /// Closes the field without writing. The caller decides whether a still-empty new
    /// layer should be dropped.
    func endTextEntry() {
        isEditingText = false
    }

    func addImageOverlay(imageID: UUID, assetIdentifier: String?) {
        recordHistory()
        let overlay = PhotoOverlay.image(id: imageID, assetIdentifier: assetIdentifier)
        recipe.overlays.append(overlay)
        selectedOverlayID = overlay.id
        // Placed on the photo and selected, but on the list — the user positions and
        // sizes it on the photo straight away rather than in a panel.
        showsOverlayDetail = false
        selectedTool = .markup
        scheduleRender()
    }

    /// Selecting and deselecting both re-render: the baked overlays and the live
    /// proxy trade places on the selection, so the photo underneath has to change
    /// with it. Selecting does *not* open the detail panel — that is
    /// `openOverlayDetail(_:)` — so a tap on the photo picks a layer up for moving
    /// and resizing while the list stays on screen.
    func selectOverlay(_ id: UUID?) {
        guard selectedOverlayID != id else { return }
        selectedOverlayID = id
        if id == nil { showsOverlayDetail = false }
        scheduleRender()
    }

    /// Selects a layer and opens its detail panel (content, font, sliders).
    func openOverlayDetail(_ id: UUID) {
        selectedOverlayID = id
        showsOverlayDetail = true
        scheduleRender()
    }

    /// Leaves the detail panel but keeps the layer selected, so its box and gestures
    /// stay live on the photo back at the list.
    func closeOverlayDetail() {
        showsOverlayDetail = false
    }

    /// Opens one undo step for a whole drag, pinch or slider sweep.
    ///
    /// Deliberately *not* `beginContinuousChange()`, which also kicks an
    /// interactive render. Nothing about the photo changes when a caption moves,
    /// so a render per frame buys nothing and costs the drag its frame rate.
    func beginOverlayGesture() {
        guard !isOverlayGesture else { return }
        recordHistory()
        isOverlayGesture = true
    }

    func endOverlayGesture() {
        isOverlayGesture = false
    }

    func updateSelectedOverlay(_ update: (inout PhotoOverlay) -> Void) {
        guard let index = selectedOverlayIndex else { return }
        if !isOverlayGesture, !isContinuousChange { recordHistory() }
        update(&recipe.overlays[index])
        // While a layer is selected the preview is rendered *without* overlays and
        // the stage draws them live, so the baked image is already correct — it is
        // the photo, and the photo did not change. Re-rendering here is what made
        // dragging a caption flicker: every frame swapped the preview between the
        // interactive and the settled resolution.
        guard !isEditingOverlay else { return }
        scheduleRender()
    }

    func duplicateSelectedOverlay() {
        guard let index = selectedOverlayIndex else { return }
        recordHistory()
        var copy = recipe.overlays[index]
        copy.id = UUID()
        // Offset so the copy is visibly its own layer rather than hiding exactly
        // behind the original.
        copy.center = NormalizedPoint(
            x: min(1, copy.center.x + 0.04),
            y: min(1, copy.center.y + 0.04)
        )
        recipe.overlays.insert(copy, at: index + 1)
        selectedOverlayID = copy.id
        scheduleRender()
    }

    func deleteSelectedOverlay() {
        guard let index = selectedOverlayIndex else { return }
        recordHistory()
        recipe.overlays.remove(at: index)
        selectedOverlayID = nil
        scheduleRender()
    }

    func toggleSelectedOverlayVisibility() {
        updateSelectedOverlay { $0.isVisible.toggle() }
    }

    /// Layers are drawn back to front, so "forward" is later in the array.
    func moveSelectedOverlayForward() {
        guard let index = selectedOverlayIndex, index < recipe.overlays.count - 1 else { return }
        recordHistory()
        recipe.overlays.swapAt(index, index + 1)
        scheduleRender()
    }

    func moveSelectedOverlayBackward() {
        guard let index = selectedOverlayIndex, index > 0 else { return }
        recordHistory()
        recipe.overlays.swapAt(index, index - 1)
        scheduleRender()
    }

    // MARK: Layer-row actions, targeted by id so they never open a layer's detail.

    private func overlayIndex(id: UUID) -> Int? {
        recipe.overlays.firstIndex { $0.id == id }
    }

    func deleteOverlay(id: UUID) {
        guard let index = overlayIndex(id: id) else { return }
        recordHistory()
        recipe.overlays.remove(at: index)
        if selectedOverlayID == id { selectedOverlayID = nil }
        scheduleRender()
    }

    func toggleOverlayVisibility(id: UUID) {
        guard let index = overlayIndex(id: id) else { return }
        recordHistory()
        recipe.overlays[index].isVisible.toggle()
        scheduleRender()
    }

    /// Layers are drawn back to front, so "forward" is later in the array.
    func moveOverlay(id: UUID, forward: Bool) {
        guard let index = overlayIndex(id: id) else { return }
        let target = forward ? index + 1 : index - 1
        guard recipe.overlays.indices.contains(target) else { return }
        recordHistory()
        recipe.overlays.swapAt(index, target)
        scheduleRender()
    }

    func canMoveOverlay(id: UUID, forward: Bool) -> Bool {
        guard let index = overlayIndex(id: id) else { return false }
        return forward ? index < recipe.overlays.count - 1 : index > 0
    }

    /// Drag-to-reorder from the layer list. The list shows the overlays front-to-back
    /// (`reversed()`), so the offsets arrive in that display order and are mapped
    /// back onto the stored back-to-front array.
    func moveOverlays(fromDisplay source: IndexSet, toDisplay destination: Int) {
        var displayed = Array(recipe.overlays.reversed())
        guard !displayed.isEmpty else { return }
        displayed.move(fromOffsets: source, toOffset: destination)
        recordHistory()
        recipe.overlays = Array(displayed.reversed())
        scheduleRender()
    }

    /// Nudges the selected layer by a normalized delta. Clamped to the frame: a
    /// layer dragged off the photo would be unreachable afterwards.
    func moveSelectedOverlay(dx: Double, dy: Double) {
        updateSelectedOverlay { overlay in
            overlay.center = NormalizedPoint(
                x: min(1, max(0, overlay.center.x + dx)),
                y: min(1, max(0, overlay.center.y + dy))
            )
        }
    }

    /// Sets the selected layer's centre absolutely — the on-photo drag positions
    /// from a fixed start rather than accumulating per-frame deltas.
    func moveSelectedOverlay(toCenter center: NormalizedPoint) {
        updateSelectedOverlay { overlay in
            overlay.center = NormalizedPoint(
                x: min(1, max(0, center.x)),
                y: min(1, max(0, center.y))
            )
        }
    }

    /// Stamps a saved signature onto this photo. Appended rather than replacing, so
    /// applying a signature never silently discards a caption already in place.
    /// Fresh ids: the same signature can be applied twice, and undo has to be able
    /// to tell the two apart.
    func applySignature(_ preset: SignaturePreset) {
        guard !preset.layers.isEmpty else { return }
        recordHistory()
        let stamped = preset.layers.map { layer in
            var copy = layer
            copy.id = UUID()
            return copy
        }
        recipe.overlays.append(contentsOf: stamped)
        selectedOverlayID = stamped.last?.id
        showsOverlayDetail = false
        selectedTool = .markup
        scheduleRender()
    }

    // MARK: - Drawing (Markup)

    /// Whether the freehand drawing sub-mode is up. A modal takeover of the Markup
    /// tab, on the same pattern as Crop: the tab bar and panel step aside, the
    /// `PKCanvasView` and its tool picker own the photo, and Clear / Done are the
    /// only ways out.
    var isEditingDrawing = false

    var hasDrawing: Bool { !(recipe.drawing?.isEmpty ?? true) }

    /// The strokes the canvas should open with — the current drawing, so reopening
    /// the tool continues the same drawing rather than starting a blank one.
    var drawingData: Data? { recipe.drawing?.data }

    /// Enters the drawing sub-mode. No history step: nothing changes until Done.
    func beginDrawing() {
        selectOverlay(nil)
        selectedTool = .markup
        isEditingDrawing = true
    }

    /// Leaves the drawing sub-mode, keeping whatever the canvas ended on.
    ///
    /// `data` is `PKDrawing.dataRepresentation()` and `canvasSize` the points the
    /// canvas used, so the renderer can scale the vector to any resolution. An empty
    /// drawing becomes `nil`, so it adds no key to the recipe. One history step for
    /// the whole session, like a crop's Done.
    func commitDrawing(data: Data, canvasSize: CGSize) {
        let next: PhotoDrawing? = data.isEmpty ? nil : PhotoDrawing(
            data: data,
            canvasWidth: Double(canvasSize.width),
            canvasHeight: Double(canvasSize.height)
        )
        isEditingDrawing = false
        guard next != recipe.drawing else { return }
        recordHistory()
        recipe.drawing = next
        scheduleRender()
    }

    /// Drops the drawing entirely. Used by the layer row's Delete and by Clear.
    func clearDrawing() {
        guard recipe.drawing != nil else { return }
        recordHistory()
        recipe.drawing = nil
        scheduleRender()
    }

    var drawingIsVisible: Bool { recipe.drawing?.isVisible ?? false }

    /// The drawing layer's eye toggle. The strokes stay in the recipe when hidden.
    func toggleDrawingVisibility() {
        guard recipe.drawing != nil else { return }
        recordHistory()
        recipe.drawing?.isVisible.toggle()
        scheduleRender()
    }

    private var selectedOverlayIndex: Int? {
        guard let selectedOverlayID else { return nil }
        return recipe.overlays.firstIndex { $0.id == selectedOverlayID }
    }

    // MARK: Masks

    func addMask(kind: PhotoMaskComponentKind) {
        recordHistory()
        let component = PhotoMaskComponent(kind: kind)
        let number = recipe.masks.count + 1
        let mask = PhotoMask(name: "\(kind.displayName) \(number)", component: component)
        recipe.masks.append(mask)
        selectedMaskID = mask.id
        selectedComponentID = component.id
        selectedTool = .masks
        markAwaitingPlacement(component)
        revealMaskShape()
    }

    /// True while the selected gradient is still waiting for its first placement
    /// drag. The stage reads this to pick between place and move.
    var selectedComponentAwaitsPlacement: Bool {
        guard let component = selectedComponent else { return false }
        return unplacedComponentIDs.contains(component.id)
    }

    private func markAwaitingPlacement(_ component: PhotoMaskComponent) {
        guard component.kind == .linearGradient || component.kind == .radialGradient
        else { return }
        unplacedComponentIDs.insert(component.id)
    }

    /// Shifts every anchor of the selected component by a normalized delta — the
    /// whole-shape move behind "drag anywhere on the photo". Both gradient ends
    /// clamp independently, same as the guide knobs.
    func moveSelectedComponent(dx: Double, dy: Double) {
        func shifted(_ point: NormalizedPoint) -> NormalizedPoint {
            NormalizedPoint(
                x: min(1, max(0, point.x + dx)),
                y: min(1, max(0, point.y + dy))
            )
        }
        switch selectedComponent?.kind {
        case .linearGradient:
            updateSelectedComponent {
                $0.startPoint = shifted($0.startPoint)
                $0.endPoint = shifted($0.endPoint)
            }
        case .radialGradient:
            updateSelectedComponent {
                $0.center = shifted($0.center)
            }
        default:
            break
        }
    }

    func selectMask(_ id: UUID) {
        selectedMaskID = id
        selectedComponentID = recipe.masks.first(where: { $0.id == id })?.components.first?.id
        revealMaskShape()
        scheduleRender()
    }

    func selectComponent(_ id: UUID) {
        selectedComponentID = id
    }

    func renameSelectedMask(_ name: String) {
        guard let index = selectedMaskIndex else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recordHistory()
        recipe.masks[index].name = trimmed
    }

    func duplicateSelectedMask() {
        guard let index = selectedMaskIndex else { return }
        recordHistory()
        var copy = recipe.masks[index]
        copy.id = UUID()
        copy.name += " Copy"
        copy.components = copy.components.map {
            var component = $0
            component.id = UUID()
            return component
        }
        recipe.masks.insert(copy, at: index + 1)
        selectedMaskID = copy.id
        selectedComponentID = copy.components.first?.id
        scheduleRender()
    }

    func invertSelectedMask() {
        guard let index = selectedMaskIndex else { return }
        recordHistory()
        recipe.masks[index].isInverted.toggle()
        revealMaskShape()
        scheduleRender()
    }

    /// Ticking the effect back on re-reveals the red overlay — the user is about
    /// to judge the area again. Unticking hides it on the spot: leaving the tint
    /// up made "did the untick work?" unanswerable, and it was also the source
    /// of the reverse confusion — an eye switched on later while the guard
    /// against effect-off masks quietly refused to draw anything.
    func toggleSelectedMaskVisibility() {
        guard let index = selectedMaskIndex else { return }
        recordHistory()
        recipe.masks[index].isVisible.toggle()
        if recipe.masks[index].isVisible {
            revealMaskShape()
        } else {
            showsMaskOverlay = false
        }
        scheduleRender()
    }

    func deleteSelectedMask() {
        guard let index = selectedMaskIndex else { return }
        recordHistory()
        recipe.masks.remove(at: index)
        selectedMaskID = recipe.masks.indices.contains(index)
            ? recipe.masks[index].id
            : recipe.masks.last?.id
        selectedComponentID = selectedMask?.components.first?.id
        scheduleRender()
    }

    func deleteSelectedComponent() {
        guard let maskIndex = selectedMaskIndex,
              let componentIndex = selectedComponentIndex
        else { return }
        recordHistory()
        recipe.masks[maskIndex].components.remove(at: componentIndex)
        if recipe.masks[maskIndex].components.isEmpty {
            recipe.masks.remove(at: maskIndex)
            selectedMaskID = recipe.masks.last?.id
        }
        selectedComponentID = selectedMask?.components.first?.id
        scheduleRender()
    }

    func updateSelectedComponent(_ update: (inout PhotoMaskComponent) -> Void) {
        guard let maskIndex = selectedMaskIndex,
              let componentIndex = selectedComponentIndex
        else { return }
        if !isContinuousChange { recordHistory() }
        update(&recipe.masks[maskIndex].components[componentIndex])
        // Any shape edit counts as placement: once the user has touched a knob or
        // placed a drag, the next photo drag must move, never rebuild.
        unplacedComponentIDs.remove(recipe.masks[maskIndex].components[componentIndex].id)
        revealMaskShape()
        scheduleRender()
    }

    /// `zoomScale` is what the photo is pinched to. The Size slider is a screen
    /// size, so the stroke records a proportionally smaller image-relative one —
    /// that is what lets a zoomed-in brush reach detail it could not otherwise.
    func beginBrushStroke(at point: NormalizedPoint, zoomScale: CGFloat = 1) {
        guard selectedComponent?.kind == .brush,
              let maskIndex = selectedMaskIndex,
              let componentIndex = selectedComponentIndex
        else { return }
        beginContinuousChange()
        revealMaskShape()
        let stroke = BrushStroke(
            points: [point],
            size: EditorLayoutMetrics.paintedSize(brushSize, zoomScale: zoomScale),
            feather: brushFeather,
            flow: brushFlow,
            isEraser: brushIsEraser
        )
        recipe.masks[maskIndex].components[componentIndex].brushStrokes.append(stroke)
        activeBrushStrokeIndex =
            recipe.masks[maskIndex].components[componentIndex].brushStrokes.count - 1
        scheduleRender(delay: .milliseconds(30))
    }

    func continueBrushStroke(at point: NormalizedPoint) {
        guard let maskIndex = selectedMaskIndex,
              let componentIndex = selectedComponentIndex,
              let activeBrushStrokeIndex,
              recipe.masks[maskIndex].components[componentIndex].brushStrokes.indices
                .contains(activeBrushStrokeIndex)
        else { return }
        var stroke = recipe.masks[maskIndex].components[componentIndex]
            .brushStrokes[activeBrushStrokeIndex]
        if let last = stroke.points.last {
            let distance = hypot(point.x - last.x, point.y - last.y)
            guard distance > 0.002 else { return }
        }
        stroke.points.append(point)
        recipe.masks[maskIndex].components[componentIndex]
            .brushStrokes[activeBrushStrokeIndex] = stroke
        scheduleRender(delay: .milliseconds(40))
    }

    func endBrushStroke() {
        activeBrushStrokeIndex = nil
        endContinuousChange()
        scheduleRender()
    }

    /// The touch turned out to be a pinch: a second finger landed, so the stroke
    /// it opened is thrown away along with the history entry it recorded. Without
    /// this, every zoom inside the mask brush left a dab of paint behind and cost
    /// an undo to clear.
    func cancelBrushStroke() {
        defer {
            activeBrushStrokeIndex = nil
            isContinuousChange = false
        }
        guard let maskIndex = selectedMaskIndex,
              let componentIndex = selectedComponentIndex,
              let activeBrushStrokeIndex,
              recipe.masks[maskIndex].components[componentIndex].brushStrokes.indices
                .contains(activeBrushStrokeIndex)
        else { return }
        recipe.masks[maskIndex].components[componentIndex]
            .brushStrokes.remove(at: activeBrushStrokeIndex)
        history.discardLast(matching: recipe)
        scheduleRender()
    }

    func setAutomaticMaskPoint(_ point: NormalizedPoint) {
        guard let component = selectedComponent,
              component.kind == .subject || component.kind == .colorRange
        else { return }
        if component.kind == .subject {
            updateSelectedComponent { $0.subjectPoint = point }
        } else if let color = samplePreviewColor(at: point) {
            updateSelectedComponent {
                $0.sampledRed = color.red
                $0.sampledGreen = color.green
                $0.sampledBlue = color.blue
            }
        }
    }

    func setGradient(start: NormalizedPoint, end: NormalizedPoint) {
        guard let component = selectedComponent else { return }
        switch component.kind {
        case .linearGradient:
            updateSelectedComponent {
                $0.startPoint = start
                $0.endPoint = end
            }
        case .radialGradient:
            let dx = end.x - start.x
            let dy = end.y - start.y
            updateSelectedComponent {
                $0.center = start
                $0.radiusX = min(1, max(0.02, abs(dx)))
                $0.radiusY = min(1, max(0.02, abs(dy)))
            }
        default:
            break
        }
    }

    // MARK: Render/save

    func scheduleRender(delay: Duration = .milliseconds(90)) {
        if isContinuousChange {
            scheduleInteractiveRender()
            return
        }

        cancelInteractiveRender()
        renderTask?.cancel()
        renderGeneration += 1
        let generation = renderGeneration
        renderTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await self.renderPreview(
                generation: generation,
                maximumDimension: self.settleDimension
            )
        }
    }

    func renderNow() async {
        renderTask?.cancel()
        cancelInteractiveRender()
        renderGeneration += 1
        await renderPreview(
            generation: renderGeneration,
            maximumDimension: settleDimension
        )
    }

    func saveCopy(format: PhotoOutputFormat, includeMetadata: Bool) async {
        guard let session, let loadedSource else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let result = try await service.saveCopy(
                session: session,
                source: loadedSource,
                recipe: recipe,
                renderRecipe: renderReady(recipe),
                requestedFormat: format,
                includeMetadata: includeMetadata,
                album: sourceAlbum
            )
            didFallbackToJPEG = result.fellBackToJPEG
            savedAssetID = result.assetID
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveChanges(format: PhotoOutputFormat, includeMetadata: Bool) async {
        guard let session, let loadedSource else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let result = try await service.saveChanges(
                session: session,
                source: loadedSource,
                recipe: recipe,
                renderRecipe: renderReady(recipe),
                requestedFormat: format,
                includeMetadata: includeMetadata
            )
            didFallbackToJPEG = result.fellBackToJPEG
            savedAssetID = result.assetID
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func scheduleInteractiveRender() {
        renderTask?.cancel()
        renderTask = nil
        interactiveRenderPending = true
        guard interactiveRenderTask == nil else { return }

        renderGeneration += 1
        let generation = renderGeneration
        interactiveRenderTask = Task { [weak self] in
            guard let self else { return }
            await self.runInteractiveRenderLoop(generation: generation)
        }
    }

    private func runInteractiveRenderLoop(generation: Int) async {
        while !Task.isCancelled, generation == renderGeneration {
            guard interactiveRenderPending else { break }
            interactiveRenderPending = false
            let isInteractive = isContinuousChange
            let changesRAWDemosaic = isInteractive
                && isRAWSource
                && selectedAdjustment.affectsRAWDemosaic
            let maximumDimension: CGFloat
            if isInteractive {
                maximumDimension = interactiveEdge(changesRAWDemosaic: changesRAWDemosaic)
            } else {
                maximumDimension = settleDimension
                frozenInteractiveEdge = nil
            }
            await renderPreview(
                generation: generation,
                maximumDimension: maximumDimension,
                usesInteractiveBase: isInteractive
            )
            await Task.yield()
        }

        guard generation == renderGeneration else { return }
        interactiveRenderTask = nil
        if interactiveRenderPending {
            scheduleInteractiveRender()
        }
    }

    private func updatePreviewAspect(from size: CGSize, recipe: PhotoEditRecipe) {
        guard size.width > 0, size.height > 0 else { return }
        let crop = recipe.crop
        let signature = [
            recipe.sourceFilename ?? "",
            "\(crop.rect.x),\(crop.rect.y),\(crop.rect.width),\(crop.rect.height)",
            "\(crop.straightenDegrees),\(crop.quarterTurns),\(crop.flippedHorizontally)"
        ].joined(separator: "|")
        guard signature != previewAspectSignature else { return }
        previewAspectSignature = signature
        previewAspectRatio = size.width / size.height
    }

    // MARK: - Interactive resolution

    /// Longest edge, in pixels, of the preview rendered while a finger is still
    /// moving: **always the size the photo is actually displayed at**, pushed in by
    /// the stage as `displayEdge`.
    ///
    /// It used to be a flat 1024, which is below the display on any modern phone, so
    /// every slider drag visibly softened the picture and it snapped back sharp on
    /// release. Dropping resolution is not an option here — the whole point of a
    /// live preview is judging the photo — so smoothness comes from *rate* instead:
    /// the render loop coalesces, keeping only the latest recipe, so a heavy recipe
    /// draws fewer frames per second rather than a smaller picture.
    private func interactiveEdge(changesRAWDemosaic: Bool) -> CGFloat {
        // Re-demosaicing a RAW per frame is in another cost class entirely; that
        // path keeps its own draft ceiling.
        guard !changesRAWDemosaic else { return Self.rawDemosaicEdge }
        // Frozen for the whole gesture anyway: if the stage were to resize mid-drag,
        // re-rendering at a new pixel size would resample the photo differently and
        // — at 800% zoom especially — read as the picture twitching.
        if let frozenInteractiveEdge { return frozenInteractiveEdge }
        // A zoomed stage can ask for more than the settle size; a *drag* still
        // stops there, because paying for 4800px per frame would cost the frame
        // rate the interactive render exists to protect.
        let edge = min(Self.settleEdge, displayEdge)
        frozenInteractiveEdge = edge
        return edge
    }

    /// Size the render that stays on screen aims for: the settle size normally, and
    /// the display size when the photo is pinched open past it.
    private var settleDimension: CGFloat {
        max(Self.settleEdge, displayEdge)
    }

    /// Called by the stage: how large the photo is actually drawn, in pixels, zoom
    /// included. This is what a render targets — never less.
    func setDisplaySize(_ size: CGSize, scale: CGFloat) {
        let edge = max(size.width, size.height) * max(1, scale)
        guard edge > 0 else { return }
        let clamped = min(
            Self.zoomedSettleEdge,
            max(Self.minimumInteractiveEdge, edge.rounded())
        )
        guard abs(clamped - displayEdge) >= 1 else { return }
        displayEdge = clamped
    }

    private func cancelInteractiveRender() {
        interactiveRenderTask?.cancel()
        interactiveRenderTask = nil
        interactiveRenderPending = false
    }

    private func renderPreview(
        generation: Int,
        maximumDimension: CGFloat = settleEdge,
        usesInteractiveBase: Bool = false
    ) async {
        guard let loadedSource else { return }
        isRendering = true
        do {
            var previewRecipe = recipe
            if selectedTool == .crop {
                // Crop handles operate in the uncropped source coordinate
                // space. Local masks are hidden only while framing so their
                // post-crop normalized coordinates are not drawn in the wrong
                // coordinate system.
                previewRecipe.crop.rect = .full
                previewRecipe.crop.aspect = .free
                previewRecipe.masks = []
                // Overlays and the drawing are normalized against the cropped frame
                // too, and would only be in the way over the framing grid.
                previewRecipe.overlays = []
                previewRecipe.drawing = nil
            }
            // A selected layer is drawn live by the stage instead, so the bake
            // steps aside — otherwise the caption appears twice while it is being
            // moved, once where it was and once where it is going.
            if isEditingOverlay { previewRecipe.overlays = [] }
            // The canvas draws its own strokes live while a drawing is being made,
            // so the baked drawing steps aside to avoid a doubled image.
            if isEditingDrawing { previewRecipe.drawing = nil }
            previewRecipe = renderReady(previewRecipe)
            // Only inside the single-mask editor: the list level is for choosing
            // a mask, and `selectMask` flips `showsMaskOverlay` on for the row
            // taps too — without the `editingMaskAdjustments` gate that tinted
            // the photo red while the user was still just browsing the list.
            let showsOverlay = showsMaskOverlay
                && selectedTool == .masks
                && editingMaskAdjustments
            let preview = if usesInteractiveBase {
                try await service.renderer.renderInteractivePreviewImages(
                    source: loadedSource.info,
                    recipe: previewRecipe,
                    maximumDimension: maximumDimension,
                    cachesBase: !(
                        isRAWSource && selectedAdjustment.affectsRAWDemosaic
                    ),
                    showsMaskOverlay: showsOverlay,
                    selectedMaskID: selectedMaskID
                )
            } else {
                try await service.renderer.renderPreviewImages(
                    source: loadedSource.info,
                    recipe: previewRecipe,
                    maximumDimension: maximumDimension,
                    showsMaskOverlay: showsOverlay,
                    selectedMaskID: selectedMaskID
                )
            }
            guard generation == renderGeneration else { return }
            let image = UIImage(cgImage: preview.displayImage)
            updatePreviewAspect(from: image.size, recipe: previewRecipe)
            editedPreviewImage = image
            colorSamplingImage = preview.cleanImage
            await updateHistogram()
            if !isContinuousChange {
                refreshMaskThumbnails()
                refreshFilterThumbnails()
            }
        } catch {
            guard generation == renderGeneration else { return }
            errorMessage = error.localizedDescription
        }
        if generation == renderGeneration {
            isRendering = false
        }
    }

    /// The histogram always describes the whole photo — not the part of it that
    /// happens to be on screen, and not the selected mask either. Zooming in to
    /// check detail, or opening a mask, must not change what the card says about
    /// the exposure of the frame.
    private func updateHistogram() async {
        guard let colorSamplingImage else { return }
        histogram = await service.renderer.histogram(of: colorSamplingImage)
    }

    /// Mask rows show the real shape of their mask. Thumbnails are rebuilt only
    /// when the mask set or its geometry actually changed, never per slider frame.
    private func refreshMaskThumbnails() {
        guard let loadedSource else { return }
        guard !recipe.masks.isEmpty else {
            maskThumbnailSignature = ""
            maskThumbnails = [:]
            return
        }
        let signature = maskGeometrySignature(for: recipe)
        guard signature != maskThumbnailSignature else { return }
        maskThumbnailSignature = signature
        maskThumbnailTask?.cancel()
        let recipe = recipe
        let info = loadedSource.info
        maskThumbnailTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resolved = try await service.renderer.maskThumbnails(
                    source: info,
                    recipe: recipe
                )
                guard !Task.isCancelled else { return }
                maskThumbnails = resolved.images.mapValues { UIImage(cgImage: $0) }
            } catch {
                // A missing thumbnail only costs the row its preview image.
            }
        }
    }

    /// Renders the swatches for the strip on screen, if they are not already there.
    /// Called when the Filters tab appears, when the strip changes, and after every
    /// settled render — a swatch has to show the photo as it is now, not as it was
    /// before the exposure moved.
    func refreshFilterThumbnails() {
        guard selectedTool == .filters, let loadedSource else { return }
        let signature = filterThumbnailBaseSignature(for: recipe)
        if signature != filterThumbnailSignature {
            filterThumbnailSignature = signature
            // Tone, colour or framing moved, so every swatch already rendered —
            // including the strips not on screen — describes an older photo.
            filterThumbnails = [:]
        }
        let filters = PhotoFilter.all(in: selectedFilterCategory)
        guard filters.contains(where: { filterThumbnails[$0] == nil }) else { return }
        filterThumbnailTask?.cancel()
        let recipe = recipe
        let info = loadedSource.info
        filterThumbnailTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resolved = try await service.renderer.filterThumbnails(
                    source: info,
                    recipe: recipe,
                    filters: filters
                )
                guard !Task.isCancelled, signature == filterThumbnailSignature else { return }
                filterThumbnails.merge(
                    resolved.images.mapValues { UIImage(cgImage: $0) },
                    uniquingKeysWith: { _, rendered in rendered }
                )
            } catch {
                // Swatches are a nicety: the strip falls back to drawing each look
                // as a two-tone gradient instead.
            }
        }
    }

    /// Everything *under* the filter — tone, the Color tab, framing, which file is
    /// being edited. Deliberately not the filter or its intensity: those are what
    /// the swatches are showing, and changing them must not rebuild them.
    private func filterThumbnailBaseSignature(for recipe: PhotoEditRecipe) -> String {
        [
            "\(recipe.source)",
            recipe.sourceFilename ?? "",
            "\(recipe.adjustments)",
            "\(recipe.color)",
            "\(recipe.crop)",
        ].joined(separator: "#")
    }

    private func maskGeometrySignature(for recipe: PhotoEditRecipe) -> String {
        var parts: [String] = ["\(recipe.crop)"]
        for mask in recipe.masks {
            parts.append("\(mask.id)|\(mask.isInverted)|\(mask.isVisible)")
            for component in mask.components {
                parts.append("\(component)")
            }
        }
        return parts.joined(separator: "#")
    }

    private func renderOriginal() async {
        guard let loadedSource else { return }
        var identity = PhotoEditRecipe.identity
        identity.source = recipe.source
        identity.sourceFilename = recipe.sourceFilename
        do {
            let cgImage = try await service.renderer.renderPreview(
                source: loadedSource.info,
                recipe: identity,
                maximumDimension: Self.settleEdge
            )
            originalPreviewImage = UIImage(cgImage: cgImage)
            await service.renderer.installInteractiveBase(
                cgImage,
                source: loadedSource.info,
                recipe: identity
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recordHistory() {
        guard !isContinuousChange else { return }
        history.record(recipe)
    }

    /// The recipe as the renderer needs it: text layers carry expanded tokens
    /// rather than `{camera}` templates.
    ///
    /// Every render and every save goes through here. The stored recipe keeps the
    /// template — it is what gets written into the photo's adjustment data, and
    /// reopening the edit has to show the tokens the user typed, not the values
    /// they happened to expand to.
    private func renderReady(_ recipe: PhotoEditRecipe) -> PhotoEditRecipe {
        guard recipe.overlays.contains(where: { $0.kind == .text }) else { return recipe }
        var resolved = recipe
        resolved.overlays = recipe.overlays.map { overlay in
            guard overlay.kind == .text else { return overlay }
            var copy = overlay
            copy.text = resolvedText(for: overlay)
            return copy
        }
        return resolved
    }

    private var selectedMaskIndex: Int? {
        guard let selectedMaskID else { return nil }
        return recipe.masks.firstIndex { $0.id == selectedMaskID }
    }

    private var selectedComponentIndex: Int? {
        guard let maskIndex = selectedMaskIndex, let selectedComponentID else { return nil }
        return recipe.masks[maskIndex].components.firstIndex { $0.id == selectedComponentID }
    }

    private func repairSelection() {
        if let selectedMaskID,
           !recipe.masks.contains(where: { $0.id == selectedMaskID }) {
            self.selectedMaskID = recipe.masks.first?.id
        }
        if let selectedComponentID,
           selectedMask?.components.contains(where: { $0.id == selectedComponentID }) != true {
            self.selectedComponentID = selectedMask?.components.first?.id
        }
        if let selectedPointColorID,
           !recipe.color.points.contains(where: { $0.id == selectedPointColorID }) {
            self.selectedPointColorID = recipe.color.points.last?.id
        }
        // Deselected rather than moved to a neighbour: undoing past a layer's
        // creation should leave the Text tab at its list, not silently editing a
        // different caption.
        if let selectedOverlayID,
           !recipe.overlays.contains(where: { $0.id == selectedOverlayID }) {
            self.selectedOverlayID = nil
        }
    }

    private func constrainedCropRect(_ rect: NormalizedRect) -> NormalizedRect {
        var width = min(1, max(0.05, rect.width))
        var height = min(1, max(0.05, rect.height))
        if let ratio = requestedCropRatio {
            let normalizedRatio = ratio / max(0.0001, effectiveImageAspect)
            if width / height > normalizedRatio {
                width = height * normalizedRatio
            } else {
                height = width / normalizedRatio
            }
        }
        let centerX = rect.x + rect.width / 2
        let centerY = rect.y + rect.height / 2
        return NormalizedRect(
            x: min(1 - width, max(0, centerX - width / 2)),
            y: min(1 - height, max(0, centerY - height / 2)),
            width: width,
            height: height
        )
    }

    private var effectiveImageAspect: Double {
        let baseAspect: Double
        if let originalPreviewImage {
            baseAspect = Double(
                originalPreviewImage.size.width / max(1, originalPreviewImage.size.height)
            )
        } else if let info = loadedSource?.info {
            let encodedAspect = Double(max(1, info.pixelWidth))
                / Double(max(1, info.pixelHeight))
            switch info.orientation {
            case .left, .leftMirrored, .right, .rightMirrored:
                baseAspect = 1 / encodedAspect
            default:
                baseAspect = encodedAspect
            }
        } else {
            baseAspect = 1
        }
        return recipe.crop.quarterTurns.isMultiple(of: 2)
            ? baseAspect
            : 1 / baseAspect
    }

    private var requestedCropRatio: Double? {
        if let ratio = recipe.crop.aspect.ratio { return ratio }
        return recipe.crop.aspect == .original ? effectiveImageAspect : nil
    }

    private func samplePreviewColor(at point: NormalizedPoint)
        -> (red: Double, green: Double, blue: Double)? {
        guard let cgImage = colorSamplingImage else { return nil }
        let x = min(cgImage.width - 1, max(0, Int(point.x * Double(cgImage.width))))
        let y = min(cgImage.height - 1, max(0, Int(point.y * Double(cgImage.height))))
        guard let cropped = cgImage.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))
        else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        return pixel.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: 1,
                      height: 1,
                      bitsPerComponent: 8,
                      bytesPerRow: 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return nil }
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            let values = bytes.bindMemory(to: UInt8.self)
            return (
                Double(values[0]) / 255,
                Double(values[1]) / 255,
                Double(values[2]) / 255
            )
        }
    }
}

// MARK: - Tone curve

extension PhotoEditorController {
    /// Replace one channel's control points. The full-screen curve editor calls
    /// this live inside a `beginContinuousChange` / `endContinuousChange` bracket,
    /// exactly like the grading rows, so a drag coalesces into one undo step.
    func setCurve(_ points: [CurvePoint], for channel: ToneCurveChannel) {
        recipe.curve[channel] = points
        scheduleRender()
    }

    /// Straighten one channel back to the identity line.
    func resetCurve(_ channel: ToneCurveChannel) {
        beginContinuousChange()
        recipe.curve[channel] = ToneCurveAdjustments.linear
        endContinuousChange()
        scheduleRender()
    }

    /// Straighten every channel.
    func resetAllCurves() {
        beginContinuousChange()
        recipe.curve = .identity
        endContinuousChange()
        scheduleRender()
    }
}
