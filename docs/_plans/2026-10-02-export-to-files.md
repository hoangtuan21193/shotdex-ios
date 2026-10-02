# Kế hoạch — Xuất ra folder: Files, ổ ngoài, server đã lưu (FS-03.07b/07c)

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-03.07b`](../02-functional-spec/FS-03-photo-editor/07b-export-to-files.md) + [`07c`](../02-functional-spec/FS-03-photo-editor/07c-export-acceptance-criteria.md) — 15 AC; chỗ chạm [FS-15.02 §2](../02-functional-spec/FS-15-server-upload/02-upload-flow.md), [FS-17.06 §5b/§6](../02-functional-spec/FS-17-import-from-server/06-edit-and-export.md) |
| Intent | [2026-09-30-user-wishes-research](../_intents/2026-09-30-user-wishes-research.md) mục 4 |
| Ngày | 2026-10-02 |
| Trạng thái | **approved 2026-10-03** — 16 task (một AC một task; AC-14 tách hai vế), + T0 export board canvas, + M đo máy thật. Quyết định ở §7 |

## 1. Hiểu đúng chưa

Một lệnh **Export…** mới, ngay dưới Resize trong ⋯ của chế độ chọn (Library, album, smart album, On This Day) và ⋯
của Photo Detail, mở một Form bốn section. Nó ghi ảnh ra **một folder bất kỳ** trình chọn folder của hệ thống cho
chọn (On My iPhone, iCloud Drive, Dropbox, SSD cắm cáp) hoặc **một connection server đã lưu**. Hai chế độ:

- **Current Version**: mỗi ảnh render **một lần** ở preset của Resize (Format, Quality, Metadata 3 mức của FS-08.06),
  bản Edited (mặc định) hoặc Original. Live Photo ra ảnh tĩnh, video đi nguyên file.
- **Unmodified Original**: chép **nguyên byte** mọi file gốc của asset (RAW + JPEG, ảnh + video Live Photo, video),
  không hàng Metadata.

Tên file theo mẫu token (`{original} {date} {time} {camera} {lens} {seq}`), tính cho **cả mẻ trước byte đầu**. Trùng
tên: Keep Both / Replace (hỏi một lần) / Skip, so không phân biệt hoa thường; hai ảnh cùng mẻ trùng tên luôn được đánh
số. Ghi qua tên tạm `.shotdex-part` rồi đổi tên. Lỗi của đích dừng mẻ, lỗi của một ảnh thì chạy tiếp. Có Export
Remaining và Retry Failed. iCloud tải **cuốn chiếu** (≤ 20 ảnh hoặc 2 GB đã tải mà chưa ghi) — ngoại lệ đã ghi ở
FS-02.06 §5. Folder nhớ bằng bookmark và danh sách 5 folder gần đây trong cài đặt app, **không** đụng database.
Sheet xuất server (FS-17.06) thêm hàng Size ở mọi lần xuất không gộp, dùng cả preset tự tạo, và thêm dòng
**Folder in Files…**. Sheet Upload không đổi.

Đọc thêm hai điểm (kỹ thuật, tự quyết — lý do ở §4):
- "Current Version · Edited" là **bản hiện hành trong Photos** (resource `.fullSizePhoto` khi có), không phải bản
  gốc + recipe. "Original" là nguồn gốc như editor chọn: RAW đọc được thì RAW, không thì JPEG của cặp.
- Video ở Current Version đi **nguyên file của bản hiện hành** (`.fullSizeVideo` nếu đã cắt trong Photos, không thì
  `.video`), không chuyển mã. Unmodified Original luôn là `.video`.

## 2. Đối chiếu AC ↔ code

Cả spec là tính năng mới, nên hầu hết là ❌. Các mảnh **đã có** được ghi trong cột Bằng chứng và ở §3. Bảng dưới là
bản đọc code ngày 2026-10-02 (`9134db3`).

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 ⋯ có **Export…** dưới Resize, glyph `square.and.arrow.up.on.square`, mờ khi 0 ảnh; Photo Detail cũng có; 26.5 = 18.6 | ❌ | `PhotoCommand` không có case export (`Features/Shared/PhotoCommand.swift:6-19`, `albumSelectionMenu` `:59-61`). Hàng Resize của chế độ chọn `SelectionBarViews.swift:240-245` (`onCompress`, cắm ở `LibraryScreen.swift:583`, `AlbumDetailScreen.swift:554`, `SmartAlbumDetailScreen.swift:529`, `OnThisDayScreen.swift:325`). Photo Detail: Resize chỉ cho ảnh tĩnh `PhotoDetailScreen.swift:794-806`. `DESIGN.md:155` chưa có glyph | `PhotoCommand.export`, `SelectionBarModel.onExport`, hàng sau Resize ở 4 màn + Photo Detail (cả video), glyph vào `DESIGN.md` §8 |
| AC-2 lần hai hàng Folder đã là *Exports*, ghi mà không mở trình chọn | ❌ | Không có kho folder xuất. Có sẵn: `FolderPicker` (`OnCloudScreen.swift:197-222`), tạo bookmark (`:182-195`), mở bookmark `FilesFolderClient.connect` (`FilesFolderClient.swift:24-37`) — nhưng **bỏ qua `isStale`** (`:26-27`), trái 07b §4 "bookmark cũ thì tạo lại" | `ExportFolderStore` (Data, UserDefaults): bookmark + tên ổ/volume UUID, ≤ 5 gần đây, tạo lại khi cũ, ba trạng thái *mở được / Not connected / không còn* |
| AC-3 `{date}_{camera}_{seq}`: ví dụ `2026-09-20_X-T5_001.jpg`; ra `…_001`, `…_002`, `2026-09-21_003.jpg` | ❌ | Không có mẫu tên. Có sẵn: camera/lens chuẩn hoá như chip lọc (`photo_metadata.normalizedCameraModel/normalizedLensModel`, `LibraryQueries.swift:267-274`), đọc cả mẻ một lần `LibraryQueries.metadata(assetIds:)` `:111`; ngày như Date Folders (`ServerUploadPath.dayFolder` `:24`, lấy `asset.creationDate` như `PhotoKitOriginalExporter.swift:63`) | `FileNameTemplate` (Domain, thuần) + màn File Name + dòng ví dụ |
| AC-4 `img_0001.jpg` có sẵn + hai `IMG_0001` → `(2)`, `(3)`; file cũ giữ SHA | một phần ✅ | ✅ `ServerUploadPath.nextFreeName` không phân biệt hoa thường (`ServerUploadPath.swift:44-57`), test `ServerUploadPathTests.keepBothPicksNextFreeName` (`ShotDexTests/ServerUploadPathTests.swift:52`). ❌ đặt tên **cả mẻ** (trùng chính nó, kể cả ở Replace) chưa có: upload xử trùng từng file lúc ghi (`ServerUploadSession.swift`, nhánh `.keepBoth`) | `FileExportPlan` gom tên đã cấp vào tập "đã chiếm" khi đi qua mẻ; giữ test cũ, thêm test mẻ |
| AC-5 Replace hỏi một lần trước byte đầu; Cancel → 0 đổi; Replace → 12 cũ mang nội dung mới; Skip → 8 + *12 skipped* | ❌ | Upload hỏi từng file (`ServerUploadSession` `resolveConflict`), không hỏi một lần cả mẻ. `ServerEditWriter` có `.replaceOriginal` (xoá rồi đổi tên sau khi kiểm, `ServerEditWriter.swift:46-60`) — dùng cho đích server | đếm trùng trong plan → một alert; Replace ghi tên tạm xong mới thay file cũ |
| AC-6 Edited vs Original, 2048 JPEG 80, No Location: Edited sáng hơn; không GPS; còn Make/Model/ngày | ❌ | Mảnh có sẵn: `PhotoRenderService.write(…, metadata:)` lọc theo `MetadataLevel` (`ShotDexKit/Render/PhotoRenderService.swift:690-724`), `resize` `:631`, `resolvedOutputFormat` (Same as Original: RAW→JPEG, HEIC→HEIC, khác→JPEG) `:1113-1121`, `MetadataLevel.sharingDefault()` (`SettingsKeys.swift:129`). **Không dùng nguyên `PhotoEditingService.compress`**: đường session của nó render bản gốc với `.identity` (`PhotoEditingService.swift:544-560`, `:572`), nên ảnh đã chỉnh trong ShotDex mất bản chỉnh khi ảnh có sẵn trên máy, trong khi đường `preparedOriginal` (`:532-543`) lại dùng bản hiện hành (`OriginalFetcher.swift` `fetch` ghi "current version") | render từ **file** của bản cần xuất qua seam `ExportRendering`; Edited = `.fullSizePhoto` khi có. Chỗ lệch của Resize đã ghi `REVIEW_QUEUE.md` lúc duyệt (§7 ⚠️-2) |
| AC-7 Unmodified Original: 5 file `…_001.RAF/.JPG`, `…_002.HEIC/.MOV`, `…_003.MOV`, SHA = gốc | ❌ | Có sẵn: liệt kê file gốc của asset `PhotoKitOriginalExporter.entries` (`originalTypes` `:21`: photo, alternatePhoto, video, pairedVideo, audio) + `ServerUploadPlan.files(kind: .allOriginals)` (`ServerUploadPlan.swift:51-60`); đọc resource theo khối `PHAssetResourceManager.requestData` → `StreamWriter` (`OriginalFetcher.swift` `fetch`) | dùng lại danh sách file gốc; một tên gốc cho cả nhóm file của asset, giữ đuôi gốc nguyên chữ hoa/thường |
| AC-8 2 ARW → JPEG 1080; cặp RAW không đọc được → từ JPEG; RAW-only không đọc được vào tổng kết; không từ bản xem trước | ❌ | Có sẵn: `ReadableSource.load` rơi về JPEG của cặp (`Domain/Editing/ReadableSource.swift:13-25`), `UnsupportedRAWError.matches`, lỗi nêu tên máy `RAWFileCamera.error` (`PhotoEditingService.swift:325-331`); Resize làm đúng luật này (FS-03.04b AC-14) | dùng lại, câu ngắn *iOS can't read this RAW yet* ở tổng kết |
| AC-9 5/20 ảnh iCloud, ảnh 7 hỏng: tiến độ tải trong sheet; 19 file đủ cỡ; Retry Failed chỉ tải lại ảnh đó | ❌ | `OriginalPreparation` tải **cả mẻ rồi mới làm**, kiểm chỗ cả mẻ, hỏi Continue/Retry/Cancel giữa chừng (`OriginalPreparation.swift:107-160`) — đúng cho Resize/Share, **sai** cho Export (07c §1 mục 5, FS-02.06 §5 ngoại lệ). Có sẵn: `OriginalFetching` (`probe`, `byteCount`, `fetch` có progress, huỷ được) + `FakeOriginalFetcher` (`-ShotDexFakeICloud`). `fetch` chỉ lấy **bản hiện hành**, không lấy từng file gốc | `RollingOriginalPrefetcher` (Data) trên `OriginalFetching`, cửa sổ 20 ảnh / 2 GB; mở rộng `OriginalFetching` nhận resource cần lấy |
| AC-10 Cancel ở ảnh 40/100: ≤ 1 s; 39 file, 0 `.shotdex-part`; Export Remaining ghi 61 ảnh, `{seq}` 040–100 | ❌ | Có sẵn mẫu: Cancel hỏi xác nhận + ra nền dừng (`ServerUploadSheet.swift:48-58`), giữ màn hình sáng `ScreenAwakeCoordinator.beginHold/endHold` (`:40-49`), xoá part kiểu detached (`ServerUploadSession` `removeQuietly`, `ServerEditWriter.swift:61-64`) | plan giữ tên cả mẻ; runner huỷ được, xoá part đang ghi |
| AC-11 rút ổ ở ảnh ~200: ≤ 2 s *“T7” was disconnected. 199 of 500 exported.*, Folder *Not connected*; cắm lại → Export Remaining; part sót bị xoá | ❌ | Có sẵn: phân lỗi đích/lỗi file `RemoteFileError.stopsBatch` (`RemoteFileClient.swift:96-106`), map lỗi Cocoa (`FilesFolderClient.map` `:84-97`). Không có trần thời gian, không phân biệt "ổ rút" với "folder mất" | `FileExportFailure` (Domain) phân loại; watchdog 2 s quanh mỗi lượt ghi điều phối |
| AC-12 thiếu chỗ: *Not enough space in “Exports” — needs 1.2 GB, 300 MB free.* trước byte đầu | ❌ | Có sẵn: `DiskSpace.availableBytes(for:)` (`Core/Utils/DiskSpace.swift:15-22`, chỉ khoá `ImportantUsage`), `RemoteFileClient.storageSpace(at:)` (FilesFolderClient không cài, trả nil), `LibraryQueries.fileSizeTotal(assetIds:)` `:123`, luật `OriginalPreparationState.fits` | `FileExportSpaceEstimate` (Domain); đọc chỗ trống của volume đích (❓-3) |
| AC-13 500 JPEG 24 MP, 2048: đỉnh RAM ≤ 1 file gốc; ≤ 1 bản render trong thư mục tạm | ❌ | Mẫu đo `ShareExportPipelineTests.twentyPhotosPeakIsFlat` (`ShotDexTests/ShareExportPipelineTests.swift:259`) | render một ảnh một lúc, ghi thẳng tên tạm ở đích; đo footprint 1 vs N |
| AC-14 Size có Original, 4K, 2048, 1080, *Client 3000*; `a_edited.jpg` 3000×2000 qua part + SHA; 3 ảnh thư viện qua Export tới connection: 0 dòng lịch sử, không dấu | ⚠️ vế 1 (đã quyết: spec đúng, sửa code) · ❌ vế 2 | ⚠️ Hàng Size chỉ có ở **Resize** của server (`ServerPhotoCommands.swift:202-207`), chỉ built-in **bỏ Original**, mặc định là phần tử đầu = **4K** (`ServerExportModel.swift:89`); Edit và Paste Edits không có Size (`ServerPhotoCommands.swift:183-187`), picker chỉ hiện khi `resizePresets != nil` (`ServerExportSheet.swift:189-200`). ✅ tên `_edited` + part + SHA (`ServerEditWriter.swift:38-64`, test `ServerEditExportTests.newFileBesideOriginal`). ❌ Export sheet → connection chưa có; không ghi lịch sử là đúng nếu đi qua `ServerEditWriter` (không có `Recorder`) | vế 1 sớm (sheet có sẵn); vế 2 sau khi runner có đích server. Quyết định ⚠️-1 |
| AC-15 Duo ngoài: control x ≤ 382, ví dụ không cắt; iPad form ≤ 700 canh giữa; hai nhánh iOS cùng hàng, cùng chữ | ❌ | Có sẵn mẫu form 700pt của Resize (FS-03.07 §4) | ảnh + dump trên 5 cấu hình, design-parity với board |

**Tổng:** ✅ 0 trọn AC (AC-4 và AC-14 có phần đã đạt, khoá bằng test đã có) · ⚠️ 1 (AC-14 vế 1) · ❌ 14.
**Chạm FS-15.02:** sheet Upload **không đổi** — đúng hiện trạng (`ServerUploadSheet` chỉ đẩy bản gốc, không preset); chỉ
sửa câu "chưa làm" ở §2 khi AC-14 xanh.

## 3. Tái dùng

| Có sẵn | Dùng cho |
|---|---|
| `CompressionPresetStore.allPresets` (`Data/Sources/CompressionPresetStore.swift:9-11`), `ResizePreset.targetPixelSize` (kit) | Size của sheet Export và sheet xuất server — một danh sách, cùng tên với Resize và Settings |
| `PhotoRenderService.render/resize/write(metadata:)`, `resolvedOutputFormat` (kit) | Current Version; **không đổi kit** |
| `MetadataLevel` + `.sharingDefault()` + `MetadataLevel.title` (`Features/Shared/MetadataLevel+Labels.swift`) | hàng Metadata, mặc định từ Settings, không nhớ |
| `ReadableSource`, `UnsupportedRAWError`, `RAWFileCamera` | AC-8 |
| `OriginalFetching` + `PhotoKitOriginalFetcher` (stream `requestData` theo khối, huỷ được) + `FakeOriginalFetcher` | tải cuốn chiếu; giả iCloud trên sim cho AC-9 |
| `PhotoKitOriginalExporter.entries` + `ServerUploadPlan.files(.allOriginals)` | danh sách file gốc cho Unmodified Original |
| `ServerUploadPath.nextFreeName`, `.dayFolder`, `.partSuffix` | Keep Both, Date Folders, tên tạm |
| `ServerEditWriter` (part → SHA → rename, không lịch sử) + `RemoteAccessPool` + `ServerBrowserModel(mode: .chooseFolder)` | đích là connection đã lưu (07b §7) |
| `FolderPicker`, cách tạo bookmark của On Cloud | Choose Folder… và Folder in Files… |
| `TemporaryWorkspace` (thêm tiền tố `ShotDexExport-`) | thư mục tạm của tải cuốn chiếu + render cho đích server |
| `ScreenAwakeCoordinator.beginHold/endHold` | màn hình không khoá trong lúc chạy |
| Cách tính ETA 30 s (`ServerUploadModel.swift:311-319`, `ServerDownloadModel.swift:266-274` — hai bản chép) | rút ra `TransferRateEstimate` (Domain) cho Export; chuyển hai chỗ cũ sang → `REVIEW_QUEUE.md`, ngoài AC |
| `ShareExportPipelineTests.twentyPhotosPeakIsFlat` | cách đo AC-13 |

## 4. File đổi

| Tầng | File | Đổi |
|---|---|---|
| Domain | `Domain/FileExport/FileNameTemplate.swift` (mới) | token, ví dụ, bỏ token thiếu kèm dấu nối thừa, ký tự exFAT → `-`, bỏ `.` đầu, cắt 200, `{seq}` 3/4 chữ số |
| Domain | `Domain/FileExport/FileExportPlan.swift` (mới) | thứ tự (ngày chụp rồi tên gốc), `{seq}` theo ảnh, nhóm file của asset chung một tên, tên cả mẻ trước byte đầu, trùng không phân biệt hoa thường, trong-mẻ luôn đánh số, đếm trùng cho Replace/Skip, Date Folders; giữ nguyên tên khi chạy Export Remaining |
| Domain | `Domain/FileExport/FileExportSpaceEstimate.swift` (mới) | Unmodified = tổng gốc; Current = gốc × tỉ lệ pixel của preset; đích không báo thì bỏ qua |
| Domain | `Domain/FileExport/FileExportFailure.swift` (mới) | lỗi đích (dừng mẻ: rút ổ, đầy, không quyền) / lỗi ảnh (chạy tiếp: không đọc được, RAW chưa đọc, `.limited`, tải hỏng, > 4 GB lên FAT32) + câu báo 07c §3 |
| Domain | `Domain/FileExport/FileExportProgress.swift` + `Domain/Shared/TransferRateEstimate.swift` (mới) | `Exporting k of n`, byte, ETA 30 s, bước *Preparing · Converting · Writing*, dòng tổng kết |
| Data | `Data/Sources/FileExport/ExportFolderStore.swift` (mới) | bookmark + tên folder/ổ + volume UUID, ≤ 5 gần đây, tạo lại khi cũ, trạng thái mở được / Not connected / không còn; mọi lựa chọn được nhớ của 07b §3 (UserDefaults, khoá mới trong `SettingsKeys`) |
| Data | `Data/Sources/FileExport/ExportDestinationWriter.swift` (mới) | protocol + `LocalFolderWriter`: ghi trong `NSFileCoordinator` thẳng vào `<tên>.shotdex-part` (closure nhận URL, nên render ghi thẳng vào đích), kiểm đủ byte + mở được, đổi tên; Replace thay file cũ sau khi part xong; xoá part sót; watchdog 2 s. `RemoteFolderWriter`: render ra một file tạm rồi `ServerEditWriter` |
| Data | `Data/Sources/FileExport/FileExportRunner.swift` (mới, actor) | một ảnh một lúc: chuẩn bị → render/chép → **[stamp]** → ghi metadata → ghi; huỷ, Export Remaining, Retry Failed; seam `ExportAssetSource` (PhotoKit thật / file giả) và `ExportRendering` |
| Data | `Data/Sources/FileExport/RollingOriginalPrefetcher.swift` (mới) | cửa sổ 20 ảnh / 2 GB trên `OriginalFetching`; probe video bằng chunk đầu, không đọc trọn |
| Data | `Data/Sources/OriginalFetcher.swift`, `FakeOriginalFetcher.swift` | `fetch` nhận resource cần lấy (bản hiện hành, hoặc một file gốc theo khoá của `PhotoKitOriginalExporter`); mặc định giữ hành vi cũ |
| Data | `Data/Sources/FileExport/PhotoKitExportSource.swift` (mới) | file của asset: `.fullSizePhoto`/`.photo` cho Current; nguồn Original theo `ReadableSource`; file gốc cho Unmodified; `.limited` gỡ giữa mẻ → lỗi ảnh |
| Core | `Core/Utils/SettingsKeys.swift`, `Core/Utils/TemporaryWorkspace.swift` | khoá `export.*`; tiền tố `ShotDexExport-` |
| Features | `Features/FileExport/FileExportSheet.swift`, `FileExportModel.swift`, `FileNameScreen.swift`, `FileExportRunView.swift` (mới) | Form 4 section, menu Folder, màn File Name, tiến độ + tổng kết; logic trong model, không trong view |
| Features | `Features/Shared/PhotoCommand.swift`, `App/SelectionBarModel.swift`, `Features/Library/SelectionBarViews.swift`, `LibraryScreen`, `AlbumDetailScreen`, `SmartAlbumDetailScreen`, `OnThisDayScreen`, `PhotoDetailScreen` | hàng Export… |
| Features | `Features/ServerImport/ServerExportModel.swift`, `ServerExportSheet.swift`, `ServerPhotoCommands.swift`, `Domain/ServerImport/ServerEditExport.swift` | Size ở mọi lần xuất không gộp (kể cả preset tự tạo, Original đầu, Resize mặc định 2048 px); preset có Format/Quality riêng thì đặt theo; đích mới **Folder in Files…** |
| Chữ | `Localizable.xcstrings` | mọi câu 07b/07c (số nhiều cho `photos/videos`, *12 skipped*, *Replace 12 files…*) |
| Test | `FileNameTemplateTests`, `FileExportPlanTests`, `FileExportSpaceEstimateTests`, `FileExportFailureTests`, `TransferRateEstimateTests`, `ExportFolderStoreTests`, `LocalFolderWriterTests`, `FileExportRunnerTests`, `RollingOriginalPrefetcherTests`, `FileExportMemoryTests`, `ServerExportSizeTests`; sửa `ServerEditMenuTests` nếu cần | thư mục tạm thật, file sinh bằng ImageIO, không ảnh người |
| Script | `ShotDexUITests/scripts/file-export-*.json` | menu, sheet, File Name, chạy, tổng kết; mọi thiết bị |
| Docs | FS-03.07c cột chứng minh; FS-15.02 §2 + FS-17.06 §5b/§6/§6 bảng (bỏ "chưa làm"); `DESIGN.md` §8 glyph; FS-02.06 không đổi (ngoại lệ đã ghi) | |

**Không đổi:** database (07b §9 — không migration), ShotDexKit, các extension, sheet Upload.

### Chỗ nối watermark (FS-05.04, plan viết song song)

Runner có **một bước đóng dấu nằm giữa render và ghi metadata**, chỉ ở Current Version:

```
nguồn → render(source, .identity) → resize(preset) → stamp?(result, item) → write(result, metadata: level, quality, format)
```

- `FileExportJob.stamp: (any ExportStamping)?` — `func stamp(_ result: PhotoRenderResult, for item: FileExportItem) async throws -> PhotoRenderResult`. Task 5 cài seam với `nil`; FS-05.04 cấp bản thật.
- Bước ghi metadata đọc thuộc tính **của file nguồn** (`result.properties`), không của ảnh đã đóng dấu, nên luật
  "render rồi mới ghi metadata" của FS-05.04 §5 đứng được mà không đổi kit.
- Stamp ném lỗi → **lỗi một ảnh** (bỏ khỏi mẻ, nêu tên ở tổng kết), không bao giờ ghi bản không dấu.
- Unmodified Original **không** đi qua bước này (nguyên byte). Sheet chừa chỗ một hàng 44pt trong section Export,
  dưới Format/Quality; FS-05.04 quyết hàng đó và chuyện Unmodified Original khi watermark bật.
- Sheet xuất server render qua `EditorBatchSaver.renderToFile` — chỗ nối ở đó là việc của plan FS-05.04.

## 5. Thứ tự task (một AC = một commit)

| # | Task | AC | Test / bằng chứng |
|---|---|---|---|
| T0 | **Không code — board đã có**, chỉ export: `PH33`/`IP23`/`IPP19`/`DI18`/`DIP18`/`DC19` `_Export` (hai chế độ), `PH34`/`IP24`/`IPP20`/`DI19`/`DIP19`/`DC20` `_FileName`, `PH35_ExportRunning`, `PH36_ExportSummary` (hai board sau chỉ có ở hàng iPhone — máy khác so bằng ảnh với board iPhone). Export `project/` vào `build/design/editor/project/`, `Tools/design-board render` | — | danh sách board đã nằm trong FS-03.07b cuối file |
| T1 | **Sheet xuất server dùng preset:** Size ở Edit / Paste Edits / Resize, danh sách `allPresets` (kể cả tự tạo), Original đầu và mặc định, Resize mặc định 2048 px; preset có format/quality riêng thì đặt Format theo nó | AC-14 vế 1 (⚠️-1: spec đúng, sửa code) | `ServerExportSizeTests.everyNonComposedExportOffersAllPresets`, `.resizeStartsAt2048`, `.customPresetRendersAtItsSize` (`a.JPG` 6000×4000 → `a_edited.jpg` 3000×2000, qua `ServerEditWriter` giả); ảnh sheet (hàng Size không có board riêng trong danh sách T0 — so bằng ảnh + `hig-components`) |
| T2 | `PhotoCommand.export` + hàng ở 4 màn chọn + Photo Detail (ảnh và video); sheet khung (4 section, Cancel/Export, Export mờ khi chưa có folder); nhớ lựa chọn (`ExportFolderStore` phần settings); glyph vào `DESIGN.md` §8 | AC-1 | `FileExportSettingsTests.remembersWhatSpecSaysAndNotMetadataOrVersion`; `scripts/file-export-menu.json` dump vị trí hàng (26.5 + 18.6), design-parity |
| T3 | Runner lõi + **Unmodified Original**: `FileNameTemplate` đủ token, `FileExportPlan` (nhóm file của asset chung tên), `LocalFolderWriter` (part → kiểm → đổi tên), chép theo khối, Live Photo Video bật/tắt | AC-7 | `FileNameTemplateTests` (mọi token, bỏ token thiếu, ký tự exFAT, 200 ký tự, `{seq}` 4 chữ số ở 1000), `FileExportRunnerTests.unmodifiedCopiesEveryOriginalByteForByte` (SHA từng file), `.livePhotoVideoSwitch`; sim: cặp RAW+JPEG (fixture `~/Library/Caches/ShotDexFixtures/raw`), Live Photo, MOV → *On My iPhone › Exports* |
| T4 | Folder nhớ: Choose Folder… → bookmark, ≤ 5 gần đây, tạo lại khi cũ, connection đã lưu trong menu, *Not connected* / *can't open anymore* | AC-2 | `ExportFolderStoreTests.bookmarkSurvivesRelaunch`, `.staleBookmarkIsRenewed`, `.recentsKeepFive`, `.goneFolderDropsFromRecents`; `scripts/file-export-folder.json`: lần 1 qua trình chọn, kill app, lần 2 không mở trình chọn |
| T5 | **Current Version**: nguồn Edited (`.fullSizePhoto`) / Original, render một lần ở preset, Same as Original, Fill crop giữa, Metadata 3 mức (mặc định Settings), Live Photo → ảnh tĩnh, video nguyên file; **seam stamp** (nil) | AC-6 | `FileExportRunnerTests.editedIsTheCurrentVersion`, `.originalIgnoresTheEdit`, `.noLocationKeepsMakeModelDate`, `.stampSitsBetweenRenderAndMetadata` (stamp giả tô 1 pixel → file có pixel đó, còn Make), `.stampFailureNeverWritesUnstamped`; sim: ảnh Exposure +1, hai lượt, đọc file bằng ImageIO |
| T6 | Màn **File Name**: 3 mẫu dựng sẵn ✓, Custom 44pt, chip token 32pt có nhãn VO *Insert Date*…, dòng ví dụ từ ảnh đầu mẻ đổi khi gõ | AC-3 | `FileExportPlanTests.dateCameraSeqDropsMissingTokens` (đúng ba tên của AC), `.exampleUsesFirstPhotoOfBatch`; ảnh màn File Name + design-parity |
| T7 | Trùng tên cả mẻ: so không phân biệt hoa thường với danh sách đọc **một lần**, trong-mẻ luôn đánh số kể cả Replace | AC-4 | `FileExportPlanTests.keepBothNumbersAgainstFolderAndBatch` (`IMG_0001 (2)`, `(3)`, `img_0001.jpg` SHA không đổi), `.replaceStillNumbersTheBatchItself`; giữ `ServerUploadPathTests.keepBothPicksNextFreeName` |
| T8 | Replace (một alert trước byte đầu, ghi xong mới thay) và Skip (*12 skipped — already in the folder*) | AC-5 | `FileExportRunnerTests.replaceAsksOnceBeforeFirstByte`, `.cancelAtReplaceChangesNothing`, `.replaceSwapsAfterPartIsComplete`, `.skipLeavesExisting`; ảnh alert + tổng kết |
| T9 | RAW không đọc được: RAW-only vào tổng kết, cặp → JPEG của cặp; không bao giờ bản xem trước | AC-8 | `FileExportRunnerTests.unreadableRAWOnlyIsListed`, `.pairFallsBackToItsJPEG`, `.readableARWRendersAt1080` (fixture ARW thật; thiếu fixture thì RAW giả qua `UnsupportedRAWError`) |
| T10 | Tiến độ (`Exporting k of n`, byte, ETA 30 s, bước), không kéo xuống đóng, màn hình sáng, ra nền = Cancel, Cancel hỏi, dừng ≤ 1 s + xoá part, Export Remaining giữ `{seq}`, Retry Failed, haptic success | AC-10 | `FileExportRunnerTests.cancelStopsWithinASecondAndLeavesNoPart` (100 ảnh giả, cancel ở 40 → 39 file, 0 part), `.exportRemainingKeepsPlannedNames` (040–100), `TransferRateEstimateTests`; ảnh sheet chạy + design-parity |
| T11 | Kiểm chỗ trước byte đầu, footer *412 GB free on T7*, đích không báo thì bỏ qua | AC-12 | `FileExportSpaceEstimateTests.unmodifiedSumsOriginals`, `.currentScalesByPixelRatio`, `.unknownFreeSkipsTheCheck`; `FileExportRunnerTests.notEnoughSpaceWritesNothing` |
| T12 | Lỗi đích dừng mẻ ≤ 2 s (rút ổ, đầy, không quyền + Choose Another Folder), lỗi ảnh chạy tiếp, > 4 GB lên FAT32, part sót bị xoá ở lần ghi sau (chỉ `.shotdex-part`), hàng Folder *Not connected*, Export Remaining mờ tới khi cắm lại | AC-11 | `FileExportFailureTests` (mỗi dòng 07c §3), `LocalFolderWriterTests.disconnectStopsWithinTwoSeconds` (writer giả treo), `.leftoverPartsAreSweptOnlyByTheirSuffix`, `FileExportRunnerTests.fullDiskRemovesPartAndOffersRemaining`; ổ thật ở M |
| T13 | iCloud cuốn chiếu: ≤ 20 ảnh / 2 GB tải trước, tiến độ trong sheet (*Preparing*), ảnh hỏng nêu tên + Retry Failed chỉ tải lại ảnh đó | AC-9 | `RollingOriginalPrefetcherTests.neverMoreThan20Or2GBAhead`, `.failedPhotoGoesToSummary`, `.retryFetchesOnlyTheFailed`; sim `-ShotDexFakeICloud cloud=5,fail=2`, `scripts/file-export-icloud.json` |
| T14 | Đo bộ nhớ và thư mục tạm, không đổi hành vi | AC-13 | `FileExportMemoryTests.fiveHundredPeakIsFlat` (footprint 1 vs N ảnh 24 MP sinh lúc chạy, đếm file trong `ShotDexExport-*` mỗi bước); số ghi vào cột chứng minh |
| T15 | Export sheet → **connection đã lưu** (duyệt folder như FS-15.02 §2a, part + SHA + rename, **không** `ServerUploadRecord`); sheet xuất server: dòng đầu **Folder in Files…** trong Other Folder… dùng chung kho bookmark | AC-14 vế 2 | `FileExportRunnerTests.toAConnectionWritesNoUploadHistory` (store GRDB trong RAM: 0 dòng `server_uploads`), `ServerExportSizeTests.folderInFilesUsesTheSameRecents`; sim với folder cloud *On My iPhone › CloudTest* (FS-17.05) |
| T16 | Bố cục mọi thiết bị + chữ, cột chứng minh 07c, FS-15.02/FS-17.06 bỏ "chưa làm", `/verify FS-03.07c`, full suite **một lần** | AC-15 | ảnh + dump: iPhone 17 26.5, iPhone 16 18.6, iPad 13 (dọc + ngang, `Tools/sim-shot`), Duo trong 951×669, Duo ngoài 466×678 (x ≤ 382); design-parity mọi board |
| M | **Đo trên máy thật** (người dùng cầm máy, không chặn task sim): iPhone USB-C + SSD exFAT, APFS, FAT32 | cho AC-2, 11, 12 | biên bản vào spec §5 07c: ❓-1…❓-6 ở §7 |

Lý do thứ tự: T1 là dòng ⚠️ duy nhất và chạy trên sheet đã có, nên đi đầu. Không có AC nào ✅ trọn (AC-4 và AC-14
có phần đã khoá bằng test cũ), nên không có task "chỉ viết test". T3 dựng runner bằng chế độ chép byte vì đó là đường
ghi đơn giản nhất. Sau đó T4 nối sheet vào folder thật, T5 thêm render. AC-14 vế 2 (T15) cần runner có đích server.

## 6. Rủi ro

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| **Bookmark ổ ngoài** sau khi rút/cắm, sau khởi động lại: có mở lại được không, và lúc ổ đang rút thì `URL(resolvingBookmarkData:)` báo lỗi gì — phân biệt *Not connected* với *không còn* | cao | lưu kèm tên ổ + volume UUID; resolve hỏng mà volume đã lưu không có mặt → *Not connected*, giữ trong danh sách; đo ở M (❓-1) |
| Rút ổ giữa lúc ghi: lỗi I/O, mất file, hay `NSFileCoordinator` treo | cao | ghi trong hàng đợi riêng + watchdog 2 s: quá trần thì gọi là *disconnected* và bỏ lượt ghi đó; đo ở M (❓-2) |
| Chỗ trống của volume ngoài: `volumeAvailableCapacityForImportantUsage` có thể nil/0 trên exFAT | vừa | thử `volumeAvailableCapacityKey` rồi mới bỏ qua bước kiểm; đo ở M (❓-3) |
| FAT32 > 4 GB: `volumeMaximumFileSize` có trả trên iOS không | vừa | có thì kiểm trước từng file, không thì map lỗi `EFBIG`; đo ở M (❓-4) |
| Đọc resource PhotoKit theo khối rồi ghi thẳng vào URL security-scoped trên ổ ngoài; cỡ khối PhotoKit có ≤ 1 MB không | vừa | `requestData` → `FileHandle` trong khối ghi điều phối (không dùng `writeData(toFile:)` của PhotoKit ra ngoài sandbox); đo ở M (❓-5) |
| Probe của `OriginalFetching` đọc header ảnh, **video thì đọc trọn** vì không đo được cỡ | chắc chắn (hiện trạng) | probe video: chunk đầu tới = trên máy, huỷ ngay; lỗi `networkAccessRequired` = iCloud |
| Cancel ≤ 1 s khi đang render 24–48 MP: lượt render Core Image không huỷ giữa chừng | vừa | UI và runner dừng ngay, kết quả render bị bỏ, part bị xoá; đo thời gian render 48 MP trên sim, ghi số |
| Bộ nhớ: render đủ cỡ rồi mới resize (như Resize) — 48 MP RGBA8 ≈ 190 MB | vừa | một ảnh một lúc; nếu T14 vượt trần thì truyền `maximumDimension` của preset cho `render` (đổi chất lượng thu nhỏ → so pixel với Resize trước khi đổi) |
| Đĩa: tải cuốn chiếu 2 GB + render tạm cho đích server | thấp | cửa sổ có trần; một file render tạm mỗi lần; `TemporaryWorkspace` quét `ShotDexExport-` |
| Concurrency: runner actor + callback PhotoKit + khối điều phối chạy trên hàng đợi global + model `@MainActor` | vừa | mẫu của `FilesFolderClient.coordinated` và `OSAllocatedUnfairLock` (memory "assumeIsolated in a sync callback"); `swift-concurrency` duyệt |
| PhotoKit `.limited`: ảnh bị gỡ khỏi tập chọn giữa mẻ | thấp | fetch theo id ra nil → lỗi một ảnh *ShotDex can't read this photo anymore.*; test bằng nguồn giả |
| **Duo trong 669pt** và Duo ngoài 382pt: Form 4 section + footer dài | vừa | Name đẩy sang màn riêng (07c §1 mục 3); dump x ≤ 382; footer xuống dòng, không cắt |
| Dropbox/cloud không báo chỗ trống, nhận file rồi mới đồng bộ | chắc chắn | bỏ bước kiểm chỗ; file nằm trong folder của dịch vụ là xong (FS-17.05 §4) |
| Hai lối "Save to Files" (share sheet, Export) làm người dùng phân vân | vừa | `copy-consistency` + `ux-reviewer` sau T16 |
| **Hai phiên cùng sửa** sheet xuất server và `EditorBatchSaver.renderToFile` (FS-05.04 watermark) | cao | T1 làm sớm và commit nhỏ; seam stamp ở §4; `git commit -- <paths>`, không stash/checkout (memory "Two agents, one checkout") |
| Ảnh thử có mặt người | — | fixture sinh bằng ImageIO; ảnh thật kiểm bằng Vision trước (memory) |

**Không có rủi ro migration:** mọi thứ lưu trong UserDefaults (07b §9), không có bảng mới.

## 7. Quyết định (người dùng duyệt 2026-10-03)

Người dùng chấp nhận mọi đề nghị của plan.

| # | Chỗ | Quyết định | Đổi trong plan / spec |
|---|---|---|---|
| ⚠️-1 | AC-14: sheet xuất server hôm nay chỉ có Size ở Resize, built-in bỏ Original, mặc định 4K (`ServerExportModel.swift:89`); spec: mọi lần xuất không gộp, kể cả preset tự tạo, Original mặc định, Resize mặc định 2048 px | **tài liệu đúng, sửa code** | FS-03.07b §8 ghi rõ code hôm nay lệch và đã chốt sửa; FS-17.06 §5b ghi ngày chốt; task T1 |
| ⚠️-2 | Ngoài AC: `PhotoEditingService.compress` (Resize) đường ảnh có trên máy render **bản gốc + `.identity`** (`:544-560`, `:572`) — ảnh đã chỉnh trong ShotDex mất bản chỉnh | Export: **code mới làm đúng spec** (Edited = bản hiện hành), không dùng lại `compress`. Resize: **mục riêng trong `REVIEW_QUEUE.md`** (đã ghi lúc duyệt, mục *user-wishes wave 2 follow-ups*), không sửa ở đây | task T5; `REVIEW_QUEUE.md` |

Các ❓ dưới đây đều là phép đo máy thật: **đã chốt đo ở task M** (người dùng cầm máy, không chặn task sim); số đo
vào 07c §5, task nào cần số thì đọc từ đó.

**❓ chưa kết luận được** — đều là phép đo trên máy thật (task M). Sim chỉ có *On My iPhone*, không có ổ ngoài:

| # | Câu hỏi | Ảnh hưởng |
|---|---|---|
| ❓-1 | bookmark folder trên SSD exFAT/APFS: mở lại sau rút–cắm, sau khởi động lại máy? lúc rút thì resolve trả gì? | AC-2 (phần ổ thật), AC-11 *Not connected* |
| ❓-2 | rút ổ giữa lượt ghi: mã lỗi, có treo `NSFileCoordinator` không, mất bao lâu | AC-11 trần 2 s |
| ❓-3 | chỗ trống của volume ngoài đọc bằng khoá nào | AC-12 phần ổ thật |
| ❓-4 | `volumeMaximumFileSize` trên FAT32; lỗi khi ghi > 4 GB | dòng FAT32 của 07c §3 |
| ❓-5 | `requestData` của PhotoKit ghi thẳng ra ổ ngoài: cỡ khối, tốc độ, có cần chép qua thư mục tạm không | AC-7, AC-13 trên máy |
| ❓-6 | iCloud thật (PhotoKit) với cửa sổ 20 ảnh / 2 GB | AC-9 phần máy thật |

## 8. Phản biện

(điền sau khi chạy `challenger` trên plan này)

## 9. Cách chứng minh là xong

- **Test:** mọi test ở §5; full suite **một lần** ở T16 (memory "Full suite once per intent" — mỗi task chỉ chạy test liên quan).
- **Đọc file nhận được:** *On My iPhone › Exports* là `File Provider Storage` của sim (`simctl get_app_container … groups`),
  đọc bằng ImageIO (cỡ, GPS, Make/Model, ngày) + `shasum -a 256` so với resource gốc lấy từ `DCIM` của sim.
- **Ảnh phải chụp** (iPhone 17 26.5, iPhone 16 18.6, iPad 13 dọc + ngang qua `Tools/sim-shot`, Duo trong, Duo ngoài):
  ⋯ chọn nhiều + ⋯ Photo Detail có Export…; sheet Export ở Current Version và Unmodified Original (có/không ảnh đã
  chỉnh); menu Folder (gần đây + connection + Choose Folder…); hàng *Not connected*; màn File Name; alert Replace;
  sheet đang chạy (*Preparing / Converting / Writing*); tổng kết sạch, có lỗi, *12 skipped*, *disconnected*; alert
  thiếu chỗ; sheet xuất server với hàng Size (Edit, Paste Edits, Resize) và Folder in Files….
- **Design-parity:** `design-parity` + `Tools/design-board compare` trên từng board của T0 (xuất `project/` của canvas
  về `build/design/editor/project/` trước), ở mọi task UI (T1, T2, T4, T6, T8, T10, T12, T13, T16).
- **Tài liệu:** cột "Chứng minh bằng" của 07c (sửa ngay sau mỗi AC); 07c §5 thêm số đo của M; FS-15.02 §2 và FS-17.06
  §5b/§6 bỏ "chưa làm"; `DESIGN.md` §8 glyph `square.and.arrow.up.on.square`; tên board đã ghi ở FS-03.07b (cuối file).
- **Agent ở Deploy:**
  - `photokit-guard` — resource đọc, `.limited`, iCloud cuốn chiếu, probe video;
  - `swift-concurrency` — runner actor, khối điều phối, huỷ ≤ 1 s, watchdog;
  - `memory-leak` — một render một lúc, closure lưu trong runner/model;
  - `device-layout` + `duo-ux-review` — sheet trên Duo 669pt và 382pt;
  - `ios26-parity` — hàng và chữ giống nhau ở 26.5 và 18.6;
  - `design-parity` — mọi board;
  - `copy-consistency` + `ux-reviewer` — hai lối Save to Files, câu lỗi 07c §3;
  - `hig-components` — Form, menu Folder, alert Replace;
  - `localization` — số nhiều, ngày trong ví dụ, đơn vị byte.

  Không cần `data-migration` (không có bảng mới) và `extension-boundary` (kit không đổi), trừ khi FS-05.04 kéo
  watermark vào kit.
