import Foundation
import Testing
@testable import ShotDex

/// Whether the local SMB test server answers on 127.0.0.1:4450.
enum LocalSMBTestServer {
    static let isListening: Bool = {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(4450).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }()
}

/// FS-19.08 end to end against the local SMB test server (impacket on
/// 127.0.0.1:4450, share `photos`, `docs/_plans/FS1908_LOOP.md`). Skipped
/// when nothing listens there, so the suite stays green on any other Mac.
@Suite(.enabled(if: LocalSMBTestServer.isListening), .serialized)
struct CommonPhotosSMBTests {
    private func client() -> SMBFileClient {
        SMBFileClient(server: FileServer(name: "Test SMB", transferProtocol: .smb, host: "127.0.0.1", port: 4450,
                                         username: "tester", share: "photos"),
                      password: "secret")
    }

    /// Steps 1–5 on the fixture: 8 of Tuấn's 12 photos sit renamed in Vợ's
    /// `from-tuan`; `edited/IMG_0001.JPG` shares a name but not the bytes.
    @Test func scanFindsTheSharedPhotos() async throws {
        let smb = client()
        try await smb.connect()
        defer { Task { await smb.disconnect() } }
        let scanner = CommonPhotosScanner(client: smb)
        let folders = ["photos/Tuan", "photos/Vo"]

        let listing = try await scanner.list(folders)
        let groups = CommonPhotosMatcher.sizeGroups(listing.files)
        let keys = try await scanner.captureKeys(for: groups, folders: folders)
        let preview = CommonPhotosMatcher.preview(listing.files, captureKeys: keys)

        #expect(listing.files[0].count == 12)
        #expect(listing.files[1].count == 13)
        #expect(preview.candidateCount == 8)
        #expect(preview.likelyCount == 8)

        let photos = try await CommonPhotosVerifier(client: smb).verify(preview, folders: folders)

        #expect(photos.count == 8)
        #expect(photos.allSatisfy { $0.files[1].first?.relativePath.hasPrefix("from-tuan/") == true })
    }
}
