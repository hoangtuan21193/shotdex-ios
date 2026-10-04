import Foundation
import os
import Photos
import UniformTypeIdentifiers

/// Content hashes for Photos assets (FS-19.02 §1b): the original is read as
/// a stream into memory, hashed, and dropped — no file is written, so the
/// pass never grows the disk. PhotoKit cannot read a range, so one read
/// gives both the fast and the full hash. An iCloud-only original is
/// downloaded once, under the index's network rule.
struct PhotosContentHashPass: Sendable {
    let store: ContentHashStore
    /// The original's bytes; injected so tests need no library.
    let readOriginal: @Sendable (_ assetId: String) async throws -> Data

    /// Hashes up to `limit` copies that have none; returns how many it saved.
    /// A copy whose original cannot be read is skipped and tried next time.
    @discardableResult
    func run(limit: Int = 200) async throws -> Int {
        var saved = 0
        for copy in try store.photosCopiesNeedingHash(limit: limit) {
            try Task.checkCancellation()
            guard let data = try? await readOriginal(copy.assetId) else { continue }
            let hash = try ContentHasher.hash(DataBytes(data: data), full: true)
            try store.save(hash, copyId: copy.copyId)
            saved += 1
        }
        return saved
    }
}

extension PhotosContentHashPass {
    enum ReadError: Error { case missingAsset, noResource }

    /// The asset's original through `PHAssetResourceManager` — the RAW of a
    /// RAW+JPEG pair, as the copy's identity (FS-19.01 §3).
    static func liveReader(allowsNetwork: @escaping @Sendable () -> Bool) -> @Sendable (String) async throws -> Data {
        { assetId in
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject
            else { throw ReadError.missingAsset }
            let resources = PHAssetResource.assetResources(for: asset)
            let raw = resources.first { $0.type == .alternatePhoto && UTType($0.uniformTypeIdentifier)?.conforms(to: .rawImage) == true }
            guard let resource = raw ?? resources.first(where: { $0.type == .photo }) ?? resources.first
            else { throw ReadError.noResource }
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = allowsNetwork()
            let buffer = OSAllocatedUnfairLock(initialState: Data())
            return try await withCheckedThrowingContinuation { continuation in
                PHAssetResourceManager.default().requestData(for: resource, options: options) { chunk in
                    buffer.withLock { $0.append(chunk) }
                } completionHandler: { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: buffer.withLock { $0 }) }
                }
            }
        }
    }
}
