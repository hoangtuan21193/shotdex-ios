import Foundation
import ShotDexKit

/// What the user is told about a RAW this iOS build can't read (FS-03.04b
/// §3): one sentence naming the camera and the iOS version, one saying what
/// to do. The version comes from the system, never written in.
struct UnsupportedRAWMessage: Equatable, Sendable {
    enum Subject: Equatable, Sendable {
        /// "Sony ILCE-7M5", from the index or the file's header.
        case camera(String)
        /// No camera in EXIF: the file's extension, "ARW".
        case fileExtension(String)
        /// A DNG: the decoder reads every DNG it can, so the file itself is
        /// at fault — convert it again, or edit it elsewhere (AC-7).
        case dng
    }

    let subject: Subject
    /// "27.0".
    let iOSVersion: String

    /// The camera's name when there is one, else the extension of
    /// `filename`. A RAW with neither is still called a RAW.
    static func make(cameraName: String?, filename: String?, iOSVersion: String) -> UnsupportedRAWMessage {
        let ext = ((filename ?? "") as NSString).pathExtension.uppercased()
        if ext == "DNG" {
            return UnsupportedRAWMessage(subject: .dng, iOSVersion: iOSVersion)
        }
        if let cameraName = cameraName?.trimmingCharacters(in: .whitespaces), !cameraName.isEmpty {
            return UnsupportedRAWMessage(subject: .camera(cameraName), iOSVersion: iOSVersion)
        }
        return UnsupportedRAWMessage(subject: .fileExtension(ext.isEmpty ? "RAW" : ext), iOSVersion: iOSVersion)
    }

    var title: String {
        String(localized: "Can't Edit This RAW", comment: "Alert title: iOS can't decode this RAW photo (FS-03.04b)")
    }

    /// The two sentences.
    var text: String {
        switch subject {
        case .camera(let name):
            String(
                localized: "iOS \(iOSVersion) doesn't support RAW files from the \(name) yet. Convert the file to DNG with Adobe DNG Converter, or wait for an iOS update that adds this camera.",
                comment: "Unsupported RAW: first the iOS version, then the camera's name"
            )
        case .fileExtension(let ext):
            String(
                localized: "iOS \(iOSVersion) doesn't support RAW files like this .\(ext) yet. Convert the file to DNG with Adobe DNG Converter, or wait for an iOS update that adds this camera.",
                comment: "Unsupported RAW with no camera name in the file: first the iOS version, then the file extension such as ARW"
            )
        case .dng:
            String(
                localized: "iOS \(iOSVersion) can't read this DNG file. Convert the original again with the latest Adobe DNG Converter, or share it to edit on a computer.",
                comment: "A DNG file iOS can't decode: the iOS version"
            )
        }
    }

    /// A DNG offers Share Original next to OK, so the file has somewhere to
    /// go (NF-04: every error has a way out).
    var offersShareOriginal: Bool { subject == .dng }
}

/// A RAW the decoder refused, carrying what to tell the user — so Resize's
/// failure line and the editor's alert say the same thing (AC-3, AC-14).
struct UnsupportedRAWError: LocalizedError, Equatable, Sendable {
    let message: UnsupportedRAWMessage

    var errorDescription: String? { message.text }

    /// The decoder's refusal in either form: the kit's bare error, or this.
    static func matches(_ error: Error) -> Bool {
        error is UnsupportedRAWError || (error as? PhotoEditingError) == .unsupportedRAW
    }
}
