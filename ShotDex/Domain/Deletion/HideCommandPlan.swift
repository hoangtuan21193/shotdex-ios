import Foundation

/// The Hide commands a selection gets (FS-19.04 §3, board mac-ipad-v2 Q1):
/// a photo in one place has plain Hide; once any selected photo is both in
/// Photos and in a folder or on a server, the menu has two rows instead —
/// Hide in Photos and Hide in ShotDex Only. Same words in the Viewer's ⋯,
/// the long-press and right-click menu, selection's ⋯ and the Mac's Photo
/// menu.
enum HideCommand: Equatable, Sendable {
    case hide
    /// The Photos copy goes to Photos' Hidden album (on every device through
    /// iCloud); ShotDex hides every other copy.
    case hideInPhotos
    /// ShotDex hides every copy, the Photos copy too; Photos is not changed.
    case hideInShotDexOnly

    var title: String {
        switch self {
        case .hide: String(localized: "Hide", comment: "Photo menu: hide a photo that lives in one place")
        case .hideInPhotos: String(localized: "Hide in Photos", comment: "Photo menu: hide in the Photos app too (photo is in Photos and in a folder or server)")
        case .hideInShotDexOnly: String(localized: "Hide in ShotDex Only", comment: "Photo menu: hide only in ShotDex, Photos unchanged")
        }
    }
}

enum HideCommandPlan {
    /// Where one selected photo has copies.
    struct Photo: Sendable {
        let hasPhotosCopy: Bool
        let hasOtherCopy: Bool
    }

    static func commands(for photos: [Photo]) -> [HideCommand] {
        photos.contains { $0.hasPhotosCopy && $0.hasOtherCopy } ? [.hideInPhotos, .hideInShotDexOnly] : [.hide]
    }
}
