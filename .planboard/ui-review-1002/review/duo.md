# duo — Duo inner 951×669 và Duo cover 466×678 (vùng app 382 + rail 84)

Phạm vi và giới hạn: Duo không boot (chỉ có iPhone 17 ×4 và iPad ×2 đang chạy) nên không chụp được frame thật; mọi thứ dưới đây đọc từ board `DI_*`/`DC_*` + code. Không thay thiết bị khác để giả Duo. Mọi finding về fold đều **Confirmed: needs-runtime-check** (simulator không có lệnh fold). Chiều cao bàn phím trên inner chưa đo — chỗ nào dùng đều ghi là K.

Phép tính ngân sách dọc dùng chung (inner 669pt): navigation bar ~82 (board), status/safe-area đã nằm trong con số đó. "Chrome cố định > 1/3 (223pt)" = blocker theo doctrine.

---

### DUO-01 Photo Info và Burst thành sheet toàn màn hình mà không có nút đóng
- Màn / thiết bị: Viewer → Photo Info, Viewer → Burst · Duo inner (cover không bị)
- Mức: blocker
- Ở đâu: APP (`ShotDex/Features/Library/MetadataPanel.swift:30-47`, `PhotoDetailScreen.swift:356-361` và `:309-323`, `ShotDex/Features/Shared/PhotoListScreen.swift:45-62`) + BOARD (`DI_Metadata`, `DC_Metadata`)
- Vấn đề: Trên inner, UIKit bỏ qua `presentationDetents` (đã đo, ghi ở `EditorHistorySheet.swift:121-126`) nên `.sheet` của Photo Info (`.medium, .large`) và Burst (không detent) thành full-screen 951×669. `MetadataPanel` là `NavigationStack { List }` chỉ có `navigationTitle("Photo Info")`, **không có toolbar nào**; `PhotoListScreen` (Burst) chỉ có nút "film" bên phải. Sheet adaptive full-screen thì không có gesture kéo xuống và `presentationDragIndicator(.visible)` không còn thanh để kéo → người dùng không có cách thoát nhìn thấy được; nút ✕ của viewer nằm *dưới* sheet. Trên cover (rộng compact) sheet vẫn là card có drag indicator nên không bị. Mọi sheet khác tôi grep đều có Cancel/Done (Advanced Search, Smart Album, Chart Editor, Customize, Adjust*, Upload…), nên đây là hai ngoại lệ.
- Đề xuất: thêm `ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }` vào `MetadataPanel` và `.cancellationAction`/Done vào Burst (bọc trong `PhotoListScreen` khi `showsDismiss`). Chi phí: 0pt chiều cao (nằm trong nav bar đã có), 2 nút. Nên làm chung cho mọi sheet: quy tắc "mọi `.sheet` phải có nút đóng trong toolbar" vì app chạy được ở màn hình mà gesture bị tắt. Sau đó, trên inner Photo Info có thể chia 2 cột (Location | Camera & Lens + Exposure) để bớt cuộn, nhưng nút đóng là phần blocker.
- Bằng chứng: `DI_Metadata.png` (không vẽ nút đóng nào; xem DUO-16 về lỗi board), code như trên. Confirmed: needs-runtime-check cho phần "không kéo xuống được" (cần mở Photo Info trên inner và thử kéo).

