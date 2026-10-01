# Kế hoạch — Bản gốc trên iCloud (FS-02.06)

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-02.06`](../02-functional-spec/FS-02-photo-detail/06-icloud-originals.md) — 18 AC |
| Intent | [2026-09-30-user-wishes-research](../_intents/2026-09-30-user-wishes-research.md) mục 1 |
| Ngày | 2026-10-01 |
| Trạng thái | **đã duyệt 2026-10-01** — 18 task (một AC một task) + 1 việc chuẩn bị của người dùng (P-1). Quyết định ở §9 |

## 1. Hiểu đúng chưa

Máy bật Optimize Storage thì trên máy thường chỉ có bản xem trước, còn bản gốc nằm trên iCloud. Spec này đòi ba thứ.

- **Biết đang cầm bản nào.** Viewer và filmstrip có glyph iCloud. Khi tải thì có vòng tiến độ không số. Editor
  một ảnh có thẻ ghi phần trăm.
- **Có pha chuẩn bị bản gốc cho mọi đường xuất/ghi** (Share ở mọi lối vào, Resize, Collage). Save All, Paste
  Edits từ lưới, % cho Combine và luật đủ pixel cho Copy/kéo thả để đợt sau (`REVIEW_QUEUE.md`). Pha này đi theo
  thứ tự: hỏi với mạng tắt → kiểm chỗ trống cả mẻ → tải về đĩa có tiến độ và Cancel → ảnh hỏng thì dừng, nêu
  tên, cho Continue N / Retry / Cancel. Chưa ghi và chưa xoá gì trước khi pha này xong.
- **"Đủ pixel" mới là bản gốc.** Không tin nhãn "bản cuối" của PhotoKit.

**Share chạy như Photos** ở mọi lối vào (viewer, lưới, chọn nhiều, menu ô, album): share sheet mở ngay với nguồn
dữ liệu lười, chưa tải gì; người dùng chọn đích rồi mới chạy pha chuẩn bị trong một modal nhỏ giữa màn
*Downloading from iCloud · 63% · 24 MB* + Cancel. Ghi lại metadata của FS-08.06 chạy sau khi tải, trong cùng modal.
Toolbar Library **không** có token tải (người dùng chốt 2026-10-01, Q3): thao tác không phải Share (Resize,
Collage, lưu hàng loạt) báo % ngay trong màn/modal xử lý có sẵn của chính nó.
Phần quyết định (đủ pixel, đếm, phần trăm, 350 ms, đứng im 15 s, chỗ trống, kết cục) là logic thuần, có test.
Phần PhotoKit đi sau một protocol nên thay bằng bản giả được.

## 2. Đối chiếu AC ↔ code

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 viewer: glyph iCloud ≤ 1 s, không tải **bản gốc** | ❌ (đường tải ✅) | Glyph chưa có: bảng thông tin chỉ có vòng/cam khi đang tải (`PhotoDetailScreen.swift:981-991`). Có sẵn đường hỏi mạng tắt: `loadLocalOriginal` `:2393` → `PhotoLibraryService.requestLocalOriginalScreenImage` `:704` (`isNetworkAccessAllowed = false`), nhưng không kiểm pixel và chạy cho cả trang hàng xóm. Trang đang hiện chạy `startDisplayUpgrade` với `allowNetwork: true` (`:2416-2425`) — **giữ nguyên** (Q1 = code đúng, như Photos) | probe trả `OriginalAvailability` (dùng luật AC-11) chỉ cho trang đang hiện, glyph + nhãn *Original in iCloud*; không đổi đường tải bản cỡ màn |
| AC-2 viewer: phóng → vòng đầy dần, VO đọc %, xong thì glyph mất | ❌ (vòng ✅) | Vòng 22pt xác định đã có (`ICloudDownloadRing` `:1214-1247`; phóng gọi `loadFullResolution` `:2543`). Vòng hiện cả khi tải bản cỡ màn (`:2421-2426`) — **đúng** theo Q1. Ở 0% vòng quay vô định (`:1229-1235`). VO chỉ đọc *Downloading from iCloud*, không có % (`:1035`). Bản gốc nhận về không kiểm pixel (`:2557-2559`) | thêm % vào nhãn VO; glyph tắt khi bản gốc đủ pixel |
| AC-3 editor: *Downloading from iCloud… N%*, Save tắt, nguồn 6000×4000 | ❌ (một phần ✅) | ✅ Save tắt khi đang nạp: `PhotoEditorScreen.swift:385`, `:3004`. ❌ thẻ: `EditorImageStage.swift:614-618` là `ProgressView` không %; chữ iCloud chỉ hiện khi bản fast-format rỗng (`PhotoEditorController.swift:813-821`). ❌ `requestContentEditingInput` không có `progressHandler` (`PhotoEditingService.swift:632-650`); `write(resource:)` cũng không có (`:729`). Không kiểm pixel nguồn | progress từ service → controller → thẻ có thanh xác định |
| AC-4 editor: Cancel ở 30% → đóng ≤ 1 s, huỷ tải, không còn `ShotDexPhoto-*` | ❌ | Continuation ở `:634-649` không có cancel handler (không gọi `cancelContentEditingInputRequest`). `writeData` (`:733`) không huỷ được. `beginSession` (`:132-138`) vẫn `remember` phiên sau khi `releaseCachedSessions()` đã chạy lúc `onDisappear` (`PhotoEditorScreen.swift:204-211`), nên thư mục tạm còn lại tới lần dọn lúc mở app (`TemporaryWorkspace.swift:20`) | huỷ thật (cancel ID / `requestData` huỷ được); phiên tạo xong sau khi huỷ thì xoá ngay, không cache |
| AC-5 editor offline: ≤ 15 s có câu báo + nút đóng | ❌ (một phần ✅) | ✅ phân loại lỗi mạng + alert + OK đóng editor: `EditorLoadFailure.swift:17-38`, `PhotoEditorScreen.swift:3708-3735`, test `EditorLoadFailureTests.networkFailuresReadAsICloud`. ❌ không có đồng hồ đứng im: PhotoKit treo thì vòng quay vô hạn | đồng hồ 15 s ở 0% → *iCloud isn't responding…* + Close, không huỷ lượt tải |
| AC-6 chọn 12 (3 iCloud) → Share: sheet mở ngay, 0 byte; chọn đích → modal %·MB + Cancel; đích nhận đủ 12 | ❌ | `LibraryScreen.swift:399-409` + `PhotoShareSheet.gather` `:15-30`: tải tuần tự **trước** khi mở sheet, không tiến độ, chỉ có spinner trên nút (`SelectionBarViews.swift:64-71`). Ảnh tải hỏng bị bỏ im lặng. **Giữ cả `Data` trong RAM** (`:107-117`), trái NF-02 / §8 "tải về đĩa". `present` (`:84-106`) nhận item đã có sẵn, không có nguồn lười | engine chuẩn bị + `OriginalDownloadModel` cấp app + nguồn item lười (file URL, tải khi đích xin) + modal giữa màn |
| AC-7 tắt mạng giữa chừng → modal nêu tên ảnh hỏng, Share 10 · Retry · Cancel | ❌ | `gather` bỏ ảnh hỏng không báo (`PhotoShareSheet.swift:22-26`) | kết cục §5 bước 4 trong modal; nguồn lười giữ callback mở tới khi người dùng chọn |
| AC-8 viewer Share ảnh iCloud → sheet mở ngay, chọn đích → modal, đích nhận 6000×4000 | ❌ | `shareImage` dùng `isNetworkAccessAllowed = false` (`PhotoDetailScreen.swift:1123-1136`) → alert *Unable to Share* chỉ có OK (`:2981-2985`) | viewer dùng cùng đường Share với lưới (modal giữa màn), bỏ alert |
| AC-9 Resize 5 (2 iCloud, offline), Continue with 3 → 3 bản, xoá 3, 2 còn nguyên | ❌ (bất biến xoá đã ✅) | Chưa có bước Continue: vòng `startExport` (`CompressionController.swift:177-227`) tải trong lúc xử lý và tự đi tiếp. Nhưng bất biến "chỉ xoá ảnh đã nén" đã đúng: `compressedOriginalIDs` chỉ thêm khi thành công (`:203-204`), `deleteOriginalsIfRequested` chỉ xoá những id đó (`:279-290`) | test bất biến viết trước khi đổi code; thêm hộp chọn |
| AC-10 Resize 20 iCloud, Cancel lúc tải ảnh 4 → 0 asset, 0 xoá, ≤ 1 s | ❌ | Hôm nay: 3 asset đã tạo rồi bị xoá ngược (`:219-220`, `:291-303`, xoá qua PhotoKit). Lượt tải đang bay không huỷ được nên modal chờ nó | huỷ trong pha chuẩn bị, trước mọi `createFlatAsset`; dòng *Downloading from iCloud · k of n · N%* + thanh trong modal xử lý của Resize |
| AC-11 kiểm đủ pixel (1536 bị loại; xoay 90° đạt; 1620/1619 @1800) | ❌ | Chỉ có hai bản private đo "cỡ màn" chứ không đo "bản gốc": `PhotoDetailScreen.swift:2500-2528`, `PhotoLibraryService.swift:866` | `Domain/ICloud/OriginalCompleteness` thuần + test |
| AC-12 Collage 4 ô, 1 iCloud offline → không lưu, báo + Retry | ❌ | `CollageEditorModel.export` `:643-688` bỏ qua ô hỏng, chỉ báo khi **mọi** ô hỏng (`:684-687`). `requestExportImage` `:801-815` không kiểm pixel | chuẩn bị ở cỡ ô trước khi dựng |
| AC-13 filmstrip: glyph iCloud → vòng khi preload, chạm → *Downloading… N%* | ❌ | `EditorFilmstripThumbnail` (`EditorSession.swift:298-360`) chỉ có `ProgressView` lúc tải **thumbnail**. `EditorPreviewPreloader` (`:33-49`) không báo gì | trạng thái theo ảnh (probe một lần mỗi run) + tiến độ preload |
| AC-14 thiếu chỗ (1,4 GB / 380 MB) → báo trước byte đầu, không tải | ❌ | Không đường xuất nào kiểm chỗ. Có sẵn `DiskSpace.availableBytes()` (`Core/Utils/DiskSpace.swift:15`, lý do E174.1 đã khai ở `PrivacyInfo.xcprivacy:23-27`) và `fileSize` đã index (`PhotoMetadata.fileSize`) | bước 2 của engine; `fileSize` chưa index → hỏi cỡ tài nguyên gốc qua PhotoKit cho ảnh của mẻ; vẫn không có → không tính, cho đi tiếp |
| AC-15 `.limited`, ảnh bị gỡ giữa chừng → *Can't Open This Photo* + Open Settings · Cancel, mọi nút đóng | ✅ | `EditorLoadFailure.classify` `:17-38` (`.noAccess`, kể cả `unavailable` khi `.limited`). Alert `PhotoEditorScreen.swift:3722-3731`: Open Settings → mở Settings rồi `close()`, Cancel → `close()`. Test: `permissionErrorsOfferSettings`, `anUnavailablePhotoUnderLimitedAccessIsTheSelection` | không sửa code; thêm test khoá tiêu đề/nút; chụp qua bản giả (task 2) |
| AC-17 lưới: không dấu iCloud, không hỏi tài nguyên theo ô | ✅ | `PhotoGridCell.applyStatusBadges` (`PhotoGridCollectionView.swift:2240-2260`) chỉ đọc `isFavorite`/`mediaSubtypes`, có chú thích cấm `PHAssetResource` theo ô. Không có `PHAssetResource`/`requestImageDataAndOrientation` trong file | test quét mã nguồn (mẫu `EditorStringsTests`) + dump `ui-drive` không có nhãn *Original in iCloud* |
| AC-16 Resize 5 iCloud, ảnh 5 hỏng → lúc alert: 0 asset, 0 xoá, 4 bản gốc trên đĩa | ❌ | Như AC-9/10: không có pha chuẩn bị. *"Preparing original…"* chỉ là preview ảnh đầu (`CompressionScreen.swift:35`, `CompressionController.load` `:118-140`) | pha chuẩn bị trước `startExport` |
| AC-18 Library index 40% + menu ô Share → sheet ngay, modal sau khi chọn đích, không token tải, token index giữ chỗ, 26.5 = 18.6 | ❌ | Token index ở `LibraryScreen.swift:1116-1126`, nhánh kính `:883-911`. Menu ô → `AssetActionsCoordinator.share` `:219-227` → `gather`, không có tiến độ | menu ô đi cùng đường Share của AC-6; engine giữ `IndexInteractionGate`; toolbar không thêm gì |

### Luật trong spec không có AC đi kèm

| Luật | Code hôm nay | Đề xuất |
|---|---|---|
| §3 lượt người dùng không xin suất index; pha chuẩn bị tự giới hạn ≤ 4 | `ExifReader.networkStreamLimiter` là `private static` (`ExifReader.swift:114`), chỉ index dùng — **giữ nguyên** (Q2 = code đúng) | engine có `AsyncLimiter(limit: 4)` riêng; BD-03.03 §1 và FS-02.06 §3 đã sửa 2026-10-01 |
| §3 *index tạm dừng trong lúc chuẩn bị* | có sẵn `IndexInteractionGate` (`beginInteraction`/`touch`/tự hết 90 s, `Domain/Indexing/IndexInteractionGate.swift`) | engine giữ một lượt trong suốt pha, `touch()` mỗi nhịp tiến độ |
| Save All, Paste Edits (lưới), Combine thêm %, Copy/kéo thả theo luật đủ pixel | `EditorBatchSaver.run` `:43-90` tải trong vòng lặp; `pasteEditsToSelection` `LibraryScreen.swift:298`; Combine có *couldn't be downloaded* + Retry (`PhotoStackScreen.swift:409`, `PanoramaMergeScreen.swift:229`); Copy `AssetActionsCoordinator.swift:195-211` | **để đợt sau** — bốn dòng ở `REVIEW_QUEUE.md` mục *user-wishes wave 1 follow-ups*; spec §2 đã ghi |
| §9 thao tác không phải Share báo % trong màn/modal xử lý của chính nó (không token tải, Q3) | Resize: *"Preparing original…"* không % (`CompressionScreen.swift:35`); Collage export không có tiến độ tải | Resize: AC-10 (task 17). Collage: dòng % trong modal export đi cùng task 18. Lưu hàng loạt: đợt sau (§2) |

## 3. Tái dùng

| Có sẵn | Dùng cho |
|---|---|
| `ICloudDownloadRing` (`PhotoDetailScreen.swift:1214`, đang `private`) | vòng viewer, filmstrip (AC-2, AC-13). Chuyển sang `Features/Shared/` |
| Modal tiến độ có sẵn của tầng D (Resize `CompressionScreen`, Collage export) | chỗ hiện dòng % tải của Resize/Collage (AC-10, task 18); kiểu cho modal Share giữa màn (AC-6, 7, 8, 14, 18) — dùng chung một view, không đẻ kiểu thứ ba |
| Phát hiện đứng im 15 s của viewer (`updateStallWatch` `PhotoDetailScreen.swift:453-472`) | luật đứng im ở editor và engine (AC-5). Chuyển thành hàm thuần trong Domain |
| `IndexInteractionGate` | tạm dừng index trong lúc chuẩn bị |
| `PhotoEditingService` (`beginSession`, `loadSource`, `EditingSessionCache`, `write(resource:)`, temp dir `ShotDexPhoto-`) | đường tải của editor, Resize, Save All (AC-3, 4, 9, 10, 16) |
| `EditorPreviewPreloader` / `EditorPreviewCache` | báo tiến độ preload theo ảnh (AC-13) |
| `PhotoShareSheet.present(items:onFinished:)` | mở sheet ngay với nguồn lười; xoá file đã chuẩn bị khi share sheet đóng (AC-6, 8) |
| `PhotoShareSheet.stripLocation` | giữ nguyên; chạy trên file đã chuẩn bị |
| `CompressionController` (`failures`, `deleteOriginals`, `cancelExport`) | pha chuẩn bị chèn trước vòng xử lý (AC-9, 10, 16) |
| `CollageEditorModel.export` (tải từng ô tuần tự ở cỡ ô × 1,5) | AC-12, giữ cách tải từng ô một |
| `EditorLoadFailure` | phân loại lỗi cho mọi đường (thêm `.stalled`, `.notEnoughSpace`) |
| `DiskSpace.availableBytes()` + `PhotoMetadata.fileSize` (+ cỡ tài nguyên PhotoKit khi chưa index) | AC-14 |
| `TemporaryWorkspace.prefixes` (dọn lúc mở app) | thêm tiền tố `ShotDexOriginals-` cho file của pha chuẩn bị |
| `AsyncLimiter` | giới hạn ≤ 4 lượt song song riêng của engine (Q2) |
| Launch arg DEBUG kiểu `-ShotDexStickyBanner` (`AppBanner.swift:39-52`), `-ShotDexImportFixtures` (`LookExchangeModel.swift:84-90`); `ui-drive` truyền được `arguments` (`UIDriverTests.swift:116`) | `-ShotDexFakeICloud <kịch bản>` để chụp mọi trạng thái trên simulator |
| `EditorStringsTests` (đọc nguồn qua `#filePath`) | test khoá AC-17 |

