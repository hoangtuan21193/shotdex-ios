# FS-03.07c — Xuất ra folder: chỗ đã chốt, chạy mẻ, đường hỏng, tiêu chí nghiệm thu

`FS-03.07c` · phần tiếp của [07b](07b-export-to-files.md) · test `ShotDexTests/FileExport*Tests.swift` (chưa có)
· script `ShotDexUITests/scripts/file-export-*.json` (chưa có) · cập nhật 2026-10-02

## 1. Chỗ đã chốt

Người dùng chốt cả sáu 2026-10-02. Bốn mục đầu là bố cục, vẽ trên canvas trước khi code (07b cuối file).

| # | Mặt | Luật |
|---|---|---|
| 1 | Lệnh nằm ở đâu | ⋯ của chế độ chọn: **Export…** ngay dưới Resize; ⋯ của Photo Detail: ngay dưới Resize. Glyph `square.and.arrow.up.on.square`, thêm vào từ điển `DESIGN.md` §8. *Vì menu nhấn giữ đã 9 dòng, và `folder` đang là "folder trên server".* |
| 2 | Bố cục sheet | một Form bốn section Destination · Export · File Names · tóm tắt (07b §3). iPhone detent large 402pt; iPad form canh giữa rộng tối đa 700pt như Resize; hàng 44pt, segmented rộng hết hàng. Folder đã nhớ thì không qua trình chọn |
| 3 | Sửa mẫu tên | hàng **Name** ghi mẫu đang dùng, ví dụ ở dòng phụ; chạm đẩy màn **File Name** (07b §5). *Vì sheet ngắn hơn ~120pt, mà Duo trong chỉ có 669pt.* |
| 4 | Upload và preset | sheet Upload **không đổi**, vẫn chỉ bản gốc. Hàng Folder của sheet Export liệt kê thêm connection đã lưu (07b §7). *Vì lời hứa của Upload là "bản gốc đã kiểm, giờ xoá được".* |
| 5 | Tải iCloud | **cuốn chiếu**: tải trước tối đa 20 ảnh hoặc 2 GB; ảnh hỏng nêu tên ở tổng kết + **Retry Failed**. Ngoại lệ của luật tải cả mẻ, ghi ở [FS-02.06](../FS-02-photo-detail/06-icloud-originals.md) §5. *Vì Export không xoá gì.* Không bao giờ xuất bản xem trước |
| 6 | Metadata của Unmodified Original | như Upload ([NF-03](../../04-non-functional-design/NF-03-privacy-and-security.md) §2b): nguyên byte, **không** có hàng Metadata; ghi chú ở [FS-08.06](../FS-08-settings/06-share-metadata-privacy.md) §2. Cần bỏ vị trí thì dùng Current Version, Size Original |

## 2. Chạy mẻ

- Bấm Export → sheet đổi sang tiến độ, không kéo xuống đóng được. Tên của **cả mẻ** được tính trước byte đầu, nên
  `{seq}` và tên Keep Both không đổi khi chạy lại phần còn lại.
- Dòng trên `Exporting 212 of 500`, thanh xác định; dưới `1.4 of 3.2 GB · about 4 min left` (ETA theo tốc độ 30 s gần
  nhất, như FS-15.02 §6); tên file đang làm và bước của nó: *Preparing* (iCloud) · *Converting* · *Writing*.
- Ảnh chỉ trên iCloud đi qua pha chuẩn bị của [FS-02.06](../FS-02-photo-detail/06-icloud-originals.md) §5, tiến độ tải
  hiện **trong sheet này** (FS-02.06 §9), không bao giờ xuất bản xem trước. Tải cuốn chiếu (§1 mục 5): ảnh tiếp
  theo được tải trong lúc ảnh trước đang ghi, không bao giờ quá 20 ảnh hoặc 2 GB đã tải mà chưa ghi.
- Trong lúc chạy màn hình không tự khoá; bật lại ở mọi lối ra. App ra nền → mẻ dừng như Cancel.
- **Cancel** hỏi *"Stop exporting? Files already exported stay in the folder."* → dừng trong ≤ 1 s, xoá tên tạm đang
  ghi. Không rollback: file đã xong là file hoàn chỉnh, và ổ có thể đã bị rút.
- Xong sạch: *"Exported 500 photos to “Exports”."* + **Done**, haptic success. Có việc cần báo thì thêm danh sách tên
  ảnh lỗi kèm lý do, và **Export Remaining** (mọi ảnh chưa ghi của mẻ) hoặc **Retry Failed** (chỉ ảnh lỗi).

## 3. Đường hỏng

