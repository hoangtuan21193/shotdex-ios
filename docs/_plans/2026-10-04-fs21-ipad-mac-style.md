# Kế hoạch — iPad theo kiểu app Mac (FS-21)

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-21`](../02-functional-spec/FS-21-ipad-mac-style/README.md) — 62 AC (AC-1…AC-60, AC-21b, AC-27b), [04](../02-functional-spec/FS-21-ipad-mac-style/04-acceptance-criteria.md) |
| Intent | [2026-10-04-ipad-mac-style](../_intents/2026-10-04-ipad-mac-style.md) (accepted) |
| Quyết định | `.planboard/macos-app/SPEC-DECISIONS.md` (mục FS-21 + gói 13 điểm + "Planboard mac-ipad-v2"), `.planboard/macos-app/DECISIONS.md`, [mac-ipad-v2](../../.planboard/mac-ipad-v2/DECISIONS.md) — không mở lại |
| Bảng AC ↔ code | [2026-10-04-fs21-ipad-mac-style-ac-table.md](2026-10-04-fs21-ipad-mac-style-ac-table.md) |
| Design | `docs/design/ipad/project/` (`Main`, `IP_*`, `IP1…IP24`, `IPP1…IPP24`); DESIGN.md §10.1g |
| Ngày | 2026-10-04 |
| Trạng thái | **đã duyệt 2026-10-04** (planboard mac-ipad-v2); 59 task = 59 commit (+ task cho màn của A25 sau `/spec`) |

## 1. Hiểu đúng chưa

Trên iPad, gốc app không còn tab bar mà là **sidebar · nội dung · inspector** với toolbar ở trên, chọn theo
**bề rộng cửa sổ** (< 700 bố cục iPhone · 700–1099 sidebar phủ + inspector là sheet · ≥ 1100 sidebar ghim 320 +
inspector cột 360), dựng từ sidebar/toolbar **của hệ thống** ở cả iOS 26 lẫn 17/18. Mỗi màn dời lệnh từ thanh đáy,
nút tròn kính và sheet lên toolbar và inspector; Viewer, Editor, công cụ tầng D mở trong cửa sổ. Kèm theo là phần
"mọi thiết bị": Viewer theo sáng/tối, Settings › **Sources**, tên công cụ Adjust/Crop, câu chào mới, lệnh iPad thêm
vào ⋯ của iPhone (List, Go to Date, Rotate, Print, Keep All, đổi kiểu biểu đồ). **iPhone và Duo giữ bố cục** — kể cả
Duo trong 951pt, rộng hơn mốc 700 (xem K1 và rủi ro R1).

Code hôm nay (chi tiết ở bảng AC): gốc là `TabView` 4 tab (`App/RootTabView.swift:189-216`) hoặc tab bar kính tự vẽ
pre-26 (`:306-326`); `AppNavigation` chỉ biết `selectedTab` (`App/AppNavigation.swift:9`); không menu bar, không
inspector, không hàm chọn bố cục cho gốc; Viewer, Compare, Settings là `fullScreenCover`; Viewer ép tối
(`PhotoDetailScreen.swift:316`); editor rộng là bản rail 48 + cột kéo được 280…420 (2026-09-22), **không** phải
FS-03.17/17a mà spec FS-21 nói nó thay.

## 2. Tổng đối chiếu

**8 ✅ · 6 ⚠️ · 47 ❌ · 1 ❓** — bảng đầy đủ: [ac-table](2026-10-04-fs21-ipad-mac-style-ac-table.md).

| | AC |
|---|---|
| ✅ khoá bằng test | AC-10 (+16), AC-14, AC-20, AC-28, AC-35, AC-36, AC-43 |
| ⚠️ đã chốt (§8) | AC-11 (Q2), AC-17 (Q3), AC-33 (Q4), AC-49 (Q1), AC-54 (Q5), AC-56 (Q6) |
| ❓ → ✅ | AC-37 — K4-A đã chốt (Settings giữ cover) nên đúng sẵn; task 55 chỉ khoá test |
| ❌ | còn lại; 3 AC phụ thuộc plan FS-19: AC-30, AC-42 (thẻ Folder/Server), phần Sources của AC-1/AC-53 |

**Chứng minh bằng của spec sai một chỗ:** 04 ghi "`Tools/ui-drive` chưa có bước phím / kéo-thả". Driver **đã có**
bước `key` với cmd/shift/option và bước `drag` (`ShotDexUITests/UIDriverTests.swift:154-180`). Thiếu thật: phím
`ctrl` (⌃⌘S), chạm có phím bổ trợ (⌘/⇧-chạm), pinch, đổi cỡ cửa sổ / Split View. Task 0 bổ sung ba cái đầu → AC-12,
13, 17–19, 44–46, 49 tự động được; AC-20, AC-22 vẫn kiểm tay + test thuần.

## 3. Phụ thuộc plan khác

Thứ tự toàn cục: FS-19 → FS-20 → (FS-01.08c bất kỳ lúc nào) → **FS-21** → FS-18.

| Task FS-21 | Chờ | Vì |
|---|---|---|
| 13 nhóm Sources của sidebar (đủ hàng nguồn, Eject, `+`) | plan FS-19 (bảng sources + store) | hôm nay không có mô hình nguồn (không `PhotoSource`, không bảng `sources`) — task 13 làm nhóm với **một** hàng Photos Library cố định, FS-19 đổ dữ liệu vào |
| 13 hàng thẻ nhớ trong Sources | plan FS-20 | hàng xuất hiện khi FS-20 có đường phát hiện thẻ |
| 32 (Compare trên toolbar chọn), 43 (segmented Single · 2-Up · Survey trên toolbar Viewer) | plan FS-01.08c | Compare thành chế độ Viewer; FS-21 chỉ đặt chỗ cho segmented |
| 54 nội dung pane Sources · 57 thẻ Add Folder or Drive / Connect to Server · 58 AC-30 offline | plan FS-19 | đổi tên mục + bỏ thẻ Your library là của FS-21; danh sách nguồn, Grant Access, offline là FS-19 |
| — | FS-12 (phiên Video Studio) | Video Studio iPad không có task ở đây; chỉ dùng chung `ShellLayout` (đọc) và K8 nếu phiên đó muốn |
| FS-18 (Mac) đọc lại | task 9, 13, 28 | `ShellLayout`, `SidebarItem`, `CommandCatalog` viết trung lập nền tảng (K6) để Mac dùng |

Task 1–12 (test khoá, ⚠️ độc lập, `ShellLayout`) **không chờ ai** — làm được ngay khi plan duyệt.

## 4. Đã chốt (planboard mac-ipad-v2) — kiến trúc

Duyệt 2026-10-04, một vòng; mọi dòng FS-21 theo đề xuất. Bảng phương án chi tiết: `.planboard/mac-ipad-plans/plan.json`
(bảng cũ). Mỗi dòng: lựa chọn — id trên board.

- **K1** — A: `NavigationSplitView` cho `.pinnedSidebar`/`.overlaySidebar`, giữ `TabView`/`LiquidGlassTabBar` cho `.phone`;
  `ShellLayout.resolve(windowWidth:idiom:)`, iPhone và Duo luôn `.phone` — **A20**.
- **K2** — A: modifier `.shellInspector` — cột `.inspector` 360 khi ghim, sheet 576 có Done ở 700–1099, sheet như iPhone
  ở `.phone` — **A20**.
- **K3** — A: `SidebarItem` (Domain) ↔ `AppTab` hai chiều, `selectedTab` suy ra — **A20**.
- **K4** — A: Viewer **đẩy** trong `NavigationStack` của cột detail, sidebar ẩn khi vào, trả lại khi Back; Settings giữ
  `fullScreenCover`; iPhone giữ cover — **Q8** (mở trong cửa sổ). AC-37 ❓ → ✅.
- **K5** — A: `CommandCatalog` thuần ở Domain (mở rộng `PhotoCommand`), ngoại lệ New Window, Activity — **A21**.
- **K6** — A: kiểu thuần không import UIKit ở `ShotDex/Domain/Shell/`, view iOS ở `App/Shell/` — **A26**.
- **K7** — A: `.commands { CommandMenu }` trên `WindowGroup` + `FocusedValue`; phím trần 0–5/P/X/U giữ nút ẩn — **A21**.
- **K8** — A: `ToolInspectorLayout` chung cho Collage, Xuất collage, Resize, Combine Photos và inspector Editor — **A22**.

## 5. Tái dùng (cấm viết bản thứ hai)

| Có sẵn | Dùng cho |
|---|---|
| `SettingsLayout` (`Features/Settings/SettingsLayout.swift:23-50`) — hàm thuần + `selection(afterExpanding:)` / `path(afterCollapsing:)` | mẫu cho `ShellLayout` và luật mang trạng thái qua mốc 700 (task 36) |
| `EditorLayoutMetrics.usesSidebar` 700×600 (`Domain/Editing/EditorLayoutMetrics.swift:151-166`), `usesRegularToolChrome` (`Features/Shared/ToolChromeEnvironment.swift`) | tầng D giữ ngưỡng riêng của nó; `ShellLayout` không thay nó (K1) |
| `SelectionBarModel` + `SelectionToolbarItems` | AC-8/9: chỉ đổi chỗ vẽ, cùng closure |
| `PhotoTileContextMenu`, `PhotoMarkKeyButtons`, `MarkKeyCommand` | menu nhấn giữ/chuột phải, phím trần |
| `PhotoCommand` (`Features/Shared/PhotoCommand.swift`) | hạt giống `CommandCatalog` (K5) |
| `AlbumDropTarget` + `PhotoDropPayload` (`Features/Albums/AlbumDropTarget.swift:26`), `PhotoDragItem` | thả ảnh lên hàng album sidebar |
| `SwipeSelection` (`Domain/Selection/SwipeSelection.swift`) | toán dải cho ⇧-chạm |
| `PhotoGridSections` / `GridSectionHeader` (`Domain/Grid/PhotoGridSections.swift:53-118`) | đầu nhóm ngày (AC-50) |
| `GridDensity` (`Domain/Grid/GridDensity.swift`) | số cột — chỉ thêm tham số, không hàm thứ hai (Q1) |
| `LibraryModel.indexProgress` / `IndexProgress` | dòng phụ toolbar + chân sidebar |
| `PhotoEditorSaveSheet`, `EditorSidebarSection` (nhóm gập), `EditorFilmstrip`, `EditorHistoryPanel` | Editor iPad: đổi vật chứa, giữ nội dung |
| `CollageUnplacedTray`, `CompressionController` | khay trái Collage; tiêu đề nút Resize tính ở controller, không ở view |
| `StatisticsScreen.columnCount(forWidth:)` | giữ; chỉ đo lại ở 1016 |
| `AppAccent` (không là tint) | Settings không amber |
| `Tools/ui-drive`, `Tools/sim-shot`, `Tools/design-board` | bằng chứng |

## 6. Chỗ nào trong code

| File | Đụng gì | Tầng | Mới / sửa |
|---|---|---|---|
| `Domain/Shell/ShellLayout.swift` | `resolve(windowWidth:idiom:)`, hằng 700/1100, `inspectorWidth` 360, `sidebarWidth` 320 | Domain | mới |
| `Domain/Shell/SidebarItem.swift` | nhóm/hàng, `tab` ↔ `AppTab`, `acceptsDrop(_:)` | Domain | mới |
| `Domain/Shell/CommandCatalog.swift` | K5; ngoại lệ nền tảng | Domain | mới (từ `PhotoCommand`) |
| `Domain/Shell/ToolbarSubtitle.swift`, `Domain/Selection/ModifierTapSelection.swift` | AC-47/48, AC-44/45 | Domain | mới |
| `Domain/Grid/GridDensity.swift` | tham số shell / inspector (Q1) | Domain | sửa |
| `App/RootTabView.swift` | rẽ `ShellLayout`: `.phone` giữ cây cũ, còn lại `ShellSplitView` | App | sửa |
| `App/Shell/ShellSplitView.swift`, `ShellSidebar.swift`, `ShellInspector.swift` (modifier K2), `ShellCommands.swift` (K7) | khung | App | mới |
| `App/AppNavigation.swift` | `sidebarSelection`, `isSidebarVisible`, khôi phục | App | sửa |
| `App/Glass/LiquidGlassTabBar.swift` | chỉ còn `.phone` | App | sửa nhỏ |
| `Features/Library/LibraryScreen.swift`, `SelectionBarViews.swift`, `SearchSuggestionsScreen.swift`, `SearchRecentsModel.swift`, `AdvancedSearchSheet.swift` | toolbar, chọn, search popover, nháp | Features | sửa |
| `Features/Library/LibraryListView.swift`, `LibraryListModel` (sắp cột) | List mode | Features | mới |
| `Features/Shared/PhotoGridCollectionView.swift` | kéo không cần chọn (Q3), ⌘/⇧-chạm, header nhóm | Features | sửa |
| `Features/Library/PhotoDetailScreen.swift`, `MetadataPanel.swift` | toolbar, inspector, sáng/tối, phím I/⌘I, filmstrip, Rotate/Print | Features | sửa |
| `Features/Shared/PhotoPrinter.swift` | `UIPrintInteractionController` | Features | mới |
| `Features/Editing/PhotoEditorScreen.swift`, `EditorSidebar.swift`, `EditorToolBar.swift` | toolbar segmented, inspector 360, tên Adjust/Crop | Features | sửa |
| `Features/Shared/ToolInspectorLayout.swift` | K8 | Features | mới |
| `Features/Collage/CollageScreen.swift`, `CollageExportScreen.swift`, `Features/Editing/CompressionScreen.swift`, `CompressionController.swift` | inspector 360, nút toolbar | Features | sửa |
| `Features/Duplicates/DuplicatesScreen.swift`, `Features/Statistics/ChartCard.swift` | Keep All, đổi kiểu biểu đồ (Q6) | Features | sửa |
| `Features/Settings/SettingsSection.swift`, `SettingsScreen.swift`, `SettingsLibraryCard.swift` | Sources | Features | sửa |
| `Features/Onboarding/OnboardingScreen.swift`, `Features/Library/EmptyLibraryView.swift` | câu 4, Continue 320, thư viện trống | Features | sửa / mới |
| `ShotDexUITests/UIDriverTests.swift` | `ctrl`, `modifierTap`, `pinch` | Test | sửa |
| `ShotDexTests/ShellLayoutTests.swift`, `SidebarItemTests.swift`, `CommandCatalogTests.swift`, `ToolbarSubtitleTests.swift`, `ModifierTapSelectionTests.swift`, `GridDensityTests.swift` | AC thuần | Test | mới / sửa |
| `ShotDexUITests/scripts/fs21-*.json` | route dump | Test | mới |

Logic: chọn bố cục, nhóm sidebar, luật nhận thả, tập lệnh, dòng phụ, ⌘/⇧-chạm, số cột — đều ở Domain, có test.
View chỉ đọc. Không thêm bảng, không migration: FS-21 **không ghi dữ liệu người dùng** mới (kiểu biểu đồ đã nằm
trong `stat_charts.config`; trạng thái cửa sổ ở `@SceneStorage`).

## 7. Thứ tự task

Một task = một commit `feat(FS-21): AC-n …`; `/build` sau mỗi commit; đụng UI thì `/screens` (iPad 26.5 ngang + dọc,
iPad 18.6, iPhone 17 khi AC ghi) và `design-parity` theo board. Cột "Tài liệu" = dòng của
[03-spec-deltas](../02-functional-spec/FS-21-ipad-mac-style/03-spec-deltas.md) (hoặc FS-18 07) sửa **trong cùng commit**.

| # | Task | AC | Test / bằng chứng | Tài liệu cùng commit | Chờ |
|---|---|---|---|---|---|
| 0 | Driver: `key` thêm `ctrl`; bước `modifierTap` (`XCUIElement.perform(withKeyModifiers:)` — xác minh API có trên iOS ở đầu task; không có thì AC-44/45 kiểm tay); bước `pinch` | (bằng chứng cho 12, 13, 44–46, 49) | chạy lại một route cũ | — | — |
| **✅** | | | | | |
| 1 | Khoá menu nhấn giữ = chuột phải, không vào chọn | AC-10, AC-16 | `fs21-context-menu.json` (longPress 0,6 s, dump menu, 0 ô chọn); AC-16 kiểm tay | — | — |
| 2 | Khoá phím 4 trên lựa chọn | AC-14 | `fs21-keys.json` bước `key "4"` + dump nhãn ô | — | 0 |
| 3 | Khoá ⋯ 18.6 = 26.5 | AC-28 | `fs21-selection-menu.json` trên 26.5 và 18.6, so dump (`ios26-parity`) | — | — |
| 4 | Khoá Editor dọc có cột | AC-35 | `EditorPanelLayoutTests.portraitIPadsKeepTheColumn` (1032×1376, 834×1210) | — | — |
| 5 | Khoá Settings không amber | AC-36 | `design-parity IP_Settings` sáng + tối; script đếm pixel amber trên `sim-shot` | — | — |
| 6 | Khoá Statistics 3 cột ở 1016 | AC-43 | `StatisticsLayoutTests.threeColumnsAt1016` + dump | — | — |
| **⚠️ độc lập** | | | | | |
| 7 | Nhãn ⋯ chọn nhiều theo Q2 | AC-11 | `SelectionMenuOrderTests` trên `PhotoCommand.albumSelectionMenu` (catalog chưa có); dump | FS-21 01 §5 + AC-11 → "Adjust Date & Time…" / "Adjust Location…" (Q2) | — |
| 8 | iPhone/Duo: Edit → Adjust, Transform → Crop; panel theo Q5 | AC-54 | `EditorToolTitleTests`; dump iPhone 17 | FS-03.13 · 13a · 13b · 17b · 17c (03 §4) | — |
| 9 | Keep All N Photos + đổi kiểu biểu đồ theo Q6 | AC-56 | `ChartKindToggleTests` (bar↔donut, line↔bar, lưu qua `ChartStore`); dump iPhone | FS-06.06/06b, FS-07.01b (03 §4) | — |
| **A khung** | | | | | |
| 10 | `ShellLayout.resolve(windowWidth:idiom:)` | AC-21 | `ShellLayoutTests` 699/700/1099/1100 **+ Duo 951 idiom phone → `.phone`** | DESIGN §10.1g (đã có), NF-05 §1 luật 3 · §3 | — |
| 11 | Cỡ cửa sổ thật, chiều cao không đổi kết quả | AC-21b | `ShellLayoutTests` 5 cỡ | — | 10 |
| 12 | Khoá Split View 1/3 = bố cục iPhone | AC-20 | `ShellLayoutTests.splitViewThirdIsPhone` + kiểm tay | — | 10 |
| 13 | `ShellSplitView` + `SidebarItem` 4 nhóm (Sources: một hàng Photos Library) | AC-1 | `SidebarItemTests` (Library 5 hàng, Utilities 7 hàng, đủ 4 nhóm); `fs21-shell.json` + `design-parity Main` | FS-01 README; DESIGN §2 tầng C, §6 · §9; docs/README đầu file | K1, K3, K6 |
| 14 | Hàng sidebar đổi nội dung | AC-2 | route; `SidebarItemTests.tabProjection` | — | 13 |
| 15 | Hide/Show Sidebar | AC-3 | route dump x mép trái | — | 13 |
| 16 | ⌃⌘S | AC-13 | route `key s` ctrl,cmd ×2 | — | 0, 15 |
| 17 | Sidebar phủ ở 700–1099 | AC-25 | route dọc (12 s + `sim-shot`) | — | 13 |
| 18 | VoiceOver sidebar | AC-29 | dump nhãn/trait; kiểm tay | NF-06 §1 | 13 |
| 19 | Vùng chạm 44 nút sidebar | AC-6 | dump khung `hittable` | NF-06 §1 | 13 |
| 20 | Pre-26: sidebar/nav bar hệ thống | AC-27b | 18.6 dump + `sim-shot` | DESIGN §6 · §9 | 13 |
| 21 | Parity tập nhãn 26.5 ↔ 18.6 | AC-27 | `ios26-parity` | — | 20 |
| 22 | Dynamic Type sidebar | AC-31 | route AX3 + dump | — | 13 |
| **B toolbar, search, lệnh** | | | | | |
| 23 | Toolbar Library: tiêu đề + dòng phụ, ≤ 3 cụm, Select | AC-5 | dump; `design-parity Main` | FS-01.02 §1–§3 | 13 |
| 24 | `ToolbarSubtitle` (đếm ↔ tiến độ theo sidebar) | AC-47, AC-48 | `ToolbarSubtitleTests`; route dọc + ngang | BD-03.04 | 23 |
| 25 | Ô search trên toolbar + ⌘F | AC-12 | route `key f` cmd; dump focus | FS-01.03 | 23, 0 |
| 26 | Popover gợi ý 400, Recents dạng hàng | AC-51 | dump; `design-parity IP_Search` | FS-01.03b §5, AC-16, AC-20 | 25 |
| 27 | Advanced Search form sheet + Discard Changes? | AC-41 | route chạm ngoài; `AdvancedSearchDraftTests` (cờ nháp ở model) | FS-01.05b §3–§4, AC-26 | — |
| 28 | `CommandCatalog` (K5); 3 builder đọc nó | AC-38 | `CommandCatalogTests.iPadAndPhoneShareEveryCommandButTwo` | NF-05 §1 luật 1 | K5 |
| 29 | Menu bar 8 menu (K7) | AC-15 | kiểm tay + ảnh bảng ⌘; `CommandCatalogTests.menuBarMatchesBoard` | DESIGN §10.3 (FS-18 07 §1) | 28, K7 |
| **C inspector, chọn, kéo** | | | | | |
| 30 | Số cột theo Q1 | AC-49 | `GridDensityTests` (7/6 ở 1016/656); route pinch | DESIGN §10.1c; FS-01.01b | Q1, 0 |
| 31 | `.shellInspector` (K2) ở Library | AC-4 | dump x 1016, số cột | — | 30, K2 |
| 32 | Chọn nhiều lên toolbar + inspector tóm tắt | AC-8 | `design-parity IP_LibrarySelect`; chạy lại task 2 cho phần inspector | FS-01.06 §1–§3 | 31, 28 |
| 33 | Done trả toolbar + inspector | AC-9 | route | — | 32 |
| 34 | Xoay giữ lựa chọn, inspector đổi dạng | AC-23, AC-24 | `fs21-rotate.json` (12 s + `sim-shot`) | FS-01.07 | 31 |
| 35 | ⌘/⇧-chạm (`ModifierTapSelection`) | AC-44, AC-45 | `ModifierTapSelectionTests`; route `modifierTap` | FS-01.06 §1–§3 | 0, 32 |
| 36 | Mang trạng thái qua mốc 700 (`@SceneStorage` hàng, chỗ cuộn, lựa chọn) | AC-22 | `ShellRestorationTests` (thuần, theo `SettingsLayout`); kiểm tay Stage Manager | FS-01.07 | 13 |
| 37 | Kéo-thả lên sidebar (`SidebarItem.acceptsDrop`) | AC-17, AC-18, AC-19 | `SidebarItemTests.dropPolicy`; route `drag` | — | Q3, 13 |
| 38 | Đầu nhóm ngày · nơi · số ở khung | AC-50 | `PhotoGridSectionBuilderTests` (dòng có nơi + số); dump iPad vs iPhone | DESIGN §10.2 (FS-18 07 §1) | 13 |
| **D iPhone ⋯ (mọi thiết bị)** | | | | | |
| 39 | List mode (bảng sắp cột) | AC-55 (1/3) | `LibraryListSortTests` | FS-01.02 (03 §4) | 28 |
| 40 | Go to Date… | AC-55 (2/3) | `GoToDateTests` (ngày → index) | FS-01.02 | 28 |
| 41 | Rotate ↺/↻ + Print… (Viewer, lựa chọn) | AC-55 (3/3, đóng AC) | `PhotoRotationTests` (recipe quarter turn hai chiều); dump ⋯ | FS-02.04, FS-01.06 §3 | 28 |
| **E Viewer** | | | | | |
| 42 | Viewer theo sáng/tối mọi thiết bị | AC-52 | `sim-shot` sáng/tối iPad + iPhone, độ sáng nền > 0,9 | FS-02 README, FS-02.03b §2 | — |
| 43 | Viewer trong cửa sổ (K4), toolbar, Back đúng chỗ | AC-7 | `fs21-viewer.json` | FS-02 README · Chrome, FS-02.01b AC-7/10/12 | K4, 13 |
| 44 | I · ⌥⌘I · ⌘I Get Info | AC-46 | route `key` | FS-02.03 §3, FS-02.03b §1–§2 | 43, 0 |
| 45 | Info dọc = sheet 576 Done | AC-26 | route xoay | FS-02.03b AC-7 | 43, 31 |
| 46 | Inspector Viewer ở AX3 | AC-32 | route AX3 | — | 43 |
| 47 | Toolbar dọc ≥ 44 (Viewer + Editor) | AC-59 | dump `IPP1_Edit`, `IPP16` | — | 43, 48 |
| **F Editor, tầng D** | | | | | |
| 48 | Editor iPad: toolbar segmented, inspector 360 theo Q4 | AC-33 | `design-parity IP1_Edit` + `IPP1_Edit` | FS-03.17 §3, FS-03.17a | Q4, 43 |
| 49 | Save Edit form sheet 600 | AC-34 | `design-parity IP12_Save` | — | 48 |
| 50 | `ToolInspectorLayout` (K8) + Collage: khay trái, Before and After, ⋯ Discard | AC-57 | `design-parity IP_Collage`, `IPP21_Collage` | FS-11 §3; DESIGN §2 | K8 |
| 51 | Xuất collage inspector + toolbar | AC-40 | `design-parity IP_CollageExport` | FS-11b §1–§2, AC-1, AC-4 | 50 |
| 52 | Resize: inspector + nút toolbar đổi chữ | AC-39 | `CompressionTitleTests` (tiêu đề ở `CompressionController`) + dump | FS-03.07 §4, AC-11, AC-13 | 50 |
| 53 | Resize dọc giữ cột | AC-58 | `design-parity IPP23_Compress` | — | 52 |
| **G Settings, lần mở đầu, nguồn** | | | | | |
| 54 | Photo Library → Sources, bỏ thẻ Your library | AC-53 | `SettingsSectionTests`; dump iPhone + iPad | FS-08.01 §2–§3 · 01b §1 + AC, FS-08.02, FS-08.05 AC-3 (FS-18 07 §3) | — (pane: FS-19) |
| 55 | Done của Settings về hàng trước | AC-37 | route Trips → gear → Done | FS-08.05 AC-12 | K4 |
| 56 | Câu chào + Continue 320 | AC-60 | dump iPad + iPhone | FS-09 §2 | — |
| 57 | Continue → thư viện trống 3 thẻ; quyền ở Add Photos Library | AC-42 | `fs21-first-run.json` (cài mới, `systemTap` Limited) | FS-09 §2–§3 + AC-2; NF-04 (FS-18 07 §3) | FS-19 |
| 58 | Hàng nguồn offline đọc "offline" | AC-30 | dump nhãn | — | FS-19 |

**Không có task cho:** Trips 3 cột, Places inspector, trang album 764×150/159, Duplicates danh sách 360, Combine
Photos / Cull / cắt video (02b §2), phím "." và Space — spec có, AC không đo (cuối bảng AC). Đã chốt (A25): `/spec FS-21`
thêm AC trước, rồi plan thêm task; không tự làm.

## 8. Đã chốt (planboard mac-ipad-v2) — câu hỏi ⚠️

Số Q của plan này → id trên board. Không câu nào khác đề xuất.

- **Q1** (AC-49) — tài liệu đúng: 7 cột ở 1016, 6 khi mở inspector (656); `GridDensity` thêm tham số khung, không hàm thứ
  hai; iPhone, Duo không đổi — **Q5**.
- **Q2** (AC-11) — "Adjust Date & Time…" và "Adjust Location…" (giữ &, thêm …); sửa FS-21 01 §5 + AC-11 ở task 7 — **A23**.
- **Q3** (AC-17) — tài liệu đúng: nhấn giữ rồi kéo luôn, không cần Select; bật cả ở `.phone` — **Q6**.
- **Q4** (AC-33) — cột inspector 360 cố định bên phải: bỏ kéo rộng 280…420 và đổi bên; rail thay bằng segmented; giữ
  ghim ảnh tham chiếu và Hide Inspector; History vào sidebar Presets — **Q7**.
- **Q5** (AC-54) — code đúng (264); AC-54 thành "panel không đổi", dọn 4 comment 246 cùng commit — **A24**.
- **Q6** (AC-56) — giữ pill, đổi chữ thành "Keep All N Photos", AC-56 đo pill; đổi kiểu biểu đồ làm như spec — **A23**.
- **Màn chưa có AC** (Trips, Places, trang album, Duplicates, Combine, Cull, cắt video, phím . và Space) — `/spec FS-21`
  thêm AC trước, rồi plan thêm task — **A25**.

**Đổi so với bản nháp:** không task nào đổi; AC-37 thành ✅ theo K4; task cho các màn của A25 thêm sau `/spec` (chưa
đếm trong 59).

## 9. Rủi ro

| # | Rủi ro | Xác suất | Xử lý |
|---|---|---|---|
| R1 | **Duo trong 951×669** rộng hơn 700 → hàm chỉ đo bề rộng sẽ đưa Duo vào khung sidebar (spec nói Duo không đổi) | cao nếu quên | `idiom` là tham số bắt buộc của `ShellLayout.resolve`; test Duo trong task 10; `device-layout` trên Duo ở task 13 |
| R2 | Hai cây gốc (`TabView` ↔ split) — qua mốc 700 mất `@State` (lựa chọn, chỗ cuộn, sheet đang mở) | cao | trạng thái sống trong `LibraryModel`/`AppNavigation` (đã ở gốc), không trong view; task 36 có test thuần |
| R3 | Bài học cũ: cover/sheet gắn sau overlay làm SwiftUI vỡ vòng preference (`RootTabView.swift:217-219`); sheet không mở trên tab `.search` (memory) | trung bình | giữ thứ tự modifier; ô search toolbar không còn là tab ở khung — chỉ `.phone` giữ đường token cũ |
| R4 | iPadOS 26 tự gom nút toolbar thành viên kính và có thể đẩy nút vào tràn khi hẹp | trung bình | AC-5 đo ≤ 3 cụm ở 1376 và 1032; mọi lệnh còn trong ⋯ (01b §2) |
| R5 | Bộ nhớ: Viewer đẩy trong cột (K4-A) giữ lưới 55k sống cạnh pager | thấp | lưới vốn không unmount khi cover; đo `memory-leak` ở task 43 |
| R6 | Concurrency: `FocusedValue` + `.commands` gọi hành động model từ menu bar | thấp | hành động `@MainActor`; `swift-concurrency` ở task 29 |
| R7 | 120 board đi trước code — lệch tích tụ, board `IPP*` dọc vừa sửa 36 → 44 | cao | `design-parity` theo board ở mọi task UI; không đóng AC khi board còn lệch |
| R8 | Dữ liệu | không có | không migration, không bảng mới; kiểu biểu đồ đi qua `ChartStore.upsert` sẵn có |
| R9 | PhotoKit | thấp | Continue không còn hỏi quyền (task 57) — `.notDetermined` thành trạng thái thường của thư viện trống, không còn cổng Onboarding duy nhất (`RootTabView.swift:145`) → `photokit-guard` ở task 57 |
| R10 | Hai phiên cùng checkout (memory) — FS-12 sửa `VideoStudio*`, FS-19 sửa `AppDatabase`/Settings | trung bình | stage đường dẫn cụ thể; task 54 chờ FS-19 commit pane Sources |

## 10. Phản biện (điền sau khi chạy `challenger`)

| Phản đối | Trả lời / thay đổi |
|---|---|
| — | chưa chạy |

## 11. Cách chứng minh là xong

- Test thuần: `ShellLayoutTests`, `SidebarItemTests`, `CommandCatalogTests`, `ToolbarSubtitleTests`,
  `ModifierTapSelectionTests`, `ShellRestorationTests`, `GridDensityTests`, `StatisticsLayoutTests`,
  `EditorPanelLayoutTests`, `PhotoGridSectionBuilderTests`, `CompressionTitleTests`, `ChartKindToggleTests`,
  `SettingsSectionTests`, `PhotoRotationTests`, `LibraryListSortTests`, `GoToDateTests`.
- Route `ShotDexUITests/scripts/fs21-*.json`: `shell`, `keys`, `context-menu`, `selection-menu`, `viewer`, `rotate`,
  `first-run`, `drag`; xoay → `wait` 12 s + burst `Tools/sim-shot` (CLAUDE.md).
- Màn chụp: iPad 13" 26.5 ngang + dọc, iPad 13" 18.6 ngang, iPhone 17 (AC-52–56, 60), Duo trong (khẳng định **không
  đổi**), sáng + tối ở Viewer/Settings.
- `design-parity` theo board: `Main`, `IP_LibrarySelect`, `IP_Search`, `IP_Settings`, `IP_Viewer`, `IP1_Edit`,
  `IPP1_Edit`, `IP12_Save`, `IP_Collage`, `IPP21_Collage`, `IP_CollageExport`, `IPP23_Compress`, `IP_Onboarding`, `IP_EmptyLibrary`.
- Kiểm tay (ghi vào FS-21 04 cột "Chứng minh bằng"): AC-15, AC-16, AC-20, AC-22, AC-29/30 (VoiceOver).
- Tài liệu: mỗi dòng của 03-spec-deltas đi với task ở §7; FS-21 04 cột "Chứng minh bằng" sửa từng AC khi xong.
- Agent giai đoạn Deploy: `device-layout` (iPad/iPhone/**Duo**), `ios26-parity` (AC-27/28), `ipad-multitasking`
  (Split View, Stage Manager, phím, con trỏ, kéo-thả), `ipad-ux-review`, `hig-components` (toolbar, sidebar, menu),
  `a11y-voiceover` (AC-29–32), `design-parity`, `component-consistency` (K8 + 3 builder lệnh), `swift-concurrency`
  (K7), `memory-leak` (K4), `photokit-guard` (task 57), `copy-consistency` (Q2, Adjust/Crop, Sources). Không cần
  `data-migration`, `extension-boundary` (không đụng kit/extension).
- Dòng `Tiến độ` của intent: điều phối viên sửa (plan này không đụng file intent) —
  `**chưa làm** (2026-10-04) — plan đã duyệt (planboard mac-ipad-v2), 59 task`.
