import Foundation

/// How an answer given in the Home Screen's "Edit Widget" menu becomes part of
/// the settings both the app and the widget read.
///
/// The menu and the app's Settings screen are two doors onto one room. The
/// widget cannot clear the menu, so it remembers which answer it has already
/// taken in (`appliedIntentSignature`) and applies a given answer once. After
/// that the app is free to change the same thing, and a menu that has not
/// moved does not undo it. Last writer wins, whichever door it came through.
enum PhotoWidgetIntentApplication {
    /// What the menu currently says, as one comparable string.
    static func signature(
        photoId: String?,
        albumId: String?,
        rotationRawValue: String?,
        dimming: Double?
    ) -> String {
        [
            photoId ?? "-",
            albumId ?? "-",
            rotationRawValue ?? "-",
            dimming.map { String(format: "%.2f", $0) } ?? "-",
        ].joined(separator: "|")
    }

    /// Folds the menu's answer into `settings`, returning true when anything
    /// changed and the file is worth rewriting.
    ///
    /// Only what the menu actually answered is applied: an empty Photo and
    /// Album leave the source alone, and "As Set in ShotDex" is not an answer.
    @discardableResult
    static func apply(
        to settings: inout PhotoWidgetSettings,
        photoId: String?,
        photoLabel: String?,
        albumId: String?,
        albumTitle: String?,
        rotation: PhotoWidgetSettings.Rotation?,
        dimming: Double?,
        signature: String
    ) -> Bool {
        // An untouched menu is not an answer. It has to stay silent rather
        // than record itself, because a second widget of the same kind with
        // nothing set would otherwise keep overwriting the first one's choice,
        // and the two would take turns rewriting the file for ever.
        let answersSomething = !(photoId ?? "").isEmpty
            || !(albumId ?? "").isEmpty
            || rotation != nil
            || dimming != nil
        guard answersSomething else { return false }
        guard settings.appliedIntentSignature != signature else { return false }

        let before = settings
        if let photoId, !photoId.isEmpty {
            settings.source = .photo(assetId: photoId)
        } else if let albumId, !albumId.isEmpty {
            settings.source = .album(collectionId: albumId, title: albumTitle ?? "Album")
        }
        if let rotation { settings.rotation = rotation }
        if let dimming { settings.photoDimming = dimming }
        settings.appliedIntentSignature = signature

        return before.source != settings.source
            || before.rotation != settings.rotation
            || before.photoDimming != settings.photoDimming
            || before.appliedIntentSignature != settings.appliedIntentSignature
    }
}
