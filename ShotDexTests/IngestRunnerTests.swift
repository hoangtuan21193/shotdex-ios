import Foundation
import Testing
@testable import ShotDex

/// FS-20 §7–8: a card import end to end, the card being a `DCIM` folder in
/// a temporary directory and the destination another.
@Suite struct IngestRunnerTests {
    static let utc = TimeZone(identifier: "UTC")!
    /// 2026-10-03 09:00 UTC.
    static let shot = Date(timeIntervalSince1970: 1_791_018_000)

    /// AC-4: `IMG_6123.CR3` shot 2026-10-03, Folders `RAW/{year}/{date}`,
    /// template Date_Kyoto_Original Number → `RAW/2026/2026-10-03/
    /// 2026-10-03_Kyoto_6123.CR3`, byte for byte the card's.
    @Test func copiesVerifiedWithTemplate() async throws {
        let card = try IngestFixture()
        defer { card.cleanUp() }
        try card.add("DCIM/100CANON/IMG_6123.CR3", bytes: 3_000_000, date: Self.shot)
        try card.add("DCIM/100CANON/IMG_6123.JPG", bytes: 400_000, date: Self.shot)
        try card.add("DCIM/100CANON/MVI_6124.MP4", bytes: 2_500_000, date: Self.shot)
        try card.add("DCIM/100CANON/MVI_6124.THM", bytes: 1_000, date: Self.shot)
        let (summary, events) = try await card.importAll(template: FileNameTemplate("{date}_Kyoto_{originalNumber}"),
                                                         folders: IngestFolderTemplate(pattern: "RAW/{year}/{date}"))
        #expect(summary.ending == .finished)
        #expect(summary.imported.count == 2)
        #expect(try card.destinationFiles() == [
            "RAW/2026/2026-10-03/2026-10-03_Kyoto_6123.CR3",
            "RAW/2026/2026-10-03/2026-10-03_Kyoto_6123.JPG",
            "RAW/2026/2026-10-03/2026-10-03_Kyoto_6124.MP4",
        ])
        #expect(try card.sha("RAW/2026/2026-10-03/2026-10-03_Kyoto_6123.CR3", onDestination: true)
                == card.sha("DCIM/100CANON/IMG_6123.CR3", onDestination: false))
        let verified = events.compactMap { if case .fileVerified(_, let file, _, let sha) = $0 { (file.name, sha) } else { nil } }
        #expect(verified.count == 3)
        #expect(verified.first?.1 == (try card.sha("DCIM/100CANON/IMG_6123.CR3", onDestination: false)))
    }
}
