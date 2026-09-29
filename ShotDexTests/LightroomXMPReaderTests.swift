import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.14a — reading a Lightroom `.xmp` preset. The presets here are
/// written for the test from the XMP format's description, not taken from
/// Adobe's files.
struct LightroomXMPReaderTests {
    static func preset(_ attributes: String, body: String = "") -> Data {
        Data("""
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Test">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
            crs:PresetType="Normal" crs:Version="15.4" crs:ProcessVersion="15.4"
            \(attributes)>
           \(body)
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        """.utf8)
    }

    /// FS-03.14 AC-a1 (Domain half). crs:Name "Golden", Exposure +0.50,
    /// Red Hue −20: a look with Exposure +0.50 EV and Red Hue −20, a ✓ row
    /// and "1 look added".
    @Test func exposureAndRedHueMap() throws {
        let settings = try LightroomXMPReader.read(Self.preset(
            #"crs:Exposure2012="+0.50" crs:HueAdjustmentRed="-20""#,
            body: #"<crs:Name><rdf:Alt><rdf:li xml:lang="x-default">Golden</rdf:li></rdf:Alt></crs:Name>"#
        ))
        #expect(settings.name == "Golden")
        let result = LightroomMapping.map(settings)
        #expect(result.recipe.adjustments[.exposure] == 0.5)
        #expect(abs(result.recipe.color.mixer[.red].hue + 0.2) < 1e-9)
        #expect(result.lines.isEmpty, "administrative tags make no line")
        #expect(result.namedSettings == [.adjustment(.exposure), .mixer(.red, .hue)])
        let status = PresetImportReport.status(applied: result.appliedCount, lines: result.lines)
        #expect(status == .added)
        let report = PresetImportReport(entries: [.init(name: "Golden", status: status, lines: result.lines)])
        #expect(report.header == "1 look added")
    }

    /// Settings may be written as child elements instead of attributes.
    @Test func elementFormIsReadToo() throws {
        let settings = try LightroomXMPReader.read(Self.preset("", body: "<crs:Exposure2012>-0.30</crs:Exposure2012>"))
        #expect(LightroomMapping.map(settings).recipe.adjustments[.exposure] == -0.3)
    }

    /// A DTD never reaches the parser: an entity-expansion bomb is refused
    /// as invalid XMP without being expanded.
    @Test func aDoctypeIsRefusedBeforeParsing() {
        let bomb = Data(#"<?xml version="1.0"?><!DOCTYPE x [<!ENTITY a "aaaa"><!ENTITY b "&a;&a;&a;">]><x>&b;</x>"#.utf8)
        #expect(throws: SafeXMLReader.Failure.forbiddenDeclaration) { try SafeXMLReader.read(bomb) }
        #expect(throws: LightroomXMPReader.Failure.notValidXMP) { try LightroomXMPReader.read(bomb) }
        let deep = Data((String(repeating: "<a>", count: 70) + String(repeating: "</a>", count: 70)).utf8)
        #expect(throws: SafeXMLReader.Failure.tooDeep) { try SafeXMLReader.read(deep) }
    }

    /// FS-03.14 AC-a4. A closing tag missing on line 14: ✕ with the next
    /// step, no look.
    @Test func malformedXMLGivesNextStep() {
        var lines = String(decoding: Self.preset(#"crs:Exposure2012="+0.50""#), as: UTF8.self).components(separatedBy: "\n")
        while lines.count < 16 { lines.insert(" <!-- padding -->", at: 1) }
        lines[13] = "<crs:Name>unclosed"
        let broken = Data(lines.joined(separator: "\n").utf8)
        #expect(throws: LightroomXMPReader.Failure.notValidXMP) { try LightroomXMPReader.read(broken) }
        #expect(LightroomXMPReader.Failure.notValidXMP.message
            == "The file is not valid XMP. Try exporting the preset from Lightroom again.")
    }

    /// FS-03.14 AC-a8. A sidecar with only EXIF and Dublin Core: ✕ "This XMP
    /// has no Lightroom edit settings", no look.
    @Test func sidecarWithoutSettingsIsNotAPreset() {
        let sidecar = Data("""
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about="" xmlns:exif="http://ns.adobe.com/exif/1.0/"
            xmlns:dc="http://purl.org/dc/elements/1.1/" exif:ExposureTime="1/250">
           <dc:creator><rdf:Seq><rdf:li>Someone</rdf:li></rdf:Seq></dc:creator>
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        """.utf8)
        #expect(throws: LightroomXMPReader.Failure.noLightroomSettings) { try LightroomXMPReader.read(sidecar) }
        #expect(LightroomXMPReader.Failure.noLightroomSettings.message == "This XMP has no Lightroom edit settings")
    }
}
