import Foundation
import Testing
@testable import ShotDex

/// AC-20: the ⋯ menu's upload row follows the number of connections.
@Suite struct ServerUploadMenuTests {
    @Test func rowShapeFollowsConnectionCount() {
        #expect(ServerUploadMenu.row(for: []) == .addFirst)

        let nas = FileServer(id: "n", name: "NAS", transferProtocol: .smb, host: "nas.local", username: "u", share: "photo", folder: "RAW")
        #expect(ServerUploadMenu.row(for: [nas]) == .single(.init(id: "n", name: "NAS", detail: "SMB · nas.local/photo/RAW")))

        let office = FileServer(id: "o", name: "Office", transferProtocol: .sftp, host: "office.example.com", username: "u")
        let phone = FileServer(id: "p", name: "NAS – Phone", transferProtocol: .smb, host: "nas.local", username: "u", share: "photo", folder: "Phone")
        guard case .list(let items) = ServerUploadMenu.row(for: [office, nas, phone]) else {
            Issue.record("three connections should make a submenu")
            return
        }
        #expect(items.map(\.name) == ["NAS", "NAS – Phone", "Office"])
        #expect(items.last?.detail == "SFTP · office.example.com")
    }
}