| Hỏng | Phạm vi | Câu báo + lối ra |
|---|---|---|
| ảnh không đọc được, RAW iOS chưa đọc (FS-03.04b) | một ảnh, mẻ chạy tiếp | tên ảnh + *"iOS can't read this RAW yet"*; cặp RAW+JPEG ở Current Version dùng JPEG của cặp |
| ảnh bị gỡ khỏi tập chọn `.limited` giữa mẻ | một ảnh | *"ShotDex can't read this photo anymore."* |
| tải iCloud hỏng | một ảnh | như FS-02.06 §5 bước 4 |
| file > 4 GB lên ổ FAT32 | một file | *"Too large for this drive's format."* |
| ổ bị rút, folder mất giữa mẻ | **dừng mẻ** ≤ 2 s | *"“T7” was disconnected. 199 of 500 exported."* + Export Remaining (mờ tới khi ổ cắm lại) |
| đích đầy | **dừng mẻ** | *"“T7” is full — 212 of 500 exported."* + Export Remaining; tên tạm đang ghi bị xoá |
| không có quyền ghi | **dừng mẻ** | *"You can't write to this folder."* + Choose Another Folder (cùng câu FS-17.06 §6) |
| thiếu chỗ trước khi chạy | không ghi gì | *"Not enough space in “Exports” — needs 1.2 GB, 300 MB free."* + OK |

- Lỗi của **đích** dừng cả mẻ (ảnh sau cũng sẽ hỏng), lỗi của **một ảnh** thì chạy tiếp — cùng luật FS-15.02 §4.
- Tên tạm còn sót trên ổ bị rút được xoá ở lần ghi tiếp theo vào folder đó; chỉ xoá file có đuôi `.shotdex-part`.

## 4. Tiêu chí nghiệm thu

