# Kế hoạch FS-21 — bảng đối chiếu AC ↔ code

Phần tách của [2026-10-04-fs21-ipad-mac-style.md](2026-10-04-fs21-ipad-mac-style.md). Đường dẫn tương đối với
`ShotDex/`. Đọc code ngày 2026-10-04 (HEAD sạch). Ký hiệu: ✅ code đã đạt (chỉ viết test khoá) · ⚠️ lệch, cần
người dùng quyết (câu hỏi ở §8 plan chính) · ❌ chưa có (quyết định sản phẩm đã chốt ở SPEC-DECISIONS, chỉ còn làm)
· ❓ chưa kết luận được, có lý do.

**Tổng: 8 ✅ · 6 ⚠️ · 47 ❌ · 1 ❓ = 62.**

Luật xếp loại dùng ở đây: khi code làm khác spec **nhưng** khác biệt đó đã được người dùng chốt trong
`.planboard/macos-app/SPEC-DECISIONS.md` (Viewer sáng/tối, Continue không hỏi quyền, phím I bật/tắt, đầu nhóm ngày…)
thì xếp ❌, không hỏi lại. ⚠️ chỉ dành cho chỗ code có một hành vi **cố ý** mà quyết định chưa nói tới, hoặc spec tự mâu thuẫn.

## 1. Khung, sidebar, toolbar

| AC | TT | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 sidebar 320, 4 nhóm, không tab bar | ❌ | gốc là `TabView` 4 tab (`App/RootTabView.swift:189-216`), pre-26 là `LiquidGlassTabBar` overlay đáy (`:306-326`); không `NavigationSplitView` nào ngoài Settings; `AppNavigation` chỉ có `selectedTab: AppTab` (`App/AppNavigation.swift:9`) | task 13 (khung + nhóm sidebar). Nhóm Sources chỉ có hàng Photos Library tới khi FS-19 giao nguồn |
| AC-2 chạm Statistics đổi nội dung, không Back | ❌ | tab, không có hàng sidebar | task 14 |
| AC-3 Hide/Show Sidebar | ❌ | — | task 15 |
| AC-4 inspector 360, lưới 7 ↔ 6 cột | ❌ | không có inspector app nào (360 chỉ là `settingsSidebarWidthMax`, `App/Theme/AppTheme.swift:63`); số cột: xem AC-49 ⚠️ | task 31 (sau quyết định AC-49, task 30) |
| AC-5 toolbar ≤ 3 cụm + search + Select | ❌ | toolbar Library hôm nay: gear + token "Indexing NN%" trái, ngày đang xem ở giữa, Filter + Select phải (`Features/Library/LibraryScreen.swift:1099-1166`) | task 23 |
| AC-6 vùng chạm 44 cho nút sidebar vẽ 32/28 | ❌ | không có sidebar | task 19 |
| AC-7 Viewer → Back về đúng ô 600, sidebar hiện lại | ❌ | Viewer là `fullScreenCover` (`LibraryScreen.swift:154-158`), nút X 52 (`App/Glass/GlassIconButton.swift:27`); chỗ cuộn được giữ vì lưới không unmount, nhưng không có Back/sidebar | task 43 (theo K4) |

## 2. Chọn nhiều, menu, bàn phím, con trỏ

