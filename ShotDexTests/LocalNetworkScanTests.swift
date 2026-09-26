import Foundation
import Testing
@testable import ShotDex

/// FS-15.04 §4b — the port-445 sweep's pure parts.
@Suite struct LocalNetworkScanTests {
    /// AC-38.
    @Test func hostsInSubnet() throws {
        let home = LocalNetworkScan.hosts(address: try #require(LocalNetworkScan.address("192.168.1.37")),
                                          netmask: try #require(LocalNetworkScan.address("255.255.255.0")))
        #expect(home.count == 253)
        #expect(LocalNetworkScan.string(home.first!) == "192.168.1.1")
        #expect(LocalNetworkScan.string(home.last!) == "192.168.1.254")
        #expect(!home.map(LocalNetworkScan.string).contains("192.168.1.37"))

        let big = LocalNetworkScan.hosts(address: try #require(LocalNetworkScan.address("10.0.5.9")),
                                         netmask: try #require(LocalNetworkScan.address("255.255.0.0")))
        #expect(big.count == 253)
        #expect(LocalNetworkScan.string(big.first!) == "10.0.5.1")

        let tiny = LocalNetworkScan.hosts(address: try #require(LocalNetworkScan.address("192.168.1.6")),
                                          netmask: try #require(LocalNetworkScan.address("255.255.255.252")))
        #expect(tiny.map(LocalNetworkScan.string) == ["192.168.1.5"])
    }

    /// AC-39: a node-status answer as Windows sends it.
    @Test func netbiosNodeStatus() {
        func entry(_ name: String, suffix: UInt8, group: Bool) -> [UInt8] {
            let padded = Array(name.utf8) + [UInt8](repeating: 0x20, count: 15 - name.utf8.count)
            return padded + [suffix, group ? 0x84 : 0x04, 0x00]
        }
        var packet: [UInt8] = [0x12, 0x34, 0x84, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]
        packet += [0x20] + [UInt8](repeating: 0x41, count: 32) + [0x00]   // encoded "*"
        packet += [0x00, 0x21, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]          // NBSTAT, IN, TTL
        let names = entry("DESKTOP-7KQ2", suffix: 0x00, group: false)
            + entry("WORKGROUP", suffix: 0x00, group: true)
            + entry("DESKTOP-7KQ2", suffix: 0x20, group: false)
        packet += [0x00, UInt8(1 + names.count)] + [0x03] + names
        #expect(LocalNetworkScan.name(fromNodeStatus: Data(packet)) == "DESKTOP-7KQ2")

        // A group name alone is not a machine name; junk and cut-offs are nil.
        #expect(LocalNetworkScan.name(fromNodeStatus: Data(packet.prefix(60))) == nil)
        #expect(LocalNetworkScan.name(fromNodeStatus: Data([0x00, 0x01])) == nil)
        #expect(LocalNetworkScan.name(fromNodeStatus: Data(repeating: 0xFF, count: 200)) == nil)

        let request = LocalNetworkScan.nodeStatusRequest(transactionId: 0x1234)
        #expect(request.count == 50)
        #expect(Array(request.suffix(4)) == [0x00, 0x21, 0x00, 0x01])
        #expect(request[13] == 0x43 && request[14] == 0x4B)                // '*' = 0x2A → "CK"
    }

    /// AC-40.
    @Test func mergeSkipsBonjourHosts() {
        let records = [BonjourRecord(name: "Hoang's MacBook", type: "_smb._tcp", host: "Hoangs-MacBook.local.", port: 445)]
        let scanned = [ScannedHost(address: "192.168.1.20", name: "HOANGS-MACBOOK"), ScannedHost(address: "192.168.1.50", name: "DESKTOP-7KQ2"),
                       ScannedHost(address: "192.168.1.60", name: nil)]
        let servers = DiscoveredServerMerge.merge(records, scanned: scanned, bonjourAddresses: ["192.168.1.20"])
        #expect(servers.map(\.name) == ["192.168.1.60", "DESKTOP-7KQ2", "Hoang's MacBook"])
        let pc = servers[1]
        #expect(pc.kind == .pc)
        #expect(pc.offers == [.init(service: .smb, host: "192.168.1.50", port: 445)])
    }
}

@Suite @MainActor struct ServerDiscoverySweepTests {
    final class Browser: LocalServerBrowsing {
        func start(onEvent: @escaping @MainActor (LocalServerBrowserEvent) -> Void) {}
        func stop() {}
    }

    /// A sweep that reports one PC after a pause.
    struct SlowScanner: LocalNetworkScanning {
        func scan(onHost: @escaping @Sendable (ScannedHost) -> Void) async {
            try? await Task.sleep(for: .milliseconds(300))
            onHost(ScannedHost(address: "192.168.1.50", name: "DESKTOP-7KQ2"))
        }
        func addresses(of hosts: [String]) async -> Set<String> { [] }
    }

    /// "No servers found" waits for the sweep, and a PC found late appears.
    @Test func emptyOnlyAfterTheSweep() async {
        let model = ServerDiscoveryModel(browser: Browser(), scanner: SlowScanner(), giveUpAfter: .milliseconds(50))
        model.start()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(model.state == .searching)
        try? await Task.sleep(for: .milliseconds(400))
        guard case .found(let servers) = model.state else { Issue.record("expected found"); return }
        #expect(servers.map(\.name) == ["DESKTOP-7KQ2"])
        #expect(!model.isSearching)
        model.stop()
    }
}
