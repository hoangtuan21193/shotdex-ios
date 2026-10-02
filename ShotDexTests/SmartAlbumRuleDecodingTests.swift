import Foundation
import Testing
@testable import ShotDex

/// Decoding smart albums written by older builds.
///
/// A `RuleField` this build does not know — the old pick/reject `flag` and star
/// `rating` were removed once (`v15`, `v16`) and are back since FS-01.12, so a
/// made-up name stands in for "removed" here. An album holding one must still
/// come back as its *other* rules.
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
        for removed in ["colorLabel", "cullScore"] {
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
        let query = try query(withRuleFields: ["colorLabel", "cullScore"])
        #expect(query.rules.isEmpty)
        #expect(query.isEmpty)
    }

    @Test func ordinaryRulesAreUntouched() throws {
        let query = try query(withRuleFields: ["cameraBody", "lens"])
        #expect(query.rules.map(\.field) == [.cameraBody, .lens])
    }

    /// FS-01.12 AC-8: a flag condition whose value this build does not know
    /// drops out on its own — the album keeps its other conditions and never
    /// becomes "every photo".
    @Test func unknownFlagValueDropsOnlyThatRule() throws {
        let json = #"""
        {"matchMode":"all","rules":[
          {"id":"\#(UUID().uuidString)","field":"flag","op":"isExactly","text":"maybe","boolValue":true,"focalMode":"actual"},
          {"id":"\#(UUID().uuidString)","field":"rating","op":"atLeast","text":"","number":4,"boolValue":true,"focalMode":"actual"}
        ]}
        """#
        let query = try JSONDecoder().decode(SmartAlbumQuery.self, from: Data(json.utf8))
        #expect(query.rules.map(\.field) == [.flag, .rating])
        let (sql, _) = SmartAlbumSQLBuilder.predicate(for: query)
        #expect(!sql.isEmpty)
        #expect(!sql.contains("photo_flag"))
        #expect(sql.contains("pending_photo_rating"))
    }
}
