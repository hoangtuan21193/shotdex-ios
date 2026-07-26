import Foundation
import Testing
@testable import ShotDex

/// Thermal/power backoff policy for the EXIF pass: reader fan-out,
/// inter-batch breather, and the refill decision that lets the fan-out
/// shrink/grow mid-batch.
struct IndexThermalPolicyTests {

    private let allStates: [ProcessInfo.ThermalState] = [.nominal, .fair, .serious, .critical]

    // MARK: Fan-out

    @Test func nominalUsesFullConcurrency() {
        #expect(IndexPipeline.readConcurrency(thermal: .nominal, isLowPowerMode: false) == IndexPipeline.readConcurrency)
    }

    @Test func thermalLadderStepsDown() {
        #expect(IndexPipeline.readConcurrency(thermal: .nominal, isLowPowerMode: false) == 12)
        #expect(IndexPipeline.readConcurrency(thermal: .fair, isLowPowerMode: false) == 6)
        #expect(IndexPipeline.readConcurrency(thermal: .serious, isLowPowerMode: false) == 3)
        #expect(IndexPipeline.readConcurrency(thermal: .critical, isLowPowerMode: false) == 2)
    }

    @Test func lowPowerModeCapsAtFairLevel() {
        // LPM caps at the fair level; deeper thermal backoff still wins.
        #expect(IndexPipeline.readConcurrency(thermal: .nominal, isLowPowerMode: true) == 6)
        #expect(IndexPipeline.readConcurrency(thermal: .fair, isLowPowerMode: true) == 6)
        #expect(IndexPipeline.readConcurrency(thermal: .serious, isLowPowerMode: true) == 3)
        #expect(IndexPipeline.readConcurrency(thermal: .critical, isLowPowerMode: true) == 2)
    }

    @Test func concurrencyNeverDropsToZero() {
        for state in allStates {
            #expect(IndexPipeline.readConcurrency(thermal: state, isLowPowerMode: false) >= 1)
            #expect(IndexPipeline.readConcurrency(thermal: state, isLowPowerMode: true) >= 1)
        }
    }

    // MARK: Inter-batch breather

    @Test func nominalHasNoPause() {
        #expect(IndexPipeline.interBatchPause(thermal: .nominal, isLowPowerMode: false) == .zero)
    }

    @Test func pauseGrowsWithThermalState() {
        #expect(IndexPipeline.interBatchPause(thermal: .fair, isLowPowerMode: false) == .seconds(3))
        #expect(IndexPipeline.interBatchPause(thermal: .serious, isLowPowerMode: false) == .seconds(10))
        #expect(IndexPipeline.interBatchPause(thermal: .critical, isLowPowerMode: false) == .seconds(10))
    }

    @Test func lowPowerModeForcesMinimumPause() {
        for state in allStates {
            #expect(IndexPipeline.interBatchPause(thermal: state, isLowPowerMode: true) >= .seconds(3))
        }
        // The thermal pause still wins when it is longer than the LPM floor.
        #expect(IndexPipeline.interBatchPause(thermal: .serious, isLowPowerMode: true) == .seconds(10))
    }

    // MARK: Refill decision

    @Test func overTargetSpawnsNothing() {
        // Device heated mid-batch: 12 in flight, new target 6 — completions
        // are not replaced, so the fan-out decays to the target.
        #expect(IndexPipeline.refillCount(inFlight: 12, target: 6, remaining: 100) == 0)
    }

    @Test func steadyStateReplacesOneForOne() {
        #expect(IndexPipeline.refillCount(inFlight: 5, target: 6, remaining: 100) == 1)
    }

    @Test func rampUpFillsTheGap() {
        // Device cooled mid-batch: fan-out grows back to the target.
        #expect(IndexPipeline.refillCount(inFlight: 3, target: 12, remaining: 100) == 9)
    }

    @Test func tailClampsToRemaining() {
        #expect(IndexPipeline.refillCount(inFlight: 3, target: 12, remaining: 1) == 1)
    }

    @Test func noRemainingSpawnsNothing() {
        #expect(IndexPipeline.refillCount(inFlight: 0, target: 12, remaining: 0) == 0)
    }

    @Test func neverStarvesTheTaskGroup() {
        // With work remaining and nothing in flight, at least one read must
        // spawn regardless of target, or the batch's drain loop would hang.
        for target in 0...2 {
            #expect(IndexPipeline.refillCount(inFlight: 0, target: target, remaining: 5) >= 1)
        }
    }
}
