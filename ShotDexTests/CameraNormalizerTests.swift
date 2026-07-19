import Testing
@testable import ShotDex

struct CameraNormalizerTests {

    @Test func manufacturerAliasesMapToCanonicalNames() {
        #expect(CameraNormalizer.normalizeManufacturer("NIKON CORPORATION") == "Nikon")
        #expect(CameraNormalizer.normalizeManufacturer("CANON") == "Canon")
        #expect(CameraNormalizer.normalizeManufacturer("  SONY ") == "Sony")
        #expect(CameraNormalizer.normalizeManufacturer("OM Digital Solutions") == "OM System")
        #expect(CameraNormalizer.normalizeManufacturer("Apple") == "Apple")
    }

    @Test func unknownManufacturerPassesThroughCleaned() {
        #expect(CameraNormalizer.normalizeManufacturer("  Weird   Brand  ") == "Weird Brand")
        #expect(CameraNormalizer.normalizeManufacturer(nil) == nil)
        #expect(CameraNormalizer.normalizeManufacturer("   ") == nil)
    }

    @Test func modelStripsDuplicatedManufacturerPrefix() {
        #expect(CameraNormalizer.normalizeModel("Canon EOS R6 Mark II", manufacturer: "Canon") == "EOS R6 Mark II")
        #expect(CameraNormalizer.normalizeModel("NIKON Z 8", manufacturer: "NIKON CORPORATION") == "Z 8")
        #expect(CameraNormalizer.normalizeModel("EOS R6", manufacturer: "Canon") == "EOS R6")
    }

    @Test func modelCollapsesWhitespace() {
        #expect(CameraNormalizer.normalizeModel("  EOS   R6  ", manufacturer: nil) == "EOS R6")
        #expect(CameraNormalizer.normalizeModel(nil, manufacturer: "Canon") == nil)
    }

    @Test func lookupKeyIsCaseAndSpacingInsensitive() {
        #expect(CameraNormalizer.lookupKey("EOS R6 Mark II") == CameraNormalizer.lookupKey("eos r6 mark ii"))
        #expect(CameraNormalizer.lookupKey("X-T5") == CameraNormalizer.lookupKey("XT5"))
        #expect(CameraNormalizer.lookupKey("ILCE-7M3") == CameraNormalizer.lookupKey("ilce 7m3"))
    }
}
