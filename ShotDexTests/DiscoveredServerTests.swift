import Foundation
import Testing
@testable import ShotDex

/// FS-15.04 §2–§4: Bonjour records become one row per machine, and a tap
/// fills the form.
@Suite struct DiscoveredServerTests {
    private func record(_ name: String, _ type: String, host: String? = nil, port: Int? = nil, txt: [String: String] = [:]) -> BonjourRecord {
        BonjourRecord(name: name, type: type, host: host, port: port, txt: txt)
    }

    /// AC-24.
    @Test func servicesMergePerMachine() {
        let records = [
            record("Hoang's MacBook", "_smb._tcp", host: "Hoangs-MacBook.local.", port: 445),
            record("Hoang's MacBook", "_sftp-ssh._tcp", host: "Hoangs-MacBook.local.", port: 22),
            record("Hoang's MacBook", "_device-info._tcp", txt: ["model": "MacBookPro18,3"]),
            record("DS920", "_webdavs._tcp", host: "DS920.local.", port: 5006),
            record("DS920", "_smb._tcp", host: "DS920.local.", port: 445),
        ]
        let all = DiscoveredServerMerge.merge(records, supports: { _ in true })
        #expect(all.map(\.name) == ["DS920", "Hoang's MacBook"])
        #expect(all[0].protocolSummary == "SMB · WebDAV (HTTPS)")
        #expect(all[0].kind == .nas)
        #expect(all[1].protocolSummary == "SMB · SFTP")
        #expect(all[1].kind == .laptop)
        #expect(all[1].offers.first == .init(service: .smb, host: "Hoangs-MacBook.local", port: 445))

        #expect(DiscoveredServerMerge.merge(records)[0].protocolSummary == "SMB · WebDAV (HTTPS)")
        // A protocol with no client yet (FTP) is left out.
        let ftp = [record("Router", "_ftp._tcp", host: "router.local.", port: 21)]
        #expect(DiscoveredServerMerge.merge(ftp).isEmpty == !RemoteFileClientFactory.supports(.ftp))
    }

    /// AC-25.
    @Test func sshCountsOnlyWithoutSftpSsh() {
        let records = [
            record("Pi", "_ssh._tcp", host: "pi.local.", port: 2222),
            record("Mac", "_ssh._tcp", host: "mac.local.", port: 22),
            record("Mac", "_sftp-ssh._tcp", host: "mac.local.", port: 2200),
        ]
        let servers = DiscoveredServerMerge.merge(records)
        #expect(servers.map(\.name) == ["Mac", "Pi"])
        #expect(servers[0].offers == [.init(service: .sftp, host: "mac.local", port: 2200)])
        #expect(servers[1].offers == [.init(service: .sftp, host: "pi.local", port: 2222)])
    }

    /// AC-26 (form half; the numbered name is the store's, AC-18).
    @Test func fillsDraft() {
        let mac = DiscoveredServer(name: "Mac", kind: .desktop, offers: [
            .init(service: .smb, host: "mac.local", port: 445),
            .init(service: .sftp, host: "mac.local", port: 2200),
        ])
        var draft = FileServerDraft()
        draft.apply(mac.offers[0], from: mac)
        #expect(draft.server.name == "Mac")
        #expect(draft.server.transferProtocol == .smb)
        #expect(draft.server.host == "mac.local")
        #expect(draft.portText == "")
        draft.apply(mac.offers[1], from: mac)
        #expect(draft.server.transferProtocol == .sftp)
        #expect(draft.portText == "2200")
        #expect(draft.port == 2200)
    }

    @Test func unresolvedAndUnknownRecordsAreDropped() {
        let records = [
            record("Printer", "_ipp._tcp", host: "printer.local.", port: 631),
            record("Half", "_smb._tcp"),
            record("Info only", "_device-info._tcp", txt: ["model": "Mac14,3"]),
        ]
        #expect(DiscoveredServerMerge.merge(records).isEmpty)
        #expect(DiscoveredServerMerge.kind(forModel: "Mac14,3") == .desktop)
        #expect(DiscoveredServerMerge.kind(forModel: "iMac21,1") == .desktop)
        #expect(DiscoveredServerMerge.kind(forModel: "DS920+") == .nas)
    }
}
