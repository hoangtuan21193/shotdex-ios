import Foundation
import Testing
@testable import ShotDex

/// FS-19.08 §4–5: the Find Common Photos sheet's logic — what stops a run,
/// and, on the local SMB test server, a scan read-only end to end.
@MainActor
@Suite struct CommonPhotosScanModelTests {
    private func smb() -> SMBFileClient {
        SMBFileClient(server: FileServer(name: "Test SMB", transferProtocol: .smb, host: "127.0.0.1", port: 4450,
                                         username: "tester", share: "photos"),
                      password: "secret")
    }

    private func model(_ folders: [String]) -> CommonPhotosScanModel {
        CommonPhotosScanModel(connectionId: "smb", sourceId: "source", folders: folders, client: smb())
    }

    @Test func whatStopsARun() {
        let sheet = model(["photos/Tuan"])
        #expect(sheet.problem == .selection(.tooFewFolders))
        #expect(!sheet.canScan)
        sheet.add(folder: "photos/Vo")
        #expect(sheet.problem == .noDestination)
        #expect(sheet.canScan)
        sheet.destination = "photos/Vo/own"
        #expect(sheet.problem == .selection(.destinationInsideSource(source: "photos/Vo")))
        sheet.add(folder: "photos/Tuan/2025")
        #expect(sheet.problem == .selection(.nested(outer: "photos/Tuan", inner: "photos/Tuan/2025")))
        #expect(!sheet.canScan)
        sheet.remove(folder: "photos/Tuan/2025")
        sheet.destination = "photos/Shared"
        #expect(sheet.problem == nil)
        // Nothing scanned yet: nothing to run.
        #expect(!sheet.canRun)
        #expect(sheet.makeRun()?.items == nil)
    }

    @Test func aFolderIsListedOnce() {
        let sheet = model(["photos/Tuan", "/photos/Tuan/", "photos/Vo"])
        #expect(sheet.folders == ["photos/Tuan", "photos/Vo"])
        sheet.add(folder: "photos/vo")
        #expect(sheet.folders.count == 2)
    }

