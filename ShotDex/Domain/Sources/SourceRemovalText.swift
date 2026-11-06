import Foundation

extension SourceRowText {
    /// Remove Source's confirmation (Mac Settings › Sources, FS-18.04 §3
    /// AC-72): the photos leave ShotDex; the files stay where they are.
    var removeMessage: String {
        let photos = switch count {
        case 0: String(localized: "Nothing from it is in ShotDex yet.", comment: "Remove Source: a source with no photos read")
        case 1: String(localized: "Its photo leaves ShotDex unless another source has it.", comment: "Remove Source: one photo leaves the library")
        default: String(localized: "Its \(count, format: .number) photos leave ShotDex unless another source has them.",
                        comment: "Remove Source: the source's photos leave the library")
        }
        let stays = switch kind {
        case .server: String(localized: "Nothing on the server is deleted.", comment: "Remove Source: server files stay")
        case .drive: String(localized: "Nothing on the drive is deleted.", comment: "Remove Source: drive files stay")
        default: String(localized: "Nothing in the folder is deleted.", comment: "Remove Source: folder files stay")
        }
        return photos + " " + stays
    }
}
