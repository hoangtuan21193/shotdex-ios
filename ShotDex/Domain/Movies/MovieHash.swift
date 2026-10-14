import Foundation

/// The 64-bit movie hash players use to recognise a film (FS-23.05 §3):
/// the file size plus every little-endian 64-bit word of the first and the
/// last 64 KB, wrapping at 2^64, as 16 lowercase hex characters. Reads at
/// most 128 KB, so it works on a NAS file as well as a local one.
///
/// A file under 128 KB has the two regions overlap; a region whose length is
/// not a multiple of 8 is padded with zeros.
enum MovieHash {
    static let regionSize = 65_536

    /// `read(offset, length)` returns the bytes there — a local file handle
    /// or `RemoteFileClient.readRange`.
    static func compute(size: Int64, read: (Int64, Int) async throws -> Data) async throws -> String {
        let region = Int(min(Int64(regionSize), size))
        let head = try await read(0, region)
        let tail = try await read(max(0, size - Int64(region)), region)
        return hex(size: size, head: head, tail: tail)
    }

    static func compute(fileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = Int64(try handle.seekToEnd())
        let region = Int(min(Int64(regionSize), size))
        try handle.seek(toOffset: 0)
        let head = try handle.read(upToCount: region) ?? Data()
        try handle.seek(toOffset: UInt64(max(0, size - Int64(region))))
        let tail = try handle.read(upToCount: region) ?? Data()
        return hex(size: size, head: head, tail: tail)
    }

    static func hex(size: Int64, head: Data, tail: Data) -> String {
        var sum = UInt64(bitPattern: size)
        for region in [head, tail] {
            region.withUnsafeBytes { raw in
                var index = 0
                while index < raw.count {
                    var word: UInt64 = 0
                    for byte in 0..<8 where index + byte < raw.count {
                        word |= UInt64(raw[index + byte]) << (8 * UInt64(byte))
                    }
                    sum &+= word
                    index += 8
                }
            }
        }
        let digits = String(sum, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }
}
