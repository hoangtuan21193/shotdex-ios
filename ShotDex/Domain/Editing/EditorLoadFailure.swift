import Foundation
import Photos
import ShotDexKit

/// Why a photo would not open in the editor, in the terms the user can act on
/// (FS-03.09 AC-15). "Editor Error" with the system's sentence and an OK
/// button left the user nowhere: a photo outside a limited selection, or one
/// only in iCloud with no connection, each have a place to go next.
enum EditorLoadFailure: Equatable {
    /// Photos will not hand over the file: access is limited to a selection
    /// that does not include this photo, or was turned off.
    case noAccess
    /// The original is only in iCloud and could not be downloaded.
    case iCloudDownload
    case other(String)

    static func classify(_ error: Error, accessIsLimited: Bool) -> EditorLoadFailure {
        let nsError = error as NSError
        if nsError.domain == PHPhotosErrorDomain {
            switch PHPhotosError.Code(rawValue: nsError.code) {
            case .accessRestricted, .accessUserDenied:
                return .noAccess
            case .networkAccessRequired, .networkError:
                return .iCloudDownload
            default:
                break
            }
        }
        if nsError.domain == NSURLErrorDomain || nsError.domain == "CloudPhotoLibraryErrorDomain" {
            return .iCloudDownload
        }
        // Under a limited selection an asset outside it comes back with no
        // input and no error at all; that is the selection, not the file.
        if accessIsLimited, (error as? PhotoEditingError) == .unavailable {
            return .noAccess
        }
        return .other(error.localizedDescription)
    }

    var title: String {
        switch self {
        case .noAccess: String(localized: "Can't Open This Photo", comment: "Editor load error title: no access to the photo")
        case .iCloudDownload: String(localized: "Couldn't Download from iCloud", comment: "Editor load error title")
        case .other: String(localized: "Couldn't Open Photo", comment: "Editor load error title")
        }
    }

    var message: String {
        switch self {
        case .noAccess:
            String(localized: "ShotDex can only open photos you've allowed it to see. Allow access to this photo, or to all photos, in Settings.", comment: "Editor load error: photo outside the limited selection")
        case .iCloudDownload:
            String(localized: "This photo's original is in iCloud and couldn't be downloaded. Check your connection and try again.", comment: "Editor load error: iCloud download failed")
        case .other(let message):
            message
        }
    }

    /// Only a permission problem is fixed in Settings.
    var offersSettings: Bool { self == .noAccess }
}
