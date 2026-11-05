# Kế hoạch — FS-19.08 §6e: quét nhanh folder ngày · xếp folder chung · giữ thông tin file

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-19.08 §6e`](../02-functional-spec/FS-19-photo-sources/08-common-photos.md) · AC-193…226 ở [`08b`](../02-functional-spec/FS-19-photo-sources/08b-common-photos-ac.md) · ghi chú ở FS-15.02, FS-22.01 §5 |
| Intent | [dated-folders-scan](../_intents/2026-11-05-common-photos-dated-folders-scan.md) · [destination-layout](../_intents/2026-11-05-common-photos-destination-layout.md) · [keep-file-dates](../_intents/2026-11-05-common-photos-keep-file-dates.md) |
| Commit spec | `9fbba089` (intent `1c6ace09`) |
| Ngày | 2026-11-05 |
| Trạng thái | đang làm — duyệt 2026-11-05 (Q1: a); T0–T10b xong — loop [FS1908_6E_LOOP.md](FS1908_6E_LOOP.md) |

## 1. Hiểu đúng chưa

Ba việc trên cùng tính năng Find Common Photos (Mac), một phần lan sang Server Upload và Backup:

1. **Quét nhanh.** Copy có ô Quick Check (tắt sẵn): cặp cùng đường dẫn tương đối + cùng cỡ + 3 mẫu 64 KB trùng thành
   Same (quick), không băm cả file. Move luôn băm đủ. Chạy lại dùng danh sách folder đã lưu cho folder lá có giờ sửa
   không đổi (trong 24 giờ, server có giờ sửa folder, không phải Scan Everything).
2. **Xếp folder chung.** Dùng lại `BackupOrganize` + `BackupPathPlanner` + trang Organize Mac của Backup; thêm mức
   **Same as Source**, bỏ Album; lưu theo bộ; mặc định bộ mới Same as Source, bộ cũ No Folders; ảnh đã gom ở nguyên chỗ;
   Undo xoá folder con rỗng do lượt đó tạo.
3. **Giữ thông tin file.** Sau khi đẩy part và đọc lại SHA, trước khi đổi tên: đặt ngày sửa, ngày tạo, cờ (và tag nếu
   được) theo bản ở folder đầu; liệt kê lại kiểm ±2 s; hỏng thì ghi `dates not kept`, ảnh vẫn Copied. Undo Move trả
   thông tin của chính bản đã xoá. Restore File Info… cho lượt cũ. Upload/Backup cùng đường.

## 2. Đối chiếu AC ↔ code

### Quét nhanh, chạy lại

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-193 ô Quick chỉ ở Copy | ❌ | Action picker `ShotDexMac/Servers/CommonPhotos/MacCommonPhotosSheet.swift:320-322`; không có ô nào | `quickCheck` trên `CommonPhotosScanModel`; ô trong sheet, ẩn khi Move; board trước |
| AC-194 cùng đường dẫn → 3 mẫu, 0 sha | ❌ | mẫu 3×64 KB `CommonPhotosVerifier.swift:138-154`, rồi luôn `fullHash` :155-177 (`client.sha256` :160) | nhánh quick trong Verifier: cặp cùng `relativePath` (casefold + NFC như §5) + mẫu trùng → Same(quick), bỏ `fullHash` |
| AC-195 mẫu lệch rơi; lệch ngày vẫn băm | ⚠️ một nửa | mẫu lệch đã rơi hôm nay (Verifier :78-84); cặp khác đường dẫn đi `fullHash` | chỉ viết test cho phần đã có; phần quick là AC-194 |
| AC-196 Copy quick: SHA lúc tải, B 0 đọc, Check = quick, không vào bảng SHA | ❌ | Copy tải bản đầu có SHA `CommonPhotosRunner.swift:401`; bảng SHA đã đọc = `common_photo_scan_records` (`CommonPhotosScanRecords.swift:50`, ghi ở `CommonPhotosScanModel.swift:819-830`); CSV `CommonPhotosLog.swift:46-59` chưa có cột Check | ảnh quick: SHA nhóm = SHA tải về của bản đầu; `remember` bỏ bản không băm; cột `check` trên `common_photo_items` + CSV |
| AC-197 đổi sang Move bỏ kết quả quick | ⚠️ có khuôn | `action` didSet :77-84 đã `resetScan` + notice `.moveChecksAgain` khi Copy scan tin cache | mở rộng điều kiện: kết quả có hàng quick → cũng reset. Test |
| AC-198 Run Again chỉ liệt kê folder đổi | ❌ | `ServerTreeListing.list` `ShotDex/Data/Sources/FileServer/ServerTreeListing.swift:9-27` bỏ folder khỏi kết quả, không giữ giờ sửa folder; `RemoteEntry.modified` có cho folder ở SMB (`SMBFileClient.swift:209`) và Files (`FilesFolderClient.swift:144`); fake: `listingCount` `ShotDexTests/ServerUploadFakes.swift:192`, folder `modified` = nil :180 | bảng mới `common_photo_folder_listings` (connection, path, folderModified, hasSubfolders, entries JSON, listedAt); `CommonPhotosTreeListing` (Data) gọi `ServerTreeListing` theo từng folder và dùng cache; fake thêm giờ sửa folder |
| AC-199 folder có con thì vẫn liệt kê | ❌ | — | luật trong `CommonPhotosListingCache` (Domain, thuần) |
| AC-200 không giờ sửa / >24 h / Scan Everything | ❌ | `scanEverything()` `CommonPhotosScanModel.swift:393` | cùng luật; `lastFullListingAt` theo setKey |
| AC-201 đo NAS thật | ❓ | cần chạy app trên NAS người dùng | đo ở `/verify`, chỉ Scan (đọc) |

### Organize

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-202 bộ mới Same as Source | ❌ | Copy ghi phẳng: `CommonPhotosDestinationPlan.swift:53-65`, runner `freeName` :360; `BackupOrganize.Levels` `BackupShared/BackupSettings.swift:32-34` không có mức này | thêm `Levels.sameAsSource`; `BackupPlacementInput` thêm `sourceFolder: String?` (`BackupPathPlanner.swift:4-19`); planner :45-76 trả folder đó |
| AC-203 bộ cũ No Folders | ❌ | sheet không lưu thiết lập; setKey `CommonPhotosIncremental.swift:20-23` | thiết lập theo setKey; không có hàng mà setKey đã có run → `noFolders` |
| AC-204 Y›M›D + video tách | ⚠️ một nửa | planner đã làm đúng việc này cho Backup (`BackupPathPlannerTests`, 8 test) | test Common Photos gọi planner với ngày + kind của ảnh |
| AC-205 ngày video: folder → mtime | ❌ | `CommonPhotosCaptureKey.swift:15-17` chỉ đọc EXIF ảnh | `CommonPhotosOrganizeDate` (Domain): index → EXIF → tên folder (`2025/03/15`, `2025-03-15`, `20250315`, `2025/03`) → `modified` |
| AC-206 tên Date and Time trùng → (2) | ❌ | `ServerUploadPath.nextFreeName` :44-55 xét một folder | Already there / tên trống xét trong folder đích của ảnh |
| AC-207 Already there theo folder con | ❌ | `landings` chỉ xét tên ở gốc :53-65 | liệt kê cây folder chung (qua cache AC-198) và xét theo đường dẫn đủ |
| AC-208 ảnh đã gom ở nguyên chỗ | ⚠️ có khuôn | `CommonPhotosIncremental` lọc ảnh đã gom theo `sources` (:38-50), không theo đích → đổi Organize không chép lại | test khoá lại + câu dưới Organize |
| AC-209 Undo xoá folder con rỗng | ❌ | Undo `CommonPhotosUndoer.swift:351` (undoCopy); `removeEmptyDirectory` có ở protocol `RemoteFileClient.swift:56` | bảng `common_photo_created_folders(runId, path)`; Undo xoá sâu trước, chỉ khi rỗng |
| AC-210 tự gom theo Organize | ❌ | `CommonPhotosGatherPass.swift:100` dựng ScanModel | GatherPass nạp thiết lập theo setKey |

### Giữ thông tin file

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-211 SMB ngày + cờ (+ tag) | ❌ | `SMBClient.upload` gọi `restoreFileAttributes` theo `fstat` file tạm (`SMBClient.swift:160-168`, `FileWriter.swift:129-171`) — nguồn gốc lỗi; `Session.setInfo(path:_:)` public `Session.swift:582`; `FileBasicInformation` init internal, `FileTime(Date)` internal | protocol mới `RemoteFileClient.applyFileInfo(_:to:)` + `fileInfo(at:)`; SMB: struct riêng phía app theo `FileInformationClass` (public), tự đổi Date → FILETIME (1601, 100 ns). Tag/ADS: spike T1 |
| AC-212 lấy bản folder đầu | ❌ | `CommonPhotosItem.Source.modifiedAt` có (`CommonPhotosRunner.swift:112`) | đọc `fileInfo(at:)` bản đầu khi chạy |
| AC-213 Move: đổi chỗ và lùi về chép, `.xmp` | ⚠️ một nửa | đổi chỗ `client.move` :528 giữ ngày (NTFS); lùi về `copy` :536-545 thì không; sidecar :723 | lùi về chép dùng cùng đường Copy; test cả hai |
| AC-214 server từ chối → báo trước | ❌ | — | bảng `server_file_info_support(connectionId, dates, tags, checkedAt)` dùng chung Upload/Backup; câu dưới Action |
| AC-215 đặt được mà lệch | ❌ | — | `VerifiedRemoteWrite` kiểm lại sau đổi tên, ±2 s |
| AC-216 Undo Move trả thông tin | ❌ | re-upload `CommonPhotosUndoer.swift:239-244`, sidecar :323-340; lưu khi xoá chỉ có `modifiedAt` | `Source` thêm `created`, `attributes` (JSON trong `sources`, decode khoan dung, không migration); Undo đặt lại |
| AC-217 Restore File Info… | ❌ | — | `CommonPhotosInfoRestorer` (Domain) + mục trong cửa sổ log + chuột phải |
| AC-218 Already there không bị đụng | ✅ đường code | Copy skip ở :348-358 trước mọi ghi | chỉ test khoá lại, sau khi T2 thêm lệnh đặt thông tin |
| AC-219 Upload + Backup | ❌ | Upload: `ServerUploadSession.swift:243-257` (ngày chụp lấy từ PHAsset ở `PhotoKitOriginalExporter.swift:38`); Backup: `BackupRunner.swift:378-388`, ngày nguồn ở `PhotoKitBackupSource.swift:41-49`, `SourceCopyBackupSource.swift:21-26` | truyền `RemoteFileInfo` vào `VerifiedRemoteWrite` |

### 2b. ⚠️ Cần người dùng quyết

| # | Chỗ lệch | Spec nói | Code / thư viện có |
|---|---|---|---|
| Q1 | SFTP giữ ngày | bảng §6e: ✅ `setstat` mtime + quyền | **Citadel 0.9.2 không có `setstat`/`fsetstat` public** (chỉ case nội bộ `SFTPSerializer.swift:109-118`). `openFile(…, attributes:)` đặt được lúc tạo, nhưng ghi dữ liệu sau đó làm server đổi lại ngày sửa. Vá Citadel trái luật "không vá thư viện" (2026-11-04). |

**Người dùng chốt 2026-11-05: (a).** Phương án Q1: (a) **SFTP báo `dates not kept`** như WebDAV từ chối, quyền đặt lúc `openFile` — đề xuất; (b) tự gửi gói
`SETSTAT` qua kênh SSH riêng (Citadel không cho dùng chung kênh SFTP → phải mở subsystem thứ hai, ~200 dòng giao thức
tự viết); (c) đổi/vá thư viện.

### 2c. ❓ Chưa kết luận được (không cần người dùng, làm ở T1)

- **Tag Finder / ADS trên SMB.** `SMBClient` gửi tên `file:stream` nguyên văn (`Pathname.swift:13-17` không lọc `:`),
  nhưng không có parser `FileStreamInformation` (chỉ có case enum). Server SMB cục bộ (impacket trên APFS) không giữ
  luồng như NTFS → test cục bộ không chứng minh được. T1 thử: liệt kê luồng bằng `queryInfo` raw + tự parse, đọc/ghi
  `:AFP_AfpInfo` và `:com.apple.metadata:_kMDItemUserTags`. Trên NAS thật chỉ thử khi người dùng cho ghi file tạm
  (lần trước cho đúng một lần, cho đo). Không được → log `tags not kept` (spec đã cho đường này).
- **WebDAV `PROPPATCH`** trên wsgidav cục bộ: thử ở T1; không có server IIS/Synology/Nextcloud để thử thật.

## 3. Dùng lại (không viết lại)

- `BackupOrganize`, `BackupPathPlanner`, `BackupDateName`, `BackupOrganizeText` (summary/sampleTree), trang
  `MacBackupOrganizePage` (`ShotDexMac/Backup/MacBackupFormSheet.swift:159`, chỉ cần `Binding<BackupOrganize>`).
  Trang nhận thêm danh sách mức được hiện (Backup: bỏ `sameAsSource`; Common Photos: bỏ `album`); iOS
  `BackupOrganizeScreen.swift:172-181` cũng lọc `sameAsSource`.
- `VerifiedRemoteWrite` (đường ghi duy nhất của Upload, Backup, Common Photos) — thêm một bước đặt thông tin trước
  `moveIntoPlace` và một bước kiểm sau.
- `ServerTreeListing` giữ nguyên cho index nguồn (FS-19.03); cache chỉ ở lớp Common Photos.
- `CommonPhotosScanRecords` (bảng SHA đã đọc), `CommonPhotosIncremental` (ảnh đã gom), `CommonPhotosWatchStore`
  (setKey), `removeEmptyDirectory`, fake `InMemoryRemoteFileClient` (đã đếm `listingCount`, `rangeReadPaths`,
  `sha256Paths`, `downloadCount`, `uploadCount`).
- `CommonPhotosSMBTests` (impacket 127.0.0.1:4450) và `CommonPhotosWebDAVTests` (wsgidav 8096) cho e2e.

## 4. File đổi

| File | Tầng | Đụng gì | Mới / sửa |
|---|---|---|---|
| `ShotDex/Domain/ServerUpload/RemoteFileClient.swift` | Domain | `RemoteFileInfo` (modified, created, readOnly, hidden, archive, posixPermissions, tags?) + `fileInfo(at:)`, `applyFileInfo(_:to:) -> FileInfoOutcome`, mặc định = không hỗ trợ | sửa |
| `ShotDex/Domain/ServerUpload/VerifiedRemoteWrite.swift` | Domain | `applyInfo` trước đổi tên, kiểm ±2 s sau | sửa |
| `ShotDex/Data/Sources/FileServer/SMBFileClient.swift` (+ struct `SMBBasicInfo`) | Data | `setInfo` FileBasicInformation, đọc `fileInfo`, luồng phụ nếu T1 được | sửa |
| `WebDAVFileClient.swift`, `SFTPFileClient.swift`, `FilesFolderClient.swift` | Data | PROPPATCH / `X-OC-Mtime`; SFTP theo Q1; Files = `FileManager.setAttributes` | sửa |
| `RoutedRemoteFileClient.swift`, `ConnectionLock.swift` (`LockedRemoteFileClient`), `CommonPhotosScanModel.swift` (`WatchedClient` :875) | Data | chuyển tiếp hai lệnh mới (không thì mặc định nuốt mất) | sửa |
| `ShotDex/Domain/CommonPhotos/CommonPhotosVerifier.swift`, `CommonPhotosMatcher.swift` | Domain | nhánh quick | sửa |
| `ShotDex/Domain/CommonPhotos/CommonPhotosListingCache.swift` | Domain | luật dùng lại danh sách (thuần) | mới |
| `ShotDex/Data/Sources/FileServer/CommonPhotos/CommonPhotosTreeListing.swift` | Data | liệt kê có cache | mới |
| `ShotDex/Domain/CommonPhotos/CommonPhotosOrganizeDate.swift` | Domain | ngày để xếp (index → EXIF → folder → mtime) | mới |
| `CommonPhotosDestinationPlan.swift`, `CommonPhotosRunner.swift`, `CommonPhotosUndoer.swift`, `CommonPhotosLog.swift` | Domain | đường đích đủ, tạo folder con, thông tin file, cột `Check`/`File info` | sửa |
| `ShotDex/Domain/CommonPhotos/CommonPhotosInfoRestorer.swift` | Domain | Restore File Info… | mới |
| `BackupShared/BackupSettings.swift`, `BackupPathPlanner.swift` | Domain (chung) | `Levels.sameAsSource`, `sourceFolder` | sửa |
| `ShotDex/Core/Models/CommonPhotosItem.swift`, `CommonPhotosRun.swift` | Model | `check`, `fileInfo`, `Source.created/attributes`, `organize` | sửa |
| `ShotDex/Data/Database/AppDatabase+CommonPhotos.swift`, `CommonPhotosStore.swift` | Data | migration: `common_photo_folder_listings`, `common_photo_set_settings(setKey, organize JSON, quickCheck)`, `common_photo_created_folders`, cột `check`/`fileInfo` trên items, `server_file_info_support` | sửa |
| `ServerUploadSession.swift`, `BackupRunner.swift` (+ nguồn Backup) | Data | truyền `RemoteFileInfo` | sửa |
| `ShotDexMac/Servers/CommonPhotos/MacCommonPhotosSheet.swift`, `MacCommonPhotosRunWindow.swift`, `ShotDexMac/Backup/MacBackupFormSheet.swift`, `ShotDex/Features/Backup/BackupOrganizeScreen.swift` | Features | ô Quick, dòng Organize, nhãn Quick, cột Check, Restore File Info…, lọc mức | sửa |
| Board Mac `MAC_CommonPhotos`, `MAC_BackupOrganize`, `MAC_CommonPhotosRun` | design | vẽ trước code | sửa |

Logic nằm ở Domain (thuần, test bằng fake); View chỉ đọc model. Không dữ liệu người dùng tự gõ vào `photo_metadata`.

## 5. Thứ tự task

Một task một commit; mỗi commit sửa cột "Chứng minh bằng" của AC trong 08b và dòng Tiến độ ba intent. Giữ thông tin
file làm trước: mức độ cao nhất và đổi đường ghi chung mà Organize cũng đi qua.

| # | Task | AC | Test kèm theo |
|---|---|---|---|
| T0 | Board: `MAC_CommonPhotos` (ô Quick, dòng Organize + câu "already gathered", câu "does not keep file dates", hàng kế hoạch đường dẫn đủ + nhãn Quick), `MAC_BackupOrganize` (Same as Source khi mở từ Common Photos), `MAC_CommonPhotosRun` (cột Check, File info, Restore File Info…). Đọc canvas trước khi sửa | — | `Tools/design-board render` sáng/tối |
| T1 | Spike: SMB luồng phụ (impacket + parse `FileStreamInformation`), WebDAV PROPPATCH trên wsgidav. Ghi kết quả vào §6e | (AC-211 phần tag, AC-214) | test probe, xoá sau khi ghi số |
| T2 | `RemoteFileInfo` + hai lệnh trên protocol (**không** mặc định — compiler bắt mọi conformer), SMB (ngày + cờ, thứ tự §6e, READONLY sau đổi tên, gỡ cờ trước xoá)/WebDAV/Files, SFTP báo `dates not kept` + quyền lúc `openFile` (Q1), forwarders, fake ghi lại lệnh đặt; `VerifiedRemoteWrite` đặt + kiểm (một lệnh hỏi một file, ±2 s giây chẵn); **một migration** cho mọi bảng/cột §6e; chạy `swift-concurrency` sau task | AC-211 (ngày, cờ), AC-215, AC-218, AC-222, AC-223 | `CommonPhotosSMBTests.copyKeepsFileInfo` (impacket), `VerifiedRemoteWriteTests.infoDriftIsReported`, `CommonPhotosRunnerTests.alreadyThereKeepsItsInfo` |
| T3 | Runner Copy/Move dùng thông tin bản folder đầu; sidecar; Move lùi về chép vẫn Move khi không giữ ngày, lưu thông tin bản bị xoá **trước** lệnh xoá; `server_file_info_support` (cập nhật mỗi lượt); cột `File info` log/CSV; câu dưới Action | AC-212, AC-213, AC-214, AC-224 | `CommonPhotosRunnerTests.firstFolderInfoWins`, `moveFallbackKeepsInfo`, `refusedDatesAreRemembered`; `CommonPhotosWebDAVTests` |
| T4 | Undo Move trả thông tin chính bản đã xoá (`Source.created/attributes`) | AC-216 | `CommonPhotosUndoTests.undoMoveRestoresInfo` |
| T5 | Restore File Info… (Domain + cửa sổ log + chuột phải, có Stop và làm tiếp) | AC-217, AC-225 | `CommonPhotosInfoRestorerTests`; ảnh Mac sáng/tối |
| T6 | Server Upload + Backup truyền `RemoteFileInfo` (Photos: ngày chụp làm ngày tạo = ngày sửa); mọi chỗ ghi `modifiedAt` bản trên server (On Server, lịch sử upload) ghi ngày **sau** khi đặt | AC-219, AC-220 | `ServerUploadSessionTests.uploadCarriesCaptureDate`, `BackupRunnerTests.folderSourceKeepsDate` |
| T7 | Quick Check: Verifier, ô sheet, reset khi sang Move, nhãn Quick, cột Check, bỏ bản không băm khỏi bảng SHA | AC-193…197 | `CommonPhotosQuickCheckTests` (5 test, đếm `rangeReadPaths`/`sha256Paths`/`downloadCount`); ảnh sheet Copy/Move |
| T8 | Cache danh sách folder (bảng + luật + `CommonPhotosTreeListing`), Move không dùng cache, fake có giờ sửa folder | AC-198…200, AC-221 | `CommonPhotosListingCacheTests` (đếm `listingCount`) |
| T9 | Organize Domain: `Levels.sameAsSource`, `sourceFolder` (tên sửa như Backup), `CommonPhotosOrganizeDate` (EXIF lấy từ mẫu đầu đã đọc), đích theo folder con + Already there theo đường đủ, chỉ liệt kê folder đích của kế hoạch | AC-204…207, AC-226 | `CommonPhotosOrganizeTests`, `BackupPathPlannerTests` thêm Same as Source |
| T10 | Organize lưu theo bộ + mặc định + trang Organize trong sheet + câu đã gom + tạo/ghi folder con + Undo xoá folder rỗng + tự gom | AC-202, 203, 208, 209, 210 | `CommonPhotosOrganizeTests`, `CommonPhotosUndoTests.undoRemovesEmptyFolders`, `CommonPhotosGatherTests.gatherUsesOrganize`; ảnh Mac |
| T10b | Luồng phụ SMB (tag Finder, Finder info): liệt kê + chép ≤ 64 KB, tên luồng đúng như server trả, nhớ "không có luồng" theo connection | AC-211 (tag) | `SMBStreamInfoTests` (parse buffer), runner với fake có luồng; NAS ở T11 |
| T11 | `/verify`: e2e SMB + WebDAV, ảnh Mac sáng/tối so board, đo NAS (chỉ Scan) | AC-201 + tất cả | — |

## 6. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| `project.pbxproj` đang bị phiên khác sửa dở; file Swift mới cần thêm vào target (và `Tools/mac-membership`) | cao | gom kiểu mới vào file đã có khi hợp lý; file mới thì chờ phiên kia commit pbxproj rồi mới thêm, không đè |
| Migration: 3 bảng + cột mới; phiên khác có thể chiếm số version | trung bình | lấy id kế tiếp lúc làm (`v58-originalPresence` là cuối hôm nay); bảng mới đều là dữ liệu dẫn xuất / thiết lập, xoá theo connection như các bảng Common Photos khác; app chưa ra → không back-compat |
| Thêm lệnh vào `RemoteFileClient` có mặc định → wrapper quên chuyển tiếp nuốt mất im lặng (đã từng với `copyOnServer` ở `WatchedClient`) | cao | test qua `LockedRemoteFileClient` + `RoutedRemoteFileClient`; kiểm `WatchedClient` cả `copyOnServer` (ghi `REVIEW_QUEUE.md` nếu thiếu) |
| `Levels.sameAsSource` vào enum chung → Backup iPhone/Mac hiện mức này nếu quên lọc (các trang lặp `allCases`) | trung bình | trang nhận danh sách mức; test khoá danh sách mức của Backup |
| Quick Check sai = Copy ảnh khác byte vào Shared (không mất dữ liệu, Move không dùng) | thấp | chỉ Copy; SHA tải về của bản đầu được ghi; người dùng bật tay, câu phụ nói rõ |
| Cache danh sách bỏ sót file ghi đè tại chỗ | trung bình | đúng giới hạn spec: 24 h liệt kê đủ, Scan Everything; folder có con luôn liệt kê |
| Đọc EXIF cho Organize thêm ~25 phút trên Tuan/Hue | chắc chắn | chỉ khi mức theo ngày; tiến độ đếm bước; đo ở T11 |
| Concurrency: `WatchedClient`, runner là struct gọi async; bảng support ghi từ Upload/Backup/Common Photos cùng lúc | thấp | ghi qua `AppDatabase` writer; agent `swift-concurrency` ở Deploy |
| Tag/ADS không kiểm được cục bộ | cao | T1; không được thì `tags not kept` (spec cho) |

## 7. Phản biện (T1, 2026-11-05: `challenger` + review giao thức SMB/WebDAV)

| Phản đối | Trả lời / thay đổi |
|---|---|
| Làm Quick Check + cache (T7, T8) trước, giữ thông tin sau | **Giữ thứ tự đã duyệt.** Mức độ cao nhất (intent keep-file-dates) là mất ngày; T7/T8 độc lập nên đổi thứ tự không giảm rủi ro |
| Tách T6 (Upload/Backup) thành intent riêng | **Không** — người dùng chốt gộp (intent keep-file-dates Q3). T6 vẫn là một commit riêng, lùi được một mình |
| Đặt ngày khi upload làm On Server thấy `changed` | **Nhận** — AC-220, T6 |
| Move lùi về chép + không giữ ngày làm mất ngày gốc | **Hỏi người dùng → "Vẫn Move"** (2026-11-05). Thêm: lưu thông tin bản bị xoá trước lệnh xoá — AC-224, T3 |
| Kiểm ±2 s bằng liệt kê folder mỗi ảnh quá tốn | **Nhận một phần** — kiểm bằng một lệnh hỏi đúng file (SMB `queryInfo`, WebDAV `PROPFIND` Depth 0), không liệt kê folder; ngân sách AC-223; so theo giây chẵn (FAT) |
| Mặc định no-op trên protocol lặp lỗi `copyOnServer` | **Nhận** — không có mặc định; compiler bắt mọi conformer |
| ADS khó chứng minh, nhiều rủi ro | **Nhận** — tách T10b sau ngày/cờ; nhớ "không có luồng" theo connection; ≤ 64 KB; NAS ở T11 |
| Bảng mới: `common_photo_set_settings`, `common_photo_created_folders` thừa; `server_file_info_support` cũ dần | **Nhận** — Organize + Quick thành cột trên hàng bộ (`common_photo_watches`, khớp §8 "cột trong Bộ gom"); folder đã tạo = cột JSON trên hàng run; bảng support cập nhật mỗi lượt chạy; **một migration** ở T2 |
| Move tin danh sách đã lưu → SHA cũ | **Nhận** — Move luôn liệt kê đủ, AC-221 |
| Liệt kê cả cây Shared mỗi Scan | **Nhận** — chỉ folder đích của kế hoạch; ảnh đã gom theo log |
| Same as Source: RAW+JPEG khác ngày, tên folder cấm | **Nhận** — mỗi ảnh theo bản của nó, tên sửa như Backup, AC-226 |
| EXIF đọc riêng 25 phút trong khi mẫu đầu đã đọc | **Nhận** — EXIF lấy từ mẫu đầu, §6e |
| Quick bỏ cả mẫu khi cùng mtime | **Không** — ngoài điều người dùng chọn |
| Chưa có ngân sách ghi, concurrency để muộn | **Nhận** — AC-223; `swift-concurrency` sau T2; test dừng giữa chừng để lại part, không để file tên thật thiếu thông tin |
| Restore File Info… không có tiến độ/dừng | **Nhận** — AC-225 |
| Giao thức: READONLY trước đổi tên làm Undo/dọn part hỏng; `FileAttributes` = 0 không xoá cờ; ghi luồng đổi ngày; tên luồng chứa `:`; luồng ≤ 64 KB; bộ đệm 1124 B; 200 của `PROPPATCH` không có nghĩa là giữ | **Nhận hết** — §6e "Thứ tự trên SMB", "Giá trị gửi", "Luồng phụ", "WebDAV"; AC-222 |

## 8. Cách chứng minh là xong

- Test: các test ở mục 5 (chạy theo lớp, không cả bộ, không `Tools/gate`); e2e `CommonPhotosSMBTests` (impacket 4450)
  và `CommonPhotosWebDAVTests` (wsgidav 8096).
- Màn hình (Mac, `-ShotDexDemoLibrary`, sáng + tối, so board bằng `design-parity`): sheet Copy (Quick tắt/bật), sheet
  Move, trang Organize mở từ Common Photos, dòng Organize bộ cũ (No Folders + câu "already gathered"), câu "does not keep
  file dates", cửa sổ log có cột Check + File info + Restore File Info…; Backup Organize Mac + iPhone vẫn không có
  Same as Source.
- Tài liệu: 08b cột "Chứng minh bằng", §6e (kết quả T1, số đo T11), FS-15.02/FS-22 nếu cách báo khác, ba intent dòng
  Tiến độ.
- Agent ở Deploy: `data-migration`, `swift-concurrency`, `design-parity`, `ux-reviewer`.
