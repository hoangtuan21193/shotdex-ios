import Photos

extension PHAsset {
    /// The star rating Photos holds (0 = unrated) — iOS 27 and later. Nil
    /// below it, where the only ratings are ShotDex's pending rows
    /// (FS-01.12 §4). An in-memory property, free per grid cell, like
    /// `isFavorite`.
    var photosStarRating: Int? {
        if #available(iOS 27, macOS 27, *) {
            return rating.rawValue
        }
        return nil
    }
}
