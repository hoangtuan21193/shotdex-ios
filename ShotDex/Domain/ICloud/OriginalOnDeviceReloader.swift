import Foundation

/// What a grid narrowed by the Filter menu's "Original on This iPhone" does
/// with the original check (FS-06.10 §4), apart from SwiftUI so it can be
/// tested: keeps `screenOpened` / `screenClosed` paired however the screen is
/// left, and reloads the grid as the check's batches land — at most once
/// every 3 s, because a pass runs ~275 batches and a grid reloading on each
/// one flickers.
///
/// `seenGeneration` is the batch the grid last reflects. It survives the
/// screen being covered (the viewer, a pushed detail), so batches that land
/// meanwhile — the pass may even finish — are caught up with one reload on
/// return. Only turning the toggle off forgets it. A batch landing while a
/// reload is running is not dropped: the loop goes round again.
@MainActor
final class OriginalOnDeviceReloader {
    struct Hooks {
        var open: @MainActor () -> Void
        var close: @MainActor () -> Void
        var reload: @MainActor () async -> Void
        var now: @MainActor () -> Date = { Date() }
        var sleep: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    }

    static let minimumInterval: TimeInterval = 3

    /// Settable so a view can hand over its latest closures on each update.
    var hooks: Hooks
    private(set) var isOpen = false
    private(set) var seenGeneration: Int?
    private var latestGeneration = 0
    private var isActive = false
    private var isOnScreen = false
    private var isPaused = false
    private var lastReload = Date.distantPast
    /// The reload loop in flight; one at a time.
    private(set) var reloadTask: Task<Void, Never>?

    init(hooks: Hooks) {
        self.hooks = hooks
    }

    /// Hand over everything the view knows, whenever any of it changes.
    func update(isActive: Bool, isOnScreen: Bool, isPaused: Bool, generation: Int) {
        let turnedOn = isActive && !self.isActive
        self.isActive = isActive
        self.isOnScreen = isOnScreen
        self.isPaused = isPaused
        latestGeneration = generation

        let wanted = isActive && isOnScreen
        if wanted != isOpen {
            isOpen = wanted
            wanted ? hooks.open() : hooks.close()
        }
        if !isActive {
            // The toggle is off: nothing to keep up with.
            seenGeneration = nil
            reloadTask?.cancel()
            reloadTask = nil
            return
        }
        // Turning the toggle on reloads the grid by itself: start from here.
        if turnedOn || seenGeneration == nil {
            seenGeneration = generation
            return
        }
        if needsReload { scheduleReload() }
    }

    private var needsReload: Bool {
        isActive && isOnScreen && !isPaused && latestGeneration != seenGeneration
    }

    private func scheduleReload() {
        guard reloadTask == nil else { return }
        reloadTask = Task { [weak self] in
            while let self, self.needsReload {
                let wait = Self.minimumInterval - self.hooks.now().timeIntervalSince(self.lastReload)
                if wait > 0 { await self.hooks.sleep(.milliseconds(Int(wait * 1000))) }
                guard !Task.isCancelled, self.needsReload else { break }
                let target = self.latestGeneration
                self.lastReload = self.hooks.now()
                await self.hooks.reload()
                guard !Task.isCancelled else { break }
                self.seenGeneration = target
            }
            self?.reloadTask = nil
        }
    }
}
