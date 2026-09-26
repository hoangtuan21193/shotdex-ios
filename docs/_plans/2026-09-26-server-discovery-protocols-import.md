# Plan: tự tìm server (FS-15.04) · tải ảnh về (FS-17) · WebDAV/FTPS/FTP (FS-15.05)

| | |
|---|---|
| Spec | [FS-15.04](../02-functional-spec/FS-15-server-upload/04-find-servers.md) AC-24…30 · [FS-17](../02-functional-spec/FS-17-import-from-server/README.md) AC-1…16 · [FS-15.05](../02-functional-spec/FS-15-server-upload/05-more-protocols.md) AC-31…36 |
| Intent | [server-discovery](../_intents/2026-09-26-server-discovery.md) · [import-from-server](../_intents/2026-09-26-import-from-server.md) · [more-file-protocols](../_intents/2026-09-26-more-file-protocols.md) |
| Ngày | 2026-09-26 |
| Duyệt | người dùng: "tự động làm spec và plan" — **dừng ở đây chờ duyệt**, chưa code |

Ba khối, làm theo thứ tự **A → B → C**: A nhỏ và dùng ngay trong form; B cần range read, thêm vào hai client đang
có; C thêm client mới — lúc đó client mới chỉ việc làm đủ hợp đồng `RemoteFileClient` (gồm range read) là B chạy
trên nó.

## Đối chiếu AC ↔ code

Tất cả là tính năng mới; không AC nào đã đạt. Cột "Bằng chứng" chỉ chỗ code sẽ nối vào.

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| 15.AC-24…26 | ❌ | không có mã Bonjour nào (`grep NWBrowser` rỗng) | `Domain/ServerUpload/DiscoveredServer.swift`: gộp bản ghi theo máy, map loại dịch vụ → giao thức/cổng, điền `FileServerDraft` |
| 15.AC-27 | ❌ | Info.plist chỉ có `NSLocalNetworkUsageDescription` (`ShotDex/Info.plist:31`) | thêm `NSBonjourServices`; bắt đầu browse ở `FileServerFormScreen` khi `draft.isNew` |
| 15.AC-28, 29 | ❌ | — | `Data/Sources/FileServer/LocalServerBrowser.swift` (`NWBrowser` + resolve host `.local`), sau protocol để test bằng bản giả |
| 15.AC-30 | ❌ | SMBClient có `listShares()` (checkout `SMBClient.swift:51`) nhưng app chưa gọi | `SMBFileClient.shareNames()` + lọc share `$` (Domain) + nút Choose… |
| 17.AC-1, 2 | ❌ | `RemoteFileClient.fileNames/folderNames` (`RemoteFileClient.swift`) chỉ có tên, không có kích thước/ngày | thêm `listEntries(in:) -> [RemoteEntry]` (tên, thư mục?, byte, ngày sửa) cho SMB/SFTP/fake; `Domain/ServerImport/ServerFolderListing.swift` lọc ảnh + ghép cặp, tái dùng `FileTypeBadge` (`LibraryGridItem.swift:33`) |
| 17.AC-3…5 | ❌ | spike 2026-09-26: ImageIO không lấy được thumbnail CR3 từ đoạn đầu; JPEG `PRVW` 1620×1080 nằm ở byte 93 984–273 850 | `readRange(path:offset:length:)` trên client (`FileReader.read(offset:length:)` SMB, `SFTPFile.read(from:length:)` SFTP); `Domain/ServerImport/EmbeddedPreview.swift` (ImageIO incremental → quét JPEG nhúng lớn nhất → tải trọn ≤ 25 MB) |
| 17.AC-6 | ❌ | — | `Data/Sources/FileServer/RemoteThumbnailCache.swift` (Caches/, khoá băm, trần 500 MB, LRU theo ngày truy cập) |
| 17.AC-7 | ❌ | lịch sử upload có `serverId`, `remotePath`, `byteCount`, `assetId` (`FileServer.swift` `ServerUploadRecord`) | bảng `server_downloads` (migration v21) + `ServerImportIndex` hỏi cả hai bảng, lọc asset còn tồn tại |
| 17.AC-8…11 | ❌ | tạo asset từ file đã có ở `PhotoLibraryService.importFile` (`PhotoLibraryService.swift:977`), chỉ một resource | `ServerDownloadSession` (actor, khuôn `ServerUploadSession`) + protocol `AssetCreating` (thật: PhotoKit `.photo` + `.alternatePhoto` + `creationDate` + album; giả: ghi lại yêu cầu) |
| 17.AC-12 | ❌ | tạo album có sẵn trong app (Selection overlay Turn 10A, `createAlbum/addAssets`) | tái dùng đường tạo album, thêm vào album trong cùng `performChanges` |
| 17.AC-13, 14, 16 | ❌ | khuôn `ServerUploadModel` (hold màn hình, huỷ, ra nền) | `ServerDownloadModel` cùng khuôn; `ScreenHolding` tái dùng |
| 17.AC-15 | ❌ | Utilities chỉ hiện khi có ảnh đã upload (`AlbumsScreen.swift:582`) | thẻ **luôn hiện** (người dùng chốt); màn `OnServerScreen`, `ServerBrowserScreen` (lưới dựng trên `PhotoGridLayout`), ui-drive |
| 15.AC-31, 32, 36 | ❌ | — | `WebDAVFileClient` trên `URLSession` + `PropfindParser` (Domain, test bằng XML mẫu) |
| 15.AC-33 | ❌ | host key SFTP đã có `HostKeyTrust` (`Domain/ServerUpload/HostKeyTrust.swift`) | tổng quát thành `TrustedFingerprint` dùng cho cả chứng chỉ TLS; đổi cột `hostKeyFingerprint` → `trustedFingerprint` |
| 15.AC-34 | ❌ | `FileServerFormScreen` chưa có ô theo giao thức | ô Path/Use HTTPS/TLS Mode + câu cảnh báo |
| 15.AC-35 | ❌ | iOS không có API FTP; khảo sát: không thư viện Swift nào đạt | libcurl + OpenSSL (người dùng chốt) — xcframework, lớp C bọc `curl_easy_setopt`, `FTPFileClient` |

