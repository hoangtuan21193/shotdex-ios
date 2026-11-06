import Foundation
import GRDB
import Testing
@testable import ShotDex

/// The Mac app and its helper open the same file: a write that meets the
/// other's lock waits for it instead of failing with "database is locked"
/// (seen mid-Move on 14,000 photos, 2026-11-06).
@Suite struct AppDatabaseBusyTests {
    @Test func writeWaitsForTheOtherProcessLock() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("shared.sqlite").path
        // Two pools on one file stand in for the two processes.
        let app = try DatabasePool(path: path, configuration: AppDatabase.sharedConfiguration)
        let helper = try DatabasePool(path: path, configuration: AppDatabase.sharedConfiguration)
        try app.write { try $0.execute(sql: "CREATE TABLE t (v INTEGER)") }

        let locked = DispatchSemaphore(value: 0)
        let released = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            try? helper.write { db in
                try db.execute(sql: "INSERT INTO t VALUES (1)")
                locked.signal()
                Thread.sleep(forTimeInterval: 0.5)
            }
            released.signal()
        }
        locked.wait()
        try app.write { try $0.execute(sql: "INSERT INTO t VALUES (2)") }
        released.wait()

        #expect(try app.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM t") } == 2)
    }
}
