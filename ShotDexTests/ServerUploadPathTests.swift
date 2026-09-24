import Foundation
import Testing
@testable import ShotDex

/// Where a file lands on the server (FS-15.02 §3, AC-1) and which files of an
/// asset a batch sends (§2, AC-2).
@Suite struct ServerUploadPathTests {
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    private func date(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = tokyo
        formatter.formatOptions = [.withFullDate, .withFullTime, .withTimeZone]
        return formatter.date(from: string)!
    }

    @Test func pathFollowsCaptureDate() {
        let shot = date("2026-09-24T14:05:00+09:00")
        #expect(ServerUploadPath.remotePath(folder: "Photos", captureDate: shot, filename: "IMG_1234.CR3", timeZone: tokyo)
            == "Photos/2026/2026-09-24/IMG_1234.CR3")
        #expect(ServerUploadPath.editedFilename(original: "IMG_1234.CR3", rendered: "FullSizeRender.JPG")
            == "IMG_1234_edited.JPG")
    }

    @Test func dayIsTheDeviceTimeZoneDay() {
        // 08:30 in Tokyo on the 24th is still the 23rd in UTC — the folder
        // follows the device's day, not UTC's.
        let early = date("2026-09-24T08:30:00+09:00")
        #expect(ServerUploadPath.remotePath(folder: "", captureDate: early, filename: "a.dng", timeZone: tokyo)
            == "2026/2026-09-24/a.dng")
    }

    @Test func folderIsNormalized() {
        let shot = date("2026-01-02T10:00:00+09:00")
        #expect(ServerUploadPath.remotePath(folder: "/Photos//Raw/", captureDate: shot, filename: "x.nef", timeZone: tokyo)
            == "Photos/Raw/2026/2026-01-02/x.nef")
    }

    @Test func keepBothPicksNextFreeName() {
        #expect(ServerUploadPath.nextFreeName(for: "IMG_1.CR3", existing: ["IMG_1.CR3", "IMG_1 (2).CR3"])
            == "IMG_1 (3).CR3")
        #expect(ServerUploadPath.nextFreeName(for: "IMG_1.CR3", existing: ["img_1.cr3"]) == "IMG_1 (2).CR3")
        #expect(ServerUploadPath.nextFreeName(for: "IMG_1.CR3", existing: ["IMG_2.CR3"]) == "IMG_1.CR3")
    }

    @Test func partPathAndComponents() {
        let path = "Photos/2026/2026-09-24/IMG_1.CR3"
        #expect(ServerUploadPath.partPath(for: path) == "Photos/2026/2026-09-24/IMG_1.CR3.shotdex-part")
        #expect(ServerUploadPath.parent(of: path) == "Photos/2026/2026-09-24")
        #expect(ServerUploadPath.lastComponent(of: path) == "IMG_1.CR3")
    }
}

@Suite struct ServerUploadPlanTests {
    private let raw = AssetUploadFile(key: "photo:IMG_1.CR3", filename: "IMG_1.CR3", isRAW: true, role: .original, estimatedBytes: 30_000_000)
    private let jpeg = AssetUploadFile(key: "alternatePhoto:IMG_1.JPG", filename: "IMG_1.JPG", isRAW: false, role: .original, estimatedBytes: 8_000_000)
    private let edited = AssetUploadFile(key: "fullSizePhoto:FullSizeRender.jpg", filename: "FullSizeRender.jpg", isRAW: false, role: .edited, estimatedBytes: 6_000_000)

    @Test func resourceSelectionPerKind() {
        let pair = [raw, jpeg, edited]
        #expect(ServerUploadPlan.files(of: pair, kind: .onlyRAW) == [raw])
        #expect(ServerUploadPlan.files(of: pair, kind: .allOriginals) == [raw, jpeg])
        #expect(ServerUploadPlan.files(of: pair, kind: .originalsAndEdited) == [raw, jpeg, edited])
        #expect(ServerUploadPlan.files(of: [jpeg], kind: .onlyRAW).isEmpty)
    }

    @Test func summaryCountsSkippedPhotos() {
        let summary = ServerUploadPlan.summary(of: [[raw, jpeg], [jpeg]], kind: .onlyRAW)
        #expect(summary == .init(photoCount: 1, fileCount: 1, estimatedBytes: 30_000_000, skippedPhotoCount: 1))
    }
}
