import SwiftUI
import ShotDexKit

/// Presentation state of the editor chrome: which nav group is showing, which
/// slider owns the gesture, whether the image is full-bleed, and which sheet is
/// up. Kept apart from `PhotoEditorController` so a pan never has to touch the
/// render pipeline's state.
@MainActor
@Observable
final class EditorChromeModel {
    struct UndoToast: Identifiable {
        let id = UUID()
        let message: String
    }

    /// Which 28c bottom-nav group is showing. Drives the panel content; the six
    /// adjustment groups all sit on the controller's global `.adjust` tool.
    var selectedGroup: EditorGroup = .light
    /// Where the phone's Edit list is — the group at its top — kept for the
    /// session so leaving Edit and coming back lands in the same place
    /// (FS-03.13b §1). Never in the recipe or the history.
    var editListGroup: EditorGroup?
    /// The exact scroll offset of the Edit list when it was left, for as long
    /// as `editListGroup` is still the group it was taken at — "same place"
    /// means the same pixel, not the top of the group (FS-03.13b AC-18).
    var editListOffset: EditorListOffset?
    /// The phone panel's height this frame (344 / 264 / 315), for what parks
    /// above it.
    var phonePanelHeight: CGFloat = EditorLayoutMetrics.phonePanelShort
    /// A group the list should scroll to (a chip tapped on the wheel).
    var editListScrollRequest: EditorGroup?
    /// The same two for the Transform list (FS-03.13b §3).
    var transformListSection: EditorTransformSection?
    var transformListScrollRequest: EditorTransformSection?
    var transformListOffset: EditorListOffset?
    /// Straighten Tool on: one finger on the photo draws a ruler instead of
    /// moving the crop frame. Off whenever Transform is left.
    var isStraightenToolOn = false
    /// The Mask tool's list of masks, opened from the name in its top row
    /// (FS-03.13c §2).
    var isMaskListOpen = false
    /// Add / Subtract / Intersect area picked in that list: the chooser grid
    /// then adds an area to the selected mask instead of making a mask.
    var maskAreaOperation: MaskBlendOperation?
    /// Size is being changed from the brush row: the stage shows the brush
    /// ring in the middle of the photo (FS-03.13c §3).
    var showsBrushSizePreview = false
    /// The Markup tool's list of layers, opened from the name in its top row.
    var isLayerListOpen = false
    /// The window's trailing safe-area inset: 84 on the Duo's cover, where
    /// iOS puts its rail (FS-03.13d §3).
    var windowTrailingInset: CGFloat = 0
    /// Floating histogram card. It sits over the photo when expanded and parks as
    /// a pill in the action bar when collapsed. Collapsed on open — the photo is
    /// what the editor is for, so nothing covers it until the user asks.
    var isHistogramCollapsed = true
    /// Corner the card snaps to when let go. Persisted so it reopens where it was
    /// last parked.
    var histogramCorner: EditorHistogramCorner = EditorChromeModel.storedHistogramCorner {
        didSet {
            UserDefaults.standard.set(histogramCorner.rawValue, forKey: Self.histogramCornerKey)
        }
    }
    /// Live finger offset while the card is being dragged; nil when parked.
    var histogramDragOffset: CGSize?

    /// Sections open in the wide-screen sidebar. Several at once, the way
    /// Lightroom's develop panels stack — unlike the phone's group wheel, where
    /// the screen only has room for one group at a time. Session state: which
    /// panels a photo needs is a property of the edit, not of the app.
    ///
    /// Starts **empty** (2026-09-22). Opening on Light looked helpful and was
    /// not: Light alone is 441pt, which on an 834pt window pushed six of the
    /// other seven headers past the bottom of the panel, so the editor opened
    /// having hidden most of itself. Closed, every section name is on screen at
    /// once and the first tap is a choice rather than a scroll.
    var expandedSidebarGroups: Set<EditorGroup> = []

    /// The section the list should bring to the top, set the moment one is
    /// opened and cleared as soon as the scroll runs. A section opened from the
    /// bottom of the panel otherwise unfolds below the fold, and the person
    /// scrolls to find rows their own tap just made.
    var sectionToScrollTo: EditorGroup?

    /// Which colour band the wide sidebar's Mix section is working on, or nil
    /// for the all-channels list. The swatch row is Lightroom's arrangement and
    /// the reason it fits: eight bands × three properties is twenty-four rows,
    /// which is more than the panel is tall, and picking the band first turns it
    /// into three. The all-channels list stays one tap away (the "All" chip) and
    /// is still the phone's only mode, where there is no room for a swatch row.
    var sidebarMixBand: ColorMixerBand? = .red

    /// True while the editor is laid out for a wide window (the sidebar beside
    /// the photo rather than a slab under it). The stage reads it for the two
    /// things that differ there: the tone-curve graph moves into the sidebar,
    /// and a double tap fills the canvas instead of hiding chrome the sidebar's
    /// own collapse control already hides.
    var isWideLayout = false

    /// Bumped when something outside the stage asks for fit ⇄ fill — the
    /// sidebar's zoom button. The stage owns the geometry the fill factor is
    /// computed from, so the request travels as a token rather than a scale.
    private(set) var fillZoomToken = 0

    func requestFillZoomToggle() {
        fillZoomToken &+= 1
    }

    var isFullBleed = false
    var showsSplitCompare = false
    var splitFraction = 0.5
    var zoomScale: CGFloat = 1
    var zoomOffset = CGSize.zero

