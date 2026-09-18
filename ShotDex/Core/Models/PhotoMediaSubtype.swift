import Foundation
import Photos

/// The capture kinds the library can be filtered by — PhotoKit's media-subtype
/// bitmask, narrowed to the ones a photographer actually sorts on.
///
/// Stored as the raw bit so a filter is a single `AND` in SQL, and so a value
/// PhotoKit adds later cannot invalidate rows already written.
enum PhotoMediaSubtype: String, CaseIterable, Codable, Identifiable, Sendable {
    case screenshot
    case livePhoto
    case portrait
    case panorama
    case hdr
    case timelapse
    case slowMotion
    case cinematic

    var id: String { rawValue }

    var bit: Int {
        switch self {
        case .panorama: Int(PHAssetMediaSubtype.photoPanorama.rawValue)
        case .hdr: Int(PHAssetMediaSubtype.photoHDR.rawValue)
        case .screenshot: Int(PHAssetMediaSubtype.photoScreenshot.rawValue)
        case .livePhoto: Int(PHAssetMediaSubtype.photoLive.rawValue)
        case .portrait: Int(PHAssetMediaSubtype.photoDepthEffect.rawValue)
        case .slowMotion: Int(PHAssetMediaSubtype.videoHighFrameRate.rawValue)
        case .timelapse: Int(PHAssetMediaSubtype.videoTimelapse.rawValue)
        case .cinematic: Int(PHAssetMediaSubtype.videoCinematic.rawValue)
        }
    }

    var title: String {
        switch self {
        case .screenshot: String(localized: "Screenshots")
        case .livePhoto: String(localized: "Live Photos")
        case .portrait: String(localized: "Portrait")
        case .panorama: String(localized: "Panoramas")
        case .hdr: String(localized: "HDR")
        case .timelapse: String(localized: "Time-lapse")
        case .slowMotion: String(localized: "Slo-mo")
        case .cinematic: String(localized: "Cinematic")
        }
    }

    var systemImage: String {
        switch self {
        case .screenshot: "camera.viewfinder"
        case .livePhoto: "livephoto"
        case .portrait: "camera.aperture"
        case .panorama: "pano"
        case .hdr: "sparkles"
        case .timelapse: "timelapse"
        case .slowMotion: "slowmo"
        case .cinematic: "video.badge.waveform"
        }
    }
}
