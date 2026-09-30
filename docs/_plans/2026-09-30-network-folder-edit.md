# Kế hoạch — Sửa và xuất ảnh trên server (FS-17.06)

| Trường | Giá trị |
|---|---|
| Đặc tả | `docs/02-functional-spec/FS-17-import-from-server/06-edit-and-export.md` (AC-52…70, AC-72…75) |
| Intent | [2026-09-29-network-folder-edit](../_intents/2026-09-29-network-folder-edit.md) |
| Ngày | 2026-09-30 |
| Trạng thái | đợt 1 gần xong (2026-09-30) — 22/22 task; còn ảnh iPad/Duo; đợt 2 chưa lập plan |
| Quyết định | planboard `.planboard/network-folder-edit/` — 12 quyết định, người dùng "OK hết theo đề xuất" 2026-09-30 |

## 1. Hiểu đúng chưa

Ảnh trong folder On Local Network / On Cloud có các lệnh file giống menu album. Mọi lệnh (trừ Export EXIF) tải bản
gốc về một thư mục tạm, chạy công cụ trên file đó, rồi mở một sheet xuất bốn đích: Original Folder, Photos Library,
Other Folder, Share. Xuất xong thì xoá bản tạm. Đích lỗi thì giữ để Retry. Rời editor mà có sửa thì hỏi Discard.
Bản gốc trên server chỉ bị thay khi người dùng chọn Replace Original và xác nhận, và không bao giờ thay bản gốc RAW.

## 2. Quyết định đã chốt (chi tiết: `.planboard/network-folder-edit/DECISIONS.md`)

| ID | Chốt |
|---|---|
| D1 | **Nguồn ảnh dạng file** song song với PHAsset. Không tạo asset tạm trong Photos |
| D2 | **Hai đợt.** Đợt 1: mọi thứ trừ Collage / Video / Combine. Đợt 2: ba lệnh đó (AC-67, plan riêng) |
| D3 | Tách bước fetch + verify của Import thành hàm Domain dùng chung; tiền tố tạm `ShotDexServerEdit-` |
| D4 | Photos Library = **asset phẳng** (chỉ bản render), ngày và vị trí lấy từ EXIF gốc |
| D5 | **Bộ ghi riêng** cho file cục bộ lên server, dùng lại `RemoteFileClient` + `ServerUploadPath`; không đụng `ServerUploadSession` |
| D6 | **Không** ghi lịch sử upload (spec §6 đã sửa) |
| D7 | Không thử ghi trước. Lỗi quyền báo ở đích + Choose Another Folder (AC-65 đã sửa) |
| D8 | Other Folder dùng màn duyệt ở chế độ chọn folder + `FileServerCatalog` |
| D9 | **Định nghĩa lệnh dùng chung** cho menu album và menu server |
| D10 | Tiến độ tải là sheet cùng khuôn Import |
| D11 | Editor nguồn file: Export… thay Save; batch xuất ảnh đã sửa; Discard edits?; ẩn Revert, Live Photo |
| D12 | Share đưa URL file tạm (luật bỏ GPS giữ nguyên); Copy tối đa 4096 px |