## 4. Chỗ nào trong code

| File | Đụng gì | Mới / sửa | Tầng |
|---|---|---|---|
| `Domain/ICloud/OriginalCompleteness.swift` | luật đủ pixel: bản gốc (có orientation), bản theo cỡ (≥ 90% của min(cỡ, cạnh dài)) | mới | Domain |
| `Domain/ICloud/OriginalPreparationState.swift` | trạng thái thuần của một mẻ: đếm k/n (ảnh đã có không tính), % trung bình theo ảnh, mốc 350 ms, đứng im 15 s, kiểm chỗ, kết cục (xong / hỏng + tên / thiếu chỗ / huỷ), chữ *Downloading from iCloud · 3 of 12 · 42%*, *2 of 12 photos couldn't…*, *Not enough space… needs 1.4 GB, 380 MB free.*; đồng hồ tiêm vào | mới | Domain |
| `Domain/Editing/EditorLoadFailure.swift` | thêm `.stalled`, `.notEnoughSpace` | sửa | Domain |
| `Data/Sources/OriginalFetcher.swift` | `protocol OriginalFetching` (`probe(asset) → OriginalAvailability`, `fetch(asset, to: URL, progress:) async throws`, huỷ được) + `PhotoKitOriginalFetcher` (`PHAssetResourceManager.requestData` ghi luồng vào `FileHandle`, `cancelDataRequest` khi huỷ; probe mạng tắt + đọc kích thước bằng `CGImageSource`, không giải mã) | mới | Data |
| `Data/Sources/OriginalPreparation.swift` | engine (actor): chạy §5 trên fetcher, giữ `IndexInteractionGate`, tự giới hạn ≤ 4 lượt song song (không xin suất index), thư mục `ShotDexOriginals-<uuid>`, kiểm đủ pixel lại lúc dùng; cỡ chưa index → hỏi `fileSize` tài nguyên | mới | Data |
| `Data/Sources/PhotoEditingService.swift` | `progressHandler` + huỷ cho `requestContentEditingInput` (`:632`) và `write(resource:)` (`:729`); `beginSession(…, progress:)`; không `remember` phiên đã bị huỷ (AC-4); kiểm đủ pixel nguồn | sửa | Data |
| `Data/Sources/PhotoLibraryService.swift` | `requestLocalOriginalScreenImage` (`:704`) trả thêm kích thước nguồn → `OriginalAvailability` | sửa | Data |
| `Core/Utils/TemporaryWorkspace.swift` | thêm tiền tố `ShotDexOriginals-` | sửa | Core |
| `App/OriginalDownloadModel.swift` | `@Observable` cấp app (trong `AppDependencies`): mẻ đang chạy, % và MB, modal Share mở/đóng, Continue/Retry/Cancel. Một chỗ cho modal ở mọi lối Share | mới | App |
| `App/AppDependencies.swift` | dựng fetcher (thật, hoặc giả khi DEBUG + `-ShotDexFakeICloud`), engine, model | sửa | App |
| `App/AssetActionsCoordinator.swift` | `share(ids:)` (`:219`) đi qua model | sửa | App |
| `App/SelectionBarModel.swift` | bỏ `isPreparingShare`; đọc model | sửa | App |
| `Features/Shared/OriginalDownloadModal.swift` | modal nhỏ giữa màn *Downloading from iCloud · 63% · 24 MB* + thanh + Cancel, kết cục §5 bước 4; canh giữa vùng an toàn của scene (Duo ngoài); `ICloudDownloadRing` chuyển về `Features/Shared/` | mới | Features |
| `Features/Shared/PhotoShareSheet.swift` | `gather` thành nguồn item lười (`NSItemProvider` / `UIActivityItemProvider` khai kiểu + xem trước trên máy, tải khi đích xin, trả file URL); xoá file khi sheet đóng | sửa | Features |
| `Features/Library/LibraryScreen.swift` | `shareSelected` (`:399`) mở sheet ngay; token index không đổi, không thêm token tải | sửa | Features |
| `Features/Library/SelectionBarViews.swift` | bỏ spinner trên nút Share (`:64-71`) | sửa | Features |
| `Features/Albums/{AlbumDetail,SmartAlbumDetail,OnThisDay}Screen.swift` | `shareSelected` → cùng đường Share | sửa | Features |
| `Features/Library/PhotoDetailScreen.swift` | glyph + nhãn VO có %, share qua cùng đường, bỏ alert *Unable to Share* | sửa | Features |
| `Features/Editing/PhotoEditorController.swift`, `EditorImageStage.swift` | thẻ *Downloading from iCloud… N%* + thanh; đồng hồ đứng im | sửa | Features |
| `Features/Editing/EditorSession.swift`, `EditorPreviewPreloader.swift` | glyph/vòng ô filmstrip; preload báo tiến độ theo ảnh | sửa | Features |
| `Features/Editing/CompressionController.swift`, `CompressionScreen.swift` | pha chuẩn bị trước `startExport`; hộp Continue/Retry/Cancel | sửa | Features |
| `Features/Collage/CollageEditorModel.swift`, `CollageExportScreen.swift` | chuẩn bị ở cỡ ô, kiểm đủ pixel, có ô hỏng thì không lưu | sửa | Features |
| `ShotDexTests/…` | `OriginalCompletenessTests`, `OriginalPreparationStateTests`, `OriginalPreparationTests` (fetcher giả), `EditorLoadFailureTests` (+), `CompressionPreparationTests`, `CollagePreparationTests`, `LazyShareItemTests`, `GridICloudFreeTests` | mới / sửa | Tests |
| `ShotDexUITests/scripts/icloud-*.json` | lộ trình chụp với `-ShotDexFakeICloud` | mới | UI driver |

