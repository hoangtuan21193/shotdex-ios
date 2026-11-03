import Foundation

/// The random check (FS-19.07 §12.4): per device this device holds hashes
/// from, reads again up to K files whose hash from that device makes a photo
/// match. A file read here keeps the hash read here. One that differs drops
/// every hash that device sent up to now, from iCloud and from the ledger
/// alike; those files are unchecked again and hashed here, and what the
/// device sends later is trusted again, checked the same way.
struct SharedHashAuditPass: Sendable {
    let store: CopyFileStore
    var sampleSize = SharedHashAudit.sampleSize
    /// Reads the file here; nil when it cannot now (a rule waits, offline,
    /// no space) — skipped, which is not a mismatch.
    var readHere: @Sendable (CopyFileStore.AuditFile) async -> String?

    /// What may be read now: Photos files, and these server sources (nil:
    /// all).
    var photos = true
    var sources: Set<String>?

    struct Summary: Equatable, Sendable {
        var checked = 0
        /// Devices some of whose files were read and all found right.
        var cleared: [String] = []
        /// Devices caught wrong in this pass.
        var caught: [String] = []
        /// Hashes dropped because of them.
        var dropped = 0
    }

    /// Stops between files when cancelled and returns what it found so far:
    /// a device already caught stays caught.
    func run(now: Date = Date()) async throws -> Summary {
        var summary = Summary()
        for device in try store.auditDevices() {
            var checked = 0
            var caught = false
            for file in try store.auditSample(device: device, limit: sampleSize, photos: photos, sources: sources) {
                if Task.isCancelled { return summary }
                guard let sha = await readHere(file)?.lowercased() else { continue }
                // Read while it was being sampled: a changed row is not the
                // device's fault.
                guard try store.files(copyId: file.copyId).first(where: { $0.fileKey == file.fileKey })?.sha256 == file.sha256
                else { continue }
                checked += 1
                summary.checked += 1
                if SharedHashAudit.isMismatch(sent: file.sha256, readHere: sha) {
                    summary.dropped += try store.recordMismatch(sha, copyId: file.copyId, fileKey: file.fileKey, device: device, at: now)
                    summary.caught.append(device)
                    caught = true
                    break
                }
                // Read here: the file's own hash from now on.
                try store.saveHash(sha, copyId: file.copyId, fileKey: file.fileKey, origin: .hashed, at: now)
            }
            if checked > 0, !caught { summary.cleared.append(device) }
        }
        return summary
    }
}
