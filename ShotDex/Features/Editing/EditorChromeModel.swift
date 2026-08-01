import SwiftUI

/// Presentation state of the editor chrome: where the histogram card sits, which
/// slider currently owns the gesture, whether the image is full-bleed, and which
/// sheet is up. Kept apart from `PhotoEditorController` so a pan never has to
/// touch the render pipeline's state.
/// One slider each, popped up over the action row by the mask shape buttons.
/// `brush*` write the controller's brush parameters; `shapeFeather` writes the
/// selected component's own `feather` (radial / luminance / color range).
enum EditorMaskControl: String, Identifiable, Sendable {
    case brushSize
    case brushFeather
    case shapeFeather

    var id: String { rawValue }
}

/// The three sections of the Color tool panel.
enum EditorColorSection: String, CaseIterable, Identifiable, Sendable {
    case mixer
    case pointColor
    case grading

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mixer: "Mixer"
        case .pointColor: "Point Color"
        case .grading: "Grading"
        }
    }
}


@MainActor
@Observable
final class EditorChromeModel {
    struct UndoToast: Identifiable {
        let id = UUID()
        let message: String
    }

    private enum Key {
        static let histogramCorner = "shotdex.edit.histogramCorner"
    }

    var histogramCorner: EditorHistogramCorner {
        didSet { defaults.set(histogramCorner.rawValue, forKey: Key.histogramCorner) }
    }

    /// Not persisted, and collapsed on open: the photo is what the editor is for,
    /// so nothing covers it until the user asks for the readout by tapping the
    /// pill in the action row.
    var isHistogramCollapsed = true

    /// Live drag position of the card; nil once it has snapped back to a corner.
    var histogramDragOffset: CGSize?

    var isFullBleed = false
    var showsSplitCompare = false
    var splitFraction = 0.5
    var zoomScale: CGFloat = 1
    var zoomOffset = CGSize.zero

    /// Non-nil while a finger owns a slider: the row highlights and the panel's
    /// scrolling is locked out. The panel itself does not move.
    var activeSlider: PhotoAdjustmentKind?

    var isNewMaskSheetPresented = false
    var isHistorySheetPresented = false
    var isMaskPickerPresented = false
    /// Which mask-shape slider is popped up over the action row (Lightroom-style
    /// Size/Feather/Flow). Nil = no popup. Cleared the moment a brush stroke
    /// starts, so the dialog never covers the area being painted.
    var activeMaskControl: EditorMaskControl?
    var numericEntryKind: PhotoAdjustmentKind?
    var numericEntryText = ""
    var undoToast: UndoToast?

    // Color tool presentation state.
    var colorSection: EditorColorSection = .mixer
    var gradingRegion: ColorGradingRegion = .midtones
    /// The eyedropper is armed: the next tap on the photo samples a point color.
    var isEyedropperActive = false
    /// Finger-owned color control that is not a `PhotoAdjustmentKind` slider —
    /// "mixer.hue.red", "grading.wheel", … Chrome-hiding checks must consider
    /// BOTH this and `activeSlider`.
    var activePlainSliderID: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        histogramCorner = defaults.string(forKey: Key.histogramCorner)
            .flatMap(EditorHistogramCorner.init(rawValue:)) ?? .topTrailing
    }

    /// Tapping the expanded card parks it as a pill in the top bar, off the photo
    /// entirely. Expanding again brings it back to the corner it was dropped in.
    func collapseHistogram() {
        histogramDragOffset = nil
        isHistogramCollapsed = true
    }

    var isZoomedIn: Bool { zoomScale > 1.01 }

    func resetZoom() {
        zoomScale = 1
        zoomOffset = .zero
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
