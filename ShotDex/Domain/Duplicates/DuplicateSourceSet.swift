import Foundation

/// A group that is raw material for a merge, not junk (FS-06.06 §5): a
/// bracket for HDR or a focus stack. Its card offers the merge and Not
/// duplicates, never a red button, and it is left out of "~GB to free".
struct DuplicateSourceSet: Equatable, Sendable {
    enum Kind: String, Sendable {
        case bracket, focusStack
    }

    var kind: Kind
    var frameCount: Int
    /// Lowest and highest exposure compensation in the set (bracket only).
    var evRange: ClosedRange<Double>?

    /// Frames of a bracket may be at most this many seconds apart.
    static let bracketMaxGap = 2
    /// Smallest EV step a bracket is made of.
    static let bracketMinStep = 0.7
    /// Steps of one bracket are even within this slack (−2/0/+2 rounds).
    static let bracketStepSlack = 0.15
    static let focusStackMinCount = 10
    static let focusStackMaxGap = 1
    /// Neighbouring frames of a focus stack barely move in the hash.
    static let focusStackMaxDistance = 6

    /// The set `members` forms, if any. Members in any order; facts come
    /// from the hash row plus the EXIF the scoring pass read.
    ///
    /// No exposure compensation on a frame → not a bracket: an exported or
    /// third-party file is not guessed at, and the group stays its own kind.
    static func detect(_ members: [HashedPhoto]) -> DuplicateSourceSet? {
        let frames = members.sorted(by: DuplicateGrouper.oldestFirst)
        guard frames.count >= 2, frames.allSatisfy({ $0.creationDate != nil }), sameFocalLength(frames) else { return nil }
        let gaps = zip(frames, frames.dropFirst()).map { ($1.creationDate ?? 0) - ($0.creationDate ?? 0) }
        let biases = frames.compactMap(\.exposureBias)

        if biases.count == frames.count, gaps.allSatisfy({ $0 <= bracketMaxGap }), isEvenBracket(biases),
           let low = biases.min(), let high = biases.max() {
            return DuplicateSourceSet(kind: .bracket, frameCount: frames.count, evRange: low...high)
        }

        let sameExposure = Set(biases.map { ($0 * 10).rounded() }).count <= 1
        let distances = zip(frames, frames.dropFirst()).map { ($0.hash.bits ^ $1.hash.bits).nonzeroBitCount }
        if frames.count >= focusStackMinCount, sameExposure,
           gaps.allSatisfy({ $0 <= focusStackMaxGap }), distances.allSatisfy({ $0 <= focusStackMaxDistance }) {
            return DuplicateSourceSet(kind: .focusStack, frameCount: frames.count, evRange: nil)
        }
        return nil
    }

    /// Every value distinct, sorted steps of at least 0.7 EV and all alike.
    static func isEvenBracket(_ biases: [Double]) -> Bool {
        let sorted = biases.sorted()
        let steps = zip(sorted, sorted.dropFirst()).map { $1 - $0 }
        guard let first = steps.first, first >= bracketMinStep else { return false }
        return steps.allSatisfy { abs($0 - first) <= bracketStepSlack }
    }

    private static func sameFocalLength(_ frames: [HashedPhoto]) -> Bool {
        let lengths = frames.compactMap(\.focalLength)
        guard let first = lengths.first else { return true }
        return lengths.allSatisfy { abs($0 - first) < 0.5 }
    }

    /// "Bracket · 5 frames · ±2 EV", "Focus stack? · 24 frames".
    var title: String {
        switch kind {
        case .bracket:
            return String(localized: "Bracket · \(frameCount) frames · \(evText)",
                          comment: "Duplicates: source-set card title, e.g. Bracket · 5 frames · ±2 EV")
        case .focusStack:
            return String(localized: "Focus stack? · \(frameCount) frames",
                          comment: "Duplicates: source-set card title; the question mark says the app is guessing")
        }
    }

    /// "±2 EV" when the range is symmetric, "−1 to +2 EV" otherwise.
    var evText: String {
        guard let evRange else { return "" }
        if abs(evRange.lowerBound + evRange.upperBound) < 0.05 {
            return "±\(Self.evNumber(evRange.upperBound)) EV"
        }
        return "\(Self.signedEV(evRange.lowerBound)) to \(Self.signedEV(evRange.upperBound)) EV"
    }

    /// "−1", "+2", "0", "+0.7".
    static func signedEV(_ value: Double) -> String {
        if abs(value) < 0.05 { return "0" }
        return (value < 0 ? "−" : "+") + evNumber(abs(value))
    }

    private static func evNumber(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}
