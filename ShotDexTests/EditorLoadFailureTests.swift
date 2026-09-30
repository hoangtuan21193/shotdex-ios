import Foundation
import Photos
import Testing
import ShotDexKit
@testable import ShotDex

/// FS-03.09 AC-15: a photo that will not open says why, and a permission
/// problem offers Settings.
@Suite struct EditorLoadFailureTests {
    @Test func permissionErrorsOfferSettings() {
        for code in [PHPhotosError.Code.accessUserDenied, .accessRestricted] {
            let failure = EditorLoadFailure.classify(NSError(domain: PHPhotosErrorDomain, code: code.rawValue), accessIsLimited: false)
            #expect(failure == .noAccess)
            #expect(failure.offersSettings)
        }
    }

    /// Outside a limited selection Photos hands back no input and no error.
    @Test func anUnavailablePhotoUnderLimitedAccessIsTheSelection() {
        #expect(EditorLoadFailure.classify(PhotoEditingError.unavailable, accessIsLimited: true) == .noAccess)
        #expect(EditorLoadFailure.classify(PhotoEditingError.unavailable, accessIsLimited: false) != .noAccess)
    }

    @Test func networkFailuresReadAsICloud() {
        let offline = NSError(domain: PHPhotosErrorDomain, code: PHPhotosError.Code.networkAccessRequired.rawValue)
        #expect(EditorLoadFailure.classify(offline, accessIsLimited: false) == .iCloudDownload)
        let url = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        #expect(EditorLoadFailure.classify(url, accessIsLimited: true) == .iCloudDownload)
        #expect(!EditorLoadFailure.iCloudDownload.offersSettings)
    }

    @Test func anythingElseKeepsItsOwnSentence() {
        let failure = EditorLoadFailure.classify(PhotoEditingError.cannotDecode, accessIsLimited: false)
        #expect(failure == .other("The photo couldn't be decoded."))
        #expect(failure.message == "The photo couldn't be decoded.")
        #expect(!failure.offersSettings)
    }
}
