import Foundation
import Photos

/// Reads what Compare's *What differs* sets side by side (FS-06.06 §14.7):
/// the index row, place and keywords in one database read, the user's
/// albums from PhotoKit off the main actor, and the rating the app shows.
/// Nothing touches the network.
@MainActor
struct PhotoFactsLoader {
    let database: AppDatabase
    let marks: PhotoMarks

    func load(ids: [String]) async -> [String: PhotoFacts] {
        guard !ids.isEmpty else { return [:] }
        let infos = (try? await PhotoInfoQueries(database: database).infos(photoIds: ids)) ?? [:]
        let albums = await Task.detached(priority: .userInitiated) { Self.albumTitles(ids) }.value
        let ratings = await marks.ratings(for: ids)
        var facts: [String: PhotoFacts] = [:]
        for id in ids {
            guard let info = infos[id], let metadata = info.metadata else { continue }
            facts[id] = Self.facts(metadata: metadata, place: info.place, keywords: info.keywords,
                                   albums: albums[id] ?? [], rating: ratings[id] ?? 0)
        }
        return facts
    }

    /// One photo's facts from what was read — pure, so it is tested.
    nonisolated static func facts(
        metadata: PhotoMetadata,
        place: ResolvedPlace?,
        keywords: [String],
        albums: [String],
        rating: Int
    ) -> PhotoFacts {
        PhotoFacts(
            date: metadata.creationDate.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            fileSize: metadata.fileSize,
            width: metadata.width,
            height: metadata.height,
            format: format(of: metadata.originalFilename),
            camera: metadata.normalizedCameraModel ?? metadata.cameraModel,
            lens: metadata.normalizedLensModel ?? metadata.lensModel,
            aperture: metadata.aperture,
            shutterSeconds: metadata.shutterSpeedSeconds,
            iso: metadata.iso,
            focalLength: metadata.focalLength,
            hasLocation: metadata.latitude != nil && metadata.longitude != nil,
            latitude: metadata.latitude,
            longitude: metadata.longitude,
            placeName: place.flatMap { $0.name ?? $0.locality ?? $0.adminArea ?? $0.country },
            albums: albums,
            rating: rating,
            keywords: keywords,
            isEdited: metadata.hasAdjustments ?? false,
            source: nil
        )
    }

    /// "HEIC", "JPEG", "DNG"… from the original's name; nil without one.
    nonisolated static func format(of filename: String?) -> String? {
        guard let ext = filename.map({ ($0 as NSString).pathExtension.uppercased() }), !ext.isEmpty else { return nil }
        return switch ext {
        case "JPG", "JPE": "JPEG"
        case "TIF": "TIFF"
        default: ext
        }
    }

    /// Titles of the albums the user made that hold each photo — not smart
    /// albums, not shared ones.
    nonisolated private static func albumTitles(_ ids: [String]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for asset in PhotoLibraryService.fetchAssets(ids: ids) {
            let albums = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
            var titles: [String] = []
            albums.enumerateObjects { album, _, _ in
                if album.assetCollectionSubtype == .albumRegular, let title = album.localizedTitle { titles.append(title) }
            }
            result[asset.localIdentifier] = titles
        }
        return result
    }
}
