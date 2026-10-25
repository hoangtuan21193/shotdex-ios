import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.07 §9: a Photos item on a server folder is deleted only after the
/// server says, just before, that each matched file is still there.
@MainActor
struct PhotoDeletionGateTests {
    /// AC-88: 20 photos in the album; after the last check the script
    /// deletes 2 files. 18 go; the alert names the 2.
    @Test func reverifiesServerCopy() async throws {
        let g = try GateFixture(photos: 20)
        try await g.client.remove("iCloud Photo/Shared/IMG_3.HEIC")
        try await g.client.remove("iCloud Photo/Shared/IMG_7.HEIC")
        let outcome = await g.gate.check(photoIds: g.ids)
        #expect(outcome.verified.count == 18)
        #expect(outcome.notOnServer == ["NAS Home": ["P3", "P7"]])
        #expect(outcome.unreachable.isEmpty)
        // Not at its path: the source was listed once more before giving up.
        #expect(g.relists.value == 1)

        let flow = PhotoDeletionFlow()
        let deleted = Box<[String]>([])
        await g.run(flow) { deleted.value = $0 }
        flow.prompt?.action?()
        while deleted.value.isEmpty { await Task.yield() }
        #expect(Set(deleted.value) == Set(outcome.verified))
        while flow.prompt == nil { await Task.yield() }
        guard case .notDeleted(2, "NAS Home") = flow.prompt?.kind else { Issue.record("no alert"); return }
        #expect(PhotoDeletionCopy.title(flow.prompt!.kind) == "2 Photos Weren't Deleted")
        #expect(PhotoDeletionCopy.message(flow.prompt!.kind) == "They're no longer on NAS Home.")
    }

    /// AC-89: the server is off. The alert offers Delete Anyway and Cancel;
    /// Cancel deletes nothing.
    @Test func unreachableAsks() async throws {
        let g = try GateFixture(photos: 20)
        g.client.connectError = .unreachable(host: "nas.local")
        let outcome = await g.gate.check(photoIds: g.ids)
        #expect(outcome.unreachable == ["NAS Home": g.ids])
        #expect(outcome.deletable.isEmpty)

        let flow = PhotoDeletionFlow()
        let performed = Box(0)
        let cancelled = Box(false)
        flow.delete(g.ids, gate: g.gate, perform: { _ in performed.value += 1 }, finished: { result in
            if case .failure(is CancellationError) = result { cancelled.value = true }
        })
        while flow.prompt == nil { await Task.yield() }
        guard case .unreachable("NAS Home") = flow.prompt?.kind else { Issue.record("no alert"); return }
        #expect(PhotoDeletionCopy.title(flow.prompt!.kind) == "Can't Reach NAS Home")
        #expect(PhotoDeletionCopy.message(flow.prompt!.kind) == "ShotDex couldn't check that these are still on NAS Home.")
        flow.prompt?.cancel?()
        #expect(performed.value == 0)
        #expect(cancelled.value)
    }

