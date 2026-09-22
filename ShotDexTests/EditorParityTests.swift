import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.11 — the six things ShotDex is catching up with Lightroom on.
struct EditorParityTests {

    /// The word "AI" as a whole word, in any case.
    private func mentionsAI(_ text: String) -> Bool {
        text.range(of: #"(?i)\bAI\b"#, options: .regularExpression) != nil
    }

    /// AC-16. Noise reduction here is a tuned classic filter, not a model, and
    /// the interface must not say otherwise: nothing a photographer reads next
    /// to a noise slider may claim "AI".
    @Test func noiseReductionNeverClaimsToBeAI() {
        let groups = EditorAdjustmentCatalog.groups(isRAWSource: true, scope: .global, hasDepth: true)
        let detailKinds = groups
            .filter { $0.id == .detail || $0.id == .raw }
            .flatMap(\.kinds)
        #expect(!detailKinds.isEmpty)
        for kind in detailKinds {
            #expect(!mentionsAI(EditorAdjustmentCatalog.shortTitle(of: kind)), "short title of \(kind)")
            #expect(!mentionsAI(kind.displayName), "display name of \(kind)")
        }
        for group in groups where group.id == .detail || group.id == .raw {
            #expect(!mentionsAI(group.title))
        }
    }
}