    /// Non-nil while a finger owns a slider: the row highlights and the panel's
    /// scrolling is locked out. The panel itself does not move.
    var activeSlider: PhotoAdjustmentKind?

    var isNewMaskSheetPresented = false
    /// Phone panel: the mask chooser is showing although masks exist (after `+`).
    var isChoosingMaskKind = false
    /// Phone panel: the "Add a layer" chooser is showing although layers exist.
    var isChoosingLayerKind = false
    /// Phone panel: the custom colour palette, open over the parameter zone
    /// (FS-05.02 §6). Nil when closed.
    var colorPalette: EditorColorPaletteRequest?
    /// Colours picked in the palette this session, newest first, at most six.
    /// Session-only by design: not stored anywhere.
    private(set) var recentColors: [OverlayColor] = []
    /// Set while the palette's eyedropper waits for a tap on the photo.
    var markupColorSampler: ((OverlayColor) -> Void)?

    func rememberRecentColor(_ color: OverlayColor) {
        recentColors.removeAll {
            abs($0.red - color.red) < 0.01 && abs($0.green - color.green) < 0.01 && abs($0.blue - color.blue) < 0.01
        }
        recentColors.insert(color, at: 0)
        if recentColors.count > 6 { recentColors.removeLast(recentColors.count - 6) }
    }
    /// Phone panel: a line that stands in for the chooser's title for 3s — why a
    /// dimmed kind is off, or what a kind does.
    var maskChooserNotice: String?
    /// The phone's route to History: a sheet, because there is no panel to put
    /// a list in. The wide layout uses `showsHistoryPanel` instead.
    var isHistorySheetPresented = false
    /// History as a column in the tools panel, which is where it belongs on a
    /// window wide enough to have one: a history step is picked by looking at
    /// the photo it produces, and a sheet covers the photo — completely, on a
    /// regular-width/compact-height window like the Duo's inner display, where
    /// UIKit ignores `presentationDetents` and every detent is full screen.
    var showsHistoryPanel = false
    var isMaskPickerPresented = false
    var numericEntryKind: PhotoAdjustmentKind?
    var numericEntryText = ""
    var undoToast: UndoToast?

    // Curve tool presentation state.
    /// Which series the curve graph shows and edits: the RGB master or one
    /// channel.
    var curveChannel: ToneCurveChannel = .rgb
    /// Point curves or the RGB region curve (FS-03.15a §1).
    var curveMode: EditorCurveMode = .point

    // Color tool presentation state.
    var gradingRegion: ColorGradingRegion = .midtones
    /// Which shelf the phone's Presets panel shows (its target strip, FS-03.12).
    var presetSource: EditorPresetSource = .presets
    /// The eyedropper is armed: the next tap on the photo samples a point color.
    var isEyedropperActive = false
    /// Finger-owned color control that is not a `PhotoAdjustmentKind` slider —
    /// "mixer.hue.red", "grading.wheel", … Chrome-hiding checks must consider
    /// BOTH this and `activeSlider`.
    var activePlainSliderID: String?

    @ObservationIgnored private var toastTask: Task<Void, Never>?

    private static let histogramCornerKey = "shotdex.edit.histogramCorner"
    private static var storedHistogramCorner: EditorHistogramCorner {
        UserDefaults.standard.string(forKey: histogramCornerKey)
            .flatMap(EditorHistogramCorner.init(rawValue:)) ?? .topTrailing
    }

    /// Swaps the command row's ✕ / ✓ ends (and reads for a left-handed thumb).
    /// Off by default; a Settings toggle can flip the stored key later.
    static var mirrorCommandBar: Bool {
        UserDefaults.standard.bool(forKey: "shotdex.edit.mirrorCommandBar")
    }

    init() {}

    var isZoomedIn: Bool { zoomScale > 1.01 }

    func resetZoom() {
        zoomScale = 1
        zoomOffset = .zero
    }

    /// Parks the floating histogram back into the action-bar pill.
    func collapseHistogram() {
        histogramDragOffset = nil
        isHistogramCollapsed = true
    }

    /// A drag shorter than 250ms is usually an accident, so the editor offers a
    /// one-tap way back for three seconds.
    func presentUndoToast(_ message: String) {
        toastTask?.cancel()
        undoToast = UndoToast(message: message)
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.undoToast = nil
        }
    }

    func dismissUndoToast() {
        toastTask?.cancel()
        undoToast = nil
    }
}

/// The three shelves of the phone's Presets panel.
enum EditorPresetSource: String, CaseIterable, Identifiable {
    case presets
    case myLooks
    case luts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .presets: "Presets"
        case .myLooks: "My Looks"
        case .luts: "LUTs"
        }
    }

    var systemImage: String {
        switch self {
        case .presets: "camera.filters"
        case .myLooks: "person.crop.square"
        case .luts: "cube"
        }
    }
}

/// What the phone's colour palette is editing: the colour now, and how to write it.
struct EditorColorPaletteRequest {
    let id: String
    let color: () -> OverlayColor
    let onBegin: () -> Void
    let onChange: (OverlayColor) -> Void
    let onEnd: () -> Void
    /// The pen's ink, picked on the same page as its colour (FS-03.13c §5).
    var ink: EditorInkChoice?
}

/// Which ink a drawing layer's pen uses, for the palette page.
struct EditorInkChoice {
    let current: () -> EditorDrawInk
    let choose: (EditorDrawInk) -> Void
}

/// The Curve tool's two ways of shaping tone.
enum EditorCurveMode: String, CaseIterable, Identifiable {
    case point, region

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .point: "Point"
        case .region: "Region"
        }
    }
}
