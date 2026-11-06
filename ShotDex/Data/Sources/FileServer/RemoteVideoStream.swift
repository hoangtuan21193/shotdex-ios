import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// FS-19.08 §6d: a video on a server played where it lies. AVFoundation asks
/// for the byte ranges it needs and each comes from the server as range
/// reads, so a 2.6 GB clip starts in seconds and takes no disk. The scan
/// already proved the bytes; nothing here checks them again.
///
/// AVFoundation holds its delegate weakly: whoever plays `asset` keeps the
/// stream alive, and calls `cancel()` when it is done.
final class RemoteVideoStream: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    static let scheme = "shotdex-remote"
    /// One read each: about a second of 4K, short enough that a seek waits
    /// for at most one of them on a shared connection.
    static let chunkBytes = 1024 * 1024
    /// At most this much per request: AVFoundation often asks for "to the
    /// end", and a request answered in part is asked again from where it
    /// stopped — so a 2.6 GB clip is never pulled whole behind the picture.
    static let requestBytes: Int64 = 8 * 1024 * 1024

    let asset: AVURLAsset
    private let client: any RemoteFileClient
    private let path: String
    private let size: Int64
    private let contentType: String
    private let queue = DispatchQueue(label: "com.hoangtuan.shotdex.remote-video")
    private let lock = NSLock()
    /// The read behind each request AVFoundation has not cancelled.
    private var reads: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var isStopped = false
    /// Requests AVFoundation cancelled; read and written on `queue` only,
    /// so nothing answers one after it went.
    private var cancelled: Set<ObjectIdentifier> = []

    init(client: any RemoteFileClient, path: String, size: Int64) {
        self.client = client
        self.path = path
        self.size = size
        let fileExtension = (path as NSString).pathExtension
        contentType = (UTType(filenameExtension: fileExtension) ?? .movie).identifier
        // Not a URL AVFoundation can open itself, so every byte asks the delegate.
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "video"
        components.path = "/" + UUID().uuidString + (fileExtension.isEmpty ? "" : "." + fileExtension)
        asset = AVURLAsset(url: components.url!)
        super.init()
        asset.resourceLoader.setDelegate(self, queue: queue)
    }

    /// Stops every read; the asset plays nothing more.
    func cancel() {
        let running = lock.withLock {
            isStopped = true
            defer { reads = [:] }
            return Array(reads.values)
        }
        running.forEach { $0.cancel() }
    }

    deinit { cancel() }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        if let info = loadingRequest.contentInformationRequest {
            info.contentType = contentType
            info.contentLength = size
            info.isByteRangeAccessSupported = true
            info.isEntireLengthAvailableOnDemand = true
        }
        guard let dataRequest = loadingRequest.dataRequest, !lock.withLock({ isStopped }) else {
            loadingRequest.finishLoading()
            return true
        }
        let start = dataRequest.currentOffset
        let asked = dataRequest.requestsAllDataToEndOfResource
            ? size : min(size, dataRequest.requestedOffset + Int64(dataRequest.requestedLength))
        let end = min(asked, start + Self.requestBytes)
        let request = Request(loading: loadingRequest)
        let key = ObjectIdentifier(loadingRequest)
        let task = Task { [client, path, queue, weak self] in
            var offset = start
            do {
                while offset < end {
                    try Task.checkCancellation()
                    let chunk = try await client.readRange(path, offset: offset, length: Int(min(Int64(Self.chunkBytes), end - offset)))
                    // The server holds less than the scan listed: the file changed.
                    guard !chunk.isEmpty else { throw RemoteFileError.other("The video ends before its listed size.") }
                    try Task.checkCancellation()
                    // On the delegate queue, in order, never to a request
                    // AVFoundation already cancelled there.
                    queue.async { [weak self] in
                        guard self?.cancelled.contains(key) == false else { return }
                        request.loading.dataRequest?.respond(with: chunk)
                    }
                    offset += Int64(chunk.count)
                }
                queue.async { [weak self] in
                    guard self?.cancelled.contains(key) == false else { return }
                    request.loading.finishLoading()
                }
            } catch is CancellationError {
                // AVFoundation cancelled the request, or the stream was stopped.
            } catch {
                queue.async { [weak self] in
                    guard self?.cancelled.contains(key) == false else { return }
                    request.loading.finishLoading(with: error)
                }
            }
            self?.finished(key)
        }
        lock.withLock { reads[key] = task }
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        // On `queue`, as every answer is.
        cancelled.insert(ObjectIdentifier(loadingRequest))
        let task = lock.withLock { reads.removeValue(forKey: ObjectIdentifier(loadingRequest)) }
        task?.cancel()
    }

    private func finished(_ key: ObjectIdentifier) {
        _ = lock.withLock { reads.removeValue(forKey: key) }
    }

    /// AVFoundation's request, answered only on the delegate queue.
    private struct Request: @unchecked Sendable {
        let loading: AVAssetResourceLoadingRequest
    }
}
