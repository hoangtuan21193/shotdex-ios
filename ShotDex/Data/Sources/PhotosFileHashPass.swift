import Foundation
import Photos

/// The Photos side of the on-server check (FS-19.07 §4): lists each asset's
/// original files with their sizes — no download — and takes the SHA-256
/// Backup already recorded for every file it copied whose stamp still
/// matches. Every listing is written as it is read, so a pass stopped
/// anywhere goes on from the next asset.
struct PhotosFileHashPass: Sendable {
    let store: CopyFileStore
    /// An asset's files as PhotoKit lists them; injected so tests need no
    /// library.
    let listFiles: @Sendable (_ assetId: String) async throws -> [PhotosFile]

    struct Summary: Equatable, Sendable {
        var listed = 0
        var seeded = 0
    }

    /// Lists up to `limit` assets that were never listed or changed since,
    /// newest first, then fills what Backup's ledger knows.
    @discardableResult
    func run(limit: Int = 200, now: Date = Date()) async throws -> Summary {
        var summary = Summary()
        for copy in try store.photosCopiesNeedingListing(limit: limit) {
            try Task.checkCancellation()
            // An asset gone from the library since the index: the indexer
            // removes its copy; nothing to list.
            guard let files = try? await listFiles(copy.assetId) else { continue }
            try store.saveListing(copyId: copy.copyId, stamp: copy.stamp, files: files, at: now)
            summary.listed += 1
        }
        summary.seeded = try store.seedFromBackupLedger(at: now)
        return summary
    }
}

extension PhotosFileHashPass {
    enum ListError: Error { case missingAsset }

    /// The asset's originals and edit renders through PhotoKit — one round
    /// trip, sizes from the resource, stamped as Backup stamps them.
    static func liveLister() -> @Sendable (String) async throws -> [PhotosFile] {
        { assetId in
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject
            else { throw ListError.missingAsset }
            let created = Int(asset.creationDate?.timeIntervalSince1970 ?? 0)
            let modified = Int(asset.modificationDate?.timeIntervalSince1970 ?? 0)
            return PhotoKitOriginalExporter.uploadFiles(for: asset).compactMap { file in
                guard let type = Int(file.key.prefix { $0 != ":" }),
                      let role = CopyFile.Role(resourceType: type, isRAW: file.isRAW) else { return nil }
                return PhotosFile(fileKey: file.key, role: role, size: file.estimatedBytes > 0 ? file.estimatedBytes : nil,
                                  stamp: PhotoKitBackupSource.stamp(for: file, created: created, modified: modified))
            }
        }
    }
}