| AC | TT | Bằng chứng | Việc |
|---|---|---|---|
| AC-8 Select → toolbar Compare · Edit · Share · ⋯ · Delete · Done, inspector "5 Photos" | ❌ | đủ lệnh nhưng chỗ khác: Compare/Edit trái nav bar, ⋯ và × phải (`Features/Library/SelectionBarViews.swift:172-306`), Share · "Show Selected (N・size)" · Delete ở thanh đáy (`:64-90`); không inspector | task 32. Tái dùng `SelectionBarModel` (`App/SelectionBarModel.swift:22-101`) — chỉ đổi chỗ vẽ |
| AC-9 Done về như AC-5, inspector về trạng thái trước | ❌ | × thay vì Done (`SelectionBarViews.swift:298-304`); không inspector | task 33 |
| AC-10 nhấn giữ = menu ngữ cảnh, không vào chọn, không cột phím | ✅ | `contextMenuConfigurationForItemAt` khi không chọn (`Features/Shared/PhotoGridCollectionView.swift:1389-1406`); recognizer nhấn-giữ-để-chọn tắt khi có menu (`:457-458`); menu dựng bởi `PhotoTileContextMenu` (`Features/Shared/PhotoTileContextMenu.swift:33-125`) không đặt `discoverabilityTitle`/phím | task 1: route khoá |
| AC-11 ⋯ chọn nhiều đúng thứ tự FS-01.06 §3 + 4 dòng | ⚠️ | một nguồn `SelectionToolbarItems` (`SelectionBarViews.swift:209-291`, nhóm `:316-390`) có đủ Select All · Favorite · Adjust… · Hide-nhóm-cuối, nhưng nhãn **"Adjust Date & Time" / "Adjust Location"** không "…", spec viết "Adjust Date and Time…" (`:344`, `:351`); không có Print… (FS-21 03 §4) | Q2; task 7 |
| AC-12 ⌘F vào ô search toolbar | ❌ | không có ⌘F (không `keyboardShortcut("f", .command)` nào); search là tab `role: .search` (`RootTabView.swift:200-212`) / sheet pre-26 (`:388-400`) | task 25 |
| AC-13 ⌃⌘S hai lần | ❌ | không có | task 16 |
| AC-14 phím 4 khi chọn 1 ảnh 2★ | ✅ (phần phím) | `PhotoMarkKeyButtons` 0–5/P/X/U trong chế độ chọn (`SelectionBarViews.swift:53-54`, `Features/Shared/PhotoMarkMenus.swift:122-141`, `Domain/Marks/MarkKeyCommand.swift:24-30`) | task 2: route khoá phần ô; phần "inspector ghi 4★" chứng minh lại ở task 32 |
| AC-15 menu bar 8 menu khớp `IP_MenuBar` | ❌ | `ShotDexApp.swift:27-28` chỉ một `WindowGroup`, không `.commands`/`CommandMenu`/`UIKeyCommand`/`buildMenu` | task 29 (sau catalog, task 28) |
| AC-16 chuột phải = cùng menu AC-10 | ✅ | UIKit mở cùng `UIContextMenuConfiguration` cho chuột phải của trackpad — cùng nguồn `contextMenuConfigurationForItemAt` (`PhotoGridCollectionView.swift:1389`) | gộp task 1 (cùng một menu, AC-16 chỉ là đường vào thứ hai — tách ra thì không có gì để commit riêng); kiểm tay |

## 3. Kéo-thả lên sidebar

| AC | TT | Bằng chứng | Việc |
|---|---|---|---|
| AC-17 kéo 1 ảnh (không ở chế độ chọn) lên album | ⚠️ | `itemsForBeginning` **chỉ** chạy khi đang chọn và kéo cả lựa chọn (`PhotoGridCollectionView.swift:1092-1102`, `:1127-1140`) — cố ý; đích thả có sẵn `AlbumDropTarget` `.dropDestination(for: PhotoDropPayload.self)` (`Features/Albums/AlbumDropTarget.swift:26`) | Q3; task 37 |
| AC-18 kéo một trong 3 ảnh đang chọn → cả 3 | ❌ | phần kéo-cả-lựa-chọn có sẵn (`:1127-1140`); thiếu hàng sidebar nhận thả | task 37 (gộp 17–19: một predicate `SidebarDropPolicy.accepts`, AC-19 là nhánh từ chối của chính nó) |
| AC-19 smart album / Statistics không sáng | ❌ | — | task 37 |

## 4. Bề rộng cửa sổ và xoay

