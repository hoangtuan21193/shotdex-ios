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
