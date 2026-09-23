import Foundation
import Testing
@testable import ShotDex

/// FS-01.10 AC-3: frames go in the order they were shot, whatever order they
/// were picked in.
struct FocusStackOrderTests {
    private typealias Frame = FocusStackOrder.Frame<String>
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func captureTimeWinsOverPickOrder() {
        let frames = [
            Frame(id: "c", captureDate: t0.addingTimeInterval(2), fileName: "DSC_0003.JPG"),
            Frame(id: "a", captureDate: t0, fileName: "DSC_0001.JPG"),
            Frame(id: "b", captureDate: t0.addingTimeInterval(1), fileName: "DSC_0002.JPG"),
        ]
        #expect(FocusStackOrder.sorted(frames) == ["a", "b", "c"])
    }

    @Test func framesInTheSameSecondFollowTheirFileNumbers() {
        // Ten frames a second: the date alone cannot tell them apart.
        let frames = ["DSC_0413.JPG", "DSC_0411.JPG", "DSC_0412.JPG", "DSC_0410.JPG"].map {
            Frame(id: $0, captureDate: t0, fileName: $0)
        }
        #expect(FocusStackOrder.sorted(frames) == ["DSC_0410.JPG", "DSC_0411.JPG", "DSC_0412.JPG", "DSC_0413.JPG"])
    }

    @Test func fileNumbersCompareAsNumbers() {
        let frames = ["IMG_10.JPG", "IMG_9.JPG"].map { Frame(id: $0, captureDate: t0, fileName: $0) }
        #expect(FocusStackOrder.sorted(frames) == ["IMG_9.JPG", "IMG_10.JPG"])
    }

    @Test func undatedFramesGoLastInThePickedOrder() {
        let frames = [
            Frame(id: "x", captureDate: nil, fileName: nil),
            Frame(id: "a", captureDate: t0, fileName: nil),
            Frame(id: "y", captureDate: nil, fileName: nil),
        ]
        #expect(FocusStackOrder.sorted(frames) == ["a", "x", "y"])
    }

    @Test func reversingThePickGivesTheSameOrder() {
        let frames = (0..<8).map { Frame(id: "f\($0)", captureDate: t0.addingTimeInterval(Double($0) * 0.5), fileName: "DSC_\(100 + $0).JPG") }
        #expect(FocusStackOrder.sorted(frames) == FocusStackOrder.sorted(frames.reversed()))
    }
}
