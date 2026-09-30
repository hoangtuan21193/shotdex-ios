import Foundation

/// Export EXIF (CSV) of server photos (FS-17.06 §4): the metadata sits in the
/// head of the file, so only that is read — never the whole RAW.
enum ServerExifExport {
    /// How much of each file is read. EXIF, TIFF and the maker notes of every
    /// camera format ImageIO reads sit well inside it.
    static let headBytes = 1 << 20

    /// One metadata row per photo, in the order given; a photo whose head
    /// ImageIO cannot read still gets its row (file name, size), as a
    /// photo without EXIF does in the library.
    static func rows(
        for photos: [ServerPhoto],
        in folder: String,
        access: any RemoteFileAccess,
        composer: MetadataComposer,
        scratch: URL
    ) async throws -> [PhotoMetadata] {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        var rows: [PhotoMetadata] = []
        for photo in photos {
            try Task.checkCancellation()
            let file = photo.raw ?? photo.primary
            let path = ServerUploadPath.join(folder, file.name)
            let head = try await access.perform { client in
                try await client.readRange(path, offset: 0, length: headBytes)
            }
            let url = scratch.appendingPathComponent(file.name)
            try head.write(to: url)
            let asset = AssetInfo(
                assetId: ServerUploadPath.join(folder, photo.id),
                creationDate: EmbeddedPreview.captureDate(from: head),
                modificationDate: photo.modified,
                mediaType: 1,
                fileSize: Int(photo.totalBytes),
                isFavorite: false,
                originalFilename: file.name
            )
            switch ExifReader.readExif(fromImageAt: url) {
            case .success(let exif):
                rows.append(composer.compose(asset: asset, exif: exif, exifStatus: .indexed))
            default:
                rows.append(composer.compose(asset: asset, exif: RawExif(), exifStatus: .noExif))
            }
            try? FileManager.default.removeItem(at: url)
        }
        return rows
    }
}
