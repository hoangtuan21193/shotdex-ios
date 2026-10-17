import CryptoKit
import Foundation
import GRDB

/// The background read that refines "already imported" (FS-20 §5, AC-22):
/// each card file once, a SHA-256 of the whole file to hold against the
/// history and the library's content hash to find the photo in a source
/// the history never saw. The import does not wait for it.
struct CardHashPass: Sendable {
    let database: AppDatabase
    let reader: any CardReader
    /// The card's file on disk, for the content hash's ranged reads.
    let fileURL: @Sendable (CardFile) -> URL?

    /// Hashes `files` in order, reporting each as it lands; a cancelled task
    /// stops between files.
    func run(_ files: [CardFile], onHashed: @Sendable (String, IngestStatus.Hashed) async -> Void) async {
        for file in files {
            guard !Task.isCancelled else { return }
            guard let hashed = try? await hash(file) else { continue }
            await onHashed(file.path, hashed)
        }
    }

    func hash(_ file: CardFile) async throws -> IngestStatus.Hashed {
        var hasher = SHA256()
        try await reader.read(file.path, chunkSize: IngestRunner.chunkSize) { data in hasher.update(data: data) }
        let sha = FileChecksum.hex(hasher.finalize())
        var isInASource = false
        if let url = fileURL(file), let content = try? ContentHasher.hash(FileBytes(url: url), full: true), let full = content.full {
            isInASource = try await database.reader.read { db in
                try Bool.fetchOne(db, sql: """
                    SELECT EXISTS(SELECT 1 FROM content_hashes h JOIN photo_copies c ON c.id = h.copyId
                                  WHERE h.algorithm = ? AND h.algorithmVersion = ? AND h.fullHash = ? AND c.missingSince IS NULL)
                    """, arguments: [content.algorithm, content.version, full]) ?? false
            }
        }
        return IngestStatus.Hashed(sha256: sha, isInASource: isInASource)
    }
}
