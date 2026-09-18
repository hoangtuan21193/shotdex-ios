import Foundation
import Photos

/// Handing the photo you are looking at to another device.
///
/// The payload is the asset's **cloud** identifier, not its local one. A local
/// identifier is meaningful only on the device that issued it — handing one to
/// an iPad would name a photo that does not exist there. `PHCloudIdentifier` is
/// PhotoKit's answer to exactly this, and it resolves on any device signed into
/// the same iCloud Photos library.
///
/// Which also means Handoff works only for photos that are in iCloud Photos. A
/// local-only photo has no cloud identifier, and no activity is published for
/// it rather than one that would fail on the other end.
enum HandoffActivity {
    static let viewPhoto = "com.hoangtuan.shotdex.view-photo"

    private enum Key {
        static let cloudIdentifier = "cloudIdentifier"
    }

    /// The activity for a photo, or nil when it has no cloud identity.
    static func activity(for asset: PHAsset, title: String?) async -> NSUserActivity? {
        guard let cloudIdentifier = await cloudIdentifier(for: asset.localIdentifier)
        else { return nil }
        let activity = NSUserActivity(activityType: viewPhoto)
        activity.title = title ?? "Photo"
        activity.userInfo = [Key.cloudIdentifier: cloudIdentifier]
        activity.isEligibleForHandoff = true
        // Not searchable and not predicted: Spotlight holds this app's
        // collections, deliberately never its individual photos, and a photo
        // the user happened to open is not a habit worth suggesting.
        activity.isEligibleForSearch = false
        activity.isEligibleForPrediction = false
        return activity
    }

    /// The local identifier on *this* device for a handed-over activity.
    static func localIdentifier(from activity: NSUserActivity) async -> String? {
        guard activity.activityType == viewPhoto,
              let cloudIdentifier = activity.userInfo?[Key.cloudIdentifier] as? String
        else { return nil }
        return await localIdentifier(forCloudIdentifier: cloudIdentifier)
    }

    // MARK: PhotoKit mapping

    private static func cloudIdentifier(for localIdentifier: String) async -> String? {
        await Task.detached(priority: .userInitiated) {
            let mappings = PHPhotoLibrary.shared()
                .cloudIdentifierMappings(forLocalIdentifiers: [localIdentifier])
            guard let result = mappings[localIdentifier],
                  let identifier = try? result.get()
            else { return nil }
            return identifier.stringValue
        }.value
    }

    private static func localIdentifier(forCloudIdentifier identifier: String) async -> String? {
        await Task.detached(priority: .userInitiated) {
            let cloud = PHCloudIdentifier(stringValue: identifier)
            let mappings = PHPhotoLibrary.shared()
                .localIdentifierMappings(for: [cloud])
            guard let result = mappings[cloud],
                  let local = try? result.get()
            else { return nil }
            return local
        }.value
    }
}
