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

    /// FS-02.06 AC-15: a photo taken out of a limited selection while it
    /// loads reads "Can't Open This Photo" with Open Settings and Cancel, and
    /// every button of that alert closes the editor.
    @Test func noAccessReadsCantOpenThisPhoto() throws {
        let failure = EditorLoadFailure.classify(PhotoEditingError.unavailable, accessIsLimited: true)
        #expect(failure.title == "Can't Open This Photo")
        #expect(failure.offersSettings)
        let screen = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Editing/PhotoEditorScreen.swift")
            .joined(separator: "\n")
        let start = try #require(screen.range(of: "private struct EditorLoadFailureAlert"))
        let alert = String(screen[start.lowerBound...].prefix(1400))
        let settings = try #require(alert.range(of: "if failure.offersSettings {"))
        let otherwise = try #require(alert.range(of: "} else {"))
        let branch = String(alert[settings.upperBound..<otherwise.lowerBound])
        #expect(branch.contains("Button(\"Open Settings\")"))
        #expect(branch.contains("Button(\"Cancel\", role: .cancel) { close() }"))
        // Open Settings leaves for Settings and closes the editor behind it.
        let openSettings = try #require(branch.range(of: "Button(\"Open Settings\")"))
        let cancel = try #require(branch.range(of: "Button(\"Cancel\""))
        #expect(branch[openSettings.upperBound..<cancel.lowerBound].contains("close()"))
    }

    @Test func anythingElseKeepsItsOwnSentence() {
        let failure = EditorLoadFailure.classify(PhotoEditingError.cannotDecode, accessIsLimited: false)
        #expect(failure == .other("The photo couldn't be decoded."))
        #expect(failure.message == "The photo couldn't be decoded.")
        #expect(!failure.offersSettings)
    }
}