### DUO-02 Mọi công tắc "màn rộng" chỉ nhìn chiều ngang; Duo inner nhận kích thước iPad với 1/2 chiều cao
- Màn / thiết bị: Collections, Statistics, Search, Albums tiles, Widget pickers, Collage/editor · Duo inner
- Mức: nên sửa (là nguyên nhân gốc của DUO-03…07, 12, 13)
- Ở đâu: APP — `grep verticalSizeClass` trong `ShotDex/` ra **0 kết quả**. Các điểm rẽ nhánh chỉ theo `horizontalSizeClass == .regular`: `AlbumsScreen.swift:14,742,787,966,1044` (hero 260 / tile 192 / 4 cột), `AlbumCoverTile.swift:117`, `StatisticsScreen.swift:131`, `SearchSuggestionsScreen.swift:156`, `PhotoWidgetPickers.swift:67,161`, `SettingsLayout.swift:24`, `CompareScreen`/`CompareLayout` (theo bề rộng).
- Vấn đề: inner = regular width × 669pt cao. Mọi metric "iPad" (hero 260, tile 192, thẻ vuông 267, preview 320…) được thiết kế cho 1032–1376pt cao nhưng nhận 669. Ngưỡng của editor/Collage đã đúng hướng (`sidebarMinCanvasHeight = 600`, `EditorLayoutMetrics.swift:153`) nhưng so với `proxy.size.height` đã trừ safe area, nên biên an toàn trên inner chỉ khoảng 16–69pt: thêm một dải chrome hệ thống là Collage tụt về layout phone-slab mà không ai nhận ra.
- Đề xuất: một giá trị môi trường `isShortWindow` (window height < ~720, đo ở `RootTabView` giống `ToolChromeEnvironment.swift`, không dùng size class) và để các `*Metrics` enum nhận cả `isShortWindow`: hero 260→~160, tile 192→~140, preview/ảnh minh hoạ thu nhỏ, v.v. Ghi hằng số 669 vào `DESIGN.md` như "chiều cao nhỏ nhất app hỗ trợ" để các lần sau có con số kiểm tra. Chi phí: một environment key + sửa ~8 điểm gọi; không chạm iPad/iPhone.
- Bằng chứng: grep trên; `DI_Collections.png`, `DI_Search.png`, `DI_Statistics.png`.

### DUO-03 Sửa widget: phần ghim chiếm 55–70% chiều cao, danh sách tuỳ chọn còn 190–280pt
- Màn / thiết bị: WidgetSettings · DI, DC
- Mức: blocker
- Ở đâu: APP (`ShotDex/Features/Settings/PhotoWidgetSettingsScreen.swift:39-60` ghim `previewHeader`; `:186` preview cao 158, **280 khi chọn Large**) + BOARD (`DI_WidgetSettings`: board vẽ Medium nên che mất ca xấu nhất)
- Vấn đề: chrome cố định trên inner = nav ~58 + preview 158 (Medium) + Widget Size picker ~32 + chips Photo/Time/Date/Weather ~44 + dòng hướng dẫn ~40 + khoảng cách ≈ 390pt = **58%** của 669; còn ~280pt cho list. Chọn Large: preview 280 → ≈ 510pt cố định (**76%**), list còn ~160pt, chưa tính bàn phím khi gõ format. Trên cover (678) cùng cấu trúc: Medium ≈ 370 (55%), Large ≈ 520 (77%). Pane chi tiết ở inner chỉ rộng 631 vì sidebar 320 vẫn đứng đó.
- Đề xuất: khi `isShortWindow` (DUO-02) đặt preview và tuỳ chọn **cạnh nhau**: ẩn sidebar (`columnVisibility = .detailOnly`) khi vào editor widget để pane có 951: trái preview ~380×(Medium 158 / Large 280) + picker + chips, phải list cuộn ~520 cao đủ 600+. Phương án rẻ hơn nếu chưa làm được: bỏ dòng hướng dẫn (~40) vào footer list, giữ preview ≤ 158 và đưa Large vào popover; chrome còn ~280 (42%). Chi phí: HStack theo `isShortWindow`; luật "preview ghim vì kéo-thả trên preview" (comment `:39-43`) vẫn đúng vì preview vẫn ghim.
- Bằng chứng: `DI_WidgetSettings.png`, `DC_WidgetSettings.png`.