| AC | TT | Bằng chứng | Việc |
|---|---|---|---|
| AC-20 Split View 1/3 → bố cục iPhone | ✅ | hôm nay **mọi** bề rộng iPad là bố cục tab (`RootTabView.swift:144-151`, không đọc bề rộng) | task 11: khoá bằng `ShellLayoutTests` ngay sau khi hàm có (không viết test trước được — chưa có hàm để gọi) |
| AC-21 699/700/1099/1100 | ❌ | không có hàm chọn bố cục cho gốc app; các hàm cùng kiểu: `VideoStudioWindowClass.resolve` (`Domain/Video/VideoStudioWindowClass.swift:31`, ngưỡng 600), `EditorLayoutMetrics.usesSidebar` (`Domain/Editing/EditorLayoutMetrics.swift:166`, 700×600) | task 9 |
| AC-21b 5 cỡ cửa sổ, chiều cao không đổi kết quả | ❌ | như trên | task 10 |
| AC-22 Stage Manager 1200 → 650 giữ Statistics + chỗ cuộn | ❌ | chỉ `@SceneStorage("scene.selectedTab")` (`RootTabView.swift:37`); chỗ cuộn, lựa chọn không lưu | task 36 |
| AC-23 xoay ngang→dọc khi chọn 5 + inspector | ❌ | — | task 34 (gộp 23–24: cùng một luật "inspector đổi dạng theo `ShellLayout`, lựa chọn sống trong model"; hai chiều của một phép đổi) |
| AC-24 xoay về | ❌ | — | task 34 |
| AC-25 sidebar phủ ở dọc, chạm lưới đóng | ❌ | — | task 17 |
| AC-26 Viewer xoay dọc → sheet 576 có Done | ❌ | Info là `.sheet` detents medium/large, không Done (`Features/Library/PhotoDetailScreen.swift:372-379`, `Features/Library/MetadataPanel.swift:46`) | task 45 |

## 5. iOS trước 26 và truy cập

| AC | TT | Bằng chứng | Việc |
|---|---|---|---|
| AC-27 18.6: tập nhãn bằng 26.5 | ❌ | — | task 21 |
| AC-27b 18.6: sidebar hệ thống x 0, 320, nav bar thường | ❌ | pre-26 hôm nay là tab bar kính tự vẽ (`App/Glass/LiquidGlassTabBar.swift:46-128`) | task 20 |
| AC-28 18.6: ⋯ cùng dòng như 26.5 | ✅ | một builder `SelectionToolbarItems` dùng cho cả hai nhánh (`SelectionBarViews.swift:209-291`), không `#available` bên trong menu | task 3: route `ios26-parity` khoá |
| AC-29 VoiceOver hàng sidebar | ❌ | — | task 18 |
| AC-30 ổ offline đọc "offline" | ❌ | không có mô hình nguồn (không `PhotoSource`/bảng sources; gần nhất `file_servers`, `Data/Database/AppDatabase.swift:449-461`) | task 58, **chờ plan FS-19** |
| AC-31 Accessibility 3: sidebar không cắt | ❌ | — | task 22 |
| AC-32 Accessibility 3: inspector Viewer | ❌ | — | task 46 |

## 6. Từng màn

