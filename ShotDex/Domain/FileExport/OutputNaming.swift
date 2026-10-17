import Foundation
import ShotDexKit

/// Save as Copy's file name (FS-18 03 §5, FS-03.06 §2): `‹name› (edited).‹ext›`
/// beside the original, and Keep Both's ` (2)`, ` (3)`… when that is taken.
enum OutputNaming {
    /// - Parameters:
    ///   - original: the source file's name, `DSCF4127.RAF`.
    ///   - fileExtension: what the copy is written as, `jpg` or `heic`.
    ///   - existing: the names already in the folder, any case.
    static func editedCopy(of original: String, fileExtension: String, existing: Set<String>) -> String {
        let stem = "\((original as NSString).deletingPathExtension) (edited)"
        let taken = Set(existing.map { $0.lowercased() })
        func name(_ number: Int?) -> String {
            "\(number.map { "\(stem) (\($0))" } ?? stem).\(fileExtension)"
        }
        guard taken.contains(name(nil).lowercased()) else { return name(nil) }
        return name(FileExportPlan.firstFreeNumber { taken.contains(name($0).lowercased()) })
    }

    /// The extension a copy is written with: HEIC stays HEIC where the
    /// encoder has it, everything else — RAW, PNG, TIFF, JPEG — is JPEG.
    static func copyExtension(of original: String, format: PhotoOutputFormat, encodesHEIC: Bool) -> String {
        let resolved: PhotoOutputFormat
        switch format {
        case .jpeg, .heic: resolved = format
        case .preserve: resolved = ["heic", "heif"].contains((original as NSString).pathExtension.lowercased()) ? .heic : .jpeg
        }
        return (resolved == .heic && !encodesHEIC ? PhotoOutputFormat.jpeg : resolved).fileExtension
    }
}
