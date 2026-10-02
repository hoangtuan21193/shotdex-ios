# Review UI/UX ShotDex (2/10) — plan thực thi

> Chốt ngày 2026-10-02, sau 1 vòng · nguồn: .planboard/ui-review-1002/plan.json · lý do từng mục: DECISIONS.md ·
> báo cáo gốc: review/ (8 reviewer, merged.md 88 mục, challenge.md)

## Nguyên tắc
- Theo P5: **một `/intent` "UI review 2/10"** cho cả 46 mục → `/spec` (AC kiểm được cho từng mục, ghi vào các FS-* bị đụng) → `/plan` → mỗi AC một commit → `/verify`.
- Mọi màn đổi thì sửa artboard tương ứng trên canvas ShotDex App Screens (<https://claude.ai/artifact/53VivNtnC7jPrMQZx41ra8>, bản local `build/design/app/project/`) trong cùng lượt, rồi `Tools/design-board compare` với dump ui-drive.
- Mỗi commit: build, test liên quan, screenshot các màn đụng tới (cả iOS 26 và pre-26 khi code rẽ nhánh). Full suite một lần khi xong intent.
- Cần đi chệch một quyết định đã chốt: dừng lại, hỏi người dùng.

Kiểm tra dùng chung (gọi tắt bên dưới):
- **build**: `xcodebuild -project ShotDex.xcodeproj -scheme ShotDex -destination 'platform=iOS Simulator,id=<udid>' build` (hoặc `/build`)
- **test X**: `/test X` (`xcodebuild … test -only-testing:ShotDexTests/X`)
- **screens F**: `/screens F` trên PH, IP, DI, DC; Duo chụp bằng `Tools/sim-shot`
- **parity**: `Tools/design-board render build/design/app/project/<Board>.dc.html -o build/design/app/render` + `Tools/design-board compare …`

## Việc cần làm

### 0. Quy trình
- [ ] **0.1 `/intent ui-review-1002`** — `docs/_intents/2026-10-02-ui-review-1002.md`
  - Theo: P5 (một intent cho tất cả)
  - Xong khi: intent liệt kê 46 mục theo ID planboard, dẫn DECISIONS.md, có dòng Tiến độ.
- [ ] **0.2 `/spec`** — các FS-* bị đụng (FS-01.03/05/08, FS-03.07, FS-06.06, FS-08.06, FS-15 …) + DESIGN.md
  - Xong khi: mỗi mục có ≥ 1 AC kiểm được; các quyết định bị đảo được sửa trong doc (FS-06.06 §8, FS-01.08 §6, FS-03.07 §5, FS-15 README:41, DESIGN §10.4/§10.6/§11/§10.1c/§10.1d).
- [ ] **0.3 `/plan`** — `docs/_plans/2026-10-0x-ui-review-1002.md`, dừng chờ duyệt.

### 1. Nền tảng (làm trước vì nhiều mục dựa vào)
- [ ] **1.1 Environment `isShortWindow`** — `ShotDex/App/RootTabView.swift`, `ShotDex/App/Theme/AppTheme.swift`
  - Theo: Z3 (env + 8 điểm gọi)
  - Xong khi: cờ là hàm thuần có test (chiều cao 669 → true, 874/1032 → false); hero Collections, Insights, Widget picker, tile Collections, rule builder đọc cờ; DESIGN ghi "669pt là cửa sổ thấp nhất".
  - Kiểm tra: test AppLayoutTests (mới); screens Collections/Statistics trên DI.
- [ ] **1.2 Luật "mọi sheet có nút đóng"** — `DESIGN.md §10.4`
  - Theo: Q1

### 2. Sửa nhanh
- [ ] **2.1 Done cho Photo Info và Burst** — `Library/MetadataPanel.swift:30-47`, `Shared/PhotoListScreen.swift:45` · Q1 · Xong khi: Done hiện ở mọi thiết bị, DI đóng được bằng chạm.
- [ ] **2.2 Lỗi Favorite/Delete hiện alert** — `Library/PhotoDetailScreen.swift:1252,1266`, `Library/CompareScreen.swift` · Q2 · Xong khi: không còn `catch {}`; huỷ không bật alert, lỗi thì có.
- [ ] **2.3 Chuỗi "Try:" tiếng Anh qua String Catalog** — `Library/SearchSuggestionsScreen.swift:208` · Q3
- [ ] **2.4 Dấu phân cách hàng nghìn** — `Statistics/ChartCard.swift:12,24` · Q4 · Xong khi: "22,640", % theo locale.
- [ ] **2.5 Chart Top Lens mặc định** — `Data/Database/ChartStore.swift` (seed + `currentSeedGeneration`) · Q5 · Kiểm tra: test ChartStoreTests.
- [ ] **2.6 `.alert` thay `confirmationDialog` khi xoá kết nối** — `ServerUpload/FileServerListScreen.swift`, `ServerImport/OnServerScreen.swift`, `ServerImport/OnCloudScreen.swift`; sửa DESIGN §11 · Q6
- [ ] **2.7 Đóng Viewer → lưới cuộn tới ảnh cuối** — `Library/LibraryScreen.swift:154-157` + AlbumDetail, SmartAlbum, OnThisDay · Q7
- [ ] **2.8 Nhóm nhỏ** — Cancel quét không destructive (`DuplicatesScreen.swift`), OnThisDay picker detents, vùng chạm 44 (`SmartAlbumRuleRow.swift`, `ChartCard.swift`), label slider Quality (`CompressionScreen.swift`), dòng `/release-check` · Q8

### 3. An toàn khi xoá
- [ ] **3.1 Merge chỉ ở Exact + alert + bỏ `try?`** — `Duplicates/DuplicatesScreen.swift:99-103`, `DuplicatesModel.swift:299-330` · D1 (exact) · Xong khi: Similar/Series không có Merge; alert ghi số nhóm; lỗi hiện. Kiểm tra: test DuplicatesModelTests.
- [ ] **3.2 Dấu xoá sống qua đổi chế độ/tab; chặn đánh dấu cả nhóm** — `DuplicatesModel.swift:162` · D2 (memory) · Kiểm tra: test DuplicatesModelTests.
- [ ] **3.3 Glyph favorite/đã chỉnh/RAW/Live, thứ tự keeper** — `DuplicatesScreen.swift`, `DuplicatesModel.swift` · D3
- [ ] **3.4 Resize: nút "…and Delete Originals", toast kết quả, chữ đen trên amber** — `Editing/CompressionScreen.swift:187` · D4 (giữ bật)
- [ ] **3.5 Toast Hide nói chỗ tìm lại** — selection actions · D5

### 4. Viewer và Compare
- [ ] **4.1 Compare zoom phân giải cao theo vùng (≤ ~3000px, pane đang chạm, > 1.5×)** — `Library/CompareScreen.swift:143,808` · V1 · Kiểm tra: agent perf-profiler + memory-leak; screens Compare zoom 5×.
- [ ] **4.2 Xoá một tấm không thoát Compare khi còn ≥ 2; hint keep-only** — `CompareScreen.swift` · V2
- [ ] **4.3 Photo Info là cột inspector ở regular width** — `Library/PhotoDetailScreen.swift`, `MetadataPanel.swift` · V3 (inspector) · Xong khi: IP và DI hiện cột phải cạnh ảnh, compact giữ sheet; board IP_/DI_Metadata vẽ lại trước khi code.
- [ ] **4.4 Camera & Lens lên trước bản đồ** — `MetadataPanel.swift` · V4 (chạm-để-ẩn chrome: để sau)

### 5. Tìm và lọc
- [ ] **5.1 Submenu Camera ▸ / Lens ▸ trong Filter** — `Shared/PhotoFilterMenu.swift` · S1
- [ ] **5.2 Trường `timeOfDay`** — indexer (`Domain/IndexPipeline`, `MetadataComposer`), cột mới trong `photo_metadata` (dữ liệu suy ra từ EXIF nên nằm ở đây được), `SearchParser`, `SearchService.swift:139` · S2 (timeofday) · Xong khi: "85mm night" ra ảnh chụp đêm; mặt trời lặn/mọc tính theo vị trí + ngày khi có GPS, không có GPS thì theo giờ địa phương; từ không hiểu vẫn hiện chip nói rõ. Kiểm tra: test SearchParserTests, TimeOfDayTests (mới), DatabaseTests; agent data-migration.
- [ ] **5.3 Rule builder: Media Type + Match một hàng, "Matches N" gần Search** — `AdvancedSearchSheet.swift`, `SmartAlbumEditorSheet.swift`, `ChartEditorSheet.swift`, `Shared/RuleBuilderSections.swift` · S4
- [ ] **5.4 Toán tử `isMissing`, Location Has/No; thanh "Unknown" mở lưới** — `Data/Database/LibraryQueries.swift`, `Albums/SmartAlbumRuleRow.swift`, Statistics drill-down · S5 · Kiểm tra: test LibraryQueriesTests.

### 6. Lần chạy đầu
- [ ] **6.1 Footnote "choose Allow Full Access", Continue maxWidth 480** — `Onboarding/OnboardingScreen.swift` · F1
- [ ] **6.2 Nhãn "Still reading photo info · N%" + làm mới Statistics khi index xong** — `StatisticsScreen.swift:136`, `DuplicatesScreen.swift`, `SearchSuggestionsScreen.swift` · F2
- [ ] **6.3 Board Limited / Denied / chờ iCloud cho Library + Statistics (4 thiết bị), rồi ux-reviewer** — canvas · F3

### 7. Share, xuất, server
- [ ] **7.1 Upload nền bằng `BGContinuedProcessingTask` (iOS 26), pre-26 giữ như cũ** — `ServerUpload/ServerUploadModel.swift`, Info.plist (BGTaskSchedulerPermittedIdentifiers), sửa FS-15 README:41 · H3 (bg-now) · Xong khi: rời app giữa lần upload 500 ảnh, hệ thống hiện tiến độ và upload tiếp; huỷ từ hệ thống thì app báo "paused". Kiểm tra: máy thật (simulator không đủ), agent swift-concurrency + photokit-guard.
- [ ] **7.2 Resize/Collage Export xong có "Share N Photos"** — `CompressionScreen.swift`, `Collage/CollageExportScreen.swift` · H1
- [ ] **7.3 Header/phụ đề Share cho ca mặc định No Metadata** — `Shared/ShareLevelRow.swift`, `PhotoShareSheet.swift` · H2
- [ ] **7.4 Sửa vặt server** (Apply to Remaining lên trên, Add Connection ra khỏi section, Select ra toolbar, glyph In Library) · H4
- [ ] **7.5 "Free Up Space — N photos · ~X GB"** — `ServerUpload/UploadedToServerScreen.swift` · H5

### 8. Màn rộng và màn thấp
- [ ] **8.1 Compress và Collage Export hai pane ở regular width; compact ghim nút** — `CompressionScreen.swift`, `CollageExportScreen.swift` · Z1 (panes) · Xong khi: IP/DI preview trái, tuỳ chọn + nút phải, nút luôn thấy không cuộn; PH nút ghim trên home indicator. Board vẽ trước.
- [ ] **8.2 Lưới adaptive cho Trips, Duplicates, Search Recents, Collage Layout** — `Places/TripsScreen.swift`, `DuplicatesScreen.swift`, `SearchSuggestionsScreen.swift`, `Collage/CollagePanelViews.swift` · Z2
- [ ] **8.3 Widget editor trên màn thấp: preview ≤ 158, Large qua popover** — `Settings/PhotoWidgetSettingsScreen.swift` (đọc `isShortWindow`) · Z4
- [ ] **8.4 Esc / ←→ trong Viewer, Compare, Compress, Trim** · Z5

### 9. Statistics, Collections, sheet
- [ ] **9.1 Chặn vuốt mất form (isDirty + Discard alert)** — `SmartAlbumEditorSheet.swift`, `ChartEditorSheet.swift`, `FileServerFormScreen.swift`, `AdvancedSearchSheet.swift` · C1
- [ ] **9.2 Chart editor Save không cần tên** — `ChartEditorSheet.swift` · C2
- [ ] **9.3 Giữ indigo, sửa DESIGN** — `DESIGN.md §10.6`, `App/Theme/AppAccentTheme.swift` (comment) · C3 (doc)
- [ ] **9.4 Tên trên thanh khi topN ≤ 5, bỏ danh sách nhãn** — `ChartCard.swift` · C4
- [ ] **9.5 "My Albums ›" → lưới đầy đủ có sort** — `Albums/AlbumsScreen.swift`, DESIGN §10.1d · C5 · board *_AllAlbums vẽ trước.
- [ ] **9.6 Một tên "My Albums", Cloud bỏ icon iCloud, ⇅ vào menu** · C6

### 10. Những gì review chưa phủ
- [ ] **10.1 design-reviewer trên `build/design/app/render-dark/`, a11y-voiceover trên tầng A/B** · P1
- [ ] **10.2 Board chấm sao / Pick / Reject / Cull (4 thiết bị) + ux-reviewer trước khi code FS-01.12** · P2
- [ ] **10.3 Kịch bản ui-drive vòng lõi Statistics → drill-down → Library → Share, đo chạm + giây** — `ShotDexUITests/scripts/core-loop.json` · P3

## Ngoài phạm vi
- **S3** (M-23) capsule "(actual)": Không OK — không tự đổi sang tương đương, không hiện "actual".
- **V5** (M-20) đảo nút Duo cover: chốt giữ nguyên.
- **P4**: 15 mục challenger loại (M-20, M-28, M-29, M-38, M-44, M-55, M-63, M-64, M-65, M-70, M-73, M-77, M-80, M-81, M-85).
- Chưa làm: Undo cho Hide, "trong album nào" ở Duplicates, chạm-để-ẩn chrome, ⌘A/⌘F.
