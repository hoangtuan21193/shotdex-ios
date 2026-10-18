#if DEBUG
import AppKit

/// `-ShotDexSnapshot <path.png> [-ShotDexSnapshotDelay <s>]`: the app draws
/// its own front window — toolbar included — into a PNG and quits. The
/// screenshot route for scripts and agents that have no Screen Recording
/// permission (`Tools/mac-shot` needs it); system glass may come out flat.
enum MacSnapshot {
    static func scheduleIfAsked() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ShotDexSnapshot"), index + 1 < arguments.count else { return }
        let path = arguments[index + 1]
        let delay = arguments.firstIndex(of: "-ShotDexSnapshotDelay")
            .flatMap { $0 + 1 < arguments.count ? Double(arguments[$0 + 1]) : nil } ?? 3
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            capture(to: URL(fileURLWithPath: path))
            NSApp.terminate(nil)
        }
    }

    @MainActor
    static func capture(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
