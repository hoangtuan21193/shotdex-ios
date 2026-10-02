import Foundation
import Testing
@testable import ShotDex

/// FS-03.04b §2 (Q2): one RAW extension list for the tile, the viewer, the
/// RAW smart album and the RAW-only rule.
struct FileTypeBadgeTests {
    @Test func oneListEverywhere() {
        #expect(Set(PhotoFileType.raw.extensions) == Set(FileTypeBadge.rawExtensions.map { $0.lowercased() }))
        #expect(FileTypeBadge.rawExtensions.contains("FFF"))
        for ext in FileTypeBadge.rawExtensions {
            #expect(FileTypeBadge.text(forExtension: ext.lowercased()) == "RAW")
            #expect(RAWVerdictStore.rawFilenameSQL.contains("'%.\(ext)'"))
        }
        #expect(FileTypeBadge.isRAW(filename: "DSC_0001.srw"))
        #expect(!FileTypeBadge.isRAW(filename: "IMG_0001.HEIC"))
        #expect(FileTypeBadge.text(forExtension: "jpeg") == "JPG")
    }
}
