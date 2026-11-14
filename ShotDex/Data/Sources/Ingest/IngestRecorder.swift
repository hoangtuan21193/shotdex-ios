import Foundation

/// What a verified file leaves behind (FS-20 §7.3, AC-15): a history row
/// written at once — so a run cut short still knows what it did — and, for
/// a photo's primary file, a `.xmp` beside the copy with the preset and the
/// day it was taken, whatever the sidecar switch in Settings says (AC-24).
struct IngestRecorder: Sendable {
    let database: AppDatabase
    let cardId: String
    let cardName: String
    let sourceId: String
    let destinationRoot: URL
    let metadata: IngestMetadataPreset
    let items: [String: CardItem]
    var now: @Sendable () -> Date = { Date() }

    func handle(_ event: IngestEvent) {
        switch event {
        case .fileVerified(let itemId, let file, let path, let sha):
            try? CardImportStore(database: database).record(.init(
                cardId: cardId, cardName: cardName, originalPath: file.path, originalName: file.name,
                byteCount: file.size, capturedAt: Int64((file.modified ?? .distantPast).timeIntervalSince1970),
                sha256: sha, sourceId: sourceId, destinationPath: path, photoId: nil, backupPath: nil,
                importedAt: Int64(now().timeIntervalSince1970)))
            guard let item = items[itemId], file == item.primary, item.kind == .photo else { return }
            let image = destinationRoot.appendingPathComponent(path)
            _ = try? SidecarWriter.write(metadata.patch(captureDate: item.date),
                                         to: SidecarWriter.sidecarURL(forImageAt: image, isPaired: true))
        case .backedUp(let itemId, let paths):
            guard let item = items[itemId] else { return }
            for (file, path) in zip(item.files, paths) {
                try? CardImportStore(database: database).recordBackup(originalPath: file.path, cardId: cardId, backupPath: path)
            }
        case .imported, .failed, .progress, .stage, .parked:
            break
        }
    }
}