Logic đếm/%/thời gian/kết cục nằm ở Domain. Engine và fetcher ở Data. View chỉ đọc model. Không có dữ liệu
người dùng tự nhập, không đụng DB (§7: trạng thái "đã có trên máy" **không lưu**).

**Seam để test không cần iCloud.** `OriginalFetching` có bản giả `FakeOriginalFetcher`, kịch bản hoá được:
có sẵn / tải với nhịp % / hỏng ở ảnh k / đứng im / lỗi quyền / lỗi hết chỗ. `CompressionController` và
`CollageEditorModel` nhận engine qua init (hôm nay nhận `PhotoEditingService` cụ thể), nên test chạy được.
Bản giả cũng nối vào app khi DEBUG + `-ShotDexFakeICloud`, để simulator vẽ đúng từng trạng thái mà chụp.

## 5. Thứ tự task

Việc chuẩn bị, không phải commit code:
- **P-1 (người dùng):** thêm glyph iCloud (`icloud`, `exclamationmark.icloud`) và modal tải của Share vào
  `DESIGN.md` §8 (spec §9: "người dùng tự sửa file đó"). Không có token tải (Q3). Chặn các task UI 4, 5, 9, 10, 13, 14.

Thứ tự theo luật là ✅ → ❌ (không còn ⚠️ sau khi duyệt). AC-11 lên trước AC-1/AC-2 vì hai AC đó cần luật đủ pixel.