### DUO-04 Xuất ảnh ghép: preview 167×167 trên inner, 75% chiều cao là chrome
- Màn / thiết bị: CollageExport · DI (cover ổn)
- Mức: blocker
- Ở đâu: APP (`ShotDex/Features/Collage/CollageExportScreen.swift:31-39,80-91`: `VStack { top bar, previewArea(flex), options card, banner, Save }`) — board đúng với code
- Vấn đề: đo trên `DI_CollageExport`: top bar ~103 + options card 218 + dòng "Added to…" ~25 + nút Save 50 + footer ~35 + padding ≈ **502pt cố định**, preview là phần còn lại = 167pt (25%). Người dùng đang chọn Size/Quality/Format cho một ảnh mà họ chỉ thấy bằng ô 167pt; 951pt chiều rộng thì bỏ trống 280pt mỗi bên.
- Đề xuất: khi regular width + `isShortWindow`: `HStack` — trái preview (khung ~420×600, thấy rõ ảnh), phải cột 400pt gồm options card + Save + footer. Chi phí: một nhánh layout, không đổi logic; trả lại ~430pt chiều cao cho preview.
- Bằng chứng: `DI_CollageExport.png` (preview y 103–270), `DC_CollageExport.png` (cover: preview 182pt cũng nhỏ nhưng cover 382 rộng thì chấp nhận được).

### DUO-05 Resize/Compress: nút chính nằm dưới màn hình, chrome trước nó 52%
- Màn / thiết bị: Compress · DI (cover/iPhone chấp nhận được vì một cột)
- Mức: blocker
- Ở đâu: APP (`ShotDex/Features/Editing/CompressionScreen.swift:117-173`: `ScrollView` cột 700 giữa màn; preview/gallery cao **250 (nhiều ảnh) / 320 (một ảnh)** `:127`; `exportButton` là phần tử cuối trong cuộn `:173`)
- Vấn đề: nav ~82 + padding 16 + gallery 250 = 348pt (**52%**) trước khi tới Size. Trên board Format ở y 554, Metadata ở 625, rồi còn Delete originals và nút "Resize 8 Photos" — nút chính ≈ y 800+, tức **~130–230pt dưới đáy màn hình**. Một ảnh (preview 320) tệ hơn: nút ≈ y 900+. Người dùng phải cuộn 1–1.5 màn để thấy hành động duy nhất của màn hình; 126pt mỗi bên cột 700 bỏ trống.
- Đề xuất: trên `isShortWindow`: hai cột — trái preview/gallery vuông ~330pt cố định, phải form cuộn; nút Save/Resize **ghim đáy** cột phải (`safeAreaInset(edge: .bottom)`) thay vì nằm cuối cuộn. Chi phí: đổi `ScrollView{VStack}` thành `HStack` khi ngắn; nút ghim luôn thấy được.
- Bằng chứng: `DI_Compress.png` (caption "cuộn dưới Format"), `CompressionScreen.swift:173`.

### DUO-06 Rule builder (Advanced Search, Edit Smart Album, Edit Chart): 3 hàng điều kiện đầy màn, đếm kết quả và nút ngoài tầm nhìn
- Màn / thiết bị: AdvancedSearch, SmartAlbumEditor, ChartEditor · DI (và DC)
- Mức: nên sửa
- Ở đâu: APP (`ShotDex/Features/Shared/RuleBuilderSections.swift:44-105`, `ShotDex/Features/Albums/SmartAlbumRuleRow.swift:7-30` "two-line iOS layout") + `AdvancedSearchSheet.swift:84-105`
- Vấn đề: sheet full-screen 669: nav 82; Media Type (header + segmented) ~100; Match (segmented + dòng chú thích) ~110; header Conditions ~40 → điều kiện đầu tiên bắt đầu y≈350. Mỗi điều kiện hai dòng (field+operator+“−” rồi ô giá trị) ≈ 100pt, ba điều kiện (đúng ví dụ board) xuống tới y≈635; **"Matches N photos." là footer của section** (`RuleBuilderSections.swift:100-103`) nên nằm sau hàng cuối, ngoài màn hình; "Save as Smart Album" thêm 50pt nữa. Bàn phím (K) che nửa dưới khi gõ giá trị, và gợi ý autocomplete nằm *dưới* ô nhập — chính chỗ bàn phím che. Chiều rộng 951 thì mỗi hàng chỉ dùng 25%.
- Đề xuất: ở regular width: (1) Media Type và Match cùng một hàng (hai segmented cạnh nhau, tiết kiệm ~110pt); (2) mỗi điều kiện **một dòng**: `[field ▾] [operator ▾] [value……] [−]` (tiết kiệm ~45pt/hàng, autocomplete thành dropdown phía dưới một dòng); (3) đưa số kết quả lên subtitle của nav bar ("Advanced Search · 214 photos") hoặc bottom bar để luôn thấy. Với 3 điều kiện: 82+100(hàng gộp)+40+3×55 ≈ 390 → còn ~280 cho bàn phím không che count. Chi phí: một biến thể row cho `isShortWindow`; comment gốc nói "two-line iOS layout" là chủ ý cho phone, cần nói rõ đây là ngoại lệ.
- Bằng chứng: `DI_AdvancedSearch.png`, `DI_SmartAlbumEditor.png`, `DI_ChartEditor.png` (đã cuộn qua Media/Match mới tới Conditions).

