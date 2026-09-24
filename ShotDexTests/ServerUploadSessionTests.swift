import CryptoKit
import Foundation
import Testing
@testable import ShotDex

/// One batch against an in-memory server (FS-15.02 §4, AC-3…AC-6): what lands
/// under a real name is always verified, and every way out cleans up.
@Suite struct ServerUploadSessionTests {
    private func sha(_ data: Data) -> String { FileChecksum.hex(SHA256.hash(data: data)) }

    private func partFiles(_ client: InMemoryRemoteFileClient) -> [String] {
        client.files.keys.filter { $0.hasSuffix(ServerUploadPath.partSuffix) }
    }

    @Test func uploadsVerifiesAndRecords() async {
        let fixture = UploadFixture(count: 3)
        let client = InMemoryRemoteFileClient()
        let recorder = UploadRecorder()

        let result = await makeSession(fixture, client: client, recorder: recorder).run(fixture.items)

        #expect(result.stopReason == nil)
        #expect(result.outcomes == fixture.items.map { .uploaded(remotePath: $0.remotePath) })
        #expect(Set(client.files.keys) == Set(fixture.items.map(\.remotePath)))
        #expect(partFiles(client).isEmpty)
        #expect(recorder.records.count == 3)
        for (index, row) in recorder.records.enumerated() {
            #expect(row.sha256 == sha(fixture.data(index)))
            #expect(row.byteCount == 10_000_000)
            #expect(row.serverName == "NAS")
        }
        #expect(fixture.leftoverFiles.isEmpty)
    }

    @Test func checksumMismatchLeavesNoFile() async {
        let fixture = UploadFixture(count: 3, bytes: 1_000)
        let client = InMemoryRemoteFileClient()
        client.corruptReadBack = [fixture.items[1].remotePath]
        let recorder = UploadRecorder()

        let result = await makeSession(fixture, client: client, recorder: recorder).run(fixture.items)

        #expect(result.stopReason == nil)
        #expect(result.outcomes[0] == .uploaded(remotePath: fixture.items[0].remotePath))
        guard case .failed = result.outcomes[1] else {
            Issue.record("file 2 should fail its checksum, got \(result.outcomes[1])")
            return
        }
        #expect(result.outcomes[2] == .uploaded(remotePath: fixture.items[2].remotePath))
        #expect(client.files[fixture.items[1].remotePath] == nil)
        #expect(partFiles(client).isEmpty)
        #expect(recorder.records.map(\.assetId) == ["A0", "A2"])
    }

    @Test func connectionLossStopsBatch() async {
        let fixture = UploadFixture(count: 4, bytes: 1_000)
        let client = InMemoryRemoteFileClient()
        client.dropConnectionOnUpload = 2
        let recorder = UploadRecorder()

        let result = await makeSession(fixture, client: client, recorder: recorder).run(fixture.items)

        #expect(result.stopReason == .error(.connectionLost))
        #expect(result.outcomes[0].isOnServer)
        #expect(!result.outcomes[1].isOnServer)
        #expect(result.outcomes[2] == .notAttempted)
        #expect(result.outcomes[3] == .notAttempted)
        #expect(partFiles(client).isEmpty)
        #expect(client.files[fixture.items[1].remotePath] == nil)

        // Upload Remaining = everything not on the server.
        let remaining = zip(fixture.items, result.outcomes).filter { !$0.1.isOnServer }.map(\.0)
        #expect(remaining.map(\.assetId) == ["A1", "A2", "A3"])
        client.dropConnectionOnUpload = nil
        let retry = await makeSession(fixture, client: client, recorder: recorder).run(remaining)
        #expect(retry.outcomes.allSatisfy { $0.isOnServer })
        #expect(recorder.records.count == 4)
    }

    @Test func cancelCleansPartAndTemp() async {
        let fixture = UploadFixture(count: 5, bytes: 1_000)
        let client = InMemoryRemoteFileClient()
        let recorder = UploadRecorder()
        let session = makeSession(fixture, client: client, recorder: recorder)
        // The hook goes in before the task exists, so upload 3 cannot slip
        // past it; it cancels whatever task the box holds by then.
        let box = TaskBox()
        client.onUpload = { number in if number == 3 { box.cancel() } }
        let task = Task { await session.run(fixture.items) }
        box.set(task)

        let result = await task.value

        #expect(result.stopReason == .cancelled)
        #expect(result.outcomes[0].isOnServer)
        #expect(result.outcomes[1].isOnServer)
        #expect(result.outcomes[2...].allSatisfy { $0 == .notAttempted })
        #expect(Set(client.files.keys) == [fixture.items[0].remotePath, fixture.items[1].remotePath])
        #expect(partFiles(client).isEmpty)
        #expect(recorder.records.count == 2)
        #expect(fixture.leftoverFiles.isEmpty)
    }

    @Test func unreadableAssetFailsOnlyItsFile() async {
        let good = UploadFixture(count: 2, bytes: 100)
        let ghost = ServerUploadItem(
            assetId: "gone",
            file: AssetUploadFile(key: "photo:x.dng", filename: "x.dng", isRAW: true, role: .original, estimatedBytes: 100),
            remotePath: "Photos/x.dng"
        )
        let client = InMemoryRemoteFileClient()
        let recorder = UploadRecorder()

        let result = await makeSession(good, client: client, recorder: recorder).run([good.items[0], ghost, good.items[1]])

        #expect(result.stopReason == nil)
        #expect(result.outcomes[0].isOnServer)
        #expect(!result.outcomes[1].isOnServer)
        #expect(result.outcomes[2].isOnServer)
    }
}

