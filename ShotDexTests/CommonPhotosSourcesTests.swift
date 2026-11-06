import Testing
@testable import ShotDex

/// FS-19.08 §6: which sources a run rescans, and when the destination is in none.
@Suite struct CommonPhotosSourcesTests {
    let nas = FileServer(id: "nas", name: "NAS", transferProtocol: .smb, host: "nas.local", port: 445, username: "u", folder: "photos/Family")
    let other = FileServer(id: "other", name: "Other", transferProtocol: .smb, host: "studio.local", port: 445, username: "u", folder: "photos")

    @Test func aSourceHoldingAFolderOrTheDestinationIsRescanned() {
        let sameShareOtherLogin = FileServer(id: "nas2", name: "NAS again", transferProtocol: .smb, host: "NAS.local", port: 445,
                                             username: "v", folder: "photos/Shared")
        let sources = [
            CommonPhotosSources.Source(sourceId: "family", connection: nas),
            CommonPhotosSources.Source(sourceId: "shared", connection: sameShareOtherLogin),
            CommonPhotosSources.Source(sourceId: "studio", connection: other),
        ]
        let ids = CommonPhotosSources.toRescan(paths: ["photos/Family/Tuan", "photos/Family/Vo", "photos/Shared/2026"],
                                               on: nas, sources: sources)
        #expect(ids == ["family", "shared"])
    }

    @Test func aSourceInsideARunFolderIsRescannedToo() {
        let inside = FileServer(id: "deep", name: "Deep", transferProtocol: .smb, host: "nas.local", port: 445, username: "u",
                                folder: "photos/Family/Tuan/2025")
        let sources = [CommonPhotosSources.Source(sourceId: "deep", connection: inside)]
        #expect(CommonPhotosSources.toRescan(paths: ["photos/Family/Tuan", "photos/Family/Vo"], on: nas, sources: sources) == ["deep"])
        // Held by a run folder is not holding the destination.
        #expect(!CommonPhotosSources.isIndexed("photos/Family", on: nas, sources: sources))
    }

    @Test func aDestinationNoSourceHoldsIsNotIndexed() {
        let sources = [CommonPhotosSources.Source(sourceId: "family", connection: nas)]
        #expect(CommonPhotosSources.isIndexed("photos/Family/Common", on: nas, sources: sources))
        #expect(!CommonPhotosSources.isIndexed("photos/Elsewhere", on: nas, sources: sources))
        #expect(!CommonPhotosSources.isIndexed("photos/Family/Common", on: other, sources: sources))
    }
}
