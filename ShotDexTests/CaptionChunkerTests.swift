import Foundation
import Testing
@testable import ShotDex

/// FS-12.14 §4: recognised words into blocks of one line — at most 32
/// characters and 3.0 s, broken at a pause of 0.4 s or after punctuation.
struct CaptionChunkerTests {
    static let clip = UUID()

    /// Clip 2's twelve words (AC-5), with the times they were said in the
    /// clip's source: "The road to Vík starts right here. Listen to that
    /// water, it never stops."
    static let twelveWords: [CaptionWord] = [
        .init(text: "The", start: 1.20, end: 1.38),
        .init(text: "road", start: 1.40, end: 1.72),
        .init(text: "to", start: 1.74, end: 1.86),
        .init(text: "Vík", start: 1.90, end: 2.40),
        .init(text: "starts", start: 3.00, end: 3.38),
        .init(text: "right", start: 3.40, end: 3.70),
        .init(text: "here.", start: 3.72, end: 4.40),
        .init(text: "Listen", start: 4.62, end: 4.98),
        .init(text: "to", start: 5.00, end: 5.10),
        .init(text: "that", start: 5.12, end: 5.30),
        .init(text: "water,", start: 5.32, end: 5.80),
        .init(text: "it never stops.", start: 5.84, end: 6.20),
    ]

    /// AC-5: every block within 32 characters and 3.0 s.
    @Test func blocksStayWithin32CharsAnd3s() {
        let cues = CaptionChunker.cues(from: Self.twelveWords, clipID: Self.clip)
        #expect(!cues.isEmpty)
        for cue in cues {
            #expect(cue.text.count <= 32, "\(cue.text)")
            #expect(cue.sourceDuration <= 3.0 + 1e-9, "\(cue.text) lasts \(cue.sourceDuration)")
        }
        // A long run with no pause and no punctuation still breaks.
        let run = (0..<20).map { CaptionWord(text: "word\($0)", start: Double($0) * 0.3, end: Double($0) * 0.3 + 0.28) }
        for cue in CaptionChunker.cues(from: run, clipID: Self.clip) {
            #expect(cue.text.count <= 32)
            #expect(cue.sourceDuration <= 3.0 + 1e-9)
        }
    }

    /// A pause of 0.4 s or more, or punctuation, ends a block.
    @Test func breaksAtPauseOrPunctuation() {
        let cues = CaptionChunker.cues(from: Self.twelveWords, clipID: Self.clip)
        #expect(cues.map(\.text) == [
            "The road to Vík",
            "starts right here.",
            "Listen to that water,",
            "it never stops.",
        ])
        // 0.39 s is no pause; 0.40 s is.
        let close = [CaptionWord(text: "a", start: 0, end: 0.5), CaptionWord(text: "b", start: 0.89, end: 1.2)]
        #expect(CaptionChunker.cues(from: close, clipID: Self.clip).count == 1)
        let apart = [CaptionWord(text: "a", start: 0, end: 0.5), CaptionWord(text: "b", start: 0.9, end: 1.2)]
        #expect(CaptionChunker.cues(from: apart, clipID: Self.clip).count == 2)
    }

    /// AC-5: a block starts within 0.3 s of its first word — here, exactly.
    @Test func startWithin0_3sOfFirstWord() {
        let cues = CaptionChunker.cues(from: Self.twelveWords, clipID: Self.clip)
        for cue in cues {
            let first = try! #require(cue.words?.first)
            #expect(abs(cue.sourceStart - first.start) <= 0.3)
            #expect(cue.clipID == Self.clip)
            #expect(cue.isEdited == false)
        }
        #expect(cues[1].sourceStart == 3.0 && cues[1].sourceEnd == 4.4)
    }

    /// AC-5: blocks in time order, named in that order — even from words
    /// that arrive out of order.
    @Test func namesInTimeOrder() {
        let cues = CaptionChunker.cues(from: Self.twelveWords.reversed(), clipID: Self.clip)
        #expect(cues.map(\.sourceStart) == cues.map(\.sourceStart).sorted())
        #expect(CaptionChunker.name(at: 0) == "Caption 1")
        #expect(CaptionChunker.name(at: 1) == "Caption 2")
    }
}

/// FS-12.14 §7: the lane reads leniently — one broken cue costs that cue.
struct VideoCaptionDecodingTests {
    private func lane(json: String) throws -> VideoCaptionLane {
        try JSONDecoder().decode(VideoCaptionLane.self, from: Data(json.utf8))
    }

    @Test func oneBrokenCueLosesOnlyItself() throws {
        let clip = UUID()
        var lane = VideoCaptionLane()
        lane.cues = [
            CaptionCue(clipID: clip, sourceStart: 1, sourceEnd: 2, text: "one"),
            CaptionCue(clipID: clip, sourceStart: 3, sourceEnd: 4, text: "two"),
            CaptionCue(clipID: clip, sourceStart: 5, sourceEnd: 6, text: "three"),
        ]
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(lane)) as! [String: Any]
        var cues = object["cues"] as! [[String: Any]]
        cues[1]["sourceStart"] = "not a number"
        object["cues"] = cues
        let decoded = try JSONDecoder().decode(VideoCaptionLane.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.cues.map(\.text) == ["one", "three"])

        // And inside a recipe: the project keeps its clips and its lane.
        var recipe = VideoProjectRecipe(clips: [VideoClip(assetID: "a", kind: .video, id: clip)])
        recipe.captions = lane
        var recipeObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(recipe)) as! [String: Any]
        var captions = recipeObject["captions"] as! [String: Any]
        captions["cues"] = cues
        recipeObject["captions"] = captions
        let reopened = try JSONDecoder().decode(VideoProjectRecipe.self, from: JSONSerialization.data(withJSONObject: recipeObject))
        #expect(reopened.clips.count == 1)
        #expect(reopened.captions?.cues.count == 2)
    }

    @Test func unknownStyleFallsBackToClean() throws {
        let decoded = try lane(json: #"{"language":"xx-YY","style":"neon","position":"sideways","sizePercent":40,"burnsIn":false,"cues":[]}"#)
        #expect(decoded.style == .clean)
        #expect(decoded.position == .bottom)
        #expect(decoded.sizePercent == 12)
        #expect(decoded.burnsIn == false)
        // A language this device cannot recognise stays: the lane still opens.
        #expect(decoded.language == "xx-YY")
    }

    @Test func aRecipeWithoutALaneHasNone() throws {
        let recipe = VideoProjectRecipe(clips: [])
        let decoded = try JSONDecoder().decode(VideoProjectRecipe.self, from: JSONEncoder().encode(recipe))
        #expect(decoded.captions == nil)
    }
}
