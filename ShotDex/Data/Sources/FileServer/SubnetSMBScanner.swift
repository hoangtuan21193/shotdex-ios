import Darwin
import Foundation
import Network

/// Sweeps this device's /24 for SMB on port 445 and asks each hit its
/// NetBIOS name (FS-15.04 §4b) — how Windows PCs show up without Bonjour and
/// without the multicast entitlement. Unicast only.
protocol LocalNetworkScanning: Sendable {
    /// Every host that answered, as it answers; returns when the sweep ends.
    func scan(onHost: @escaping @Sendable (ScannedHost) -> Void) async
    /// IPv4 addresses of Bonjour hosts (`Mac.local`), to leave out of the sweep's rows.
    func addresses(of hosts: [String]) async -> Set<String>
}

struct SubnetSMBScanner: LocalNetworkScanning {
    private let queue = DispatchQueue(label: "com.hoangtuan.shotdex.subnet-scan", attributes: .concurrent)

    func scan(onHost: @escaping @Sendable (ScannedHost) -> Void) async {
        guard let (address, netmask) = Self.wifiAddress() else { return }
        let hosts = LocalNetworkScan.hosts(address: address, netmask: netmask).map(LocalNetworkScan.string)
        await scan(hosts, port: LocalNetworkScan.port, onHost: onHost)
    }

    /// The sweep over given addresses — `scan(onHost:)` with the Wi-Fi /24.
    func scan(_ hosts: [String], port: UInt16, onHost: @escaping @Sendable (ScannedHost) -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            var next = hosts.makeIterator()
            func addNext() -> Bool {
                guard let text = next.next() else { return false }
                group.addTask {
                    guard await self.isOpen(text, port: port) else { return }
                    let name = await self.netbiosName(of: text)
                    onHost(ScannedHost(address: text, name: name))
                }
                return true
            }
            for _ in 0..<LocalNetworkScan.concurrency where addNext() {}
            while await group.next() != nil {
                if Task.isCancelled { group.cancelAll(); return }
                _ = addNext()
            }
        }
    }

    func addresses(of hosts: [String]) async -> Set<String> {
        await Task.detached(priority: .utility) {
            var result = Set<String>()
            for host in hosts {
                var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM, ai_protocol: 0,
                                     ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
                var info: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(host, nil, &hints, &info) == 0 else { continue }
                var cursor = info
                while let entry = cursor {
                    if let raw = entry.pointee.ai_addr, raw.pointee.sa_family == sa_family_t(AF_INET) {
                        let ipv4 = raw.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
                        result.insert(LocalNetworkScan.string(UInt32(bigEndian: ipv4)))
                    }
                    cursor = entry.pointee.ai_next
                }
                freeaddrinfo(info)
            }
            return result
        }.value
    }

    // MARK: Probes

    /// Whether a TCP connection to `host:port` comes up within the timeout.
    private func isOpen(_ host: String, port: UInt16) async -> Bool {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let result = OnceFlag()
        return await withCheckedContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if result.claim() { continuation.resume(returning: true) }
                    connection.cancel()
                case .failed, .waiting:
                    if result.claim() { continuation.resume(returning: false) }
                    connection.cancel()
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 1) {
                if result.claim() { continuation.resume(returning: false) }
                connection.cancel()
            }
        }
    }

    /// The NetBIOS node-status answer from UDP 137, or nil after a second.
    private func netbiosName(of host: String) async -> String? {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: 137, using: .udp)
        let result = OnceFlag()
        let request = LocalNetworkScan.nodeStatusRequest(transactionId: UInt16.random(in: 1...0xFFFF))
        return await withCheckedContinuation { continuation in
            connection.stateUpdateHandler = { state in
                guard case .ready = state else { return }
                connection.send(content: request, completion: .contentProcessed { _ in })
                connection.receiveMessage { data, _, _, _ in
                    if result.claim() { continuation.resume(returning: data.flatMap(LocalNetworkScan.name(fromNodeStatus:))) }
                    connection.cancel()
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 1) {
                if result.claim() { continuation.resume(returning: nil) }
                connection.cancel()
            }
        }
    }

    /// IPv4 address and netmask of the Wi-Fi (or first private) interface.
    static func wifiAddress() -> (UInt32, UInt32)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var fallback: (UInt32, UInt32)?
        var cursor = list
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let raw = entry.pointee.ifa_addr, raw.pointee.sa_family == sa_family_t(AF_INET),
                  let rawMask = entry.pointee.ifa_netmask,
                  entry.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                  entry.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0
            else { continue }
            let address = raw.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let mask = rawMask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let name = String(cString: entry.pointee.ifa_name)
            if name == "en0" { return (address, mask) }
            if fallback == nil, isPrivate(address) { fallback = (address, mask) }
        }
        return fallback
    }

    private static func isPrivate(_ address: UInt32) -> Bool {
        address >> 24 == 10 || address >> 20 == 0xAC1 || address >> 16 == 0xC0A8
    }
}

/// First caller wins — one continuation resume across racing callbacks.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isClaimed = false

    func claim() -> Bool {
        lock.withLock {
            guard !isClaimed else { return false }
            isClaimed = true
            return true
        }
    }
}
