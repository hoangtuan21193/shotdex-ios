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
        /// Copies whose sidecar could not be written (no permission, a full
        /// disk); each keeps a pending mark.
        var failed = 0
        /// Copies not written because their source is offline or cannot be
        /// opened now; each keeps a pending mark.
        var pending = 0
        /// Photos whose values changed because another app had written their
        /// sidecar — what the app shows of them is out of date.
        var reread: Set<String> = []
    }

    func write(photoIds: [String]) throws -> Summary {
        var summary = Summary()
        for photoId in photoIds {
            let copies = try database.reader.read { db in try Self.fileCopies(db, photoId: photoId) }
            var sidecars: [(copyId: String, url: URL)] = []
            for copy in copies {
                // A copy on a drive that is not plugged in is written when it
                // comes back; until then it carries a pending mark (FS-19.02 §7).
                guard copy.isOnline, let image = fileURL(copy.sourceId, copy.relativePath) else {
                    try markPending(copy.id, photoId: photoId, reason: copy.isOnline ? .unavailable : .offline)
                    summary.pending += 1
                    continue
                }
                let sidecar = Self.sidecarURL(forImageAt: image, isPaired: copy.isPaired)
                if try rereadIfChanged(sidecar, since: copy.sidecarStamp, photoId: photoId) {
                    summary.reread.insert(photoId)
                }
                sidecars.append((copy.id, sidecar))
            }
            let patch = try database.reader.read { db in try Self.patch(db, photoId: photoId) }
            for sidecar in sidecars {
                do {
                    try Self.write(patch, to: sidecar.url)
                    let stamp = SidecarReader.stamp(of: sidecar.url)
                    try database.writer.write { db in
                        try db.execute(sql: "UPDATE photo_copies SET sidecarStamp = ? WHERE id = ?", arguments: [stamp, sidecar.copyId])
                        try db.execute(sql: "DELETE FROM pending_sidecar WHERE copyId = ?", arguments: [sidecar.copyId])
                    }
                    summary.written += 1
                } catch {
                    try markPending(sidecar.copyId, photoId: photoId, reason: .writeFailed)
                    summary.failed += 1
                }
            }
        }
        return summary
    }

    /// Why a copy's sidecar waits. The mark is user data (FS-19.05 §3): it
    /// survives Clear Local Metadata Index and points at the winner after a
    /// merge.
    enum PendingReason: String {
        /// The drive is not plugged in.
        case offline
        /// The source's folder cannot be opened now.
        case unavailable
        /// The write itself failed.
        case writeFailed
    }

    private func markPending(_ copyId: String, photoId: String, reason: PendingReason) throws {
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO pending_sidecar (copyId, photoId, reason, markedAt) VALUES (?, ?, ?, ?)
                ON CONFLICT(copyId) DO UPDATE SET photoId = excluded.photoId, reason = excluded.reason, markedAt = excluded.markedAt
                """, arguments: [copyId, photoId, reason.rawValue, Int(Date().timeIntervalSince1970)])
        }
    }

    /// Another app may have written the sidecar since ShotDex last read or
    /// wrote it: its stamp no longer matches. What it says comes in first —
    /// each field by the later change — so the write carries it along rather
    /// than over it (FS-19.02 §6).
    private func rereadIfChanged(_ sidecar: URL, since known: String?, photoId: String) throws -> Bool {
        guard let stamp = SidecarReader.stamp(of: sidecar), stamp != known,
              let values = SidecarReader.read(sidecarAt: sidecar) else { return false }
        let at = Int((SidecarReader.modified(sidecar) ?? Date()).timeIntervalSince1970)
        try database.writer.write { db in
            try PhotoUserMarksStore.applySidecar(db, values: values, photoId: photoId, at: at)
        }
        return true
    }

    /// The sidecar of `image`: whichever of `DSC0001.xmp` and
    /// `DSC0001.ARW.xmp` is there (the newer when both are), else
    /// `DSC0001.xmp` — the name Lightroom, Capture One and Bridge read. A
    /// JPEG not paired with the RAW beside it always uses `DSC0001.JPG.xmp`;
    /// `DSC0001.xmp` is the RAW's (FS-19.01 §3).
    static func sidecarURL(forImageAt image: URL, isPaired: Bool = true) -> URL {
        let base = image.deletingPathExtension().appendingPathExtension("xmp")
        let full = image.appendingPathExtension("xmp")
        if !isPaired {
            let siblings = (try? FileManager.default.contentsOfDirectory(atPath: image.deletingLastPathComponent().path)) ?? []
            if PairingRule.usesFullNameSidecar(image.lastPathComponent, siblings: siblings) { return full }
        }
        let existing = [base, full].filter { FileManager.default.fileExists(atPath: $0.path) }
        return existing.max { modified($0) < modified($1) } ?? base
    }

    /// Patches the sidecar through a temporary file in the same folder and
    /// swaps it in, so a reader never sees half a file.
    static func write(_ patch: XMPPatch, to sidecar: URL) throws {
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
    /// Rejected), its keywords, title and caption, and in ShotDex's namespace
    /// its flag, real stars, favorite and recipe.
    static func patch(_ db: Database, photoId: String) throws -> XMPPatch {
        var patch = XMPPatch()
        let marks = try Row.fetchOne(db, sql: "SELECT rating, isFavorite, title, caption FROM photo_user_marks WHERE photoId = ?",
                                     arguments: [photoId])
        let flag = try String.fetchOne(db, sql: "SELECT flag FROM photo_flag WHERE assetId = ?", arguments: [photoId])
        let rating: Int? = marks?["rating"]
        if flag == PhotoFlag.reject.rawValue {
            patch.rating = .set(-1)
        } else if let rating {
            patch.rating = .set(rating)
        }
        // Pick and Reject both live in ShotDex's namespace too: the standard
        // field has no Pick, and its −1 hides the stars a Reject keeps —
        // which is why the real stars are there as well.
        patch.shotdex["Flag"] = flag.map { .set($0) } ?? .remove
        patch.shotdex["Rating"] = rating.map { .set(String($0)) } ?? .remove
        let isFavorite: Bool? = marks?["isFavorite"]
        patch.shotdex["Favorite"] = isFavorite == true ? .set("True") : .remove
        let recipe = try Data.fetchOne(db, sql: "SELECT recipe FROM photo_recipes WHERE photoId = ?", arguments: [photoId])
        patch.shotdex["Recipe"] = recipe.map { .set($0.base64EncodedString()) } ?? .remove
        if let title: String = marks?["title"] { patch.title = .set(title) }
        if let caption: String = marks?["caption"] { patch.caption = .set(caption) }
        let keywords = try String.fetchAll(db, sql: "SELECT keyword FROM photo_user_keyword WHERE photoId = ? ORDER BY addedAt, rowid",
                                           arguments: [photoId])
        patch.keywords = .set(keywords)
        return patch
    }

    private struct Copy {
        let id: String
        let sourceId: String
        let relativePath: String
        let isPaired: Bool
        let isOnline: Bool
        let sidecarStamp: String?
    }

    /// Every file copy that is still there — online or on a drive that is
    /// not plugged in. A missing file or a cloud placeholder has no sidecar
    /// to write.
    private static func fileCopies(_ db: Database, photoId: String) throws -> [Copy] {
        try Row.fetchAll(db, sql: """
            SELECT id, sourceId, relativePath, pairedPath, isOnline, sidecarStamp FROM photo_copies
            WHERE photoId = ? AND kind = 'file' AND missingSince IS NULL AND isCloudPlaceholder = 0
            ORDER BY id
            """, arguments: [photoId]).map {
            Copy(id: $0["id"], sourceId: $0["sourceId"], relativePath: $0["relativePath"],
                 isPaired: ($0["pairedPath"] as String?) != nil, isOnline: $0["isOnline"], sidecarStamp: $0["sidecarStamp"])
        }
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
    /// Told which photos took values from a sidecar another app wrote, so
    /// what is on screen follows (`PhotoMarks.reload`).
    private var onReread: (@Sendable (Set<String>) async -> Void)?

    static let defaultDelay: Duration = .seconds(1)

    init(writer: SidecarWriter, delay: Duration = SidecarWriteQueue.defaultDelay) {
        self.writer = writer
        self.delay = delay
    }

    func setOnReread(_ handler: @escaping @Sendable (Set<String>) async -> Void) {
        onReread = handler
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
        let summary = (try? writer.write(photoIds: ids)) ?? SidecarWriter.Summary()
        if !summary.reread.isEmpty, let onReread {
            Task { await onReread(summary.reread) }
        }
        return summary
    }
}
