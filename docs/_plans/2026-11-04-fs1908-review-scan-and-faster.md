# Kế hoạch — FS-19.08 §6d Xem kết quả Scan rồi mới quyết · chạy nhanh hơn

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-19.08 §6d`](../02-functional-spec/FS-19-photo-sources/08-common-photos.md) · AC: [`08b`](../02-functional-spec/FS-19-photo-sources/08b-common-photos-ac.md) (AC-174…191) |
| Intent | [2026-11-04-common-photos-compare-before-run](../_intents/2026-11-04-common-photos-compare-before-run.md) |
| Commit spec | `eb90a39c` (intent `2bc06c36`) |
| Ngày | 2026-11-04 |
| Trạng thái | đang làm — R1–R3 xong (loop: [FS1908_REVIEW_LOOP.md](FS1908_REVIEW_LOOP.md)) |

## 1. Hiểu đúng chưa

Sau Scan, sheet Find Common Photos phải là một **kế hoạch** đọc được trước khi bấm. Bốn thay đổi:

- **Danh sách.** Chỉ hàng Same. Mỗi hàng ghi nó sẽ thành gì ở Shared (tên cuối, Already in Shared, Move xoá mấy bản)
  và có ô chọn.
- **Chạy.** Bấm Copy/Move là chạy đúng các hàng đang chọn, không băm lại bản nguồn.
- **Compare.** Cửa sổ Compare mở được từ một hàng: hai bản cạnh nhau, video chạy đồng bộ, tải cả file khi chưa index
  (cache tạm 2 GB).
- **Left Out.** Hàng bỏ ra được nhớ theo SHA cho bộ gom, ở bảng riêng. Danh sách Move chờ của tự gom có cùng cách bỏ.

Thêm phần tăng tốc Copy, chỉ cho WebDAV: NAS tự chép bằng `COPY`, vẫn đọc lại SHA ở đích, nên byte qua Mac còn ≈ 1× thay
cho 3×. SMB giữ tải + đẩy: người dùng không cho vá `SMBClient` (2026-11-04). Băm khi Scan vẫn một lệnh một lúc.

## 2. Đối chiếu AC ↔ code

Đã đọc (qua subagent `code-search`, kèm dòng): `CommonPhotosScanModel.swift`, `CommonPhotosMatcher.swift`,
`CommonPhotosRunner.swift`, `CommonPhotosServerChecks.swift`, `CommonPhotosVerifier.swift`, `CommonPhotosStore.swift`,
`CommonPhotosWatchStore.swift`, `CommonPhotosIncremental.swift`, `AppDatabase+CommonPhotos.swift`,
`FileServerStore.swift`, `MetadataStore.swift`, `ConnectionLock.swift`, `ServerOriginalLoader.swift`,
`RemoteThumbnailCache.swift`, `SMBFileClient.swift`, `WebDAVFileClient.swift`, `RemoteFileClient.swift`,
`MacCommonPhotosSheet.swift`, `MacCommonPhotosRunWindow.swift`, `MacCommonPhotosRuns.swift`, `PhotoCompareScreen.swift`,
`ShotDexTests/ServerUploadFakes.swift`, checkout `SMBClient` (rev `66eafaa6`).

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-174 chỉ Same | ❌ | `CommonPhotosScanModel.swift:205-220`: `rows` gộp Same với Likely/Checking từ `preview.likely`; sheet in nhãn Likely `MacCommonPhotosSheet.swift:732` | `rows` chỉ trả Same; giữ `checkingCount` cho đầu danh sách; bỏ case `.likely` khỏi hàng |
| AC-175 kế hoạch Copy | ❌ | tên ` (2)` và Skipped quyết **lúc chạy**: `CommonPhotosRunner.swift:341-355` (`nextFreeName` :354), `:473-485`; Scan chỉ liệt kê đích khi bộ đã gom (`CommonPhotosScanModel.swift:513-552`) | Scan luôn liệt kê đích; tách luật đặt tên thành một hàm Domain dùng chung cho kế hoạch và runner |
| AC-176 kế hoạch Move | ❌ | dữ liệu có (nguồn của từng ảnh trong `items` :91-117), màn chưa ghi | dòng phụ + `.help` liệt kê bản sẽ xoá |
| AC-177 Copy không băm lại nguồn | ✅ | runner chỉ `download` bản nguồn (`:374`, SHA tính khi tải, `SMBFileClient.swift:239-251`); `sha256` chỉ lên đích (:331, :346, :384) | chỉ viết test khoá: client giả đếm `sha256Paths` theo nguồn |
| AC-178 Move không băm lại nguồn | ✅ | `isUnchanged` (`:469`, `:605`) qua `CommonPhotosServerChecks.swift:12-20`: liệt kê folder, `sha256` chỉ khi không có ngày sửa | test khoá |
| AC-179 file đổi sau Scan (Move) | ✅ | `isUnchanged` lệch → Failed `changedOnServer`, không xoá | test khoá + e2e SMB ảo |
| AC-180 Shared đổi giữa Scan và chạy | ✅ | runner liệt kê đích lúc bắt đầu (`:232-233`) rồi `nextFreeName`; không ghi đè | test khoá; log/CSV đã ghi tên cuối |
| AC-181 Compare (đã index) | ❌ | Mac chưa có màn so sánh; `PhotoCompareScreen.swift:43` nhận `PHAsset`, không dùng cho file server | cửa sổ mới `MacCommonPhotosCompareWindow` + model Domain |
| AC-182 tải cả file để xem | ❌ | `ServerOriginalLoader.swift:23-58` tải về thư mục tạm, kiểm chỗ trống, `discard` xoá | dùng lại loader; thêm cache LRU 2 GB theo mẫu `RemoteThumbnailCache` (:7-60) |
| AC-183 mất kết nối khi tải | ❌ | — | lỗi FS-15.01 §3 + Try Again trong khung |
| AC-184 không chặn Scan | ❌ | `ConnectionLock.swift:8-75`: chỉ có `normal` và `backup`, cùng mức thì ai chờ lâu đi trước | thêm mức ưu tiên thấp nhất cho Compare |
| AC-185 video đồng bộ | ❌ | `AVPlayer` có ở `VideoPlaybackModel.swift:308`, chưa có chỗ nào chạy hai player cùng lúc | model đồng bộ hai `AVPlayer` (một đồng hồ, seek cả hai) |
| AC-186 bỏ chọn | ❌ | `makeRun()` (`CommonPhotosScanModel.swift:612-618`) lấy mọi `photos`; `runTitle` đếm cả (`MacCommonPhotosSheet.swift:642-653`) | `selected` trong model; `makeRun` nhận tập con |
| AC-187 Left Out được nhớ | ❌ | không có bảng | migration v57 `common_photo_left_out` (setKey, sha256, createdAt); matcher bỏ SHA trong bảng |
| AC-188 Include | ❌ | — | xoá hàng khỏi bảng |
| AC-189 Clear Index / xoá bộ | ❌ (một nửa ✅) | `MetadataStore.deleteAll` (`:417-430`) không đụng `common_photo_*`, nên bảng mới tự sống sót; `WatchStore.remove` (`:81-85`) và `FileServerStore.delete` (`:92-110`) chưa biết bảng mới | xoá theo bộ khi Remove from List và khi xoá connection |
| AC-190 bỏ chọn trong danh sách Move chờ | ❌ | `dropReady` xoá cả lượt (`CommonPhotosStore.swift:382-405`); cửa sổ log không có hàng chọn được (`MacCommonPhotosRunWindow.swift:432-437, 725-737`) | bỏ một item `pending` khỏi lượt ready + ghi Left Out, `updatedAt` tăng (giữ luật so `updatedAt` của `confirmReady`) |
| AC-191 Copy ngay trên server | ❌ | `RemoteFileClient` không có `copy`; WebDAV chỉ `MOVE` (`WebDAVFileClient.swift:174`); `SMBClient` có `CtlCode.srvCopyChunk` nhưng `Session.send` là private (`Session.swift:693-769`), không vá | `copy(_:to:)` tuỳ chọn trên protocol, mặc định "không làm được"; WebDAV `COPY`; runner thử copy trước, bị từ chối thì tải + đẩy |

Không dòng nào ⚠️ (tài liệu nói một đằng, code làm một nẻo). Các AC ✅ đã đúng như spec: chỉ thiếu test khoá.

## 3. Tái dùng — không làm hai lần

| Đã có | Dùng cho |
|---|---|
| luật đặt tên ` (2)` và Already there trong `CommonPhotosRunner` | kéo thành một hàm `CommonPhotosDestinationPlan` (Domain), kế hoạch và runner gọi chung |
| `CommonPhotosIncremental.setKey` | khoá của bảng Left Out |
| `ServerOriginalLoader` | tải bản để Compare |
| mẫu LRU của `RemoteThumbnailCache` | cache Compare 2 GB |
| `ConnectionLock` | thêm một mức ưu tiên, không mở cách khoá mới |
| `InMemoryRemoteFileClient` (`sha256Paths`, `bytesRead`, `commands`) | test AC-177…180, 186, 191; thêm đếm byte ghi và lệnh copy |
| hàng `MacCommonPhotosRow` | thêm ô chọn và dòng kế hoạch; danh sách ready dùng lại cùng hàng |
| board `MAC_Duplicates` | cách đặt hai khung A/B trên Mac cho board Compare |

## 4. File đổi

| File | Đụng gì | Tầng | Mới / sửa |
|---|---|---|---|
| `docs/design/mac/project/MAC_CommonPhotos.dc.html` | hàng kế hoạch, ô chọn, Left Out, bỏ Likely | design | sửa |
| `docs/design/mac/project/MAC_CommonPhotosCompare.dc.html` + `canvas.json` | ảnh, video, đang tải, lỗi; sáng/tối | design | mới |
| `docs/design/mac/project/MAC_CommonPhotosRun.dc.html` | danh sách ready có ô chọn | design | sửa |
| `ShotDex/Domain/CommonPhotos/CommonPhotosDestinationPlan.swift` | luật tên đích + Already there | Domain | mới |
| `ShotDex/Domain/CommonPhotos/CommonPhotosCompare.swift` | model so sánh: hàng, bản trái/phải, đồng hồ video | Domain | mới |
| `ShotDex/Data/Sources/FileServer/CommonPhotos/CommonPhotosScanModel.swift` | chỉ Same, kế hoạch, `selected`, Left Out | Data | sửa |
| `ShotDex/Domain/CommonPhotos/CommonPhotosRunner.swift` | dùng plan chung; `copy` trên server trước | Domain | sửa |
| `ShotDex/Data/Database/AppDatabase+CommonPhotos.swift` | v57 `common_photo_left_out` | Data | sửa |
| `ShotDex/Data/Database/CommonPhotosLeftOutStore.swift` | đọc/ghi Left Out | Data | mới |
| `CommonPhotosStore.swift` · `CommonPhotosWatchStore.swift` · `FileServerStore.swift` | bỏ một item ready; xoá Left Out theo bộ / connection | Data | sửa |
| `ShotDex/Data/Sources/FileServer/ConnectionLock.swift` | mức ưu tiên thấp | Data | sửa |
| `ShotDex/Data/Sources/FileServer/CompareFileCache.swift` | cache 2 GB | Data | mới |
| `ShotDex/Domain/ServerUpload/RemoteFileClient.swift` | `copy(_:to:)` mặc định "không làm được" | Domain | sửa |
| `WebDAVFileClient.swift` | `COPY` | Data | sửa |
| `ShotDexMac/Servers/CommonPhotos/MacCommonPhotosSheet.swift` | hàng, ô chọn, Left Out, Space/nhấp đúp | Features | sửa |
| `ShotDexMac/Servers/CommonPhotos/MacCommonPhotosCompareWindow.swift` | cửa sổ Compare | Features | mới |
| `ShotDexMac/Servers/CommonPhotos/MacCommonPhotosRunWindow.swift` · `MacCommonPhotosRuns.swift` | ready có ô chọn, Move N theo số chọn | Features | sửa |
| `ShotDexTests/CommonPhotos*Tests.swift`, `ServerUploadFakes.swift` | test từng AC | test | sửa / mới |

Logic nằm ở Domain/Data: kế hoạch, Left Out, đồng hồ video, cache. View chỉ vẽ.

## 5. Thứ tự task

Theo luật: ✅ (viết test) trước, ❌ sau. Board vẽ trước task UI tương ứng.

| # | Task | AC | Test kèm theo |
|---|---|---|---|
| R1 | Khoá test những gì code đã đạt | AC-177, 178, 179, 180 | `CommonPhotosReviewTests.copyRunReadsNoSource`, `moveRunReadsNoSource`, `changedAfterScanFails`, `destinationChangedAfterScan`; e2e SMB ảo cho AC-179 |
| R2 | Vẽ board: `MAC_CommonPhotos` (hàng kế hoạch, ô chọn, Left Out, bỏ Likely), `MAC_CommonPhotosRun` (ready có ô chọn), `MAC_CommonPhotosCompare` mới; publish canvas | (174–176, 181–186, 190) | render sáng + tối |
| R3 | Chỉ Same | AC-174 | `CommonPhotosScanModelTests.onlySameRows` |
| R4 | Kế hoạch ở Scan: liệt kê đích, `CommonPhotosDestinationPlan`, dòng phụ Copy/Move | AC-175, 176 | `CommonPhotosDestinationPlanTests` (trống, trùng khác byte, cùng SHA, Move N bản); ảnh Mac sáng/tối so board |
| R5 | Bỏ chọn, chạy tập con | AC-186 | `CommonPhotosScanModelTests.runsOnlySelected` (client giả: 0 lệnh cho hàng bỏ) |
| R6 | Left Out: v57, store, matcher bỏ SHA, mục Left Out + Include, xoá theo bộ/connection | AC-187, 188, 189 | `CommonPhotosLeftOutTests` (quét lại, Run Again, tự gom, Include, Clear Index, Remove from List, xoá connection) |
| R7 | Danh sách Move chờ: ô chọn, bỏ item ready + Left Out, Move N | AC-190 | `CommonPhotosGatherTests.readyLeavesOneOut`; ảnh cửa sổ log |
| R8 | Compare với bản đã index: cửa sổ, hai khung, ←/→, Esc, zoom theo nhau | AC-181 | `CommonPhotosCompareTests.rowsAndSides`; ảnh Mac sáng/tối so board |
| R9 | Compare tải cả file: loader, cache 2 GB, huỷ khi sang hàng, lỗi + Try Again, ưu tiên thấp | AC-182, 183, 184 | `CompareFileCacheTests`, `ConnectionLockTests.lowestWaitsForEveryone`, `CommonPhotosCompareTests.cancelsAndCleansUp`; e2e SMB ảo |
| R10 | Video đồng bộ | AC-185 | `CommonPhotosCompareTests.videoClockKeepsBothTogether` (đồng hồ thuần); chạy tay một clip trên Mac |
| R11 | Copy ngay trên server (WebDAV): `copy` trên protocol, WebDAV `COPY`, runner thử copy trước rồi lùi | AC-191 | `CommonPhotosRunnerTests.serverCopyThenReadBack`, `refusedCopyFallsBack`; e2e WebDAV cục bộ đếm byte; SMB ảo chứng minh đường lùi |
| R12 | `/verify` | tất cả | bảng AC; `design-parity` |

Một task một commit. Sau mỗi task: build iOS + ShotDexMac, test liên quan (không chạy cả bộ), dòng Tiến độ intent.

## 6. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| 1. Migration v57 trên DB đang có dữ liệu | thấp | bảng mới, không đổi bảng cũ; app chưa phát hành (không cần đường lùi) |
| 2. Kế hoạch ở Scan lệch với lúc chạy (Shared đổi giữa chừng) | vừa | runner vẫn đặt tên lúc chạy (AC-180); kế hoạch là dự kiến, log/CSV ghi tên thật |
| 3. Tải RAW/video lớn để Compare chiếm đĩa | vừa | chỉ hai bản của hàng đang xem; huỷ khi sang hàng; trần 2 GB; kiểm chỗ trống trước (loader đã làm) |
| 4. Hai `AVPlayer` trôi lệch nhau | vừa | một đồng hồ chủ, bên phải seek theo khi lệch > 1 khung; test thuần trên đồng hồ |
| 5. Một lệnh mỗi connection: Compare chen giữa các lệnh băm | thấp | mức ưu tiên thấp nhất; Scan giải phóng khoá giữa các lệnh nên Compare chỉ chạy khi Scan không có lệnh chờ |
| 6. Bỏ item khỏi lượt ready trong khi helper đang thay danh sách | vừa | ghi qua `updatedAt` như `confirmReady`; lệch thì cửa sổ đọc lại |

## 7. Agent chạy ở giai đoạn Deploy

`data-migration` (v57, Left Out, xoá theo bộ) · `swift-concurrency` (Compare tải và huỷ, khoá ưu tiên, hai player) ·
`memory-leak` (cache 2 GB, player) · `design-parity` (3 board) · `a11y-voiceover` (ô chọn, hai khung Compare) ·
`ux-reviewer` (Left Out, Move N theo số chọn).

## 8. Cách chứng minh là xong

- Test: các tên ở bảng mục 5. Chạy theo lớp, không chạy cả bộ; `Tools/gate` chỉ khi người dùng bảo.
- e2e SMB ảo `127.0.0.1:4450` (ảnh phong cảnh, không mặt người): AC-179, 182–184, 191; WebDAV cục bộ cho AC-191.
- Ảnh Mac sáng + tối, so board:
  - sheet sau Scan có hàng kế hoạch và Left Out;
  - Compare ở 4 trạng thái: ảnh, video, đang tải, lỗi;
  - cửa sổ log ready có ô chọn.
- Tài liệu: cột "Chứng minh bằng" của 08b; 08 nếu lệch; dòng Tiến độ intent.
