import SwiftUI

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
    var numericEntryKind: PhotoAdjustmentKind?
    var numericEntryText = ""
    var undoToast: UndoToast?

    // Color tool presentation state.
    var gradingRegion: ColorGradingRegion = .midtones
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