## 3. Đối chiếu AC ↔ code

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-52 | ❌ | menu ảnh chỉ có Import/Rename/Delete — `ServerBrowserScreen.swift:276-305` | menu nhấn giữ mới |
| AC-53 | ❌ | ⋯ chế độ chọn chưa có; tên lệnh album nằm trong `SelectionBarViews.swift:200-340` | D9: định nghĩa chung + test so |
| AC-54 | ❌ | editor chỉ nhận PHAsset — `PhotoEditorScreen.swift:23`, session cần `PHContentEditingInput` — `PhotoEditingService.swift:22-41` | D1 + D3 |
| AC-55 | ⚠️ một phần | kiểm chỗ trống có sẵn — `ServerDownloadModel.swift:128` (ước tính + 1 GB) | dùng lại cho phiên bản tạm |
| AC-56 | ⚠️ một phần | Cancel của Import — `ServerDownloadModel.swift:249` | phiên bản tạm có Cancel riêng, xoá thư mục |
| AC-57 | ❌ | recipe nháp trong `EditorSession.swift:16-57` khoá theo localIdentifier | khoá theo connection+đường dẫn; hỏi Discard |
| AC-58 | ❌ | — | cùng task AC-57 |
| AC-59 | ⚠️ một phần | sweep lúc khởi động — `TemporaryWorkspace.swift:19-36`, gọi ở `ShotDexApp.swift:11` | thêm tiền tố + test |
| AC-60 | ⚠️ một phần | `.part` → SHA → move ở `ServerUploadSession.swift:240-266`; `editedFilename` — `ServerUploadPath.swift:36` | D5 bộ ghi mới |
| AC-61 | ✅ phần tên | `ServerUploadPath.nextFreeName` — `ServerUploadPath.swift:44` | chỉ nối vào bộ ghi + test |
| AC-62 | ❌ | — | Replace Original + hộp xác nhận |
| AC-63 | ❌ | — | luật RAW trong model sheet |
| AC-64 | ⚠️ một phần | tạo asset phẳng có sẵn — `PhotoEditingService.swift:700`; share nhận URL — `PhotoShareSheet.swift:82` | điều phối nhiều đích |
| AC-65 | ❌ | không có cờ chỉ đọc — `ServerBrowserModel.swift:208-215`; lỗi `RemoteFileError.permissionDenied` | D7 |
| AC-66 | ⚠️ một phần | lưu cả loạt — `EditorBatchSaver.swift:43` (PHAsset) | batch trên nguồn file, chỉ ảnh có nháp |
| AC-67 | ❌ đợt 2 | `CollageScreen.swift:23`, `VideoStudioModel.swift:156`, `PhotoStackModel.swift:75` | plan đợt 2 |
| AC-68 | ⚠️ một phần | `RemoteFileClient.readRange` — `RemoteFileClient.swift:36`; `ExifCSVExporter.swift:36`; `MetadataComposer.compose(asset: AssetInfo…)` — `MetadataComposer.swift:84` | đọc đầu file → RawExif → dòng CSV |
| AC-69 | ❌ | — | kết quả từng đích + Retry Failed |
| AC-70 | ❌ | — | ảnh 4 thiết bị × 2 nhánh |
| AC-72 | ⚠️ một phần | `EditClipboard.paste(onto:)` — `EditClipboard.swift:49` | dán lên nháp nguồn file → sheet xuất |
| AC-73 | ⚠️ một phần | `PhotoRenderService.resize` — `ShotDexKit/Render/PhotoRenderService.swift:624`; màn Resize nhận PHAsset — `CompressionController.swift:53` | Resize trên nguồn file |
| AC-74 | ⚠️ một phần | `PhotoShareSheet.stripLocation(from:)` — `PhotoShareSheet.swift:42` | share file tạm, dọn khi đóng |
| AC-75 | ⚠️ một phần | copy ảnh từ PHImageManager — `AssetActionsCoordinator.swift:194-212` | copy từ file, giới hạn 4096 px |

Không có dòng ⚠️ "lệch" nào chờ quyết: bốn chỗ spec lệch code (D4, D6, D7, AC thiếu cho Paste/Resize/Share/Copy)
đã sửa spec trong lượt này.

## 4. Chỗ nào trong code

| File | Đụng gì | Mới / sửa |
|---|---|---|
| `Core/Utils/TemporaryWorkspace.swift` | tiền tố `ShotDexServerEdit-` | sửa |
| `Domain/ServerImport/ServerDownloadSession.swift` | tách fetch + verify một ảnh | sửa |
| `Domain/ServerImport/ServerEditFetch.swift` | phiên tải bản tạm: kiểm chỗ, tiến độ, Cancel | mới |
| `Domain/ServerImport/ServerEditWriter.swift` | ghi file cục bộ lên server: tên, `.part`, SHA, move, replace | mới |
| `Domain/ServerImport/ServerEditExport.swift` | kế hoạch xuất: đích, luật RAW, kết quả từng đích, Retry, lúc nào xoá bản tạm | mới |
| `Data/Sources/PhotoEditingService.swift` | phiên nguồn file (không `PHContentEditingInput`), asset phẳng từ render + EXIF | sửa |
| `Features/Editing/PhotoEditorController.swift`, `EditorSession.swift`, `PhotoEditorScreen.swift` | nguồn file; Export…; Discard; ẩn Revert/Live | sửa |
| `Features/Editing/EditorPreviewPreloader.swift`, `EditorBatchSaver.swift` | chạy trên nguồn file | sửa |
| `Features/Editing/CompressionController.swift` | Resize trên nguồn file | sửa |
| `Features/Shared/PhotoCommand.swift` | tên, glyph, thứ tự lệnh dùng chung (D9) | mới |
| `Features/Library/SelectionBarViews.swift` | đọc tên từ định nghĩa chung | sửa |
| `Features/ServerImport/ServerBrowserScreen.swift` | menu nhấn giữ, ⋯ chế độ chọn, viewer | sửa |
| `Features/ServerImport/ServerEditFetchSheet.swift`, `ServerExportSheet.swift`, `ServerExportModel.swift` | sheet tiến độ, sheet xuất | mới |

