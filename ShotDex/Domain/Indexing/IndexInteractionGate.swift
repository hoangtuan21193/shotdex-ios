import Foundation
import os

/// Refcounted "a human is looking at a photo" signal. The EXIF pass polls
/// `shouldPauseIndexing` and stops spawning networked reads while it is true,
/// so an interactive iCloud download gets the bandwidth instead of queueing
/// behind `readConcurrency` index streams in the system download daemon.
///
/// The viewer holds one count while open and touches the gate on activity
/// (page change, download progress). A pause with no activity auto-expires
/// after `maxPauseDuration`, so a leaked count can never stall indexing
/// forever.
final class IndexInteractionGate: Sendable {
    /// Auto-resume window: a pause with no activity for this long releases
    /// indexing even if the viewer stays open on an already-loaded photo.
    static let maxPauseDuration: Duration = .seconds(90)

    private struct State: Sendable {
        var count = 0
        var lastActivity: ContinuousClock.Instant = .now
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func beginInteraction() {
        state.withLock {
            $0.count += 1
            $0.lastActivity = .now
        }
    }

    func endInteraction() {
        state.withLock { $0.count = max(0, $0.count - 1) }
    }

    /// Marks user activity (page swipe, iCloud download progress tick) —
    /// extends the pause window. Only meaningful while a count is held.
    func touch() {
        touch(now: .now)
    }

    /// Injectable clock for unit tests.
    func touch(now: ContinuousClock.Instant) {
        state.withLock { $0.lastActivity = now }
    }

    var shouldPauseIndexing: Bool {
        shouldPauseIndexing(now: .now)
    }

    /// Injectable clock for unit tests.
    func shouldPauseIndexing(now: ContinuousClock.Instant) -> Bool {
        state.withLock { $0.count > 0 && now - $0.lastActivity < Self.maxPauseDuration }
    }
}
