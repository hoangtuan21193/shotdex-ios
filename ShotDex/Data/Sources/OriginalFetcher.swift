import Foundation
import ImageIO
import Photos
import os

/// One photo whose original something needs (FS-02.06): what the fetcher and
/// the preparation have to know, and nothing PhotoKit-shaped, so both run in
/// a unit test without a library.
struct OriginalItem: Sendable, Hashable, Identifiable {
    /// The asset's local identifier.
    let id: String
    let filename: String
    /// The photo's size as PhotoKit reports it — already the shown size.
    let photo: PixelSize
    /// Bytes of the original, from the index; `nil` when the row has none.
    var byteCount: Int64?

    init(id: String, filename: String, photo: PixelSize, byteCount: Int64? = nil) {
        self.id = id
        self.filename = filename
        self.photo = photo
        self.byteCount = byteCount
    }
}

extension OriginalItem {
    init(asset: PHAsset, byteCount: Int64? = nil) {
        let resources = PHAssetResource.assetResources(for: asset)
        let name = resources.first { $0.type == .photo }?.originalFilename
            ?? resources.first?.originalFilename ?? "Photo"
        self.init(
            id: asset.localIdentifier,
            filename: name,
            photo: PixelSize(width: asset.pixelWidth, height: asset.pixelHeight),
            byteCount: byteCount
        )
    }
}

enum OriginalFetchError: Error, Equatable {
    case missing
    /// What came back is not the whole photo.
    case incomplete
    /// The disk filled up while the original was being written: a space
    /// problem, never to be called an iCloud one (§5).
    case outOfSpace
}

/// Where the app asks about and downloads originals. `PhotoKitOriginalFetcher`
/// in the app; `FakeOriginalFetcher` in the tests and behind the DEBUG launch
/// argument `-ShotDexFakeICloud`, because a simulator has no iCloud library.
protocol OriginalFetching: Sendable {
    /// Asks once, with the network off, whether the original is on this device.
    func probe(_ item: OriginalItem) async -> OriginalAvailability
    /// The original's size in bytes, for a photo the index has no size for.
    func byteCount(of item: OriginalItem) async -> Int64?
    /// Writes the photo's current version — the edited one if it was edited —
    /// to `url`, downloading it from iCloud when it is not here. `progress`
    /// gets 0…1 on any thread. Cancelling the task stops the download.
    func fetch(_ item: OriginalItem, to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws
    /// Paths that download through a PhotoKit request of their own (the
    /// viewer's zoom, the editor's input) get their progress from that
    /// request: for PhotoKit this returns at once. A scripted fetcher plays
    /// its download here, so the simulator can show those states.
    func scriptedTransfer(for id: String, progress: @escaping @Sendable (Double) -> Void) async throws
}

extension OriginalFetching {
    func scriptedTransfer(for id: String, progress: @escaping @Sendable (Double) -> Void) async throws {}
}

/// Asks PhotoKit. The probe and the download both read the resource's bytes
/// with `PHAssetResourceManager`, which never hands over an Optimize Storage
/// preview in place of the file — but the size is still checked (§3).
struct PhotoKitOriginalFetcher: OriginalFetching {
    private static func resource(for id: String) -> (PHAsset, PHAssetResource)? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let type = ShareSource.sharedResourceType(among: resources.map(\.type)),
              let resource = resources.first(where: { $0.type == type })
        else { return nil }
        return (asset, resource)
    }

    func probe(_ item: OriginalItem) async -> OriginalAvailability {
        guard let (_, resource) = Self.resource(for: item.id) else { return .unknown }
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false
        let header = HeaderProbe()
        let manager = PHAssetResourceManager.default()
        return await withCheckedContinuation { continuation in
            header.continuation = continuation
            let request = manager.requestData(for: resource, options: options) { chunk in
                // Stops as soon as the header gives a size: the probe reads
                // a few hundred kilobytes, never the whole 24 MB.
                if let measured = header.append(chunk) {
                    header.resume(OriginalAvailability.judgeResource(measured, photo: item.photo))
                    header.cancel(manager)
                }
            } completionHandler: { error in
                if error == nil, let measured = header.measureAll() {
                    header.resume(OriginalAvailability.judgeResource(measured, photo: item.photo))
                } else if let error = error as NSError?, error.domain == PHPhotosErrorDomain,
                          [PHPhotosError.Code.networkAccessRequired.rawValue, PHPhotosError.Code.networkError.rawValue]
                              .contains(error.code) {
                    header.resume(.inCloud)
                } else {
                    header.resume(error == nil ? .unknown : .inCloud)
                }
            }
            header.setRequest(request)
        }
    }

