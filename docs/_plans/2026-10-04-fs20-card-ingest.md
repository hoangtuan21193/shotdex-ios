# Kế hoạch — Nhập từ thẻ nhớ (FS-20)

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-20`](../02-functional-spec/FS-20-card-ingest/README.md) · [27 AC](../02-functional-spec/FS-20-card-ingest/01-acceptance-criteria.md) + AC-28 Pause/Resume (thêm ở task 28) — mọi thiết bị |
| Intent | [macos-app](../_intents/2026-10-04-macos-app.md) (D8) · [ipad-mac-style](../_intents/2026-10-04-ipad-mac-style.md) |
| Quyết định | `.planboard/macos-app/SPEC-DECISIONS.md` mục FS-20 + "Planboard mac-ipad-v2" + `DECISIONS.md` D3–D8 · [mac-ipad-v2](../../.planboard/mac-ipad-v2/DECISIONS.md) — **không mở lại** |
| Design | `MAC_Ingest`, `MAC_IngestProgress` · `IP_Ingest`, `IPP_Ingest` (dọc) · `PH_Ingest`, `PH_IngestProgress` · `DI_Ingest`, `DI_IngestProgress`, `DC_Ingest` — **đã vẽ cả**, README FS-20 còn ghi "chưa vẽ" (sửa ở task 13) |
| Bảng AC ↔ code | [`2026-10-04-fs20-card-ingest-ac-table.md`](2026-10-04-fs20-card-ingest-ac-table.md) — ✅ 0 · ⚠️ 1 · ❌ 25 · ❓ 1 |
| Ngày | 2026-10-04 |
| Trạng thái | **đã duyệt 2026-10-04** (planboard mac-ipad-v2); 28 task = 28 commit |

## 1. Hiểu đúng chưa

Cắm thẻ (đầu đọc hoặc máy ảnh USB) → một hàng thẻ trong nhóm Sources; chạm mới mở màn **Import from Card** thay chỗ
lưới. Màn liệt kê ô theo ngày (cũ trước), ô mới tick sẵn, ô đã nhập (theo lịch sử tên gốc + byte + giờ chụp, hash nền
tinh chỉnh) không chọn được. Inspector chọn đích là một **nguồn thư mục FS-19** (hoặc New Folder… thành nguồn mới), mẫu
thư mục Year/Date, mẫu tên dùng **bộ 8 token chung với Export**, preset metadata, backup tuỳ chọn, Eject. Chép **một file
một lúc, khối ≤ 1 MB**, vào `.shotdex-part`, đọc lại so SHA-256 với bản trên thẻ, rồi đổi tên; ghi `.xmp`; đăng ký vào
nguồn ngay (lưới cập nhật giữa mẻ); rồi backup cùng cách. Không bao giờ ghi đè; lỗi đích/thẻ dừng mẻ, lỗi một file chạy
tiếp; có lỗi là không nhả thẻ. Photos không đổi. iOS 26 ra nền chạy tiếp; trước 26 dừng như Stop.

Không lệch đặc tả, trừ hai chỗ đặc tả tự mâu thuẫn với FS-19 / board (mục 6, Q4–Q5 — đã chốt).

## 2. Phụ thuộc (đọc trước khi xếp lịch)

Thứ tự chung: **FS-19 → FS-20 → (FS-01.08c độc lập) → FS-21 → FS-18.**

| FS-20 cần | Ai làm | Task FS-20 chờ |
|---|---|---|
| Bảng Nguồn + bookmark đọc-ghi; tạo nguồn từ một thư mục ("New Folder…") | FS-19.01 / 05 | 13 (popup Destination), 17, 25 |
| Bảng Bản sao + **lệnh đăng ký một file vừa chép** (không chờ watcher) | FS-19.05 | 17, 21, 25 |
| Bộ băm nội dung FS-19 (phần ảnh, có tên thuật toán) đọc được theo **luồng khối** | FS-19.02 §1 | 18 |
| Bộ ghi sidecar `.xmp` (Creator, Copyright, Keywords, ngày) + công tắc XMP | FS-19.02 §5 | 20, 21 |
| Watcher của nguồn **bỏ qua `*.shotdex-part`** và không đăng ký lại file nhập vừa đăng ký | FS-19.01 §2 (hôm nay chỉ bỏ file bắt đầu bằng `.`) | 25 — ghi vào plan FS-19 |
| Dọn mồ côi 30 ngày **trừ** `card_imports` (FS-19.05 §5, test 4) | FS-19.05 | 13 (bảng phải có trước test của FS-19) |
| Nhóm **Sources**: iPhone/Duo ở Collections › Sources (board `PH_Ingest` ghi rõ) | FS-19 (board PH_/DI_/DC_) | 23 |
| Sidebar iPad + chân sidebar tiến độ + inspector→sheet < 1100 (FS-21 AC-23) | FS-21 | 23 (phần iPad), 25 (phần iPad) |
| Target Mac, panel **Window › Activity** (⌥⌘0), sandbox | FS-18 | 23, 25 phần Mac — chứng minh trên Mac để FS-18 |
| Bộ chạy nền iOS 26 | FS-15.02b (spec, **chưa có code** — E11) | 26 — xem K5 |

**Làm được ngay, không chờ ai:** task 1–12 (Domain + Data thuần, thẻ giả = thư mục `DCIM` trong thư mục tạm, đích =
thư mục tạm, đăng ký nguồn qua seam rỗng). Task 1 còn chờ phiên đang sửa Export (file `Domain/FileExport/*`,
`Features/FileExport/*` đổi lúc 14:xx hôm nay) commit xong — luật 07-spec-deltas.

## 3. Tái dùng — cấm làm cách thứ hai

| Cần | Dùng lại | Ghi chú |
|---|---|---|
| Tên cả mẻ, Keep Both, Date Folders | `FileExportPlan.make` (E1), `FileNameTemplate` (E2), `ServerUploadPath.dayFolder/nextFreeName/partSuffix` | Import truyền `.unmodifiedOriginal` + `.keepBoth`; mục `FileExportItem` dựng từ ô thẻ (id = đường dẫn tương đối trên thẻ, role `.photo/.alternatePhoto/.video/.audio` đã có ở `FileExportPlan.swift:5-26`) |
| Part → rename, dọn part, watchdog rút ổ, phân loại lỗi đích | `LocalFolderWriter` (E3), `FileExportFailure.classify` (E6) | thêm bước verify — K2 |
| SHA-256 khối 1 MB | `FileChecksum` (E5) | băm **trong lúc** chép, không đọc thẻ hai lần |
| Kiểm chỗ trước byte đầu | `FileExportSpaceEstimate.check` (E12) | |
| ETA, `about 4 min` | `TransferRateEstimate` (`Domain/Shared/TransferRateEstimate.swift:6`) | mỗi file đếm hai lần (chép + đọc lại) như FS-15 `ServerUploadSession.swift:65-67` |
| Ghép RAW+JPEG, đuôi RAW, đuôi ảnh hệ thống đọc được | `ServerFolderListing.isRAW/imageExtensions/renderedTwinExtensions` (E8), `FileTypeBadge` | `CardCatalog` mở rộng luật (WAV, video, bỏ THM) chứ không chép lại |
| Thumbnail + ngày từ đầu file | `EmbeddedPreview` (E9), `RemoteThumbnailer` | tách seam nhỏ `HeadReading` (readRange) để thẻ dùng được — `RemoteThumbnailer` hôm nay đòi `any RemoteFileClient` |
| Camera/lens của thẻ | `ExifReader.parse(properties:)` (`Data/Sources/ExifReader.swift:742`), `CameraNormalizer.normalizeModel` (`Domain/Normalize/CameraNormalizer.swift:45`) | đầu màn `Canon EOS R6 Mark II` |
| Nơi chụp cho nhóm ngày | `PlaceStore.cachedCell` (`Data/Database/PlaceStore.swift:135`) | K6: chỉ cache, không mạng |
| Bookmark thẻ, *Not connected* | khuôn `ExportFolderStore` (E10) | `CardBookmarkStore` cùng hình, khoá UserDefaults riêng |
| Ô thẻ | `ServerPhotoCell` (`Features/ServerImport/ServerBrowserScreen.swift:889`) | tách ô chung; ô tick góc **trên-trái** theo board — `component-consistency` xem hai chỗ |
| Lưới chip token | `FileNameScreen.swift:53-68` | tách `FileNameTokenGrid` dùng cho Export và Import (AC-25) |
| Ô Keywords | `KeywordTokenField` (`Features/Library/CaptionKeywords/`), `AutocompleteTokenField` | |
| Giữ màn sáng trước 26 | `ScreenAwakeCoordinator` | |
| Banner `Imported 811 photos…` | `AppBannerModel` (`App/AppBanner.swift:7`) | |
| Lịch sử (khuôn bảng + store) | `server_downloads` (`AppDatabase.swift:490-503`), `ServerDownloadStore` | bảng riêng, không FK cascade |

## 4. Chỗ nào trong code

| Tầng | File | Đụng gì | Mới / sửa |
|---|---|---|---|
| Domain | `Domain/FileExport/FileNameTemplate.swift`, `ExportCopy.swift` | 8 token: `original`, `originalNumber`, `date`, `time`, `camera`, `lens`, `sequence`, `text`; nhãn chip; tên mẫu dựng sẵn | sửa (task 1) |
| Domain | `Domain/Ingest/CardCatalog.swift` | danh mục thẻ → `CardItem` (ghép cặp, WAV, video, bỏ THM/MISC/ẩn), nhóm ngày | mới |
| Domain | `Domain/Ingest/IngestStatus.swift` | New/Imported từ lịch sử + bản sao đích + hash nền; thu gọn ngày | mới |
| Domain | `Domain/Ingest/IngestPlan.swift` | bọc `FileExportPlan` (Keep Both cứng, Folders Year/Date), backup cùng tên | mới |
| Domain | `Domain/Ingest/IngestRunner.swift` (actor) | copy → verify → `.xmp` → đăng ký → lịch sử → backup; sự kiện Copy/Verify/Backup; Stop; Retry Failed; Import/Back Up Remaining | mới |
| Domain | `Domain/Ingest/IngestFailure.swift`, `IngestReadiness.swift`, `IngestProgress.swift`, `IngestSummary.swift`, `IngestCopy.swift` (bảng chuỗi `Ingest`) | lý do mờ nút, tiến độ, tổng kết, mọi câu §7–§8 | mới |
| Domain | `Domain/Ingest/IngestSettings.swift` | đích, backup, Folders, mẫu tên, preset metadata (có tên), Eject — giải mã khoan dung như `FileExportSettings` | mới |
| Data | `Data/Sources/FileExport/ExportDestinationWriter.swift` | verify tuỳ chọn trước rename (K2) | sửa |
| Data | `Data/Sources/Ingest/CardReader.swift` | protocol: `list()`, `readRange`, `stream(path, chunk:)`, `freeAndUsed`, `eject()`; `VolumeCardReader` (FileHandle, security-scoped) · `CameraCardReader` (ImageCaptureCore `requestReadData`) | mới |
| Data | `Data/Sources/Ingest/CardBrowser.swift` (`@Observable`, `@MainActor`) | `ICDeviceBrowser` + theo dõi bookmark (K4) → danh sách thẻ đang cắm | mới |
| Data | `Data/Sources/Ingest/CardBookmarkStore.swift`, `IngestSettingsStore.swift` | UserDefaults | mới |
| Data | `Data/Sources/Ingest/CardHashPass.swift` | hash nền SHA-256 + hash FS-19 trong một lượt đọc | mới |
| Data | `Data/Database/AppDatabase.swift` | migration `vNN-cardImports` **sau** migration của FS-19 | sửa |
| Data | `Data/Database/CardImportStore.swift` | ghi một dòng mỗi file kiểm xong; `match`, `rows(for card)` | mới |
| App | `App/ContinuedProcessingRun.swift` | `BGContinuedProcessingTask` iOS 26, dùng chung FS-15.02b (K5) | mới |
| App | `Info.plist` | id tác vụ chạy tiếp trong `BGTaskSchedulerPermittedIdentifiers` (`:5`); chuỗi quyền ImageCaptureCore nếu cần (R7) | sửa |
| Features | `Features/Ingest/IngestModel.swift`, `IngestScreen.swift`, `IngestInspector.swift`, `IngestTile.swift`, `IngestProgressPanel.swift`, `CardSourceRow.swift` | màn, inspector/sheet, tiến độ, hàng thẻ | mới |
| Features | `Features/FileExport/FileNameScreen.swift` | dùng `FileNameTokenGrid`, 8 chip | sửa (task 1) |
| Tests | `ShotDexTests/Ingest*Tests.swift`, `CardImportStoreTests`, sửa `FileNameTemplateTests`, `FileExportPlanTests` | thẻ giả = thư mục `DCIM`; reader giả ném lỗi ở byte N, trả byte khác khi đọc lại | mới / sửa |

Logic không nằm trong View: `IngestModel` chỉ nối `IngestRunner`/`IngestStatus`/`IngestReadiness` với màn.
Lịch sử nhập là dữ liệu người dùng không đọc lại được → **bảng riêng** `card_imports` (BD-02), không cột nào ở
`photo_metadata`.

`card_imports`: `id` · `cardId` (volume UUID, hoặc id thiết bị ICC) · `cardName` · `originalPath` (tương đối trên thẻ) ·
`originalName` · `byteCount` · `capturedAt` (K6) · `sha256` (cả file) · `sourceId` · `destinationPath` (tương đối trong
nguồn) · `photoId` (FS-19, có thể trống) · `backupPath` (trống tới khi backup kiểm xong — K7) · `importedAt`.
Chỉ mục (`originalName`, `byteCount`, `capturedAt`) và (`sourceId`, `destinationPath`). Không FK cascade.

## 5. Thứ tự task

✅ không có. ⚠️ trước (task 1), rồi ❌ theo phụ thuộc. Mỗi task một commit `feat(FS-20): AC-n …`, build sau mỗi commit,
đụng UI thì `/screens`. Test của task chạy riêng; full suite một lần khi xong intent.

| # | Task | AC | Test kèm theo |
|---|---|---|---|
| 1 | **Bộ token chung**: thêm `originalNumber` (chữ số cuối tên gốc, `IMG_6123`→`6123`, không có → bỏ token), `text`, đổi `seq`→`sequence` (chuỗi lưu đổi luôn, app chưa phát hành); chip **Sequence**; mẫu "Date + Camera + Sequence"; `FileNameTokenGrid` dùng chung. Sửa FS-03.07b §5 + 07c (dòng delta FS-18 §3 "FS-03.07b §5, 07c") cùng commit | AC-25 | `FileNameTemplateTests.originalNumberTakesTrailingDigits`, `.sequenceKeepsWidth`; `FileNameTokenGridTests.eightChipsSameWords` (đọc danh sách chip của Export **và** Import từ một nguồn); dump màn File Name |
| 2 | `CardCatalog`: cặp CR3+JPG/HIF = 1 ô, theo (thư mục con, tên gốc) | AC-6 | `CardCatalogTests.pairIsOneTile`, `.sameNameInTwoDCIMFoldersIsTwoTiles` |
| 3 | `CardCatalog`: WAV theo ô ảnh, MP4/MOV ô riêng có thời lượng, bỏ THM/MISC/ẩn/danh mục | AC-23 | `CardCatalogTests.wavJoinsPhoto`, `.thmAndMiscSkipped` + chạy mẻ giả: 0 `.THM` ở đích |
| 4 | `IngestPlan` + `IngestRunner` + verify trong writer: thẻ giả → `RAW/2026/2026-10-03/2026-10-03_Kyoto_6123.CR3`, SHA = thẻ | AC-4 | `IngestRunnerTests.copiesVerifiedWithTemplate` |
| 5 | Keep Both cứng | AC-7 | `IngestPlanTests.neverOverwritesKeepBothCaseInsensitive` (`…_0001.cr3` có sẵn → `(2)`, `(3)`; SHA file cũ không đổi) |
| 6 | SHA lệch: chép lại 1 lần, còn lệch → lỗi một file, part xoá, Retry Failed, cờ không nhả | AC-13 | `IngestRunnerTests.mismatchRetriesOnceThenFails` (reader giả lệch 2 lần ở ảnh 5/10) |
| 7 | Đích đầy dừng mẻ, xoá part, câu §8 | AC-12 | `IngestRunnerTests.destinationFullStops` (writer giả ENOSPC ở ảnh 412) |
| 8 | Thẻ rút: dừng ≤ 2 s, 0 part, Import Remaining | AC-10 | `IngestRunnerTests.cardDisconnectStopsWithinTwoSeconds` (reader treo/ENXIO ở ảnh 412) |
| 9 | Stop Import… dừng ≤ 1 s giữa khối, xoá part, không nhả | AC-14 | `IngestRunnerTests.stopWithinASecondMidFile` |
| 10 | `IngestReadiness`: thiếu chỗ → footer, nút mờ, 0 file | AC-11 | `IngestReadinessTests.notEnoughSpaceDimsImport` |
| 11 | Backup bật mà ổ không cắm → *Not connected*, footer nêu tên ổ, nút mờ | AC-8 | `IngestReadinessTests.backupDriveMissingDims` |
| 12 | Backup rút giữa mẻ: bản chính chạy hết, không nhả, *Backup incomplete — 357 of 811.*, Back Up Remaining chạy 454 | AC-9 | `IngestRunnerTests.backupDisconnectKeepsPrimaryRunning`, `.backUpRemainingCopiesTheRest` |
| — | **chờ FS-19** (schema, đăng ký file, sidecar, Sources group) | | |
| 13 | Bảng `card_imports` + `CardImportStore` + `IngestStatus` + `IngestScreen` (header, segmented New mặc định, lưới, inspector/sheet theo `IP_Ingest`/`IPP_Ingest`/`PH_Ingest`) · BD-02 (dòng delta FS-18 §2 "lịch sử nhập thẻ") · README FS-20 bỏ "chưa vẽ" · dòng FS-18 §5 board Ingest đánh dấu xong | AC-1 | `CardImportStoreTests.migrationShape`, `IngestStatusTests.historyMarksImported` (1.046/234); `design-parity` `IP_Ingest` |
| 14 | Tick/bỏ tick, tổng GB theo mọi file của ô | AC-2 | `IngestSelectionTests.untickHIFDropsBytes` |
| 15 | Ngày đủ Imported thu gọn một dòng | AC-3 | `IngestStatusTests.fullyImportedDayCollapses` |
| 16 | Thẻ đã nhập hết: *0 new photos* + câu rỗng + Show All | AC-16 | `IngestStatusTests.everythingImported`; ảnh màn rỗng |
| 17 | Ảnh đã nhập mà bản sao đích mất → New, tick | AC-21 | `IngestStatusTests.deletedAtDestinationIsNewAgain` (dùng bảng Bản sao FS-19; đích offline = vẫn Imported — Q2) |
| 18 | Hash nền tinh chỉnh (lịch sử khớp, hash khác → New; không lịch sử, hash trùng nguồn → Imported) | AC-22 | `CardHashPassTests.historyMatchButContentDiffers`, `.hashMatchesSourceWithoutHistory` |
| 19 | Mỗi file kiểm xong ghi lịch sử ngay → mở lại thấy 200 Imported, New 612 | AC-15 | `IngestRunnerTests.historyWrittenPerFile` |
| 20 | `.xmp` mang Creator/Copyright/Keywords/ngày; SHA ảnh không đổi | AC-5 | `IngestRunnerTests.writesSidecarWithPreset` |
| 21 | Công tắc XMP tắt vẫn ghi cho mẻ, 0 `.xmp` cho ảnh khác | AC-24 | `IngestRunnerTests.sidecarIgnoresGlobalSwitch` |
| 22 | Mọi bản kiểm xong → nhả (theo Q3), banner, 811 dòng lịch sử; có lỗi → không nhả | AC-18 | `IngestRunnerTests.ejectsOnlyWhenClean`; ảnh banner |
| 23 | `CardBrowser` + hàng thẻ trong nhóm Sources (≤ 2 s, không tự mở, 0 banner) + **Choose Card…**; FS-10 thêm dòng ngoại lệ trỏ FS-20 (delta FS-18 §3) | AC-19 | `CardBrowserTests.rowAppearsWithoutOpening` (browser giả); iPhone: dump Collections › Sources; iPad/Mac: sau FS-21/FS-18 |
| 24 | Bookmark thẻ nhớ theo volume UUID, cắm lại không hỏi | AC-20 | `CardBookmarkStoreTests.recognisesSameCard`; thẻ thật: chưa kiểm (cần máy thật, board Q10) |
| 28 | **Pause / Resume** (board Q3, làm **trước 25**): runner dừng ở ranh giới file (file đang chép đi hết copy → verify → rename), trạng thái paused giữ danh sách còn lại, Resume tiếp từ file kế; mọi thiết bị; thêm AC-28 vào FS-20 01 + §7 cùng commit | AC-28 (mới) | `IngestRunnerTests.pauseFinishesCurrentFileThenResumes`; dump `PH_IngestProgress` có Pause |
| 25 | Tiến độ không chặn: chân sidebar/hàng thẻ `Importing from … N%`, nguồn đích vòng quay, đăng ký file vào nguồn giữa mẻ | AC-17 | `IngestRunnerTests.registersEachFileMidBatch`; iPad: lưới All Photos cuộn trong khi chạy (ui-drive); Mac → FS-18 |
| 26 | Ra nền: iOS 26 `ContinuedProcessingRun`, trước 26 = Stop + Import Remaining, 0 part | AC-26 | `IngestModelTests.backgroundOn26KeepsRunning`, `.backgroundBefore26Stops` (bộ chạy nền giả); 26.5 + 18.6 |
| 27 | iPhone 402×874 + Duo ngoài: chạm hàng thẻ → nhập 3 ảnh; Duo ngoài mọi control x ≤ 366 | AC-27 | ui-drive dump (`DC_Ingest`, `PH_Ingest`) + `design-board compare`; SHA bằng thẻ giả (thư mục DCIM); đầu đọc thật: chưa kiểm (cần máy thật) |

Mọi câu đã chốt (§6). Task 28 (Pause) làm trước task 25.

## 6. Đã chốt (planboard mac-ipad-v2)

Duyệt 2026-10-04, một vòng. Mỗi dòng: lựa chọn — id trên board.

**Kiến trúc**

- **K1** — A: `IngestRunner` mới trong `Domain/Ingest`, dùng lại plan/writer/checksum/failure của Export — **A11**.
- **K2** — A: `ExportDestinationWriter.write` nhận `expectedSHA256` tuỳ chọn, lệch → xoá part, ném `.checksumMismatch`
  trước rename; Export truyền nil — **A11**.
- **K3** — A: bookmark ổ thắng khi có, ImageCaptureCore khi chỉ nó thấy (máy ảnh USB), gộp hàng theo `cardId` — **A13**.
  Phép đo tốc độ ICC (cần máy ảnh thật) bỏ: chưa đo (cần máy thật) — **Q10**.
- **K4** — A: app active thì mỗi 1 s thử `checkResourceIsReachable` các bookmark thẻ (≤ 5) + callback ICC; Mac dùng
  `NSWorkspace.didMountNotification` — **A13**.
- **K5** — A: `App/ContinuedProcessingRun` chung, FS-20 làm trước, FS-15.02b dùng lại — **A12**.
- **K6** — A: ngày file trong danh mục thẻ cho khoá lịch sử và nhóm ngày; EXIF đọc nền để tinh nhóm + nơi chụp (chỉ
  `PlaceStore.cachedCell`) — **A14**.
- **K7** — A: cột `backupPath` trong `card_imports` — **A12**.

**Câu hỏi ⚠️ / ❓** (số Q của plan này → id trên board)

- **Q1** (AC-25) — chip Text chèn `_` + chữ `Text` được bôi chọn; chuỗi lưu là chữ thường, không token `{text}` — **A15**.
- **Q2** (AC-21) — đích offline: ảnh đã nhập vẫn **Imported** — **A14**.
- **Q3** (AC-18) — nhả qua ICC khi ICC thấy thẻ; không thì banner *"You can remove … now"*, công tắc Eject chỉ hiện khi
  nhả được; sửa FS-20 §6/§7 + AC-18 ở task 22 — **Q2**.
- **Q4** (spec ↔ spec) — SHA-256 cả file để kiểm + lịch sử; hash FS-19 băm từ cùng các khối lúc chép; sửa FS-20 §7.3 ở
  task 4 — **A11**.
- **Q5** (board ↔ spec) — **giữ Pause** (khác khuyên của bản nháp): dừng sau file đang chép, Resume chạy tiếp chỗ cũ,
  mọi thiết bị; task 28 + AC-28 — **Q3**.
- **Q6** (AC-4) — preset "Date and Number" = `{date}_{originalNumber}` — **A15**.
- **Kiểm cần thẻ / đầu đọc / máy ảnh thật** (AC-10 rút thật, AC-18 nhả thật, AC-20, AC-27 đầu đọc thật) — bỏ qua, ghi
  "chưa kiểm (cần máy thật)" — **Q10**.

## 7. Đổi so với bản nháp

- **Task 28 mới** (board Q3): Pause/Resume + AC-28, làm trước task 25. Tổng 27 → 28 task.
- **Task 24, 27** (Q10): bỏ phần "thẻ thật"; AC-20 và phần đầu đọc thật của AC-27 ghi "chưa kiểm (cần máy thật)" ở
  FS-20 01 (đã sửa khi duyệt).
- **K3** (Q10): khoá A không cần số đo ICC ở task 23.

## 8. Rủi ro và đánh đổi

| # | Rủi ro | Xác suất | Xử lý |
|---|---|---|---|
| R1 | **Dữ liệu:** migration `card_imports` | thấp | chỉ thêm bảng; đường lùi = drop bảng (lịch sử mất, ảnh ở đích còn nguyên); đăng ký **sau** migration FS-19; `data-migration` duyệt trước task 13 |
| R2 | **Bộ nhớ:** 1.046 ô đọc đầu file (RAF tới 8 MB/ô) + khối chép | trung | thumbnail ≤ 400 px vào cache có trần (cache chung FS-19.01b); đọc đầu theo ô đang hiện + hàng đợi nền giới hạn 2; một file một lúc, khối 1 MB, `autoreleasepool` mỗi khối; test đỉnh RAM như `FileExportMemoryTests` |
| R3 | **Thiết bị:** Duo trong 669pt, Duo ngoài rail 84, iPad dọc | trung | theo `DI_Ingest` (inspector thành sheet < 1100, FS-21), `DC_Ingest` (x ≤ 366), `IPP_Ingest` sheet hai cột; `device-layout` + `duo-ux-review` |
| R4 | **Concurrency:** đọc `FileHandle` trên ổ vừa rút có thể treo | cao | đọc khối trên thread riêng có watchdog 2 s (khuôn `LocalFolderWriter.guardedRename`, E3 `:149-163`); callback ICC → continuation, gọi một lần (`OSAllocatedUnfairLock` như memory "assumeIsolated in sync callback") |
| R5 | **Concurrency:** watcher FS-19 thấy `.shotdex-part` hoặc đăng ký trùng file nhập | trung | điều kiện ở bảng phụ thuộc; test `registersEachFileMidBatch` đếm đúng 1 bản sao |
| R6 | **Tốc độ:** đọc lại cả file ở đích gấp đôi I/O đích; ETA "about 4 min" | trung | ETA đếm byte hai lần; lần đầu đoán 100 MB/s (số §5), sau đó nhớ tốc độ mẻ trước theo đích |
| R7 | **Quyền:** ImageCaptureCore iOS cần `requestContentsAuthorization`; Mac sandbox cần entitlement thiết bị | trung | `privacy-manifest` xem trước task 23; phần Mac ghi vào FS-18 |
| R8 | **Simulator:** không có đầu đọc thẻ, không ICC | chắc | thẻ giả = thư mục `DCIM` trong On My iPhone, mở qua đường bookmark; ICC, rút thật, Eject thật, AC-20, đầu đọc thật của AC-27: **chưa kiểm (cần máy thật)** ở cột "Chứng minh bằng" (board Q10) |
| R9 | **PhotoKit:** không đụng (Photos không đổi) | — | `photokit-guard` không cần |
| R10 | Hai phiên cùng checkout (Export đang sửa) | cao | task 1 chờ commit; stage đúng đường dẫn, `git commit -- <paths>` |

## 9. Phản biện (điền sau khi chạy `challenger`)

| Phản đối | Trả lời / thay đổi |
|---|---|
| … | … |

## 10. Cách chứng minh là xong

- **Test:** mọi test ở mục 5; `Tools/gate` một lần cuối intent.
- **Màn phải chụp** (sáng + tối, iOS 26.5 + 18.6): Import from Card (New, All, ngày thu gọn, rỗng), inspector/sheet,
  đang chạy, tổng kết từng câu §8, hàng thẻ trong Sources, banner — trên iPhone 17, iPad ngang + dọc, Duo trong +
  ngoài (`Tools/sim-shot`); Mac sau FS-18. `design-parity` cho `PH_Ingest`, `PH_IngestProgress`, `IP_Ingest`,
  `IPP_Ingest`, `DI_Ingest`, `DI_IngestProgress`, `DC_Ingest`.
- **Tài liệu cập nhật cùng commit:** FS-03.07b §5 + 07c (task 1) · BD-02 (task 13) · README FS-20 dòng board (task 13)
  · FS-10 dòng ngoại lệ (task 23) · FS-20 §6/§7/AC-18 theo Q3 (task 22) · FS-20 §7.3 theo Q4 (task 4) · FS-20 §7 + AC-28 Pause (task 28) · cột
  "Chứng minh bằng" mỗi AC. **FS-21 §3:** không dòng nào thuộc FS-20 (FS-21 01-shell §35 đã đúng). **FS-18 §5** board
  Ingest iPhone/Duo/iPad dọc: đã vẽ — đánh dấu ở task 13.

## 11. Agent ở giai đoạn Deploy

`data-migration` (task 13) · `swift-concurrency` (runner, ICC, watchdog) · `memory-leak` + `perf-profiler` (thumbnail
1.046 ô, khối chép) · `device-layout` + `duo-ux-review` + `ipad-ux-review` + `iphone-ux-review` · `design-parity` ·
`ios26-parity` (task 26) · `ux-reviewer` (Stop, lỗi, không nhả) · `copy-consistency` + `localization` (bảng `Ingest`,
chip chung) · `a11y-voiceover` (ô *"IMG_5884.CR3, checked"*, phần trăm Copy/Verify/Backup) · `component-consistency`
(ô thẻ vs ô server, lưới chip) · `privacy-manifest` (ImageCaptureCore) · `challenger` trước khi duyệt.
Không cần: `photokit-guard` (không đụng Photos), `extension-boundary` (không gì vào ShotDexKit).
