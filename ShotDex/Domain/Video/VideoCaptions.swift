import Foundation
import ShotDexKit

/// Auto captions (FS-12.14): one lane of timed captions, recognised from the
/// clips' own speech on the device, anchored to clip and **source** time so a
/// trim, a move or a speed change carries every caption with its words.
///
/// The project keeps at most one lane (`VideoProjectRecipe.captions`): one
/// language, one style for the whole lane (§2). Everything here is value
/// types; recognising, laying out and drawing live elsewhere.

/// One recognised word, in the clip's source seconds.
struct CaptionWord: Codable, Equatable, Sendable {
    var text: String
    var start: Double
    var end: Double
}

/// One caption block (§4): a line of at most 32 characters and 3.0 s, tied to
/// the clip it was heard in and to where in that clip's source it was said.
struct CaptionCue: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    /// The clip whose sound this was. A cue whose clip is gone is not shown.
    var clipID: UUID
    /// Source seconds within the clip's media — not timeline seconds.
    var sourceStart: Double
    var sourceEnd: Double
    var text: String
    /// When each word was said, as recognised. Nil once the text is edited
    /// by hand: the words no longer match the times (§5), so Word by Word
    /// spreads them evenly instead.
    var words: [CaptionWord]?
    var isEdited: Bool

    init(
        id: UUID = UUID(),
        clipID: UUID,
        sourceStart: Double,
        sourceEnd: Double,
        text: String,
        words: [CaptionWord]? = nil,
        isEdited: Bool = false
    ) {
        self.id = id
        self.clipID = clipID
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
        self.text = text
        self.words = words
        self.isEdited = isEdited
    }

    var sourceDuration: Double { max(0, sourceEnd - sourceStart) }
}

/// Clean · Box · Outline · Word by Word (§5) — the lane's, never a cue's.
enum CaptionStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case clean, box, outline, wordByWord

    var id: String { rawValue }
}

/// Where the line's centre sits: 85 %, 50 % or 15 % of the frame's height.
enum CaptionPosition: String, CaseIterable, Identifiable, Codable, Sendable {
    case bottom, middle, top

    var id: String { rawValue }

    /// The line's centre as a fraction of the frame height, from the top.
    var centreY: Double {
        switch self {
        case .bottom: 0.85
        case .middle: 0.5
        case .top: 0.15
        }
    }
}

/// How far recognition got (§8): the clips it set out to read, the ones it
/// has finished, and — when it stopped before the end — the percentage it
/// stopped at, so a reopened project can say "Captions stopped at 58%" and
/// Continue reads only the clips not done yet.
struct CaptionRecognitionState: Codable, Equatable, Sendable {
    /// Every clip this run reads, in timeline order.
    var plannedClipIDs: [UUID] = []
    /// The clips whose cues are in the lane.
    var finishedClipIDs: [UUID] = []
    /// Set when the run stopped before finishing (Back, the app leaving).
    var stoppedAtPercent: Int?

    var remainingClipIDs: [UUID] {
        plannedClipIDs.filter { !finishedClipIDs.contains($0) }
    }

    var isComplete: Bool { remainingClipIDs.isEmpty }
}

/// The project's one caption lane, C1.
struct VideoCaptionLane: Codable, Equatable, Sendable {
    /// BCP-47, as the recogniser names it: "en-US".
    var language: String = VideoCaptionLane.defaultLanguage
    var style: CaptionStyle = .clean
    /// Text height as a percentage of the export frame's short edge, 3–12.
    var sizePercent: Double = VideoCaptionLane.defaultSizePercent
    var position: CaptionPosition = .bottom
    /// On: drawn into every exported frame. Off: written as a subtitle track.
    var burnsIn = true
    var cues: [CaptionCue] = []
    var recognition = CaptionRecognitionState()

    static let sizeRange: ClosedRange<Double> = 3...12
    static let defaultSizePercent: Double = 6
    /// English (US) when the device's language has no on-device model (§4).
    static let defaultLanguage = "en-US"
}

// MARK: - Lenient decoding (FS-12.14 §7)

// A cue that will not read costs that cue; a style or position this build
// does not know falls back to its default; an unknown language stays as it
// is (the lane opens and edits; only Language says it is not on the device).

extension CaptionCue {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? container.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            clipID: try container.decode(UUID.self, forKey: .clipID),
            sourceStart: try container.decode(Double.self, forKey: .sourceStart),
            sourceEnd: try container.decode(Double.self, forKey: .sourceEnd),
            text: value(.text, ""),
            words: (try? container.decodeLossyArrayIfPresent(CaptionWord.self, forKey: .words)) ?? nil,
            isEdited: value(.isEdited, false)
        )
    }
}

extension CaptionRecognitionState {
    init(from decoder: any Decoder) throws {
        self.init()
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        plannedClipIDs = ((try? container.decodeLossyArrayIfPresent(UUID.self, forKey: .plannedClipIDs)) ?? nil) ?? []
        finishedClipIDs = ((try? container.decodeLossyArrayIfPresent(UUID.self, forKey: .finishedClipIDs)) ?? nil) ?? []
        stoppedAtPercent = (try? container.decodeIfPresent(Int.self, forKey: .stoppedAtPercent)) ?? nil
    }
}

extension VideoCaptionLane {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? container.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        self.init()
        language = value(.language, Self.defaultLanguage)
        style = value(.style, CaptionStyle.clean)
        sizePercent = min(max(value(.sizePercent, Self.defaultSizePercent), Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        position = value(.position, CaptionPosition.bottom)
        burnsIn = value(.burnsIn, true)
        cues = ((try? container.decodeLossyArrayIfPresent(CaptionCue.self, forKey: .cues)) ?? nil) ?? []
        recognition = value(.recognition, CaptionRecognitionState())
    }
}
