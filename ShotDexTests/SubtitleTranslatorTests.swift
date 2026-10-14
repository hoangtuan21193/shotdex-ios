import Foundation
import Testing
@testable import ShotDex

/// FS-23.04: translating a subtitle block by block with a fake AI.
@Suite @MainActor struct SubtitleTranslatorTests {
    /// Answers `n|Dòng …` for every cue it is given — or, for the blocks
    /// it is told to, one line short.
    final class FakeEngine: SubtitleTranslationEngine, @unchecked Sendable {
        let blockSize: Int
        var shortBlocks: Set<Int> = []
        var rateLimitsLeft = 0
        private let lock = NSLock()
        private(set) var asked: [Range<Int>] = []

        init(blockSize: Int = 40) { self.blockSize = blockSize }

        func translate(block: Range<Int>, of cues: [SubtitleCue], instructions: String) async throws -> [Int: String]? {
            let limited = lock.withLock { () -> Bool in
                asked.append(block)
                if rateLimitsLeft > 0 { rateLimitsLeft -= 1; return true }
                return false
            }
            if limited { throw AIProviderClient.Failure.rateLimited }
            let prompt = SubtitleTranslationPlan.prompt(cues: cues, block: block)
            var lines = prompt.components(separatedBy: "\n").filter { $0.contains("|") }
                .map { $0.replacingOccurrences(of: "Line", with: "Dòng") }
            if block.count > 1, shortBlocks.contains(block.lowerBound / blockSize) { lines.removeLast() }
            return SubtitleTranslationPlan.parse(lines.joined(separator: "\n"), block: block)
        }
    }

    private func document(_ count: Int) -> SubtitleDocument {
        SubtitleDocument(cues: (0..<count).map { index in
            SubtitleCue(startMs: Int64(index) * 2_000 + 137, endMs: Int64(index) * 2_000 + 1_789, lines: [[SubtitleRun(text: "Line \(index + 1)")], [SubtitleRun(text: "second")]])
        })
    }

    private struct Fixture {
        let store: MovieStore
        let files: MovieFileStore
        let movie: Movie
        let english: MovieSubtitle
        let translations: MovieTranslations
    }

    private func fixture() throws -> Fixture {
        let store = MovieStore(database: try AppDatabase.makeEmpty(), plexTokens: InMemoryPasswordStore())
        let files = MovieFileStore(root: FileManager.default.temporaryDirectory.appending(path: "translate-\(UUID().uuidString)"))
        try files.prepare()
        let movie = Movie(sourceId: nil, title: "Dune", originalFileName: "Dune.mkv", byteCount: 1, state: .onDevice, addedAt: 0)
        try store.add(movie)
        let english = MovieSubtitle(movieId: movie.id, language: "en", origin: .sidecar, format: .srt, fileName: "en.srt")
        try store.saveSubtitle(english)
        let translations = MovieTranslations(store: store, files: files)
        translations.translator = SubtitleTranslator(wait: { _ in })
        return Fixture(store: store, files: files, movie: movie, english: english, translations: translations)
    }

