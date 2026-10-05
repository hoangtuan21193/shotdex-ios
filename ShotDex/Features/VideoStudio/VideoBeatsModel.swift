import Foundation
import Observation

/// The beats of a project's music beds (FS-12.12 §4): what the analysis of
/// each bed found, and the tasks finding it. Owned by `VideoStudioModel`,
/// which closes it with the studio; a bed deleted mid-analysis cancels its
/// task. Results are derived data, cached by file — nothing here is in the
/// recipe.
@MainActor @Observable
final class VideoBeatsModel {
    enum State: Equatable {
        case finding
        case found(BeatAnalysis)
        /// The autocorrelation found no tempo worth snapping to.
        case noSteadyBeat
        /// The file could not be decoded.
        case unreadable
    }

    /// By the music track's file, so two beds of one song share one result.
    private(set) var states: [String: State] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let analyze: @Sendable (URL) async throws -> BeatAnalysis

    init(analyze: @escaping @Sendable (URL) async throws -> BeatAnalysis) {
        self.analyze = analyze
    }

    convenience init(cache: AudioAnalysisCache) {
        let analyzer = MusicBeatAnalyzer(cache: cache)
        self.init(analyze: { try await analyzer.analysis(for: $0) })
    }

    static func key(_ url: URL) -> String { url.standardizedFileURL.path }

    func state(for url: URL) -> State? { states[Self.key(url)] }

    /// The analysis of `url`, when it found a steady beat.
    func analysis(for url: URL) -> BeatAnalysis? {
        if case .found(let analysis) = states[Self.key(url)] { return analysis }
        return nil
    }

    /// Starts finding the beats of `url` unless they are known or being
    /// found. Runs off the main actor; a cancelled task leaves no state.
    func findBeats(of url: URL) {
        let key = Self.key(url)
        guard states[key] == nil || states[key] == .unreadable, tasks[key] == nil else { return }
        states[key] = .finding
        let analyze = analyze
        tasks[key] = Task { [weak self] in
            let result: State
            do {
                // `analyze` is nonisolated: the decode and the arithmetic
                // run off the main actor, and this task's cancellation
                // reaches them.
                let analysis = try await analyze(url)
                result = analysis.isSteady ? .found(analysis) : .noSteadyBeat
            } catch is CancellationError {
                return
            } catch {
                result = .unreadable
            }
            guard !Task.isCancelled else { return }
            self?.finish(key, with: result)
        }
    }

    private func finish(_ key: String, with state: State) {
        tasks[key] = nil
        states[key] = state
    }

    /// Stops finding `url`'s beats — the bed was deleted.
    func cancel(_ url: URL) {
        let key = Self.key(url)
        tasks[key]?.cancel()
        tasks[key] = nil
        if states[key] == .finding { states[key] = nil }
    }

    /// The studio closed: every analysis stops.
    func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        states = states.filter { $0.value != .finding }
    }

    var isFinding: Bool { !tasks.isEmpty }
}
