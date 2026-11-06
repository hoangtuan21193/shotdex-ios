import Foundation
import Testing
@testable import ShotDex

/// FS-06.12 §3: the line under a smart album kept in Photos.
struct PhotosAlbumSyncLineTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func offSaysNothing() {
        #expect(PhotosAlbumSyncLine.line(state: .synced, isEnabled: false, assetCount: 3, lastSyncedAt: nil, progress: nil) == nil)
        #expect(PhotosAlbumSyncLine.line(state: nil, isEnabled: true, assetCount: 0, lastSyncedAt: nil, progress: nil) == nil)
    }

    /// AC-2: count, when, and the Move to Shared Library hint.
    @Test func syncedCountAndHint() throws {
        let line = try #require(PhotosAlbumSyncLine.line(state: .synced, isEnabled: true, assetCount: 8_412,
                                                          lastSyncedAt: now.addingTimeInterval(-120), progress: nil, now: now))
        #expect(line.text.hasPrefix("In Photos · 8,412 photos · Updated "))
        #expect(line.showsHint)
    }

    /// AC-12: progress while writing, no hint.
    @Test func updatingShowsProgress() throws {
        let line = try #require(PhotosAlbumSyncLine.line(state: .updating, isEnabled: true, assetCount: 0, lastSyncedAt: nil,
                                                          progress: (3_200, 8_412)))
        #expect(line.text == "Updating album in Photos… 3,200 of 8,412")
        #expect(!line.showsHint)
    }

    /// AC-10, AC-13: deleted in Photos (switch already off) and a failed write.
    @Test func deletedAndFailed() {
        #expect(PhotosAlbumSyncLine.line(state: .deletedInPhotos, isEnabled: false, assetCount: 0, lastSyncedAt: nil, progress: nil)?.text
                == "The album was deleted in Photos. Keep in Photos is off.")
        #expect(PhotosAlbumSyncLine.line(state: .failed, isEnabled: true, assetCount: 0, lastSyncedAt: nil, progress: nil)?.text
                == "Couldn’t update the album in Photos. Will try again.")
    }
}
