import Foundation

/// Which Lensfun lens profile corrects this photo, and the body's crop factor
/// the profile has to be scaled by. Resolved in the app — matching an EXIF
/// lens string to a Lensfun row is the app's job — and stored resolved, so the
/// renderer only looks the lens up by id.
public struct PhotoLensProfileChoice: Codable, Equatable, Sendable {
    /// `LensfunLens.id` — "maker|model".
    public var lensID: String
    public var cameraCropFactor: Double
    /// True when ShotDex matched it from EXIF, false when the user picked it.
    public var isAutomatic: Bool

    public init(lensID: String, cameraCropFactor: Double, isAutomatic: Bool) {
        self.lensID = lensID
        self.cameraCropFactor = cameraCropFactor
        self.isAutomatic = isAutomatic
    }
}