| # | Task | AC | Test kèm theo |
|---|---|---|---|
| 1 | Khoá: lưới không hỏi tài nguyên theo ô | AC-17 | `GridICloudFreeTests.gridHasNoPerCellResourceQuery` (quét `PhotoGridCollectionView.swift`: không `PHAssetResource`, `requestImageDataAndOrientation`, `PHImageResultIsInCloudKey`, nhãn *Original in iCloud*) |
| 2 | Khoá: lỗi quyền → *Can't Open This Photo* + Open Settings · Cancel | AC-15 | `EditorLoadFailureTests.noAccessReadsCantOpenThisPhoto` + hai test có sẵn |
| 3 | `OriginalCompleteness` thuần | AC-11 | `OriginalCompletenessTests`: 1536×1024 "bản cuối" bị loại; 4000×6000 orientation 90° đạt; @1800: 1620 đạt, 1619 không |
| 4 | Viewer: probe trang đang hiện → glyph + nhãn VO; đường tải bản cỡ màn giữ nguyên | AC-1 | `OriginalAvailabilityTests` (probe giả: proxy có nhãn "bản cuối" → `.inCloud`); ui-drive giả: glyph ≤ 1 s, fetcher giả đếm **0 lượt tải bản gốc** |
| 5 | Viewer: vòng khi bản cỡ màn hoặc bản gốc đang tải, VO đọc %, glyph mất khi bản gốc về | AC-2 | `OriginalPreparationStateTests.accessibilityPercent`; ui-drive giả: 3 ảnh cách 2 s |
| 6 | Editor: tiến độ từ service, thẻ % + thanh, Save tắt, kiểm pixel nguồn | AC-3 | `EditorLoadProgressTests` (service với fetcher giả: nhịp % tới controller; nguồn thiếu pixel → chưa xong) |
| 7 | Editor: Cancel huỷ lượt tải ≤ 1 s, không còn `ShotDexPhoto-*` | AC-4 | `PhotoEditingServiceCancelTests` (huỷ ở 30% → fetcher giả nhận cancel; phiên tạo muộn bị xoá; quét `temporaryDirectory`) |
| 8 | Editor: đứng im 15 s / offline → câu báo + Close | AC-5 | `EditorLoadFailureTests.stallAfterFifteenSecondsAtZero` (đồng hồ tiêm) + test có sẵn |
| 9 | Filmstrip: glyph → vòng khi preload, chạm → thẻ % | AC-13 | `EditorPreviewPreloaderTests.reportsPerPhotoProgress`; ui-drive giả 5 ảnh |
| 10 | Engine (≤ 4 song song, giữ gate index) + `OriginalDownloadModel` + nguồn item lười + modal giữa màn; Share từ chọn nhiều mở sheet ngay | AC-6 | `LazyShareItemTests.sheetOpensWithZeroFetches` (fetcher giả đếm 0 trước khi đích xin), `OriginalPreparationTests` (12 ảnh, 3 iCloud: % trung bình, MB, modal ẩn < 350 ms, 12 file, file xoá khi sheet đóng, gate được giữ/nhả, ≤ 4 lượt cùng lúc) |
| 11 | Kết cục có ảnh hỏng trong modal: tên, Share 10 · Retry · Cancel | AC-7 | `OriginalPreparationTests.failuresHoldProvidersUntilChoice` (không nguồn nào trả file trước khi chọn), `.retryOnlyRefetchesFailures`, `.cancelDeliversNothing` |
| 12 | Kiểm chỗ trống cả mẻ trước byte đầu, sau khi chọn đích | AC-14 | `OriginalPreparationStateTests.notEnoughSpace` (1,4 GB / 380 MB, 0 lượt fetch); `.unknownSizeAsksResourceThenProceeds`; hết chỗ giữa chừng → lỗi chỗ trống, không phải iCloud |
| 13 | Menu ô Share (Library, album) cùng đường; toolbar không có token tải, token index giữ chỗ trong lúc tải | AC-18 | `OriginalPreparationTests.indexGateHeldDuringShare`; ui-drive giả trên 26.5 và 18.6 (token index còn, không có nhãn token tải trong dump, modal hiện) |
| 14 | Viewer Share cùng đường, bỏ *Unable to Share* | AC-8 | `LazyShareItemTests.viewerSharesPreparedOriginal` (fetcher giả 6000×4000) |
| 15 | Resize: pha chuẩn bị trước vòng xử lý | AC-16 | `CompressionPreparationTests.failureAlertBeforeAnyWrite` (0 tạo, 0 xoá, 4 file trên đĩa) |
| 16 | Resize: Continue with N (viết test bất biến xoá **trước** khi đổi code) | AC-9 | `CompressionPreparationTests.continueWithThreeDeletesOnlyThree` |
| 17 | Resize: dòng % tải + thanh trong modal xử lý; Cancel trong pha chuẩn bị | AC-10 | `CompressionPreparationTests.progressLineInProcessingModal` (fetcher giả: *k of 20 · N%*), `.cancelDuringDownloadCreatesNothing` (≤ 1 s với fetcher giả treo); ui-drive giả: modal Resize có dòng %, toolbar không có token tải |
| 18 | Collage: chuẩn bị ở cỡ ô, dòng % tải trong modal export (spec §9), không lưu khi có ô hỏng | AC-12 | `CollagePreparationTests` (1/4 hỏng → không `saveImage`, câu báo + Retry) |

