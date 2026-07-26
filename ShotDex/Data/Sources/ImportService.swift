import AVFoundation
import Foundation
import ImageIO
import Photos
import UIKit

/// Errors surfaced while scanning an external volume for import.
enum ImportScanError: Error {
    /// The picked folder could not be enumerated (access lost, not a folder).
    case folderNotReadable
}

/// Reads image files off a user-picked external volume (SD card / USB / folder)
/// and imports the chosen ones into the photo library. All heavy work
/// (enumeration, thumbnailing, EXIF) is `nonisolated` so it runs off the main
/// actor; only the composer build and the PhotoKit write hop back to the main
/// actor. Holds no UI state — `ImportModel` owns that.
@MainActor
final class ImportService {
    private let photoLibrary: PhotoLibraryService
    private let metadataStore: MetadataStore
    private let sensorDatabase: SensorDatabaseLoader

    init(photoLibrary: PhotoLibraryService, metadataStore: MetadataStore, sensorDatabase: SensorDatabaseLoader = SensorDatabaseLoader()) {
        self.photoLibrary = photoLibrary
        self.metadataStore = metadataStore
        self.sensorDatabase = sensorDatabase
    }

    /// Builds the same normalizer/sensor composer the index pipeline uses, so
    /// an import candidate resolves to the identical camera/lens/sensor values
    /// it will carry once indexed. Cheap; called once per scan.
    func makeComposer() -> MetadataComposer {
        let records = (try? sensorDatabase.loadRecords()) ?? []
        let mappings = (try? metadataStore.customMappings()) ?? []
        return MetadataComposer(sensorLookup: SensorLookup(records: records, customMappings: mappings))
    }

    /// Enumerates every recognized image file under `folder` (recursively — a
    /// card's DCIM holds per-shoot subfolders), classifying by extension and
    /// reading cheap file attributes. Each candidate gets a filename-only
    /// placeholder `PhotoMetadata` so type/name/date filters work before the
    /// EXIF pass runs. Videos and unrecognized files are skipped. Newest first.
    nonisolated func scanFolder(at folder: URL, using composer: MetadataComposer) throws -> [ImportCandidate] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw ImportScanError.folderNotReadable
        }

        var candidates: [ImportCandidate] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            guard let classified = ImportCandidate.classify(url: url) else { continue }
            let date = values?.creationDate ?? values?.contentModificationDate
            candidates.append(ImportCandidate(
                url: url,
                filename: url.lastPathComponent,
                kind: classified.kind,
                fileType: classified.fileType,
                fileSize: values?.fileSize,
                creationDate: date,
                metadata: placeholderMetadata(
                    id: url.path,
                    filename: url.lastPathComponent,
                    kind: classified.kind,
                    fileSize: values?.fileSize,
                    date: date,
                    composer: composer
                )
            ))
        }
        return candidates.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
    }

    /// Composes the full `PhotoMetadata` — the background upgrade over the
    /// placeholder. Images have their EXIF read (camera/lens/sensor/exposure);
    /// videos are composed EXIF-free (`noExif`), exactly like `IndexPipeline`.
    nonisolated func fullMetadata(for candidate: ImportCandidate, using composer: MetadataComposer) -> PhotoMetadata {
        switch candidate.kind {
        case .video:
            return composer.compose(
                asset: assetInfo(for: candidate, exif: .empty),
                exif: .empty,
                exifStatus: .noExif
            )
        case .image:
            let exif: RawExif = {
                if case .success(let raw) = ExifReader.readExif(fromImageAt: candidate.url) { return raw }
                return .empty
            }()
            return composer.compose(
                asset: assetInfo(for: candidate, exif: exif),
                exif: exif,
                exifStatus: .indexed
            )
        }
    }

    /// A grid thumbnail for a candidate — ImageIO for stills, an
    /// `AVAssetImageGenerator` poster frame for videos.
    nonisolated func thumbnail(for candidate: ImportCandidate, maxPixel: CGFloat) -> UIImage? {
        switch candidate.kind {
        case .image: return imageThumbnail(for: candidate.url, maxPixel: maxPixel)
        case .video: return videoThumbnail(for: candidate.url, maxPixel: maxPixel)
        }
    }

    /// Straight ImageIO thumbnail (no full decode). RAW files may yield nil on
    /// devices without a matching codec — the caller shows a placeholder.
    private nonisolated func imageThumbnail(for url: URL, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// First-frame poster for a video via AVFoundation.
    private nonisolated func videoThumbnail(for url: URL, maxPixel: CGFloat) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Copies one file (photo or video) into the photo library, returning the
    /// new asset id.
    func importAsset(_ candidate: ImportCandidate) async throws -> String {
        try await photoLibrary.importFile(at: candidate.url, isVideo: candidate.kind == .video)
    }

    // MARK: Helpers

    private nonisolated func mediaTypeRawValue(_ kind: ImportMediaKind) -> Int {
        (kind == .video ? PHAssetMediaType.video : PHAssetMediaType.image).rawValue
    }

    private nonisolated func assetInfo(for candidate: ImportCandidate, exif: RawExif) -> AssetInfo {
        AssetInfo(
            assetId: candidate.id,
            creationDate: candidate.creationDate,
            modificationDate: candidate.creationDate,
            mediaType: mediaTypeRawValue(candidate.kind),
            width: nil,
            height: nil,
            fileSize: candidate.fileSize,
            latitude: nil,
            longitude: nil,
            isFavorite: false,
            originalFilename: candidate.filename
        )
    }

    /// Placeholder row with only PHAsset-free facts populated (no EXIF read).
    private nonisolated func placeholderMetadata(
        id: String,
        filename: String,
        kind: ImportMediaKind,
        fileSize: Int?,
        date: Date?,
        composer: MetadataComposer
    ) -> PhotoMetadata {
        composer.compose(
            asset: AssetInfo(
                assetId: id,
                creationDate: date,
                modificationDate: date,
                mediaType: mediaTypeRawValue(kind),
                width: nil,
                height: nil,
                fileSize: fileSize,
                latitude: nil,
                longitude: nil,
                isFavorite: false,
                originalFilename: filename
            ),
            exif: .empty,
            exifStatus: .pendingRead
        )
    }
}
