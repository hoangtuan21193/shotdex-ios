import Testing
@testable import ShotDex

/// FS-06.10 AC-3, AC-4 — every original resource has to be on this device.
struct OriginalPresenceTests {

    /// AC-3: a Live Photo whose still is here and whose movie is in iCloud is
    /// not on this device.
    @Test func livePhotoWithMovieInCloudIsICloudOnly() {
        let required = OriginalPresence.required(among: [.photo, .pairedVideo])
        #expect(required == [.photo, .pairedVideo])
        #expect(OriginalPresence.judge([.local, .inCloud]) == .iCloudOnly)
    }

    /// AC-4: an edited photo whose original is here and whose render is in
    /// iCloud is not on this device; the adjustment data does not count.
    @Test func editedPhotoWithRenderInCloudIsICloudOnly() {
        let required = OriginalPresence.required(among: [.photo, .other, .fullSizePhoto, .other])
        #expect(required == [.photo, .fullSizePhoto])
        #expect(OriginalPresence.judge([.local, .inCloud]) == .iCloudOnly)
    }

    @Test func everyResourceHereIsOnDevice() {
        let required = OriginalPresence.required(among: [.photo, .alternatePhoto, .pairedVideo, .fullSizePhoto, .fullSizePairedVideo])
        #expect(required.count == 5)
        #expect(OriginalPresence.judge(Array(repeating: .local, count: required.count)) == .onDevice)
    }

    @Test func editedVideoNeedsBothMovies() {
        #expect(OriginalPresence.required(among: [.video, .fullSizeVideo, .other]) == [.video, .fullSizeVideo])
        #expect(OriginalPresence.judge([.inCloud, .local]) == .iCloudOnly)
    }

    /// A check that could not tell leaves the item unchecked — unless another
    /// resource is already known to be in iCloud.
    @Test func unknownLeavesItUnchecked() {
        #expect(OriginalPresence.judge([.local, .unknown]) == nil)
        #expect(OriginalPresence.judge([.unknown, .inCloud]) == .iCloudOnly)
    }

    @Test func nothingRequiredIsUnchecked() {
        #expect(OriginalPresence.required(among: [.other, .other]).isEmpty)
        #expect(OriginalPresence.judge([]) == nil)
    }

    @Test func duplicateResourcesCountOnce() {
        #expect(OriginalPresence.required(among: [.photo, .photo, .pairedVideo]) == [.photo, .pairedVideo])
    }
}
