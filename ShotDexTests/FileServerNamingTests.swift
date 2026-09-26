import Foundation
import Testing
@testable import ShotDex

/// AC-18: two connections never share a name, because the ⋯ menu lists
/// nothing else.
@Suite struct FileServerNamingTests {
    @Test func duplicateNamesGetNumbered() {
        #expect(FileServerNaming.uniqueName("nas.local", existing: ["nas.local", "NAS"]) == "nas.local (2)")
        #expect(FileServerNaming.uniqueName("nas", existing: ["nas.local", "NAS"]) == "nas (2)")
        #expect(FileServerNaming.uniqueName("NAS", existing: ["NAS", "nas (2)"]) == "NAS (3)")
        #expect(FileServerNaming.uniqueName("Office", existing: ["NAS"]) == "Office")
    }
}
