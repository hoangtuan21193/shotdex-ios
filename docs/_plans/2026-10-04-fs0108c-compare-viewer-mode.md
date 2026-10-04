# Kế hoạch — Compare là một chế độ của Viewer (FS-01.08c)

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-01.08c`](../02-functional-spec/FS-01-library/08c-compare-viewer-mode.md) — **26 AC**; thay một phần [`FS-01.08`](../02-functional-spec/FS-01-library/08-compare.md) (§1, §2 dấu Duplicates, §3, §4 chạm-để-đánh-dấu, §7 "dấu bỏ khi đóng") |
| Bảng AC ↔ code | [`2026-10-04-fs0108c-compare-viewer-mode-ac-table.md`](2026-10-04-fs0108c-compare-viewer-mode-ac-table.md) (tách ra cho dễ đọc) |
| Intent | [2026-10-04-ipad-mac-style](../_intents/2026-10-04-ipad-mac-style.md) · [2026-10-04-macos-app](../_intents/2026-10-04-macos-app.md) — quyết định **D15** ([DECISIONS](../../.planboard/macos-app/DECISIONS.md)) + mục "FS-01.08c Compare" và "Planboard mac-ipad-v2" của [SPEC-DECISIONS](../../.planboard/macos-app/SPEC-DECISIONS.md) · [mac-ipad-v2](../../.planboard/mac-ipad-v2/DECISIONS.md) — **không mở lại** |
| Design | board trong repo: `PH_Compare` ([iphone](../design/iphone/project/)), `IP_Compare` · `IP_CompareSurvey` ([ipad](../design/ipad/project/)), `DI_Compare` · `DI_CompareSurvey` · `DC_Compare` ([duo](../design/duo/project/)), `MAC_Compare` · `MAC_CompareSurvey` ([mac](../design/mac/project/)). Đã đọc 2026-10-04: iPad/Mac **đã bỏ** *Sync Zoom and Pan*, `MAC_CompareSurvey` **đã có** Delete 2 Photos — hai dòng board của 08c §8 coi như xong |
| Plan anh em | FS-19 (nguồn, id, bản sao, hash, xoá theo đích) → FS-20 → **plan này** (độc lập, bắt đầu bất cứ lúc nào) → FS-21 (vỏ iPad) → FS-18 (Mac) |
| Ngày | 2026-10-04 |
| Trạng thái | **đã duyệt 2026-10-04** (planboard mac-ipad-v2); 26 task = 26 commit; 6 task (21–26) chờ FS-19/FS-18 |

## 1. Hiểu đúng chưa

Compare thôi là màn đen riêng. Nó là **chế độ thứ hai/thứ ba của Viewer**: cùng nền, cùng sáng/tối, cùng Close/Back.
Màn rộng (iPad, Duo trong, Mac) đổi **Single · 2-Up · Survey**; màn hẹp (iPhone, Duo ngoài) đổi **Single · Compare**, và
Compare ở đó là 2-Up **xếp chồng** (Select trên, Candidate dưới). Chạm ảnh chỉ chọn **khung làm việc** (viền amber);
cờ là cờ thật của FS-01.12 (`photo_flag`), đặt bằng nút trên khung hoặc phím `0–5 P X U`, và **còn sau khi đóng** —
lưới, Cull, bộ lọc Rejected thấy ngay. **Reject = đánh dấu xoá**; một nút **Delete N** (không nổi bật) xoá đúng các ảnh
Reject *trong phép so này*, đi tới đích theo nguồn (Photos → hộp hệ thống; thư mục/NAS → FS-19). Xoá xong: còn ≥ 2 ở
lại chế độ đang dùng, còn 1 về Single, 0 về lưới. Phóng/kéo luôn đồng bộ, không công tắc.

Code hôm nay (chi tiết ở bảng AC): `CompareScreen` là cover tầng D, một cách nhìn nhiều cột, chạm = dấu xoá trong
**bộ nhớ** (hoặc trong `DuplicateReviewSession`), không phím, không vai Select/Candidate, không Survey, hai ngón mới
kéo ảnh. Cái đúng sẵn: đồng bộ phóng/kéo theo tỉ lệ, ở-lại-khi-còn-≥-2, huỷ hộp hệ thống không đổi gì, Keep Only This
(trên dấu cục bộ). Plan **bỏ `CompareScreen`** (giữ `CompareScrollSynchronizer` và pane video), đưa luật vào một
`CompareSession` thuần ở Domain, và cắm một **sân khấu Compare** vào `PhotoDetailScreen` thay cho pager khi chế độ ≠ Single.

Không migration: cờ đã có bảng (`v27-ratingsAndFlags`); plan không thêm cột/bảng. Ảnh thư mục/NAS chưa tồn tại tới khi
FS-19 xong — các AC của chúng là ⏳.

## 2. Đối chiếu AC ↔ code (tóm tắt)

Bảng đầy đủ, bằng chứng `file:line`: [ac-table](2026-10-04-fs0108c-compare-viewer-mode-ac-table.md).

| Trạng thái | AC |
|---|---|
| ✅ code đã đạt — chỉ viết test khoá | AC-11 (huỷ hộp hệ thống không đổi gì) · AC-16 (không công tắc Sync, đồng bộ luôn bật — phần iPad) |
| ⚠️ᴰ lệch, D15 đã chốt "tài liệu đúng" | AC-1 · AC-2 · AC-6 · AC-8 · AC-10 · AC-17 · AC-20 · AC-22 |
| ⚠️ lệch, đã chốt | AC-9 (gỡ dòng cờ khi xoá vs luật mồ côi 30 ngày của FS-19) — §7 Q1 (A9) |
| ❌ chưa có | AC-3 · AC-4 · AC-5 · AC-7 · AC-14 · AC-15 · AC-19 · AC-21 · AC-26 |
| ❌ ⏳ chờ plan khác | AC-12 · AC-13 · AC-23 · AC-24 · AC-25 (FS-19) · AC-18 + phần Mac của AC-12/16/23 (FS-18) · nửa "sáng" của AC-1 và vị trí toolbar iPad (FS-21) |

**2 ✅ · 9 ⚠️ (8ᴰ + 1 đã chốt) · 15 ❌ (6 chờ hẳn plan khác).** ❓ đi kèm: AC-14 (sim không gập được — đo tay).
AC-26 đã chốt (board Q4): iPhone/Duo ngoài chỉ vào Compare từ chọn ≥ 2 ảnh; 08c §2, §7, AC-26 đã sửa khi duyệt.

## 3. Tái dùng (chặn "một khái niệm hai cách làm")

| Cần | Dùng cái có sẵn | Ghi chú |
|---|---|---|
| Đặt cờ/sao, nhớ trong bộ nhớ, undo | `PhotoMarks.apply` / `setFlag` / `setRating` (`PhotoMarks.swift:154-244`) | **không** giữ dấu trong `CompareModel`; đọc `photoMarks.version` để vẽ lại |
| Phím `0–5 P X U` | `PhotoMarkKeyButtons(ids:)` (`PhotoMarkMenus.swift:122`) + `MarkKeyCommand` | ids = `[workingId]` |
| Hàng `[Reject 44][★×5][Pick 44]` 340pt (iPhone/Duo) | `CullScreen.controlRow` + `flagButton` (`CullScreen.swift:170-220`), số ở `CullLayout` (`:11-17`) | **tách** thành `PhotoMarkRow` dùng chung có tham số bề mặt (tầng D cho Cull, kính tầng C cho Viewer) — không chép lần hai |
| Xoá ảnh Reject (Photos) | `RejectedDeleter.live` (`RejectedDeleter.swift:43-50`) + `RejectedDeletion.ids` (`RejectedDeletion.swift:9-11`) | cùng đường với Cull và viên Delete của thanh lọc; FS-19 mở rộng đúng chỗ này (K6) |
| Gỡ cờ khi app xoá | `PhotoLibraryService.deleteAssets` → `onAssetsDeleted` (`PhotoLibraryService.swift:967-975`, `AppDependencies.swift:346-352`) | không gỡ cờ lần hai trong Compare |
| Đồng bộ phóng/kéo, pane video | `CompareScrollSynchronizer`, `CompareVideoPaneView` (`CompareScreen.swift:17-251`) | dời sang `Features/Library/Compare/`; bỏ hai cờ chết `isZoomSyncEnabled`/`isPanSyncEnabled` (`:18-19`) |
| Ảnh phóng được, vuốt bằng UIKit | `ZoomableImageView` (`sync`, `paneIndex`, `onSwipe`, `panRequiresTwoFingers`, `ZoomableImageView.swift:10-60`) | cử chỉ SwiftUI chết trong UIScrollView (memory `swiftui-gesture-in-uiscrollview`) — vuốt candidate qua `onSwipe` |
| Nguồn ảnh cho Viewer từ một danh sách id | `PhotoListModel` (`PhotoListModel.swift:14`) | Duplicates mở Viewer trên nhóm; chế độ chọn dùng nguồn của màn (`LibraryModel`, `AlbumDetailModel`…) |
| Cổng "giữ ít nhất một" | `DuplicatesModel.isLastUnmarked` / `toggleMark` / `showBlocked` (`DuplicatesModel.swift:457-490`) | rút luật thành hàm thuần nhận vị từ "bị đánh dấu" (K2), lưới và Compare cùng gọi |
| Lớp cửa sổ (compact / cover 84 / rộng-thấp / rộng) | `VideoStudioWindowClass.resolve` (`VideoStudioWindowClass.swift:31-50`) | K3 — không viết ngưỡng 600/84/720 lần hai |
| Nút xoá chỗ Viewer để Delete (iPhone/Duo) | `GlassIconButton` trash của action bar (`PhotoDetailScreen.swift:742-748`) | Delete N ở cùng góc, kính + chữ đỏ |
| Banner kết quả xoá | `.appBannerHost` của Viewer (`PhotoDetailScreen.swift:322`) | Compare giờ ở trong Viewer nên banner hiện được — xem Q4 |
| Bốn bản `comparePhotos(_:)` gần giống nhau | `LibraryScreen.swift:436-449`, `AlbumDetailScreen.swift:471-480`, `OnThisDayScreen.swift:336-343`, `SmartAlbumDetailScreen.swift:462-468` | gộp thành một `CompareRequest(selection:)` — task 2 |

## 4. Chỗ nào trong code

| File | Tầng | Đụng gì | Mới / sửa |
|---|---|---|---|
| `ShotDex/Domain/Compare/CompareSession.swift` | Domain | thứ tự so, `selectId`, `candidateIndex`, `workingId`, `mode`; `start(selection:)`, `start(viewing:next:)`, `nextCandidate`/`previousCandidate`, `makeSelect`, `remove`, `keepOnly(_:) → (reject:, unreject:)`, `afterDeletion(gone:) → .stay/.single(id)/.grid`, `fold(to:)`, nhãn `Candidate k of n` / `N Photos` | mới |
| `ShotDex/Domain/Compare/ViewerMode.swift` | Domain | `single · twoUp · survey · compare(stacked)`; `available(for: windowClass)` | mới |
| `ShotDex/Domain/Compare/CompareLayout.swift` (thay `Domain/Grid/CompareLayout.swift`) | Domain | `twoUp`, `stacked(phone/cover)`, `survey(count:area:)` có ô tối thiểu ½ và cuộn; khung cao theo tỉ lệ ảnh | viết lại; bỏ `columns`/`distribute` |
| `ShotDex/Domain/Compare/CompareZoom.swift` | Domain | Fit ↔ 100 % (pixel ảnh ÷ (bề rộng Fit × scale)), nhãn `100%`, `Z` | mới |
| `ShotDex/Domain/Duplicates/…` (cạnh `DuplicateReview`) | Domain | `canMark(_:in:isMarked:)` — cổng thuần dùng chung | mới (rút từ `DuplicatesModel.swift:457-461`) |
| `ShotDex/Features/Library/Compare/CompareModel.swift` | Features | `@Observable`: giữ `CompareSession`, assets, `PhotoMarks`, bộ xoá; lệnh flag/keepOnly/delete; móc Duplicates (cổng + tỉa cache sau xoá) | mới |
| `ShotDex/Features/Library/Compare/CompareStage.swift`, `ComparePane.swift`, `CompareSurveyGrid.swift`, `CompareChrome.swift` | Features | sân khấu 2-Up / xếp chồng / Survey; pane (ảnh, tên + EXIF, sao + cờ, nhãn `Rejected`/`Picked`/`100%`, viền amber); segmented chế độ; Delete N; dòng gợi ý giữ-lâu; menu giữ-lâu | mới |
| `ShotDex/Features/Library/Compare/CompareScrollSynchronizer.swift` | Features | dời từ `CompareScreen.swift:14-251` | dời |
| `ShotDex/Features/Shared/PhotoMarkRow.swift` | Features | hàng Cull dùng chung (tầng D / tầng C) + `PhotoFlagSegmented` (None · Pick · Reject, 44) | mới, `CullScreen.swift:170-220` gọi nó |
| `ShotDex/Features/Library/PhotoDetailScreen.swift` | Features | `@State viewerMode` + `compareModel`; pager ↔ `CompareStage`; chrome theo chế độ; tắt kéo-xuống-đóng khi ≠ Single; nhận `CompareRequest` lúc mở | sửa (file 3169 dòng — logic vào `CompareModel`, view chỉ nối) |
| `LibraryScreen.swift`, `AlbumDetailScreen.swift`, `OnThisDayScreen.swift`, `SmartAlbumDetailScreen.swift`, `DuplicatesScreen.swift`, `DuplicatesModel.swift` | Features | lối vào: cover `CompareScreen(...)` → Viewer + `CompareRequest`; Duplicates qua `PhotoListModel` | sửa |
| `SelectionBarViews.swift:190`, `SelectionBarModel.swift:49` | Features | `CompareScreen.minPhotoCount` → `CompareSession.minimumCount` | sửa |
| `ShotDex/Features/Library/CompareScreen.swift` | — | xoá (sau task 2) | xoá |
| `ShotDexTests/CompareSessionTests.swift`, `ViewerModeTests.swift`, `CompareLayoutTests.swift` (viết lại), `CompareZoomTests.swift`, `CompareModelTests.swift`, `CompareScrollSynchronizerTests.swift`, `DuplicateReviewTests.swift` (+ cổng) | Test | | mới / sửa |
| `ShotDexUITests/scripts/compare-*.json` | Test | route iPhone xếp chồng, iPad 2-Up/Survey, Duo trong/ngoài; thay `compare-ipad-landscape.json` | mới / viết lại |

## 5. Thứ tự task

Thứ tự theo luật ✅ → ⚠️ → ❌, trừ chỗ phụ thuộc bắt buộc (ghi ở cột cuối). **Một AC = một task = một commit**
(`feat(FS-01.08c): AC-n …`), build sau mỗi commit, đụng UI thì `/screens compare` + `design-parity` board tương ứng.

| # | AC | Task (file) | Test / bằng chứng | Phụ thuộc · tài liệu cùng commit |
|---|---|---|---|---|
| 1 | AC-16 ✅ | test khoá `CompareScrollSynchronizer` trên code hôm nay: pinch một `UIScrollView` → mọi view đã đăng ký cùng zoom + offset tỉ lệ; view dựng sau nhận trạng thái cuối | `CompareScrollSynchronizerTests.everyPaneFollowsAPinch`, `…aLatePaneCatchesUp` | — |
| 2 | AC-1 ⚠️ᴰ | **Khung**: `CompareSession` (start từ thứ tự chọn), `ViewerMode`, `CompareLayout.twoUp`; `CompareModel`; `CompareStage` 2-Up trong `PhotoDetailScreen` (pager ẩn, kéo-xuống-đóng tắt); `CompareRequest(selection:)` gộp 4 bản `comparePhotos`; 5 lối vào đổi sang Viewer; dời synchronizer; xoá `CompareScreen`; màu **ngữ nghĩa** (theo scheme của Viewer, không `Color.black`/`EditorTheme`) | `CompareSessionTests.selectionOrderGivesSelectAndCandidateOneOfThree`, `CompareLayoutTests.iPadTwoUpFramesAre664x832`; route `compare-ipad-2up.json` (Select = ảnh chọn đầu, `Candidate 1 of 3`); ảnh tối. **Nửa sáng chờ FS-21 AC-52** (K4) | sửa `08-compare.md` (khối "thay thế bởi 08c" ở đầu §1–§4, §7) · DESIGN.md §2 bỏ câu "Code hiện vẫn vẽ Compare ở tầng D…" · FS-01 README thêm dòng 08c · FS-18 `07-spec-deltas.md` §3 dòng 08 và FS-21 `03-spec-deltas.md` §1 dòng FS-01.08 ghi "đã làm" |
| 3 | AC-11 ✅ | test khoá: `CompareModel.deleteRejected()` với bộ xoá ném `userCancelled` → `.cancelled`, 3 khung, cờ còn, banner rỗng | `CompareModelTests.cancelInTheSystemDialogKeepsFramesAndFlags` | 2 |
| 4 | AC-2 ⚠️ᴰ | cờ thật: `CompareModel.apply(_:)` → `PhotoMarks.apply(ids: [working])`; `PhotoMarkKeyButtons`; nhãn `× Rejected` trên khung (VoiceOver *"Rejected, marked for deletion"*); tách `PhotoMarkRow` từ `CullScreen` (iPhone/Duo); Delete N đếm `RejectedDeletion.ids(visible: session.ids)` | `CompareModelTests.xOnTheWorkingFrameRejectsItForReal` (in-memory `PhotoMarksStore`); route: `X` → `Delete 1 Photo`, đóng → ô lưới alpha 0.45 (dump) | FS-01.12 §3 bỏ dòng "Cờ trong Compare — cố ý không có" |
| 5 | AC-8 ⚠️ᴰ | `CompareSession.keepOnly` (Reject mọi ảnh khác, bỏ Reject của nó, Pick giữ); menu giữ-lâu: Make Select · Share (iPhone/Duo) · Remove from Comparison · Keep Only This (đỏ); dòng *"Touch and hold to keep only this one"* khi ≥ 1 Reject | `CompareSessionTests.keepOnlyRejectsTheOthersAndKeepsAPick`; `CompareModelTests.keepOnlyGivesDeleteThree` | 4 |
| 6 | AC-9 ⚠️ (Q1) | `CompareModel.deleteRejected()` qua `RejectedDeleter.live`; `CompareSession.afterDeletion(gone:)` → `.stay(mode)`; banner kết quả | `CompareSessionTests.twoLeftStayInTwoUp`; `CompareModelTests.deletedFramesLeaveAndFlagsGo` (AC-9 quan sát được: 0 Reject trong phép so, bộ lọc Rejected không còn 2 ảnh) | 4 · câu chữ AC-9 theo Q1 (A9) · 08c §6 câu Hỏng → banner + Try Again (Q4, A18) |
| 7 | AC-22 ⚠️ᴰ | Delete N luôn có: 0 Reject → chữ **Delete**, `.disabled`, mờ; bỏ dòng *"Tap a photo…"*; kiểu "kính + chữ đỏ, không nền đỏ" | `CompareModelTests.noRejectsMeansADisabledDelete` (nhãn + `canDelete == false`); dump route: nút `Delete` không bật, chạm không mở hộp | DESIGN.md §13 dòng 518 ("…một control duy nhất ở top-right — xem §Compare") viết lại |
| 8 | AC-10 ⚠️ᴰ | `afterDeletion` → `.single(id)`: Viewer về Single, `currentIndex = source.index(of: id)`, `reseatToken += 1`; `.grid` → dismiss | `CompareSessionTests.oneLeftGoesSingleOnIt`, `…noneLeftGoesToTheGrid` | 6 |
| 9 | AC-17 ⚠️ᴰ | Duplicates ↔ cờ theo K2: Compare mở từ Duplicates qua `PhotoListModel`, Reject ghi `photo_flag`; Duplicates đọc dấu theo K2; xoá trong Compare gọi `DuplicatesModel.delete(ids:)` để tỉa hash/nhóm | `DuplicateReviewTests.aRejectFromCompareMarksTheTile` (theo K2); route Duplicates → Compare → `X` → đóng → lưới mờ 45 % + bộ lọc Rejected chứa ảnh | DESIGN.md §9 câu "trạng thái đánh dấu phá hủy (card Compare mở từ Duplicates…)" → nhãn `Rejected` + cờ thật · `08-compare.md` §2 dòng Duplicates |
| 10 | AC-20 ⚠️ᴰ | iPhone/Duo: bỏ `panRequiresTwoFingers` trong Compare; > Fit một ngón kéo (đồng bộ), vuốt ngang đổi candidate **chỉ ở Fit** (như pager Viewer) | route `compare-iphone-stacked.json`: 100 % → vuốt → `Candidate 1 of 3`; Fit → vuốt → `2 of 3` | 11, 12 (ngoại lệ thứ tự: cần xếp chồng + 100 %) |
| 11 | AC-3 ❌ | `CompareLayout.stacked(.phone)` 370×294; Select trên, Candidate dưới; vuốt Candidate (`onSwipe`) → `nextCandidate`; Select đứng yên | `CompareLayoutTests.phoneStacksTwo370x294`; `CompareSessionTests.swipeMovesOnlyTheCandidate`; route `compare-iphone-stacked.json` | 2 |
| 12 | AC-4 ❌ | `CompareZoom`: mức 100 %, nhãn `100%` (+ glyph liên kết ở iPhone/Duo), popup **Fit · 100%**, phím `Z` | `CompareZoomTests.hundredPercentIsOnePixelPerPixel`; route pinch Select → cả hai nhãn `100%` | 2 |
| 13 | AC-5 ❌ | Make Select: toolbar (iPad tạm ở chrome Viewer, K5), thanh dưới iPhone/Duo, phím `↑` | `CompareSessionTests.makeSelectSwapsRolesNotMarks` | 2 |
| 14 | AC-21 ❌ | Survey: `CompareLayout.survey` (iPad 432×288 → min 216×144, Duo trong 264×176 → 132×88), lưới cuộn dọc; ảnh xin **cỡ ô**, không cỡ màn (rủi ro bộ nhớ §6) | `CompareLayoutTests.twelveOnIPadShrinkTo216x144AndScroll`, `…sixFitWithoutScroll`; route `compare-ipad-survey.json` | 2 |
| 15 | AC-6 ⚠️ᴰ | chạm ô = khung làm việc (viền amber), không đổi cờ; `P` → nhãn `Picked` | `CompareSessionTests.tapSetsTheWorkingFrameOnly`; route Survey ô 3 → `P` | 14 (ngoại lệ thứ tự) |
| 16 | AC-7 ❌ | Remove from Survey (✕/⊖ 44, Mac `⌫` ở FS-18): `CompareSession.remove`, tiêu đề `5 Photos` | `CompareSessionTests.removeKeepsTheFlagAndTheLibrary` | 14 |
| 17 | AC-15 ❌ | cổng thuần dùng chung; Compare từ Duplicates: Reject ảnh không-Reject cuối của nhóm → không đổi, `.sensoryFeedback(.warning)`, *"Keep at least one photo in this group."*; nút Reject của ảnh đó mờ | `DuplicateReviewTests.theLastUnrejectedPhotoCannotBeRejected`; route | 9 · FS-06.06b §1 dòng "nút thùng rác của pane" → "nút Reject của ảnh cuối" |
| 18 | AC-19 ❌ | pane màn rộng: 5 sao + `PhotoFlagSegmented` None · Pick · Reject cao **44** (iPad) | dump `compare-ipad-2up.json`: segmented cao 44 ±1 | 4 |
| 19 | AC-14 ❌ | `CompareSession.fold(to: .compact)` (Survey/2-Up → xếp chồng, Select = khung làm việc), `CompareLayout.stacked(.cover)` 350×224, mọi control x ≤ 366 | `CompareSessionTests.foldingSurveyMakesTheWorkingFrameSelect`, `CompareLayoutTests.coverKeepsEverythingLeftOf366`; route `compare-duo-cover.json`; **gập bằng tay** trong Simulator.app (❓ cây view có giữ không — như ❓3 của plan Video) | 11, 14 |
| 20 | AC-26 ❌ | `CompareSession.start(viewing:next:)`: Select = ảnh đang xem, Candidate = `source.photoId(at: i + 1)` (ảnh cuối → ảnh trước); segmented chế độ trong Single **chỉ màn rộng** (`ViewerMode.available(for:)`); iPhone/Duo ngoài: Viewer Single không segmented, không dòng Compare trong ⋯ — chỉ vào từ chọn ≥ 2 (`CompareSession.minimumCount`, board Q4) | `CompareSessionTests.fromTheViewerTheCandidateIsTheNextCell`, `ViewerModeTests.compactSingleOffersNoCompare`; route `compare-from-viewer.json`: iPad ô 5 → 2-Up; iPhone dump 0 segmented, chọn 1 → Compare mờ, chọn 2 → xếp chồng | 2 · 08c §2/§7/AC-26 đã sửa khi duyệt |
| 21 | AC-12 ⏳ | Mac, thư mục → Thùng rác (file + `.xmp`) | `design-parity` `MAC_Compare`; test của FS-19 | **FS-19** (bộ định tuyến xoá, K6) + **FS-18** (target Mac) · chữ AC-12 theo Q2 (A7) |
| 22 | AC-13 ⏳ | NAS → Hide; SHA-256 file không đổi | test của FS-19 | **FS-19** (Hide, bảng ẩn) · chữ AC-13 theo Q2 (A7) |
| 23 | AC-18 ⏳ | Mac: Delete N trước Edit, `⌘⌫`, Keep Only This ở menu chuột phải + menu Photo | route Mac | **FS-18** |
| 24 | AC-23 ⏳ | trộn nguồn: một hộp liệt kê từng đích, Photos qua hộp hệ thống; huỷ ở đó chỉ giữ phần Photos | test của FS-19 | **FS-19** + **FS-18** · chữ AC-23 theo Q2 (A7); luật huỷ theo Q3 (A7) |
| 25 | AC-24 ⏳ | ổ ngoài không Thùng rác: hộp đỏ thứ hai *Delete Permanently* | test của FS-19 | **FS-19** |
| 26 | AC-25 ⏳ | Reject ảnh thư mục → `.xmp` sao −1 sống qua khởi động lại | test của FS-19 | **FS-19** (ghi sidecar); Compare không thêm code — chỉ chứng minh |

## 6. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| **Bộ nhớ Survey**: ảnh cỡ màn (`ActiveDisplay.pixelSize`, `CompareScreen.swift:808`) × 12 ô ≈ 12 × 22 MB trên iPad 13" | cao | Survey xin ảnh **cỡ ô × scale**; 2-Up giữ cỡ màn; luật bản cao 08 §6 (≤ 2 × 3000px) **chưa có trong code** (`:806-833`) và không thuộc AC nào của 08c → ghi `REVIEW_QUEUE.md`, không làm ở đây; `memory-leak` |
| **Duo trong 669pt**: 2-Up 451×453 + toolbar + hàng sao/cờ; ngoài: rail 84, control x ≤ 366, góc bo ~37pt | cao | số ở `CompareLayout` có test tổng chiều cao; `Tools/sim-shot … inner|cover` có mask; Duo **chỉ** lái bằng `Tools/ui-drive` (CLAUDE.md) |
| **Cử chỉ chọi nhau**: pager Viewer (vuốt ngang), kéo-xuống-đóng, vuốt candidate, một ngón kéo khi phóng | cao | Compare ẩn pager và tắt kéo-xuống-đóng; mọi cử chỉ qua UIKit (`ZoomableImageView.onSwipe`), không SwiftUI `DragGesture` trong scroll view (memory) |
| **`PhotoDetailScreen` 3169 dòng, FS-21 cũng sửa nó** (toolbar iPad, sáng/tối) | cao | logic ở `CompareModel`/`CompareSession`; view chỉ một nhánh `if viewerMode == .single { pager } else { CompareStage }`; commit `git commit -- <paths>`, không `add -A` (memory `two-agents-shared-checkout`) |
| Concurrency: `PhotoMarks.setFlag` chờ ghi nền; bấm `X` liên tiếp trên hai khung | trung bình | ghi tuần tự trên main actor như Cull; `swift-concurrency` |
| PhotoKit: xoá cả mẻ hoặc không; `.limited`; ảnh chỉ iCloud xoá không tải | thấp | đi nguyên `RejectedDeleter` + `deleteAssets` đã có; `photokit-guard` |
| Dữ liệu: không migration; Duplicates đổi nguồn dấu (K2) | trung bình | K2 phương án A/B không đổi schema; `DuplicateReviewTests` giữ mọi test cổng/Merge/Delete hiện có |
| iOS 26 vs trước: chrome Viewer có hai nhánh kính | trung bình | segmented + Delete N qua `GlassPanel`/`GlassIconButton`/`.glassBackground` (3 lối vào kính); `ios26-parity` |
| Bàn phím: `←/→` của Viewer (pager) vs candidate; `↑` Make Select; `Z`; `Esc` | trung bình | hidden button theo chế độ (như `CullScreen.keyButtons`); FS-21 bổ sung phím iPad |

## 7. Đã chốt (planboard mac-ipad-v2)

Duyệt 2026-10-04, một vòng. Mỗi dòng: lựa chọn — id trên board.

**Kiến trúc**

- **K1** — A: `PhotoDetailScreen` thêm `viewerMode`; khác Single thì `CompareStage` thay pager; luật ở
  `CompareSession`/`CompareModel` — **A16**.
- **K2** — A: Compare chỉ ghi cờ; dấu phiên của nhóm Duplicates được nâng thành Reject lúc mở; Duplicates coi ô đã đánh
  dấu khi `session.marks ∪ Reject`; sửa FS-06.06b §1 ở task 9 — **A17**.
- **K3** — A: nâng `VideoStudioWindowClass` thành `Domain/Layout/WindowClass` (một commit nhỏ trước task 2, báo plan
  Video) — **A16**.
- **K4** — B: Compare chỉ dùng màu ngữ nghĩa; FS-21 AC-52 làm Viewer sáng/tối và chụp nửa sáng của AC-1 — **A19**.
- **K5** — A: iPad dùng chrome Viewer hiện có tới khi có toolbar FS-21; `design-parity IP_Compare` chỉ qua phần sân khấu
  tới lúc đó — **A19**.
- **K6** — A: FS-19 mở rộng `RejectedDeleter` thành bộ định tuyến; Compare chỉ gọi nó; task 21–26 chờ FS-19 — **A18**.

**Câu hỏi ⚠️** (số Q của plan này → id trên board; 8 dòng ⚠️ᴰ không hỏi — D15 "tài liệu đúng, sửa code")

- **Q1** (AC-9) — tài liệu FS-19 đúng (mồ côi 30 ngày); AC-9 thành điều quan sát được, sửa ở task 6 — **A9**.
- **Q2** (AC-12, 13, 23) — §5 đúng: chữ nút theo đích (Move/Delete/Hide); sửa chữ ba AC ở task 21, 22, 24 — **A7**.
- **Q3** (AC-23) — 08c §6 đúng: huỷ hộp hệ thống chỉ giữ lại phần Photos; FS-19.04 §2 sửa ở FS-19 task E3 — **A7**.
- **Q4** (§6 Hỏng) — code đúng: lỗi xoá → banner + **Try Again** qua `appBannerHost`, một cách cho mọi lệnh xoá Reject;
  sửa câu 08c §6 ở task 6 — **A18**.
- **Q5** (AC-26) — **khác đề xuất**: iPhone và Duo ngoài **chỉ** so sánh từ chế độ chọn ≥ 2 ảnh — không "Compare with
  Next" trong ⋯, không nút trên Viewer Single; màn rộng giữ 2-Up từ Single (Candidate = ảnh kế) — **Q4**.

## 8. Đổi so với bản nháp

- **Task 20** (board Q4): bỏ lối vào iPhone từ ⋯; thêm test `ViewerModeTests.compactSingleOffersNoCompare` và phần
  iPhone của route `compare-from-viewer.json`. Không cần vẽ `PH_Viewer`.
- **Task 6**: thêm câu Hỏng của 08c §6 (A18) và câu chữ AC-9 (A9) vào cùng commit.
- **Task 21, 22, 24**: chữ AC-12, 13, 23 theo A7 cùng commit.
- Số task không đổi: 26.

## 9. Phụ thuộc giữa các plan

| Plan | Plan này cần gì | Plan đó cần gì từ plan này |
|---|---|---|
| FS-19 (nguồn, xoá theo đích) | bộ định tuyến xoá (K6), bảng ẩn, ghi `.xmp`, bảng Cờ chung theo id ảnh → task 21, 22, 24, 25, 26; sửa FS-19.04 §2 theo Q3 (FS-19 task E3) | `CompareModel` gọi đúng một điểm xoá |
| FS-21 (vỏ iPad) | Viewer sáng/tối (AC-52) → nửa sáng AC-1; toolbar Viewer (segmented, Make Select, Delete N trước Edit, filmstrip 100 có viền amber/mờ Reject) | `ViewerMode`, `CompareModel`, `PhotoFlagSegmented` 44 dùng lại ở inspector |
| FS-18 (Mac) | target Mac, menu Photo, `⌘⌫` → task 21, 23, 24 | toàn bộ Domain/Features Compare dùng lại |
| `vs-wide-and-duo-layout` | `VideoStudioWindowClass` (K3) | đổi tên/chuyển chỗ theo K3-A — hẹn trước |
| `rating-flags-cull` (2026-10-02) | `PhotoMarks`, `RejectedDeleter`, hàng Cull | `PhotoMarkRow` tách ra — Cull gọi bản chung |

## 10. Cách chứng minh là xong

- **Test** (`/test`): `CompareSessionTests`, `ViewerModeTests`, `CompareLayoutTests` (viết lại — bỏ test cột cũ), `CompareZoomTests`,
  `CompareModelTests`, `CompareScrollSynchronizerTests`, `DuplicateReviewTests` (+ cổng, + K2). Full suite một lần cuối
  intent (`Tools/gate`).
- **Route** (`Tools/ui-drive`, một lượt một lúc): `compare-iphone-stacked`, `compare-ipad-2up`, `compare-ipad-survey`
  (6 và 12 ảnh), `compare-duo-inner`, `compare-duo-cover`, `compare-from-duplicates`, `compare-from-viewer`. Ảnh mẫu
  **không có mặt người** (memory). Chụp Duo bằng `Tools/sim-shot … inner|cover`.
- **Màn hình** (`/screens compare`): iPhone 402×874, iPad 13" ngang + dọc, Duo trong 951×669, Duo ngoài 466×678; mỗi
  chế độ (Single, 2-Up/Compare, Survey), 0 / ≥ 1 Reject, menu giữ-lâu, sau xoá (≥ 2, 1); iOS 26.5 + 18.6; tối (sáng sau
  FS-21).
- **design-parity**: `PH_Compare`, `IP_Compare`, `IP_CompareSurvey`, `DI_Compare`, `DI_CompareSurvey`, `DC_Compare`
  (≤ 2pt; iPad phần toolbar sau FS-21); `MAC_*` ở FS-18.
- **Đo tay**: gập Duo (AC-14).
- **Tài liệu cùng commit**: cột "Chứng minh bằng" của 08c từng AC; các dòng ở cột cuối §5 (08 §1–§4/§7, DESIGN.md §2/§9/§13
  dòng 518, FS-01.12 §3, FS-06.06b §1, FS-01 README, FS-18 07 §1/§3, FS-21 03 §1); `REVIEW_QUEUE.md`: luật bản cao 08 §6
  chưa có trong code.

## 11. Agent ở giai đoạn Deploy

| Agent | Vì sao |
|---|---|
| `design-parity` | 6 board iOS, lặp tới khi qua |
| `device-layout` · `duo-ux-review` | 669pt, rail 84, x ≤ 366, góc bo; Compare trước đây là tầng D trong danh sách của nó |
| `iphone-ux-review` · `ipad-ux-review` | cử chỉ xếp chồng/vuốt candidate/một ngón kéo; Survey + phím |
| `ios26-parity` | chrome Viewer hai nhánh kính |
| `a11y-voiceover` | nhãn khung *"Photo, DSC04513.ARW, No rating, Rejected, marked for deletion"*, sao/cờ là control riêng |
| `photokit-guard` | đường xoá, `.limited`, iCloud |
| `memory-leak` | Survey 12 ô, synchronizer giữ yếu, pane video |
| `swift-concurrency` | ghi cờ liên tiếp, nạp ảnh pane |
| `component-consistency` · `copy-consistency` | `PhotoMarkRow` một bản cho Cull + Compare; Delete/Move/Hide N; `Candidate k of n`; "Keep Only This" |
| `ux-reviewer` · `challenger` | luồng xoá theo đích, ở lại/Single/lưới sau xoá; K2 đổi nghĩa thanh Duplicates |

## 12. Phản biện (điền sau khi chạy `challenger`)

| Phản đối | Trả lời / thay đổi |
|---|---|
| … | … |
