import Foundation
import Testing
@testable import ShotDex

/// The launch sweep: our own scratch directories go, anything else stays.
@Suite struct TemporaryWorkspaceTests {
    private func makeSandbox() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SweepTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func itRemovesEveryPrefixTheAppCreates() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        for prefix in TemporaryWorkspace.prefixes {
            let leftover = sandbox.appendingPathComponent("\(prefix)\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
            // A copied source inside it, the thing that makes a leftover cost
            // something rather than being an empty folder.
            try Data("raw".utf8).write(to: leftover.appendingPathComponent("IMG_0001.CR3"))
        }

        let removed = TemporaryWorkspace.sweepOrphans(in: sandbox)

        #expect(removed == TemporaryWorkspace.prefixes.count)
        let remaining = try FileManager.default.contentsOfDirectory(at: sandbox, includingPropertiesForKeys: nil)
        #expect(remaining.isEmpty)
    }

    /// `/tmp` is shared with the system and with anything else that writes
    /// there. The sweep touches only what this app named.
    @Test func itLeavesEverythingElseAlone() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let strangers = ["com.apple.something", "ShotDex", "shotdexphoto-lowercase", "NSIRD_x"]
        for name in strangers {
            try Data().write(to: sandbox.appendingPathComponent(name))
        }

        let removed = TemporaryWorkspace.sweepOrphans(in: sandbox)

        #expect(removed == 0)
        let remaining = try FileManager.default.contentsOfDirectory(at: sandbox, includingPropertiesForKeys: nil)
        #expect(remaining.count == strangers.count)
    }

    @Test func aMissingDirectoryIsNotAnError() {
        let absent = FileManager.default.temporaryDirectory
            .appendingPathComponent("SweepTest-absent-\(UUID().uuidString)", isDirectory: true)
        #expect(TemporaryWorkspace.sweepOrphans(in: absent) == 0)
    }
}
