import Foundation
import Observation

/// What the project's clips sound like, for ducking (FS-12.13 §4): each
/// asset's voices and levels, the tasks listening for them, and the clips
/// that could not be read. Owned by `VideoStudioModel`, which closes it with
/// the studio. Results are derived data, cached by asset — nothing here is
/// in the recipe; reorder, trim and speed reuse them.
@MainActor @Observable
final class VideoDuckingModel {
    /// One asset to listen to: the part of its source the project plays.
    struct Need: Equatable, @unchecked Sendable {
        var assetID: String
        var range: ClosedRange<Double>
        var source: VideoClipSource

        static func == (lhs: Need, rhs: Need) -> Bool {
            lhs.assetID == rhs.assetID && lhs.range == rhs.range
        }
    }

    typealias Analyze = @Sendable (String, VideoClipSource, ClosedRange<Double>) async throws -> ClipSoundActivity

    /// By asset.
    private(set) var activity: [String: ClipSoundActivity] = [:]
    /// Assets whose sound could not be read — iCloud with no network, a
    /// revoked `.limited` grant. They make no dip (§6).
    private(set) var unreadable: Set<String> = []
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    /// What each running task was asked for, so a wider trim restarts it.
    @ObservationIgnored private var asked: [String: ClosedRange<Double>] = [:]
    @ObservationIgnored private let analyze: Analyze
    /// Called when a result lands — the studio rebuilds its audio mix.
    @ObservationIgnored var onChange: (() -> Void)?

    init(analyze: @escaping Analyze) {
        self.analyze = analyze
    }

    convenience init(cache: AudioAnalysisCache) {
        let analyzer = ClipSoundAnalyzer(cache: cache)
        self.init(analyze: { try await analyzer.activity(assetID: $0, source: $1, range: $2) })
    }

    /// "Listening for voices…" while this is true.
    var isListening: Bool { !tasks.isEmpty }

    /// Starts listening to every asset in `needs` whose part is not known
    /// yet, and stops the ones the project no longer plays.
    func listen(to needs: [Need]) {
        let wanted = Dictionary(needs.map { ($0.assetID, $0) }, uniquingKeysWith: { first, _ in first })
        for (assetID, task) in tasks where wanted[assetID] == nil {
            task.cancel()
            tasks[assetID] = nil
            asked[assetID] = nil
        }
        for need in wanted.values {
            if let known = activity[need.assetID], known.covers(need.range.lowerBound, need.range.upperBound) { continue }
            if let range = asked[need.assetID], range.contains(need.range.lowerBound), range.contains(need.range.upperBound) { continue }
            if unreadable.contains(need.assetID), tasks[need.assetID] == nil, asked[need.assetID] == nil {
                // Tried and failed: try again only when asked to retry.
                continue
            }
            start(need)
        }
    }

    /// A clip that could not be read came back (it downloaded): forget the
    /// failure so the next `listen` reads it again.
    func retryUnreadable() {
        unreadable.removeAll()
    }

    private func start(_ need: Need) {
        tasks[need.assetID]?.cancel()
        asked[need.assetID] = need.range
        let analyze = analyze
        let assetID = need.assetID
        tasks[assetID] = Task { [weak self] in
            do {
                // `analyze` is nonisolated: the decode and the classifier
                // run off the main actor, and this task's cancellation
                // reaches them.
                let result = try await analyze(assetID, need.source, need.range)
                guard !Task.isCancelled else { return }
                self?.finish(assetID, with: result)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.fail(assetID)
            }
        }
    }

    private func finish(_ assetID: String, with result: ClipSoundActivity) {
        tasks[assetID] = nil
        asked[assetID] = nil
        unreadable.remove(assetID)
        activity[assetID] = result
        onChange?()
    }

    private func fail(_ assetID: String) {
        tasks[assetID] = nil
        asked[assetID] = nil
        unreadable.insert(assetID)
        onChange?()
    }

    /// The studio closed: every analysis stops; what was found stays in
    /// the cache for the next time.
    func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        asked.removeAll()
    }

    /// Waits until nothing is being listened to — the export's "Listening
    /// for voices…" (D-14). Returns early when the waiting task is cancelled.
    func waitUntilDone() async {
        while isListening, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
