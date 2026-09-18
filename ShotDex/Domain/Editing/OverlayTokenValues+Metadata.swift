import Foundation
import ShotDexKit

extension OverlayTokenValues {
    /// Built from the indexed row rather than from a fresh EXIF read: the values
    /// here have already been through the camera and lens normalizers, so a text
    /// overlay says "Canon EOS R6" where the raw tag says "Canon EOS R6 Body".
    init(
        metadata: PhotoMetadata?,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        self.init()
        guard let metadata else { return }
        camera = Self.trimmed(metadata.normalizedCameraModel ?? metadata.cameraModel)
        lens = Self.trimmed(metadata.normalizedLensModel ?? metadata.lensModel)
        focal = metadata.focalLength.flatMap(MetadataFormatter.focalLength)
        aperture = metadata.aperture.flatMap(MetadataFormatter.aperture)
        shutter = metadata.shutterSpeedDisplay
            ?? metadata.shutterSpeedSeconds.flatMap(MetadataFormatter.shutterSpeedCompact)
        iso = metadata.iso.flatMap(MetadataFormatter.iso)
        filename = Self.trimmed(metadata.originalFilename)
        if let value = metadata.creationDateValue {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            date = formatter.string(from: value)
        }
    }

}
