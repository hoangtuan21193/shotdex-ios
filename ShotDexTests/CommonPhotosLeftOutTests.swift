import Foundation
import Testing
@testable import ShotDex

/// FS-19.08 §6d: photos left out of a set stay out — every later scan, Run
/// Again and Keep gathering skips them until Include.
@MainActor
@Suite struct CommonPhotosLeftOutTests {
    /// Three Same photos in A and B on connection "S1", destination C.
    private static func nas() -> InMemoryRemoteFileClient {
        let nas = InMemoryRemoteFileClient()
        for index in 1...3 {
            let bytes = Data((0..<(3_000 + index)).map { UInt8(truncatingIfNeeded: $0 &* (index + 3)) })
            nas.put("A/IMG_\(index).JPG", bytes)
            nas.put("B/IMG_\(index).JPG", bytes)
        }
        nas.addDirectory("C")
        return nas
    }

    private static func scanned(_ nas: InMemoryRemoteFileClient, _ database: AppDatabase) async throws -> CommonPhotosScanModel {
        let sheet = CommonPhotosScanModel(connectionId: "S1", sourceId: "source", folders: ["A", "B"], client: nas, database: database)
        sheet.destination = "C"
        sheet.scan()
        for _ in 0..<300 where sheet.phase != .done || sheet.isCutting || sheet.isPlanning {
            if case .failed(let message) = sheet.phase { Issue.record("scan failed: \(message)"); break }
            try await Task.sleep(for: .milliseconds(20))
        }
        return sheet
    }

    /// AC-187: IMG_3 unchecked in one sheet; the next scan of the set lists
    /// it under Left Out (1), not as a row, and the run leaves it.
    @Test func leftOutStaysOut() async throws {
        let nas = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let first = try await Self.scanned(nas, database)
        let out = try #require(first.rows.first { $0.name == "IMG_3.JPG" })
        first.setIncluded(false, rows: [out.id])
        await first.close()

        let again = try await Self.scanned(nas, database)

        #expect(Set(again.rows.map(\.name)) == ["IMG_1.JPG", "IMG_2.JPG"])
        #expect(again.leftOutEntries.map(\.name) == ["IMG_3.JPG"])
        #expect(again.sameCount == 2)
        #expect(again.makeRun()?.items.count == 2)
        await again.close()
    }

    /// AC-187: Keep gathering's pass (the helper, `scanToEnd`) does not find
    /// the left-out photo either.
    @Test func gatherPassSkipsIt() async throws {
        let nas = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let first = try await Self.scanned(nas, database)
        first.setIncluded(false, rows: Set(first.rows.filter { $0.name != "IMG_1.JPG" }.map(\.id)))
        await first.close()

        let pass = CommonPhotosScanModel(connectionId: "S1", sourceId: "", folders: ["A", "B"], client: nas, database: database)
        pass.destination = "C"
        await pass.scanToEnd()

        #expect(pass.includedPhotos.count == 1)
        #expect(pass.makeRun()?.items.count == 1)
        await pass.close()
    }

    /// AC-188: Include one of two — it is a row again, checked, now and in
    /// the next scan; the other stays out.
    @Test func includeBringsItBack() async throws {
        let nas = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let first = try await Self.scanned(nas, database)
        first.setIncluded(false, rows: Set(first.rows.filter { $0.name != "IMG_1.JPG" }.map(\.id)))
        await first.close()
        let again = try await Self.scanned(nas, database)
        let back = try #require(again.leftOutEntries.first { $0.name == "IMG_2.JPG" })

        again.include([back.sha256])

        #expect(again.rows.first { $0.name == "IMG_2.JPG" }?.isIncluded == true)
        #expect(again.leftOutEntries.map(\.name) == ["IMG_3.JPG"])
        await again.close()
        let third = try await Self.scanned(nas, database)
        #expect(Set(third.rows.map(\.name)) == ["IMG_1.JPG", "IMG_2.JPG"])
        #expect(third.leftOutEntries.map(\.name) == ["IMG_3.JPG"])
        await third.close()
    }

    /// Unchecked before a destination is chosen: stored once there is one.
    @Test func uncheckedBeforeADestination() async throws {
        let nas = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let sheet = CommonPhotosScanModel(connectionId: "S1", sourceId: "source", folders: ["A", "B"], client: nas, database: database)
        sheet.scan()
        for _ in 0..<300 where sheet.phase != .done { try await Task.sleep(for: .milliseconds(20)) }
        let out = try #require(sheet.rows.first { $0.name == "IMG_2.JPG" })
        sheet.setIncluded(false, rows: [out.id])
        sheet.destination = "C"
        await sheet.close()

        let again = try await Self.scanned(nas, database)
        #expect(again.leftOutEntries.map(\.name) == ["IMG_2.JPG"])
        await again.close()
    }

    /// Unchecked with no destination, then a folder added: another set —
    /// the old choice is not stored into it.
    @Test func anotherFolderIsAnotherSet() async throws {
        let nas = Self.nas()
        nas.addDirectory("E")
        let database = try AppDatabase.makeEmpty()
        let sheet = CommonPhotosScanModel(connectionId: "S1", sourceId: "source", folders: ["A", "B"], client: nas, database: database)
        sheet.scan()
        for _ in 0..<300 where sheet.phase != .done { try await Task.sleep(for: .milliseconds(20)) }
        sheet.setIncluded(false, rows: Set(sheet.rows.filter { $0.name == "IMG_2.JPG" }.map(\.id)))
        sheet.add(folder: "E")
        #expect(sheet.leftOut.isEmpty)
        sheet.remove(folder: "E")
        sheet.destination = "C"
        #expect(try CommonPhotosLeftOutStore(database: database)
            .entries(setKey: CommonPhotosIncremental.setKey(connectionId: "S1", folders: ["A", "B"], destination: "C")).isEmpty)
        await sheet.close()
    }

    /// AC-189: Clear Local Metadata Index keeps the Left Out list; Remove
    /// from List takes the set's; deleting the connection takes all of its.
    @Test func whatClearsIt() throws {
        let database = try AppDatabase.makeEmpty()
        let servers = FileServerStore(database: database, passwords: InMemoryPasswordStore())
        try servers.save(FileServer(id: "S1", name: "NAS Home", transferProtocol: .webdav, host: "127.0.0.1", username: "me"), password: "pw")
        let store = CommonPhotosLeftOutStore(database: database)
        let keyC = CommonPhotosIncremental.setKey(connectionId: "S1", folders: ["A", "B"], destination: "C")
        let keyD = CommonPhotosIncremental.setKey(connectionId: "S1", folders: ["A", "B"], destination: "D")
        let two = [CommonPhotosLeftOutStore.Photo(sha256: "x", name: "IMG_1.JPG", size: 1),
                   CommonPhotosLeftOutStore.Photo(sha256: "y", name: "IMG_2.JPG", size: 2)]
        try store.leaveOut(two, setKey: keyC, connectionId: "S1")
        try store.leaveOut(two, setKey: keyD, connectionId: "S1")

        try MetadataStore(database: database).deleteAll()
        #expect(try store.entries(setKey: keyC).count == 2)

        let watches = CommonPhotosWatchStore(database: database)
        let watch = try watches.keepGathering(connectionId: "S1", folders: ["A", "B"], destination: "C", action: .copy)
        try watches.stopGathering(id: watch.id)
        try watches.remove(id: watch.id)
        #expect(try store.entries(setKey: keyC).isEmpty)
        #expect(try store.entries(setKey: keyD).count == 2)

        try servers.delete(id: "S1")
        #expect(try store.entries(setKey: keyD).isEmpty)
    }
}
