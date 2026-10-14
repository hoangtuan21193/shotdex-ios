import Compression
import Foundation

/// Bytes of a movie file, wherever it is: on the device, or on a source
/// read range by range (FS-23.03 §3).
protocol MovieByteSource: Sendable {
    var size: Int64 { get }
    /// Reads that may be in flight at once: 1 over a connection that does
    /// one thing at a time (SMB, SFTP), more over HTTP or on the device.
    var concurrentReads: Int { get }
    func read(offset: Int64, length: Int) async throws -> Data
}

extension MovieByteSource {
    var concurrentReads: Int { 1 }
}

/// A subtitle track inside a Matroska file.
struct MatroskaSubtitleTrack: Equatable, Sendable {
    var number: UInt64
    var codec: String
    /// `eng`, `vie`, BCP 47 when the file has it.
    var language: String
    var name: String
    /// Text the player can draw itself; nil for picture subtitles (PGS,
    /// VobSub) that only VLC can.
    var format: SubtitleParser.Format? {
        switch codec {
        case "S_TEXT/UTF8", "S_TEXT/ASCII": .srt
        case let codec where codec.hasPrefix("S_TEXT/ASS") || codec.hasPrefix("S_TEXT/SSA"): .ass
        case "S_TEXT/WEBVTT": .vtt
        default: nil
        }
    }
}

/// Text subtitle tracks out of a Matroska (MKV, WebM) file without decoding
/// anything (spike S2, FS-23.03 §3). Two ways in:
///
/// - **Cues**: jump to the subtitle blocks the index names. A 3-hour movie
///   costs about half a megabyte and two small reads per line — the way for
///   a streamed movie.
/// - **Walk**: read every Cluster's element headers in order. Only for a
///   file on the device (it reads the whole file); a stream without Cues
///   for a track leaves that track to VLC (AC-55).
///
/// Skips CRC-32 and Void wherever they sit; inflates zlib and restores
/// header-stripped payloads; skips laced subtitle blocks (none seen).
final class MatroskaSubtitleReader {
    struct Extraction: Equatable, Sendable {
        /// Track number → the subtitle as SRT, ASS or WebVTT text.
        var texts: [UInt64: String] = [:]
        /// Text tracks the Cues do not point at.
        var withoutCues: Set<UInt64> = []
    }

    enum Failure: Error, Equatable {
        case notMatroska
    }

    private let source: any MovieByteSource
    private var segmentData: Int64 = 0
    private var segmentEnd: Int64 = 0
    private var scale: Int64 = 1_000_000
    private var seeks: [UInt32: Int64] = [:]
    private(set) var tracks: [MatroskaSubtitleTrack] = []
    /// The audio tracks, in file order, `file:0`, `file:1`… — what the
    /// movie page lists before anything plays (FS-23.08 §4).
    private(set) var audioTracks: [MovieAudioTrack] = []
    private var compression: [UInt64: (algorithm: UInt64, settings: [UInt8])] = [:]
    private var codecPrivate: [UInt64: [UInt8]] = [:]
    private var events: [UInt64: [Event]] = [:]
    /// Bytes asked of the source, for the < 2 MB budget (AC-53).
    private(set) var bytesRead: Int64 = 0

    private struct Event {
        var startNs: Int64
        var durationNs: Int64?
        var payload: [UInt8]
    }

    init(source: any MovieByteSource) {
        self.source = source
    }

    /// The file's subtitle tracks, text and picture alike.
    func readTracks() async throws -> [MatroskaSubtitleTrack] {
        try await openSegment()
        var position = segmentData
        var sawTracks = false
        // Info, Tracks and SeekHead sit before the first Cluster.
        while position < segmentEnd, let (head, _) = try await header(at: position) {
            switch head.id {
            case ID.info: parseInfo(try await body(head))
            case ID.tracks:
                parseTracks(try await body(head))
                sawTracks = true
            case ID.seekHead: parseSeekHead(try await body(head))
            case ID.cluster, ID.cues: position = segmentEnd
            default: break
            }
            guard position < segmentEnd, let end = head.end else { break }
            position = end
        }
        if !sawTracks, let at = seeks[ID.tracks], let (head, _) = try await header(at: at), head.id == ID.tracks {
            parseTracks(try await body(head))
        }
        return tracks
    }

