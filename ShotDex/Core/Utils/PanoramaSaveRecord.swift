import Foundation

/// A note that a panorama save was in flight, so the next launch can say so.
///
/// A save of a big panorama can run for a minute, and a minute in the
/// background is long enough for iOS to reclaim the app. Nothing is half
/// written when that happens — the picture is built in a scratch directory
/// and only handed to PhotoKit at the end — so the damage is not a corrupt
/// file, it is a photographer who believes they saved a photograph and has
/// no photograph (FS-14.01 §6).
///
/// The note lives in `UserDefaults` rather than in the database because it
/// belongs to a launch, not to a library: it is written before the work and
/// cleared after it, and anything still there next time is a save that never
/// finished.
enum PanoramaSaveRecord {
    private static let key = "panorama.save.inFlight"

    /// The frames a save was started with, or nil when the last save ended
    /// the way it should have.
    static var interrupted: [String]? {
        let identifiers = UserDefaults.standard.stringArray(forKey: key)
        return (identifiers?.isEmpty == false) ? identifiers : nil
    }

    static func begin(assetIDs: [String]) {
        UserDefaults.standard.set(assetIDs, forKey: key)
    }

    static func finish() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