/// Same name already on the server (FS-15.02 §5, AC-8, AC-9).
@Suite struct ServerUploadConflictTests {
    @Test func applyToRemainingAsksOnce() async {
        let fixture = UploadFixture(count: 3, bytes: 500)
        let client = InMemoryRemoteFileClient()
        for item in fixture.items { client.put(item.remotePath, Data("older".utf8)) }
        let recorder = UploadRecorder()

        let result = await makeSession(fixture, client: client, recorder: recorder) { _ in
            .init(choice: .skip, appliesToRemaining: true)
        }.run(fixture.items)

        #expect(recorder.conflicts.count == 1)
        #expect(result.outcomes == [.skipped, .skipped, .skipped])
        #expect(client.files.values.allSatisfy { $0 == Data("older".utf8) })
        #expect(recorder.records.isEmpty)
    }

    @Test func identicalFileCountsAsUploaded() async {
        let fixture = UploadFixture(count: 1, bytes: 2_000)
        let client = InMemoryRemoteFileClient()
        client.put(fixture.items[0].remotePath, fixture.data(0))
        let recorder = UploadRecorder()

        let result = await makeSession(fixture, client: client, recorder: recorder).run(fixture.items)

        #expect(recorder.conflicts.isEmpty)
        #expect(client.uploadCount == 0)
        #expect(result.outcomes == [.alreadyThere(remotePath: fixture.items[0].remotePath)])
        #expect(recorder.records.count == 1)
    }

    @Test func keepBothWritesBesideTheOld() async {
        let fixture = UploadFixture(count: 1, bytes: 500, names: ["IMG_1.CR3"])
        let client = InMemoryRemoteFileClient()
        let dir = "Photos/2026/2026-09-24"
        client.put("\(dir)/IMG_1.CR3", Data("a".utf8))
        client.put("\(dir)/IMG_1 (2).CR3", Data("b".utf8))
        let recorder = UploadRecorder()

        let result = await makeSession(fixture, client: client, recorder: recorder) { _ in .init(choice: .keepBoth) }
            .run(fixture.items)

        #expect(result.outcomes == [.uploaded(remotePath: "\(dir)/IMG_1 (3).CR3")])
        #expect(client.files["\(dir)/IMG_1.CR3"] == Data("a".utf8))
        #expect(client.files["\(dir)/IMG_1 (3).CR3"] == fixture.data(0))
        #expect(recorder.records.first?.remotePath == "\(dir)/IMG_1 (3).CR3")
    }

    @Test func replaceOverwritesOnlyAfterVerify() async {
        let fixture = UploadFixture(count: 1, bytes: 500)
        let client = InMemoryRemoteFileClient()
        let path = fixture.items[0].remotePath
        client.put(path, Data("old".utf8))
        client.corruptReadBack = [path]
        let recorder = UploadRecorder()

        let result = await makeSession(fixture, client: client, recorder: recorder) { _ in .init(choice: .replace) }
            .run(fixture.items)

        // The new copy failed its check, so the old file must still be there.
        guard case .failed = result.outcomes[0] else {
            Issue.record("expected a checksum failure, got \(result.outcomes[0])")
            return
        }
        #expect(client.files[path] == Data("old".utf8))
        #expect(client.files.count == 1)
    }
}

/// Which photos "Delete from iPhone" may offer (FS-15.02 §7, AC-10).
@Suite struct ServerUploadEligibilityTests {
    private let rawA = AssetUploadFile(key: "photo:A.CR3", filename: "A.CR3", isRAW: true, role: .original, estimatedBytes: 1)
    private let rawB = AssetUploadFile(key: "photo:B.CR3", filename: "B.CR3", isRAW: true, role: .original, estimatedBytes: 1)
    private let jpegB = AssetUploadFile(key: "alternatePhoto:B.JPG", filename: "B.JPG", isRAW: false, role: .original, estimatedBytes: 1)
    private let editedB = AssetUploadFile(key: "fullSizePhoto:B.jpg", filename: "B.jpg", isRAW: false, role: .edited, estimatedBytes: 1)

    @Test func pairNeedsBothFiles() {
        let verdict = ServerUploadEligibility.evaluate(
            assets: [("A", [rawA]), ("B", [rawB, jpegB])],
            uploadedKeys: ["A": [rawA.key], "B": [rawB.key]]
        )
        #expect(verdict.deletable == ["A"])
        #expect(verdict.missing == ["B": ["B.JPG"]])
    }

    @Test func pairOnTwoServersIsDeletable() {
        // RAW went up today, the JPEG last month to another server: the
        // history does not care which server, only that both are somewhere.
        let verdict = ServerUploadEligibility.evaluate(
            assets: [("B", [rawB, jpegB, editedB])],
            uploadedKeys: ["B": [rawB.key, jpegB.key]]
        )
        #expect(verdict.deletable == ["B"])
    }

    @Test func nothingUploadedIsNeitherOfferedNorExplained() {
        let verdict = ServerUploadEligibility.evaluate(assets: [("A", [rawA])], uploadedKeys: [:])
        #expect(verdict == .init())
    }
}

private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<ServerUploadResult, Never>?
    private var cancelled = false

    func set(_ task: Task<ServerUploadResult, Never>) {
        lock.withLock {
            self.task = task
            if cancelled { task.cancel() }
        }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            task?.cancel()
        }
    }
}