    /// The text tracks in `numbers`, by Cues; tracks the Cues miss are
    /// walked for only when `walkWithoutCues` (a file on the device).
    func extract(_ numbers: Set<UInt64>, walkWithoutCues: Bool) async throws -> Extraction {
        let wanted = numbers.intersection(tracks.filter { $0.format != nil }.map(\.number))
        var result = Extraction()
        guard !wanted.isEmpty else { return result }
        let covered = try await readByCues(wanted)
        let missing = wanted.subtracting(covered)
        if !missing.isEmpty {
            if walkWithoutCues {
                for number in missing { events[number] = [] }
                try await walkClusters(missing)
            } else {
                result.withoutCues = missing
            }
        }
        for track in tracks where wanted.contains(track.number) && !result.withoutCues.contains(track.number) {
            result.texts[track.number] = render(track, events[track.number] ?? [])
        }
        return result
    }

    // MARK: Elements

    private struct Header {
        let id: UInt32
        /// nil: unknown size (a live-written Cluster).
        let size: Int64?
        let start: Int64
        let dataStart: Int64
        var end: Int64? { size.map { dataStart + $0 } }
    }

    private enum ID {
        static let ebml: UInt32 = 0x1A45_DFA3, segment: UInt32 = 0x1853_8067, seekHead: UInt32 = 0x114D_9B74
        static let seek: UInt32 = 0x4DBB, seekID: UInt32 = 0x53AB, seekPosition: UInt32 = 0x53AC
        static let info: UInt32 = 0x1549_A966, timecodeScale: UInt32 = 0x2AD7B1
        static let tracks: UInt32 = 0x1654_AE6B, trackEntry: UInt32 = 0xAE, trackNumber: UInt32 = 0xD7, trackType: UInt32 = 0x83
        static let audio: UInt32 = 0xE1, channels: UInt32 = 0x9F, flagDefault: UInt32 = 0x88
        static let codecID: UInt32 = 0x86, language: UInt32 = 0x22B59C, languageBCP47: UInt32 = 0x22B59D, name: UInt32 = 0x536E
        static let codecPrivate: UInt32 = 0x63A2, contentEncodings: UInt32 = 0x6D80, contentCompression: UInt32 = 0x5034
        static let compressionAlgorithm: UInt32 = 0x4254, compressionSettings: UInt32 = 0x4255
        static let cues: UInt32 = 0x1C53_BB6B, cuePoint: UInt32 = 0xBB, cueTime: UInt32 = 0xB3, cueTrackPositions: UInt32 = 0xB7
        static let cueTrack: UInt32 = 0xF7, cueClusterPosition: UInt32 = 0xF1, cueRelativePosition: UInt32 = 0xF0, cueDuration: UInt32 = 0xB2
        static let cluster: UInt32 = 0x1F43_B675, timecode: UInt32 = 0xE7, simpleBlock: UInt32 = 0xA3
        static let blockGroup: UInt32 = 0xA0, block: UInt32 = 0xA1, blockDuration: UInt32 = 0x9B
    }

    private func read(_ offset: Int64, _ length: Int) async throws -> [UInt8] {
        let count = Int(max(0, min(Int64(length), source.size - offset)))
        guard count > 0 else { return [] }
        bytesRead += Int64(count)
        return [UInt8](try await source.read(offset: offset, length: count))
    }