Logic nằm ở Domain (fetch, writer, kế hoạch xuất: thuần, test bằng client giả như `ServerUploadSession`). Features chỉ
nối. Không đụng ShotDexKit (render đã nhận URL). Không có migration, không có bảng mới.

## 5. Thứ tự task (đợt 1)

Mỗi task là một commit `feat(FS-17.06): AC-xx …`, build sau mỗi commit, đụng UI thì `/screens`.

| # | Task | AC | Test kèm theo |
|---|---|---|---|
| 1 | Tiền tố tạm + sweep | AC-59 | `TemporaryWorkspaceTests` thêm ca tiền tố |
| 2 | Tách fetch + verify; phiên bản tạm kiểm chỗ trống | AC-55 | `ServerEditSessionTests.spaceCheckBeforeDownload` + test Import cũ vẫn xanh |
| 3 | Cancel phiên bản tạm | AC-56 | `ServerEditSessionTests.cancelRemovesTemp` |
| 4 | Phiên sửa ảnh nguồn file (D1); Edit mở editor | AC-54 | `ServerEditSessionTests.downloadsOriginalOnly` + test editor cũ vẫn xanh |
| 5 | Discard edits? khi có sửa | AC-57 | `ServerEditSessionTests.discardDropsDraft` + ảnh |
| 6 | Rời không sửa: không hỏi | AC-58 | `ServerEditSessionTests.cleanLeaveNoPrompt` |
| 7 | Bộ ghi: file mới cạnh bản gốc | AC-60 | `ServerEditExportTests.newFileBesideOriginal` |
| 8 | Trùng tên → (2) | AC-61 | `ServerEditExportTests.nameCollisionNumbers` |
| 9 | Replace Original + xác nhận | AC-62 | `ServerEditExportTests.replaceNeedsConfirm` + ảnh |
| 10 | RAW không thay được | AC-63 | `ServerEditExportTests.rawCannotBeReplaced` + ảnh |
| 11 | Sheet xuất nhiều đích: Photos phẳng, Other Folder, Share sau cùng | AC-64 | `ServerEditExportTests.multipleDestinations` + ảnh |
| 12 | Đích lỗi giữ nháp, Retry Failed | AC-69 | `ServerEditExportTests.failedDestinationKeepsDraft` |
| 13 | Lỗi quyền + Choose Another Folder | AC-65 | `ServerEditExportTests.permissionDeniedOffersAnotherFolder` + ảnh |
| 14 | Batch: chỉ xuất ảnh đã sửa | AC-66 | `ServerEditExportTests.batchExportsEditedOnly` |
| 15 | Định nghĩa lệnh chung; ⋯ chế độ chọn | AC-53 | `ServerEditMenuTests.matchesAlbumMenu` (lặp qua danh sách) |
| 16 | Menu nhấn giữ + viewer | AC-52 | `scripts/server-edit.json` + ảnh |
| 17 | Paste Edits → sheet xuất | AC-72 | `ServerEditSessionTests.pasteEditsGoesToExportSheet` |
| 18 | Resize trên nguồn file | AC-73 | `ServerEditExportTests.resizeExportsThroughSheet` |
| 19 | Share file tạm | AC-74 | `ServerEditSessionTests.shareHandsOriginalAndCleansUp` |
| 20 | Copy | AC-75 | `ServerEditSessionTests.copyBoundsAndCleansUp` |
| 21 | Export EXIF chỉ đọc đầu file | AC-68 | `ServerEditExifTests.readsHeadOnly` |
| 22 | Ảnh 4 thiết bị × iOS 26.5 / 18.6 | AC-70 | `/screens server-edit` |

Thứ tự theo phụ thuộc: bản tạm (1–3) → editor (4–6) → xuất (7–14) → menu (15–16) → các lệnh còn lại (17–21) → ảnh (22).
Không có dòng ✅ trọn để viết test trước; AC-61 (phần tên) làm trong task 8.

