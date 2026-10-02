import CoreImage
import Foundation
import ShotDexKit

/// What the verdict pass asks of the system (FS-03.04b §2), behind a
/// protocol so tests can play a decoder that refuses everything.
protocol RAWDecoderProbing: Sendable {
    /// `CIRAWFilter.supportedCameraModels`: 930 entries on iOS 26.5.
    func supportedCameraModels() -> [String]
    /// Tries one photo's RAW file if it is on the device: `true` decoded,
    /// `false` refused, `nil` when the file is only in iCloud. Never
    /// downloads (AC-12).
    func localFileDecodes(assetId: String) async -> Bool?
}

/// The iOS build a verdict belongs to, and the version the messages name.
struct OSRelease: Equatable, Sendable {
    /// "23F77" — what the verdict table keys on. A simulator reports its own
    /// here; `kern.osversion` would give the host Mac's.
    let build: String
    /// "26.5" — what "iOS 26.5 doesn't support…" says.
    let version: String

    static let current: OSRelease = {
        let info = ProcessInfo.processInfo
        let numbers = info.operatingSystemVersion
        let version = numbers.patchVersion == 0
            ? "\(numbers.majorVersion).\(numbers.minorVersion)"
            : "\(numbers.majorVersion).\(numbers.minorVersion).\(numbers.patchVersion)"
        return OSRelease(build: build(from: info.operatingSystemVersionString) ?? version, version: version)
    }()

    /// "Version 26.5 (Build 23F77)" → "23F77".
    static func build(from versionString: String) -> String? {
        guard let range = versionString.range(of: "Build ") else { return nil }
        let rest = versionString[range.upperBound...]
        let build = rest.prefix { $0 != ")" }.trimmingCharacters(in: .whitespaces)
        return build.isEmpty ? nil : build
    }
}