    /// The header at `position` plus whatever of its data `prefetch` read.
    private func header(at position: Int64, prefetch: Int = 16) async throws -> (Header, [UInt8])? {
        let bytes = try await read(position, prefetch)
        guard let (id, idLength, _) = Self.vint(bytes[...], keepMarker: true),
              let (size, sizeLength, unknown) = Self.vint(bytes[idLength...], keepMarker: false) else { return nil }
        let head = Header(
            id: UInt32(truncatingIfNeeded: id), size: unknown ? nil : Int64(size), start: position,
            dataStart: position + Int64(idLength + sizeLength)
        )
        return (head, Array(bytes.dropFirst(idLength + sizeLength)))
    }

    /// The header in `bytes`, read at `position`.
    private static func header(_ bytes: [UInt8], at position: Int64) -> Header? {
        guard let (id, idLength, _) = vint(bytes[...], keepMarker: true),
              bytes.count > idLength,
              let (size, sizeLength, unknown) = vint(bytes[idLength...], keepMarker: false) else { return nil }
        return Header(
            id: UInt32(truncatingIfNeeded: id), size: unknown ? nil : Int64(size), start: position,
            dataStart: position + Int64(idLength + sizeLength)
        )
    }

    /// An element's whole data, reusing what the header read brought.
    private func body(_ head: Header, prefetched: [UInt8] = []) async throws -> [UInt8] {
        let size = Int(head.size ?? 0)
        if prefetched.count >= size { return Array(prefetched.prefix(size)) }
        return try await read(head.dataStart, size)
    }

    static func vint(_ bytes: ArraySlice<UInt8>, keepMarker: Bool) -> (UInt64, Int, Bool)? {
        guard let first = bytes.first else { return nil }
        let length = first == 0 ? 9 : first.leadingZeroBitCount + 1
        guard length <= 8, bytes.count >= length else { return nil }
        let mask: UInt8 = 0xFF >> length
        var value = UInt64(keepMarker ? first : first & mask)
        var allOnes = (first & mask) == mask
        for byte in bytes.dropFirst().prefix(length - 1) {
            value = value << 8 | UInt64(byte)
            if byte != 0xFF { allOnes = false }
        }
        return (value, length, allOnes)
    }

    private static func uint(_ bytes: [UInt8]) -> UInt64 {
        bytes.prefix(8).reduce(0) { $0 << 8 | UInt64($1) }
    }

    /// Children of an element already read whole.
    private static func children(_ data: [UInt8]) -> [(UInt32, [UInt8])] {
        var out: [(UInt32, [UInt8])] = []
        var index = 0
        while index < data.count {
            guard let (id, idLength, _) = vint(data[index...], keepMarker: true),
                  index + idLength < data.count,
                  let (size, sizeLength, _) = vint(data[(index + idLength)...], keepMarker: false) else { break }
            let start = index + idLength + sizeLength
            let end = min(data.count, start + Int(clamping: size))
            out.append((UInt32(truncatingIfNeeded: id), Array(data[start..<end])))
            index = end
        }
        return out
    }

    // MARK: Top level

    private func openSegment() async throws {
        var position: Int64 = 0
        var first = true
        while let (head, _) = try await header(at: position) {
            if first, head.id != ID.ebml { throw Failure.notMatroska }
            first = false
            if head.id == ID.segment {
                segmentData = head.dataStart
                segmentEnd = head.end ?? source.size
                return
            }
            guard let end = head.end else { break }
            position = end
        }
        throw Failure.notMatroska
    }

    private func parseInfo(_ data: [UInt8]) {
        for (id, value) in Self.children(data) where id == ID.timecodeScale {
            scale = Int64(Self.uint(value))
        }
    }

    private func parseSeekHead(_ data: [UInt8]) {
        for (id, seek) in Self.children(data) where id == ID.seek {
            var target: UInt32 = 0
            var position: Int64 = 0
            for (childId, value) in Self.children(seek) {
                if childId == ID.seekID { target = UInt32(truncatingIfNeeded: Self.uint(value)) }
                if childId == ID.seekPosition { position = Int64(Self.uint(value)) }
            }
            if seeks[target] == nil { seeks[target] = segmentData + position }
        }
    }

