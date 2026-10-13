import Foundation
import Testing
@testable import ShotDex

/// The shared index's file format and merge rules (FS-22.05 §2, §6).
@Suite struct BackupContentIndexTests {
    private let sha = String(repeating: "ab", count: 32)

    private func line(_ path: String, size: Int64 = 10, modified: Int? = 100) -> BackupContentIndex.Line {
        .init(path: path, size: size, modified: modified, sha256: sha, device: "D", recordedAt: 1)
    }

    @Test func segmentNamesCountPerDevice() {
        #expect(BackupContentIndex.segmentName(device: "A1B2-C3", number: 7) == "A1B2-C3-000007.jsonl")
        #expect(BackupContentIndex.parseSegment("A1B2-C3-000007.jsonl")! == ("A1B2-C3", 7))
        #expect(BackupContentIndex.parseSegment("A1B2-C3-000007.jsonl.shotdex-part") == nil)
        #expect(BackupContentIndex.parseSegment("notes.txt") == nil)
        let names = ["A-000001.jsonl", "A-000004.jsonl", "B-000009.jsonl", "junk"]
        #expect(BackupContentIndex.nextNumber(device: "A", existing: names) == 5)
        #expect(BackupContentIndex.nextNumber(device: "C", existing: names) == 1)
    }

    /// A cut-off, malformed or escaping line is skipped; the rest are read.
    @Test func badLinesAreSkippedNotTheSegment() {
        var data = BackupContentIndex.encode([line("a/1.HEIC"), line("b/2.HEIC")])
        data.append(Data("{\"path\":\"../x\",\"size\":1,\"sha256\":\"\(sha)\",\"device\":\"D\",\"recordedAt\":1}\n".utf8))
        data.append(Data("{\"path\":\"c.HEIC\",\"size\":1,\"sha256\":\"zz\",\"device\":\"D\",\"recordedAt\":1}\n".utf8))
        data.append(Data("{\"path\":\"d.HEIC\",\"si".utf8))
        #expect(BackupContentIndex.decode(data).map(\.path) == ["a/1.HEIC", "b/2.HEIC"])
    }

    @Test func mergeTrustsOnlyMatchingFiles() {
        let listed = BackupDestinationFile(jobId: "J", path: "a.HEIC", size: 10, modified: 100, origin: .listed)
        #expect(BackupContentIndex.merged(line("a.HEIC"), into: listed, jobId: "J", now: 5)?.sha256 == sha)
        // Another size, or another date: the file changed after the line.
        #expect(BackupContentIndex.merged(line("a.HEIC", size: 11), into: listed, jobId: "J", now: 5) == nil)
        #expect(BackupContentIndex.merged(line("a.HEIC", modified: 200), into: listed, jobId: "J", now: 5) == nil)
        // A date nobody knew yet does not block it.
        var undated = listed
        undated.modified = nil
        #expect(BackupContentIndex.merged(line("a.HEIC"), into: undated, jobId: "J", now: 5)?.modified == 100)
        // Not listed here: taken as there, asked for before it counts.
        let added = BackupContentIndex.merged(line("new.HEIC"), into: nil, jobId: "J", now: 5)
        #expect(added?.origin == .index)
        #expect(added?.needsPublish == false)
    }
}
