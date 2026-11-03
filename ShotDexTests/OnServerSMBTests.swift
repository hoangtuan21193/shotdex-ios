import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.07 §12.2 end to end on the local SMB test server (impacket on
/// 127.0.0.1:4450, share `photos`; `docs/_plans/FS1908_LOOP.md`): the Mac
/// hashes a scratch source and writes its ledger; a phone over the same
/// share then takes every hash from the ledger without reading a file.
/// Skipped when nothing listens there.
@Suite(.enabled(if: LocalSMBTestServer.isListening), .serialized)
@MainActor
struct OnServerSMBTests {
    nonisolated private static func client() -> SMBFileClient {
        SMBFileClient(server: FileServer(name: "Test SMB", transferProtocol: .smb, host: "127.0.0.1", port: 4450,
                                         username: "tester", share: "photos"),
                      password: "secret")
    }

    /// A device of its own over the scratch root.
    @MainActor
    private struct Device {
        let f: OnServerFixture
        let refresh: ServerSourceRefresh
        let store: CopyFileStore
        let root: String

        init(root: String) async throws {
            self.root = root
            f = try OnServerFixture(photos: 0)
            let servers = FileServerStore(database: f.database, passwords: InMemoryPasswordStore())
            try servers.save(FileServer(id: "C1", name: "Test SMB", transferProtocol: .smb, host: "127.0.0.1", port: 4450,
                                        username: "tester", share: "photos", folder: root), password: "secret")
            refresh = ServerSourceRefresh(database: f.database, servers: servers, composer: ServerSourceIndexTests.composer) { _, _ in
                OnServerSMBTests.client()
            }
            store = CopyFileStore(database: f.database)
            let scan = await refresh.rescan(sourceId: f.source)
            #expect(scan?.photos == 3, "the scan of \(root) did not list the 3 photos")
        }

        func pass(as device: String) async throws -> ServerFileHashPass.Summary {
            let smb = OnServerSMBTests.client()
            var pass = ServerFileHashPass(store: store, client: smb)
            pass.hashesEverything = true
            pass.deviceId = device
            return try await pass.run(sourceId: f.source, connectionId: "C1", folder: root)
        }
    }

    /// AC-146 on the real server.
    @Test func ledgerSavesDownloads() async throws {
        let smb = Self.client()
        try await smb.connect()
        // Paths start with the share, as everywhere in this suite.
        let root = "photos/e2e-ledger-\(UUID().uuidString.prefix(8))"
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("OnServerSMB-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        // The share's fixture photos are synthetic landscapes (FS1908_LOOP.md).
        do {
            try await smb.createDirectory("\(root)/Shared")
            for index in 1...3 {
                let name = String(format: "IMG_%04d.JPG", index)
                let local = work.appendingPathComponent(name)
                _ = try await smb.download("photos/Tuan/2025/06/\(name)", to: local, progress: { _ in })
                try await smb.upload(local, to: "\(root)/Shared/\(name)", progress: { _ in })
            }

            let mac = try await Device(root: root)
            let wrote = try await mac.pass(as: "MAC")
            #expect(wrote.hashed == 3 && wrote.published == 3)
            #expect(try await smb.entries(in: "\(root)/.shotdex/hash-index").map(\.name) == ["MAC-000001.jsonl"])

            let phone = try await Device(root: root)
            let read = try await phone.pass(as: "PHONE")
            #expect(read.fromLedger == 3)
            #expect(read.hashed == 0)
            let rows = try await phone.f.database.reader.read { db in
                try Row.fetchAll(db, sql: "SELECT origin, sharedFrom FROM copy_files WHERE sha256 IS NOT NULL")
            }
            #expect(rows.count == 3)
            #expect(rows.allSatisfy { ($0["origin"] as String?) == "ledger" && ($0["sharedFrom"] as String?) == "MAC" })
            // The ledger is not a photo of the source.
            let copies = try await phone.f.database.reader.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_copies WHERE kind = 'server'")
            }
            #expect(copies == 3)
        } catch {
            try? await smb.removeFolderTree(root)
            await smb.disconnect()
            throw error
        }
        do {
            try await smb.removeFolderTree(root)
        } catch {
            Issue.record("left \(root) on the test share: \(error)")
        }
        await smb.disconnect()
    }
}
