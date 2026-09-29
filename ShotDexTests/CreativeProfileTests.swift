import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

struct CreativeProfileTests {
    /// FS-03.14 AC-b6 (the experiment's outcome, 2026-09-29): a creative
    /// profile carrying Look/Parameters/LookTable at Amount 60 is not decoded
    /// — Adobe's table encoding has no published description — so the report
    /// says so and the rest of the preset still lands.
    @Test func aCreativeProfileTableIsReportedNotGuessed() throws {
        let body = """
        <crs:Look>
         <rdf:Description crs:Name="Vintage 07" crs:Amount="0.6" crs:UUID="00000000000000000000000000000007">
          <crs:Parameters>
           <rdf:Description crs:Version="15.4" crs:ProcessVersion="15.4" crs:LookTable="0123456789ABCDEF0123456789ABCDEF"/>
          </crs:Parameters>
         </rdf:Description>
        </crs:Look>
        """
        let settings = try LightroomXMPReader.read(LightroomXMPReaderTests.preset(#"crs:Vibrance="+10""#, body: body))
        #expect(settings.look["Name"] == "Vintage 07")
        let result = LightroomMapping.map(settings)
        #expect(abs(result.recipe.adjustments[.vibrance] - 0.1) < 1e-9)
        #expect(result.recipe.lutID == nil)
        #expect(result.lines == [PresetReportLine(kind: .skipped, text: "Creative profile 'Vintage 07' — its colour table can't be read, so it's left out")])

        let builtIn = try LightroomXMPReader.read(LightroomXMPReaderTests.preset(
            #"crs:Vibrance="+10""#,
            body: #"<crs:Look><rdf:Description crs:Name="Adobe Portrait" crs:Amount="1"/></crs:Look>"#
        ))
        #expect(LightroomMapping.map(builtIn).lines == [PresetReportLine(kind: .skipped, text: "The profile's colour table isn't in the file")])
    }
}