Mỗi task một commit `feat(FS-02.06): AC-n …`. Build sau mỗi commit, chạy test của task đó; task đụng UI thì
chạy thêm `/screens`. Full suite chạy một lần khi xong intent.

## 6. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| **Simulator không có thư viện iCloud** | chắc chắn | Logic: test thuần + fetcher giả. Giao diện: `-ShotDexFakeICloud` + ui-drive chụp mọi trạng thái trên simulator. Hành vi PhotoKit thật: máy thật bật Optimize Storage (bảng §7) |
| PhotoKit: `writeData(for:toFile:)` không trả ID, nên **không huỷ được** | chắc chắn | đổi sang `requestData` + ghi luồng ra `FileHandle`, `cancelDataRequest` khi huỷ. `requestContentEditingInput` dùng `cancelContentEditingInputRequest` trong `withTaskCancellationHandler` |
| PhotoKit: mạng tắt vẫn trả bản xem trước gắn nhãn "bản cuối"; có máy lại trả `nil` | cao | probe đọc kích thước bằng `CGImageSource` (không giải mã), áp AC-11. Xử lý cả hai trường hợp. Đo trên máy thật |
| PhotoKit: hệ thống dọn lại bản gốc sau khi tải | thấp | đọc từ file của pha chuẩn bị (đã ở đĩa của app), kiểm đủ pixel lần nữa lúc dùng |
| PhotoKit: `fileSize` chưa index (dòng mới) → không có tổng để kiểm chỗ | trung bình | hỏi `fileSize` của `PHAssetResource` chỉ cho ảnh của mẻ; không có thì không tính và cho đi tiếp (Q đã chốt) |
| Nguồn item lười: có đích (Messages, AirDrop) xin dữ liệu ngay khi chọn và có thể hết giờ chờ lượt tải dài; preview của sheet cần ảnh trên máy | cao | task 10 đo trên máy thật với Files, Messages, AirDrop; preview lấy thumbnail local; đích nào hỏng thì ghi spec §11 |
| PhotoKit: progress handler gọi trên hàng đợi bất kỳ, có thể sau completion | cao | về main bằng `Task { @MainActor }`. Continuation resume đúng một lần (cờ trong lock, như mẫu `OSAllocatedUnfairLock` ở memory) |
| Concurrency: engine sống lâu hơn màn (Share từ lưới rồi rời tab) | trung bình | engine thuộc `OriginalDownloadModel` cấp app; modal Share chặn màn nên không rời được giữa chừng; Cancel huỷ và trả lỗi huỷ cho mọi nguồn lười. Tầng D: engine thuộc modal, đóng modal là huỷ |
| Concurrency: `IndexInteractionGate` rò lượt | trung bình | `begin` / `end` trong `defer` của engine. Gate tự hết sau 90 s |
| Concurrency: phiên editor tạo xong sau khi editor đóng (lỗi AC-4 hôm nay) | đã xảy ra | `beginSession` kiểm `Task.isCancelled` như `preloadSession` (`:154-158`), xoá thư mục tạm |
| Bộ nhớ: share hôm nay giữ `Data` trong RAM (1,4 GB = jetsam) | cao | share bằng file URL; Collage giữ cách tải từng ô một; editor nhiều ảnh vẫn đi từng ảnh một (NF-02 §2) |
| Đĩa: cả mẻ gốc nằm trên đĩa cùng lúc | chắc chắn (spec chấp nhận) | kiểm trước (AC-14), xoá khi share sheet đóng / modal xong; dọn `ShotDexOriginals-` lúc mở app |
| Thiết bị: Duo ngoài, modal Share bị dải 84pt bên phải che | trung bình | modal canh giữa vùng an toàn của scene. Chụp bằng `Tools/sim-shot … cover` |
| Thiết bị: Duo trong 669pt, modal Resize/Collage thêm danh sách tên ảnh hỏng | trung bình | danh sách cuộn được, tối đa ~5 dòng rồi *and N more* |
| iOS 26 vs trước 26: modal và share sheet | trung bình | modal không phải kính, cùng view ở hai nhánh. Cancel/Retry/Continue giống nhau ở hai nhánh (spec §8) |
| Chung checkout: plan FS-08.06 (riêng tư khi chia sẻ) cũng sửa `PhotoShareSheet.gather` | cao | thống nhất trước: nguồn lười tải về file đã chuẩn bị, rồi FS-08.06 ghi lại metadata trên file đó **trong cùng pha modal**. FS-08.06 task 10 (AC-11 Cancel) dùng modal của task 10 ở đây; ai làm trước dựng modal. Ai commit sau thì rebase |
| Hiệu năng: probe filmstrip cho run dài | thấp | probe mạng tắt một lần mỗi ảnh mỗi run, lười theo ô đang hiện, không bao giờ cho lưới (AC-17) |