### DUO-07 Search trên inner: thẻ Recents vuông 267pt nằm dưới bàn phím
- Màn / thiết bị: Search · DI
- Mức: nên sửa
- Ở đâu: APP (`ShotDex/Features/Library/SearchSuggestionsScreen.swift:332` `.aspectRatio(1)`, `:178-184` 3 cột, `:156` `isFieldAtTop` khi regular) + BOARD (`DI_Search` không vẽ phím, thấy rác "123/{{k.k}}/space")
- Vấn đề: trên inner field lên toolbar, nội dung là `ScrollView`: tiêu đề Search ~60 → capsules (tối đa 5×52 + 28 = ~290) → Recents (30 + thẻ **(951−64)/3 = 267 vuông**). Thẻ đầu tiên bắt đầu y≈244–400 tuỳ số capsule và kết thúc 511–670; toolbar ~90 + bàn phím K (chưa đo, giả định 260–330) để lại vùng nhìn thấy ≈ 250–320pt → Recents, thứ người dùng quay lại tìm nhất (comment `:154-157` nói đúng điều đó), nằm gần hết dưới bàn phím. `scrollDismissesKeyboard(.never)` khiến muốn thấy chúng phải cuộn trong lúc bàn phím mở.
- Đề xuất: khi regular + `isShortWindow`: thẻ Recents `aspectRatio(2.4)` (267×~110, như cover 109pt), capsules xếp **trái** Recents (HStack hai cột 40/60) thay vì chồng dọc. Vùng dưới toolbar: header 60 + 110 + 30 = 200 < 280. Chi phí: hai nhánh layout nhỏ.
- Bằng chứng: `DI_Search.png`, `DC_Search.png` (cover: thẻ 109pt, ổn).

### DUO-08 Vào chế độ chọn (long-press) làm lưới đổi 9 → 10 cột ngay dưới ngón tay
- Màn / thiết bị: Library/Album/SmartAlbum/OnThisDay chọn ảnh · DI
- Mức: nên sửa
- Ở đâu: APP (`LibraryScreen.swift:95` `.toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)`; `GridDensity.swift:74-80` số cột = round(density × width / reference); grid chỉ `ignoresSafeArea(.vertical)` `:735`) — board nói rõ: `DI_Library` "9 cột trong 867pt", `DI_LibrarySelect` "rail ẩn, 10 cột"
- Vấn đề: rail 84pt biến mất khi chọn nên vùng grid rộng 867 → 951, cột 9 → 10, cell co từ ~96 xuống ~94.6 và **mọi tile đổi chỗ đúng lúc người dùng nhấn giữ một tile** (và ngược lại khi thoát). Với tile là thứ vừa nhấn, nó nhảy khỏi ngón tay; đây không xảy ra ở iPhone/iPad (không có inset ngang).
- Đề xuất: giữ bề rộng tính cột bằng bề rộng trước khi vào chọn (cố định `columns` trong lúc `isSelecting`, giữ gutter phải 84pt trống), hoặc dựng `resolvedColumns` từ bề rộng *không trừ* rail. Chi phí: 1 biến giữ cột khi bắt đầu chọn; mất 84pt bề ngang trong lúc chọn — đáng.
- Bằng chứng: `DI_Library.png` vs `DI_LibrarySelect.png`, code trên. Confirmed: needs-runtime-check (cần xem inset ngang có thật sự đổi khi rail ẩn).

