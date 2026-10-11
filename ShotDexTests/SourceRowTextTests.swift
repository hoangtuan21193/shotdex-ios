import Foundation
import Testing
@testable import ShotDex

/// The words and dot of a Sources row (FS-19.01b §1, board `PH_SettingsSources`).
@Suite struct SourceRowTextTests {
    @Test func rowsReadAsTheBoardDraws() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let japan = SourceRowText(kind: .onDevice, status: .online, count: 4_118, lastReadAt: now.addingTimeInterval(-120))
        #expect(japan.badge == "On My iPhone")
        #expect(japan.detail(now: now).hasPrefix("4,118 items · indexed 2 min"))
        #expect(japan.dot == .ok)

        let t7 = SourceRowText(kind: .drive, status: .offline, count: 26_107)
        #expect(t7.badge == "USB-C Drive")
        #expect(t7.detail(now: now) == "Not connected · 26,107 photos kept")
        #expect(t7.dot == .away && t7.isOffline)

        let client = SourceRowText(kind: .iCloudDrive, status: .needsAccess, count: 10)
        #expect(client.detail(now: now) == "Choose the folder again in Files to let ShotDex read it.")
        #expect(client.dot == .attention)

        let nas = SourceRowText(kind: .server(protocolName: "SMB"), status: .online, count: 1_102)
        #expect(nas.detail(now: now) == "SMB · 1,102 items")
        #expect(SourceRowText(kind: .server(protocolName: "SMB"), status: .offline, count: 3).detail(now: now) == "Not reachable · 3 photos kept")

        let photos = SourceRowText(kind: .photos, status: .online, count: 0, photosAccess: "Denied", photosAccessIsFull: false)
        #expect(photos.detail(now: now) == "Denied · 0 items")
        #expect(photos.dot == .away)
        #expect(SourceRowText(kind: .onDevice, status: .reading(done: 12, total: 0), count: 12).detail(now: now) == "Reading… 12 items so far")
    }

    /// A read that finished a moment "after" now — the stored stamp and the
    /// clock disagree by a fraction — still reads as the past, never "in 0 sec."
    @Test func justReadIsNeverInTheFuture() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let nas = SourceRowText(kind: .server(protocolName: "SMB"), status: .online, count: 20, lastReadAt: now.addingTimeInterval(0.6))
        #expect(!nas.detail(now: now).contains("in "))
        #expect(nas.detail(now: now).hasPrefix("SMB · 20 items · indexed"))
    }
}