    private func parseTracks(_ data: [UInt8]) {
        for (id, entry) in Self.children(data) where id == ID.trackEntry {
            var number: UInt64 = 0
            var type: UInt64 = 0
            var track = MatroskaSubtitleTrack(number: 0, codec: "", language: "eng", name: "")
            var hasBCP47 = false
            var privateData: [UInt8]?
            var entryCompression: (algorithm: UInt64, settings: [UInt8])?
            var channels: Int?
            var isDefault = true
            for (childId, value) in Self.children(entry) {
                switch childId {
                case ID.audio:
                    for (key, field) in Self.children(value) where key == ID.channels { channels = Int(Self.uint(field)) }
                case ID.flagDefault: isDefault = Self.uint(value) != 0
                case ID.trackNumber: number = Self.uint(value)
                case ID.trackType: type = Self.uint(value)
                case ID.codecID: track.codec = String(decoding: value, as: UTF8.self)
                case ID.language where !hasBCP47: track.language = String(decoding: value, as: UTF8.self)
                case ID.languageBCP47:
                    track.language = String(decoding: value, as: UTF8.self)
                    hasBCP47 = true
                case ID.name: track.name = String(decoding: value, as: UTF8.self)
                case ID.codecPrivate: privateData = value
                case ID.contentEncodings:
                    for (_, encoding) in Self.children(value) {
                        for (encodingId, compressionData) in Self.children(encoding) where encodingId == ID.contentCompression {
                            var algorithm: UInt64 = 0
                            var settings: [UInt8] = []
                            for (key, setting) in Self.children(compressionData) {
                                if key == ID.compressionAlgorithm { algorithm = Self.uint(setting) }
                                if key == ID.compressionSettings { settings = setting }
                            }
                            entryCompression = (algorithm, settings)
                        }
                    }
                default: break
                }
            }
            if type == 0x02 {
                audioTracks.append(MovieAudioTrack(
                    id: MovieAudioTrack.fileId(audioTracks.count),
                    language: track.language, name: track.name.isEmpty ? nil : track.name,
                    codec: Self.audioCodec(track.codec), channels: channels, isDefault: isDefault
                ))
                continue
            }
            guard type == 0x11 else { continue }
            track.number = number
            codecPrivate[number] = privateData
            compression[number] = entryCompression
            tracks.append(track)
        }
    }

    /// `A_TRUEHD` → `truehd`, the short names `MovieAudioTrackLabel` knows.
    static func audioCodec(_ codecID: String) -> String? {
        let id = codecID.uppercased()
        let known: [(String, String)] = [
            ("A_TRUEHD", "truehd"), ("A_EAC3", "eac3"), ("A_AC3", "ac3"), ("A_DTS", "dts"), ("A_AAC", "aac"),
            ("A_OPUS", "opus"), ("A_FLAC", "flac"), ("A_VORBIS", "vorbis"), ("A_MPEG/L3", "mp3"), ("A_MPEG/L2", "mp2"),
            ("A_ALAC", "alac"), ("A_PCM", "pcm"),
        ]
        return known.first { id.hasPrefix($0.0) }?.1 ?? (id.isEmpty ? nil : String(id.dropFirst(2)).lowercased())
    }

    // MARK: Cues

