import Foundation
import Testing
@testable import ShotDex

/// A NAS ends a login left idle for about 50 minutes with a TCP reset
/// (seen 2026-11-05: two sessions dropped after 53 minutes). The next call
/// must log in again, not report the server unreachable. Runs against the
/// local SMB test server through a relay that can reset every connection.
@Suite(.enabled(if: LocalSMBTestServer.isListening), .serialized)
struct SMBDroppedLoginTests {
    private func client(port: UInt16) -> SMBFileClient {
        SMBFileClient(server: FileServer(name: "Test SMB", transferProtocol: .smb, host: "127.0.0.1", port: Int(port),
                                         username: "tester", share: "photos"),
                      password: "secret")
    }

    @Test func loginTheServerEndedIsReplaced() async throws {
        let relay = try ResettingRelay(upstreamPort: 4450)
        defer { relay.stop() }
        let smb = client(port: relay.port)
        try await smb.connect()
        let before = try await smb.entries(in: "photos")
        #expect(!before.isEmpty)
        #expect(relay.acceptedCount == 1)

        relay.resetAll()
        // The reset reaches the client's connection asynchronously; on
        // loopback it lands at once.
        try await Task.sleep(for: .milliseconds(500))

        let after = try await smb.entries(in: "photos")
        await smb.disconnect()
        #expect(after.map(\.name).sorted() == before.map(\.name).sorted())
        #expect(relay.acceptedCount == 2, "the second listing did not log in again")
    }
}

/// A TCP relay on 127.0.0.1 to a local port, on one thread: `resetAll()`
/// ends every connection with a reset (`SO_LINGER` 0), as a NAS does.
final class ResettingRelay: @unchecked Sendable {
    let port: UInt16
    private let listener: Int32
    private let upstreamPort: UInt16
    private let lock = NSLock()
    private var isResetRequested = false
    private var isStopped = false
    private var accepted = 0

    var acceptedCount: Int { lock.withLock { accepted } }

    init(upstreamPort: UInt16) throws {
        self.upstreamPort = upstreamPort
        let listening = socket(AF_INET, SOCK_STREAM, 0)
        var address = Self.loopback(port: 0)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listening, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard listening >= 0, bound == 0, listen(listening, 8) == 0 else {
            if listening >= 0 { close(listening) }
            throw POSIXError(.EADDRINUSE)
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listening, $0, &length) }
        }
        listener = listening
        port = UInt16(bigEndian: address.sin_port)
        Thread { [self] in run() }.start()
    }

    func resetAll() { lock.withLock { isResetRequested = true } }
    func stop() { lock.withLock { isStopped = true } }

    private static func loopback(port: UInt16) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return address
    }

    private func dialUpstream() -> Int32? {
        let upstream = socket(AF_INET, SOCK_STREAM, 0)
        var address = Self.loopback(port: upstreamPort)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(upstream, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else { close(upstream); return nil }
        return upstream
    }

    private func abort(_ socket: Int32) {
        var linger = Darwin.linger(l_onoff: 1, l_linger: 0)
        setsockopt(socket, SOL_SOCKET, SO_LINGER, &linger, socklen_t(MemoryLayout<Darwin.linger>.size))
        close(socket)
    }

    private func run() {
        // Each pair: (client side, server side).
        var pairs: [(Int32, Int32)] = []
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let (reset, stopped) = lock.withLock {
                defer { isResetRequested = false }
                return (isResetRequested, isStopped)
            }
            if reset || stopped {
                for (client, server) in pairs { abort(client); close(server) }
                pairs = []
            }
            if stopped { close(listener); return }

            var polled = [pollfd(fd: listener, events: Int16(POLLIN), revents: 0)]
            for (client, server) in pairs {
                polled.append(pollfd(fd: client, events: Int16(POLLIN), revents: 0))
                polled.append(pollfd(fd: server, events: Int16(POLLIN), revents: 0))
            }
            guard poll(&polled, nfds_t(polled.count), 50) > 0 else { continue }

            if polled[0].revents & Int16(POLLIN) != 0 {
                let client = accept(listener, nil, nil)
                if client >= 0, let server = dialUpstream() {
                    pairs.append((client, server))
                    lock.withLock { accepted += 1 }
                } else if client >= 0 {
                    close(client)
                }
            }
            var closed: Set<Int> = []
            for (index, (client, server)) in pairs.enumerated() {
                for (from, to, slot) in [(client, server, 1 + index * 2), (server, client, 2 + index * 2)]
                where slot < polled.count && polled[slot].revents != 0 {
                    let count = read(from, &buffer, buffer.count)
                    if count <= 0 || write(to, buffer, count) != count { closed.insert(index) }
                }
            }
            for index in closed.sorted(by: >) {
                close(pairs[index].0)
                close(pairs[index].1)
                pairs.remove(at: index)
            }
        }
    }
}