## 7. Phản biện (điền sau khi chạy `challenger`)

| Phản đối | Trả lời / thay đổi |
|---|---|
| *chưa chạy* | |

## 8. Cách chứng minh là xong

- **Test (simulator):** các test ở bảng §5. Luật đủ pixel, đếm, %, 350 ms, 15 s, chỗ trống, kết cục, huỷ và
  dọn thư mục đều chứng minh được bằng fetcher giả.
- **Chụp trên simulator, qua `-ShotDexFakeICloud`:** AC-1, 2, 3, 5, 6, 7, 8, 10, 12, 13, 14, 15, 16, 18 (share sheet
  mở ngay, rồi modal sau khi chọn Save to Files; dòng % trong modal Resize). Chụp trên
  iPhone 402×874, iPad 1376×1032, Duo trong 951×669 và Duo ngoài 466×678 (`Tools/sim-shot`), cả iOS 26.5 và 18.6.
  AC-17 chứng minh trọn trên simulator: test quét nguồn + dump `ui-drive` không có nhãn *Original in iCloud*.
- **Chỉ máy thật (Optimize Storage bật) mới chứng minh được:**
  - PhotoKit thật trả bản xem trước "bản cuối" (tiền đề của AC-11, AC-1);
  - glyph ≤ 1 s, 0 byte (AC-1); vòng thật đầy dần (AC-2);
  - nguồn editor đúng 6000×4000 (AC-3) và viewer share 6000×4000 (AC-8);
  - huỷ thật một lượt tải PhotoKit ≤ 1 s (AC-4, AC-10);
  - thời gian Airplane Mode ≤ 15 s (AC-5);
  - mã lỗi khi ảnh bị gỡ khỏi tập chọn giữa chừng (AC-15);
  - tắt mạng giữa mẻ (AC-7, AC-9, AC-16);
  - Settings đã tắt dữ liệu di động cho Photos (§11);
  - đích thật của share sheet nhận bản gốc qua nguồn lười (Files, Messages, AirDrop).

  `/verify` ghi các dòng này là **chưa chứng minh** cho tới khi có ảnh chụp từ máy thật.
