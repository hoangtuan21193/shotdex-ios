import Testing
@testable import ShotDexKit

/// The Warmth / Tint gains (FS-03.15 AC-15).
struct WhiteBalanceMathTests {
    @Test func zeroIsIdentity() {
        let gains = WhiteBalanceMath.gains(warmth: 0, tint: 0)
        #expect(abs(gains.x - 1) < 1e-9 && abs(gains.y - 1) < 1e-9 && abs(gains.z - 1) < 1e-9)
    }

    @Test func warmRaisesRedAndLowersBlue() {
        let warm = WhiteBalanceMath.gains(warmth: 0.5, tint: 0)
        #expect(warm.x > 1)
        #expect(warm.z < 1)
        #expect(abs(warm.y - 1) < 1e-9, "normalised on green")
        let cool = WhiteBalanceMath.gains(warmth: -0.5, tint: 0)
        #expect(cool.x < 1)
        #expect(cool.z > 1)
    }

    @Test func magentaTintLowersGreen() {
        #expect(WhiteBalanceMath.gains(warmth: 0, tint: 0.5).y < 1)
        #expect(WhiteBalanceMath.gains(warmth: 0, tint: -0.5).y > 1)
    }
}
