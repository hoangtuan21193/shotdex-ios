import Foundation
import GRDB

/// Writes what ShotDex holds about a photo into the `.xmp` sidecar beside
/// every online file copy of it (FS-19.02 §5). The image file itself is
/// never opened for writing — not even a JPEG.
struct SidecarWriter: Sendable {
    let database: AppDatabase
    /// Where a copy's file is now; nil when its source cannot be opened.
    let fileURL: @Sendable (_ sourceId: String, _ relativePath: String) -> URL?
    /// Read and Write .xmp Sidecars. Off: nothing is written and nothing is
    /// marked pending — the values stay in ShotDex's own tables.
    var isEnabled: @Sendable () -> Bool = { SidecarSetting.isOn() }

    struct Summary: Equatable, Sendable {
        /// Sidecars whose text changed. One that already said the photo's
        /// values is left alone and not counted.
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
        guard isEnabled() else { return summary }
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
                    if try Self.write(patch, to: sidecar.url) { summary.written += 1 }
                    let stamp = SidecarReader.stamp(of: sidecar.url)
                    try database.writer.write { db in
                        try db.execute(sql: "UPDATE photo_copies SET sidecarStamp = ? WHERE id = ?", arguments: [stamp, sidecar.copyId])
                        try db.execute(sql: "DELETE FROM pending_sidecar WHERE copyId = ?", arguments: [sidecar.copyId])
                    }
                } catch {
                    try markPending(sidecar.copyId, photoId: photoId, reason: Self.isReadOnly(error) ? .readOnly : .writeFailed)
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
        /// The volume, the share or the folder does not let ShotDex write.
        /// Retried when the copy comes back online.
        case readOnly
        /// The write itself failed for another reason.
        case writeFailed
    }

    /// A write refused for lack of permission rather than for space or a
    /// vanished folder.
    static func isReadOnly(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain,
           [NSFileWriteNoPermissionError, NSFileWriteVolumeReadOnlyError].contains(error.code) { return true }
        if error.domain == NSPOSIXErrorDomain, [Int(EACCES), Int(EROFS), Int(EPERM)].contains(error.code) { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error { return isReadOnly(underlying) }
        return false
    }

    /// Photos with a pending mark in `sourceId`, by reason — what the source
    /// row reports (FS-19.02 §5).
    func pendingProblems(sourceId: String) throws -> [PendingReason: Int] {
        try database.reader.read { db in
            var out: [PendingReason: Int] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT p.reason, COUNT(DISTINCT p.photoId) AS photos FROM pending_sidecar p
                JOIN photo_copies c ON c.id = p.copyId WHERE c.sourceId = ? GROUP BY p.reason
                """, arguments: [sourceId]) {
                if let reason = PendingReason(rawValue: row["reason"]) { out[reason] = row["photos"] }
            }
            return out
        }
    }

    /// The source row's line for photos whose sidecar could not be saved;
    /// nil for a reason the row does not report (an unplugged drive says so
    /// on its own).
    static func problemLine(reason: PendingReason, photos: Int, sourceName: String, locale: Locale = .current) -> String? {
        guard reason == .readOnly else { return nil }
        return String(AttributedString(
            localized: "Couldn't save .xmp for ^[\(photos) photo](inflect: true) · \(sourceName) is read-only",
            locale: locale,
            comment: "Sources: a folder or drive ShotDex may not write to; stars and keywords stay in ShotDex until it can"
        ).characters)
    }

    /// Photos with a pending mark on a copy in `sourceId`.
    func pendingPhotoIds(sourceId: String) throws -> [String] {
        try database.reader.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT p.photoId FROM pending_sidecar p JOIN photo_copies c ON c.id = p.copyId
                WHERE c.sourceId = ? ORDER BY p.photoId
                """, arguments: [sourceId])
        }
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
    /// Returns whether the file changed.
    @discardableResult
    static func write(_ patch: XMPPatch, to sidecar: URL) throws -> Bool {
        let current = try? String(contentsOf: sidecar, encoding: .utf8)
        let text = XMPPatcher.apply(patch, to: current)
        guard text != current else { return false }
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
        return true
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

    /// A drive came back (or a folder opened again): the photos with a
    /// pending mark there get their current values, once (FS-19.02 §7) —
    /// not a replay of every change made while it was away.
    @discardableResult
    func sourceCameOnline(_ sourceId: String) -> SidecarWriter.Summary {
        guard let ids = try? writer.pendingPhotoIds(sourceId: sourceId), !ids.isEmpty else { return SidecarWriter.Summary() }
        pending.formUnion(ids)
        return flush()
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

/// The Read and Write .xmp Sidecars switch (FS-19.02 §5), on unless the
/// user turned it off.
enum SidecarSetting {
    static func isOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: SettingsKeys.readsAndWritesSidecars) as? Bool ?? true
    }
}
