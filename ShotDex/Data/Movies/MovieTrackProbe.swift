import AVFoundation
import Foundation

/// A movie's audio tracks before it plays (FS-23.08 §4): Matroska from its
/// header (a few kilobytes, streamed or on the device), MP4/MOV on the
/// device through AVFoundation. nil: they show once the movie plays.
enum MovieTrackProbe {
    static func audioTracks(fileName: String, source: any MovieByteSource, localURL: URL?) async -> [MovieAudioTrack]? {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if ["mkv", "mk3d", "mka", "webm"].contains(ext) {
            let reader = MatroskaSubtitleReader(source: source)
            guard (try? await reader.readTracks()) != nil else { return nil }
            return reader.audioTracks
        }
        if ["mp4", "m4v", "mov"].contains(ext), let localURL {
            return try? await movAudioTracks(AVURLAsset(url: localURL))
        }
        return nil
    }

    private static func movAudioTracks(_ asset: AVURLAsset) async throws -> [MovieAudioTrack] {
        var found: [MovieAudioTrack] = []
        for (index, track) in try await asset.loadTracks(withMediaType: .audio).enumerated() {
            let language = try? await track.load(.languageCode)
            let format = try? await track.load(.formatDescriptions).first
            let fourCC = format.map { CMFormatDescriptionGetMediaSubType($0) }
            let channels = format.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame }
            found.append(MovieAudioTrack(
                id: MovieAudioTrack.fileId(index), language: language, name: nil,
                codec: fourCC.map(Self.fourCC), channels: channels.map(Int.init), isDefault: index == 0
            ))
        }
        return found
    }

    /// `mp4a` → `mp4a`, `ac-3` → `ac-3`: the label maps them.
    private static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [UInt8(code >> 24 & 0xFF), UInt8(code >> 16 & 0xFF), UInt8(code >> 8 & 0xFF), UInt8(code & 0xFF)]
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }
}
