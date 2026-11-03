import Foundation
import Testing
@testable import ShotDex

/// FS-19.08 §6d: the plan the scan shows — each Same photo's name in the
/// destination, by the run's own rule.
@Suite struct CommonPhotosDestinationPlanTests {
    typealias Plan = CommonPhotosDestinationPlan

    private func photo(_ name: String, _ size: Int64 = 100, sha: String? = nil) -> Plan.Photo {
        Plan.Photo(name: name, size: size, sha256: sha ?? "sha-\(name.lowercased())")
    }

    @Test func freeNameKeepsItsName() {
        #expect(Plan.landings([photo("IMG_1.JPG")], in: []) == [.name("IMG_1.JPG")])
    }

    /// AC-175: the destination holds the name with other bytes — the next
    /// free name; with the same bytes — Already there, under its spelling.
    @Test func takenNameAndSameBytes() {
        let existing = [Plan.Existing(name: "IMG_0001.JPG", size: 100, sha256: "other"),
                        Plan.Existing(name: "img_0002.jpg", size: 100, sha256: "sha-img_0002.jpg")]
        let landings = Plan.landings([photo("IMG_0001.JPG"), photo("IMG_0002.JPG")], in: existing)
        #expect(landings == [.name("IMG_0001 (2).JPG"), .alreadyThere("img_0002.jpg")])
    }

    /// Another size under the name is never the same bytes: no read, next name.
    @Test func otherSizeIsNotRead() {
        let existing = [Plan.Existing(name: "IMG_1.JPG", size: 999)]
        #expect(Plan.toHash([photo("IMG_1.JPG")], in: existing).isEmpty)
        #expect(Plan.landings([photo("IMG_1.JPG")], in: existing) == [.name("IMG_1 (2).JPG")])
    }

    /// Only a same-name, same-size file with no SHA yet is read — once.
    @Test func readsOnlyWhatDecides() {
        let existing = [Plan.Existing(name: "IMG_1.JPG", size: 100), Plan.Existing(name: "IMG_2.JPG", size: 100, sha256: "x"),
                        Plan.Existing(name: "IMG_3.JPG", size: 5)]
        let photos = [photo("IMG_1.JPG"), photo("img_1.jpg", sha: "b"), photo("IMG_2.JPG"), photo("IMG_3.JPG")]
        #expect(Plan.toHash(photos, in: existing).map(\.name) == ["IMG_1.JPG"])
    }

    /// Two photos of one name in one run: the second takes the next free
    /// name, as the run does (`CommonPhotosRunnerTests.sameNameTwiceInOneRun`).
    @Test func sameNameTwiceInOneRun() {
        let landings = Plan.landings([photo("IMG.JPG", sha: "a"), photo("IMG.JPG", sha: "b")], in: [])
        #expect(landings == [.name("IMG.JPG"), .name("IMG (2).JPG")])
    }
}
