# FS-20 — Bảng đối chiếu AC ↔ code

Thuộc [kế hoạch FS-20](2026-10-04-fs20-card-ingest.md). Đặc tả: [FS-20 README](../02-functional-spec/FS-20-card-ingest/README.md)
· [AC](../02-functional-spec/FS-20-card-ingest/01-acceptance-criteria.md). Đọc code ngày 2026-10-04.

**Tóm tắt:** ✅ 0 · ⚠️ 1 · ❌ 25 · ❓ 1. Không có dòng code nào nhập thẻ: không `ImageCaptureCore`, không
`Features/Ingest/`, không bảng lịch sử nhập (grep `ICDeviceBrowser|ICCameraDevice|Ingest|card_imports` = 0). FS-10
(Import cũ) đã gỡ sạch 2026-09-24 ([plan](2026-09-24-fs-10-remove-import.md)) — không còn gì để hồi sinh; thứ tái
dùng được là khuôn của Export to Files (07b) và FS-15/17.

## Bằng chứng chung (dẫn lại ở từng dòng)

| Mã | Ở đâu | Nói gì |
|---|---|---|
| E1 | `Domain/FileExport/FileExportPlan.swift:137-203` | tính tên cả mẻ trước byte đầu; Keep Both so không phân biệt hoa thường với folder **và** trong mẻ (`:180-185`); Date Folders qua `ServerUploadPath.dayFolder` (`:115-117`) |
| E2 | `Domain/FileExport/FileNameTemplate.swift:17-18, 80-131` | 6 token `original date time camera lens seq`; bỏ token thiếu + dấu nối; exFAT `-`; ≤ 200 |
| E3 | `Data/Sources/FileExport/ExportDestinationWriter.swift:88-126, 137-143` | `LocalFolderWriter`: ghi `.shotdex-part` → kiểm "có byte, mở được" → rename có watchdog 2 s; **không** đọc lại SHA (07b §6) |
| E4 | `Domain/ServerUpload/ServerUploadSession.swift:240-257` | khuôn FS-15.02 §4: part → đọc lại → so SHA-256 → rename; lệch → xoá part, file lỗi |
| E5 | `Domain/ServerUpload/RemoteFileClient.swift:142-157` | `FileChecksum.sha256` khối 1 MB |
| E6 | `Domain/FileExport/FileExportFailure.swift:7-41, 66-90` | lỗi một ảnh chạy tiếp / lỗi đích dừng mẻ; `classify` ENOSPC/ENXIO/EIO… |
| E7 | `Data/Sources/FileExport/FileExportRunner.swift:132-173` | runner một asset một lúc, `Task.isCancelled` mỗi asset, `sweepLeftoverParts` đầu lượt (`:139`), Export Remaining / Retry Failed theo id |
| E8 | `Domain/ServerImport/ServerFolderListing.swift:90-125` | ghép RAW + **một** JPEG/HEIC cùng tên; video, WAV, THM rơi vào `others` |
| E9 | `Domain/ServerImport/EmbeddedPreview.swift:41, 80` · `Data/Sources/FileServer/RemoteThumbnailer.swift:24-50` | thumbnail từ đầu file (256 KB → 1 MB, RAF theo con trỏ), ngày chụp từ đầu file |
| E10 | `Data/Sources/FileExport/ExportFolderStore.swift:82-106` | bookmark security-scoped, ổ ngoài rút = *Not connected* (không quên) |
| E11 | `Features/FileExport/FileExportSheet.swift:57-61` | ra nền = Cancel; không có `BGContinuedProcessingTask` ở đâu trong `ShotDex/` (FS-15.02b mới là spec) |
| E12 | `Domain/FileExport/FileExportSpaceEstimate.swift:32-35` | kiểm chỗ trống trước byte đầu |

