import Foundation
import ImageIO
import Testing
@testable import ShotDex

/// FS-19.02 §5 — writing `.xmp` sidecars.
@Suite struct SidecarWriterTests {
    /// A Lightroom Classic sidecar with `count` develop settings, Photo
    /// Mechanic's own fields and two keywords — the kind of file whose every
    /// byte ShotDex must leave alone.
    static func lightroomSidecarWithSettings(count: Int) -> String {
        let settings = (0..<count).map { "    crs:Setting\(String(format: "%03d", $0))=\"\(Double($0) / 7)\"" }.joined(separator: "\n")
        return """
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 7.0-c000 1.000000, 0000/00/00-00:00:00        ">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
            xmlns:photomechanic="http://ns.camerabits.com/photomechanic/1.0/"
            xmp:CreatorTool="Adobe Lightroom Classic 14.0 (Macintosh)"
            xmp:Rating="3"
            photomechanic:ColorClass="2"
            photomechanic:Tagged="True"
            photomechanic:Prefs="0:2:3:005631"
        \(settings)>
           <dc:subject>
            <rdf:Bag>
             <rdf:li>Nara</rdf:li>
             <rdf:li>Japan</rdf:li>
            </rdf:Bag>
           </dc:subject>
           <crs:ToneCurvePV2012>
            <rdf:Seq>
             <rdf:li>0, 0</rdf:li>
             <rdf:li>255, 255</rdf:li>
            </rdf:Seq>
           </crs:ToneCurvePV2012>
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        """
    }

    /// The text with one element taken out — what "every other tag is the
    /// same, byte for byte" is compared on.
    static func removing(_ element: String, from xmp: String) -> String {
        guard let start = xmp.range(of: "<\(element)"),
              let end = xmp.range(of: "</\(element)>", range: start.upperBound..<xmp.endIndex) else { return xmp }
        return String(xmp[..<start.lowerBound]) + String(xmp[end.upperBound...])
    }

    /// AC-25: a sidecar holding 214 Lightroom develop settings and Photo
    /// Mechanic's fields gets the keyword "deer" from ShotDex. The sidecar
    /// now lists deer beside its keywords, and everything outside the
    /// keyword list is the same text, byte for byte.
    @Test func preservesForeignTags() throws {
        let original = Self.lightroomSidecarWithSettings(count: 214)
        var patch = XMPPatch()
        patch.keywords = .set(["Nara", "Japan", "deer"])
        let patched = XMPPatcher.apply(patch, to: original)

        #expect(Self.removing("dc:subject", from: patched) == Self.removing("dc:subject", from: original))
        let values = try #require(SidecarReader.values(xmp: Data(patched.utf8)))
        #expect(values.keywords == ["Nara", "Japan", "deer"])
        #expect(values.rating == 3)
        let metadata = try #require(CGImageMetadataCreateFromXMPData(Data(patched.utf8) as CFData))
        #expect(CGImageMetadataCopyStringValueWithPath(metadata, nil, "crs:Setting213" as CFString) as String? == String(213.0 / 7))
        #expect(CGImageMetadataCopyStringValueWithPath(metadata, nil, "photomechanic:Prefs" as CFString) as String? == "0:2:3:005631")
    }

    /// The patcher's other moves, each leaving the rest of the text alone:
    /// a rating changed in place, a title added where there was none, a
    /// keyword list removed, a sidecar made from nothing, and an element-
    /// form rating (`<xmp:Rating>2</xmp:Rating>`) rewritten as it stands.
    @Test func patchesOnlyItsOwnFields() throws {
        let original = Self.lightroomSidecarWithSettings(count: 3)
        var patch = XMPPatch()
        patch.rating = .set(-1)
        patch.title = .set("Deer & <friends>")
        patch.keywords = .remove
        let patched = XMPPatcher.apply(patch, to: original)
        let values = try #require(SidecarReader.values(xmp: Data(patched.utf8)))
        #expect(values.isRejected)
        #expect(values.title == "Deer & <friends>")
        #expect(values.keywords.isEmpty)
        #expect(patched.contains("crs:Setting002=\"\(2.0 / 7)\""))
        #expect(patched.contains("<crs:ToneCurvePV2012>"))

        var fresh = XMPPatch()
        fresh.rating = .set(4)
        fresh.keywords = .set(["Kyoto"])
        fresh.caption = .set("Fushimi Inari")
        let created = try #require(SidecarReader.values(xmp: Data(XMPPatcher.apply(fresh, to: nil).utf8)))
        #expect(created == SidecarValues(rating: 4, keywords: ["Kyoto"], caption: "Fushimi Inari"))

        let elementForm = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/">
           <xmp:Rating>2</xmp:Rating>
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        """
        var five = XMPPatch()
        five.rating = .set(5)
        let rewritten = XMPPatcher.apply(five, to: elementForm)
        #expect(rewritten == elementForm.replacingOccurrences(of: "<xmp:Rating>2<", with: "<xmp:Rating>5<"))
    }
}