Không có dòng ⚠️ "lệch" (tài liệu và code không mâu thuẫn — chỉ thiếu). Các ⚠️ CẦN QUYẾT trong spec giữ nguyên để
người dùng chốt khi duyệt plan.

## Tái dùng — không làm lại

`RemoteFileClient` + fake `InMemoryRemoteFileClient` · `RemoteFolderBrowser` (duyệt folder) · `FileServerRow` ·
`FileTypeBadge` · `PhotoGridLayout` (hình học lưới) · khuôn `ServerUploadSession`/`ServerUploadModel` (tiến độ theo
byte, ETA 30 s, hold màn hình, huỷ khi ra nền) · `RemoteFileError` (câu lỗi) · `FileServerNaming` · `TemporaryWorkspace`
(thêm tiền tố `ShotDexDownload-`) · `ScreenAwakeCoordinator`.

## File đổi theo tầng

| Tầng | A (tìm server) | B (tải về) | C (giao thức) |
|---|---|---|---|
| Domain | `DiscoveredServer`, `ShareNames` | `ServerFolderListing`, `EmbeddedPreview`, `ServerDownloadSession`, `ServerDownloadPlan` | `PropfindParser`, `TrustedFingerprint` |
| Data | `LocalServerBrowser`, `SMBFileClient.shareNames` | `RemoteFileClient.listEntries/readRange` (SMB, SFTP), `RemoteThumbnailCache`, `ServerDownloadStore`, migration v21, `PhotoKitAssetCreator` | `WebDAVFileClient`, `FTPFileClient`, migration v22, `RemoteFileClientFactory` |
| Features | `FileServerFormScreen` (section + Choose…) | `OnServerScreen`, `ServerBrowserScreen`, `ServerPhotoGrid`, `ServerDownloadSheet/Model`, `AlbumsScreen` | `FileServerFormScreen` (ô theo giao thức, cảnh báo, Trust chứng chỉ) |
| Khác | Info.plist `NSBonjourServices` | — | NF-03 đã ghi; privacy manifest nếu thư viện FTP cần |

## Task (một AC hoặc một cụm AC = một commit, test đi kèm)

**A — tìm server**
1. `DiscoveredServer` gộp/map/điền draft — 15.AC-24, 25, 26.
2. `LocalServerBrowser` + Info.plist + trạng thái rỗng/từ chối — 15.AC-29 (unit), 15.AC-27.
3. Section "Servers Found on This Network" + Choose… share — 15.AC-28, 30; ui-drive `server-discovery.json` với
   `dns-sd -R` quảng bá server SMB giả lập.