Ảnh mẫu **A** = HEIC 8064×6048 Fujifilm X-T5, chụp 2026-09-20 17:05:12, có GPS. Simulator dùng folder *On My iPhone ›
Exports* thay SSD; phần cần ổ thật ghi rõ.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | chọn 3 ảnh trong Library | mở ⋯ | có **Export…** ngay dưới Resize, glyph `square.and.arrow.up.on.square`, mờ khi 0 ảnh; ⋯ của Photo Detail cũng có; iOS 26.5 và 18.6 cùng chỗ | ✅ ⋯ chọn nhiều: `FileExportSettingsTests.menuRowSitsUnderResize` + dump `file-export-menu.json` — Export… ngay dưới Resize (y 282 trên 26.5, 311 trên 18.6, cùng thứ tự), mờ khi 0 ảnh, sáng khi 3 ảnh; ⋯ Photo Detail: `file-export-folder.json` ảnh `05-viewer-menu` (Export… cạnh Resize, menu mở ngược lên) |
| AC-2 | chưa export lần nào | Export… → Choose Folder… → *Exports* → Export 2 ảnh; đóng app; mở lại, Export… | lần hai hàng Folder đã là *Exports*, ghi thêm 2 file mà không mở trình chọn | ✅ (sim) `ExportFolderStoreTests.bookmarkSurvivesRelaunch`, `.staleBookmarkIsRenewed`, `.recentsKeepFive`, `.goneFolderDropsFromRecents` (+ *Not connected* giữ lại); `file-export-folder.json`: lần 1 ghi 2 file vào *On My iPhone › Exports*, mở lại app, lần 2 hàng Folder đã là *On My iPhone › Exports* và ghi thêm 2 file (Keep Both `(2)`) mà không qua trình chọn. Lần chọn đầu dùng `-ShotDexExportFolder` thay trình chọn của hệ thống (script không lái được nó). Ổ ngoài thật: chờ M (❓-1) |
| AC-3 | mẫu `{date}_{camera}_{seq}`; ảnh A, một ảnh X-T5 chụp 17:06, một ảnh chụp màn hình 2026-09-21 | nhìn dòng ví dụ, rồi Export (Current Version, JPEG) | ví dụ ghi `2026-09-20_X-T5_001.jpg`; folder có `2026-09-20_X-T5_001.jpg`, `2026-09-20_X-T5_002.jpg`, `2026-09-21_003.jpg` | ✅ `FileExportPlanTests.dateCameraSeqDropsMissingTokens` (plan và folder sau khi chạy: `2026-09-20_X-T5_001.jpg`, `2026-09-20_X-T5_002.jpg`, `2026-09-21_003.jpg`), `.exampleUsesFirstPhotoOfBatch` (ví dụ `2026-09-20_X-T5_001.jpg`, đổi ngay khi gõ Custom, ✓ sang Custom); màn File Name `ios26/ios18-05-file-name` (chip 102×32 so board 104×32; hàng mẫu cao hơn board 13pt vì hàng Form hai dòng của hệ thống) |
| AC-4 | folder đã có `img_0001.jpg`; mẻ có hai ảnh tên gốc `IMG_0001` (hai máy); mẫu `{original}`, Keep Both | Export | có `IMG_0001 (2).jpg` và `IMG_0001 (3).jpg`; SHA-256 của `img_0001.jpg` không đổi | ✅ `FileExportPlanTests.keepBothNumbersAgainstFolderAndBatch` (folder có `img_0001.jpg`, hai `IMG_0001` → `IMG_0001 (2)`, `IMG_0001 (3)`, SHA-256 của `img_0001.jpg` không đổi; khớp `ServerUploadPath.nextFreeName`), `.replaceStillNumbersTheBatchItself`; giữ `ServerUploadPathTests.keepBothPicksNextFreeName` |
| AC-5 | mẻ 20 ảnh, 12 tên đã có trong folder; If a File Exists = Replace | Export, rồi Cancel ở hộp hỏi; Export lại, chọn Replace | hộp *Replace 12 files in “Exports”?* hiện trước byte đầu; Cancel → 0 file đổi; Replace → 20 file, 12 file cũ mang nội dung mới. Skip → 8 file mới, tổng kết *12 skipped* | ⚠️ chưa có |
| AC-6 | ảnh A đã chỉnh Exposure +1 (Save Changes); Size 2048 px, JPEG, Quality 80, Metadata No Location | Export với Version Edited, rồi Version Original | Edited: JPEG 2048×1536, sáng hơn bản Original của cùng lượt; không GPS; còn Make `FUJIFILM`, Model `X-T5`, ngày chụp | ✅ (unit, renderer thật) `FileExportRunnerTests.editedIsTheCurrentVersion` (2048×1536, Edited sáng hơn Original cùng lượt, không GPS, còn Make `FUJIFILM`/Model `X-T5`/ngày chụp), `.originalIgnoresTheEdit` (chỉ đọc `.photo`), `.noLocationKeepsMakeModelDate`, `.stampSitsBetweenRenderAndMetadata`, `.stampFailureNeverWritesUnstamped`, `.videoGoesAsItIsAndLivePhotoIsAStill`; ảnh đã chỉnh trong Photos trên sim: chưa chụp |
| AC-7 | cặp `DSCF1000.RAF`+`DSCF1000.JPG`, Live Photo `IMG_0042`, video `IMG_0050.MOV` 10 s; mẫu `{date}_{seq}`, Live Photo Video bật | Export, Unmodified Original | 5 file: `…_001.RAF`, `…_001.JPG`, `…_002.HEIC`, `…_002.MOV`, `…_003.MOV`; SHA-256 mỗi file bằng tài nguyên gốc trong Photos | ✅ `FileExportRunnerTests.unmodifiedCopiesEveryOriginalByteForByte` (5 file `2026-09-20_001.RAF/.JPG`, `_002.HEIC/.MOV`, `_003.MOV`, SHA-256 từng file = nguồn, 0 `.shotdex-part`), `.livePhotoVideoSwitch`, `.dateFoldersNestByDay`; `FileNameTemplateTests` (mọi token, bỏ token thiếu kèm dấu nối, ký tự exFAT, 200 ký tự, `{seq}` 4 chữ số từ 1000). Sim với thư viện thật: xem AC-2 |
| AC-8 | 2 ARW đọc được, 1 RAW-only iOS chưa đọc, 1 cặp RAW chưa đọc + JPEG | Export, Current Version, 1080 px | 2 JPEG cạnh dài 1080 từ ARW; cặp ra JPEG 1080 từ JPEG của cặp; RAW-only nằm trong tổng kết với *iOS can't read this RAW yet*; không file nào từ bản xem trước | ✅ (unit, fixture RAW thật) `FileExportRunnerTests.unreadableRAWOnlyIsListed` (2 ARW → JPEG cạnh dài 1080; cặp RAF chưa đọc + JPEG → 1080 từ JPEG; RAF-only `X-Q9` → tổng kết *iOS can't read this RAW yet*, không file), `.pairFallsBackToItsJPEG` (đọc RAW trước, JPEG chỉ khi bị từ chối), `.readableARWRendersAt1080` (Model `ILCE-7M3` giữ nguyên); không có đường nào lấy bản xem trước |
| AC-9 | 20 ảnh 6000×4000, 5 chỉ trên iCloud, ảnh thứ 7 hỏng khi tải; Size Original | Export | tiến độ tải hiện trong sheet; 19 file đủ 6000×4000; tổng kết nêu tên ảnh hỏng + Retry Failed; Retry Failed chỉ tải lại ảnh đó | ⚠️ chưa có (giả iCloud bằng `-ShotDexFakeICloud`; máy thật cho PhotoKit thật) |
| AC-10 | mẻ 100 ảnh, đang ghi ảnh 40 | Cancel → Stop | dừng ≤ 1 s; folder có 39 file hoàn chỉnh, 0 file `.shotdex-part`; Export Remaining ghi 61 ảnh còn lại với `{seq}` 040–100 | ⚠️ chưa có |
| AC-11 | 500 ảnh lên SSD exFAT, rút ổ ở ảnh ~200 | lượt ghi kế tiếp lỗi | ≤ 2 s sau: *“T7” was disconnected. 199 of 500 exported.*, không treo; hàng Folder *Not connected*; cắm lại → Export Remaining ghi 301 ảnh còn lại, tên tạm sót bị xoá | ⚠️ chưa có (logic bằng client giả ném lỗi; rút ổ thật chỉ trên máy) |
| AC-12 | folder còn 300 MB; Unmodified Original 40 ảnh tổng 1.2 GB | Export | trước byte đầu: *Not enough space in “Exports” — needs 1.2 GB, 300 MB free.* + OK; folder không có file mới | ⚠️ chưa có |
| AC-13 | 500 JPEG 24 MP, Current Version 2048 px | Export | đỉnh RAM cao hơn lúc xuất 1 ảnh không quá dung lượng 1 file gốc; không lúc nào có quá 1 bản render trong thư mục tạm | ⚠️ chưa có (cách đo như `ShareExportPipelineTests.twentyPhotosPeakIsFlat`) |
| AC-14 | preset tự tạo *Client 3000* (cạnh dài 3000, JPEG 90%); `a.JPG` 6000×4000 trên NAS đã chỉnh | sheet xuất server → Size = Client 3000 → Original Folder → Export | hàng Size có Original, 4K, 2048 px, 1080 px, Client 3000; server có `a_edited.jpg` 3000×2000 qua tên tạm + SHA-256. 3 ảnh thư viện qua sheet Export tới connection đó ra 3 file trên server, 0 dòng lịch sử upload, ảnh không có dấu đã-lên-server | một phần: vế 1 ✅ `ServerExportSizeTests.everyNonComposedExportOffersAllPresets` (Original · 4K · 2048 px · 1080 px · Client 3000, Original mặc định), `.resizeStartsAt2048`, `.customPresetRendersAtItsSize` (`a_edited.jpg` 3000×2000 qua part + SHA, Format theo preset); vế 2 (Export → connection) ⚠️ chưa có |
| AC-15 | Duo ngoài 466×678; iPhone 17 26.5, iPhone 16 18.6, iPad 13, Duo trong | mở sheet Export và màn File Name | Duo ngoài: mọi control trong x ≤ 382, dòng ví dụ không cắt; iPad: form ≤ 700pt canh giữa; hai nhánh iOS cùng hàng, cùng chữ | ⚠️ chưa có |

