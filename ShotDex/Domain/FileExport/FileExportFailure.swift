import Foundation

/// What went wrong in an export, and how far it reaches (FS-03.07c §3): a
/// problem with **one photo** leaves the batch running; a problem with the
/// **destination** stops it, because every later photo would fail the same
/// way — the rule of FS-15.02 §4.
enum FileExportFailure: Error, Equatable, Sendable, Hashable {
    // One photo.
    /// The file is there but nothing can read it.
    case unreadable
    /// A RAW the system decoder can't read yet, with no JPEG beside it.
    case unsupportedRAW
    /// Taken out of the limited selection, or deleted, mid-batch.
    case noLongerAvailable
    /// The iCloud download did not finish (FS-02.06 §5 step 4).
    case downloadFailed
    /// Over 4 GB, to a drive formatted FAT32.
    case tooLargeForDrive
    /// The render or encode failed.
    case renderFailed
    /// The stamp step refused this photo; it is left out, never written
    /// without its stamp (FS-05.04).
    case stampFailed

    // The destination.
    /// The drive was unplugged or the folder went away.
    case disconnected
    case full
    case permissionDenied
    /// Not enough room before the first byte: nothing was written.
    case notEnoughSpace(needed: Int64, free: Int64)

    /// Whether the rest of the batch stops.
    var stopsBatch: Bool {
        switch self {
        case .unreadable, .unsupportedRAW, .noLongerAvailable, .downloadFailed, .tooLargeForDrive, .renderFailed, .stampFailed:
            false
        case .disconnected, .full, .permissionDenied, .notEnoughSpace:
            true
        }
    }

    /// The line under a photo's name in the summary.
    var photoReason: String {
        switch self {
        case .unsupportedRAW:
            String(localized: "iOS can't read this RAW yet", table: ExportCopy.table, comment: "Export summary: a RAW the decoder can't read")
        case .noLongerAvailable:
            String(localized: "ShotDex can't read this photo anymore.", table: ExportCopy.table, comment: "Export summary: photo removed from the limited selection")
        case .downloadFailed:
            String(localized: "Couldn't download from iCloud.", table: ExportCopy.table, comment: "Export summary: iCloud download failed")
        case .tooLargeForDrive:
            String(localized: "Too large for this drive's format.", table: ExportCopy.table, comment: "Export summary: over 4 GB to FAT32")
        case .stampFailed:
            String(localized: "Couldn't add the watermark.", table: ExportCopy.table, comment: "Export summary: the stamp step failed")
        case .renderFailed, .unreadable:
            String(localized: "ShotDex couldn't read this photo.", table: ExportCopy.table, comment: "Export summary: unreadable photo")
        case .disconnected, .full, .permissionDenied, .notEnoughSpace:
            ""
        }
    }

    /// Sorts any error thrown while writing into the one the user is told
    /// about. Cocoa and POSIX codes for a missing volume, a full disk, no
    /// permission, a file too large.
    static func classify(_ error: Error) -> FileExportFailure? {
        if let failure = error as? FileExportFailure { return failure }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileWriteOutOfSpaceError: return .full
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError: return .permissionDenied
            case NSFileWriteVolumeReadOnlyError: return .permissionDenied
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return .disconnected
            case NSFileWriteFileExistsError: return nil
            default: break
            }
        }
        if nsError.domain == NSPOSIXErrorDomain {
            switch Int32(nsError.code) {
            case ENOSPC, EDQUOT: return .full
            case EACCES, EPERM, EROFS: return .permissionDenied
            case ENOENT, ENXIO, ENODEV, EIO, ENOTDIR: return .disconnected
            case EFBIG: return .tooLargeForDrive
            default: break
            }
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error { return classify(underlying) }
        return nil
    }
}
