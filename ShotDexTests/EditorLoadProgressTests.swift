import Foundation
import Photos
import Testing
@testable import ShotDex

/// FS-02.06 AC-3, AC-4: the editor's download says how far it is, and Close
/// stops it and leaves nothing behind.
@MainActor
@Suite(.serialized) struct EditorLoadProgressTests {
    /// AC-3. PhotoKit's progress reaches the stage; a source that is not the
    /// whole photo is an iCloud failure, never an edit of a preview.
    @Test func progressReachesTheStageAndAShortSourceFails() throws {
        let service = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Data/Sources/PhotoEditingService.swift")
            .joined(separator: "\n")
        let request = try #require(service.range(of: "private func requestContentEditingInput("))
        let body = String(service[request.lowerBound...].prefix(2400))
        #expect(body.contains("options.progressHandler = { value, _ in progress(value) }"))
        #expect(body.contains("asset.cancelContentEditingInputRequest(id)"))
        #expect(service.contains("try Self.checkComplete(input, of: asset)"))
        #expect(EditorLoadFailure.classify(OriginalFetchError.incomplete, accessIsLimited: false) == .iCloudDownload)

        let stage = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Editing/EditorImageStage.swift")
            .joined(separator: "\n")
        #expect(stage.contains("Text(\"Downloading from iCloud… \\(percent)%\")"))
        #expect(stage.contains("ProgressView(value: min(1, max(0, fraction)))"))
    }

    /// AC-4. A session that finishes opening after the editor closed is
    /// thrown away at once — no `ShotDexPhoto-` folder waits for the next
    /// launch's sweep.
    @Test func aSessionMadeAfterCloseLeavesNoFolder() async throws {
        let run = ServerComposeToolTests.Run()
        defer { try? FileManager.default.removeItem(at: run.directory) }
        let photo = try run.photos(["A.jpg"])[0]
        // A root of its own: other suites open sessions in the shared
        // temporary directory at the same time.
        let root = run.directory.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let service = PhotoEditingService(temporaryRoot: root)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.beginSession(for: .serverFile(photo), isOnCanvas: true)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Self.sessionFolders(in: root).isEmpty)
    }

    /// AC-4. The scripted download stops at the next tick once cancelled —
    /// at 30%, well within a second.
    @Test func cancelAtThirtyPercentStopsTheDownload() async throws {
        let fake = FakeOriginalFetcher(script: .init("cloud=all,seconds=10"), base: FixtureOriginalFetcher())
        let ticks = Ticks()
        let download = Task { try await fake.scriptedTransfer(for: "A") { ticks.add($0) } }
        for _ in 0..<100 where (ticks.values.last ?? 0) < 0.3 { try await Task.sleep(for: .milliseconds(50)) }
        let pressed = ContinuousClock.now
        download.cancel()
        await #expect(throws: CancellationError.self) { try await download.value }
        #expect(ContinuousClock.now - pressed < .seconds(1))
        #expect(fake.cancelledCount == 1)
        #expect(await fake.probe(.test("A")) == .inCloud)
    }

    static func sessionFolders(in root: URL) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return Set(names.filter { $0.hasPrefix("ShotDexPhoto-") })
    }
}
