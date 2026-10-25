import Foundation
import Testing
@testable import ShotDex

/// FS-19.07 §7: the line under a smart album's conditions.
@MainActor
struct OnServerProgressTests {
    /// AC-80: 100 items, 30 known, 70 with a same-size NAS file to hash —
    /// `Checking · 30 of 100`, with what is left to download.
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
        #expect(progress == OnServerProgress(checked: 30, total: 100, bytesToDownload: 70_000_000, editedOnlyMissing: 0))
        let lines = OnServerProgressLine.lines(.init(progress: progress, wait: nil, finishedAt: nil, sourceName: "NAS Home"))
        #expect(lines == ["Checking · 30 of 100 · \(Int64(70_000_000).formatted(.byteCount(style: .file))) to download"])
    }

    /// AC-99: an edited item whose render is not on the NAS is named.
    @Test func editedLine() async throws {
        let f = try OnServerFixture(photos: 1)
        try f.photo(0, files: [("1:IMG_1.HEIC", .photo, 7_000, "orig"), ("5:FullSizeRender.HEIC", .editedPhoto, 7_500, "edit")])
        try f.server("Shared/IMG_1.HEIC", size: 7_000, sha: "orig")
        let progress = try OnServerProgressQueries(database: f.database).progress(sourceId: f.source, folder: nil)
        #expect(progress.editedOnlyMissing == 1)
        let lines = OnServerProgressLine.lines(.init(progress: progress, wait: nil, finishedAt: nil, sourceName: "NAS Home"))
        #expect(lines.last == "1 Edited — edit not on NAS Home")
    }

    /// AC-92 and the waits: `.limited` adds its sentence; a wait leads the
    /// line; a finished check says when.
    @Test func waitsLimitedAndDone() {
        let half = OnServerProgress(checked: 5, total: 10)
        func first(_ wait: OnServerSchedule.Wait) -> String? {
            OnServerProgressLine.lines(.init(progress: half, wait: wait, finishedAt: nil, sourceName: "NAS Home")).first
        }
        #expect(first(.wifi) == "Waiting for Wi‑Fi · 5 of 10")
        #expect(first(.space) == "Waiting for space · 5 of 10")
        #expect(first(.unreachable("NAS Home")) == "NAS Home isn't reachable · 5 of 10")
        #expect(first(.openApp) == "Open ShotDex to continue · 5 of 10")
        let limited = OnServerProgressLine.lines(.init(progress: half, wait: nil, finishedAt: nil, sourceName: "NAS Home", isLimited: true))
        #expect(limited.last == "Only photos ShotDex can access are checked.")
        let now = Date(timeIntervalSince1970: 10_000)
        let done = OnServerProgressLine.lines(.init(progress: OnServerProgress(checked: 10, total: 10), wait: nil,
                                                    finishedAt: now.addingTimeInterval(-180), sourceName: "NAS Home"), now: now)
        #expect(done.first?.hasPrefix("Checked ") == true)
    }
}
