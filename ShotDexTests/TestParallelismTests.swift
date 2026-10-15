import Foundation
import Testing

/// The cap on how many tests run at once, set in the ShotDex and ShotDexTests
/// schemes' Test action (`SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH`).
///
/// Swift Testing runs every test on the Swift concurrency pool, one thread per
/// CPU. Many tests block their thread in a system call — `PKDrawing.image`, a
/// HEIC encode or decode through ImageIO — and on iOS 26 those calls finish
/// only once a pool thread is free to run work of their own. Uncapped, the
/// whole suite fills the pool with such calls and every one of them waits for
/// a thread that never frees: the run hung at ~2,200 tests from 2026-10-01 on.
/// Fewer tests at once than the pool is wide keeps threads free for that work.
struct TestParallelismTests {
    @Test func fewerTestsRunAtOnceThanThePoolIsWide() throws {
        let value = ProcessInfo.processInfo.environment["SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH"]
        let width = try #require(value.flatMap(Int.init), "the scheme's Test action lost the parallelism cap")
        #expect(width < ProcessInfo.processInfo.activeProcessorCount)
    }
}