### DUO-09 Gập/mở máy: lưới không bù vị trí cuộn, người dùng nhảy hàng trăm ảnh
- Màn / thiết bị: Library, Album, mọi grid · fold inner ↔ cover
- Mức: nên sửa
- Ở đâu: APP (`ShotDex/Features/Shared/PhotoGridLayout.swift:463-478,481-485`: bề rộng đổi → `dropLevels()` + invalidate; không có `targetContentOffset(forProposedContentOffset:)`; `PhotoGridCollectionView.swift:386-431` chỉ giữ vị trí khi *nội dung* đổi (`preservableScroll`), không khi *bề rộng* đổi)
- Vấn đề: inner 9 cột (cell ~96) → cover 3 cột (cell ~125): chiều cao nội dung gấp ~3 lần mà `contentOffset.y` giữ nguyên số pt. Ví dụ đang xem hàng 100 (offset ≈ 10.000pt) ở inner → trên cover offset đó ứng hàng ~80 × 3 cột ≈ ảnh thứ 240 thay vì ảnh thứ 900: **nhảy ~660 ảnh**, và Library neo ở đáy (`anchorsBottom`) nên cũng mất "đang ở mới nhất". Ngược lại cover → inner nhảy về phía mới hơn.
- Đề xuất: giữ `anchor = ảnh đầu tiên nhìn thấy`; trong `prepare()` khi `width != preparedWidth` ghi lại item đầu thấy được trước, và sau layout `setContentOffset` về frame mới của item đó (cùng cơ chế `restoreScroll` đã có `:405-431`). Chi phí: ~20 dòng ở layout; đã có `restoreScroll`.
- Bằng chứng: code trên. Confirmed: needs-runtime-check.

### DUO-10 Gập/mở máy: cái gì còn, cái gì mất (bảng cho người sửa)
- Màn / thiết bị: toàn app · fold
- Mức: nên sửa (các dòng "mất")
- Ở đâu: APP (không có `onChange(of: horizontalSizeClass)` nào ngoài `SettingsScreen.swift:121-123`; một `@SceneStorage` duy nhất, `RootTabView.swift:37`)
- Vấn đề / Đề xuất, theo trạng thái:
  - **Còn (code đã lo):** tab đang chọn (`@SceneStorage`, root state); `LibraryModel`/`AlbumsModel` sống ở `RootTabView` nên filter/search/selectedIds không mất; Settings đổi giữa split view và list giữ chỗ đọc (`SettingsLayout.swift:30-48`, `navigation.layoutChanged`); Collage giữ model, text overlay và sheet (state ở `CollageEditorModel` + `@State` của screen, `CollageScreen.swift:46-56`) dù khung canvas dựng lại.
  - **Mất — Statistics:** `usesColumns` chọn `columns(model)` hay `rows(model)` trong một `Group` (`StatisticsScreen.swift:131,155-160`), hai nhánh khác identity → ScrollView dựng lại, **cuộn về đầu** và các `@State` trong thẻ tải lại. Fix: để cả hai là cùng một `ScrollView` với `LazyVGrid` đổi số cột (hoặc lưu offset ở model).
  - **Mất — Search đang gõ:** `isFieldAtTop` (`SearchSuggestionsScreen.swift:156`) đổi field từ toolbar (inner) sang đáy tab-search (cover); text giữ qua `query` binding nhưng focus/bàn phím nhiều khả năng rơi. Fix: giữ `isSearchPresented`/focus ở model và gán lại sau khi đổi.
  - **Mất — vị trí cuộn lưới:** DUO-09.
  - **Sheet đang mở khi gập:** sheet trên cover là card có detent; sang inner thành full-screen (DUO-01 — nếu thiếu Done thì kẹt); sheet `.medium` trên cover (OnThisDay date picker, DUO-14) lên inner sẽ đổi hình dạng. Không có code nào dismiss sheet khi gập — chấp nhận, nhưng mọi sheet phải tự đủ nút đóng.
  - **Tác vụ dài khi gập:** `ServerUploadSheet.swift:50-52` huỷ batch khi `scenePhase == .background`. Nếu fold đi qua `.background` (chưa biết), upload "Keep ShotDex open…" bị dừng trong im lặng. Cần đo: gập khi đang upload và xem `scenePhase`. Nếu có, đổi sang chỉ huỷ khi background thật sự > N giây.
