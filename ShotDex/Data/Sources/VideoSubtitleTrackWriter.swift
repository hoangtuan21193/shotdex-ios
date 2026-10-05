import AVFoundation
import CoreMedia
import Foundation

/// Captions as a soft subtitle track (FS-12.14 §6, plan Q3): 3GPP timed
/// text (`tx3g`) in the `.mp4` the export writes — one sample per cue, the
/// lane's language on the track, no style (a player draws subtitles its own
/// way). Players with a CC button can show it; Photos, Instagram and TikTok
/// ignore it, which the switch's note says beforehand.
enum VideoSubtitleTrackWriter {
    /// One caption: timeline seconds and words.
    struct Cue: Equatable, Sendable {
        let start: Double
        let end: Double
        let text: String
    }

    struct Track: Sendable {
        let cues: [Cue]
        /// BCP-47 — "en-US".
        let language: String
    }

    /// The lane as a subtitle track, when it is not burnt in.
    static func track(_ lane: VideoCaptionLane?, recipe: VideoProjectRecipe) -> Track? {
        guard let lane, !lane.burnsIn else { return nil }
        let cues = CaptionLayout.cues(lane, in: recipe).map { Cue(start: $0.start, end: $0.end, text: $0.text) }
        guard !cues.isEmpty else { return nil }
        return Track(cues: cues, language: lane.language)
    }

    /// The writer input for `track`, or nil when the writer will not take
    /// timed text (the export then goes on without it).
    static func input(for track: Track, writer: AVAssetWriter) -> AVAssetWriterInput? {
        guard let format = formatDescription() else { return nil }
        let input = AVAssetWriterInput(mediaType: .text, outputSettings: nil, sourceFormatHint: format)
        input.expectsMediaDataInRealTime = false
        let language = CaptionLanguages.languageCode(track.language)
        input.languageCode = Locale.LanguageCode(language).identifier(.alpha3) ?? language
        input.extendedLanguageTag = CaptionLanguages.normalized(track.language)
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        return input
    }

    /// One sample buffer per cue, in time order: the tx3g text sample —
    /// a 16-bit big-endian length and the UTF-8 words. A timed-text track
    /// plays its samples back to back, so the time between two cues is an
    /// empty sample (length 0): nothing on screen, and nothing for a count
    /// of captions to see.
    static func samples(for track: Track) -> [CMSampleBuffer] {
        guard let format = formatDescription() else { return [] }
        var buffers: [CMSampleBuffer] = []
        var cursor = 0.0
        for cue in track.cues.sorted(by: { $0.start < $1.start }) {
            let start = max(cue.start, cursor)
            if start - cursor > 0.001, let gap = sample(text: "", start: cursor, duration: start - cursor, format: format) {
                buffers.append(gap)
            }
            let end = max(cue.end, start + 0.04)
            if let buffer = sample(text: cue.text, start: start, duration: end - start, format: format) {
                buffers.append(buffer)
            }
            cursor = end
        }
        return buffers
    }

    static func sample(text: String, start: Double, duration: Double, format: CMFormatDescription) -> CMSampleBuffer? {
        let utf8 = Array(text.utf8.prefix(Int(UInt16.max)))
        var bytes: [UInt8] = [UInt8(utf8.count >> 8), UInt8(utf8.count & 0xFF)]
        bytes.append(contentsOf: utf8)
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: bytes.count, flags: 0, blockBufferOut: &block
        ) == kCMBlockBufferNoErr, let block else { return nil }
        guard CMBlockBufferReplaceDataBytes(with: bytes, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes.count) == kCMBlockBufferNoErr
        else { return nil }
        var timing = CMSampleTimingInfo(
            duration: CMTime(seconds: duration, preferredTimescale: 600),
            presentationTimeStamp: CMTime(seconds: start, preferredTimescale: 600),
            decodeTimeStamp: .invalid
        )
        var size = bytes.count
        var buffer: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &buffer
        ) == noErr else { return nil }
        return buffer
    }

    /// The 3GPP TextSampleEntry (TS 26.245 §5.16): white text, bottom
    /// centred, no box, one font — what a player falls back to.
    static func formatDescription() -> CMFormatDescription? {
        var entry = Data()
        func u8(_ value: UInt8) { entry.append(value) }
        func u16(_ value: UInt16) { entry.append(contentsOf: [UInt8(value >> 8), UInt8(value & 0xFF)]) }
        func u32(_ value: UInt32) { entry.append(contentsOf: withUnsafeBytes(of: value.bigEndian, Array.init)) }
        let fontName = Array("Sans-Serif".utf8)
        let ftabSize = UInt32(13 + fontName.count)
        // size, type, reserved, data ref, flags, justification ×2, colour,
        // box, style record — then the font table.
        let headerSize: UInt32 = 46
        let size = headerSize + ftabSize
        u32(size)
        entry.append(contentsOf: Array("tx3g".utf8))
        entry.append(contentsOf: [0, 0, 0, 0, 0, 0])      // reserved
        u16(1)                                           // data reference index
        u32(0)                                           // display flags
        u8(1)                                            // horizontal: centre
        u8(0xFF)                                         // vertical: bottom (-1)
        entry.append(contentsOf: [0, 0, 0, 0])           // background RGBA
        u16(0); u16(0); u16(0); u16(0)                   // default text box
        u16(0); u16(0)                                   // style: start, end char
        u16(1)                                           // font id
        u8(0)                                            // face style flags
        u8(18)                                           // font size
        entry.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF]) // text RGBA
        u32(ftabSize)
        entry.append(contentsOf: Array("ftab".utf8))
        u16(1)                                           // entry count
        u16(1)                                           // font id
        u8(UInt8(fontName.count))
        entry.append(contentsOf: fontName)
        var description: CMTextFormatDescription?
        let status = entry.withUnsafeBytes { raw in
            CMTextFormatDescriptionCreateFromBigEndianTextDescriptionData(
                allocator: kCFAllocatorDefault,
                bigEndianTextDescriptionData: raw.bindMemory(to: UInt8.self).baseAddress!,
                size: entry.count,
                flavor: nil,
                mediaType: kCMMediaType_Text,
                formatDescriptionOut: &description
            )
        }
        return status == noErr ? description : nil
    }
}
