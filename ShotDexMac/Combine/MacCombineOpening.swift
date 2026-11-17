import GRDB
import Photos
import SwiftUI

/// Image › Combine Photos › Panorama… with photos chosen: which of them can
/// be frames, read off the main actor. A photo is a frame when it is a
/// still with its original here — a file on this Mac, or a Photos library
/// picture. Videos, cloud placeholders and server-only photos are left out
/// and counted (FS-18.04 §4b).
extension MacCombineSession {
    /// At most this many frames: Save decodes every frame at full size and
    /// holds them all while it blends (30 × 45 MP is about 5 GB), and a
    /// sweep of more is a different tool.
    static let frameLimit = 30
    static func make(ids allIds: [String], dependencies: MacDependencies) async -> MacCombineSession? {
        let found = await MacPhotoOrigins.resolve(ids: allIds, limit: frameLimit, dependencies: dependencies)
        guard found.photos.count >= 2 else { return nil }
        let frames = found.photos.enumerated().map { index, photo in
            Frame(id: index, photoId: photo.origin.id, name: photo.name,
                  exposure: exposure(shutter: photo.shutter, aperture: photo.aperture))
        }
        let session = MacCombineSession(origins: found.photos.map(\.origin), frames: frames,
                                        leftOut: found.leftOut,
                                        subtitle: subtitle(count: frames.count, camera: found.photos.lazy.compactMap(\.camera).first,
                                                           lens: found.photos.lazy.compactMap(\.lens).first),
                                        photoLibrary: dependencies.photoLibrary)
        session.overLimit = found.overLimit
        return session
    }

    /// "1/250 s · f/8".
    nonisolated static func exposure(shutter: String?, aperture: Double?) -> String {
        [shutter.map { "\($0) s" }, aperture.map { "f/\($0.formatted(.number.precision(.fractionLength(0...1))))" }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// "8 photos · Sony A7 IV · FE 24-70mm F2.8 GM II".
    static func subtitle(count: Int, camera: String?, lens: String?) -> String {
        ([MacInflect.string("^[\(count) photo](inflect: true)", comment: "Mac Combine: subtitle, how many frames")]
         + [camera, lens].compactMap { $0 }).joined(separator: " · ")
    }

    #if DEBUG
    /// `-ShotDexSection panorama` (board `MAC_Merge`): eight overlapping
    /// slices of the demo picture, as a sweep shot left to right.
    static func demo(dependencies: MacDependencies) async -> MacCombineSession? {
        let urls = await Task.detached(priority: .userInitiated) { MacDemoLibrary.panoramaFrames() }.value
        guard urls.count >= 2 else { return nil }
        let origins = urls.enumerated().map { PhotoEditOrigin.fileCopy(FileCopyPhoto(photoId: "demo-pano-\($0.offset)", url: $0.element)) }
        let shutters = ["1/250", "1/250", "1/320", "1/250", "1/250", "1/200", "1/250", "1/250"]
        let frames = urls.enumerated().map { index, url in
            Frame(id: index, photoId: "demo-pano-\(index)", name: url.lastPathComponent,
                  exposure: exposure(shutter: shutters[index % shutters.count], aperture: 8))
        }
        return MacCombineSession(origins: origins, frames: frames, leftOut: 0,
                                 subtitle: subtitle(count: frames.count, camera: "Sony A7 IV", lens: "FE 24-70mm F2.8 GM II"),
                                 photoLibrary: dependencies.photoLibrary)
    }
    #endif
}

/// Chosen photos that can be worked on here: stills with their original on
/// this Mac (a file) or in the Photos library. Shared by Combine Photos and
/// Collage (FS-18.04 §4b, §4c), read off the main actor.
struct MacResolvedPhoto {
    let origin: PhotoEditOrigin
    let name: String
    let shutter: String?
    let aperture: Double?
    let camera: String?
    let lens: String?
}

enum MacPhotoOrigins {
    /// The photos looked at: enough past any limit to skip videos and cloud
    /// copies, and well under SQLite's bound-variable cap.
    static let candidateLimit = 400

    /// `leftOut`: videos, cloud placeholders, server-only photos.
    /// `overLimit`: usable photos past `limit`.
    @MainActor
    static func resolve(ids allIds: [String], limit: Int, dependencies: MacDependencies)
        async -> (photos: [MacResolvedPhoto], leftOut: Int, overLimit: Int) {
        let ids = Array(allIds.prefix(candidateLimit))
        let database = dependencies.database
        let rows = await Task.detached(priority: .userInitiated) { () -> [MacOriginRow] in
            (try? database.reader.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT assetId, mediaType, originalFilename, shutterSpeedDisplay, aperture,
                           COALESCE(normalizedCameraModel, cameraModel) AS camera,
                           COALESCE(normalizedLensModel, lensModel) AS lens
                    FROM photo_metadata WHERE assetId IN (\(ids.map { _ in "?" }.joined(separator: ",")))
                    """, arguments: StatementArguments(ids))
                .map { MacOriginRow(id: $0["assetId"], isImage: ($0["mediaType"] as Int?) == PHAssetMediaType.image.rawValue,
                                    filename: $0["originalFilename"], shutter: $0["shutterSpeedDisplay"], aperture: $0["aperture"],
                                    camera: $0["camera"], lens: $0["lens"]) }
            }) ?? []
        }.value
        let byId = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var photos: [MacResolvedPhoto] = []
        var overLimit = 0
        for id in ids {
            guard let row = byId[id], row.isImage else { continue }
            guard photos.count < limit else { overLimit += 1; continue }
            let origin: PhotoEditOrigin?
            if await MacEditorModel.isPhotosOnly(id, database: database) {
                let asset = await Task.detached { MacOriginAssetBox(PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject) }.value
                origin = asset.asset.map { .asset($0) }
            } else if let file = await MacPhotoFiles.resolve(id, dependencies: dependencies), !file.isPlaceholder {
                origin = .fileCopy(FileCopyPhoto(photoId: id, url: file.url))
            } else {
                origin = nil
            }
            guard let origin else { continue }
            photos.append(MacResolvedPhoto(origin: origin, name: row.filename ?? origin.localFileURL?.lastPathComponent ?? id,
                                           shutter: row.shutter, aperture: row.aperture, camera: row.camera, lens: row.lens))
        }
        return (photos, ids.count - photos.count - overLimit, overLimit + max(0, allIds.count - ids.count))
    }
}

private struct MacOriginRow: Sendable {
    let id: String
    let isImage: Bool
    let filename: String?
    let shutter: String?
    let aperture: Double?
    let camera: String?
    let lens: String?
}

/// A fetched asset carried out of the detached fetch; PHAsset is immutable once fetched.
private struct MacOriginAssetBox: @unchecked Sendable {
    let asset: PHAsset?
    init(_ asset: PHAsset?) { self.asset = asset }
}
