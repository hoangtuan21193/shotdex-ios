import CryptoKit
import Foundation
import ShotDexKit
import Testing
@testable import ShotDex

/// FS-05.04 through the server export sheet (FS-17.06 §6).
@MainActor
@Suite(.serialized) struct ServerExportWatermarkTests {
    final class Stamps: @unchecked Sendable {
        private let lock = NSLock()
        private var _seen: [String: WatermarkStamp?] = [:]
        var seen: [String: WatermarkStamp?] { lock.withLock { _seen } }
        func add(_ id: String, _ stamp: WatermarkStamp?) { lock.withLock { _seen[id] = stamp } }
    }

    /// AC-9: two JPEGs on the NAS, Original Folder, configuration W — Replace
    /// Original is off with its reason; each photo goes out as
    /// `<name>_edited.jpg` with the stamp; the two originals keep their bytes.
    @Test func replaceIsOffAndOriginalsKeepTheirHash() async throws {
        let fixture = ServerEditExportTests.Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let a = try fixture.photo("a.JPG")
        let b = try fixture.photo("b.JPG")
        let hashes = ["Trip/a.JPG", "Trip/b.JPG"].map { SHA256.hash(data: fixture.client.files[$0]!) }

        let credit = WatermarkFixture.credit(logo: nil)
        let stores = try WatermarkModelTests.stores(presets: [credit])
        stores.settings.update { $0.presetID = credit.id; $0.isEnabled = true; $0.placement = WatermarkFixture.placementW }

        let stamps = Stamps()
        var services = fixture.services()
        services.render = { photo, format, _, watermark, folder in
            stamps.add(photo.id, watermark)
            let url = folder.appendingPathComponent("render.\(format.fileExtension)")
            try Data("stamped \(photo.photo.primary.name)".utf8).write(to: url)
            return url
        }
        let model = ServerExportModel(
            photos: [a, b], originServer: FileServer(name: "NAS", transferProtocol: .smb, host: "nas.local", username: "u", share: "photos"), renderDirectory: fixture.directory.appendingPathComponent("exports"),
            services: services, watermarkSettings: stores.settings, signaturePresets: stores.presets, imageExists: { _ in true }
        )
        #expect(model.offersWatermark)
        #expect(model.watermarkRowValue == "Credit")
        #expect(!model.canReplaceOriginals)
        #expect(WatermarkCopy.watermarkedCopiesAreNew(locale: Locale(identifier: "en")) == "Watermarked copies are saved as new files.")

        model.toggle(.originalFolder)
        model.placement = .replaceOriginal
        model.export()
        for _ in 0..<200 where model.stage == .exporting { try await Task.sleep(for: .milliseconds(25)) }
        #expect(model.stage == .done)
        #expect(fixture.client.files["Trip/a_edited.jpg"] == Data("stamped a.JPG".utf8))
        #expect(fixture.client.files["Trip/b_edited.jpg"] == Data("stamped b.JPG".utf8))
        #expect(["Trip/a.JPG", "Trip/b.JPG"].map { SHA256.hash(data: fixture.client.files[$0]!) } == hashes)
        #expect(stamps.seen.count == 2)
        #expect(stamps.seen.values.allSatisfy { $0?.presetID == credit.id })
    }

    /// The sheet's Share destination takes the renders as they are — already
    /// stamped by the sheet's own row — through a gather with no watermark
    /// and so no With/Without row (FS-05.04 §4).
    @Test func shareDestinationIsNotStampedTwice() throws {
        let sheet = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/ServerImport/ServerExportSheet.swift")
            .joined(separator: "\n")
        let gather = try #require(sheet.range(of: "PhotoShareSheet.gather("))
        let call = sheet[gather.lowerBound...].prefix(900)
        #expect(!call.contains("watermark:"))
    }
}