    /// AC-174: the scan loses the server part-way — the list holds only the
    /// photos proven Same, every one of them; what it never reached is a
    /// count ("Not checked"), not rows.
    @Test func onlySameRows() async throws {
        let nas = InMemoryRemoteFileClient()
        for index in 1...6 {
            let bytes = Data((0..<(2_000 + index)).map { UInt8(truncatingIfNeeded: $0 &* index) })
            nas.put("A/IMG_\(index).JPG", bytes)
            nas.put("B/IMG_\(index).JPG", bytes)
        }
        let sheet = CommonPhotosScanModel(connectionId: "nas", sourceId: "source", folders: ["A", "B"], client: nas)
        sheet.destination = "C"
        nas.failRangeReadsAfter = 5
        sheet.scan()
        for _ in 0..<200 where sheet.isScanning || sheet.phase == .idle {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(sheet.failure != nil)
        #expect(sheet.sameCount > 0)
        #expect(sheet.rows.count == sheet.sameCount)
        #expect(Set(sheet.rows.map(\.name)) == Set(sheet.photos.map { $0.files[0][0].name }))
        // Every group decided before the failure is counted, none twice.
        #expect(sheet.checkedFiles + sheet.notCheckedCount == sheet.candidateCount)
        #expect(sheet.checkedFiles >= sheet.sameCount)
        #expect(sheet.notCheckedCount > 0)
        await sheet.close()
    }

    /// Three Same photos in A and B; the destination C holds IMG_1's bytes
    /// and another file named img_2.jpg of IMG_2's size.
    private func planned() async throws -> (CommonPhotosScanModel, InMemoryRemoteFileClient, [String: Data]) {
        let nas = InMemoryRemoteFileClient()
        var photos: [String: Data] = [:]
        for index in 1...3 {
            let bytes = Data((0..<(3_000 + index)).map { UInt8(truncatingIfNeeded: $0 &* (index + 1)) })
            nas.put("A/IMG_\(index).JPG", bytes)
            nas.put("B/x/IMG_\(index).JPG", bytes)
            photos["IMG_\(index).JPG"] = bytes
        }
        nas.put("C/IMG_1.JPG", photos["IMG_1.JPG"]!)
        nas.put("C/img_2.jpg", Data(repeating: 9, count: photos["IMG_2.JPG"]!.count))
        let sheet = CommonPhotosScanModel(connectionId: "nas", sourceId: "source", folders: ["A", "B"], client: nas)
        sheet.destination = "C"
        sheet.action = .move
        sheet.scan()
        for _ in 0..<300 where sheet.phase != .done || sheet.landings.count < 3 {
            if case .failed(let message) = sheet.phase { Issue.record("scan failed: \(message)"); break }
            try await Task.sleep(for: .milliseconds(20))
        }
        return (sheet, nas, photos)
    }

    /// AC-175, AC-176: each row says what it becomes in C — Already in C,
    /// the next free name, its own name — and how many copies a Move takes
    /// out; only the one file whose bytes decide is read in C.
    @Test func rowsCarryThePlan() async throws {
        let (sheet, nas, _) = try await planned()
        let landing = Dictionary(uniqueKeysWithValues: sheet.rows.map { ($0.name, $0.landing) })
        #expect(landing["IMG_1.JPG"] == .alreadyThere("IMG_1.JPG"))
        #expect(landing["IMG_2.JPG"] == .name("IMG_2 (2).JPG"))
        #expect(landing["IMG_3.JPG"] == .name("IMG_3.JPG"))
        #expect(sheet.alreadyThereCount == 1)
        #expect(sheet.rows.allSatisfy { $0.copies == 2 })
        #expect(Set(nas.sha256Paths.filter { $0.hasPrefix("C/") }) == ["C/IMG_1.JPG", "C/img_2.jpg"])
        await sheet.close()
    }

    /// AC-175: Copy counts only what it writes — the photo already in C is
    /// not in the button; a Move still takes it out of A and B.
    @Test func runCountLeavesOutWhatIsThere() async throws {
        let (sheet, _, _) = try await planned()
        #expect(sheet.runCount == 3)
        sheet.action = .copy
        #expect(sheet.runCount == 2)
        await sheet.close()
    }

    /// A destination chosen after the scan gets its plan; flipping away and
    /// back reads none of its files again (same size and write time).
    @Test func destinationChosenAfterTheScan() async throws {
        let nas = InMemoryRemoteFileClient()
        let bytes = Data((0..<3_001).map { UInt8(truncatingIfNeeded: $0) })
        nas.put("A/IMG_1.JPG", bytes)
        nas.put("B/IMG_1.JPG", bytes)
        nas.put("C/IMG_1.JPG", bytes)
        nas.modified["C/IMG_1.JPG"] = Date(timeIntervalSince1970: 1_000)
        nas.addDirectory("D")
        let sheet = CommonPhotosScanModel(connectionId: "nas", sourceId: "source", folders: ["A", "B"], client: nas)
        sheet.scan()
        for _ in 0..<300 where sheet.phase != .done { try await Task.sleep(for: .milliseconds(20)) }
        #expect(sheet.rows.first?.landing == nil)

        for destination in ["C", "D", "C"] {
            sheet.destination = destination
            for _ in 0..<300 where sheet.isCutting || sheet.landings.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
            #expect(sheet.rows.first?.landing == (destination == "C" ? .alreadyThere("IMG_1.JPG") : .name("IMG_1.JPG")))
        }
        #expect(nas.sha256Paths.filter { $0 == "C/IMG_1.JPG" }.count == 1)
        await sheet.close()
    }

    /// AC-180, the row's side: the row said `IMG_2 (2).JPG`; that name is
    /// taken before the run — the photo lands as `IMG_2 (3).JPG`.
    @Test func runNamesFromTheDestinationAsItIsThen() async throws {
        let (sheet, nas, photos) = try await planned()
        sheet.action = .copy
        #expect(sheet.rows.first { $0.name == "IMG_2.JPG" }?.landing == .name("IMG_2 (2).JPG"))
        nas.put("C/IMG_2 (2).JPG", Data(repeating: 4, count: 10))
        let made = try #require(sheet.makeRun())
        let store = CommonPhotosStore(database: try AppDatabase.makeEmpty())
        try store.start(made.run, items: made.items)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("CommonPhotosScanModelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }

        try await CommonPhotosRunner(client: nas, store: store, workDirectory: work).run(made.run.id)

        let item = try #require(try store.items(runId: made.run.id).first { $0.sources.first?.path == "A/IMG_2.JPG" })
        #expect(item.destinationPath == "C/IMG_2 (3).JPG")
        #expect(nas.files["C/IMG_2 (3).JPG"] == photos["IMG_2.JPG"])
        await sheet.close()
    }

    /// The fixture: 8 of Tuấn's 12 photos sit renamed in Vợ's `from-tuan`.
    /// Read-only — nothing is copied or written on the server.
    @Test(.enabled(if: LocalSMBTestServer.isListening))
    func scanOnTheServerFindsTheSharedPhotos() async throws {
        let sheet = model(["photos/Tuan", "photos/Vo"])
        sheet.destination = "photos/Shared"
        sheet.scan()
        for _ in 0..<600 where sheet.phase != .done {
            if case .failed(let message) = sheet.phase { Issue.record("scan failed: \(message)"); return }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(sheet.phase == .done)
        #expect(sheet.fileCounts == ["photos/Tuan": 12, "photos/Vo": 13])
        #expect(sheet.sameCount == 8)
        #expect(sheet.checkingCount == 0)
        #expect(sheet.rows.count == 8)
        // Folder and subfolder per copy; Vo's name differs, so it is named.
        let first = try #require(sheet.rows.first { $0.name == "IMG_0001.JPG" })
        #expect(first.paths == "Tuan/2025/06 · Vo/from-tuan as 2025-06-01 IMG_0001.JPG")
        #expect(first.fullPaths == "Tuan/2025/06/IMG_0001.JPG\nVo/from-tuan/2025-06-01 IMG_0001.JPG")
        #expect(sheet.canRun)
        let made = try #require(sheet.makeRun())
        #expect(made.run.folders == ["photos/Tuan", "photos/Vo"])
        #expect(made.run.destination == "photos/Shared")
        #expect(made.run.action == .copy)
        #expect(made.items.count == 8)
        #expect(made.items.allSatisfy { $0.sources.count == 2 })
        await sheet.close()
    }
}