    /// The tracks it found index entries for. The index is read first; the
    /// blocks it names are then fetched `source.concurrentReads` at a time
    /// (a long movie has a thousand subtitle lines, each its own read — one
    /// after another over a home network that is minutes) and taken in the
    /// index's order.
    private func readByCues(_ wanted: Set<UInt64>) async throws -> Set<UInt64> {
        guard let at = seeks[ID.cues], let (head, prefetched) = try await header(at: at), head.id == ID.cues else { return [] }
        var entries: [CueEntry] = []
        for (id, point) in Self.children(try await body(head, prefetched: prefetched)) where id == ID.cuePoint {
            var time: Int64 = 0
            var positions: [(track: UInt64, cluster: Int64, relative: Int64?, duration: Int64?)] = []
            for (pointId, value) in Self.children(point) {
                if pointId == ID.cueTime { time = Int64(Self.uint(value)) }
                guard pointId == ID.cueTrackPositions else { continue }
                var track: UInt64 = 0
                var cluster: Int64 = -1
                var relative: Int64?
                var duration: Int64?
                for (key, field) in Self.children(value) {
                    switch key {
                    case ID.cueTrack: track = Self.uint(field)
                    case ID.cueClusterPosition: cluster = Int64(Self.uint(field))
                    case ID.cueRelativePosition: relative = Int64(Self.uint(field))
                    case ID.cueDuration: duration = Int64(Self.uint(field))
                    default: break
                    }
                }
                if cluster >= 0 { positions.append((track, cluster, relative, duration)) }
            }
            for position in positions where wanted.contains(position.track) {
                entries.append(CueEntry(
                    track: position.track, clusterStart: segmentData + position.cluster,
                    relative: position.relative, time: time, duration: position.duration
                ))
            }
        }
        let covered = Set(entries.map(\.track))

        // Where each Cluster's data starts, then each block: fetched in parallel.
        let clusterStarts = Array(Set(entries.filter { $0.relative != nil }.map(\.clusterStart)))
        let clusterHeads = try await fetch(clusterStarts.map { ($0, 16) })
        var clusterData: [Int64: Int64] = [:]
        for (position, bytes) in zip(clusterStarts, clusterHeads) {
            if let head = Self.header(bytes, at: position), head.id == ID.cluster { clusterData[position] = head.dataStart }
        }
        let located = entries.compactMap { entry -> (CueEntry, Int64)? in
            guard let relative = entry.relative, let dataStart = clusterData[entry.clusterStart] else { return nil }
            return (entry, dataStart + relative)
        }
        let blocks = try await fetch(located.map { ($0.1, 512) })

        var blockAt: [Int: [UInt8]] = [:]
        for (index, bytes) in blocks.enumerated() { blockAt[index] = bytes }
        var next = 0
        for entry in entries {
            guard entry.relative != nil else {
                // No block offset: read that Cluster for this track.
                if let (cluster, _) = try await header(at: entry.clusterStart), cluster.id == ID.cluster {
                    try await walkCluster(cluster, tracks: [entry.track])
                }
                continue
            }
            guard next < located.count, located[next].0 == entry else { continue }
            let position = located[next].1
            let bytes = blockAt[next] ?? []
            next += 1
            guard let block = Self.header(bytes, at: position) else { continue }
            let rest = Array(bytes.dropFirst(Int(block.dataStart - position)))
            let before = events[entry.track]?.count ?? 0
            // CueTime is the block's own time: no Cluster Timecode read.
            switch block.id {
            case ID.blockGroup: takeGroup(try await body(block, prefetched: rest), startNs: entry.time * scale)
            case ID.simpleBlock: take(block: try await body(block, prefetched: rest), startNs: entry.time * scale, durationNs: nil)
            default: break
            }
            if let duration = entry.duration, let count = events[entry.track]?.count, count > before,
               events[entry.track]?[before].durationNs == nil {
                events[entry.track]?[before].durationNs = duration * scale
            }
        }
        return covered
    }

    private struct CueEntry: Equatable {
        var track: UInt64
        var clusterStart: Int64
        var relative: Int64?
        var time: Int64
        var duration: Int64?
    }

