import Foundation
import Testing
@testable import ShotDex

/// FS-01.11 §4 — AC-3, AC-11, AC-21: order, reference and the two warnings.
@Suite struct HDRBracketOrderTests {
    typealias Frame = HDRBracketOrder.Frame<String>

    /// An aperture-priority AEB: f/8, ISO 100, the camera moves the shutter
    /// and records the bias it was asked for.
    static func aeb(_ id: String, shutter: Double, bias: Double, raw: Bool = true) -> Frame {
        Frame(id: id, shutterSeconds: shutter, iso: 100, aperture: 8, exposureBias: bias, isRAW: raw)
    }

    @Test func shuffledSelectionComesBackDarkestFirstWithTheMiddleAsReference() {
        let frames = [Self.aeb("p2", shutter: 1.0 / 30, bias: 2), Self.aeb("m4", shutter: 1.0 / 2000, bias: -4),
                      Self.aeb("0", shutter: 1.0 / 125, bias: 0), Self.aeb("p4", shutter: 1.0 / 8, bias: 4),
                      Self.aeb("m2", shutter: 1.0 / 500, bias: -2)]
        let series = HDRBracketOrder.series(frames)
        #expect(series.order == ["m4", "m2", "0", "p2", "p4"])
        #expect(series.reference == 2)
        #expect(series.order[series.reference] == "0")
        // Stops from the shutter alone — the bias is already in it, not added
        // twice. Cameras write the nominal shutter (1/30 is really 1/32), so a
        // tenth of a stop either way.
        for (got, want) in zip(series.stops, [-4.0, -2.0, 0, 2.0, 4.0]) { #expect(abs(got - want) < 0.1) }
        #expect(!series.isSameExposure)
        #expect(series.mergesFromRAW)
    }

    @Test func anEvenSeriesTakesTheBrighterOfTheTwoMiddleFrames() {
        let frames = [Self.aeb("a", shutter: 1.0 / 500, bias: -1), Self.aeb("b", shutter: 1.0 / 250, bias: 0),
                      Self.aeb("c", shutter: 1.0 / 125, bias: 1), Self.aeb("d", shutter: 1.0 / 60, bias: 2)]
        let series = HDRBracketOrder.series(frames)
        #expect(series.order[series.reference] == "c")
    }

    @Test func withoutExposureDataTheBiasThenTheMeasurementDecides() {
        let byBias = [Frame(id: "x", exposureBias: 1, isRAW: false), Frame(id: "y", exposureBias: -1, isRAW: false)]
        #expect(HDRBracketOrder.series(byBias).order == ["y", "x"])
        let measured = [Frame(id: "x", isRAW: false, measuredLog2Brightness: -3),
                        Frame(id: "y", isRAW: false, measuredLog2Brightness: -1)]
        #expect(HDRBracketOrder.series(measured).order == ["x", "y"])
    }

    /// AC-11: five frames within half a stop are not a bracket.
    @Test func framesAtOneExposureAreFlagged() {
        let frames = (0..<5).map { Self.aeb("\($0)", shutter: 1.0 / 125 * (1 + Double($0) * 0.05), bias: 0) }
        let series = HDRBracketOrder.series(frames)
        #expect(series.isSameExposure)
        #expect(series.order.count == 5)
    }

    /// AC-21: three RAW and two JPEG merge from the processed versions.
    @Test func aMixedSeriesIsFlaggedAndDoesNotMergeFromRAW() {
        let frames = [Self.aeb("a", shutter: 1.0 / 500, bias: -2), Self.aeb("b", shutter: 1.0 / 125, bias: 0),
                      Self.aeb("c", shutter: 1.0 / 30, bias: 2), Self.aeb("d", shutter: 1.0 / 2000, bias: -4, raw: false),
                      Self.aeb("e", shutter: 1.0 / 8, bias: 4, raw: false)]
        let series = HDRBracketOrder.series(frames)
        #expect(series.isMixedRAW)
        #expect(!series.mergesFromRAW)
    }
}
