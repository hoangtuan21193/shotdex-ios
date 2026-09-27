import Foundation
import Testing
@testable import ShotDex

/// FS-17.01 §2b — AC-42, 43: each protocol's answer, read without a server.
@Suite struct StorageSpaceTests {
    @Test func smbAllocationUnits() {
        let space = StorageSpaceReading.smb(totalUnits: 1_000_000, freeUnits: 250_000, sectorsPerUnit: 8, bytesPerSector: 512)
        #expect(space == StorageSpace(total: 4_096_000_000, free: 1_024_000_000))
        #expect(StorageSpaceReading.smb(totalUnits: 1, freeUnits: 1, sectorsPerUnit: 0, bytesPerSector: 512) == nil)
        #expect(StorageSpaceReading.smb(totalUnits: .max, freeUnits: 1, sectorsPerUnit: 8, bytesPerSector: 512) == nil)
    }

    @Test func webdavQuota() {
        let body = Data("""
            <?xml version="1.0"?><d:multistatus xmlns:d="DAV:"><d:response><d:href>/dav/</d:href>
            <d:propstat><d:prop><d:quota-available-bytes>750</d:quota-available-bytes>
            <d:quota-used-bytes>250</d:quota-used-bytes></d:prop></d:propstat></d:response></d:multistatus>
            """.utf8)
        #expect(StorageSpaceReading.webdavQuota(body) == StorageSpace(total: 1000, free: 750))
        let noQuota = Data("""
            <?xml version="1.0"?><d:multistatus xmlns:d="DAV:"><d:response><d:href>/dav/</d:href>
            <d:propstat><d:prop/><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat></d:response></d:multistatus>
            """.utf8)
        #expect(StorageSpaceReading.webdavQuota(noQuota) == nil)
    }

    @Test func sftpDiskFree() {
        let df = """
            Filesystem 1024-blocks Used Available Capacity Mounted on
            /dev/disk1 976490576 488245288 488245288 50% /home
            """
        #expect(StorageSpaceReading.diskFree(df) == StorageSpace(total: 999_926_349_824, free: 499_963_174_912))
        let spaced = "Filesystem 1024-blocks Used Available Capacity Mounted on\nMy Disk 100 40 60 40% /Volumes/My Disk\n"
        #expect(StorageSpaceReading.diskFree(spaced) == nil || StorageSpaceReading.diskFree(spaced)?.free == 61_440)
        #expect(StorageSpaceReading.diskFree("sh: df: not found") == nil)
        #expect(StorageSpaceReading.diskFree("") == nil)
    }

    @Test func footerText() {
        #expect(StorageSpace(total: 4_000_000_000_000, free: 1_200_000_000_000).footerText == "1.2 TB free of 4 TB")
        #expect(StorageSpace(total: nil, free: 1_200_000_000_000).footerText == "1.2 TB free")
    }
}
