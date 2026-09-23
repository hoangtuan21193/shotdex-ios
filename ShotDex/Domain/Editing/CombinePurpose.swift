import Foundation
import ShotDexKit

/// One row of the Combine Photos submenu (FS-01.09 §2).
///
/// Rows are named for what the photographer is doing, never for the blend
/// underneath: nobody goes looking for Darken to clear tourists out of a
/// square. Operator names appear only inside Stack Exposures, where each one
/// comes with a sentence saying what it is for.
enum CombinePurpose: String, CaseIterable, Identifiable, Sendable {
    case focusStack
    case panorama
    case stackExposures

    var id: String { rawValue }

    /// Fewer frames than this and there is nothing to combine.
    static let minimumPhotoCount = 2

    /// The rows the submenu shows, in order. Built from `allCases` so a row can
    /// never go missing on one device and not another.
    static var menuRows: [CombinePurpose] { allCases.filter(\.isAvailable) }

    /// Whether the screen behind this row ships in this build. Every row does
    /// now that Panorama has its screen (FS-14).
    var isAvailable: Bool { true }

    var title: String {
        switch self {
        case .focusStack:
            String(localized: "Focus Stack", comment: "Combine Photos submenu row and screen title: focus stacking")
        case .panorama:
            String(localized: "Panorama", comment: "Combine Photos submenu row: stitch a panorama")
        case .stackExposures:
            String(localized: "Stack Exposures", comment: "Combine Photos submenu row and screen title: average, lighten or darken a sequence of one scene")
        }
    }

    var systemImage: String {
        switch self {
        case .focusStack: "camera.macro"
        case .panorama: "pano"
        case .stackExposures: "camera.filters"
        }
    }

    /// The stack modes this row's screen offers, the first being the one it
    /// opens on. Panorama is not a stack, so it has none.
    var stackModes: [PhotoStackMode] {
        switch self {
        case .focusStack: [.focusStack]
        case .panorama: []
        case .stackExposures: [.average, .lighten, .darken]
        }
    }

    var defaultMode: PhotoStackMode? { stackModes.first }

    /// Only a screen with a choice to make shows a picker.
    var showsModePicker: Bool { stackModes.count > 1 }

    /// Dimmed, not hidden, below the minimum — the row still says what exists.
    func isEnabled(imageCount: Int) -> Bool { imageCount >= Self.minimumPhotoCount }
}

extension PhotoStackMode {
    /// The name on the Stack Exposures picker, or the Focus Stack title.
    var displayName: String {
        switch self {
        case .average: String(localized: "Average", comment: "Stack Exposures picker: equal-weight average of every frame")
        case .lighten: String(localized: "Lighten", comment: "Stack Exposures picker: keep the brightest pixel")
        case .darken: String(localized: "Darken", comment: "Stack Exposures picker: keep the darkest pixel")
        case .focusStack: String(localized: "Focus Stack", comment: "Combine Photos submenu row and screen title: focus stacking")
        }
    }

    /// One line under the picker saying what the mode is for, not what it
    /// computes — the arithmetic is already on screen in the preview.
    var purposeDescription: String {
        switch self {
        case .average:
            String(localized: "Reduces noise, or smooths water and clouds like a long exposure.", comment: "Stack Exposures: what Average is for")
        case .lighten:
            String(localized: "Keeps the brightest light from every frame — star trails, traffic, fireworks.", comment: "Stack Exposures: what Lighten is for")
        case .darken:
            String(localized: "Clears people and cars that moved between frames. Shoot from a tripod.", comment: "Stack Exposures: what Darken is for")
        case .focusStack:
            String(localized: "Keeps the sharpest part of every frame, for depth of field no single shot can reach.", comment: "Focus Stack: what the screen does")
        }
    }
}
