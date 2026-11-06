import Foundation

/// `FILE_STREAM_INFORMATION` (MS-FSCC 2.4.44), which SMBClient lists no
/// parser for: entries of NextEntryOffset, StreamNameLength, StreamSize,
/// StreamAllocationSize and the name in UTF-16LE (FS-19.08 §6e).
enum SMBStreamInformation {
    struct Stream: Equatable, Sendable {
        /// As the server names it: `:AFP_AfpInfo:$DATA`.
        let name: String
        let size: Int64

        /// The file's own bytes (`::$DATA`), not an alternate stream.
        var isMainData: Bool { name == "::$DATA" }
        /// A stream ShotDex carries with a copy: `:name:$DATA` with a name of
        /// its own — never the file's bytes (`::$DATA`, `:$DATA`, or the
        /// nameless entry impacket lists) — that is Finder info or a Finder
        /// metadata item (tags). Other streams (`Zone.Identifier`, resource
        /// forks) are not ShotDex's to copy.
        var isCarried: Bool {
            let parts = name.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0].isEmpty, parts[2] == "$DATA" else { return false }
            let stream = parts[1]
            guard !stream.isEmpty, !stream.contains("/"), !stream.contains("\\") else { return false }
            return stream == "AFP_AfpInfo" || stream.hasPrefix("com.apple.metadata\u{F022}")
        }
        /// Finder info, copied only whole.
        var isFinderInfo: Bool { name == ":AFP_AfpInfo:$DATA" }
    }

    static let finderInfoSize = 60

    /// The entries of `buffer`; a malformed tail is dropped.
    static func streams(in buffer: Data) -> [Stream] {
        let bytes = [UInt8](buffer)
        func uint32(_ at: Int) -> UInt32? {
            guard at >= 0, at + 4 <= bytes.count else { return nil }
            return UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
        }
        func int64(_ at: Int) -> Int64? {
            guard let low = uint32(at), let high = uint32(at + 4) else { return nil }
            return Int64(bitPattern: UInt64(high) << 32 | UInt64(low))
        }
        var out: [Stream] = []
        var offset = 0
        // More entries than the 1124-byte reply could hold means a loop.
        while out.count < 64, let next = uint32(offset), let nameLength = uint32(offset + 4), let size = int64(offset + 8) {
            let nameStart = offset + 24
            let nameEnd = nameStart + Int(nameLength)
            guard nameLength % 2 == 0, nameEnd <= bytes.count else { break }
            let units = stride(from: nameStart, to: nameEnd, by: 2).map { UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8 }
            out.append(Stream(name: String(decoding: units, as: UTF16.self), size: size))
            guard next > 0 else { break }
            offset += Int(next)
        }
        return out
    }
}
