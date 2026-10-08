import Foundation
import Observation

/// The Video Studio's input switches (FS-12.17 §7–8, FS-12.17b §4): they
/// belong to the device, not to a project, so they live in this app's
/// defaults and never in a recipe. Unwritten means on, for every switch.
@MainActor
@Observable
final class VideoInputPreferences {
    static let shared = VideoInputPreferences()

    enum Key {
        static let frameStepHaptics = "video.frameStepHaptics"
        static let frameZoomOnPinch = "video.frameZoomOnPinch"
        static let pencilStillSteps = "video.pencilStillSteps"
        static let pencilHover = "video.pencilHover"
        /// The keyboard list has shown itself once (17b §4).
        static let keyboardListShown = "video.keyboardListShown"
        /// This iPad has reported a Pencil hovering (17 §8).
        static let pencilHoverSeen = "video.pencilHoverSeen"
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        frameStepHaptics = Self.bool(Key.frameStepHaptics, defaults, default: true)
        frameZoomOnPinch = Self.bool(Key.frameZoomOnPinch, defaults, default: true)
        pencilStillSteps = Self.bool(Key.pencilStillSteps, defaults, default: true)
        pencilHover = Self.bool(Key.pencilHover, defaults, default: true)
        hasShownKeyboardList = Self.bool(Key.keyboardListShown, defaults, default: false)
        hasSeenPencilHover = Self.bool(Key.pencilHoverSeen, defaults, default: false)
    }

    /// PRECISION — Frame steps with haptics: a selection tick each frame.
    var frameStepHaptics: Bool {
        didSet { defaults.set(frameStepHaptics, forKey: Key.frameStepHaptics) }
    }

    /// PRECISION — Frame zoom on pinch: the pinch reaches 12pt a frame.
    var frameZoomOnPinch: Bool {
        didSet { defaults.set(frameZoomOnPinch, forKey: Key.frameZoomOnPinch) }
    }

    /// PENCIL — Frame steps when held still (iPad).
    var pencilStillSteps: Bool {
        didSet { defaults.set(pencilStillSteps, forKey: Key.pencilStillSteps) }
    }

    /// PENCIL — Hover shows the trim point (iPad with hover).
    var pencilHover: Bool {
        didSet { defaults.set(pencilHover, forKey: Key.pencilHover) }
    }

    var hasShownKeyboardList: Bool {
        didSet { defaults.set(hasShownKeyboardList, forKey: Key.keyboardListShown) }
    }

    /// The hover switch shows only after this.
    var hasSeenPencilHover: Bool {
        didSet { defaults.set(hasSeenPencilHover, forKey: Key.pencilHoverSeen) }
    }

    private static func bool(_ key: String, _ defaults: UserDefaults, default value: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? value : defaults.bool(forKey: key)
    }
}