    /// AC-90: deleting photos that are on a server says where they go and
    /// when iCloud space comes back.
    @Test func confirmNamesRecentlyDeleted() async throws {
        let g = try GateFixture(photos: 2)
        let flow = PhotoDeletionFlow()
        flow.delete(g.ids, gate: g.gate, perform: { _ in }, finished: { _ in })
        while flow.prompt == nil { await Task.yield() }
        guard let kind = flow.prompt?.kind, case .confirm(2, "NAS Home") = kind else { Issue.record("no confirm"); return }
        #expect(PhotoDeletionCopy.message(kind)
                == "They're on NAS Home. They move to Recently Deleted. iCloud space is freed after Recently Deleted is emptied.")
    }

    /// AC-95: Library's select-and-delete goes through the gate — a photo
    /// whose NAS file was deleted is kept.
    @Test func libraryDeleteRoutes() async throws {
        let g = try GateFixture(photos: 1)
        try await g.client.remove("iCloud Photo/Shared/IMG_0.HEIC")
        #expect(await g.gate.check(photoIds: ["P0"]).notOnServer == ["NAS Home": ["P0"]])
        let screen = try PhotoKitDeleteCallSites.source("ShotDex/Features/Library/LibraryScreen.swift")
        #expect(screen.contains("deletionFlow.delete(selectedIds, gate: dependencies.photoDeletionGate"))
    }

    /// AC-98: deleting the Photos copy leaves the server copy shown.
    @Test func serverCopyStaysVisible() async throws {
        let g = try GateFixture(photos: 1)
        let outcome = await g.gate.check(photoIds: ["P0"])
        #expect(outcome.verified == ["P0"])
        // What every Photos delete does to the index once PhotoKit is done.
        try MetadataStore(database: g.f.database).deleteAssets(ids: outcome.verified)
        let server = try await g.f.database.reader.read { db in
            try Row.fetchOne(db, sql: "SELECT missingSince, isHidden FROM photo_copies WHERE kind = 'server'")
                .map { (missingSince: $0["missingSince"] as Int?, isHidden: $0["isHidden"] as Bool) }
        }
        #expect(server?.missingSince == nil)
        #expect(server?.isHidden == false)
        #expect(try DeletionTargetQueries(database: g.f.database, hasTrash: { _ in false })
            .stillShown(photoIds: ["server:Shared/IMG_0.HEIC"]) == ["server:Shared/IMG_0.HEIC"])
    }

    /// AC-102: the file was rewritten with the same size after the last
    /// check — a new write time is enough to keep the photo.
    @Test func modifiedDateBlocks() async throws {
        let g = try GateFixture(photos: 1)
        g.client.modified["iCloud Photo/Shared/IMG_0.HEIC"] = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(await g.gate.check(photoIds: ["P0"]).notOnServer == ["NAS Home": ["P0"]])
    }

    /// AC-103: the script moved the file to another folder of the source.
    /// A fresh listing finds it by fast hash and size; the photo is deleted.
    @Test func reResolvesMovedFile() async throws {
        let data = try ServerSourceIndexTests.raw(padding: 4_096, seed: 9)
        let client = InMemoryRemoteFileClient()
        client.put("iCloud Photo/Shared/2025/a.ARW", data)
        let f = try OnServerFixture(photos: 1)
        let servers = FileServerStore(database: f.database, passwords: InMemoryPasswordStore())
        try servers.save(FileServer(id: "C1", name: "NAS Home", transferProtocol: .smb, host: "nas.local", username: "u",
                                    folder: "iCloud Photo"), password: "pw")
        let refresh = ServerSourceRefresh(database: f.database, servers: servers, composer: ServerSourceIndexTests.composer) { _, _ in client }
        _ = await refresh.rescan(sourceId: f.source)
        try f.photo(0, files: [("4:a.ARW", .raw, Int64(data.count), BackupFixture.sha(data))])
        try await ServerFileHashPass(store: CopyFileStore(database: f.database), client: client)
            .run(sourceId: f.source, connectionId: "C1", folder: "iCloud Photo")
        #expect(try await f.count(.isExactly) == 1)

        // The script makes the folder and moves the file there.
        client.put("iCloud Photo/Shared/x/b.ARW", data)
        try await client.remove("iCloud Photo/Shared/2025/a.ARW")
        let gate = PhotoDeletionGate(database: f.database, connect: { _ in (client, "iCloud Photo") },
                                     relist: { id in _ = await refresh.rescan(sourceId: id) })
        let reads = client.sha256Paths.count
        #expect(await gate.check(photoIds: ["P0"]).verified == ["P0"])
        #expect(client.sha256Paths.count == reads)
    }

    /// FS-19.07 N2 (T20): every other way to delete from Photos — viewer,
    /// albums, On This Day, Hidden, Duplicates, Bursts, Cull, the source
    /// deletion's Photos part — goes through the gate.
    @Test func everyEntryPointRoutes() async throws {
        for file in PhotoKitDeleteCallSites.gated {
            #expect(try PhotoKitDeleteCallSites.source(file).contains("deleteAssetsCheckingServer("), "\(file) deletes without the gate")
        }
        for model in ["ShotDex/Features/Library/LibraryModel.swift", "ShotDex/Features/Albums/SmartAlbumDetailModel.swift"] {
            #expect(try PhotoKitDeleteCallSites.source(model).contains("deleteAssetsCheckingServer(assets)"))
        }
        #expect(try PhotoKitDeleteCallSites.source("ShotDex/Data/Sources/PhotoEditingService.swift").contains("deletionGate.check(photoIds:"))
        // What those entry points say for the photos they keep.
        let g = try GateFixture(photos: 3)
        try await g.client.remove("iCloud Photo/Shared/IMG_1.HEIC")
        try await g.client.remove("iCloud Photo/Shared/IMG_2.HEIC")
        let kept = PhotoDeletionGate.Kept(outcome: await g.gate.check(photoIds: g.ids))
        #expect(kept.errorDescription == "2 photos weren't deleted — they're no longer on NAS Home.")
        g.client.connectError = .unreachable(host: "nas.local")
        let away = PhotoDeletionGate.Kept(outcome: await g.gate.check(photoIds: ["P0"]))
        #expect(away.errorDescription == "Can't reach NAS Home, so 1 photo wasn't deleted. ShotDex couldn't check that it's still there.")
    }

    /// AC-104: a PhotoKit delete added outside the known places fails here,
    /// naming the file and line.
    @Test func noNewDirectDeletes() throws {
        let found = try PhotoKitDeleteCallSites.scan()
        let unexpected = found.filter { site in
            (PhotoKitDeleteCallSites.known[site.file] ?? 0) < found.filter { $0.file == site.file }.count
        }
        #expect(unexpected.isEmpty, "PhotoKit delete outside the gate: \(unexpected.map { "\($0.file):\($0.line)" })")
        for screen in ["ShotDex/Features/Library/LibraryScreen.swift", "ShotDex/Features/Albums/SmartAlbumDetailScreen.swift",
                       "ShotDex/Features/ServerUpload/UploadedToServerScreen.swift"] {
            #expect(try PhotoKitDeleteCallSites.source(screen).contains("dependencies.photoDeletionGate"), "\(screen) bypasses the gate")
        }
    }
}

