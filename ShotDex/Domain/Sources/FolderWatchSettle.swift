import Foundation

/// When a file a folder watcher reported is ready to read (FS-19.01 §5): its
/// size has not changed for `quiet` seconds. A file still being copied in by
/// Finder keeps growing, so it never becomes a half-read, broken photo; a
/// batch of 12 dropped at once is read together once the last one settles.
struct FolderWatchSettle: Sendable {
    static let quiet: TimeInterval = 2

    private var pending: [String: (size: Int64, changedAt: Date)] = [:]

    var isEmpty: Bool { pending.isEmpty }

    /// A watcher event, or a poll of a pending file's size. A changed size
    /// starts the quiet period again.
    mutating func observe(path: String, size: Int64, at now: Date) {
        if let known = pending[path], known.size == size { return }
        pending[path] = (size, now)
    }

    /// A file removed before it settled (a cancelled copy) is forgotten.
    mutating func remove(path: String) {
        pending[path] = nil
    }

    /// The files quiet for long enough, taken out of the pending set, by
    /// path.
    mutating func settled(at now: Date) -> [String] {
        let ready = pending.filter { now.timeIntervalSince($0.value.changedAt) >= Self.quiet }.keys.sorted()
        for path in ready { pending[path] = nil }
        return ready
    }

    /// When to look again: the moment the earliest pending file would settle.
    var nextCheck: Date? {
        pending.values.map { $0.changedAt.addingTimeInterval(Self.quiet) }.min()
    }
}
