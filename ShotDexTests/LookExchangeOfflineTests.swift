import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// Records every request the default URL loading system is asked to make and
/// fails it — the "airplane mode" of FS-03.14 AC-0.1.
final class NoNetworkProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests: [URL] = []

    override class func canInit(with request: URLRequest) -> Bool {
        requests.append(request.url ?? URL(fileURLWithPath: "/"))
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}

struct LookExchangeOfflineTests {
    /// FS-03.14 AC-0.1. Import a 3 KB .xmp, then export the look as a
    /// .shotdexlook, with every connection refused: both finish and not one
    /// request was attempted.
    @MainActor @Test func importAndExportNeedNoNetwork() throws {
        URLProtocol.registerClass(NoNetworkProtocol.self)
        defer { URLProtocol.unregisterClass(NoNetworkProtocol.self) }
        NoNetworkProtocol.requests = []

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("offline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let padding = String(repeating: " ", count: 2_500)
        let url = folder.appendingPathComponent("Golden.xmp")
        try LightroomXMPReaderTests.preset(#"crs:Exposure2012="+0.50" \#(padding)"#).write(to: url)
        let store = LookPresetStore(directory: folder.appendingPathComponent("store"), defaults: UserDefaults(suiteName: "offline-\(UUID().uuidString)")!)
        let report = PresetImporter.apply(try PresetImporter.read([url]), looks: store, luts: nil)
        #expect(report.addedCount == 1)
        let look = try #require(store.presets.first)
        let file = try LookFileCodec.encode(look)
        try file.write(to: folder.appendingPathComponent("Golden.shotdexlook"))
        #expect(try LookFileCodec.decode(file).name == "Golden")
        #expect(NoNetworkProtocol.requests.isEmpty)
    }
}