- Bằng chứng: các file:line trên. Mọi dòng: Confirmed: needs-runtime-check.

### DUO-11 Viewer: ảnh hiển thị lấy theo kích thước cửa sổ lúc tải, không tải lại khi gập cover → inner
- Màn / thiết bị: Viewer · fold cover → inner
- Mức: gợi ý
- Ở đâu: APP (`PhotoDetailScreen.swift:2441` `targetSize = ActiveDisplay.pixelSize()`, `:2395`; `ActiveDisplay.swift:33-41` đọc cửa sổ lúc gọi; không có `onChange` theo size)
- Vấn đề: cover 382–466pt rộng → ảnh ngang nhận bản ~466pt-fit; mở sang inner 951×669 phóng ~2× cho tới khi người dùng lướt sang ảnh khác (bản gốc chỉ tải khi zoom, `:2386`). Chiều ngược lại không hại.
- Đề xuất: `onChange(of: proxy.size)` → nếu cạnh dài tăng > 1.3× thì gọi lại `loadDisplayImage`. Chi phí: một request; chỉ khi gập.
- Bằng chứng: code trên. Confirmed: needs-runtime-check.

### DUO-12 Collections: hero 260 + tile 192 = 40% chiều cao cho một thẻ On This Day
- Màn / thiết bị: Collections · DI
- Mức: nên sửa
- Ở đâu: APP (`AlbumsScreen.swift:1220-1222` `isRegularWidth ? 260 : 180`; tile `AlbumTileMetrics.side` regular 192)
- Vấn đề: hero đo từ board y 86–346 = 260 (39%), "Smart Albums" ở 384, hàng đầu tile 192 kết thúc ~612, "My Albums" ở 640 (bị cắt). Màn đầu của tab chỉ thấy **một thẻ + một hàng**; trên iPad 1032 cao cùng cấu trúc thấy 3–4 hàng.
- Đề xuất: theo `isShortWindow` (DUO-02): hero 160, tile 140 (4–5 hàng chung màn, hàng thứ hai của "My Albums" lộ ra ~y 560). Chi phí: hai hằng số.
- Bằng chứng: `DI_Collections.png`, `DC_Collections.png` (cover hero 180 tile 132 — hợp lý, dùng làm chuẩn).

### DUO-13 Statistics: Insights ăn 190pt trước biểu đồ đầu tiên
- Màn / thiết bị: Statistics · DI
- Mức: gợi ý
- Ở đâu: APP (`StatisticsScreen.swift:195-205` Insights nằm trên các cột) + BOARD (`DI_Statistics`, biểu đồ rỗng)
- Vấn đề: nav ~80 + Insights 4 dòng ≈ 190 → tới y≈270 mới thấy tiêu đề Top Camera; đồ thị đầu tiên chưa trọn khi chạm đáy 669. Phần Insights lại là 2 cột × 2 hàng chữ — 951pt cho chữ.
- Đề xuất: Insights thành một dải ngang 1 hàng (carousel 2 thẻ cuộn) cao ~64 khi `isShortWindow`, tiết kiệm ~120pt; hoặc để Insights là cột phải ~300pt rộng. Chi phí: layout biến thể; luật FS-07.01 §6 ("một thẻ, không chia cột") cần nới.
- Bằng chứng: `DI_Statistics.png`.

