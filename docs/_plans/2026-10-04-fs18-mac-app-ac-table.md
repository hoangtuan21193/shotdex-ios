# Bảng đối chiếu AC ↔ code — FS-18 ShotDex trên Mac

Thuộc [plan](2026-10-04-fs18-mac-app.md). Đặc tả: [`FS-18.06`](../02-functional-spec/FS-18-mac-app/06-acceptance-criteria.md)
(66 AC). Đọc code ngày 2026-10-04.

**Ký hiệu.** ✅ code đã đạt (chỉ viết test khoá) · ⚠️ lệch, **đã chốt** (plan §3, planboard mac-ipad-v2) · ⚠️ᴰ lệch nhưng SPEC-DECISIONS đã
chốt "tài liệu đúng" (không hỏi lại) · ❌ chưa có · ⏳ chờ plan khác (cột cuối).

**Code hôm nay, một đoạn.** Không có target macOS nào: project chỉ `SDKROOT = iphoneos`
(`ShotDex.xcodeproj/project.pbxproj:818, 874`), không `SUPPORTED_PLATFORMS`, không Catalyst. Vì vậy **mọi AC có màn
Mac là ❌**. Thứ đáng ghi trong bảng là **phần logic dùng chung đã có** (cột "Tái dùng") và **chỗ code iOS hôm nay sẽ
cho kết quả khác** nếu đem dùng nguyên (cột trạng thái ⚠️). "Biên dịch được trên macOS" dưới đây là kết quả spike
typecheck (plan §2): file đó typecheck với SDK macOS 27 / đích macOS 15 không lỗi.

Plan anh em: **FS-19** [`2026-10-04-fs19-photo-sources`](2026-10-04-fs19-photo-sources.md) (nguồn, id, bản sao,
sidecar, xoá theo đích, bookmark) · **FS-20** [`2026-10-04-fs20-card-ingest`](2026-10-04-fs20-card-ingest.md) (nhập thẻ) · **FS-01.08c**
[`2026-10-04-fs0108c-compare-viewer-mode`](2026-10-04-fs0108c-compare-viewer-mode.md) · **FS-21** [`2026-10-04-fs21-ipad-mac-style`](2026-10-04-fs21-ipad-mac-style.md) (khung iPad;
bảng phím Editor chung, mật độ lưới màn rộng, sidebar).

## 01 — Cửa sổ và điều hướng

