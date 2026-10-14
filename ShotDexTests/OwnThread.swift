import Foundation

/// Runs blocking work — a `RemoteMovieStream` read, as VLC's input thread
/// does it — on a thread of its own. Never on the concurrency pool: the
/// stream waits there for an async read that needs a pool thread itself,
/// and with the pool full (the whole suite at once) both sides wait forever.
func onOwnThread<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        Thread { continuation.resume(returning: body()) }.start()
    }
}
