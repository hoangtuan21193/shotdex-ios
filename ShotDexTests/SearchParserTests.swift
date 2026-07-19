import Testing
@testable import ShotDex

struct SearchParserTests {

    @Test func recognizesISO() {
        #expect(SearchParser.parse("ISO 3200").iso == 3200)
        #expect(SearchParser.parse("iso3200").iso == 3200)
    }

    @Test func recognizesAperture() {
        #expect(SearchParser.parse("f/1.8").aperture == 1.8)
        #expect(SearchParser.parse("F2.8").aperture == 2.8)
    }

    @Test func recognizesShutterSpeed() {
        #expect(SearchParser.parse("1/500").shutterSeconds == 1.0 / 500.0)
        #expect(SearchParser.parse("1/500s").shutterSeconds == 1.0 / 500.0)
        #expect(SearchParser.parse("2s").shutterSeconds == 2)
    }

    @Test func recognizesFocalLength() {
        #expect(SearchParser.parse("85mm").focalLength == 85)
        #expect(SearchParser.parse("23.5mm").focalLength == 23.5)
    }

    @Test func recognizesSensorFormats() {
        #expect(SearchParser.parse("full frame").sensorFormat == .fullFrame)
        #expect(SearchParser.parse("APS-C").sensorFormat == .apsC)
        #expect(SearchParser.parse("mft").sensorFormat == .microFourThirds)
    }

    @Test func freeTextGoesToDeviceMatch() {
        // "R6" is not a bare number — stays free text.
        let parsed = SearchParser.parse("Canon R6")
        #expect(parsed.freeTextTerms == ["Canon", "R6"])
    }

    @Test func bareNumbersAreCollected() {
        let parsed = SearchParser.parse("400")
        #expect(parsed.bareNumbers == [400])
        #expect(parsed.iso == nil)
    }

    @Test func combinedQuery() {
        let parsed = SearchParser.parse("Canon 85mm f/1.8 ISO 400")
        #expect(parsed.freeTextTerms == ["Canon"])
        #expect(parsed.focalLength == 85)
        #expect(parsed.aperture == 1.8)
        #expect(parsed.iso == 400)
    }

    @Test func lensNameWithRangeStaysFreeText() {
        let parsed = SearchParser.parse("RF 100-500")
        #expect(parsed.freeTextTerms.contains("RF"))
        #expect(parsed.freeTextTerms.contains("100-500"))
    }

    @Test func emptyQuery() {
        #expect(SearchParser.parse("  ").isEmpty)
    }
}
