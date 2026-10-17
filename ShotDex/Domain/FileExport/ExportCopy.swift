import Foundation
import ShotDexKit

/// The words of FS-03.07b and FS-03.07c. Every string lives in the `Export`
/// string table (`Resources/Export.xcstrings`); counts go through its plural
/// variants. `locale` is injectable for tests.
enum ExportCopy {
    static let table = "Export"

    static var command: String {
        String(localized: "Export…", table: table, comment: "Photo command: write the selection to a folder in Files or a saved server")
    }

    static var title: String { String(localized: "Export", table: table, comment: "Export sheet title") }

    /// `48 Photos · 3 Videos` under the sheet title.
    static func countsTitle(photos: Int, videos: Int, locale: Locale = .current) -> String {
        var parts: [String] = []
        if photos > 0 || videos == 0 {
            parts.append(String(localized: "\(photos) Photos", table: table, locale: locale, comment: "Export sheet subtitle: photo count (plural)"))
        }
        if videos > 0 {
            parts.append(String(localized: "\(videos) Videos", table: table, locale: locale, comment: "Export sheet subtitle: video count (plural)"))
        }
        return parts.joined(separator: " · ")
    }

    /// `48 photos · 3 videos · ~1.2 GB` — the summary footer's first line.
    static func summary(photos: Int, videos: Int, bytes: Int64?, isEstimate: Bool, locale: Locale = .current) -> String {
        var parts: [String] = []
        if photos > 0 || videos == 0 {
            parts.append(String(localized: "\(photos) photos", table: table, locale: locale, comment: "Export summary: photo count (plural)"))
        }
        if videos > 0 {
            parts.append(String(localized: "\(videos) videos", table: table, locale: locale, comment: "Export summary: video count (plural)"))
        }
        if let bytes, bytes > 0 {
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            parts.append(isEstimate ? "~\(size)" : size)
        }
        return parts.joined(separator: " · ")
    }

    static var destination: String { String(localized: "Destination", table: table, comment: "Export sheet section") }
    static var folder: String { String(localized: "Folder", table: table, comment: "Export sheet row: where the files go") }
    static var noFolder: String { String(localized: "None", table: table, comment: "Export sheet: no folder chosen yet") }
    static var chooseFolder: String { String(localized: "Choose Folder…", table: table, comment: "Export sheet: open the system folder picker") }
    static var dateFolders: String { String(localized: "Date Folders", table: table, comment: "Export sheet switch: year/day subfolders") }
    static var exportSection: String { String(localized: "Export", table: table, comment: "Export sheet section: what is written") }
    static var exportAs: String { String(localized: "Export As", table: table, comment: "Export sheet row: Current Version or Unmodified Original") }

    static func mode(_ mode: FileExportMode) -> String {
        switch mode {
        case .currentVersion: String(localized: "Current Version", table: table, comment: "Export As: rendered at a preset")
        case .unmodifiedOriginal: String(localized: "Unmodified Original", table: table, comment: "Export As: original files byte for byte")
        }
    }

    static var version: String { String(localized: "Version", table: table, comment: "Export sheet row: Edited or Original") }

    static func version(_ version: FileExportVersion) -> String {
        switch version {
        case .edited: String(localized: "Edited", table: table, comment: "Export Version: with the edit made in Photos")
        case .original: String(localized: "Original", table: table, comment: "Export Version: as shot")
        }
    }

    static var size: String { String(localized: "Size", table: table, comment: "Export sheet row: Resize preset") }
    static var format: String { String(localized: "Format", table: table, comment: "Export sheet row: output format") }
    static var colorSpace: String { String(localized: "Color Space", table: table, comment: "Export sheet row: the color profile the files are written in") }
    static var quality: String { String(localized: "Quality", table: table, comment: "Export sheet row: compression quality") }
    static var metadata: String { String(localized: "Metadata", table: table, comment: "Export sheet row: metadata level") }
    static var livePhotoVideo: String { String(localized: "Live Photo Video", table: table, comment: "Export sheet switch: include the movie of a Live Photo") }
    static var fileNames: String { String(localized: "File Names", table: table, comment: "Export sheet section") }
    static var name: String { String(localized: "Name", table: table, comment: "Export sheet row: file name template") }
    static var ifFileExists: String { String(localized: "If a File Exists", table: table, comment: "Export sheet row: what to do on a name clash") }