| AC | TT | Code hôm nay (bằng chứng) | Tái dùng | Task | Chờ |
|---|---|---|---|---|---|
| AC-1 | ❌ | không có cửa sổ Mac | `ShellLayout` lớp `.mac` (FS-21 task 9, Domain/Shell) | M1 | T1, FS-21 task 9 |
| AC-2 | ❌ | không có | `ShellLayout` (FS-21) thêm ngưỡng Mac 1100/1280 — thuần | M2 | T1, FS-21 task 9 |
| AC-3 | ❌ | không có | như AC-2 | M3 | T1, FS-21 task 9 |
| AC-4 | ❌ | Editor iOS chỉ có bố cục điện thoại/iPad (`EditorLayoutMetrics`, Domain) | `PhotoEditorController` (biên dịch macOS sau P3: 20 lỗi, đều `UIImage`) | M41 | FS-21 (tên công cụ Adjust/Crop) |
| AC-5 | ❌ | Video Studio iOS dựng trên `UIScrollView` (`VideoTimelineScroller.swift`, 397 dòng) | `VideoStudioModel` (8 lỗi macOS: `UIApplication` background task, `UIImage`), `VideoStudioDeskGeometry` của plan wide-duo | M57 | T1, K3 |
| AC-6 | ❌ | Viewer iOS là pager `UIPageViewController` trong `PhotoDetailScreen.swift` (3169 dòng, 2 representable) | `PhotoGridSections`, lựa chọn/khôi phục cuộn của `LibraryModel` (1 lỗi macOS) | M22 | FS-01.08c (segmented Viewer) |
| AC-7 | ❌ | iOS một scene/cửa sổ | `AppDependencies` (biên dịch macOS 0 lỗi) dùng chung; `LibraryModel` mỗi cửa sổ một bản | M26 | M22 |
| AC-8 | ❌ | Collage/Resize/Combine iOS là `fullScreenCover` | `CollageModel` (0 lỗi), `CompressionController` (UIKit), `PanoramaMergeModel` | M53 | M26 |
| AC-9 | ❌ | không có | phím Z: `CullScreen.swift:68-111` là mẫu phím iOS | M25 | M22 |
| AC-10 | ❌ | lần mở đầu iOS là `OnboardingScreen.swift:5` → hộp quyền | — | M8 | ⏳ FS-19 (thêm nguồn), FS-21 (3 cách thêm nguồn mọi thiết bị) |
| AC-11 | ❌ | không có nguồn thư mục | — | M9 | ⏳ FS-19 |
| AC-12 | ❌ | iOS có accent amber (`App/Theme/AppAccentTheme.swift`, lỗi macOS: UIColor) | token `accent`/`accentFill` DESIGN.md §10b | M4 | T5 |
| AC-13 | ❌ | không có | driver Mac dump khung (T3) | M64 | M22, M41, M37 |
| AC-14 | ❌ | iOS có nhánh `#available(iOS 26)` mẫu (`LiquidGlassTabBar`, `RootTabView`) | cách chia nhánh của `ios26-parity` | — (nhánh macOS 15 trong từng task M) | chưa kiểm (cần máy thật, board Q10) |
| AC-15 | ❌ | `Tools/gate` chỉ build simulator iOS (`Tools/gate:24-31`) | `Tools/gate` | T2 | T1 |
| AC-16 | ❌ | tầng D iOS luôn tối (`EditorTheme`) | `EditorTheme` bảng màu §3.3 | M56 | M41, M53, M57 |

## 01b — Menu, phím, chuột phải, kéo thả

