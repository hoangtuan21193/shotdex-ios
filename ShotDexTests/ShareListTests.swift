import Foundation
import Testing
@testable import ShotDex

/// AC-30, list half: administrative shares stay out of Choose….
@Suite struct ShareListTests {
    @Test func hidesSystemShares() {
        #expect(SMBShareNames.visible(["photos", "IPC$", "backup", "ADMIN$", "print$"]) == ["backup", "photos"])
    }
}
