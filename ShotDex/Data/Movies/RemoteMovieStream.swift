import Foundation
import os

/// A movie on a source, read on demand for the player (FS-23.02 §1, spike
/// S1): a seekable `InputStream` over `RemoteFileClient.readRange`, handed to
/// VLCKit's `VLCMedia(stream:)`. VLC reads on its own input thread — blocking
/// there while the server answers is how it expects a stream to behave —
/// and seeks through `NSStreamFileCurrentOffsetKey`. Nothing is written to
/// the device (AC-3), no port is opened, and VLC never sees a password.
final class RemoteMovieStream: InputStream, @unchecked Sendable {
    struct Stats: Sendable, Equatable {
        var bytesFetched: Int64 = 0
        var fetches = 0
        var seeks = 0
    }

    private let client: any RemoteFileClient
    private let path: String
    let size: Int64
    /// Bytes per request: 1 MB, or 128 000 for SFTP (S1: one larger read
    /// can stall).
    private let chunk: Int
    private let gate = AsyncGate()
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var status: Stream.Status = .notOpen
        var position: Int64 = 0
        var bufferStart: Int64 = 0
        var buffer = Data()
        var stats = Stats()
        var error: Error?
    }

    var stats: Stats { state.withLock { $0.stats } }

    init(client: any RemoteFileClient, path: String, size: Int64, chunk: Int = 1 << 20) {
        self.client = client
        self.path = path
        self.size = size
        self.chunk = chunk
        super.init(data: Data())
    }

    override var streamStatus: Stream.Status { state.withLock { $0.status } }
    override var streamError: Error? { state.withLock { $0.error } }
    override var hasBytesAvailable: Bool { state.withLock { $0.position < size } }
    override func open() { state.withLock { $0.status = .open } }
    override func close() { state.withLock { $0.status = .closed } }
    override func schedule(in aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {}
    override func remove(from aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {}
    override var delegate: StreamDelegate? {
        get { nil }
        set {}
    }
    override func getBuffer(_ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, length len: UnsafeMutablePointer<Int>) -> Bool { false }

    override func property(forKey key: Stream.PropertyKey) -> Any? {
        key == .fileCurrentOffsetKey ? NSNumber(value: state.withLock { $0.position }) : nil
    }

    override func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool {
        guard key == .fileCurrentOffsetKey, let offset = (property as? NSNumber)?.int64Value, offset >= 0 else { return false }
        state.withLock {
            $0.position = min(offset, size)
            $0.stats.seeks += 1
        }
        return true
    }

    override func read(_ out: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        let (position, held) = state.withLock { state -> (Int64, Data?) in
            let end = state.bufferStart + Int64(state.buffer.count)
            guard state.position >= state.bufferStart, state.position < end else { return (state.position, nil) }
            let start = state.buffer.startIndex + Int(state.position - state.bufferStart)
            let count = min(len, state.buffer.endIndex - start)
            return (state.position, state.buffer.subdata(in: start..<start + count))
        }
        if position >= size { return 0 }
        let data: Data
        if let held {
            data = held
        } else {
            guard let fetched = fetch(at: position), !fetched.isEmpty else { return -1 }
            state.withLock {
                $0.bufferStart = position
                $0.buffer = fetched
                $0.stats.bytesFetched += Int64(fetched.count)
                $0.stats.fetches += 1
            }
            data = fetched.prefix(len)
        }
        data.copyBytes(to: out, count: data.count)
        state.withLock { $0.position = position + Int64(data.count) }
        return data.count
    }

    /// A small file beside the movie (a sidecar subtitle), read over the
    /// same connection and in turn with the movie's own reads.
    func fetchFile(_ path: String, limit: Int64 = 8 << 20) async throws -> Data {
        await gate.enter()
        do {
            let data = try await readWhole(path, limit: limit)
            await gate.leave()
            return data
        } catch {
            await gate.leave()
            throw error
        }
    }

    private func readWhole(_ path: String, limit: Int64) async throws -> Data {
        guard let size = try await client.fileSize(at: path) else { throw RemoteFileError.fileMissing(path) }
        var data = Data()
        var offset: Int64 = 0
        let total = min(size, limit)
        while offset < total {
            let part = try await client.readRange(path, offset: offset, length: Int(min(Int64(chunk), total - offset)))
            if part.isEmpty { break }
            data.append(part)
            offset += Int64(part.count)
        }
        return data
    }

    /// Blocks VLC's input thread until the server answers; one request at a
    /// time on the connection.
    private func fetch(at offset: Int64) -> Data? {
        let length = Int(min(Int64(chunk), size - offset))
        let semaphore = DispatchSemaphore(value: 0)
        let result = OSAllocatedUnfairLock<Result<Data, Error>?>(initialState: nil)
        let client = client, path = path, gate = gate
        Task.detached {
            await gate.enter()
            let outcome: Result<Data, Error>
            do {
                outcome = .success(try await client.readRange(path, offset: offset, length: length))
            } catch {
                outcome = .failure(error)
            }
            await gate.leave()
            result.withLock { $0 = outcome }
            semaphore.signal()
        }
        semaphore.wait()
        switch result.withLock({ $0 }) {
        case .success(let data): return data
        case .failure(let error):
            state.withLock { $0.error = error }
            return nil
        case nil: return nil
        }
    }
}
