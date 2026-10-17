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
| AC-1 | ❌ | không màn, không lịch sử; khuôn "đã có" duy nhất là `ServerDownloadStore.knownFiles` (`Data/Database/ServerDownloadStore.swift:26-46`) theo đường dẫn server | bảng `card_imports` + `CardImportStore.match(name, bytes, date)`; `IngestCatalog` đếm New/Imported; `IngestScreen` header + segmented + lưới |
| AC-2 | ❌ | — | `IngestSelection` (tick/bỏ tick, tổng byte theo mọi file của ô); nút `Import N Photos` |
| AC-3 | ❌ | — | `IngestCatalog.days` thu gọn ngày đủ Imported thành một dòng |
| AC-4 | ❌ | tên + Date Folders có ở E1/E2 nhưng chỉ cho asset Photos; không token `Original Number`/`Text`; E3 không đọc lại SHA | `IngestPlan` (bọc E1, Keep Both cứng) + `IngestRunner` + bước verify trong writer (khuôn E4) |
| AC-5 | ❌ | không có bộ ghi `.xmp` sidecar (chỉ `LookXMPWriter` cho preset, `Domain/Editing/LookExchange/LookXMPWriter.swift`) | dùng bộ ghi sidecar của FS-19 (Creator, Copyright, Keywords, ngày chụp) |
| AC-6 | ⚠️ nửa danh mục (2026-10-18) | `Domain/Ingest/CardCatalog.swift` qua `PairingRule.units` (thêm đuôi `hif`) | task 2 xong; tên đích ở task 4 |
| AC-7 | ❌ | luật đúng đã có và đã test cho Export: E1 `:180-185`, `FileExportPlanTests.keepBothNumbersAgainstFolderAndBatch` | `IngestPlan` gọi E1 với `.keepBoth`, không bao giờ Replace/Skip; test mới với `…_0001.cr3` có sẵn |
| AC-8 | ❌ | E10 có trạng thái *Not connected* cho folder Export | `IngestReadiness` (Domain) trả lý do mờ nút; hàng Backup + footer |
| AC-9 | ❌ | — | lỗi ổ backup là lỗi **phụ**: bản chính chạy tiếp, ghi `backupPath` trống; **Back Up Remaining** |
| AC-10 | ❌ | E3/E6 phân loại rút ổ **đích**; không có gì cho **nguồn** bị rút | `CardReadFailure.disconnected` dừng mẻ ≤ 2 s (watchdog như E3 `:149-163`), xoá part; Import Remaining |
| AC-11 | ❌ | E12 có phép kiểm, câu chữ là của Export | `IngestReadiness` dùng E12; câu *Needs 24.6 GB, 12.0 GB free on T7.* |
| AC-12 | ❌ | E6 `.full` dừng mẻ cho Export | dùng lại E6 trong `IngestRunner`; câu của FS-20 §8 |
| AC-13 | ❌ | E4 lệch SHA = file lỗi, không chép lại | runner: lệch → chép lại 1 lần từ thẻ → còn lệch = lỗi một file, part xoá, **Retry Failed**, cờ "không nhả" |
| AC-14 | ❌ | E7 dừng ở ranh giới asset; E3 xoá part khi `produce` ném | dừng **giữa khối 1 MB** (`Task.checkCancellation` mỗi khối), câu *Stop importing?…* |
| AC-15 | ❌ | — | mỗi file kiểm xong ghi một dòng lịch sử **ngay** (không cuối mẻ) → mở lại thấy 200 Imported |
| AC-16 | ❌ | — | trạng thái rỗng New + **Show All** |
| AC-17 | ❌ | không có sidebar/Activity (FS-18/FS-21 chưa làm) | runner không chặn UI; đăng ký file vào nguồn FS-19 sau mỗi file; chân sidebar `Importing from … N%` |
| AC-18 | ❓ | — | **vì sao ❓:** iOS không có API công khai nhả một ổ mở qua Files/bookmark; chỉ thiết bị ImageCaptureCore có `requestEject`. Đặc tả chưa nói iOS làm gì khi thẻ chỉ tới qua bookmark → câu Q3 |
| AC-19 | ❌ | không có nhóm Sources ở đâu (iPhone: Collections chưa có mục Sources; iPad sidebar = FS-21; Mac = FS-18) | `CardBrowser` (ICC + bookmark) → hàng thẻ trong nhóm Sources do FS-19/21/18 dựng |
| AC-20 | ❌ | khuôn bookmark nhớ lại có ở E10 | `CardBookmarkStore` (nhận lại thẻ theo volume UUID), **Choose Card…** |
| AC-21 | ❌ | — | trạng thái lấy thêm "bản sao đích còn không" từ bảng Bản sao FS-19 |
| AC-22 | ❌ | — | `CardHashPass` nền (SHA-256 cả file + hash nội dung FS-19) tinh chỉnh trạng thái |
| AC-23 | ❌ | E8 đẩy WAV/MP4/THM vào `others` | `CardCatalog`: WAV theo ô ảnh cùng tên gốc, MP4/MOV ô riêng, bỏ THM/MISC/ẩn/file danh mục |
| AC-24 | ❌ | công tắc XMP chưa có (FS-19.02 §5) | lượt nhập luôn ghi `.xmp`; không đổi công tắc |
| AC-25 | ✅ nửa Export (2026-10-18) | `FileNameChip.all` + `FileNameTokenGrid` (`Features/FileExport/FileNameTokenGrid.swift`), token `originalNumber`, `seq`→`sequence`, mẫu "Date + Camera + Sequence" | task 1 xong; nửa Import ở task 13 |
| AC-26 | ❌ | E11 | bộ chạy nền chung `ContinuedProcessingRun` (iOS 26) + nhánh trước 26 = Stop + Import Remaining |
| AC-27 | ❌ | — | bố cục iPhone/Duo ngoài theo `PH_Ingest`, `DC_Ingest`; Duo ngoài chừa rail 84 |
