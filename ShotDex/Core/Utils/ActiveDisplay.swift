import UIKit

/// The display and the window the app is actually on.
///
/// `UIScreen.main` is the wrong question on a device with two displays: it
/// answers with one fixed display instead of the one showing this scene, and
/// Apple deprecates it for that reason (iPhone Duo's inner and outer displays
/// differ in size *and* scale). Everything that needs a pixel scale, a
/// window-sized image request or the display brightness reads it here, so the
/// app follows its window across folds, poses and Split View.
enum ActiveDisplay {
    /// The foreground-active window scene, falling back to any connected one —
    /// sizes are sometimes wanted while the app is not frontmost (prewarming).
    static var windowScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    /// The display the app's window is on.
    static var screen: UIScreen? { windowScene?.screen }

    /// Pixels per point of that display.
    static var scale: CGFloat {
        let scale = screen?.scale ?? UITraitCollection.current.displayScale
        return scale > 0 ? scale : 2
    }

    /// Point size of the app's own window — deliberately not the display's.
    /// In Split View, and on a partly folded iPhone Duo, the window is smaller
    /// than the screen, and a "screen-sized" image request measured off the
    /// display would over-fetch by a wide margin.
    static var size: CGSize {
        if let scene = windowScene {
            let window = scene.keyWindow ?? scene.windows.first
            if let size = window?.bounds.size, size.width > 0, size.height > 0 {
                return size
            }
            let screenSize = scene.screen.bounds.size
            if screenSize.width > 0 { return screenSize }
        }
        // No scene at all (unit tests, or called while the app has no window):
        // the fixed main display is the only answer left.
        return UIScreen.main.bounds.size
    }

    /// `size` in pixels, optionally capped at a lower scale factor (thumbnails
    /// that do not need 3x).
    static func pixelSize(scaleCap: CGFloat = .greatestFiniteMagnitude) -> CGSize {
        let scale = min(scale, scaleCap)
        let size = size
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}