| AC | TT | Bằng chứng | Việc |
|---|---|---|---|
| AC-33 Editor ngang: toolbar Adjust · Crop · Mask · Heal · Markup, Save phải, inspector 360 | ⚠️ | editor rộng là bản 2026-09-22: băng lệnh mờ đục hết ngang (`Features/Editing/PhotoEditorScreen.swift:2179-2323`) + **rail dọc 48** (`EditorToolRail`, `Features/Editing/EditorSidebar.swift:102-191`, `EditorLayoutMetrics.swift:245`) + cột **kéo được 280…420** mặc định 320, chọn trái/phải, ẩn được, lưu UserDefaults (`EditorLayoutMetrics.swift:172-173`, `PhotoEditorScreen.swift:1500-1526`, `EditorSidebar.swift:8`); tên "Edit" / "Crop & Geometry" (`EditorSidebar.swift:53-80`, `Features/Editing/PhotoEditorController.swift:119-124`); nhóm gập được đã có (`EditorSidebarSection`, `EditorSidebar.swift:200-296`); không đĩa nổi trên ảnh | Q4; task 48 |
| AC-34 Save → sheet Save Edit 600 | ❌ | `PhotoEditorSaveSheet` đủ Save Changes · Save Copy · JPEG/HEIC · Metadata (`PhotoEditorScreen.swift:3645-3770`) nhưng `.presentationDetents([.medium, .large])`, không form sheet 600 (`:927-970`) | task 49 (FS-03.17 D6 đã chốt) |
| AC-35 Editor dọc giữ cột | ✅ (phần cột) | `usesSidebar` = rộng ≥ 700 và cao ≥ 600, bỏ luật ngang từ 2026-09-22 (`EditorLayoutMetrics.swift:151-166`) → 1032×1376 và 834×1210 đều có cột | task 4: test khoá; phần "PASS `IPP1_Edit`" chứng minh ở task 48 |
| AC-36 Settings chiếm cửa sổ, sidebar 320 + Done, 0 amber, công tắc xanh | ✅ | `fullScreenCover` (`App/SettingsSheet.swift:30-34`), split view `.balanced` ở regular (`Features/Settings/SettingsScreen.swift:274-289`), cột 320 (`AppTheme.swift:57`), Done (`SettingsScreen.swift:472-477`); không có `AccentColor.colorset` nên tint là hệ thống, `AppAccent` không phải tint (`App/Theme/AppAccentTheme.swift:4-11`) | task 5: `design-parity IP_Settings` + đếm pixel amber. Ngoài AC: `Features/Settings/CameraDatabaseScreen.swift:53,80` dùng `\.appAccent` → `REVIEW_QUEUE.md` (FS-08.01b AC-9) |
| AC-37 Settings mở từ Trips → Done → về Trips cùng chỗ cuộn | ❓ | hôm nay đúng nhờ cover phủ lên tab đang sống; sau đổi khung, đúng hay không **tuỳ K4** (Settings còn là cover hay thành đích của sidebar) | chốt sau K4; task 55 |
| AC-38 bộ lệnh iPad = iPhone trừ 2 ngoại lệ | ❌ | bốn builder rời: ⋯ chọn (`SelectionBarViews.swift:209-390`), menu ô (`PhotoTileContextMenu.swift:33-125`), ⋯ Viewer (`PhotoDetailScreen.swift:760-912`), không menu bar; có sẵn một danh sách thứ tự `PhotoCommand.albumSelectionMenu` (`Features/Shared/PhotoCommand.swift:68`) | task 28 (K5) |
| AC-39 Resize: nút toolbar đổi "… and Delete Originals" | ❌ | form một cột ≤ 700 (`Features/Editing/CompressionScreen.swift:117-140`), nút trong cuộn (`:173-197`), tiêu đề không đổi theo Delete Originals (`:183`, công tắc `:324-344`) | task 52 |
| AC-40 Xuất collage: Share… + Save to Photos trên toolbar, inspector 360 | ❌ | một cột, không Share (`Features/Collage/CollageExportScreen.swift:8-293`, Save `:198-253`) | task 51 |
| AC-41 Advanced Search có nháp: chạm ngoài → Discard Changes? | ❌ | `.sheet` detents large (`LibraryScreen.swift:147-153`), Cancel = `dismiss()` (`Features/Library/AdvancedSearchSheet.swift:102-111`), không `interactiveDismissDisabled` | task 27 |
| AC-42 Continue → thư viện trống 3 thẻ; quyền ở Add Photos Library | ❌ | Continue gọi `requestAuthorization()` (`Features/Onboarding/OnboardingScreen.swift:22`); gốc hiện Onboarding khi `.notDetermined` (`RootTabView.swift:145-146`); trống = `ContentUnavailableView` "No Photos" (`LibraryScreen.swift:867-871`) | task 57, **thẻ Folder/Server chờ FS-19** |
| AC-43 Statistics 3 cột 328, Insights 1016 | ✅ | `columnCount(forWidth:)` ≥ 320, 2…3 (`Features/Statistics/StatisticsScreen.swift:107-124`), Insights hết bề rộng (`:198-204`) | task 6: test số + đo dump (±1 có thể lệch do lề — nếu lệch, thành việc của task 23 khung) |

