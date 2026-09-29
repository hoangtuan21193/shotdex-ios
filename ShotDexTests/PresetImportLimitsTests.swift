import Foundation
import Testing
@testable import ShotDex

struct PresetImportLimitsTests {
    /// FS-03.14 AC-a5. A 50 MB .xmp is refused as "Larger than 5 MB — not a
    /// preset" from its reported size: the file here is sparse, 50 MB long
    /// with nothing written, so reading it would be the only way to notice.
    @Test func oversizedFileIsRefusedUnread() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("huge-\(UUID().uuidString).xmp")
        #expect(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 50_000_000)
        try handle.close()
        defer { try? FileManager.default.removeItem(at: url) }
        let outcome = PresetImportLimits.check(url)
        #expect(outcome == .failure(.tooLarge(limitMegabytes: 5)))
        if case let .failure(refusal) = outcome {
            #expect(refusal.message == "Larger than 5 MB — not a preset")
        }

        let small = FileManager.default.temporaryDirectory.appendingPathComponent("small-\(UUID().uuidString).lrtemplate")
        try Data("s = {}".utf8).write(to: small)
        defer { try? FileManager.default.removeItem(at: small) }
        #expect(PresetImportLimits.check(small) == .success(.lrtemplate))
        #expect(PresetImportLimits.Kind.dng.maximumBytes == 200_000_000)
        #expect(PresetImportLimits.Kind.shotdexlook.maximumBytes == 16_000_000)
    }
}
