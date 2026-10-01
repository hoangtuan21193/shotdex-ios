import Foundation
import ShotDexKit
import Testing
@testable import ShotDex

/// FS-08.06 §4 — the Include Location switch becomes the three-level default,
/// once, without anyone losing the choice they made.
struct SettingsMetadataLevelMigrationTests {
    let defaults: UserDefaults
    let suite = "metadata-level-\(UUID().uuidString)"

    init() {
        defaults = UserDefaults(suiteName: suite)!
    }

    @Test func unwrittenIsAllMetadata() {
        defer { defaults.removePersistentDomain(forName: suite) }
        MetadataLevel.migrateLegacySharingSwitch(in: defaults)
        #expect(MetadataLevel.sharingDefault(in: defaults) == .all)
    }

    @Test func switchedOffBecomesNoLocation() {
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: SettingsKeys.legacyShareIncludesLocation)
        MetadataLevel.migrateLegacySharingSwitch(in: defaults)
        #expect(MetadataLevel.sharingDefault(in: defaults) == .noLocation)
        #expect(defaults.object(forKey: SettingsKeys.legacyShareIncludesLocation) == nil)
    }

    @Test func switchedOnStaysAllMetadata() {
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: SettingsKeys.legacyShareIncludesLocation)
        MetadataLevel.migrateLegacySharingSwitch(in: defaults)
        #expect(MetadataLevel.sharingDefault(in: defaults) == .all)
        #expect(defaults.object(forKey: SettingsKeys.legacyShareIncludesLocation) == nil)
    }

    /// A level chosen since is never overwritten by the old switch.
    @Test func aChosenLevelWins() {
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(MetadataLevel.noMetadata.rawValue, forKey: SettingsKeys.shareMetadataLevel)
        defaults.set(false, forKey: SettingsKeys.legacyShareIncludesLocation)
        MetadataLevel.migrateLegacySharingSwitch(in: defaults)
        #expect(MetadataLevel.sharingDefault(in: defaults) == .noMetadata)
    }

    @Test func anUnknownValueReadsAsAllMetadata() {
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("someday", forKey: SettingsKeys.shareMetadataLevel)
        #expect(MetadataLevel.sharingDefault(in: defaults) == .all)
    }
}
