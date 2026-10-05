import Foundation
import GRDB

/// Writes what ShotDex holds about a photo into the `.xmp` sidecar beside
/// every online file copy of it (FS-19.02 §5). The image file itself is
/// never opened for writing — not even a JPEG.
struct SidecarWriter: Sendable {
    let database: AppDatabase
    /// Where a copy's file is now; nil when its source cannot be opened.
    let fileURL: @Sendable (_ sourceId: String, _ relativePath: String) -> URL?

    struct Summary: Equatable, Sendable {
        var written = 0
        /// Copies whose sidecar could not be written (no folder, no permission).
        var failed = 0
    }

    func write(photoIds: [String]) throws -> Summary {
        var summary = Summary()
        for photoId in photoIds {
            let (patch, copies) = try database.reader.read { db in
                (try Self.patch(db, photoId: photoId), try Self.onlineFileCopies(db, photoId: photoId))
            }
            for copy in copies {
                guard let image = fileURL(copy.sourceId, copy.relativePath) else {
                    summary.failed += 1
                    continue
                }
                do {
                    try Self.write(patch, beside: image)
                    summary.written += 1
                } catch {
                    summary.failed += 1
                }
            }
        }
        return summary
    }

    /// The sidecar of `image`: whichever of `DSC0001.xmp` and
    /// `DSC0001.ARW.xmp` is there (the newer when both are), else
    /// `DSC0001.xmp` — the name Lightroom, Capture One and Bridge read.
    static func sidecarURL(forImageAt image: URL) -> URL {
        let base = image.deletingPathExtension().appendingPathExtension("xmp")
        let full = image.appendingPathExtension("xmp")
        let existing = [base, full].filter { FileManager.default.fileExists(atPath: $0.path) }
        return existing.max { modified($0) < modified($1) } ?? base
    }

    /// Patches the sidecar through a temporary file in the same folder and
    /// swaps it in, so a reader never sees half a file.
    static func write(_ patch: XMPPatch, beside image: URL) throws {
        let sidecar = sidecarURL(forImageAt: image)
        let current = try? String(contentsOf: sidecar, encoding: .utf8)
        let text = XMPPatcher.apply(patch, to: current)
        guard text != current else { return }
        let temporary = sidecar.deletingLastPathComponent()
            .appendingPathComponent(".\(sidecar.lastPathComponent).\(UUID().uuidString).tmp")
        try Data(text.utf8).write(to: temporary)
        do {
            if current != nil {
                _ = try FileManager.default.replaceItemAt(sidecar, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: sidecar)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    /// The photo's current values as a patch: the standard rating (−1 when
    /// Rejected), its keywords, title and caption.
    static func patch(_ db: Database, photoId: String) throws -> XMPPatch {
        var patch = XMPPatch()
        let marks = try Row.fetchOne(db, sql: "SELECT rating, title, caption FROM photo_user_marks WHERE photoId = ?", arguments: [photoId])
        let flag = try String.fetchOne(db, sql: "SELECT flag FROM photo_flag WHERE assetId = ?", arguments: [photoId])
        if flag == PhotoFlag.reject.rawValue {
            patch.rating = .set(-1)
        } else if let rating: Int = marks?["rating"] {
            patch.rating = .set(rating)
        }
        if let title: String = marks?["title"] { patch.title = .set(title) }
        if let caption: String = marks?["caption"] { patch.caption = .set(caption) }
        let keywords = try String.fetchAll(db, sql: "SELECT keyword FROM photo_user_keyword WHERE photoId = ? ORDER BY addedAt, rowid",
                                           arguments: [photoId])
        patch.keywords = .set(keywords)
        return patch
    }

    private static func onlineFileCopies(_ db: Database, photoId: String) throws -> [(sourceId: String, relativePath: String)] {
        try Row.fetchAll(db, sql: """
            SELECT sourceId, relativePath FROM photo_copies
            WHERE photoId = ? AND kind = 'file' AND isOnline = 1 AND missingSince IS NULL AND isCloudPlaceholder = 0
            ORDER BY id
            """, arguments: [photoId]).map { ($0["sourceId"], $0["relativePath"]) }
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

/// Sidecar writes wait for the last change to settle — one second after it
/// (FS-19.02 §5) — so a run of key presses in the culling pass is one write
/// per photo, not one per press.
actor SidecarWriteQueue {
    private let writer: SidecarWriter
    private let delay: Duration
    private var pending: Set<String> = []
    private var timer: Task<Void, Never>?

    init(writer: SidecarWriter, delay: Duration = .seconds(1)) {
        self.writer = writer
        self.delay = delay
    }

    func schedule(_ photoIds: some Sequence<String> & Sendable) {
        pending.formUnion(photoIds)
        timer?.cancel()
        timer = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self.flush()
        }
    }

    /// Writes everything waiting now.
    @discardableResult
    func flush() -> SidecarWriter.Summary {
        timer?.cancel()
        timer = nil
        let ids = pending.sorted()
        pending = []
        return (try? writer.write(photoIds: ids)) ?? SidecarWriter.Summary()
    }
}
