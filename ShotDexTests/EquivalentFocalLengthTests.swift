import Testing
@testable import ShotDex

struct EquivalentFocalLengthTests {

    @Test func calculatesFromCropFactor() {
        #expect(EquivalentFocalLength.calculate(actualFocalLength: 25, cropFactor: 2.0) == 50)
        #expect(EquivalentFocalLength.calculate(actualFocalLength: 50, cropFactor: 1.5) == 75)
        #expect(EquivalentFocalLength.calculate(actualFocalLength: 50, cropFactor: 1.6) == 80)
        #expect(EquivalentFocalLength.calculate(actualFocalLength: 150, cropFactor: 2.0) == 300)
    }

    @Test func missingInputsReturnNil() {
        #expect(EquivalentFocalLength.calculate(actualFocalLength: nil, cropFactor: 2.0) == nil)
        #expect(EquivalentFocalLength.calculate(actualFocalLength: 50, cropFactor: nil) == nil)
        #expect(EquivalentFocalLength.calculate(actualFocalLength: 0, cropFactor: 2.0) == nil)
        #expect(EquivalentFocalLength.calculate(actualFocalLength: 50, cropFactor: 0) == nil)
    }

    @Test func exif35mmTakesPriority() {
        #expect(EquivalentFocalLength.resolve(exif35mm: 52, actualFocalLength: 25, cropFactor: 2.0) == 52)
    }

    @Test func fallsBackToCalculationWhenExifInvalid() {
        #expect(EquivalentFocalLength.resolve(exif35mm: 0, actualFocalLength: 25, cropFactor: 2.0) == 50)
        #expect(EquivalentFocalLength.resolve(exif35mm: nil, actualFocalLength: 25, cropFactor: 2.0) == 50)
        #expect(EquivalentFocalLength.resolve(exif35mm: 9999, actualFocalLength: 25, cropFactor: 2.0) == 50)
    }

    @Test func unknownCropFactorYieldsNil() {
        #expect(EquivalentFocalLength.resolve(exif35mm: nil, actualFocalLength: 25, cropFactor: nil) == nil)
    }
}