    static func policy(_ policy: FileExportConflictPolicy) -> String {
        switch policy {
        case .keepBoth: String(localized: "Keep Both", table: table, comment: "If a File Exists: number the new file")
        case .replace: String(localized: "Replace", table: table, comment: "If a File Exists: overwrite the old file")
        case .skip: String(localized: "Skip", table: table, comment: "If a File Exists: leave the photo out")
        }
    }

    static func formatName(_ format: PhotoOutputFormat) -> String {
        switch format {
        case .preserve: String(localized: "Same as Original", table: table, comment: "Export Format: HEIC stays HEIC, JPEG stays JPEG, the rest JPEG")
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        }
    }

    static func colorSpaceName(_ space: ExportColorSpace) -> String {
        switch space {
        case .original: String(localized: "Original", table: table, comment: "Export Color Space: keep the photo's own profile")
        case .sRGB: "sRGB"
        case .displayP3: "Display P3"
        case .adobeRGB: "Adobe RGB"
        }
    }

    static func qualityText(_ quality: Double) -> String {
        "\(Int((quality * 100).rounded()))%"
    }

    static var videosAsTheyAre: String {
        String(localized: "Videos are exported as they are.", table: table, comment: "Export summary footer, Current Version with videos")
    }

    static var originalsAsTheyAre: String {
        String(localized: "Original files are copied as they are, with all their metadata. Edits aren't included.",
               table: table, comment: "Export summary footer, Unmodified Original")
    }

    /// `Example: 2026-09-20_X-T5_001.jpg`.
    static func example(_ name: String) -> String {
        String(localized: "Example: \(name)", table: table, comment: "Export sheet: the first photo's file name under the template")
    }

    static var fileNameTitle: String { String(localized: "File Name", table: table, comment: "File Name screen title") }
    static var custom: String { String(localized: "Custom", table: table, comment: "File Name screen: section for a typed template") }
    static var exampleLabel: String { String(localized: "Example", table: table, comment: "File Name screen: the first photo's name") }

    static func tokenTitle(_ token: FileNameTemplate.Token) -> String {
        switch token {
        case .original: String(localized: "Original Name", table: table, comment: "File name token chip")
        case .originalNumber: String(localized: "Original Number", table: table, comment: "File name token chip: the digits that end the original name, 6123 from IMG_6123")
        case .date: String(localized: "Date", table: table, comment: "File name token chip")
        case .time: String(localized: "Time", table: table, comment: "File name token chip")
        case .camera: String(localized: "Camera", table: table, comment: "File name token chip")
        case .lens: String(localized: "Lens", table: table, comment: "File name token chip")
        case .sequence: String(localized: "Sequence", table: table, comment: "File name token chip: 001, 002… through the batch")
        }
    }

    static func chipTitle(_ chip: FileNameChip) -> String {
        switch chip {
        case .token(let token): tokenTitle(token)
        case .text: String(localized: "Text", table: table, comment: "File name chip: adds words of your own")
        }
    }

    /// VoiceOver: `Insert Date`.
    static func insertChip(_ chip: FileNameChip) -> String {
        String(localized: "Insert \(chipTitle(chip))", table: table, comment: "File name token chip, VoiceOver label")
    }

    static func missingTokenFooter(_ example: String?) -> String {
        if let example {
            String(localized: "A token with no value is left out with its separator: a screenshot becomes \(example). RAW + JPEG pairs share one name.",
                   table: table, comment: "File Name screen footer, with an example")
        } else {
            String(localized: "A token with no value is left out with its separator. RAW + JPEG pairs share one name.",
                   table: table, comment: "File Name screen footer")
        }
    }

    static func templateTitle(_ template: FileNameTemplate) -> String {
        switch template {
        case .originalName: String(localized: "Original Name", table: table, comment: "File name template")
        case .dateCameraSequence: String(localized: "Date + Camera + Sequence", table: table, comment: "File name template")
        case .dateOriginal: String(localized: "Date + Original Name", table: table, comment: "File name template")
        default: String(localized: "Custom", table: table, comment: "File name template typed by the user")
        }
    }

    // MARK: Folder

    static var notConnected: String { String(localized: "Not connected", table: table, comment: "Export folder row: its drive is unplugged") }

    static func connectDrive(_ drive: String) -> String {
        String(localized: "Connect “\(drive)” or choose another folder.", table: table, comment: "Export footer: the folder's drive is unplugged")
    }

    static var folderGone: String {
        String(localized: "ShotDex can't open this folder anymore. Choose it again.", table: table, comment: "Export: a remembered folder no longer opens")
    }

    // MARK: Run

    static func exporting(_ current: Int, of total: Int) -> String {
        String(localized: "Exporting \(current) of \(total)", table: table, comment: "Export progress headline")
    }

