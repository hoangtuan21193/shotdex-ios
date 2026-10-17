import Testing
@testable import ShotDex

/// FS-20 AC-26: what leaving the app does to a card import.
@Suite struct IngestBackgroundPolicyTests {
    /// iOS 26: the run asked for continued processing when it started and
    /// iOS said yes — it keeps going in the background.
    @Test func backgroundOn26KeepsRunning() {
        #expect(IngestBackgroundPolicy.onBackground(isRunning: true, hasContinuedTask: true) == .keepRunning)
    }

    /// Before 26, or when iOS said no: it stops like Stop (no part file, the
    /// rest waits for Import Remaining — `IngestRunnerTests.stopWithinASecondMidFile`).
    @Test func backgroundBefore26Stops() {
        #expect(IngestBackgroundPolicy.onBackground(isRunning: true, hasContinuedTask: false) == .stop)
        #expect(IngestBackgroundPolicy.onBackground(isRunning: false, hasContinuedTask: false) == .keepRunning)
    }
}
