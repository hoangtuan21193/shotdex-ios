import AVFoundation
import Foundation
import ImageIO
import Observation
import os
import Photos
import UIKit
import UniformTypeIdentifiers

/// Keeps photos and videos on this device so they open without a connection
/// (intent 2026-10-19-keep-offline). One item at a time from a queue, into a
/// scratch folder under `Kept/.incoming/`, then moved to `Kept/<id>/`.
///
/// Where the bytes come from follows the photo's open copy: a Photos asset
/// through PhotoKit (iCloud originals download), a server copy through its
/// connection, a folder copy from its file — a cloud placeholder downloaded
/// first. A viewing copy is drawn here: photos at 2732 px, videos at 1080p.
///
/// The pattern is Movik's movie downloader (`MovieDownloadRunner`): one
/// writer of state, a free-space gate with headroom, a launch sweep that
/// marks a vanished file missing and never deletes a row.
@MainActor
@Observable
final class KeepRunner {
    private let store: KeptStore
    let files: KeptFileStore
    private let openCopies: OpenCopyQueries
    private let folderRoots: FolderSourceRoots
    private let serverLoader: ServerOriginalLoader

    private var queue: [String] = []
    private var worker: Task<Void, Never>?
    private var hasStarted = false
    /// The item downloading now.
    private(set) var current: String?
    /// 0…1 for `current`, nil while the source reports none.
    private(set) var progress: Double?
    /// Bumped whenever a row changes, so screens reload.
    private(set) var revision = 0
    /// Pause Downloads: the queue stays, nothing starts.
    private(set) var isPaused = false

    init(store: KeptStore, files: KeptFileStore, openCopies: OpenCopyQueries,
         folderRoots: FolderSourceRoots, serverLoader: ServerOriginalLoader) {
        self.store = store
        self.files = files
        self.openCopies = openCopies
        self.folderRoots = folderRoots
        self.serverLoader = serverLoader
    }

