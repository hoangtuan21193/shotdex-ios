import Foundation

/// Lets one caller at a time through — async code's mutex. An actor alone
/// is not enough: it lets another call in at every `await`.
actor AsyncGate {
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func leave() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// One visit to a connection's photos (FS-17.01 §3): one login shared by
/// every folder, thumbnail and date read, one server call at a time — the
/// SMB session is not safe to use from two calls at once, and the network is
/// the limit anyway.
final class ServerBrowseSession: Sendable {
    let server: FileServer
    private let client: any RemoteFileClient
    private let gate = AsyncGate()
    private let connection = ConnectionState()

    private actor ConnectionState {
        var isConnected = false
        func set(_ value: Bool) { isConnected = value }
    }

    init(server: FileServer, client: any RemoteFileClient) {
        self.server = server
        self.client = client
    }

    /// Runs `work` with the connected client, after every call queued
    /// before it. A call cancelled while waiting still takes its turn but
    /// skips the work.
    func perform<T: Sendable>(_ work: @Sendable (any RemoteFileClient) async throws -> T) async throws -> T {
        await gate.enter()
        do {
            try Task.checkCancellation()
            if await !connection.isConnected {
                try await client.connect()
                await connection.set(true)
            }
            let value = try await work(client)
            await gate.leave()
            return value
        } catch let error as RemoteFileError where error.stopsBatch {
            // The login is gone; the next call dials again.
            await connection.set(false)
            await gate.leave()
            throw error
        } catch {
            await gate.leave()
            throw error
        }
    }

    func close() async {
        await gate.enter()
        await client.disconnect()
        await connection.set(false)
        await gate.leave()
    }
}