    private func finish(_ f: Fixture) async throws -> String {
        for _ in 0..<400 {
            if case .finished(let id) = f.translations.runs[f.movie.id]?.state { return id }
            if case .failed(let problem) = f.translations.runs[f.movie.id]?.state { Issue.record("failed: \(problem)"); return "" }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("never finished")
        return ""
    }

    /// AC-29: 1,380 cues in, 1,380 out, every start and end the original's.
    @Test func keepsTimingAndCount() async throws {
        let f = try fixture()
        let original = document(1_380)
        f.translations.start(movie: f.movie, from: f.english, document: original, toLanguage: "vi", using: .provider("p1"), serviceName: "Anthropic", engine: FakeEngine())
        let id = try await finish(f)
        let subtitle = try #require(try f.store.subtitles(movieId: f.movie.id).first { $0.id == id })
        #expect(subtitle.origin == .translated)
        #expect(subtitle.language == "vi")
        #expect(subtitle.translatedFromId == f.english.id)
        #expect(subtitle.translationProviderId == "provider:p1")
        let data = try Data(contentsOf: f.files.directory(for: f.movie.id).appending(path: subtitle.fileName))
        let result = SubtitleParser.parse(String(decoding: data, as: UTF8.self), format: .srt)
        #expect(result.cues.count == 1_380)
        #expect(zip(result.cues, original.cues).allSatisfy { $0.startMs == $1.startMs && $0.endMs == $1.endMs })
        #expect(result.cues[411].plainText == "Dòng 412\nsecond")
        #expect(try f.store.translationJobs(movieId: f.movie.id).isEmpty)
    }

    /// AC-30: block 3 comes back a line short — asked once more, then cue by
    /// cue; still 1,380 cues.
    @Test func wrongCountFallsBackPerCue() async throws {
        let engine = FakeEngine()
        engine.shortBlocks = [2]
        let done = try await SubtitleTranslator(wait: { _ in }).run(
            cues: document(1_380).cues, translated: [:], engine: engine, instructions: ""
        ) { _ in }
        #expect(done.count == 1_380)
        #expect(engine.asked.filter { $0 == 80..<120 }.count == 2)
        #expect(engine.asked.filter { $0.count == 1 }.count == 40)
        #expect(done[85] == "Dòng 86\nsecond")
    }

    /// AC-31: cancelled at 412 of 1,380; Translate offers to continue, and
    /// only cues from 413 are sent.
    @Test func resumesAfterCancel() async throws {
        let f = try fixture()
        let original = document(1_380)
        let slow = FakeEngine(blockSize: 4)
        f.translations.start(movie: f.movie, from: f.english, document: original, toLanguage: "vi", using: .provider("p1"), serviceName: "Anthropic", engine: slow)
        while (f.translations.runs[f.movie.id]?.done ?? 0) < 412 { try await Task.sleep(for: .milliseconds(1)) }
        f.translations.cancel(movieId: f.movie.id)
        try await Task.sleep(for: .milliseconds(50))
        let pending = try #require(f.translations.pending(movieId: f.movie.id, fromId: f.english.id, toLanguage: "vi"))
        #expect(pending.total == 1_380)
        #expect(pending.done >= 412)

        let rest = FakeEngine()
        f.translations.start(movie: f.movie, from: f.english, document: original, toLanguage: "vi", using: .provider("p1"), serviceName: "Anthropic", engine: rest)
        let id = try await finish(f)
        #expect(rest.asked.first?.lowerBound == pending.done)
        let subtitle = try #require(try f.store.subtitles(movieId: f.movie.id).first { $0.id == id })
        let data = try Data(contentsOf: f.files.directory(for: f.movie.id).appending(path: subtitle.fileName))
        #expect(SubtitleParser.parse(String(decoding: data, as: UTF8.self), format: .srt).cues.count == 1_380)
    }

    /// A 429 waits 2 s, then 8 s, and carries on.
    @Test func rateLimitWaitsAndRetries() async throws {
        let engine = FakeEngine()
        engine.rateLimitsLeft = 2
        let waited = WaitLog()
        let done = try await SubtitleTranslator(wait: { await waited.add($0) }).run(
            cues: document(10).cues, translated: [:], engine: engine, instructions: ""
        ) { _ in }
        #expect(done.count == 10)
        #expect(await waited.all == [.seconds(2), .seconds(8)])
    }

    actor WaitLog {
        var all: [Duration] = []
        func add(_ duration: Duration) { all.append(duration) }
    }

    /// FS-23.04 §4: the error titles.
    @Test func problemsSayWhatToDo() {
        let key = MovieTranslations.problem(AIProviderClient.Failure.rejectedKey, serviceName: "Anthropic")
        #expect(key.title == "Anthropic Rejected the API Key")
        #expect(key.opensSettings)
        let offline = MovieTranslations.problem(AIProviderClient.Failure.unreachable("Anthropic"), serviceName: "Anthropic")
        #expect(offline.title == "Can't Reach Anthropic")
        let quota = MovieTranslations.problem(AIProviderClient.Failure.service("Your credit balance is too low."), serviceName: "Anthropic")
        #expect(quota.message == "Your credit balance is too low.")
    }

    /// The plan: numbered lines in, numbered lines out, line breaks kept.
    @Test func planReadsNumberedAnswers() {
        let cues = document(3).cues
        let prompt = SubtitleTranslationPlan.prompt(cues: cues, block: 1..<3)
        #expect(prompt.contains("Context:\n- Line 1 ⏎ second"))
        #expect(prompt.contains("1|Line 2 ⏎ second"))
        let parsed = SubtitleTranslationPlan.parse("1| Dòng 2 ⏎ hai\n2|Dòng 3", block: 1..<3)
        #expect(parsed == [1: "Dòng 2\nhai", 2: "Dòng 3"])
        #expect(SubtitleTranslationPlan.parse("1|Dòng 2", block: 1..<3) == nil)
        #expect(SubtitleTranslationPlan.blocks(count: 85, from: 0, size: 40) == [0..<40, 40..<80, 80..<85])
    }

    private func service(_ providers: [AIProvider], onDevice: AIChoice.OnDevice) throws -> TranslationService {
        let store = AIProviderStore(database: try AppDatabase.makeEmpty(), keys: InMemoryPasswordStore())
        for provider in providers { try store.save(provider, key: provider.kind == .homeServer ? nil : "sk-test-7Qx2") }
        return TranslationService(providers: store, defaults: UserDefaults(suiteName: "tr-\(UUID().uuidString)")!, onDevice: onDevice)
    }

    /// AC-32: Using lists what the device has, then home servers, then cloud;
    /// with nothing at all the sheet can only offer Set Up AI.
    @Test func usingListsWhatCanTranslate() throws {
        let claude = AIProvider(id: "c1", kind: .claude, name: "Claude", model: "m", createdAt: 1)
        let home = AIProvider(id: "h1", kind: .homeServer, name: "Mac Studio", address: "http://10.0.0.2:11434", model: "m", createdAt: 2)
        let simulator = try service([claude, home], onDevice: .init(appleTranslation: true, appleIntelligence: false))
        #expect(simulator.usingOptions() == [.appleTranslation, .provider("h1"), .provider("c1")])
        #expect(simulator.defaultUsing() == .appleTranslation)
        simulator.rememberUsing(.provider("c1"))
        #expect(simulator.defaultUsing() == .provider("c1"))
        #expect(try service([], onDevice: .init(appleTranslation: false, appleIntelligence: false)).usingOptions().isEmpty)
    }

    /// AC-33: with Claude the note names Anthropic; a home server and the
    /// device say where the words stay. The key never appears.
    @Test func noteSaysWhereTheWordsGo() throws {
        let claude = AIProvider(id: "c1", kind: .claude, name: "Claude", model: "m")
        let home = AIProvider(id: "h1", kind: .homeServer, name: "Mac Studio", address: "http://10.0.0.2:11434", model: "m")
        let service = try service([claude, home], onDevice: .init(appleTranslation: true, appleIntelligence: false))
        let cloud = service.note(for: .provider("c1"), lines: 1_380)
        #expect(cloud == "1,380 lines of subtitle text will be sent to Anthropic with your API key. Timing stays as it is.")
        #expect(!cloud.contains("7Qx2"))
        #expect(service.note(for: .provider("h1"), lines: 1_380).hasPrefix("Sent to Mac Studio on your network."))
        #expect(service.note(for: .appleTranslation, lines: 1_380).hasPrefix("Stays on this device."))
        #expect(service.name(of: "provider:c1") == "Claude")
        #expect(service.name(of: "provider:gone") == nil)
    }
}