## 6. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| Tách `PhotoEditingSession` khỏi PHAsset làm hỏng editor ảnh library | trung bình | nguồn PHAsset giữ nguyên đường cũ; chạy toàn bộ test editor sau task 4; `/screens editor` một lần |
| Chỗ đọc `asset.*` rải rác trong controller (pixelWidth :336/:351, canPerform :1153, revert :1163) | cao | liệt kê hết ở task 4, mỗi chỗ có nhánh nguồn file; compiler bắt khi asset thành optional |
| Mattes cache khoá theo `persistentIdentity` = localIdentifier (`PhotoEditingService.swift:227`) | trung bình | nguồn file khoá theo connection + đường dẫn + số byte + ngày sửa |
| Đĩa: loạt 20 RAW = 1.2 GB bản tạm cộng preview loạt | trung bình | kiểm trước (task 2); preview loạt vẫn nằm trên đĩa (NF-02) |
| Concurrency: một lệnh mỗi connection trong lúc lưới tải thumbnail | trung bình | mọi lệnh đi qua `ServerBrowseSession.perform`; `swift-concurrency` review |
| File cloud online-only (iCloud Drive, Dropbox) | thấp | file coordination của client Files; Cancel dừng lượt tải |
| Hai session sửa cùng checkout (shotdex-ios-2 đang /verify FS-17) | cao | stage đúng đường dẫn, `git commit -- <paths>`; AC-71 là của session kia |

## 7. Phản biện (`challenger`, 2026-09-30)

| Phản đối | Trả lời / thay đổi |
|---|---|
| Chỗ nối chưa được đặt tên; 5 kiểu bám PHAsset (session, controller, EditorSession, CompressionController, EditorBatchSaver) sẽ mỗi kiểu tự nghĩ một cách | **một kiểu chung** cho nguồn ảnh (asset hoặc file server) thay PHAsset ở cả 5 chỗ, viết trước task 4 |
| Batch saver đổi ở task 14, cách mốc chạy lại test editor 10 task | chạy lại toàn bộ test editor ngay sau task 14 |
| Revert: model trả false nhưng nút vẫn có thể hiện | một test khẳng định cả hai với nguồn file |
| Preview cache khoá theo PHAsset là chỗ thứ 6 | nguồn file khoá theo đường dẫn + byte + ngày sửa; cache vẫn bị xoá khi đóng editor |
| Mattes cache khoá theo localIdentifier | giữ như plan (connection + đường dẫn + byte + ngày sửa) |

## 8. Cách chứng minh là xong

- Test: `/test ServerEditSessionTests`, `ServerEditExportTests`, `ServerEditMenuTests`, `ServerEditExifTests`,
  `TemporaryWorkspaceTests`; toàn bộ test editor + ServerImport + ServerUpload sau task 4, 11 và 14; full suite một
  lần lúc xong đợt 1.
- Server thử: impacket SMB 4450 + asyncssh SFTP 2222 + wsgidav (memory FS-15); một share chỉ đọc cho AC-65.
- Màn hình: menu nhấn giữ, ⋯ chế độ chọn, viewer, sheet tiến độ, editor Export…, Discard, sheet xuất (thường / RAW /
  lỗi / Retry), hộp Replace — iPhone 26.5 + 18.6, iPad, Duo trong/ngoài (`Tools/sim-shot`).
- Agent ở Deploy: `swift-concurrency`, `memory-leak`, `photokit-guard` (asset phẳng), `component-consistency`,
  `copy-consistency`, `ios26-parity`, `device-layout`.
- Tài liệu: cột "Chứng minh bằng" của FS-17.06 sau mỗi AC; FS-03.06 thêm một dòng về nguồn file; NF-02 §2 thêm tiền
  tố; dòng Tiến độ của intent sau mỗi commit.

## 9. Kết quả đợt 1 (2026-09-30)

- Commit: `5084085` … `d05ed3e` (AC-59 → AC-75 và 4 sửa lỗi thấy trên ảnh chụp).
- Chạy thật trên SMB (impacket, 127.0.0.1:4451) ở iPhone 17 Pro 26.5 và iPhone 16 Pro 18.6: Edit → Export tới
  Original Folder (`_edited`, rồi `_edited (2)`), Replace có xác nhận, Discard xoá bản tạm, Resize mở sheet có Size.
- Lỗi thấy khi chụp và đã sửa: tiêu đề chọn bị cắt, Import xuống dòng ở viewer, markup inflect lộ ra trong hộp
  Replace, lưới không thoát chế độ chọn sau khi xuất, và thumbnail JPEG không có thumbnail nhúng chỉ vẽ nửa trên (FS-17.01).
- Chưa làm: ảnh iPad/Duo (công cụ MCP bấm sai ở iPad ngang và Duo; `ui-drive` cài lại app nên mất connection seed),
  ảnh AC-63 (không có RAW mẫu không mặt người), ảnh AC-65, đợt 2 (Collage/Video/Combine, AC-67).