**Chưa chứng minh được:** cả 15 AC (spec mới). Cần máy thật + SSD cho AC-11 và phần ổ thật của AC-2, AC-12.

## 5. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| bookmark folder trên ổ ngoài có mở lại được sau khi rút/cắm, sau khi khởi động lại máy hay không | đo trên iPhone USB-C + SSD exFAT và APFS ở `/plan`; không mở được thì hàng Folder rơi về *Choose it again* (07b §4) |
| hệ thống trả lỗi gì khi ổ bị rút giữa lúc ghi (mất file, lỗi I/O, treo điều phối file) | đo trên máy; mọi lỗi đọc/ghi của đích kèm folder không còn tới được thì gọi là *disconnected*, có trần 2 s |
| dịch vụ cloud (Dropbox) không báo chỗ trống, nhận file rồi mới đồng bộ | bỏ bước kiểm chỗ (07b §9); file nằm trong folder của dịch vụ trên máy là xong, như FS-17.05 §4 |
| ước lượng dung lượng Current Version lệch, nên kiểm chỗ trước vẫn có thể hết chỗ giữa mẻ | đích đầy dừng mẻ, xoá tên tạm, Export Remaining (§3) |
| tên Keep Both / Replace trên đích không phân biệt hoa thường mà app so có phân biệt | luôn so không phân biệt hoa thường (07b §6) |
| hai lối "Save to Files" (của share sheet, của Export) làm người dùng phân vân | chạy agent `copy-consistency` và `ux-reviewer` sau khi làm |