- **Tài liệu phải cập nhật cùng task:**
  - cột "Chứng minh bằng" của FS-02.06;
  - FS-02.04 §3 (bỏ *Unable to Share*, Share như Photos) — task 14;
  - FS-02.06 §11 (đích share đo trên máy thật);
  - đã sửa lúc duyệt 2026-10-01: FS-02.06 (§2, §3, §4, §5, §9, AC-1/2/6/7/8/14/18), FS-02.01 §1 và §4 (Q1),
    BD-03.03 §1 (Q2);
  - đã sửa sau duyệt 2026-10-01 (Q3, bỏ token tải): FS-02.06 §4, §5, §9, §11, AC-10, AC-18.
- **Agent ở giai đoạn Deploy:**
  - `photokit-guard`: probe mạng tắt, `requestData` huỷ được, `.limited`, dọn bản gốc;
  - `swift-concurrency`: engine actor, continuation, cancel handler, gate;
  - `memory-leak`: share bằng file thay vì `Data`, engine/closure giữ `self`;
  - `device-layout`: modal Share giữa màn và dải 84pt, modal Resize/Collage trên 669pt;
  - `ios26-parity`: share sheet + modal ở hai nhánh.

  Thêm ngoài danh sách chuẩn:
  - `a11y-voiceover`: VO đọc % ở vòng không số, nhãn *Original in iCloud*;
  - `perf-profiler`: AC-17, probe filmstrip.

  Không cần `data-migration` (không ghi DB) và `extension-boundary` (không đụng kit/extension).