    /// Once per launch: folders ready, the sweep, unfinished work queued
    /// again, kept albums topped up.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        try? files.prepare()
        let items = (try? store.items()) ?? []
        for id in files.sweep(items: items) {
            try? store.setState(id: id, .missing, error: nil)
        }
        for item in items where item.state == .queued || item.state == .downloading {
            try? store.setState(id: item.id, .queued)
            queue.append(item.id)
        }
        refreshAlbums()
        revision += 1
        runIfIdle()
    }

    /// The pending download count, the one being fetched included.
    var pendingCount: Int { queue.count + (current == nil ? 0 : 1) }

    // MARK: Keep

    /// Keeps these photos and videos. Ones already kept stay as they are.
    func keep(ids: [String], quality: KeepQuality, albumId: String? = nil) {
        let rows = ids.map { KeptItem(id: $0, isVideo: Self.isVideo(id: $0, openCopies: openCopies), quality: quality, albumId: albumId) }
        let added = (try? store.add(rows)) ?? []
        queue.append(contentsOf: added.map(\.id))
        revision += 1
        runIfIdle()
    }

    /// Keeps a whole album; with `keepsNewPhotos`, later additions too.
    func keepAlbum(id: String, title: String, quality: KeepQuality, keepsNewPhotos: Bool) {
        try? store.save(KeptAlbum(id: id, title: title, quality: quality, keepsNewPhotos: keepsNewPhotos))
        keep(ids: Self.members(ofAlbum: id), quality: quality, albumId: id)
    }

    /// Queues what was added to a kept album since it was last looked at.
    func refreshAlbums() {
        for album in (try? store.albums()) ?? [] where album.keepsNewPhotos {
            let kept = (try? store.keptIds()) ?? []
            let new = Self.members(ofAlbum: album.id).filter { !kept.contains($0) }
            if !new.isEmpty { keep(ids: new, quality: album.quality, albumId: album.id) }
        }
    }

    // MARK: Remove

    func remove(ids: [String]) {
        for id in ids { cancelIfCurrent(id); files.remove(id: id) }
        queue.removeAll { ids.contains($0) }
        try? store.remove(ids: ids)
        revision += 1
    }

    func removeAlbum(id: String) {
        let ids = (try? store.removeAlbum(id: id)) ?? []
        for id in ids { cancelIfCurrent(id); files.remove(id: id) }
        queue.removeAll { ids.contains($0) }
        revision += 1
    }

    func removeAll() {
        let ids = ((try? store.items()) ?? []).map(\.id)
        for album in (try? store.albums()) ?? [] { _ = try? store.removeAlbum(id: album.id) }
        remove(ids: ids)
    }

    // MARK: Control

    func retry(id: String) {
        guard !queue.contains(id), current != id else { return }
        try? store.setState(id: id, .queued)
        queue.append(id)
        revision += 1
        runIfIdle()
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        if paused {
            worker?.cancel()
        } else {
            runIfIdle()
        }
        revision += 1
    }

    private func cancelIfCurrent(_ id: String) {
        if current == id { worker?.cancel() }
    }

    // MARK: Worker

    private func runIfIdle() {
        guard worker == nil, !isPaused, !queue.isEmpty else { return }
        worker = Task { [weak self] in
            while let self, !Task.isCancelled, !self.isPaused, !self.queue.isEmpty {
                let id = self.queue.removeFirst()
                await self.run(id)
            }
            self?.finishWorker()
        }
    }

    private func finishWorker() {
        worker = nil
        current = nil
        progress = nil
        revision += 1
        // A pause or a removal cancelled the worker; anything left waits for
        // the next call.
        if !isPaused { runIfIdle() }
    }

    private func run(_ id: String) async {
        guard let item = try? store.item(id: id), item.state != .onDevice else { return }
        current = id
        progress = 0
        try? store.setState(id: id, .downloading)
        revision += 1
        let environment = Fetch(openCopies: openCopies, folderRoots: folderRoots, serverLoader: serverLoader)
        do {
            let work = try files.makeWorkFolder()
            defer { try? FileManager.default.removeItem(at: work) }
            let fetched = try await environment.fetch(item, into: work) { [weak self] value in
                Task { @MainActor in self?.progress = value }
            }
            try Task.checkCancellation()
            // Removed while it downloaded: nothing to finish.
            guard (try? store.item(id: id)) != nil else { return }
            let placed = try files.finish(fetched.url, id: id, as: fetched.name)
            try? store.finish(id: id, fileName: placed.name, byteCount: placed.bytes)
        } catch is CancellationError {
            // Paused or removed. A paused item waits at the front.
            if (try? store.item(id: id)) != nil {
                try? store.setState(id: id, .queued)
                queue.insert(id, at: 0)
            }
        } catch {
            if (try? store.item(id: id)) != nil {
                try? store.setState(id: id, .failed, error: Self.message(for: error))
            }
        }
        current = nil
        progress = nil
        revision += 1
    }

    static func message(for error: Error) -> String {
        switch error {
        case KeepFetchError.notEnoughSpace:
            String(localized: "Not enough space on this \(KeepDevice.name).", comment: "Keep on This iPhone: a download stopped for lack of space")
        case KeepFetchError.unavailable:
            String(localized: "This photo is not available anymore.", comment: "Keep on This iPhone: the photo's source no longer has it")
        case ServerOriginalLoader.Failure.notEnoughSpace:
            String(localized: "Not enough space on this \(KeepDevice.name).", comment: "Keep on This iPhone: a download stopped for lack of space")
        default:
            String(localized: "Could not download. Check the connection and try again.", comment: "Keep on This iPhone: a download failed")
        }
    }

    // MARK: Lookups

    /// The members of a PhotoKit album, newest first.
    static func members(ofAlbum id: String) -> [String] {
        guard let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
        else { return [] }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var ids: [String] = []
        PHAsset.fetchAssets(in: collection, options: options).enumerateObjects { asset, _, _ in
            ids.append(asset.localIdentifier)
        }
        return ids
    }

    static func isVideo(id: String, openCopies: OpenCopyQueries) -> Bool {
        if let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject {
            return asset.mediaType == .video
        }
        guard let path = (try? openCopies.openCopy(photoId: id))?.relativePath,
              let type = UTType(filenameExtension: (path as NSString).pathExtension)
        else { return false }
        return type.conforms(to: .movie)
    }
}

enum KeepFetchError: Error {
    case unavailable
    case notEnoughSpace
}

/// The fetch itself, off the main actor: where the bytes come from and how a
/// viewing copy is drawn.
private struct Fetch: Sendable {
    let openCopies: OpenCopyQueries
    let folderRoots: FolderSourceRoots
    let serverLoader: ServerOriginalLoader

    struct Result { let url: URL; let name: String }

    func fetch(_ item: KeptItem, into work: URL, progress: @escaping @Sendable (Double?) -> Void) async throws -> Result {
        if let short = DeviceSpaceCheck.shortfall(for: 0, free: KeptFileStore.freeSpace()), short > 0 {
            throw KeepFetchError.notEnoughSpace
        }
        let copy = try? openCopies.openCopy(photoId: item.id)
        switch copy?.kind {
        case "server":
            guard let copy else { throw KeepFetchError.unavailable }
            let original = try await serverLoader.load(copyId: copy.copyId) { _ in progress(nil) }
            defer { original.discard() }
            return try await finish(from: original.url, item: item, into: work, progress: progress)
        case "file":
            guard let copy, let path = copy.relativePath,
                  let url = folderRoots.fileURL(sourceId: copy.sourceId, relativePath: path)
            else { throw KeepFetchError.unavailable }
            if !UbiquitousFileDownloader.isDownloaded(url) {
                try await UbiquitousFileDownloader().download(url) { progress($0) }
            }
            return try await finish(from: url, item: item, into: work, progress: progress)
        default:
            let assetId = copy?.photoKitId ?? item.id
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject
            else { throw KeepFetchError.unavailable }
            return try await fetchPhotoKit(asset, item: item, into: work, progress: progress)
        }
    }

    // MARK: PhotoKit

