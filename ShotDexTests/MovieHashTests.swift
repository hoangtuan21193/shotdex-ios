import Foundation
import Testing
@testable import ShotDex

/// FS-23.05 §3: the 64-bit movie hash, against values from an independent
/// implementation (Python, the reference algorithm) over a synthetic file
/// whose byte n is (31·n + 7) mod 256.
@Suite struct MovieHashTests {
    private static func byte(_ n: Int64) -> UInt8 { UInt8(truncatingIfNeeded: n &* 31 &+ 7) }

    private final class ReadLog: @unchecked Sendable {
        private let lock = NSLock()
        private var total = 0
        func add(_ n: Int) { lock.withLock { total += n } }
        var bytes: Int { lock.withLock { total } }
    }

    private func hash(size: Int64, log: ReadLog = ReadLog()) async throws -> String {
        try await MovieHash.compute(size: size) { offset, length in
            log.add(length)
            let end = min(size, offset + Int64(length))
            return Data((offset..<end).map(Self.byte))
        }
    }

    /// AC-24: a 310 MB file — the expected 16 hex digits, reading ≤ 128 KB.
    @Test func matchesReference() async throws {
        let log = ReadLog()
        #expect(try await hash(size: 310_000_013, log: log) == "c000407fd27a598d")
        #expect(log.bytes <= 131_072)
    }

    /// Small files: the two regions overlap; odd lengths pad with zeros.
    @Test func smallFiles() async throws {
        #expect(try await hash(size: 100_000) == "5f9fe02060a246a0")
        #expect(try await hash(size: 12_345) == "db338be43c9924e9")
        #expect(try await hash(size: 7) == "01834506c88a4c15")
    }

    @Test func localFileMatchesByteSource() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "hash-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data((0..<Int64(100_000)).map(Self.byte)).write(to: url)
        #expect(try MovieHash.compute(fileAt: url) == "5f9fe02060a246a0")
    }
}
