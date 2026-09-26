import Foundation

/// What the grid gets for one server photo (FS-17.01 §3).
struct RemoteThumbnailResult: @unchecked Sendable {
    /// Nil when nothing gave an image — the tile shows the format icon.
    let thumbnail: EmbeddedPreview.Thumbnail?
    /// EXIF `DateTimeOriginal`, when the head carried one.
    let captureDate: Date?
}

/// Reads as little of a file as it can to draw its tile: the head of the
/// file, more of it only when the preview was blurry, the whole file only
/// for small non-RAW images (FS-17.01 §3).
struct RemoteThumbnailer: Sendable {
    let client: any RemoteFileClient
    /// Non-RAW files at or under this are downloaded whole when their head
    /// held no usable preview.
    var wholeFileLimit: Int64 = 25 * 1024 * 1024
    var workDirectory: URL = FileManager.default.temporaryDirectory

    func thumbnail(for photo: ServerPhoto, in folder: String) async throws -> RemoteThumbnailResult {
        var best: EmbeddedPreview.Thumbnail?
        var date: Date?
        // A pair tries its RAW's head first: a few hundred KB instead of the
        // whole JPEG twin.
        let order = photo.raw.map { raw in [raw] + photo.files.filter { $0 != raw } } ?? photo.files
        for file in order {
            let path = ServerUploadPath.join(folder, file.name)
            let found = try await preview(of: file, at: path)
            date = date ?? found.captureDate
            if let thumbnail = found.thumbnail, thumbnail.sourceLongSide > (best?.sourceLongSide ?? 0) {
                best = thumbnail
            }
            if let best, best.sourceLongSide >= EmbeddedPreview.sharpEnough { break }
        }
        return RemoteThumbnailResult(thumbnail: best, captureDate: date)
    }

    /// Only the capture date — Date Taken sorting reads every file's head,
    /// not just the visible ones, so it stops at the first 64 KB.
    func captureDate(of file: RemoteEntry, at path: String) async throws -> Date? {
        let head = try await client.readRange(path, offset: 0, length: 64 * 1024)
        return EmbeddedPreview.captureDate(from: head)
    }

    private func preview(of file: RemoteEntry, at path: String) async throws -> RemoteThumbnailResult {
        let isRAW = ServerFolderListing.isRAW(file.name)
        var head = try await client.readRange(path, offset: 0, length: EmbeddedPreview.firstRead)
        let date = EmbeddedPreview.captureDate(from: head)
        var best = EmbeddedPreview.thumbnail(from: head)
        func sharp() -> Bool { (best?.sourceLongSide ?? 0) >= EmbeddedPreview.sharpEnough }

        if !sharp(), let raf = EmbeddedPreview.rafPreviewRange(header: head), raf.length <= EmbeddedPreview.rafPreviewLimit {
            let jpeg = try await client.readRange(path, offset: raf.offset, length: raf.length)
            if let found = EmbeddedPreview.thumbnail(from: jpeg), found.sourceLongSide > (best?.sourceLongSide ?? 0) {
                best = found
            }
        }
        if !sharp(), isRAW, file.size > Int64(EmbeddedPreview.firstRead) {
            head.append(try await client.readRange(
                path, offset: Int64(head.count), length: EmbeddedPreview.secondRead - head.count
            ))
            if let found = EmbeddedPreview.thumbnail(from: head), found.sourceLongSide > (best?.sourceLongSide ?? 0) {
                best = found
            }
        }
        if !sharp(), !isRAW, file.size <= wholeFileLimit {
            let url = workDirectory.appendingPathComponent("ShotDexThumb-\(UUID().uuidString)-\(file.name)")
            defer { try? FileManager.default.removeItem(at: url) }
            try await client.download(path, to: url, progress: { _ in })
            if let found = EmbeddedPreview.thumbnail(ofFileAt: url), found.sourceLongSide > (best?.sourceLongSide ?? 0) {
                best = found
            }
        }
        return RemoteThumbnailResult(thumbnail: best, captureDate: date)
    }
}
