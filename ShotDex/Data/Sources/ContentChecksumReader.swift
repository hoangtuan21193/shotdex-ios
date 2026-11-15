import Foundation
import os
import Photos

/// Reads an original's bytes through PhotoKit, chunk by chunk, into a
/// SHA-256 (FS-06.06 §14.2). The resource is the one the index measured
/// (`ExifReader.photoResource`), so the byte count that picked the candidate
/// and the bytes hashed are the same file. Network only when the scan may use
/// it — an iCloud-only original stays unread otherwise. Each read stops at
/// `timeout`, and a cancelled task cancels the read in flight.
enum ContentChecksumReader {
    typealias Record = (assetId: String, modificationDate: Int?, sha256: String?)

    static let timeout: Duration = .seconds(60)
    /// Results are written every this many photos, so a cancel or a kill
    /// keeps what was read.
    static let batchSize = 20

    /// Reads each candidate, skipping one whose photo changed since it was
    /// indexed; a failed read comes back with a nil checksum so it is not
    /// retried until the network may be used. `onBatch` stores results as
    /// they come.
    static func read(
        _ photos: [HashedPhoto],
        allowNetwork: Bool,
        onBatch: ([Record]) -> Void
    ) async {
        let indexedDates = Dictionary(photos.map { ($0.assetId, $0.modificationDate) }, uniquingKeysWith: { first, _ in first })
        var batch: [Record] = []
        for asset in PhotoLibraryService.fetchAssets(ids: photos.map(\.assetId)) {
            if Task.isCancelled { break }
            let date = asset.modificationDate.map { Int($0.timeIntervalSince1970) }
            // Changed since indexing: the size that picked it is stale.
            guard date == indexedDates[asset.localIdentifier] ?? nil else { continue }
            let sha = await checksum(of: asset, allowNetwork: allowNetwork)
            if Task.isCancelled { break }
            batch.append((asset.localIdentifier, date, sha))
            if batch.count >= batchSize { onBatch(batch); batch.removeAll() }
        }
        if !batch.isEmpty { onBatch(batch) }
    }

    private static func checksum(of asset: PHAsset, allowNetwork: Bool) async -> String? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = ExifReader.photoResource(among: resources),
              [.photo, .fullSizePhoto, .alternatePhoto].contains(resource.type) else { return nil }
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = allowNetwork
        let manager = PHAssetResourceManager.default()
        let request = OSAllocatedUnfairLock<PHAssetResourceDataRequestID?>(initialState: nil)
        let box = HasherBox()
        // The deadline cancels a read that stalls (an iCloud download that
        // never finishes must not hold the regroup forever).
        let watchdog = Task {
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled, let id = request.withLock({ $0 }) { manager.cancelDataRequest(id) }
        }
        defer { watchdog.cancel() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                let id = manager.requestData(for: resource, options: options) { chunk in
                    box.update(chunk)
                } completionHandler: { error in
                    continuation.resume(returning: error == nil ? box.finalize() : nil)
                }
                request.withLock { $0 = id }
                if Task.isCancelled { manager.cancelDataRequest(id) }
            }
        } onCancel: {
            if let id = request.withLock({ $0 }) { manager.cancelDataRequest(id) }
        }
    }

    /// The hasher the data callback feeds; PhotoKit calls it serially.
    private final class HasherBox: @unchecked Sendable {
        private let lock = NSLock()
        private var hasher = ContentChecksum.Hasher()
        func update(_ chunk: Data) { lock.withLock { hasher.update(chunk) } }
        func finalize() -> String { lock.withLock { hasher.finalize() } }
    }
}