    func byteCount(of item: OriginalItem) async -> Int64? {
        guard let (_, resource) = Self.resource(for: item.id) else { return nil }
        return (resource.value(forKey: "fileSize") as? NSNumber)?.int64Value
    }

    func fetch(_ item: OriginalItem, to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let (_, resource) = Self.resource(for: item.id) else { throw OriginalFetchError.missing }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        let writer = StreamWriter(handle: handle)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        options.progressHandler = { value in progress(value) }
        let manager = PHAssetResourceManager.default()
        let request = OSAllocatedUnfairLock<PHAssetResourceDataRequestID?>(initialState: nil)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let id = manager.requestData(for: resource, options: options) { chunk in
                    writer.write(chunk)
                } completionHandler: { error in
                    let writeError = writer.close()
                    if let writeError { continuation.resume(throwing: writeError) }
                    else if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
                request.withLock { $0 = id }
                if Task.isCancelled { manager.cancelDataRequest(id) }
            }
        } onCancel: {
            if let id = request.withLock({ $0 }) { manager.cancelDataRequest(id) }
        }
        try Task.checkCancellation()
        // A resource's bytes are the file itself, never a preview; the check
        // is against a truncated write. 90%, not exact: a RAW's header can
        // count its sensor margins, which PhotoKit's size leaves out.
        guard let measured = OriginalCompleteness.measure(url),
              OriginalCompleteness.isSufficient(received: measured.size.oriented(measured.orientation),
                                                requestedLongEdge: item.photo.longEdge, photo: item.photo)
        else { throw OriginalFetchError.incomplete }
    }
}

extension OriginalAvailability {
    /// A resource read offline: its header size against the photo's.
    static func judgeResource(_ measured: (size: PixelSize, orientation: CGImagePropertyOrientation), photo: PixelSize) -> Self {
        OriginalCompleteness.isSufficient(received: measured.size.oriented(measured.orientation),
                                          requestedLongEdge: photo.longEdge, photo: photo) ? .local : .inCloud
    }
}

/// Collects the first bytes of a resource until its header gives a size.
private final class HeaderProbe: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var data = Data()
    private var request: PHAssetResourceDataRequestID?
    private var cancelsOnSet = false
    private var hasResumed = false
    var continuation: CheckedContinuation<OriginalAvailability, Never>?

    /// The size once the header is in; nil while it is not.
    func append(_ chunk: Data) -> (size: PixelSize, orientation: CGImagePropertyOrientation)? {
        lock.withLock {
            guard !hasResumed else { return nil }
            data.append(chunk)
            return OriginalCompleteness.measure(data)
        }
    }

    func measureAll() -> (size: PixelSize, orientation: CGImagePropertyOrientation)? {
        lock.withLock { OriginalCompleteness.measure(data) }
    }

    func resume(_ value: OriginalAvailability) {
        let continuation: CheckedContinuation<OriginalAvailability, Never>? = lock.withLock {
            guard !hasResumed else { return nil }
            hasResumed = true
            data = Data()
            return self.continuation
        }
        continuation?.resume(returning: value)
    }

    func setRequest(_ id: PHAssetResourceDataRequestID) {
        let cancelNow = lock.withLock {
            request = id
            return cancelsOnSet
        }
        if cancelNow { PHAssetResourceManager.default().cancelDataRequest(id) }
    }

    func cancel(_ manager: PHAssetResourceManager) {
        let id: PHAssetResourceDataRequestID? = lock.withLock {
            if request == nil { cancelsOnSet = true }
            return request
        }
        if let id { manager.cancelDataRequest(id) }
    }
}

/// Writes a download's chunks to disk as they arrive, so a 24 MB original
/// never sits in memory whole (NF-02).
private final class StreamWriter: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private let handle: FileHandle
    private var error: Error?

    init(handle: FileHandle) { self.handle = handle }

    func write(_ chunk: Data) {
        lock.withLock {
            guard error == nil else { return }
            do { try handle.write(contentsOf: chunk) } catch {
                self.error = Self.isOutOfSpace(error) ? OriginalFetchError.outOfSpace : error
            }
        }
    }

    func close() -> Error? {
        lock.withLock {
            try? handle.close()
            return error
        }
    }

    static func isOutOfSpace(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError { return true }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOSPC) { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error { return isOutOfSpace(underlying) }
        return false
    }
}