### DUO-14 OnThisDay chọn ngày: `.medium` trên cover bị cắt, không cuộn
- Màn / thiết bị: On This Day · DC (inner thành full-screen nên ổn)
- Mức: nên sửa
- Ở đâu: APP (`ShotDex/Features/Albums/OnThisDayScreen.swift:380-409`: `VStack { DatePicker(.graphical); Spacer() }` không phải ScrollView, `presentationDetents([.medium])`)
- Vấn đề: DatePicker graphical ≈ 330–350pt + nav 56 ≈ 400pt; `.medium` trên 678pt ≈ 320–340pt (trên iPhone 874 là ≈437 nên không lộ). Hai tuần cuối của tháng bị cắt, không cuộn được, "Done" vẫn bấm được nhưng ngày cuối tháng không chọn được.
- Đề xuất: `.presentationDetents([.height(440), .large])` hoặc `.medium, .large` + bọc `ScrollView`. Chi phí: 1 dòng. Phép tính cần xác nhận bằng một lần mở thật trên cover (ước lượng, chưa đo).
- Bằng chứng: code trên. Confirmed: needs-runtime-check.

### DUO-15 Adjust Location: map còn 40–140pt khi gõ tìm địa điểm trên inner
- Màn / thiết bị: Adjust Location · DI
- Mức: nên sửa
- Ở đâu: APP (`ShotDex/Features/Shared/AdjustLocationSheet.swift:60-66,146-148`: map linh hoạt, `resultList` **cố định 220**, search drawer + nav + bottom bar "Remove Location")
- Vấn đề: 669 − nav/search ~108 − bàn phím K − 220 (list) − bottom bar ~50 ⇒ map = 291 − K: với K=200 còn ~90pt, K=300 là **âm** (map biến mất, chỉ còn list). Người dùng đang đặt ghim lên bản đồ mà bản đồ là dải mỏng.
- Đề xuất: `resultList` dùng `frame(maxHeight: 220)` + `layoutPriority(0)`; hoặc đặt list **bên phải** map (HStack 40/60) khi `isShortWindow`. Chi phí: sửa 1 dòng hoặc một HStack.
- Bằng chứng: code trên. K chưa đo nên Confirmed: needs-runtime-check (cần frame bàn phím trên inner).

### DUO-16 Menu ⋯ của chế độ chọn dài 523pt trên 669pt và đè lên nút Delete
- Màn / thiết bị: LibrarySelect · DI, DC
- Mức: gợi ý
- Ở đâu: APP (menu 14 mục, `SelectionBarViews`/`LibraryScreen` selection menu) + BOARD (`DI_LibrarySelect`, `DC_LibrarySelect`)
- Vấn đề: board: 13 hàng + 2 phân cách chạy y 95–618 ≈ 78% chiều cao; hàng "Hide" (y 606) chồng lên nút thùng rác (x 890–935, y 590–632). Menu là hệ thống nên tự cuộn/đổi chỗ, nhưng 14 mục trên 669 nghĩa là thấy ~10 mục rồi cuộn.
- Đề xuất: nhóm thành 3 submenu (Create ▸ Collage/Video/Resize/Combine; Edit ▸ Date/Location/Paste Edits; Organise ▸ Add to Collection/Hide/Duplicate), mục hay dùng (Select All, Favorite) để ngoài; còn ≤ 8 hàng ≈ 290pt. Chi phí: đổi cấu trúc menu cho mọi thiết bị — nếu không muốn, bỏ qua; đây là gợi ý.
- Bằng chứng: `DI_LibrarySelect.png`, `DC_LibrarySelect.png`.

