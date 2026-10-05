import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

/// FS-12.11 §4: the three gestures on a clip's body, by hold and travel.
struct TimelinePressClassifierTests {
    /// AC-18: (0.2 s, 15pt) scrolls · (0.4 s, 2pt) does nothing · (0.6 s,
    /// 2pt) enters multi-select · (0.6 s, 20pt) moves.
    @Test func fourCasesFromTheSpec() {
        #expect(TimelinePressClassifier.classify(held: 0.2, travel: 15, isReleased: false) == .scroll)
        #expect(TimelinePressClassifier.classify(held: 0.4, travel: 2, isReleased: true) == .nothing)
        #expect(TimelinePressClassifier.classify(held: 0.6, travel: 2, isReleased: true) == .enterSelection)
        #expect(TimelinePressClassifier.classify(held: 0.6, travel: 20, isReleased: false) == .move)
    }

    /// The edges: 0.32 s is the first held instant that moves, 0.5 s the
    /// first that selects, and 10pt is still in place.
    @Test func boundariesBelongToTheLongerGesture() {
        #expect(TimelinePressClassifier.classify(held: 0.319, travel: 11, isReleased: false) == .scroll)
        #expect(TimelinePressClassifier.classify(held: 0.32, travel: 11, isReleased: false) == .move)
        #expect(TimelinePressClassifier.classify(held: 0.499, travel: 0, isReleased: true) == .nothing)
        #expect(TimelinePressClassifier.classify(held: 0.5, travel: 0, isReleased: true) == .enterSelection)
        #expect(TimelinePressClassifier.classify(held: 0.6, travel: 10, isReleased: true) == .enterSelection)
        #expect(TimelinePressClassifier.classify(held: 0.6, travel: 10.01, isReleased: true) == .move)
        #expect(TimelinePressClassifier.classify(held: 0.31, travel: 0, isReleased: true) == .tap)
        #expect(TimelinePressClassifier.classify(held: 0.32, travel: 0, isReleased: true) == .nothing)
    }

    /// Held in place and not yet let go, the press is undecided — the user
    /// may still drag (move) or lift (select or nothing).
    @Test func aHeldPressIsPendingUntilItMovesOrLifts() {
        #expect(TimelinePressClassifier.classify(held: 0.4, travel: 3, isReleased: false) == .pending)
        #expect(TimelinePressClassifier.classify(held: 2.0, travel: 0, isReleased: false) == .pending)
    }

    /// The UIKit long-press and the rule share one source of numbers.
    @Test func thresholdsAreTheSpecsNumbers() {
        #expect(TimelinePressClassifier.movePress == 0.32)
        #expect(TimelinePressClassifier.selectPress == 0.5)
        #expect(TimelinePressClassifier.slop == 10)
    }

    /// AC-16's other half: the clip's own tap, which the hosted SwiftUI
    /// content fires on release, is swallowed after a held press — once —
    /// and an ordinary tap still selects.
    @MainActor @Test func theGateSwallowsOnlyThePressesTap() {
        let gate = TimelinePressGate()
        let clip = UUID(), other = UUID()
        #expect(!gate.swallowsTap(on: clip, now: 10))

        gate.began(on: clip)
        #expect(!gate.swallowsTap(on: other, now: 10.1))
        gate.ended(now: 10.4)
        #expect(gate.swallowsTap(on: clip, now: 10.45))
        #expect(!gate.swallowsTap(on: clip, now: 10.5))

        gate.began(on: clip)
        gate.ended(now: 20)
        #expect(!gate.swallowsTap(on: clip, now: 20 + TimelinePressGate.window + 0.01))
    }
}
