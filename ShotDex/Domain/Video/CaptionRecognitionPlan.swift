import Foundation

/// What Auto Captions reads and how far it has got (FS-12.14 §4, §8).
///
/// Only video clips with their sound on are read: photos and freeze frames
/// have no speech, and a clip the user muted is not words they want shown.
/// Music is never read. Each clip is read inside its trim window, in source
/// seconds.
enum CaptionRecognitionPlan {
    /// The clips to read, in timeline order.
    static func clipIDs(in recipe: VideoProjectRecipe) -> [UUID] {
        recipe.clips.filter(isReadable).map(\.id)
    }

    static func isReadable(_ clip: VideoClip) -> Bool {
        clip.kind == .video && !clip.isMuted && clip.volume > 0 && clip.effectiveDuration > 0
    }

    /// The part of the clip's source the project plays.
    static func sourceWindow(of clip: VideoClip) -> ClosedRange<Double> {
        let speed = max(clip.speed, VideoClip.speedRange.lowerBound)
        let start = clip.trimStart
        return start...(start + clip.effectiveDuration * speed)
    }

    /// The run's progress, 0…1: the finished clips' share of the planned
    /// clips' length, plus the share of the one being read.
    static func progress(
        _ state: CaptionRecognitionState,
        in recipe: VideoProjectRecipe,
        current: (clipID: UUID, fraction: Double)? = nil
    ) -> Double {
        let lengths = Dictionary(recipe.clips.map { ($0.id, $0.effectiveDuration) }, uniquingKeysWith: { first, _ in first })
        let total = state.plannedClipIDs.reduce(0) { $0 + (lengths[$1] ?? 0) }
        guard total > 0 else { return state.isComplete ? 1 : 0 }
        var done = state.finishedClipIDs.reduce(0) { $0 + (state.plannedClipIDs.contains($1) ? lengths[$1] ?? 0 : 0) }
        if let current, !state.finishedClipIDs.contains(current.clipID) {
            done += (lengths[current.clipID] ?? 0) * min(max(current.fraction, 0), 1)
        }
        return min(done / total, 1)
    }

    /// Whole percent, never 100 before the last clip is done.
    static func percent(_ progress: Double, isComplete: Bool) -> Int {
        let value = Int((progress * 100).rounded(.down))
        return isComplete ? 100 : min(value, 99)
    }

    /// One clip's cues into the lane: whatever that clip had is replaced,
    /// the clip counts as finished, and the cues stay in clip-then-time
    /// order. Used on the project and on every undo snapshot that has a
    /// lane, so Undo never takes back what was heard (plan K4).
    static func merge(_ cues: [CaptionCue], clipID: UUID, into lane: inout VideoCaptionLane, order: [UUID]) {
        lane.cues.removeAll { $0.clipID == clipID }
        lane.cues.append(contentsOf: cues)
        if !lane.recognition.finishedClipIDs.contains(clipID) {
            lane.recognition.finishedClipIDs.append(clipID)
        }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        lane.cues.sort { (rank[$0.clipID] ?? .max, $0.sourceStart) < (rank[$1.clipID] ?? .max, $1.sourceStart) }
    }

    /// A clip that could not be read (iCloud with no network, limited
    /// access): it is not finished, and the others go on (§8).
    static func markUnreadable(_ clipID: UUID, in lane: inout VideoCaptionLane) {
        lane.recognition.plannedClipIDs.removeAll { $0 == clipID }
    }
}
