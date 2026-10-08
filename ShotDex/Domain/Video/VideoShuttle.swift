import Foundation

/// J / K / L (FS-12.17b §3): L plays forward at 1×, again at 2×, again at
/// 4×; J the same backwards; K stops. Sound at 1× and 2× (pitch kept),
/// none at 4× or backwards. While at 2× or 4× the play button wears the
/// rate.
enum VideoShuttle {
    enum Key: Sendable { case j, k, l }

    /// The rates a key steps through.
    static let speeds: [Float] = [1, 2, 4]

    /// The rate after `key`, from `rate` (0 stopped; negative backwards).
    static func rate(after key: Key, from rate: Float) -> Float {
        switch key {
        case .k:
            return 0
        case .l:
            guard rate > 0 else { return 1 }
            return speeds.first { $0 > rate } ?? speeds.last ?? 1
        case .j:
            guard rate < 0 else { return -1 }
            return -(speeds.first { $0 > -rate } ?? speeds.last ?? 1)
        }
    }

    /// "2×", "4×" — nil at 1× and when stopped.
    static func label(for rate: Float) -> String? {
        let speed = abs(rate)
        guard speed >= 2 else { return nil }
        return "\(Int(speed))×"
    }

    /// No sound at 4× or backwards.
    static func isMuted(_ rate: Float) -> Bool {
        rate < 0 || abs(rate) >= 4
    }

    /// Frames a second when the item cannot play backwards (§7): the
    /// playhead steps back this often, silent.
    static let reverseStepsPerSecond: Double = 15
}