    /// `1.4 GB of 3.2 GB`.
    static func bytesOf(_ written: String, _ total: String) -> String {
        String(localized: "\(written) of \(total)", table: table, comment: "Export progress: bytes written of the total")
    }

    static func timeLeft(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 {
            return String(localized: "less than a minute left", table: table, comment: "Export progress: time left under a minute")
        }
        return String(localized: "about \(minutes) min left", table: table, comment: "Export progress: time left in minutes")
    }

    static func step(_ step: FileExportStep) -> String {
        switch step {
        case .preparing: String(localized: "Preparing", table: table, comment: "Export step: downloading the original from iCloud")
        case .converting: String(localized: "Converting", table: table, comment: "Export step: rendering at the preset")
        case .writing: String(localized: "Writing", table: table, comment: "Export step: writing the file to the folder")
        }
    }

    static func downloadingFromICloud(_ fraction: Double) -> String {
        String(localized: "downloading from iCloud · \(Int((fraction * 100).rounded()))%", table: table, comment: "Export step detail: iCloud download progress")
    }

    static func toTarget(_ name: String) -> String {
        String(localized: "to \(name)", table: table, comment: "Export step detail: the file being written")
    }

    static var now: String { String(localized: "Now", table: table, comment: "Export progress section: the file being made") }

    static func keepOpen(_ folder: String) -> String {
        String(localized: "Keep ShotDex open. Files already exported stay in “\(folder)” if you stop.", table: table, comment: "Export progress footer")
    }

    static var stopTitle: String { String(localized: "Stop exporting?", table: table, comment: "Export: confirm Cancel during a run") }
    static var stopMessage: String {
        String(localized: "Files already exported stay in the folder.", table: table, comment: "Export: confirm Cancel during a run, message")
    }
    static var stop: String { String(localized: "Stop", table: table, comment: "Export: stop the run") }
    static var keepExporting: String { String(localized: "Keep Exporting", table: table, comment: "Export: do not stop the run") }

    static func replaceTitle(_ count: Int, folder: String) -> String {
        String(localized: "Replace \(count) files in “\(folder)”?", table: table, comment: "Export: Replace confirmation before the first byte (plural)")
    }

    static var replace: String { String(localized: "Replace", table: table, comment: "Export: confirm replacing files") }

    // MARK: Summary

    static func exported(_ count: Int, to folder: String) -> String {
        String(localized: "Exported \(count) photos to “\(folder)”.", table: table, comment: "Export summary headline (plural)")
    }

    static func notExported(_ count: Int) -> String {
        String(localized: "\(count) photos weren't exported.", table: table, comment: "Export summary: how many failed (plural)")
    }

    static func skipped(_ count: Int) -> String {
        String(localized: "\(count) skipped — already in the folder", table: table, comment: "Export summary: Skip left these out")
    }

    static var notExportedHeader: String { String(localized: "Not Exported", table: table, comment: "Export summary: list of photos that failed") }

    static func disconnected(_ drive: String, done: Int, total: Int) -> String {
        String(localized: "“\(drive)” was disconnected. \(done) of \(total) exported.", table: table, comment: "Export stopped: the drive was unplugged")
    }

    static func full(_ drive: String, done: Int, total: Int) -> String {
        String(localized: "“\(drive)” is full — \(done) of \(total) exported.", table: table, comment: "Export stopped: the destination is full")
    }

    static var cantWrite: String { String(localized: "You can't write to this folder.", table: table, comment: "Export stopped: no permission") }

    static func notEnoughSpace(_ folder: String, needed: Int64, free: Int64) -> String {
        let need = ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)
        let have = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
        return String(localized: "Not enough space in “\(folder)” — needs \(need), \(have) free.", table: table, comment: "Export: not enough room before the first byte")
    }

    static func freeOn(_ bytes: Int64, place: String) -> String {
        let free = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return String(localized: "\(free) free on \(place).", table: table, comment: "Export summary footer: free space on the destination")
    }

    static var done: String { String(localized: "Done", table: table, comment: "Export: close the summary") }
    static var exportRemaining: String { String(localized: "Export Remaining", table: table, comment: "Export: write what is not written yet") }
    static var retryFailed: String { String(localized: "Retry Failed", table: table, comment: "Export: try the failed photos again") }
    static var chooseAnotherFolder: String { String(localized: "Choose Another Folder", table: table, comment: "Export: pick another folder after a refusal") }
    static var ok: String { String(localized: "OK", table: table, comment: "Export: dismiss an alert") }
}