    /// Many small reads, `source.concurrentReads` in flight, in the order asked.
    private func fetch(_ ranges: [(offset: Int64, length: Int)]) async throws -> [[UInt8]] {
        let source = source
        let size = source.size
        let width = max(1, source.concurrentReads)
        var results = [[UInt8]](repeating: [], count: ranges.count)
        try await withThrowingTaskGroup(of: (Int, [UInt8]).self) { group in
            var started = 0
            func startNext() {
                guard started < ranges.count else { return }
                let index = started
                let (offset, length) = ranges[index]
                started += 1
                group.addTask {
                    let count = Int(max(0, min(Int64(length), size - offset)))
                    guard count > 0 else { return (index, []) }
                    return (index, [UInt8](try await source.read(offset: offset, length: count)))
                }
            }
            for _ in 0..<width { startNext() }
            while let (index, bytes) = try await group.next() {
                results[index] = bytes
                startNext()
            }
        }
        bytesRead += Int64(results.reduce(0) { $0 + $1.count })
        return results
    }

    // MARK: Walk

    private func walkClusters(_ numbers: Set<UInt64>) async throws {
        var position = segmentData
        while position < segmentEnd, let (head, _) = try await header(at: position) {
            if head.id == ID.cluster { try await walkCluster(head, tracks: numbers) }
            guard let end = head.end else { break }
            position = end
        }
    }

    private func walkCluster(_ cluster: Header, tracks numbers: Set<UInt64>) async throws {
        var position = cluster.dataStart
        let end = cluster.end ?? segmentEnd
        var clusterTime: Int64 = 0
        while position < end, let (head, rest) = try await header(at: position, prefetch: 32) {
            switch head.id {
            case ID.timecode:
                clusterTime = Int64(Self.uint(Array(rest.prefix(Int(head.size ?? 0)))))
            case ID.simpleBlock:
                if let (track, _, _) = Self.vint(rest[...], keepMarker: false), numbers.contains(track) {
                    take(block: try await body(head, prefetched: rest), clusterTime: clusterTime)
                }
            case ID.blockGroup:
                if let (blockId, idLength, _) = Self.vint(rest[...], keepMarker: true), UInt32(truncatingIfNeeded: blockId) == ID.block,
                   rest.count > idLength, let (_, sizeLength, _) = Self.vint(rest[idLength...], keepMarker: false),
                   rest.count > idLength + sizeLength,
                   let (track, _, _) = Self.vint(rest[(idLength + sizeLength)...], keepMarker: false), numbers.contains(track) {
                    takeGroup(try await body(head, prefetched: rest), clusterTime: clusterTime)
                }
            case ID.cluster:
                // An unknown-size Cluster ends where the next begins.
                return
            default: break
            }
            guard let next = head.end else { break }
            position = next
        }
    }

    // MARK: Blocks

    private func takeGroup(_ data: [UInt8], clusterTime: Int64) {
        guard let (block, duration) = Self.group(data), let relative = Self.relativeTime(block) else { return }
        take(block: block, startNs: (clusterTime + relative) * scale, durationNs: duration.map { $0 * scale })
    }

    private func takeGroup(_ data: [UInt8], startNs: Int64) {
        guard let (block, duration) = Self.group(data) else { return }
        take(block: block, startNs: startNs, durationNs: duration.map { $0 * scale })
    }

    private func take(block: [UInt8], clusterTime: Int64) {
        guard let relative = Self.relativeTime(block) else { return }
        take(block: block, startNs: (clusterTime + relative) * scale, durationNs: nil)
    }

    private static func group(_ data: [UInt8]) -> ([UInt8], Int64?)? {
        var block: [UInt8]?
        var duration: Int64?
        for (id, value) in children(data) {
            if id == ID.block { block = value }
            if id == ID.blockDuration { duration = Int64(uint(value)) }
        }
        return block.map { ($0, duration) }
    }

    private static func relativeTime(_ block: [UInt8]) -> Int64? {
        guard let (_, length, _) = vint(block[...], keepMarker: false), block.count >= length + 3 else { return nil }
        return Int64(Int16(bitPattern: UInt16(block[length]) << 8 | UInt16(block[length + 1])))
    }

