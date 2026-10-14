import Foundation
import Testing
@testable import ShotDex

/// FS-23.01 §4: an MP4's own cover, found by box headers and `moov` only.
@Suite struct MP4CoverArtTests {
    private func box(_ type: String, _ payload: Data, large: Bool = false) -> Data {
        var out = Data()
        if large {
            out.append(contentsOf: [0, 0, 0, 1])
            out.append(Data(type.utf8))
            let size = UInt64(16 + payload.count)
            out.append(contentsOf: (0..<8).reversed().map { UInt8((size >> (8 * UInt64($0))) & 0xFF) })
        } else {
            let size = UInt32(8 + payload.count)
            out.append(contentsOf: [UInt8(size >> 24), UInt8((size >> 16) & 0xFF), UInt8((size >> 8) & 0xFF), UInt8(size & 0xFF)])
            out.append(Data(type.utf8))
        }
        out.append(payload)
        return out
    }

    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, 0xFF, 0xD9])

    private func moov(withCover: Bool = true) -> Data {
        let covr = box("covr", box("data", Data([0, 0, 0, 13, 0, 0, 0, 0]) + jpeg))
        let ilst = box("ilst", withCover ? box("desc", Data("x".utf8)) + covr : Data())
        let meta = box("meta", Data([0, 0, 0, 0]) + box("hdlr", Data(repeating: 0, count: 25)) + ilst)
        return box("moov", box("mvhd", Data(repeating: 0, count: 100)) + box("trak", Data(repeating: 0, count: 300)) + box("udta", meta))
    }

    private final class Reads: @unchecked Sendable {
        private let lock = NSLock()
        private var total = 0
        func add(_ n: Int) { lock.withLock { total += n } }
        var bytes: Int { lock.withLock { total } }
    }

    private func find(_ file: Data, reads: Reads = Reads()) async throws -> Data? {
        try await MP4CoverArt.find(size: Int64(file.count)) { offset, length in
            reads.add(length)
            let start = Int(offset)
            return file.subdata(in: min(start, file.count)..<min(file.count, start + length))
        }
    }

    @Test func moovFirst() async throws {
        let file = box("ftyp", Data("isom".utf8)) + moov() + box("mdat", Data(repeating: 7, count: 2_000_000))
        #expect(try await find(file) == jpeg)
    }

    /// `moov` after a large `mdat`: found without reading the media.
    @Test func moovAtTheEndReadsLittle() async throws {
        let mdat = box("mdat", Data(repeating: 7, count: 3_000_000), large: true)
        let file = box("ftyp", Data("isom".utf8)) + mdat + moov()
        let reads = Reads()
        #expect(try await find(file, reads: reads) == jpeg)
        #expect(reads.bytes < 20_000)
    }

    @Test func noCover() async throws {
        let file = box("ftyp", Data("isom".utf8)) + moov(withCover: false)
        #expect(try await find(file) == nil)
        #expect(try await find(Data("not an mp4 at all".utf8)) == nil)
    }
}