    private func fetchPhotoKit(_ asset: PHAsset, item: KeptItem, into work: URL,
                               progress: @escaping @Sendable (Double?) -> Void) async throws -> Result {
        let base = (OriginalItem(asset: asset).filename as NSString).deletingPathExtension
        switch (item.quality, asset.mediaType == .video) {
        case (.original, _):
            let original = OriginalItem(asset: asset)
            let url = work.appending(path: KeptFileStore.safeName(original.filename))
            try await PhotoKitOriginalFetcher().fetch(original, to: url) { progress($0) }
            return Result(url: url, name: original.filename)
        case (.viewingCopy, false):
            let image = try await Self.requestViewingImage(asset, progress: progress)
            let url = work.appending(path: "\(base).heic")
            guard let data = image.heicData() ?? image.jpegData(compressionQuality: 0.9) else { throw KeepFetchError.unavailable }
            try data.write(to: url)
            return Result(url: url, name: url.lastPathComponent)
        case (.viewingCopy, true):
            let url = work.appending(path: "\(base).mp4")
            let session = try await Self.requestExportSession(asset, progress: progress)
            try await Self.export(session, to: url)
            return Result(url: url, name: url.lastPathComponent)
        }
    }

    private static func requestViewingImage(_ asset: PHAsset, progress: @escaping @Sendable (Double?) -> Void) async throws -> UIImage {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.progressHandler = { value, _, _, _ in progress(value) }
        let side = CGFloat(KeepQuality.viewingLongSide)
        let target = CGSize(width: side, height: side)
        let manager = PHImageManager.default()
        let request = OSAllocatedUnfairLock<PHImageRequestID?>(initialState: nil)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, Error>) in
                let id = manager.requestImage(for: asset, targetSize: target, contentMode: .aspectFit, options: options) { image, info in
                    if (info?[PHImageCancelledKey] as? Bool) == true {
                        continuation.resume(throwing: CancellationError())
                    } else if let image {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: (info?[PHImageErrorKey] as? Error) ?? KeepFetchError.unavailable)
                    }
                }
                request.withLock { $0 = id }
            }
        } onCancel: {
            if let id = request.withLock({ $0 }) { manager.cancelImageRequest(id) }
        }
    }

    private static func requestExportSession(_ asset: PHAsset, progress: @escaping @Sendable (Double?) -> Void) async throws -> AVAssetExportSession {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        options.progressHandler = { value, _, _, _ in progress(value) }
        let manager = PHImageManager.default()
        let request = OSAllocatedUnfairLock<PHImageRequestID?>(initialState: nil)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AVAssetExportSession, Error>) in
                let id = manager.requestExportSession(forVideo: asset, options: options, exportPreset: AVAssetExportPreset1920x1080) { session, info in
                    if let session {
                        nonisolated(unsafe) let session = session
                        continuation.resume(returning: session)
                    } else if (info?[PHImageCancelledKey] as? Bool) == true {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(throwing: (info?[PHImageErrorKey] as? Error) ?? KeepFetchError.unavailable)
                    }
                }
                request.withLock { $0 = id }
            }
        } onCancel: {
            if let id = request.withLock({ $0 }) { manager.cancelImageRequest(id) }
        }
    }

    private static func export(_ session: AVAssetExportSession, to url: URL) async throws {
        if #available(iOS 18.0, *) {
            try await session.export(to: url, as: .mp4)
        } else {
            session.outputURL = url
            session.outputFileType = .mp4
            await session.export()
            if let error = session.error { throw error }
            guard session.status == .completed else { throw CancellationError() }
        }
    }

    // MARK: Files from a server or a folder

    /// An original that is already on the device (a server copy in a scratch
    /// folder, a folder file): copied as it is, or drawn as a viewing copy.
    private func finish(from source: URL, item: KeptItem, into work: URL,
                        progress: @escaping @Sendable (Double?) -> Void) async throws -> Result {
        let name = source.lastPathComponent
        let base = (name as NSString).deletingPathExtension
        switch (item.quality, item.isVideo) {
        case (.original, _):
            let url = work.appending(path: KeptFileStore.safeName(name))
            try FileManager.default.copyItem(at: source, to: url)
            return Result(url: url, name: name)
        case (.viewingCopy, false):
            let url = work.appending(path: "\(base).heic")
            try Self.drawViewingCopy(of: source, to: url)
            return Result(url: url, name: url.lastPathComponent)
        case (.viewingCopy, true):
            let url = work.appending(path: "\(base).mp4")
            guard let session = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPreset1920x1080) else {
                throw KeepFetchError.unavailable
            }
            try await Self.export(session, to: url)
            return Result(url: url, name: url.lastPathComponent)
        }
    }

    /// ImageIO at 2732 px — a RAW's embedded preview when it is big enough,
    /// never a full decode — written as HEIC.
    private static func drawViewingCopy(of source: URL, to url: URL) throws {
        guard let input = CGImageSourceCreateWithURL(source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(input, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: KeepQuality.viewingLongSide,
              ] as CFDictionary),
              let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil)
        else { throw KeepFetchError.unavailable }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw KeepFetchError.unavailable }
    }
}
