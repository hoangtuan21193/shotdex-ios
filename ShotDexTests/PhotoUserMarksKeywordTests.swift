import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-18.02 §2: keywords added to and taken off a whole selection of file
/// photos (the Mac inspector).
struct PhotoUserMarksKeywordTests {
    private func keywords(_ database: AppDatabase, _ id: String) throws -> [String] {
        try database.reader.read { db in
            try String.fetchAll(db, sql: "SELECT keyword FROM photo_user_keyword WHERE photoId = ? ORDER BY keyword", arguments: [id])
        }
    }

    @Test func addingKeepsAnotherCaseAndRemovingTakesEveryCase() throws {
        let database = try AppDatabase.makeEmpty()
        let store = PhotoUserMarksStore(database: database)
        try database.writer.write { db in try PhotoUserMarksStore.addKeywords(db, ["kyoto"], photoId: "a", at: 1) }

        try store.addKeyword("Kyoto", photoIds: ["a", "b"])
        #expect(try keywords(database, "a") == ["kyoto"])
        #expect(try keywords(database, "b") == ["Kyoto"])

        try store.removeKeyword("KYOTO", photoIds: ["a", "b"])
        #expect(try keywords(database, "a").isEmpty)
        #expect(try keywords(database, "b").isEmpty)
    }
}