    private func take(block: [UInt8], startNs: Int64, durationNs: Int64?) {
        guard let (track, length, _) = Self.vint(block[...], keepMarker: false), block.count >= length + 3 else { return }
        // Laced subtitle blocks: never seen in the wild; skipped.
        guard block[length + 2] & 0x06 == 0 else { return }
        var payload = Array(block[(length + 3)...])
        if let compression = compression[track] {
            switch compression.algorithm {
            case 0: payload = Self.inflate(payload)
            case 3: payload = compression.settings + payload
            default: return
            }
        }
        events[track, default: []].append(Event(startNs: startNs, durationNs: durationNs, payload: payload))
    }

    /// Matroska's zlib has the 2-byte zlib header; Compression wants raw
    /// deflate.
    static func inflate(_ zlib: [UInt8]) -> [UInt8] {
        guard zlib.count > 2 else { return [] }
        let input = Array(zlib.dropFirst(2))
        var capacity = max(1_024, input.count * 8)
        while capacity < 16 << 20 {
            var output = [UInt8](repeating: 0, count: capacity)
            let written = compression_decode_buffer(&output, capacity, input, input.count, nil, COMPRESSION_ZLIB)
            if written > 0, written < capacity { return Array(output.prefix(written)) }
            capacity *= 4
        }
        return []
    }

    // MARK: Text

    private static func stamp(_ ns: Int64, ass: Bool) -> String {
        let ms = max(0, ns / 1_000_000)
        let hours = ms / 3_600_000, minutes = ms / 60_000 % 60, seconds = ms / 1_000 % 60, fraction = ms % 1_000
        return ass
            ? String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, fraction / 10)
            : String(format: "%02d:%02d:%02d%@%03d", hours, minutes, seconds, ",", fraction)
    }

    private func render(_ track: MatroskaSubtitleTrack, _ events: [Event]) -> String {
        let sorted = events.sorted { $0.startNs < $1.startNs }
        switch track.format {
        case .ass:
            // Matroska keeps ReadOrder, Layer, Style, Name, MarginL, MarginR,
            // MarginV, Effect, Text; the times live on the block.
            let lines = sorted.map { event -> (Int, String) in
                let fields = String(decoding: event.payload, as: UTF8.self).split(separator: ",", maxSplits: 8, omittingEmptySubsequences: false)
                let order = Int(fields.first ?? "") ?? 0
                let layer = fields.count > 1 ? String(fields[1]) : "0"
                let rest = fields.dropFirst(2).joined(separator: ",")
                let end = event.startNs + (event.durationNs ?? 0)
                return (order, "Dialogue: \(layer),\(Self.stamp(event.startNs, ass: true)),\(Self.stamp(end, ass: true)),\(rest)")
            }
            var header = String(decoding: codecPrivate[track.number] ?? [], as: UTF8.self)
            if !header.contains("[Events]") { header += "\n[Events]\n" }
            return header + lines.sorted { $0.0 < $1.0 }.map(\.1).joined(separator: "\n") + "\n"
        case .vtt:
            return "WEBVTT\n\n" + sorted.map { event in
                "\(Self.stamp(event.startNs, ass: false).replacingOccurrences(of: ",", with: ".")) --> \(Self.stamp(event.startNs + (event.durationNs ?? 0), ass: false).replacingOccurrences(of: ",", with: "."))\n\(String(decoding: event.payload, as: UTF8.self))\n"
            }.joined(separator: "\n")
        default:
            return sorted.enumerated().map { index, event in
                "\(index + 1)\n\(Self.stamp(event.startNs, ass: false)) --> \(Self.stamp(event.startNs + (event.durationNs ?? 0), ass: false))\n\(String(decoding: event.payload, as: UTF8.self))\n"
            }.joined(separator: "\n")
        }
    }
}
