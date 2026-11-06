import Foundation
import Testing
@testable import ShotDex

/// FS-19.08 §6d: the Compare window's rows and sides.
@Suite struct CommonPhotosCompareTests {
    private func file(_ folder: Int, _ path: String, size: Int64 = 100) -> CommonPhotosFile {
        CommonPhotosFile(folder: folder, relativePath: path, size: size, modified: nil)
    }

    /// AC-181: a Same photo's copies, first folder left — one per folder,
    /// the folder's first copy, with its place and path on the server.
    @Test func rowsAndSides() {
        let photo = CommonPhoto(sha256: "s", size: 100, files: [
            [file(0, "2025/IMG_4021.HEIC"), file(0, "older/IMG_4021.HEIC")],
            [file(1, "Phone/2025-06-01 IMG_4021.HEIC")]
        ])
        let copies = CommonPhotosCompare.copies(of: photo, folders: ["photos/Tuan", "photos/Vo"])
        #expect(copies.map(\.place) == ["Tuan/2025", "Vo/Phone"])
        #expect(copies.map(\.name) == ["IMG_4021.HEIC", "2025-06-01 IMG_4021.HEIC"])
        #expect(copies.map(\.path) == ["photos/Tuan/2025/IMG_4021.HEIC", "photos/Vo/Phone/2025-06-01 IMG_4021.HEIC"])
    }

    /// ↓ steps to the next row and stops on the last; ↑ back, stops on the first.
    @Test func stepsThroughTheRows() {
        var compare = CommonPhotosCompare(rowIds: ["a", "b", "c"], showing: "b")
        #expect(compare.position == (2, 3))
        compare.next()
        compare.next()
        #expect(compare.currentId == "c")
        compare.previous()
        compare.previous()
        compare.previous()
        #expect(compare.currentId == "a")
    }

    /// The list changes under the window: the same row stays shown when it
    /// is still there; gone, the window shows the one now at its place.
    @Test func followsTheList() {
        var compare = CommonPhotosCompare(rowIds: ["a", "b", "c"], showing: "c")
        compare.update(rowIds: ["x", "c"])
        #expect(compare.currentId == "c")
        compare.update(rowIds: ["x"])
        #expect(compare.currentId == "x")
        compare.update(rowIds: [])
        #expect(compare.currentId == nil)
    }
}

/// AC-185: one clock for the two copies of a video.
@Suite struct CommonPhotosVideoSyncTests {
    @Test func videoClockKeepsBothTogether() {
        let frame = CommonPhotosVideoSync.frameDuration(fps: 30)
        #expect(abs(frame - 1.0 / 30) < 1e-9)
        #expect(CommonPhotosVideoSync.frameDuration(fps: 0) == 1.0 / 30)
        // Within two frames: left alone; past them: put back on the leader's time.
        #expect(!CommonPhotosVideoSync.needsSeek(leader: 6.0, follower: 6.06, frameDuration: frame))
        #expect(CommonPhotosVideoSync.needsSeek(leader: 6.0, follower: 6.08, frameDuration: frame))
        #expect(CommonPhotosVideoSync.needsSeek(leader: 6.08, follower: 6.0, frameDuration: frame))
        // At 120 fps two frames is 17 ms: jitter that small is not drift.
        #expect(!CommonPhotosVideoSync.needsSeek(leader: 6.0, follower: 6.04, frameDuration: 1.0 / 120))
        // A scrub to 60 % of 10 s takes both to 6 s; out of range is clamped.
        #expect(CommonPhotosVideoSync.time(at: 0.6, of: 10) == 6)
        #expect(CommonPhotosVideoSync.time(at: 1.4, of: 10) == 10)
        // Play at the end starts again; a length not read yet is never the end.
        #expect(CommonPhotosVideoSync.isAtEnd(time: 9.99, duration: 10, frameDuration: frame))
        #expect(!CommonPhotosVideoSync.isAtEnd(time: 9.9, duration: 10, frameDuration: frame))
        #expect(!CommonPhotosVideoSync.isAtEnd(time: 0, duration: 0, frameDuration: frame))
        #expect(CommonPhotosVideoSync.label(6.9) == "0:06")
        #expect(CommonPhotosVideoSync.label(3_725) == "1:02:05")
    }
}
