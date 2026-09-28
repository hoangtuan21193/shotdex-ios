import Foundation
import Testing
@testable import ShotDex

/// FS-03.16b AC-b6 — what the editor says about lens correction.
struct EditorStringsTests {

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// String literals in a Swift file, comments left out.
    static func literals(in url: URL) throws -> [String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var out: [String] = []
        for line in text.split(separator: "\n") {
            var code = String(line)
            if let comment = code.range(of: "//") { code = String(code[..<comment.lowerBound]) }
            out += code.matches(of: /"([^"\\]|\\.)*"/).map { String($0.output.0) }
        }
        return out
    }

    /// AC-b6. No editor string says "Lensfun" — the credit is in Settings ›
    /// Acknowledgements only, which still has it with the licence; the RAW
    /// group has no lens row; Optics has one switch.
    @Test func noLensfunInEditorStrings() throws {
        let folder = Self.repository.appendingPathComponent("ShotDex/Features/Editing")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            + [Self.repository.appendingPathComponent("ShotDex/Domain/Editing/EditorAdjustmentCatalog.swift")]
        #expect(files.count > 20)
        for file in files {
            for literal in try Self.literals(in: file) where literal.localizedCaseInsensitiveContains("lensfun") {
                Issue.record("\(file.lastPathComponent): \(literal)")
            }
        }
        let settings = try String(
            contentsOf: Self.repository.appendingPathComponent("ShotDex/Features/Settings/SettingsScreen.swift"), encoding: .utf8
        )
        #expect(settings.contains("Lensfun") && settings.contains("CC-BY-SA 3.0"))
    }

    /// 16b §2: the status line of every state, word for word.
    @Test func statusLinesSayWhatCorrectsThePhoto() {
        #expect(EditorLensProfileSection.statusLine(.found(lensName: "FE 24-70mm F2.8 GM II")) == "FE 24-70mm F2.8 GM II · Found from photo info")
        #expect(EditorLensProfileSection.statusLine(.chosen(lensName: "Sigma 35mm")) == "Sigma 35mm · Chosen by you")
        #expect(EditorLensProfileSection.statusLine(.correctedInCamera) == "Already corrected in camera")
        #expect(EditorLensProfileSection.statusLine(.builtIn) == "Using the camera's built-in correction")
        #expect(EditorLensProfileSection.statusLine(.noProfile) == "No profile for this lens yet")
        #expect(EditorLensProfileSection.buttonTitle(.found(lensName: "x")) == "Change")
        #expect(EditorLensProfileSection.buttonTitle(.noProfile) == "Choose Lens")
    }
}