## 9. Quyết định (người dùng duyệt 2026-10-01)

| # | Câu hỏi | Quyết định | Đổi trong plan / spec |
|---|---|---|---|
| Q1 | viewer tải bản cỡ màn qua mạng khi chưa phóng? | **code đúng** (như Photos) | AC-1 = "không tải **bản gốc** trước khi phóng"; §4 vòng hiện khi bản cỡ màn hoặc bản gốc đang tải; FS-02.01 §1, §4 sửa; task 4, 5 |
| Q2 | 4 suất chung toàn app? | **code đúng** — lượt người dùng tự giới hạn ≤ 4 song song, dựa vào cổng tạm dừng index | BD-03.03 §1, FS-02.06 §3 sửa; engine có limiter riêng (task 10) |
| Q3 | token tải ở toolbar Library cho thao tác không phải Share? | **không có token** (người dùng chốt 2026-10-01). Resize, Collage, lưu hàng loạt báo % trong màn/modal xử lý có sẵn của chính nó; Share giữ modal giữa màn sau khi chọn đích | spec §4, §5, §9, §11, AC-10, AC-18; task 4 bỏ bước đo nav bar, task 13, 17, 18 sửa; P-1 bỏ token |
| ❓1 | nav bar lớp phủ chọn có vừa token? | ~~đo ở bước 0 của task 4~~ — **bỏ 2026-10-01**: không còn token (Q3) | P-2 bỏ; bước đo bỏ khỏi task 4 |
| ❓2, ❓3 | chỗ báo tiến độ khi Share từ viewer / album / menu ô | **luật mới "như iOS"**: share sheet mở ngay, chưa tải gì; chọn đích → modal nhỏ giữa màn *Downloading from iCloud · 63% · 24 MB* + Cancel tới khi bản gốc sẵn sàng (nguồn lười); ghi lại metadata FS-08.06 chạy sau khi tải trong cùng modal; bỏ hẳn *Unable to Share*. Thao tác không phải Share: xem Q3 | spec §4, §5, §6, §9, AC-6/7/8/14/18 viết lại; task 10–14 đổi |
| ❓4 | kiểm chỗ khi `fileSize` chưa index | hỏi PhotoKit cỡ tài nguyên; không có thì cho đi tiếp | spec §5 bước 2; task 12 |
| ❓5 | Save All, Paste Edits lưới, % Combine, luật đủ pixel Copy/kéo | **để đợt sau** | bốn dòng ở `REVIEW_QUEUE.md`; spec §2 |
| ❓6 | dòng Tiến độ của intent | đã ghi 2026-10-01 | — |

## 10. Còn lại sau khi duyệt

- ~~Token tải chưa có AC nào dùng.~~ **Xong 2026-10-01 (Q3):** không có token tải; thao tác không phải Share báo
  % trong màn/modal xử lý của chính nó (Resize: AC-10, Collage: task 18, lưu hàng loạt: đợt sau). Không còn việc mở.
