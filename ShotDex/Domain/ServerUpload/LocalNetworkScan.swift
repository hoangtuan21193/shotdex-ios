import Foundation

/// A machine the port-445 sweep found (FS-15.04 §4b).
struct ScannedHost: Hashable, Sendable {
    /// Dotted IPv4.
    let address: String
    /// Its NetBIOS name, when it answered the node-status query.
    let name: String?
}

/// The pure half of the subnet sweep that finds Windows PCs and NAS drives
/// without Bonjour (FS-15.04 §4b): which addresses to knock on, and the
/// NetBIOS name query that says who answered.
enum LocalNetworkScan {
    static let port: UInt16 = 445
    static let concurrency = 32
    static let connectTimeout: Duration = .seconds(1)

    // MARK: Addresses

    /// Every host address of the /24 around `address` (or the whole subnet
    /// when it is smaller), except `address` itself. A /16 home network is
    /// 65 534 hosts — a minute of knocking — so only this device's /24.
    static func hosts(address: UInt32, netmask: UInt32) -> [UInt32] {
        let mask = netmask | 0xFFFF_FF00
        let network = address & mask
        let broadcast = network | ~mask
        guard broadcast > network + 1 else { return [] }
        return ((network + 1)..<broadcast).filter { $0 != address }
    }

    static func string(_ address: UInt32) -> String {
        "\(address >> 24 & 0xFF).\(address >> 16 & 0xFF).\(address >> 8 & 0xFF).\(address & 0xFF)"
    }

    static func address(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 < 256 }) else { return nil }
        return parts.reduce(0) { $0 << 8 | $1 }
    }

    // MARK: NetBIOS node status (RFC 1002 §4.2.17–18)

    /// A node-status request for the wildcard name `*`, sent unicast to UDP
    /// 137 — no broadcast, so no multicast entitlement.
    static func nodeStatusRequest(transactionId: UInt16) -> Data {
        var data = Data()
        data.append(contentsOf: [UInt8(transactionId >> 8), UInt8(transactionId & 0xFF)])
        data.append(contentsOf: [0x00, 0x00])             // flags: query
        data.append(contentsOf: [0x00, 0x01])             // one question
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        data.append(0x20)                                 // 32-byte encoded name
        var name = [UInt8]("*".utf8)
        name += [UInt8](repeating: 0, count: 16 - name.count)
        for byte in name {
            data.append(0x41 + (byte >> 4))
            data.append(0x41 + (byte & 0x0F))
        }
        data.append(0x00)
        data.append(contentsOf: [0x00, 0x21, 0x00, 0x01]) // NBSTAT, IN
        return data
    }

    /// The machine's name from a node-status answer: the server name
    /// (suffix `0x20`), else the workstation name (`0x00`), never a group.
    /// Nil for anything short or malformed — it is a packet off the network.
    static func name(fromNodeStatus data: Data) -> String? {
        let bytes = [UInt8](data)
        guard bytes.count > 12 else { return nil }
        var index = 12
        // Answer name: a pointer (2 bytes) or labels up to a zero byte.
        if bytes[index] & 0xC0 == 0xC0 {
            index += 2
        } else {
            while index < bytes.count, bytes[index] != 0 {
                index += Int(bytes[index]) + 1
            }
            index += 1
        }
        index += 2 + 2 + 4 + 2                            // type, class, TTL, RDLENGTH
        guard index < bytes.count else { return nil }
        let count = Int(bytes[index])
        index += 1
        var workstation: String?
        for _ in 0..<count {
            guard index + 18 <= bytes.count else { break }
            let name = String(decoding: bytes[index..<(index + 15)], as: UTF8.self)
                .trimmingCharacters(in: .whitespaces.union(.controlCharacters))
            let suffix = bytes[index + 15]
            let isGroup = bytes[index + 16] & 0x80 != 0
            index += 18
            guard !isGroup, !name.isEmpty else { continue }
            if suffix == 0x20 { return name }
            if suffix == 0x00, workstation == nil { workstation = name }
        }
        return workstation
    }
}

extension DiscoveredServerMerge {
    /// Bonjour rows plus the sweep's finds, minus any address Bonjour already
    /// shows — a Mac with File Sharing answers on 445 too (FS-15.04 §4b).
    static func merge(
        _ records: some Sequence<BonjourRecord>,
        scanned: [ScannedHost],
        bonjourAddresses: Set<String>
    ) -> [DiscoveredServer] {
        let fromBonjour = merge(records)
        let extra = scanned
            .filter { !bonjourAddresses.contains($0.address) }
            .map { host in
                DiscoveredServer(
                    name: host.name ?? host.address,
                    kind: .pc,
                    offers: [.init(service: .smb, host: host.address, port: Int(LocalNetworkScan.port))]
                )
            }
        return (fromBonjour + extra).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
