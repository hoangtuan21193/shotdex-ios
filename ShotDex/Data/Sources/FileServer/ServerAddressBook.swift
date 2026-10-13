import Foundation
import os

/// The last IPv4 address each `.local` connection resolved to
/// (FS-15.04 §7). Kept in the App Group's defaults, not the database, so
/// the background-upload extension reads it too; it is a cache, not user
/// data — losing it only means the next connection away from home fails
/// until one at home succeeds.
protocol ServerAddressBook: Sendable {
    func address(for serverId: String) -> String?
    func setAddress(_ address: String, for serverId: String)
}

struct DefaultsServerAddressBook: ServerAddressBook {
    private static let prefix = "serverAddress."

    func address(for serverId: String) -> String? {
        Self.defaults?.string(forKey: Self.prefix + serverId)
    }

    func setAddress(_ address: String, for serverId: String) {
        Self.defaults?.set(address, forKey: Self.prefix + serverId)
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: BackupUploadShared.groupIdentifier) }
}

final class InMemoryServerAddressBook: ServerAddressBook, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<[String: String]>(initialState: [:])

    func address(for serverId: String) -> String? { lock.withLock { $0[serverId] } }
    func setAddress(_ address: String, for serverId: String) { lock.withLock { $0[serverId] = address } }
}

/// The IPv4 address of a host name, or nil when it does not resolve within
/// `timeout`. A `.local` lookup away from home can hang for seconds, so it
/// is raced against the clock; the lookup thread is left to finish alone.
enum HostAddressLookup {
    static func ipv4(of host: String, timeout: Duration = .seconds(2)) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { await lookup(host) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func lookup(_ host: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: resolve(host))
            }
        }
    }

    private static func resolve(_ host: String) -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return nil }
        defer { freeaddrinfo(result) }
        guard let address = first.pointee.ai_addr else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(address, first.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        return String(cString: buffer)
    }
}