/// Every place that asks PhotoKit to delete, read from the source tree.
enum PhotoKitDeleteCallSites {
    /// Files and how many direct calls each may hold: the gate's own
    /// `perform` paths (the three screens with `PhotoDeletionFlow`), the
    /// primitive and its gated twin, and the compress path, which asks the
    /// gate itself. Every other entry point calls
    /// `deleteAssetsCheckingServer` (T20).
    static let known: [String: Int] = [
        "ShotDex/Features/Library/LibraryModel.swift": 1,
        "ShotDex/Features/Albums/SmartAlbumDetailModel.swift": 1,
        "ShotDex/Features/ServerUpload/UploadedToServerScreen.swift": 1,
        "ShotDex/Data/Sources/PhotoLibraryService.swift": 1,
        "ShotDex/Data/Sources/PhotoEditingService.swift": 1,
        // Keep Offline's screen, still being built in another change; it
        // moves to the gated call when that lands.
        "ShotDex/Features/OnThisIPhone/OnThisIPhoneModel.swift": 1,
    ]

    /// Entry points with no alerts of their own: each goes through the gate.
    static let gated = [
        "ShotDex/App/AssetActionsCoordinator.swift", "ShotDex/App/AppDependencies.swift",
        "ShotDex/Features/Bursts/BurstFramesScreen.swift", "ShotDex/Features/Shared/PhotoListModel.swift",
        "ShotDex/Features/Albums/AlbumsModel.swift", "ShotDex/Features/Albums/OnThisDayModel.swift",
        "ShotDex/Features/Albums/HiddenPhotosModel.swift", "ShotDex/Features/Duplicates/DuplicatesModel.swift",
        "ShotDex/Data/Sources/RejectedDeleter.swift",
    ]

    static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    static func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    static func scan() throws -> [(file: String, line: Int)] {
        let pattern = try NSRegularExpression(pattern: #"photoLibrary\.deleteAssets\(|PHAssetChangeRequest\.deleteAssets\("#)
        var out: [(String, Int)] = []
        let base = root.appendingPathComponent("ShotDex")
        guard let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let relative = "ShotDex/" + url.path.dropFirst(base.path.count + 1)
            for (n, line) in text.components(separatedBy: "\n").enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                if pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                    out.append((String(relative), n + 1))
                }
            }
        }
        return out
    }
}

/// Photos items P0… each with one HEIC on `NAS Home` under `Shared/`, as
/// the last check left them, and the same files on an in-memory server.
@MainActor
private struct GateFixture {
    let f: OnServerFixture
    let client = InMemoryRemoteFileClient()
    let relists = Box(0)
    let ids: [String]
    var gate: PhotoDeletionGate {
        let client = client
        let relists = relists
        return PhotoDeletionGate(database: f.database, connect: { _ in (client, "iCloud Photo") },
                                 relist: { _ in await MainActor.run { relists.value += 1 } })
    }

    init(photos: Int) throws {
        f = try OnServerFixture(photos: photos)
        ids = (0..<photos).map { "P\($0)" }
        for n in 0..<photos {
            let size = 2_000 + Int64(n)
            let path = "Shared/IMG_\(n).HEIC"
            try f.photo(n, files: [("1:IMG_\(n).HEIC", .photo, size, "sha\(n)")])
            try f.server(path, size: size, sha: "sha\(n)")
            client.put("iCloud Photo/" + path, Data(repeating: UInt8(n), count: Int(size)))
            // The fixture's listing saw write time 1.
            client.modified["iCloud Photo/" + path] = Date(timeIntervalSince1970: 1)
        }
    }

    func run(_ flow: PhotoDeletionFlow, deleted: @escaping ([String]) -> Void) async {
        flow.delete(ids, gate: gate, perform: { deleted($0) }, finished: { _ in })
        while flow.prompt == nil { await Task.yield() }
    }
}

@MainActor
final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}