### DUO-17 Việc nào thuộc màn nào (quyết định, không phải lỗi)
- Màn / thiết bị: Compare, Collage, Compress, Duplicates, Server · cover
- Mức: gợi ý
- Ở đâu: APP
- Vấn đề: không có màn nào cần *từ chối* cover. Lý do cho từng màn: Compare một cột 358pt (`CompareLayout.minimumCardWidth = 330`, `CompareLayout.swift:19`) nhìn được 2 thẻ/màn đồng bộ zoom (đã đủ so sánh, kể cả khi thấy một thẻ ở một thời điểm); Collage dùng layout phone 250pt panel (37%) chấp nhận được; Duplicates/Server là danh sách. Hai điểm đáng nói: (1) trên **inner** Compare ra 2 cột (927−28)/3 = 299 < 330 nên 3 ảnh không lên 3 cột — hợp lý, nhưng với 4 ảnh ngang hai hàng cao ≈ 718 > 573 (cuộn); nên thử `minimumCardWidth = 290` khi `isShortWindow` để 3 ảnh thấy một lượt. (2) Không dùng "tiếp tục trên màn lớn" cho bất kỳ màn nào: phiên bản cover hẹp đều tốt hơn lời nhắc.
- Đề xuất: giữ nguyên; tuỳ chọn (1). Chi phí: 1 hằng số.
- Bằng chứng: `DI_Compare.png`, `DC_Compare.png`, `DC_Collage.png`.

### DUO-18 Board: lỗi vẽ của board Duo (không phải lỗi app, nhưng làm hỏng bằng chứng)
- Màn / thiết bị: nhiều · DI, DC
- Mức: gợi ý
- Ở đâu: BOARD
- Vấn đề (mỗi mục đã đối chiếu code, app không sai):
  - `DI_Metadata`/`DC_Metadata`: sheet vẽ trong suốt chồng lên Viewer, chrome viewer (✕, thanh EXIF, Share/♡/Trash) lộ xuyên qua, chữ "Photo Info" đè lên thanh EXIF; không có Done (xem DUO-01 — đây là chỗ board vô tình đúng, nhưng vì sai lý do).
  - `DI_Search`/`DC_Search`: bàn phím không vẽ phím, rác "123/{{k.k}}/space/search".
  - `DI_ServerForm`: sidebar Settings chồng lên form Add Connection.
  - `DC_ChartEditor`/`DC_DateRange`: toolbar Statistics lộ ra sau tiêu đề sheet ("Edit Chart" chồng "Date Range").
  - `DI_Library`, `DC_Library`, `*_LibrarySelect`, `DI_Collections`, `DI_Duplicates`, `DI_Statistics`, `DI_Collage`, `DI_CollageExport`: thumbnail/ảnh/biểu đồ là placeholder `{{p.meta}}`, `{{c.name}}`, ô trắng — không đo được độ phủ thật.
  - `DC_Settings`, `DC_WidgetSettings`: chấm đen tròn ở (418, 47) vùng rail.
  - `DC_Onboarding`: caption nói "lời hứa cuối bị cắt trên nút Continue" nhưng hình hiện đủ 4 lời hứa; caption hoặc hình sai.
  - `DI_WidgetSettings` chỉ vẽ preview Medium, che trường hợp Large của DUO-03.
- Đề xuất: vẽ lại các board trên trước khi dùng làm chuẩn parity; thêm một board `DI_WidgetSettings_Large` và `DI_Search_Keyboard` với bàn phím thật (K đo trên máy).
- Bằng chứng: các PNG nêu trên.

---

Không có finding về rail trên cover: mọi control đặt từ mép phải ở các board cover (`DC_LibrarySelect` thùng rác kết thúc x=362, `DC_Viewer` thùng rác x=362, `DC_Collage` Export x=370, `DC_Settings` Done x=365) nằm trong 382; `LibraryScreen.swift:743-750` đã ghi lý do grid không `ignoresSafeArea` ngang. Cover Library: ngày "September 30, 2026" cách nút filter 4pt (`DC_Library`) — chuỗi dài nhất trong năm; kiểm tra cắt chữ trên ảnh chụp thật (thuộc `device-layout`).
