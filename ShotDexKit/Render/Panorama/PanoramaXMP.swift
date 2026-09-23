import Foundation
import ImageIO

/// ShotDex's own panorama tag, and how to read it back out of a file.
///
/// A stitched panorama has to stay a panorama after it leaves the app: copied
/// to another device through iCloud, re-imported, indexed by a fresh install.
/// A row in the database would not survive any of that, so the fact lives in
/// the file, in XMP, and the indexer reads it back (FS-14.02 §7).
///
/// Deliberately a private namespace rather than GPano alone. GPano describes
/// **equirectangular** panoramas; writing it for a cylindrical or perspective
/// stitch tells other apps something untrue, and Google Photos would show the
/// result as a sphere. GPano is written too, but only for Spherical.
public enum PanoramaXMP {
    /// The namespace URI, which is what identifies the tag. Readers match on
    /// this, not on the prefix — a prefix is only a local nickname and a file
    /// written elsewhere may use another one.
    public static let namespace = "http://ns.shotdex.app/panorama/1.0/"
    /// The prefix written into files this app produces.
    public static let prefix = "shotdexPano"

    /// "This image was stitched by ShotDex." Presence with a true value is the
    /// whole test — the rest is description.
    public static let stitchedProperty = "Stitched"
    /// Which projection produced it, as `PanoramaProjection.rawValue`.
    public static let projectionProperty = "Projection"
    /// How many frames went in.
    public static let frameCountProperty = "FrameCount"

    /// The standard namespace, written only for a spherical stitch.
    public static let gpanoNamespace = "http://ns.google.com/photos/1.0/panorama/"

    /// Whether this file carries ShotDex's panorama tag.
    ///
    /// Walks the tags and matches on namespace and name rather than asking for
    /// a path like `shotdexPano:Stitched`: a path lookup needs the prefix to be
    /// registered on the metadata object first, and a file written by another
    /// build — or another tool round-tripping the packet — is free to have
    /// renamed the prefix. The namespace is the part that cannot move.
    public static func isStitchedPanorama(_ source: CGImageSource) -> Bool {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, options) else { return false }
        return isStitchedPanorama(metadata)
    }

    public static func isStitchedPanorama(_ metadata: CGImageMetadata) -> Bool {
        guard let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag] else { return false }
        for tag in tags {
            guard let namespace = CGImageMetadataTagCopyNamespace(tag) as String?,
                  namespace == Self.namespace,
                  let name = CGImageMetadataTagCopyName(tag) as String?,
                  name == stitchedProperty
            else { continue }
            return isTrue(CGImageMetadataTagCopyValue(tag))
        }
        return false
    }

    /// The metadata object to attach to a stitched file.
    ///
    /// Writing lives beside reading on purpose: a tag whose writer and reader
    /// are in different files drifts, and the one thing this feature cannot
    /// afford is a panorama the app itself no longer recognises.
    ///
    /// `projection` and `frameCount` are description, not test — nothing keys
    /// off them today. They are written because the one question anybody asks
    /// of a stitched file later is "what did this come from".
    public static func makeMetadata(projection: String, frameCount: Int) -> CGMutableImageMetadata? {
        let metadata = CGImageMetadataCreateMutable()
        guard register(prefix: prefix, for: namespace, on: metadata) else { return nil }
        let values: [(String, CFTypeRef)] = [
            (stitchedProperty, "True" as CFString),
            (projectionProperty, projection as CFString),
            (frameCountProperty, String(frameCount) as CFString),
        ]
        for (name, value) in values {
            guard let tag = CGImageMetadataTagCreate(
                namespace as CFString, prefix as CFString, name as CFString, .string, value
            ) else { return nil }
            guard CGImageMetadataSetTagWithPath(metadata, nil, "\(prefix):\(name)" as CFString, tag) else {
                return nil
            }
        }
        return metadata
    }

    private static func register(prefix: String, for namespace: String, on metadata: CGMutableImageMetadata) -> Bool {
        var error: Unmanaged<CFError>?
        let registered = CGImageMetadataRegisterNamespaceForPrefix(
            metadata, namespace as CFString, prefix as CFString, &error
        )
        error?.release()
        return registered
    }

    /// XMP has no booleans of its own — a boolean is the text "True" or
    /// "False" — so accept both that and a number, and treat anything else as
    /// absent rather than guessing.
    private static func isTrue(_ value: CFTypeRef?) -> Bool {
        if let text = value as? String {
            return text.caseInsensitiveCompare("true") == .orderedSame || text == "1"
        }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }
}

/// What the stitched file says it was shot with.
///
/// The rule, from FS-14.02 §7: identity comes from the first frame, and
/// anything that describes *this exposure* survives only if every frame agrees
/// about it. A panorama shot across a bright sky and a dark street has no one
/// shutter speed, and claiming the first frame's would make the library lie —
/// these are the columns the whole app filters and charts on.
public enum PanoramaMetadataRule {

    /// Keys under `{Exif}` that describe one exposure rather than the camera.
    static let exposureKeys: [CFString] = [
        kCGImagePropertyExifExposureTime,
        kCGImagePropertyExifFNumber,
        kCGImagePropertyExifISOSpeedRatings,
        kCGImagePropertyExifShutterSpeedValue,
        kCGImagePropertyExifApertureValue,
        kCGImagePropertyExifExposureBiasValue,
        kCGImagePropertyExifBrightnessValue,
    ]

    /// Builds the properties for the stitched file out of the frames' own.
    ///
    /// - Parameter frames: image properties of each frame, in stitching order —
    ///   the first is the top-left one, which is the one the panorama inherits
    ///   its identity from.
    /// - Parameter pixelWidth: the size actually written.
    public static func merge(
        frames: [[CFString: Any]],
        pixelWidth: Int,
        pixelHeight: Int
    ) -> [CFString: Any] {
        guard let first = frames.first else { return [:] }
        var merged = first

        // The picture's own facts are about the picture, not about the frame it
        // borrowed the rest from.
        merged[kCGImagePropertyPixelWidth] = pixelWidth
        merged[kCGImagePropertyPixelHeight] = pixelHeight
        // Stood upright at render time, so any rotation the first frame carried
        // would rotate a picture that is already the right way up.
        merged[kCGImagePropertyOrientation] = 1

        var exif = (first[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
        for key in exposureKeys where !allAgree(frames, key: key) {
            exif.removeValue(forKey: key)
        }
        if exif.isEmpty {
            merged.removeValue(forKey: kCGImagePropertyExifDictionary)
        } else {
            merged[kCGImagePropertyExifDictionary] = exif
        }
        return merged
    }

    /// Whether every frame reports the same value for one exposure key.
    ///
    /// Compared as text because these arrive as numbers, arrays and CFNumbers
    /// depending on the camera, and the question is only "are they the same".
    static func allAgree(_ frames: [[CFString: Any]], key: CFString) -> Bool {
        var seen: String?
        for frame in frames {
            let exif = (frame[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
            guard let value = exif[key] else { return false }
            let text = String(describing: value)
            if let seen, seen != text { return false }
            seen = text
        }
        return seen != nil
    }
}
