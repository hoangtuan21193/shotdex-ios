import Foundation
import Testing
@testable import ShotDex

/// The on-server popover's file line and speed while several originals
/// download at once (the check runs four): each file reports its own bytes,
/// the speed is all of them together.
struct OnServerActivityTests {
    @Test func speedCountsEveryFileInFlight() async throws {
        let activity = OnServerActivity()
        activity.begin(.downloading, key: "a", fileName: "IMG_1.HEIC", bytesTotal: 4_000_000)
        activity.begin(.downloading, key: "b", fileName: "IMG_2.HEIC", bytesTotal: 4_000_000)
        activity.progress("a", 0)
        activity.progress("b", 0)
        try await Task.sleep(for: .milliseconds(600))
        // Interleaved, the way concurrent downloads call back.
        activity.progress("a", 1_000_000)
        activity.progress("b", 1_000_000)
        let now = try #require(activity.current)
        #expect(now.fileName == "IMG_2.HEIC")
        #expect(now.bytesDone == 1_000_000)
        #expect(now.otherFiles == 1)
        // 2 MB over ~0.6 s; one file's bytes against another's mark used to
        // give nonsense here.
        let rate = try #require(now.bytesPerSecond)
        #expect(rate > 1_500_000 && rate < 4_000_000)
        activity.end("b")
        #expect(activity.current?.fileName == "IMG_1.HEIC")
        #expect(activity.current?.otherFiles == 0)
        activity.end("a")
        #expect(activity.current?.fileName == nil)
    }

    @Test func staleSpeedIsNotShown() async throws {
        let activity = OnServerActivity()
        activity.begin(.reading, key: "s", fileName: "DSC_1.ARW", bytesTotal: nil)
        activity.progress("s", 0)
        try await Task.sleep(for: .milliseconds(600))
        activity.progress("s", 500_000)
        #expect(activity.current?.bytesPerSecond != nil)
        try await Task.sleep(for: .seconds(3.2))
        #expect(activity.current?.bytesPerSecond == nil)
    }
}
