import Testing
@testable import ShotDex

struct SensorLookupTests {
    private let records = [
        SensorCameraRecord(manufacturer: "Canon", model: "EOS R6 Mark II", sensorFormat: "Full Frame", cropFactor: 1.0, aliases: nil),
        SensorCameraRecord(manufacturer: "Sony", model: "A6700", sensorFormat: "APS-C", cropFactor: 1.5, aliases: ["ILCE-6700"]),
        SensorCameraRecord(manufacturer: "OM System", model: "OM-1", sensorFormat: "Micro Four Thirds", cropFactor: 2.0, aliases: nil),
    ]

    @Test func findsKnownCameras() {
        let lookup = SensorLookup(records: records)
        let r6 = lookup.lookup(normalizedModel: "EOS R6 Mark II")
        #expect(r6.sensorFormat == .fullFrame)
        #expect(r6.cropFactor == 1.0)

        let om1 = lookup.lookup(normalizedModel: "OM-1")
        #expect(om1.sensorFormat == .microFourThirds)
        #expect(om1.cropFactor == 2.0)
    }

    @Test func matchIsCaseAndSpacingInsensitive() {
        let lookup = SensorLookup(records: records)
        #expect(lookup.lookup(normalizedModel: "eos r6 mark ii").sensorFormat == .fullFrame)
        #expect(lookup.lookup(normalizedModel: "OM1").sensorFormat == .microFourThirds)
    }

    @Test func aliasesResolve() {
        let lookup = SensorLookup(records: records)
        #expect(lookup.lookup(normalizedModel: "ILCE-6700").sensorFormat == .apsC)
        #expect(lookup.lookup(normalizedModel: "ILCE-6700").cropFactor == 1.5)
    }

    @Test func manufacturerPrefixedModelResolves() {
        let lookup = SensorLookup(records: records)
        #expect(lookup.lookup(normalizedModel: "Canon EOS R6 Mark II").sensorFormat == .fullFrame)
    }

    @Test func unknownCameraReturnsUnknown() {
        let lookup = SensorLookup(records: records)
        let result = lookup.lookup(normalizedModel: "Mystery Cam 3000")
        #expect(result.sensorFormat == .unknown)
        #expect(result.cropFactor == nil)
        #expect(lookup.lookup(normalizedModel: nil) == .unknown)
    }

    @Test func customMappingsTakePrecedence() {
        let custom = [CustomCameraMapping(normalizedCameraModel: "Mystery Cam 3000", sensorFormat: "APS-C", cropFactor: 1.5)]
        let lookup = SensorLookup(records: records, customMappings: custom)
        #expect(lookup.lookup(normalizedModel: "Mystery Cam 3000").sensorFormat == .apsC)

        let override = [CustomCameraMapping(normalizedCameraModel: "OM-1", sensorFormat: "Full Frame", cropFactor: 1.0)]
        let overridden = SensorLookup(records: records, customMappings: override)
        #expect(overridden.lookup(normalizedModel: "OM-1").sensorFormat == .fullFrame)
    }
}
