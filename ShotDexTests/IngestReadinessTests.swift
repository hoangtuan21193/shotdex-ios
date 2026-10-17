import Foundation
import Testing
@testable import ShotDex

/// FS-20 §6, §8: Import dims, and says why, before a single byte is written.
@Suite struct IngestReadinessTests {
    static let t7 = IngestReadiness.Drive(name: "T7", isConnected: true, freeBytes: 12_000_000_000)

    /// AC-11: 24.6 GB checked, 12.0 GB free on T7.
    @Test func notEnoughSpaceDimsImport() {
        let readiness = IngestReadiness(checkedCount: 811, checkedBytes: 24_600_000_000, destination: Self.t7)
        #expect(!readiness.canImport)
        #expect(readiness.footer == "Needs 24.6 GB, 12.0 GB free on T7.")
        #expect(IngestReadiness(checkedCount: 811, checkedBytes: 11_000_000_000, destination: Self.t7).canImport)
    }

    /// AC-8: backup on, LaCie not plugged in.
    @Test func backupDriveMissingDims() {
        let readiness = IngestReadiness(checkedCount: 811, checkedBytes: 1_000, destination: Self.t7,
                                        backup: .init(name: "LaCie Backup", isConnected: false, freeBytes: nil))
        #expect(readiness.blocker == .backupNotConnected("LaCie Backup"))
        #expect(readiness.footer == "Connect “LaCie Backup” or turn off backup.")
    }

    @Test func nothingCheckedDimsWithoutAFooter() {
        let readiness = IngestReadiness(checkedCount: 0, checkedBytes: 0, destination: Self.t7)
        #expect(!readiness.canImport)
        #expect(readiness.footer == nil)
    }
}