| AC | TT | Code hôm nay | Tái dùng | Task | Chờ |
|---|---|---|---|---|---|
| AC-17 | ❌ | phím iOS rải theo màn (`keyboardShortcut` ở 38 chỗ: `PhotoEditorScreen.swift:383-403`, `VideoStudioScreen.swift:611-638`, `CullScreen.swift:65-111` …) — không có danh mục lệnh | `CommandCatalog` (FS-21 task 28, `Domain/Shell/`) — mở rộng cho menu bar Mac, không viết bản thứ hai | M5 | T1, FS-21 task 28 |
| AC-18 | ❌ | không có | `CommandCatalog` | M6 | M5 |
| AC-19 | ❌ | ⌘E của Video Studio iOS là Export (`VideoStudioScreen.swift:635`) — khớp ý | `CommandCatalog` + menu Clip của FS-12.17b | M58 | M57 |
| AC-20 | ❌ | xoay chỉ có trong Editor (`PhotoEditorController.swift:2474`); không lệnh xoay từ lưới; **không dùng `UndoManager` ở đâu** (grep 0) | `PhotoEditRecipe` crop/rotate trong kit | M21 | K6 |
| AC-21 | ⚠️ᴰ | `MarkCopy.swift:153` chỉ có "Delete N Rejected…"; `RejectedDeleter.swift:20-38` chỉ PhotoKit | `MarkCopy`, `RejectedDeletion.swift:7` | S6 (tên theo đích, mọi thiết bị) + M39 (toolbar Cull Mac) — 2 commit | ⏳ FS-19 (đích từng bản sao) |
| AC-22 | ⚠️ | iOS: ← → **bước khung khi video dừng** (`PhotoDetailScreen.swift:1669-1680`), F = Favorite (`:706`), không có phím "." — khớp luật Mac, **ngược** FS-02.01b §2 (K8) | `VideoPlaybackModel.stepFrame` | S8 (iOS, theo câu trả lời Q1) + M24 (Mac) — 2 commit | Q1 |
| AC-23 | ⚠️ᴰ | iPad: ⌘C/⌘V chép-dán edit, ⌘0, ⌘\\ (`PhotoEditorScreen.swift:392-403`) — SPEC-DECISIONS: một bảng chung ⇧⌘C/⇧⌘V, `\`, Z | — (bảng mới `EditorKeyMap`, Domain) | S9 (bảng + iPad binding + test) + M47 (Mac) | sau FS-21 task 29 (cùng DESIGN §10.3) |
| AC-24 | ❌ | menu nhấn giữ iOS: `PhotoMarkMenus.swift` (bộ con Rating/Flag) | `PhotoMarkMenus` nội dung, `AssetActionsCoordinator.swift:100` (lỗi macOS: UIKit) | M16 | T1 |
| AC-25 | ❌ | không có trạng thái offline | — | M17 | ⏳ FS-19 |
| AC-26 | ❌ | iOS có thả lên album: `AlbumDropTarget.swift`, `PhotoDragItem.swift:13` (+ `PhotoDragItemTests`) | `PhotoDragItem`, `AlbumDropTarget` logic | M18 | K6 (undo) |
| AC-27 | ❌ | không có kéo ra Finder | render chia sẻ `LazyShareBatch` (lỗi macOS: UIKit), mức metadata FS-08.06 | M19 | ⏳ FS-19 (file gốc thư mục) |
| AC-28 | ❌ | iOS chép file thả vào Photos: `PhotoDropImport.swift:15` (+ `PhotoDropImportTests`) | `PhotoDropImport` cho nhánh Copy to Photos Library | M20 | ⏳ FS-19 (Add Folder) |
| AC-29 | ❌ | không có | — | M27 | M22 |

## 02 — Thư viện, Viewer, Cull, Get Info

| AC | TT | Code hôm nay | Tái dùng | Task | Chờ |
|---|---|---|---|---|---|
| AC-30 | ⚠️ | `GridDensity.columns(forDensity:width:isRegularWidth:)` (`GridDensity.swift:73-79`) cho **13 cột** ở bề rộng ~1180 (mật độ 3 × 1180 / 275); spec: **7 cột ô 165** | `GridDensity.stepped` (`:37`), `PhotoGridSections` | M10 | Q3 = FS-21 Q1 (`GridDensity` thêm tham số) |
| AC-31 | ❌ | iOS lưới phẳng; nhóm theo ngày đã có ở Domain `PhotoGridSections.swift:6, 74` (dùng cho On This Day/album) | `PhotoGridSections`, `PhotoGridSectionBuilder` (FS-21 task 38: dòng có nơi + số) | M11 | ⏳ FS-21 task 38 |
| AC-32 | ❌ | iOS chọn bằng chế độ Select + `SwipeSelection` (Domain) | `SwipeSelection` cho kéo khung | M12 | K3 |
| AC-33 | ❌ | iOS không có bảng | `LibraryModel` sắp xếp + `LibraryQueries` | M13 | — |
| AC-34 | ✅ một phần | parser: `SearchParserTests.combinedQuery` khoá "Canon 85mm f/1.8 ISO 400"; **chưa** có ca đúng câu AC; phạm vi nguồn ❌ | `SearchParser`, `SearchIntentParser` | A1 (test khoá parser) + M14 (token + phạm vi) | ⏳ FS-19 (điều kiện nguồn) |
| AC-35 | ❌ | iOS lọc qua sheet/chip (`LibraryModel`) | `FilterCriteria`, dòng "212 of 55,231" của `LibraryModel` | M15 | — |
| AC-36 | ❌ | iOS inspector 360 trong Viewer (FS-02.03b) | `PhotoInfoPanelSummary` (Domain) | M23 | M22 |
| AC-37 | ❌ | iOS có `InfoCaptionKeywordModel` + `PhotoKeywordStore.swift:13` (GRDB, quan sát được) | hai model cùng đọc một store — quan sát chung | M30 | M28 |
| AC-38 | ❌ | Cull iOS không có dải phím ẩn được | `CullSession.swift:6` | M37 | — |
| AC-39 | ❌ | không có offline | `CullSession` | M38 | ⏳ FS-19 |
| AC-40 | ❌ | `RejectedDeleter.swift:20-38` gửi hết vào Recently Deleted | `RejectedDeletion.swift:7` (lọc chỉ Rejected) | S5 | ⏳ FS-19 |
| AC-41 | ❌ | không có panel tiện ích | `PhotoInfoPanelSummary` | M28 | M22 |
| AC-42 | ❌ | caption/keyword nhiều ảnh có `CaptionKeywordBatchPlan.swift:39` (+ test); không có "Mixed" cho sao/Creator | `CaptionKeywordBatchPlan` | M29 | ⏳ FS-19 (Creator/Copyright vào sidecar) |

## 03 — Editor và xuất

| AC | TT | Code hôm nay | Tái dùng | Task | Chờ |
|---|---|---|---|---|---|
| AC-43 | ❌ | iOS chỉ lưu vào Photos (`PhotoEditingService.swift`) | recipe kit, `PhotoEditorController` | M42 | ⏳ FS-19 (recipe trong DB + sidecar) |
| AC-44 | ❌ | Save Changes iOS ghi Photos (`PhotoEditingService`) — đường này dùng lại nguyên | `PhotoEditingService` (lỗi macOS: `PhotoEditOrigin` rò tầng + 1 availability) | M44 | P2, P4; nửa iPhone/iCloud: chưa kiểm (cần máy thật) |
| AC-45 | ❌ | iOS hỏi "Discard" khi rời (FS-03.13a) — Mac tự Done (đã chốt, FS-03.13a sửa theo) | như AC-44 | M43 | — |
| AC-46 | ❌ | Revert iOS cho ảnh Photos | — | M45 | ⏳ FS-19 |
| AC-47 | ❌ | không có offline | — | M46 | ⏳ FS-19 |
| AC-48 | ❌ | `EditorSyncScope` chỉ `.look`/`.everything` (`EditClipboard.swift:72-92`) — không tick theo nhóm | `EditClipboard`, `EditorSyncScope.apply` | S3 | — |
| AC-49 | ❌ | `FileExportSettings` không có trường không gian màu (`FileExportOptions.swift:30-43`) | `FileExportRunner.swift:93`, `FileExportPlan` | S2 | — |
| AC-50 | ❌ (logic ✅) | Cancel/Stop iOS đã có test (`FileExportCancelTests`) | `FileExportRunner`, `FileExportProgress` | M51 | M49 (sheet Mac) |
| AC-51 | ❌ (logic ✅) | đích đầy iOS: `FileExportFailure.swift`, `FileExportFailureTests` | như trên | M52 | M51 |
| AC-52 | ❌ | đánh số " (2)" đã có (`FileExportPlan.swift:166-170`); không có hậu tố " (edited)"; Save Copy iOS ra asset Photos (`PhotoEditingService.swift:337`) — nửa Photos khớp | `FileExportPlan` đánh số, `saveCopy` | S4 | ⏳ FS-19 (ghi cạnh file gốc) |
| AC-53 | ❌ | Combine lưu vào Photos (`PhotoLibraryService.swift:994, 1051`) | `PanoramaStitchService`, `PhotoStackRenderer` (kit) | M54 | ⏳ FS-19 |

## 04 — Các màn còn lại

| AC | TT | Code hôm nay | Tái dùng | Task | Chờ |
|---|---|---|---|---|---|
| AC-54 | ❌ | `StatisticsQueries.swift:6` đếm theo dòng `photo_metadata` (một dòng mỗi asset) | `StatisticsQueries` | S10 | ⏳ FS-19 (id ảnh + bảng bản sao) |
| AC-55 | ❌ | không có điều kiện Source | `ChartSpec`, `ChartStore` | S11 | ⏳ FS-19 |
| AC-56 | ❌ | `ChartDimension` không có trục giờ/thứ (`ChartSpec.swift:167-184`) | `StatisticsQueries` (SQL `strftime`) | S1 | — |
| AC-57 | ❌ (logic ✅) | drill-down iOS: `AppNavigation.swift:45, 132` `pendingLibraryFilter` | `AppNavigation` (biên dịch macOS 0 lỗi) | M33 | S1 |
| AC-58 | ❌ | Statistics iOS có popup khoảng ngày ở trang máy (FS-07) | `StatisticsModel` (0 lỗi macOS) | M32 | — |
| AC-59 | ❌ | Settings iOS là split view có ô tìm (FS-08.01) | các store settings (`SettingsKeys`, `FileExportSettingsStore` …) | M36 | ⏳ FS-19 (pane Sources) |
| AC-60 | ❌ (logic ✅) | album trong folder Photos đã liệt kê phẳng: `AlbumsModel.swift:387-397` | `AlbumsModel` (0 lỗi macOS) | M31 | — |
| AC-61 | ❌ | Resize xoá gốc chỉ qua PhotoKit (`CompressionController.swift:19, 48`) | `CompressionController` | S7 | ⏳ FS-19 |

## 05 — Nền tảng

| AC | TT | Code hôm nay | Tái dùng | Task | Chờ |
|---|---|---|---|---|---|
| AC-62 | ❌ | không có bookmark | — | — (code: FS-19 B3 + T1) | ⏳ FS-19 (bookmark store); chưa kiểm (cần máy thật) |
| AC-63 | ❌ | iOS xử lý mất quyền Photos (`PhotoLibraryService`) | trạng thái quyền của `PhotoLibraryService` | — (code: M7, M36) | ⏳ FS-19 (trạng thái hàng nguồn); chưa kiểm (cần máy thật) |
| AC-64 | ❌ (test ✅ trên iOS) | `KernelGoldenTests.swift` + `KernelGoldenSupport.swift` không dùng UIKit; 9 kernel `.ci.metal` biên dịch cho macOS không lỗi (spike) | test golden của kit | M61 | P1, T3 |
| AC-65 | ❌ | không có | — | — (code: FS-19 C10, M41) | ⏳ FS-19 (sidecar); chưa kiểm (cần máy thật) |
| AC-66 | ✅ phần iOS | `Tools/gate` build + test iOS (`Tools/gate:76-79`) | `Tools/gate` | T1 + T3 (phần Mac) | — |

## Tổng

**0 ✅ trọn · 2 ✅ một phần** (AC-34 parser, AC-66 iOS) · **2 ⚠️ cần hỏi** (AC-22, AC-30) · **2 ⚠️ᴰ** (AC-21, AC-23) ·
**60 ❌** (6 trong đó logic đã có: AC-50, 51, 57, 60, 64 và nửa Photos của AC-52) · **0 ❓** trên AC; **❓ ngoài bảng**:
các màn không có AC nào ở FS-18 (plan §3, A30).

Chờ plan khác: **FS-19 — 22 AC** (10, 11, 21, 25, 27, 28, 34, 39, 40, 42, 43, 46, 47, 52, 53, 54, 55, 59, 61, 62, 63, 65) ·
**FS-21 — 9 AC** (1, 2, 3, 4, 10, 17, 18, 30, 31; AC-23 làm sau task 29 của nó) · **FS-01.08c — 1** (6) · FS-20 không có AC nào
của FS-18 chờ (chỉ dòng menu Import from Card… ở M5).
