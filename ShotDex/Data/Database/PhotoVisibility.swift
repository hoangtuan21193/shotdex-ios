import Foundation

/// Which photos the library shows and counts (FS-19.05 §3, FS-19.04 §3): a
/// photo is visible while at least one of its copies is there (not missing),
/// not hidden, and either on an online source or on one that keeps its
/// photos while unplugged. Computed in the query, never stored, so hiding a
/// copy or unplugging a drive needs no rewrite of `photo_metadata`.
///
/// A Photos asset always has its Photos copy, so the library of a user with
/// no other source is exactly what it was.
enum PhotoVisibility {
    static let condition = """
        EXISTS (SELECT 1 FROM photo_copies vc WHERE vc.photoId = photo_metadata.assetId \
        AND vc.missingSince IS NULL AND vc.isHidden = 0 \
        AND (vc.isOnline = 1 OR vc.sourceId NOT IN (SELECT id FROM sources WHERE whenUnplugged = 'hidePhotos')))
        """
}
