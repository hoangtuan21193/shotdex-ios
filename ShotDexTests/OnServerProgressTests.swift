import Foundation
import Testing
@testable import ShotDex

/// FS-19.07 §7: the line under a smart album's conditions.
@MainActor
struct OnServerProgressTests {
    /// AC-80: 100 items, 30 known, 70 with a same-size NAS file to hash —
    /// `70 photos left to check on NAS Home › Shared` — one number, and
    /// where it counts.
    @Test func checkingCounts() async throws {
        let f = try OnServerFixture(photos: 100)
        for n in 0..<30 {
            try f.photo(n, files: [("1:IMG_\(n).HEIC", .photo, 1_000 + Int64(n), "sha\(n)")])
        }
        for n in 30..<100 {
            try f.photo(n, files: [("1:IMG_\(n).HEIC", .photo, 1_000_000, nil)])
        }
        try f.server("Shared/big.HEIC", size: 1_000_000, sha: "other")
        let progress = try OnServerProgressQueries(database: f.database).progress(sourceId: f.source, folder: "Shared")
        #expect(progress == OnServerProgress(checked: 30, total: 100, editedOnlyMissing: 0))
        let lines = OnServerProgressLine.lines(.init(progress: progress, wait: nil, finishedAt: nil, sourceName: "NAS Home", folder: "Shared", thisDevice: .iPhone))
        #expect(lines == ["70 photos left to check on NAS Home › Shared"])
        let whole = OnServerProgressLine.lines(.init(progress: OnServerProgress(checked: 54_920 - 1, total: 54_920), wait: nil, finishedAt: nil,
                                                     sourceName: "WIN", thisDevice: .mac))
        #expect(whole == ["1 photo left to check on WIN"])
    }

    /// AC-99: an edited item whose render is not on the NAS is named.
    @Test func editedLine() async throws {
        let f = try OnServerFixture(photos: 1)
        try f.photo(0, files: [("1:IMG_1.HEIC", .photo, 7_000, "orig"), ("5:FullSizeRender.HEIC", .editedPhoto, 7_500, "edit")])
        try f.server("Shared/IMG_1.HEIC", size: 7_000, sha: "orig")
        let progress = try OnServerProgressQueries(database: f.database).progress(sourceId: f.source, folder: nil)
        #expect(progress.editedOnlyMissing == 1)
        let lines = OnServerProgressLine.lines(.init(progress: progress, wait: nil, finishedAt: nil, sourceName: "NAS Home", thisDevice: .iPhone))
        #expect(lines.last == "1 edited photo without the edit on NAS Home")
    }

    /// AC-92 and the waits: `.limited` adds its sentence; a wait leads the
    /// line; a finished check says when.
    @Test func waitsLimitedAndDone() {
        let half = OnServerProgress(checked: 5, total: 10)
        func first(_ wait: OnServerSchedule.Wait) -> String? {
            OnServerProgressLine.lines(.init(progress: half, wait: wait, finishedAt: nil, sourceName: "NAS Home", thisDevice: .iPhone)).first
        }
        #expect(first(.wifi) == "Waiting for Wi‑Fi · 5 photos left")
        #expect(first(.space) == "Waiting for space · 5 photos left")
        #expect(first(.unreachable("NAS Home")) == "NAS Home isn't reachable · 5 photos left")
        #expect(first(.openApp) == "Open ShotDex to continue · 5 photos left")
        let limited = OnServerProgressLine.lines(.init(progress: half, wait: nil, finishedAt: nil, sourceName: "NAS Home", isLimited: true, thisDevice: .iPhone))
        #expect(limited.last == "Only photos ShotDex can access are checked.")
        let now = Date(timeIntervalSince1970: 10_000)
        let done = OnServerProgressLine.lines(.init(progress: OnServerProgress(checked: 10, total: 10), wait: nil,
                                                    finishedAt: now.addingTimeInterval(-180), sourceName: "NAS Home", thisDevice: .iPhone), now: now)
        #expect(done.first?.hasPrefix("Checked ") == true)
    }

    /// AC-153 (§12.4): a device caught wrong is named right under the
    /// progress, on each kind of device; one that sent no name is "another
    /// device"; with none caught there is no such line.
    @Test func mismatchLine() {
        let half = OnServerProgress(checked: 5, total: 10)
        func lines(_ from: [String?], _ device: OnServerProgressLine.ThisDevice) -> [String] {
            OnServerProgressLine.lines(.init(progress: half, wait: nil, finishedAt: nil, sourceName: "NAS Home",
                                             mismatchFrom: from, thisDevice: device))
        }
        #expect(lines(["Tuấn's MacBook"], .iPhone)
            == ["5 photos left to check on NAS Home", "Hashes from Tuấn's MacBook didn't match — checking on this iPhone."])
        #expect(lines(["Tuấn's iPhone"], .mac).last == "Hashes from Tuấn's iPhone didn't match — checking on this Mac.")
        #expect(lines([nil], .iPad).last == "Hashes from another device didn't match — checking on this iPad.")
        #expect(lines([], .iPhone) == ["5 photos left to check on NAS Home"])
        // Two caught, one unnamed; a name twice is said once.
        #expect(lines(["iPad", nil, "iPad"], .mac).last
            == "Hashes from another device and iPad didn't match — checking on this Mac.")
    }

    /// The name a device sends with its hashes is what the line shows; the
    /// newest name wins.
    @Test func deviceNamesKept() throws {
        let store = SharedIndexStore(database: try AppDatabase.makeEmpty())
        try store.saveDeviceNames(["MAC": "Old name"])
        try store.saveDeviceNames(["MAC": "Tuấn's MacBook", "IPAD": ""])
        #expect(try store.deviceNames(["MAC", "IPAD", "PHONE"]) == ["MAC": "Tuấn's MacBook"])
    }
}
