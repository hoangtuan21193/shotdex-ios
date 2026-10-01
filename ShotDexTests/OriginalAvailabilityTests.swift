import Foundation
import Testing
@testable import ShotDex

/// FS-02.06 AC-1: the viewer asks once, with the network off, and never
/// downloads the original to find out.
@Suite struct OriginalAvailabilityTests {
    /// AC-1. A photo the script puts in iCloud answers `.inCloud`, as many
    /// times as it is asked, and asking downloads nothing.
    @Test func probeDownloadsNothing() async {
        let base = FixtureOriginalFetcher()
        let fake = FakeOriginalFetcher(script: .init("cloud=1"), base: base)
        let cloud = OriginalItem.test("A"), local = OriginalItem.test("B")
        #expect(await fake.probe(cloud) == .inCloud)
        #expect(await fake.probe(cloud) == .inCloud)
        #expect(await fake.probe(local) == .local)
        #expect(fake.downloadCount == 0)
        #expect(fake.fetchCount == 0)
        #expect(base.fetched.isEmpty)
    }

    /// AC-1 / AC-2. Once the zoom's download has played, the photo is here
    /// and the glyph's question answers `.local`.
    @Test func aPlayedDownloadMakesTheOriginalLocal() async throws {
        let fake = FakeOriginalFetcher(script: .init("cloud=all,seconds=0.2"), base: FixtureOriginalFetcher())
        let item = OriginalItem.test("A")
        let ticks = Ticks()
        try await fake.scriptedTransfer(for: item.id) { ticks.add($0) }
        #expect(await fake.probe(item) == .local)
        #expect(ticks.values.last == 1)
        #expect(ticks.values == ticks.values.sorted())
    }

    /// AC-1. The viewer's question is the offline probe of the page on
    /// screen; the probe reads with the network off; nothing on that path
    /// fetches.
    @Test func viewerProbesOfflineOnly() throws {
        let viewer = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Library/PhotoDetailScreen.swift")
            .joined(separator: "\n")
        let start = try #require(viewer.range(of: "private func probeOriginal()"))
        let body = String(viewer[start.lowerBound...].prefix(1200))
        #expect(body.contains("fetcher.probe(item)"))
        #expect(!body.contains(".fetch("))
        #expect(!body.contains("allowNetwork"))
        let fetcher = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Data/Sources/OriginalFetcher.swift")
            .joined(separator: "\n")
        let probe = try #require(fetcher.range(of: "func probe(_ item: OriginalItem) async -> OriginalAvailability {"))
        let probeBody = String(fetcher[probe.lowerBound...].prefix(600))
        #expect(probeBody.contains("options.isNetworkAccessAllowed = false"))
    }
}

/// Progress values collected from any thread.
final class Ticks: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Double] = []
    func add(_ value: Double) { lock.lock(); stored.append(value); lock.unlock() }
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return stored }
}
