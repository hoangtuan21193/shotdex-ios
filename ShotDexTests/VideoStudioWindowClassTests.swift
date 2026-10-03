import CoreGraphics
import Testing
@testable import ShotDex

/// The Video Studio's layout is chosen by the window — size and trailing
/// inset — not by the device (FS-12.03 §1, FS-12.07b §1). The table is the
/// one the wide-and-Duo plan specified for its task 4.
struct VideoStudioWindowClassTests {
    @Test(arguments: [
        (CGSize(width: 402, height: 874), CGFloat(0), VideoStudioWindowClass.phone),
        (CGSize(width: 466, height: 678), 84, .duoCover),
        (CGSize(width: 466, height: 678), 0, .phone),
        (CGSize(width: 951, height: 669), 0, .duoInner),
        (CGSize(width: 1376, height: 1032), 0, .iPadLandscape),
        (CGSize(width: 1032, height: 1376), 0, .iPadPortrait),
        (CGSize(width: 639, height: 1376), 0, .iPadPortrait),
        (CGSize(width: 507, height: 1032), 0, .phone),
        (CGSize(width: 1000, height: 800), 0, .iPadLandscape),
        (CGSize(width: 1000, height: 700), 0, .duoInner),
    ])
    func windowsResolveToTheirLayout(window: CGSize, trailingInset: CGFloat, expected: VideoStudioWindowClass) {
        #expect(VideoStudioWindowClass.resolve(window: window, trailingInset: trailingInset) == expected)
    }

    @Test func shortWindowsAreUnder720() {
        for height in [CGFloat(669), 678, 719.5] {
            #expect(VideoStudioWindowClass.isShortWindow(height: height))
        }
        for height in [CGFloat(720), 812, 874, 1032] {
            #expect(!VideoStudioWindowClass.isShortWindow(height: height))
        }
    }

    /// FS-12.04 AC-2: every layout offers all five tools — iterated over the
    /// layouts and over the tools, compared element by element, not counted.
    @Test func everyLayoutOffersTheFiveAddTools() {
        for windowClass in VideoStudioWindowClass.allCases {
            let offered = VideoAddTool.addTools(for: windowClass)
            for tool in VideoAddTool.allCases {
                #expect(offered.contains(tool), "\(windowClass) is missing \(tool)")
            }
        }
        // iPad: four inserts in the pool or the dock, Look as the default panel.
        for windowClass in [VideoStudioWindowClass.iPadLandscape, .iPadPortrait] {
            #expect(VideoAddTool.placement(of: .look, in: windowClass) == .defaultPanel)
            for tool in [VideoAddTool.media, .text, .sticker, .music] {
                #expect(VideoAddTool.placement(of: tool, in: windowClass) != .defaultPanel)
            }
        }
    }
}
