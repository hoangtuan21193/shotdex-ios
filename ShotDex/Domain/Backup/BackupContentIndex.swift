import Foundation

/// The shared index on the NAS (FS-22.05 §2): what each device knows of a
/// destination folder, so a photo another phone already copied is not copied
/// again.
///
/// Each device writes only its own segments — `<device>-<n>.jsonl` under
/// `.shotdex/backup-index/` in the destination folder, a new one per run that
/// learned something — and never touches another's: SMB and WebDAV have no
/// lock, and two writers on one file lose lines. One line is one file.
enum BackupContentIndex {
    /// Relative to the job's folder.
    static let folder = ".shotdex/backup-index"
    static let segmentExtension = "jsonl"

    struct Line: Codable, Equatable, Sendable {
        /// Relative to the job's folder.
        var path: String
        var size: Int64
        /// Modification time at the destination, seconds; nil = not known.
        var modified: Int?
        var sha256: String
        /// The device that wrote the line.
        var device: String
        var recordedAt: Int
    }

    // MARK: Segments

    static func segmentName(device: String, number: Int) -> String {
        "\(device)-\(String(format: "%06d", number)).\(segmentExtension)"
    }

    /// The device and number of a segment's file name; nil for anything else
    /// in the folder (a part file, a stray note).
    static func parseSegment(_ name: String) -> (device: String, number: Int)? {
        guard name.hasSuffix(".\(segmentExtension)") else { return nil }
        let stem = name.dropLast(segmentExtension.count + 1)
        guard let dash = stem.lastIndex(of: "-"), let number = Int(stem[stem.index(after: dash)...]), number > 0 else { return nil }
        let device = String(stem[..<dash])
        return device.isEmpty ? nil : (device, number)
    }

    /// The number of this device's next segment, after every one it wrote
    /// before — this install or an earlier one.
    static func nextNumber(device: String, existing names: some Sequence<String>) -> Int {
        names.compactMap(parseSegment).filter { $0.device == device }.map(\.number).max().map { $0 + 1 } ?? 1
    }

    // MARK: Lines

    static func encode(_ lines: [Line]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = Data()
        for line in lines {
            guard let json = try? encoder.encode(line) else { continue }
            data.append(json)
            data.append(0x0A)
        }
        return data
    }

    /// Every readable line; one that is cut off, malformed or points outside
    /// the folder is skipped, never the whole segment (FS-22.05 §2).
    static func decode(_ data: Data) -> [Line] {
        let decoder = JSONDecoder()
        var lines: [Line] = []
        for slice in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let line = try? decoder.decode(Line.self, from: Data(slice)), isValid(line) else { continue }
            lines.append(line)
        }
        return lines
    }

    private static func isValid(_ line: Line) -> Bool {
        let components = line.path.split(separator: "/", omittingEmptySubsequences: false)
        return line.size >= 0
            && line.sha256.count == 64 && line.sha256.allSatisfy(\.isHexDigit)
            && !line.path.isEmpty && !line.path.hasPrefix("/")
            && !components.contains { $0.isEmpty || $0 == ".." || $0 == "." }
            && !line.path.hasPrefix(".shotdex/")
    }

    // MARK: Merging

    /// What a line read from the shared index changes in this device's copy:
    /// the row to save, or nil when the line adds nothing or is out of date
    /// (FS-22.05 §2, §6).
    ///
    /// A line names a file this device has listed only if the size agrees —
    /// and the date, when both know it; otherwise the file changed since the
    /// line was written and its hash is not trusted. A file this device has
    /// not listed is taken as there; it is asked for before it counts.
    static func merged(_ line: Line, into existing: BackupDestinationFile?, jobId: String, now: Int) -> BackupDestinationFile? {
        guard var row = existing else {
            return BackupDestinationFile(
                jobId: jobId, path: line.path, size: line.size, modified: line.modified,
                sha256: line.sha256.lowercased(), origin: .index, seenAt: now
            )
        }
        guard row.sha256 == nil, row.size == line.size else { return nil }
        if let known = row.modified, let written = line.modified, known != written { return nil }
        row.sha256 = line.sha256.lowercased()
        row.modified = row.modified ?? line.modified
        return row
    }
}