**B — tải về**
4. `listEntries` + `readRange` trên SMB/SFTP/fake; `ServerFolderListing` — 17.AC-1, 2.
5. `EmbeddedPreview` + spike đo theo hãng (xem Rủi ro) — 17.AC-3, 4, 5.
6. `RemoteThumbnailCache` — 17.AC-6.
7. `server_downloads` + `ServerImportIndex` — 17.AC-7.
8. `ServerDownloadSession` + `PhotoKitAssetCreator` — 17.AC-8…12.
9. `ServerDownloadModel` + sheet — 17.AC-13, 14, 16.
10. Utilities → On Server → duyệt → lưới → chọn → tải; ui-drive `server-import.json` trên 26.5, 18.6, iPad — 17.AC-15.

**C — giao thức**
11. Model + migration v22 + form theo giao thức + cảnh báo — 15.AC-34.
12. `PropfindParser` + `WebDAVFileClient` + bộ test hợp đồng dùng chung — 15.AC-31, 32; ui-drive với wsgidav — 15.AC-36.
13. `TrustedFingerprint` cho chứng chỉ TLS — 15.AC-33.
14. libcurl + OpenSSL xcframework (14a) rồi `FTPFileClient` FTP + FTPS (14b) — 15.AC-35 với pyftpdlib/vsftpd.

Sau mỗi task: build, test của task, sửa cột "Chứng minh bằng" và dòng Tiến độ của intent tương ứng. Đụng UI thì chụp
(`/screens`). Kết thúc mỗi khối: `/verify`.

## Rủi ro

| Rủi ro | Xử lý |
|---|---|
| **Preview nhúng theo hãng**: mới đo được CR3 (và JPEG). NEF/ARW/RAF/ORF/RW2/DNG chưa có file mẫu | task 5: tải mỗi hãng một file từ raw.pixls.us (CC0) vào scratchpad — người dùng đã cho phép 2026-09-26; AC-5 (icon) là đường lùi |
| Hộp Local Network **không hiện trên simulator** (quyền mạng nội bộ chỉ áp trên máy thật) | 15.AC-27 chỉ chứng minh được trên iPhone thật; simulator chứng minh phần tìm máy |
| Bonjour trên simulator dùng mạng của Mac | `dns-sd -R` quảng bá server giả lập được — đủ cho 15.AC-28 |
| **libcurl + OpenSSL** (chốt): phải build xcframework cho iOS device + simulator (arm64), giữ OpenSSL cập nhật, +vài MB binary | task 14 chia 14a (build xcframework bằng script có kiểm checksum nguồn, commit script chứ không commit binary nếu được — hỏi lại khi tới) và 14b (`FTPFileClient`); test với vsftpd `require_ssl_reuse=YES` + pyftpdlib TLS |
| Photos từ chối WebP/AVIF/GIF động | đo ở task 8 trên simulator; từ chối thì lỗi theo file (spec đã cho phép) |
| Migration v21 (bảng mới) và v22 (thêm cột, **đổi tên cột**) | app chưa phát hành: đổi tên cột bằng `ALTER TABLE … RENAME COLUMN`, không cần đường lùi; `photo_metadata` không đụng |
| Lưới server hàng nghìn file | liệt kê một lần, thumbnail chỉ cho ô sắp hiện, tối đa 4 luồng, huỷ khi cuộn qua; `perf-profiler` soát |
| Bộ nhớ: tách JPEG nhúng từ đoạn 512 KB, thu về 400 px | không giải mã full-res; `memory-leak` soát cache |
| Duo 669 pt: sheet tải về và lưới | chụp Duo ở `/verify` (lần trước thiếu) |

## Agent ở Deploy

`data-migration` (v21, v22) · `photokit-guard` (tạo asset, alternatePhoto, album, `.limited`) · `swift-concurrency`
(browser, session tải về, thumbnail song song) · `perf-profiler` + `memory-leak` (lưới, cache) · `privacy-manifest`
(`NSBonjourServices`, thư viện FTP) · `device-layout` + `ios26-parity` (lưới, sheet, form) · `copy-consistency`.
