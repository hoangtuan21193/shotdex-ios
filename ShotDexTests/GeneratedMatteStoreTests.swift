import CoreImage
import Foundation
import Testing
@testable import ShotDexKit

/// FS-03.15d AC-51 — mattes worked out once are read back on reopen.
struct GeneratedMatteStoreTests {

    static let extent = CGRect(x: 0, y: 0, width: 200, height: 150)

    /// What "Vision" returns here: a soft disc, deterministic.
    static func disc() -> CIImage {
        CIFilter(name: "CIRadialGradient", parameters: [
            kCIInputCenterKey: CIVector(x: 100, y: 75),
            "inputRadius0": 20, "inputRadius1": 60,
            "inputColor0": CIColor.white, "inputColor1": CIColor.black,
        ])!.outputImage!.cropped(to: extent)
    }

    static func bytes(_ image: CIImage) -> [UInt8] {
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var values = [UInt8](repeating: 0, count: Int(extent.width * extent.height) * 4)
        context.render(image, toBitmap: &values, rowBytes: Int(extent.width) * 4, bounds: extent,
                       format: .RGBA8, colorSpace: nil)
        return values
    }

    /// AC-51. Open, work the matte out (Vision once); reopen — a new
    /// renderer over the same store — and Vision runs 0 times, the matte
    /// matching the first pixel for pixel; delete the file and open again,
    /// and it is worked out afresh without an error.
    @Test func reopenReadsTheSavedMatte() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mattes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GeneratedMatteStore(directory: directory)
        let key = PhotoRenderService.persistentMattePrefix + "asset-1|original|0|subject"
        let photo = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: Self.extent)
        var visionRuns = 0

        let first = PhotoRenderService()
        await first.setMatteStore(store)
        let firstMatte = try #require(try await first.automaticMatte(key: key, image: photo) {
            visionRuns += 1
            return Self.disc()
        })
        #expect(visionRuns == 1)
        #expect(FileManager.default.fileExists(atPath: store.url(for: key).path))

        let reopened = PhotoRenderService()
        await reopened.setMatteStore(store)
        let secondMatte = try #require(try await reopened.automaticMatte(key: key, image: photo) {
            visionRuns += 1
            return Self.disc()
        })
        #expect(visionRuns == 1, "reopening ran Vision again")
        #expect(Self.bytes(secondMatte) == Self.bytes(firstMatte))

        store.remove(key)
        let third = PhotoRenderService()
        await third.setMatteStore(store)
        let thirdMatte = try await third.automaticMatte(key: key, image: photo) {
            visionRuns += 1
            return Self.disc()
        }
        #expect(visionRuns == 2)
        #expect(thirdMatte != nil)
    }

    /// A photo with no lasting name keeps its mattes in memory only.
    @Test func unnamedPhotosWriteNothing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mattes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GeneratedMatteStore(directory: directory)
        let service = PhotoRenderService()
        await service.setMatteStore(store)
        let photo = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: Self.extent)
        _ = try await service.automaticMatte(key: "/tmp/source.jpg|subject", image: photo) { Self.disc() }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(files.isEmpty)
    }
}
