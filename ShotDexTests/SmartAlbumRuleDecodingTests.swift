import Foundation
import Testing
@testable import ShotDex

/// Decoding smart albums written by older builds.
///
/// Two `RuleField` cases have been removed — the pick/reject `flag` (`v15`) and
/// the star `rating` (`v16`) — and both migrations rewrite the stored JSON. This
/// is the net under that: an album written by a build that ran before its
/// migration must still come back as its *other* rules.
struct SmartAlbumRuleDecodingTests {

    private func query(withRuleFields fields: [String]) throws -> SmartAlbumQuery {
        let rules = fields.map { field in
            """
            {"id":"\(UUID().uuidString)","field":"\(field)","op":"contains",\
            "text":"R6","boolValue":true,"focalMode":"actual"}
            """
        }
        let json = #"{"matchMode":"all","rules":[\#(rules.joined(separator: ","))]}"#
        return try JSONDecoder().decode(SmartAlbumQuery.self, from: Data(json.utf8))
    }

    /// An empty `SmartAlbumQuery` has no predicate, so it matches the whole
    /// library — decoding "my picks shot on the R6" into everything is a far
    /// worse answer than decoding it into "shot on the R6".
    @Test func aRuleWithARemovedFieldIsDroppedNotFatal() throws {
        for removed in ["flag", "rating"] {
            let query = try query(withRuleFields: [removed, "cameraBody"])
            #expect(query.rules.count == 1)
            #expect(query.rules.first?.field == .cameraBody)
            #expect(!query.isEmpty)
        }
    }

    /// Every rule being a removed one is the case that has to stay honest: the
    /// album now has no conditions, and `isEmpty` must say so rather than the
    /// screen resolving it against the whole library as if it were a filter.
    @Test func anAlbumOfOnlyRemovedRulesDecodesToNoRules() throws {
        let query = try query(withRuleFields: ["flag", "rating"])
        #expect(query.rules.isEmpty)
        #expect(query.isEmpty)
    }

    @Test func ordinaryRulesAreUntouched() throws {
        let query = try query(withRuleFields: ["cameraBody", "lens"])
        #expect(query.rules.map(\.field) == [.cameraBody, .lens])
    }
}
