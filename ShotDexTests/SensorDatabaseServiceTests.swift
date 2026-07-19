import Foundation
import Testing
@testable import ShotDex

struct SensorDatabaseServiceTests {

    @Test func loadsBundledDatabase() throws {
        // The JSON ships in the app bundle, which is the test host.
        let records = try SensorDatabaseService().loadRecords(bundle: Bundle(for: AppDatabase.self))
        #expect(!records.isEmpty)

        let lookup = SensorLookup(records: records)
        #expect(lookup.lookup(normalizedModel: "EOS R6 Mark II").sensorFormat == .fullFrame)
        #expect(lookup.lookup(normalizedModel: "EOS R7").cropFactor == 1.6)
        #expect(lookup.lookup(normalizedModel: "A6700").sensorFormat == .apsC)
        #expect(lookup.lookup(normalizedModel: "ILCE-6700").sensorFormat == .apsC)
        #expect(lookup.lookup(normalizedModel: "OM-1").sensorFormat == .microFourThirds)
        #expect(lookup.lookup(normalizedModel: "RX100 VII").sensorFormat == .oneInch)
    }

    @Test func coversPhonesAndLegacyCameras() throws {
        let records = try SensorDatabaseService().loadRecords(bundle: Bundle(for: AppDatabase.self))
        let lookup = SensorLookup(records: records)
        // Canon EXIF short forms for Mark II R bodies.
        #expect(lookup.lookup(normalizedModel: "EOS R5m2").sensorFormat == .fullFrame)
        #expect(lookup.lookup(normalizedModel: "EOS R6m2").sensorFormat == .fullFrame)
        #expect(lookup.lookup(normalizedModel: "EOS M").sensorFormat == .apsC)
        // Sony EXIF model codes.
        #expect(lookup.lookup(normalizedModel: "ILCE-7M2").sensorFormat == .fullFrame)
        #expect(lookup.lookup(normalizedModel: "ILCE-7RM2").sensorFormat == .fullFrame)
        #expect(lookup.lookup(normalizedModel: "DSC-R1").sensorFormat == .apsC)
        // Legacy compacts.
        #expect(lookup.lookup(normalizedModel: "DMC-LS80").sensorFormat == .compact)
        // Phones and tablets.
        #expect(lookup.lookup(normalizedModel: "iPhone 6").sensorFormat == .smartphone)
        #expect(lookup.lookup(normalizedModel: "iPhone 11 Pro Max").sensorFormat == .smartphone)
        #expect(lookup.lookup(normalizedModel: "iPad Pro (11-inch) (2nd generation)").sensorFormat == .smartphone)
        #expect(lookup.lookup(normalizedModel: "BlackBerry PlayBook").sensorFormat == .smartphone)
        #expect(lookup.lookup(normalizedModel: "SM-G998B").sensorFormat == .smartphone)
        #expect(lookup.lookup(normalizedModel: "Pixel 7 Pro").sensorFormat == .smartphone)
    }

    @Test func allRecordsHaveValidFormats() throws {
        let records = try SensorDatabaseService().loadRecords(bundle: Bundle(for: AppDatabase.self))
        for record in records {
            #expect(SensorFormat(rawValue: record.sensorFormat) != nil, "Invalid format: \(record.sensorFormat) for \(record.model)")
            #expect(record.cropFactor > 0)
        }
    }
}