## 7. Từ các quyết định 2026-10-04

| AC | TT | Bằng chứng | Việc |
|---|---|---|---|
| AC-44 ⌘/⇧-chạm khi chưa chọn → chọn đúng ô đó | ❌ | không `modifierFlags`/`EventModifiers` nào; pan chọn 1 ngón chỉ khi đang chọn (`PhotoGridCollectionView.swift:1426-1431`) | task 35 (gộp 44–45: cùng một `ModifierTapSelection.apply` thuần, hai trạng thái vào) |
| AC-45 ⇧ dải, ⌘ bật/tắt | ❌ | dải đã có toán ở `Domain/Selection/SwipeSelection.swift:18-40` (tái dùng phần dải) | task 35 |
| AC-46 I · I · ⌥⌘I · ⌘I | ❌ | `I` chỉ **mở** sheet (`PhotoDetailScreen.swift:714`); không ⌘I, không Get Info (chỉ link "Show All Raw Metadata", `MetadataPanel.swift:83-103`) | task 44 |
| AC-47 dọc, sidebar ẩn: dòng phụ = tiến độ index | ❌ | tiến độ là token "Indexing NN%" trên toolbar Library (`LibraryScreen.swift:881-905`, `:1124-1137`) từ `LibraryModel.indexProgress` (`Features/Library/LibraryModel.swift:167`) | task 24 (gộp 47–48: một hàm `ToolbarSubtitle.text(sidebarVisible:indexProgress:counts:)`) |
| AC-48 ngang, Hide Sidebar, index xong ≤ 2 s | ❌ | như trên | task 24 |
| AC-49 pinch đổi mật độ, inspector bớt cột, nhớ qua lần mở | ⚠️ | mật độ lưu `@AppStorage(gridColumns)` mặc định 3 (`LibraryScreen.swift:20`); `GridDensity.columns` (`Domain/Grid/GridDensity.swift:74-80`, scale 0.7) ra **11 cột ở 1016 và 7 ở 656** — board/spec nói 7 và 6; spec cũng nói "theo mật độ như §10.1c" → spec tự mâu thuẫn | Q1; task 30 |
| AC-50 đầu nhóm "Monday, September 28 · Kyoto · 48 photos" | ❌ | máy có sẵn (`PhotoGridSectionMode`, `Domain/Grid/PhotoGridSections.swift:53-118`; header 32 `GridSectionHeader`) nhưng Library truyền `.flat` (`LibraryScreen.swift:684-689`); header chỉ ngày, không nơi + số | task 38 |
| AC-51 popover Recents 400 dạng hàng | ❌ | 3 thẻ mọi thiết bị (`Features/Library/SearchRecentsModel.swift:25`, `SearchSuggestionsScreen.swift:179-191`) | task 26 |
| AC-52 Viewer sáng ở chế độ sáng (iPad + iPhone) | ❌ | ép tối: `.preferredColorScheme(.dark)` (`PhotoDetailScreen.swift:316`), `Color.black` nền (`:203`, `:1496`, `:2355`), glyph ⋯ trắng cứng (`:904-906`) | task 42 |
| AC-53 Settings mục 1 "Sources", không thẻ Your library | ❌ | `case photoLibrary` "Photo Library" (`Features/Settings/SettingsSection.swift:12,29`), thẻ "Your library" (`SettingsLibraryCard.swift:114`, `SettingsScreen.swift:654-676`) | task 54 (đổi tên + bỏ thẻ; nội dung pane là FS-19) |
| AC-54 iPhone: "Adjust", "Crop"; panel vẫn 246 | ⚠️ | tên "Edit"/"Transform" (`Features/Editing/EditorToolBar.swift:11-19`) → ❌ phần tên; nhưng panel phone **264/344/315**, không 246 (`EditorLayoutMetrics.swift:46-48`; 246 chỉ còn trong comment cũ) | Q5; task 8 |
| AC-55 iPhone ⋯: Grid/List, Go to Date…, Rotate ×2, Print… | ❌ | không List mode, Go to Date, Print (`UIPrintInteractionController` 0 kết quả); xoay chỉ có trong editor, chỉ chiều kim (`PhotoEditorController.swift:2474-2478`) | task 39–41 (List · Go to Date · Rotate+Print) — tách vì ba tính năng khác nhau; AC đóng ở task cuối |
| AC-56 iPhone: "Keep All 3 Photos" ở ⋯ nhóm; đổi kiểu biểu đồ còn sau mở lại | ⚠️ | Duplicates **không có ⋯ nhóm**, có pill "Keep all"/"Keeping all" (`Features/Duplicates/DuplicatesScreen.swift:827-833`, `:921`) — iPhone đã có chức năng, khác chỗ và chữ; kiểu biểu đồ chỉ đổi được trong editor biểu đồ (`Features/Statistics/ChartEditorSheet.swift:160-165`), `ChartKind` lưu trong `stat_charts` (`Data/Database/ChartStore.swift:16`) | Q6; task 9 |
| AC-57 Collage: khay trái, Before and After, ⋯ Discard | ❌ | khay có nhưng là dải 48 trong cột (`Features/Collage/CollageScreen.swift:260-266`, `:630`); Discard là hộp khi Back (`:122-123`, `:392-399`); không Before/After (`CollageCommandBand`, `:478-499`) | task 50 (kèm `ToolInspectorLayout`, K8) |
| AC-58 Resize dọc: cột 360 | ❌ | như AC-39 | task 53 |
| AC-59 dọc: mọi nút toolbar Editor + Viewer ≥ 44 | ❌ | Editor: đĩa 44 ở regular (`EditorLayoutMetrics.swift:329-331`) — đạt; Viewer dọc chưa có toolbar | task 47 |
| AC-60 "Your photos stay where they are"; Continue 320×50 | ❌ | câu 4 "Your photos stay on your device" (`OnboardingScreen.swift:67`); Continue `maxWidth: .infinity` (`:21-31`) | task 56 |

## Việc spec có mà không AC nào đo (báo, không làm thêm)

- Combine Photos (Focus Stack/Stack Exposures/HDR một cột `PhotoStackScreen.swift:80-85`; Panorama cột 320
  `PanoramaMergeScreen.swift:371-379`), Cull, cắt video (02b §2 bảng) — **không AC** → task 50 chỉ chuyển sang khung
  `ToolInspectorLayout` cùng lúc với Collage nếu K8 chọn A; nếu không thì ghi `REVIEW_QUEUE.md` và hỏi `/spec` thêm AC.
- Trips 3 cột 328 (02 §6; hôm nay một cột `Features/Places/TripsScreen.swift:34-53`), Places inspector cụm (hôm nay đẩy
  `PhotoListScreen`, `PlacesMapScreen.swift:40-46`), trang album hero 764×150 / tile 159, Duplicates danh sách nhóm 360
  — **không AC** ngoài board. Đề nghị `/spec` thêm AC trước khi làm; plan để chỗ ở khối F.
- Phím "." Favorite, Space Quick Look (01 §7), Share popover (02 §3) — không AC.