## FS-20

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 | ✅ (2026-10-18) | `CardImportStore`, `IngestStatus`, `IngestScreen` | task 13 |
| AC-2 | ✅ | `IngestSelection` | task 14 |
| AC-3 | ✅ | `IngestStatus.days` | task 15 |
| AC-4 | ✅ (2026-10-18) | `Domain/Ingest/IngestRunner.swift`, `IngestPlan.swift` (`IngestFolderTemplate`), `CardReader.swift`; `LocalFolderWriter.writeVerified` (K2) | task 4 xong |
| AC-5 | ✅ | `IngestRecorder` + `XMPPatch` creator/rights/createDate | task 20 |
| AC-6 | ✅ (2026-10-18) | `CardCatalog` + `IngestRunner` | task 2, 4 |
| AC-7 | ✅ (2026-10-18) | `IngestRunner` + `IngestPlan` (Keep Both cứng) | task 5 |
| AC-8 | ⚠️ logic | `IngestReadiness.backupNotConnected` | task 11 |
| AC-9 | ⚠️ logic | backup rút → `backupIncomplete`; `run(only:copiesPrimary:false)` | task 12 |
| AC-10 | ⚠️ logic | `.cardDisconnected` dừng mẻ; `run(only:)` = Import Remaining | task 8; watchdog đọc thẻ treo (R4) chưa có |
| AC-11 | ⚠️ logic | `IngestReadiness` | task 10 |
| AC-12 | ⚠️ logic | `IngestSummary.Ending.destinationFailed`, `IngestCopy.endingMessage` | task 7 |
| AC-13 | ⚠️ logic (2026-10-18) | `IngestRunner.copyFile` thử lại 1 lần; `LocalFolderWriter.readBack` | task 6; Retry Failed UI task 13 |
| AC-14 | ⚠️ logic | huỷ Task = Stop, kiểm mỗi khối | task 9 |
| AC-15 | ✅ | `IngestRecorder` ghi từng file | task 19 |
| AC-16 | ⚠️ | `IngestScreen` trạng thái rỗng | task 16; ảnh màn rỗng |
| AC-17 | ⚠️ (2026-10-18) | đọc lại nguồn đích mỗi ≤ 10 s (`IngestModel.readSourceIfDue`) | task 25 phần iPhone; iPad/Mac chờ FS-21/18 |
| AC-18 | ⚠️ logic | `IngestSummary.canEject`, `IngestCopy.finishedBanner`, banner ở `IngestModel.finish` | task 22; ICC eject chưa có |
| AC-19 | ⚠️ iPhone | `CardStore`, `SourcesGroup.cardRow` | task 23 phần iPhone |
| AC-20 | ❌ | khuôn bookmark nhớ lại có ở E10 | `CardBookmarkStore` (nhận lại thẻ theo volume UUID), **Choose Card…** |
| AC-21 | ✅ | `CardImportStore.isCopyGone` | task 17 |
| AC-22 | ✅ | `CardHashPass` | task 18 |
| AC-23 | ⚠️ nửa danh mục (2026-10-18) | `CardCatalog.items`: WAV theo ô ảnh, MP4/MOV ô `.video`, `isListed` bỏ ẩn + MISC, chỉ giữ ảnh/RAW/video/WAV | task 3 xong; mẻ thật ở task 4, thời lượng video ở task 13 |
| AC-24 | ✅ | `SidecarWriter.write` tĩnh | task 21 |
| AC-25 | ✅ nửa Export (2026-10-18) | `FileNameChip.all` + `FileNameTokenGrid` (`Features/FileExport/FileNameTokenGrid.swift`), token `originalNumber`, `seq`→`sequence`, mẫu "Date + Camera + Sequence" | task 1 xong; nửa Import ở task 13 |
| AC-26 | ⚠️ logic | `App/IngestBackgroundService.swift`, `IngestBackgroundPolicy` | task 26 |
| AC-27 | ❌ | — | bố cục iPhone/Duo ngoài theo `PH_Ingest`, `DC_Ingest`; Duo ngoài chừa rail 84 |
| AC-28 | ✅ (2026-10-18) | `IngestRunner.pause/resume`, panel tiến độ | task 28 |
