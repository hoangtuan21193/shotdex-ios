import Foundation

/// Which of an asset's files one upload sends (FS-15.02 §2). Chosen on every
/// upload and never remembered: "only the RAWs this time" is a decision about
/// this batch, not a preference.
enum ServerUploadFileKind: String, CaseIterable, Identifiable, Sendable {
    case onlyRAW
    case allOriginals
    case originalsAndEdited

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onlyRAW: String(localized: "Only RAW", comment: "Upload to Server: send just the RAW file of each photo")
        case .allOriginals: String(localized: "All Originals", comment: "Upload to Server: send every original file of each photo (RAW, JPEG, Live Photo video)")
        case .originalsAndEdited: String(localized: "Originals + Edited", comment: "Upload to Server: send the originals and the edited version made in Photos")
        }
    }
}

/// One file of an asset, as the upload sees it — the Photos resource reduced
/// to what the plan, the path and the history need.
struct AssetUploadFile: Hashable, Sendable {
    enum Role: String, Sendable {
        /// A file the camera (or the import) wrote: RAW, JPEG, HEIC, the
        /// video of a Live Photo, a video.
        case original
        /// The rendered result of an edit made in Photos.
        case edited
    }

    /// Stable within one asset: the resource type plus its file name. It is
    /// what the history is keyed on, so "is this asset fully on a server"
    /// can be asked without Photos.
    let key: String
    let filename: String
    let isRAW: Bool
    let role: Role
    /// What Photos reports before the file is written out — used for the
    /// batch estimate only; the real size comes from the file.
    let estimatedBytes: Int64
}

enum ServerUploadPlan {
    /// The files `kind` sends out of one asset's files, in the asset's order.
    static func files(of assetFiles: [AssetUploadFile], kind: ServerUploadFileKind) -> [AssetUploadFile] {
        switch kind {
        case .onlyRAW:
            assetFiles.filter { $0.role == .original && $0.isRAW }
        case .allOriginals:
            assetFiles.filter { $0.role == .original }
        case .originalsAndEdited:
            assetFiles
        }
    }

    /// The batch summary on the prepare step.
    struct Summary: Equatable, Sendable {
        var photoCount = 0
        var fileCount = 0
        var estimatedBytes: Int64 = 0
        /// Assets that would send nothing under this kind — at Only RAW, the
        /// JPEG-only ones.
        var skippedPhotoCount = 0
    }

    static func summary(of assets: [[AssetUploadFile]], kind: ServerUploadFileKind) -> Summary {
        var summary = Summary()
        for assetFiles in assets {
            let chosen = files(of: assetFiles, kind: kind)
            if chosen.isEmpty {
                summary.skippedPhotoCount += 1
                continue
            }
            summary.photoCount += 1
            summary.fileCount += chosen.count
            summary.estimatedBytes += chosen.reduce(0) { $0 + $1.estimatedBytes }
        }
        return summary
    }
}
