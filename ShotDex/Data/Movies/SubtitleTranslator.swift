import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Something that turns a block of cues into another language (FS-23.04
/// §2). nil from `translate` means the answer did not line up with the
/// cues — the translator retries, then goes cue by cue.
protocol SubtitleTranslationEngine: Sendable {
    var blockSize: Int { get }
    func translate(block: Range<Int>, of cues: [SubtitleCue], instructions: String) async throws -> [Int: String]?
}

/// A home server or a cloud service, through `AIProviderClient`.
struct ModelTranslationEngine: SubtitleTranslationEngine {
    let provider: AIProvider
    let key: String?
    var client = AIProviderClient()
    var blockSize: Int { SubtitleTranslationPlan.modelBlockSize }

    func translate(block: Range<Int>, of cues: [SubtitleCue], instructions: String) async throws -> [Int: String]? {
        let answer = try await client.complete(
            provider, key: key, system: instructions,
            prompt: SubtitleTranslationPlan.prompt(cues: cues, block: block), timeout: 120
        )
        return SubtitleTranslationPlan.parse(answer, block: block) ?? Self.single(answer, block: block)
    }

    /// One cue asked alone may come back without its number.
    static func single(_ answer: String, block: Range<Int>) -> [Int: String]? {
        guard block.count == 1 else { return nil }
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains("\n\n") else { return nil }
        return [block.lowerBound: text.replacingOccurrences(of: "⏎", with: "\n")]
    }
}

#if canImport(FoundationModels)
/// Apple Intelligence: a new session for every block (FS-23.04 §2 — the
/// window is 4,096 tokens).
@available(iOS 26.0, *)
struct AppleIntelligenceTranslationEngine: SubtitleTranslationEngine {
    var blockSize: Int { SubtitleTranslationPlan.onDeviceBlockSize }

    func translate(block: Range<Int>, of cues: [SubtitleCue], instructions: String) async throws -> [Int: String]? {
        let session = LanguageModelSession(instructions: instructions)
        let answer = try await session.respond(to: SubtitleTranslationPlan.prompt(cues: cues, block: block)).content
        return SubtitleTranslationPlan.parse(answer, block: block) ?? ModelTranslationEngine.single(answer, block: block)
    }
}
#endif

/// The loop (FS-23.04 §2): block by block from where it stopped; a block
/// whose answer does not line up is asked once more, then cue by cue; a
/// 429 waits 2, 8, then 30 s; any other error stops with the finished
/// blocks kept.
struct SubtitleTranslator: Sendable {
    static let rateLimitWaits: [Duration] = [.seconds(2), .seconds(8), .seconds(30)]
    var wait: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    /// - Parameters:
    ///   - translated: what earlier runs finished, by cue index.
    ///   - onBlock: called after each block with everything translated so
    ///     far, to keep it.
    func run(
        cues: [SubtitleCue],
        translated: [Int: String],
        engine: any SubtitleTranslationEngine,
        instructions: String,
        onBlock: @Sendable ([Int: String]) async throws -> Void
    ) async throws -> [Int: String] {
        var done = translated
        let start = (0..<cues.count).first { done[$0] == nil } ?? cues.count
        for block in SubtitleTranslationPlan.blocks(count: cues.count, from: start, size: engine.blockSize) {
            try Task.checkCancellation()
            var texts = try await ask(engine, block, cues, instructions)
            if texts == nil { texts = try await ask(engine, block, cues, instructions) }
            if let texts {
                done.merge(texts) { _, new in new }
            } else {
                for index in block {
                    try Task.checkCancellation()
                    // Cue by cue: a cue that still will not come back keeps its
                    // original words rather than stopping the run.
                    let texts = try await ask(engine, index..<(index + 1), cues, instructions)
                    done[index] = texts?[index] ?? cues[index].plainText
                }
            }
            try await onBlock(done)
        }
        return done
    }

    private func ask(_ engine: any SubtitleTranslationEngine, _ block: Range<Int>, _ cues: [SubtitleCue], _ instructions: String) async throws -> [Int: String]? {
        var waits = Self.rateLimitWaits[...]
        while true {
            do {
                return try await engine.translate(block: block, of: cues, instructions: instructions)
            } catch AIProviderClient.Failure.rateLimited {
                guard let pause = waits.popFirst() else { throw AIProviderClient.Failure.rateLimited }
                try await wait(pause)
            }
        }
    }
}

#if canImport(Translation)
import Translation

/// Apple Translation (FS-23.04 §2): batches of cues through the session the
/// view's `translationTask` hands over — valid only while that view is up,
/// so this one stops with the panel. Does not run on the Simulator.
@available(iOS 18.0, *)
final class AppleTranslationEngine: SubtitleTranslationEngine, @unchecked Sendable {
    private let session: TranslationSession
    var blockSize: Int { 50 }

    init(session: TranslationSession) {
        self.session = session
    }

    func translate(block: Range<Int>, of cues: [SubtitleCue], instructions: String) async throws -> [Int: String]? {
        let requests = block.map { TranslationSession.Request(sourceText: cues[$0].plainText, clientIdentifier: String($0)) }
        let responses = try await session.translations(from: requests)
        var found: [Int: String] = [:]
        for response in responses {
            guard let index = response.clientIdentifier.flatMap(Int.init) else { continue }
            found[index] = response.targetText
        }
        return found.count == block.count ? found : nil
    }
}
#endif
