import Foundation
import ShotDexKit
import UniformTypeIdentifiers

/// What to tell the user when a `.cube` file will not import.
///
/// Specific on purpose: "couldn't read that LUT" leaves a colourist guessing
/// between a truncated download, a 1D file and a Resolve export at 65³. Each
/// parser failure names the thing that is wrong, so they know whether to
/// re-export or give up on the file.
enum LUTImportMessage {
    /// `.cube` has no registered system type, so it is matched by extension.
    static let cubeType = UTType(filenameExtension: "cube") ?? .data

    static func text(for error: any Error) -> String {
        guard let failure = error as? CubeLUTParser.Failure else {
            return String(
                localized: "The file could not be opened as text. ShotDex reads .cube files.",
                comment: "LUT import: the picked file is not readable text"
            )
        }
        switch failure {
        case .noSize:
            return String(
                localized: "The file has no LUT_3D_SIZE line, so it is not a .cube table.",
                comment: "LUT import: the cube file declares no size"
            )
        case .unsupportedSize(let size):
            return String(
                localized: "The table is \(size) points on a side. ShotDex reads \(CubeLUTParser.minimumDimension) to \(CubeLUTParser.maximumDimension).",
                comment: "LUT import: the cube size is outside the supported range"
            )
        case .wrongRowCount(let expected, let found):
            return String(
                localized: "The table should have \(expected) rows but has \(found). The file may be cut short.",
                comment: "LUT import: the number of table rows does not match the declared size"
            )
        case .malformedRow(let line):
            return String(
                localized: "Line \(line) is not three numbers.",
                comment: "LUT import: a table row could not be read"
            )
        }
    }
}
