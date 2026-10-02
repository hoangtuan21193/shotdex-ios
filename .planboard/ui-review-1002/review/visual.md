# Review thị giác (slug: visual)

Phạm vi: DESIGN.md, 148 board PNG (PH/IP/DI/DC/Main), và nguồn Swift của các màn tầng A/B/C + các màn tầng D "nhỏ" (Compress, Collage Export, Video Trim). Không build, không sửa code.

**Cảnh báo về độ tin cậy của board** (xem VIS-22): các board là wireframe xám vẽ từ code, nhiều board rò template (`{{c.name}}`, `{{p.meta}}`), biểu đồ Swift Charts không vẽ, toggle/nút hệ thống vẽ trắng/xám, nhiều sheet bị vẽ chồng lên màn bên dưới. Vì thế mọi nhận xét về màu/độ tương phản/độ dày chữ dưới đây đều lấy từ **nguồn Swift** (đã đối chiếu), board chỉ dùng để xem bố cục. Những chỗ cần ảnh thật từ simulator được ghi rõ.

Tính toán độ tương phản dùng accent thật trong `App/Theme/AppAccentTheme.swift`: dark `#EB9526` (L≈0.39), light `#C57310` (L≈0.24).

---

### VIS-01 Chữ/glyph trắng trên nền amber: không đạt tương phản
- Màn / thiết bị: Compress · PH, IP, DI, DC; DateRange (Statistics) · mọi thiết bị; Support (badge chưa đọc) · mọi thiết bị
- Mức: nên sửa
- Ở đâu: APP (Features/Editing/CompressionScreen.swift:187; Features/Statistics/DateRangePickerSheet.swift:162-185; Features/Support/SupportScreen.swift:198-203)
- Vấn đề: Nút chính "Resize 8 Photos / Save to Photos" của Compress vẽ chữ `.white` trên `accent`. Compress ép `.preferredColorScheme(.dark)` nên accent luôn là `#EB9526`: trắng trên amber = **2.4:1** (WCAG AA cần 4.5 cho chữ 16pt semibold). Đen trên cùng amber = **8.9:1**. Chính DESIGN.md §9 quy định "active = nền accent + glyph **đen**", và `CollageExportScreen.saveButton` (dòng ~219) đã dùng `.black` — tức hai nút primary tầng D cùng một vai trò mà chữ khác màu. Ngày chọn trong DateRange (`foreground(for:)` trả `.white` trên `Circle().fill(accent)`) ở light mode là trắng trên `#C57310` = 3.6:1, vẫn dưới 4.5 cho số 17pt. Badge unread của Support: `.caption2.semibold` trắng trên accent, cùng vấn đề.
- Đề xuất: (a) Compress: `.foregroundStyle(isDisabled ? EditorTheme.dimText : .black)`. (b) Tạo một token `AppAccent.onAccent` (đen ở dark, trắng ở light chỉ khi >=4.5, mặc định đen) hoặc đơn giản dùng `.black` cho mọi glyph trên accent ngoài badge lưới ảnh (check 14pt trong đĩa thì chấp nhận được, Photos làm vậy). Chi phí: 3 dòng + 1 token; không phá luật nào, thực ra là thực thi §9.
- Bằng chứng: PH_Compress.png / IP_Compress.png (nút amber chữ trắng), PH_CollageExport.png (nút amber chữ đen); mã nguồn các dòng trên.

### VIS-02 Card Statistics dạng bar: biểu đồ + danh sách vẽ cùng một dữ liệu hai lần, không thẳng hàng
- Màn / thiết bị: Statistics · PH, IP, DI, DC
- Mức: nên sửa (cơ hội lớn nhất để app trông "xịn hơn")
- Ở đâu: APP (Features/Statistics/ChartCard.swift:84-100 `barBody`, 160-185 `drillRows`) + BOARD (biểu đồ không vẽ nên board trống một khoảng ~160pt trên mỗi card, xem PH_Statistics.png)
- Vấn đề: `barBody` = `Chart` cao `count*28+20` (5 cột ≈ 160pt) với `.chartYAxis(.hidden)` rồi bên dưới lại `drillRows` liệt kê đúng 5 nhãn đó. Thanh không có nhãn, người đọc phải đối chiếu thanh thứ i với dòng thứ i bằng vị trí, mà khoảng cách thanh (28pt) và dòng chữ (~32pt, tuỳ Dynamic Type) không khớp nên lệch dần xuống dưới. Mỗi card tốn ~300pt cao cho 5 con số. Trên iPhone 874pt, một lần cuộn chỉ thấy 1,5 card. Dòng drill cũng chỉ cao ~28-32pt, dưới 44pt chạm.
- Đề xuất: bỏ `Chart` cho kind `.bar` có <= 10 hàng, vẽ **thanh nội tuyến trong chính hàng**: mỗi hàng là `VStack(spacing: 4)`: dòng 1 = nhãn `.subheadline` (trái) + giá trị `.subheadline.monospacedDigit()` + % `.footnote` secondary (phải); dòng 2 = capsule cao 6pt, nền `secondarySystemFill`, phần đầy = accent (hàng đầu 100%, các hàng sau 55-60% opacity), độ dài = value/max. Hàng cao >=44 (padding dọc 8) và là cả vùng chạm drill. Kết quả: ~52pt/hàng, 5 hàng = 260pt nhưng thông tin liền một khối, không còn khoảng trống, và `Chart` + trục ẩn biến mất (rẻ hơn khi render 55k ảnh x nhiều card). Giữ `Chart` cho kind `.line` và `.donut`. Chi phí: viết `BarRow` (~40 dòng), bỏ ~25 dòng; test snapshot không có nên cần chụp sim. Không phá luật DESIGN (accent trên chart được phép).
- Bằng chứng: ChartCard.swift:84-100, 160-185; PH_Statistics.png (khoảng trống phía trên các hàng Top Camera); IP_Statistics.png (cột 1 và 3).

### VIS-03 Số liệu Statistics không có dấu phân cách hàng nghìn; chỗ khác có
- Màn / thiết bị: Statistics · mọi thiết bị (so với Settings)
- Mức: nên sửa
- Ở đâu: APP (Features/Statistics/ChartCard.swift:5-27 `ChartValueFormatter.string`, dòng 177 `String(format: "%.0f%%")`)
- Vấn đề: card KPI hiện `55231`, hàng bar hiện `22640`, `13815`; Settings → Photo Library cùng con số là `55,231` (dùng `.number`), Support `412`. Cùng một app, cùng một thực thể, hai cách viết. Dòng `%` dùng `String(format:)` nên không theo locale (vi: "42 %"). Vi phạm DESIGN §7.3 (số liệu thay đổi dùng `.monospacedDigit()`) vì cột giá trị cũng không monospacedDigit nên cột số không thẳng hàng như trong IP_Statistics.png (1210 / 9880 / 11420).
- Đề xuất: `Int(value.rounded()).formatted(.number)` ở nhánh mặc định, `value.formatted(.percent.precision(.fractionLength(0)))` cho dòng %, và `.monospacedDigit()` trên cột giá trị + %. Chi phí: 5 dòng.
- Bằng chứng: PH_Statistics.png (22640 / 42%), PH_Settings.png (55,231), ChartCard.swift:9-27, 174-180.

### VIS-04 Biểu đồ dùng indigo/teal, trong khi DESIGN.md và icon nói accent của chart là amber
- Màn / thiết bị: Statistics, ChartEditor · mọi thiết bị
- Mức: gợi ý (cần quyết định, hai phía đều có lý)
- Ở đâu: APP (App/Theme/ChartPalette.swift:6-23) vs DESIGN.md §10.6 ("accent chỉ dùng cho ... badge chọn ảnh, trạng thái active editor, **chart**") và AppAccentTheme.swift (doc comment cũng liệt kê charts)
- Vấn đề: `ChartPalette.bar` là gradient `.indigo`, series đầu cũng `.indigo`. Tức tài liệu hứa chart ăn accent amber nhưng code thì không; toàn bộ tab Statistics (màn có nhiều "đồ hoạ tự vẽ" nhất) không mang màu thương hiệu, trong khi onboarding/trim/collage/compress đều amber. Người dùng chuyển từ Compress (amber) sang Statistics (indigo) thấy hai sản phẩm.
- Đề xuất: đặt `ChartPalette.colors[0] = AppAccent.color`; `bar` = accent (hàng đầu) và accent.opacity(0.55) (các hàng còn lại, xem VIS-02); giữ `teal/indigo/pink/...` làm series 2..8 cho donut/line. Amber trên nền `secondarySystemGroupedBackground` đạt >=3:1 (cần cho thành phần đồ hoạ) ở cả hai chế độ (light `#C57310` trên trắng 3.6:1). Nếu không muốn đổi: sửa DESIGN.md/AppAccentTheme để bỏ "charts" khỏi danh sách. Chi phí: 10 dòng.
- Bằng chứng: ChartPalette.swift; DESIGN.md §10.6; PH_Compress.png vs PH_Statistics.png.

### VIS-05 Card KPI: một con số trong một card cao ~100pt, hai card liền nhau để lại lỗ hổng
- Màn / thiết bị: Statistics · PH, IP (cột giữa), DI, DC
- Mức: gợi ý
- Ở đâu: APP (ChartCard.swift:44-62 `kpiBody`; StatisticsScreen cột)
- Vấn đề: "Total Photos & Videos 55231" và "Slow Shutter 12%" mỗi cái là một card đầy đủ header + menu `ellipsis.circle` + chữ "All Time" + số `.largeTitle`. Trên IP_Statistics.png cột giữa chỉ có hai KPI rồi trống hơn nửa chiều cao màn (DESIGN §10.1c nói cột tự co khít, nhưng round-robin theo index nên cột có nhiều KPI sẽ ngắn).
- Đề xuất: gom các card kind `.kpi` **liên tiếp** thành một hàng 2-up (compact) hoặc 3-4-up (regular): tile cao 88pt, `r-lg`, số `.title.bold.monospacedDigit()`, dòng dưới `.footnote` secondary = tên + scope ("Slow Shutter · All Time"), menu ⋯ chuyển vào context menu (long press / right click) và giữ nút ⋯ chỉ ở edit mode. Giữ nguyên thứ tự do người dùng sắp. Chi phí: nhóm run-length ở `StatisticsScreen.rows/columns`, 1 view mới; làm lại accessibility cho menu. Đây là đề xuất "đẹp hơn" chứ không phải sai luật.
- Bằng chứng: IP_Statistics.png, PH_Statistics.png; ChartCard.swift:44-62.

### VIS-06 Onboarding: icon amber + nút Continue xanh hệ thống; trên iPad nút trải 1320pt; khoảng cách ngoài thang
- Màn / thiết bị: Onboarding · PH, IP, DI, DC
- Mức: nên sửa
- Ở đâu: APP (Features/Onboarding/OnboardingScreen.swift:26-31, 42, 71, 82) + BOARD (nút Continue vẽ xám, nên board không lộ ra xung đột màu)
- Vấn đề: (1) `ShotDexApp` không `.tint(...)` (DESIGN §10.6), nên `.borderedProminent` Continue là **xanh hệ thống**, còn mark và 4 icon hàng là amber: màn đầu tiên người dùng thấy có hai màu nhấn tranh nhau. Accent ở đây cũng không nằm trong danh sách đã duyệt (badge, active editor, chart). (2) IP_Onboarding.png: nội dung là cột ~700pt lệch trái-giữa nằm ở nửa trên, nút Continue rộng **1320pt** (`padding(.horizontal, 28)`, không `maxWidth`), nửa dưới màn trống ~480pt: đúng thứ §10.1c cấm (layout điện thoại bị kéo giãn). (3) Hằng số 28 / 22 / 40 / 56 / padding dọc 6 đều nằm ngoài thang 4/8/12/16/20/24.
- Đề xuất: giữ **một** màu nhấn: icon hàng dùng `.primary` hierarchical (hoặc `.secondary`), chỉ mark ShotDex giữ amber (đó là hình icon app, hợp lý) và Continue để xanh hệ thống như mọi control chuẩn; hoặc ghi vào DESIGN một ngoại lệ có tên "onboarding: tint amber cho Continue". Khuyến nghị cách đầu (không cần ngoại lệ). Trên regular width: bọc `pitch` và nút trong `.frame(maxWidth: 480)` canh giữa, đặt pitch canh giữa dọc (`Spacer` hai đầu đã có, nhưng ScrollView không cho nó giãn: dùng `GeometryReader` + `minHeight`). Spacing: 28 -> 24, 22 -> 24, 40 -> 24 + safe area, 6 -> 8; mark 56pt có thể giữ vì là glyph (không phải khoảng cách).
- Bằng chứng: IP_Onboarding.png, PH_Onboarding.png, OnboardingScreen.swift.

### VIS-07 Ba công cụ tầng D "nhỏ" tự vẽ ba kiểu: segmented, nút chính, nơi đặt Cancel/Save
- Màn / thiết bị: Compress, CollageExport, VideoTrim · mọi thiết bị
- Mức: nên sửa
- Ở đâu: APP (Editing/CompressionScreen.swift:55-67, 178-196, 272-320; Collage/CollageExportScreen.swift:195-210, 293-320; Library/VideoTrimScreen.swift:60-70)
- Vấn đề: cùng một khái niệm (chọn Format / Size / Quality rồi Lưu) có ba hình dạng.
  - **Segmented**: Compress dùng `Picker(.segmented)` hệ thống (đoạn chọn = xám sáng, PH_Compress.png), CollageExport dùng `CollageSegmentPicker` tự vẽ (đoạn chọn = **amber**, chữ đen, PH_CollageExport.png). Hai "Format: JPEG | HEIC" khác hẳn nhau. Theo DESIGN §9, "active = nền accent + glyph đen" ở tầng D, nên Compress lệch; nhưng §10.3 cho photo editor "active = nền trắng + glyph đen", nên hệ thống thực ra có hai quy tắc active và hai tool này mỗi cái chọn một.
  - **Nút chính**: Compress = hàng cuối form, trắng/amber (VIS-01); Collage = pill amber dưới card; Trim = chữ "Save" amber trên top bar. DESIGN §10.3 nói tầng D = "Cancel trái, tiêu đề, Save/Done phải". Compress đặt Cancel ở nav bar hệ thống nhưng không có Save ở đó.
  - **Cancel**: Compress = `Button("Cancel")` trong nav bar hệ thống nền `panelSolid` (board vẽ xanh, cần chụp sim iOS 26 để xác nhận Cancel là kính hay xanh); Trim = chữ trắng custom; Collage = nút chevron kính tròn.
  - Hai nút lưu (`CollageExportScreen.saveButton` và `CompressionScreen.exportButton`) copy-paste cùng 8 dòng (height 50, `Radius.md`, accent) — "hệ thống thứ hai" mà §1.5 cấm.
- Đề xuất: thêm `EditorPrimaryButton(title:systemImage:isEnabled:)` vào `Editing/EditorTheme.swift` (nền `EditorTheme.accent`, glyph đen, cao `primaryActionHeight`, `Radius.md`, disabled = `EditorTheme.control` + `dimText`), và `EditorSegmentedPicker` (từ `CollageSegmentPicker`) dùng cho cả Compress và Collage; quyết định một quy tắc "active" cho tool tầng D ngoài photo editor = amber (khớp §9). Compress: giữ nút ở đáy (vì form dài), nhưng đưa Cancel về kính tầng D cùng kiểu Collage back. Chi phí: 2 component, đổi ~6 call site; Compress mất segmented native (a11y hiện tốt hơn): giữ `accessibilityTraits` khi tự vẽ.
- Bằng chứng: PH_Compress.png, PH_CollageExport.png, PH_VideoTrim.png; các dòng nguồn trên.

### VIS-08 Pill/chip điều kiện lọc: 4 công thức capsule + nút Clear/Edit viết 3 lần + 2 quy ước nền
- Màn / thiết bị: Library (FilterTokenBar), AdvancedSearch bar, SmartAlbum detail · PH, IP, DI, DC
- Mức: nên sửa
- Ở đâu: APP (Library/FilterTokenBar.swift:116-130; Albums/SmartAlbumConditionsBar.swift:44-90; Library/AdvancedSearchSheet.swift:190-210; Albums/SmartAlbumRuleRow.swift:62-76; Library/LibraryScreen.swift:915-919)
- Vấn đề: (a) nút glass "Clear" / "Edit · Clear" được lặp ở `FilterTokenBar`, `SmartAlbumConditionsBar` (comment ghi "the same capsule as AdvancedSearchBar's Edit/Clear") và `AdvancedSearchBar`, cùng `.padding(.horizontal, 14)` + `minHeight: 34` — 14 và 34 đều không có trong thang (pill A/B = 32, spacing 4/8/12/16/20/24). (b) Chip điều kiện đang bật có 3 công thức: `ActiveConditionChip`, text-capsule 10/5 trong `SmartAlbumConditionsBar` (`secondarySystemFill`), `menuToken` 10/6 trong rule row, và "Match all" 8/3 `tertiarySystemFill`. (c) Hai thanh nói cùng việc nhưng khác chất liệu: `FilterTokenBar` ghi rõ "No background... floating chrome" còn `SmartAlbumConditionsBar` kết thúc bằng `.background(.bar)` — một dải đặc có đường biên, chính là cái FilterTokenBar tránh.
- Đề xuất: một `GlassTextPill(_ title:)` (hoặc `FilterBarActions(onEdit:onClear:)`) trong `Shared/`, chiều cao 32 (`AppTheme.Size.pillHeightLight`), padding ngang 12, `.glassBackground(Capsule())`; một `ConditionChip` cho mọi chip tĩnh (`secondarySystemFill`, 12/4, `.footnote`); bỏ `.bar` của SmartAlbumConditionsBar để thành chrome nổi như FilterTokenBar. Chi phí: ~1 ngày, 5 file; phải chụp sim để thấy thanh smart album không bị chữ chồng lên lưới khi bỏ nền (FilterTokenBar xử lý bằng `fadingTrailingEdge` + safeAreaInset).
- Bằng chứng: các dòng nguồn trên; PH_SmartAlbum.png (2 chip + "Match all" thẳng hàng một dải).

### VIS-09 Hero "On This Day" 260pt chiếm hơn một nửa màn trong của Duo (669pt cao)
- Màn / thiết bị: Collections · DI (và iPad ở cửa sổ ngắn)
- Mức: nên sửa
- Ở đâu: APP (Features/Albums/AlbumsScreen.swift:1215-1223 `CollectionsHeroMetrics.height`; 13-14) — hậu quả của DESIGN.md §10.1e ("180 compact → 260 regular")
- Vấn đề: quy tắc chỉ nhìn `horizontalSizeClass`. Màn trong Duo là regular-width nhưng chỉ cao 669pt: nav ~52 + hero 260 + heading ~40 + tile 192 = ~545, chỉ còn ~120pt: DI_Collections.png thấy đúng một hàng "Smart Albums" và tiêu đề "My Albums" nằm sát đáy; hàng Media Types/Utilities cách 2 lần cuộn. Lý lẽ §10.1e (chống dải letterbox 7:1) vẫn đúng ở 951pt rộng: 260pt = 3.7:1, 180pt = 5.3:1 — vẫn xem được.
- Đề xuất: hero = `min(260, max(180, 0.28 * containerHeight))` đọc qua `GeometryReader`/`containerRelativeFrame`, tức iPad 13" ngang (1032 cao) vẫn ~260-290, Duo inner (669) ra 187, cửa sổ iPad Split View thấp cũng tự co. Cập nhật §10.1e. Chi phí: 6 dòng, một test cho hàm thuần `CollectionsHeroMetrics.height(containerHeight:isRegularWidth:)`.
- Bằng chứng: DI_Collections.png (hero 835x~230 + 1 hàng tile), IP_Collections.png; AlbumsScreen.swift:13-14.

### VIS-10 Collections: tiêu đề section không có affordance, mọi thứ cuộn ngang, không có "xem tất cả"
- Màn / thiết bị: Collections · PH, IP, DI, DC
- Mức: gợi ý
- Ở đâu: APP (AlbumsScreen.swift:299-303, 474-478, 524-527, 704-707 — bốn lần `Text(title).font(.title2.bold())`)
- Vấn đề: Photos (đối chuẩn DESIGN §10.1d dẫn) dùng tiêu đề section là nút có chevron ("My Albums >") mở lưới tất cả. Ở ShotDex tiêu đề là chữ chết; một người có 80 album chỉ lướt ngang từng hàng 2-3 tile, không có cách nhìn toàn bộ. Bốn bản sao cùng một tiêu đề `.title2.bold()` + `.padding(.horizontal)` cũng là chỗ dễ lệch.
- Đề xuất: component `CollectionSectionHeader(title, destination?)`: `.title2.bold()` + `Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)` khi có đích; đích = `AlbumGridScreen` (lưới `LazyVGrid adaptive(minimum: 132)` các tile cover, cùng `AlbumCoverTile`). Cho My Albums và Smart Albums trước. Chi phí: 1 view + 1 màn lưới nhỏ; cũng giải được yêu cầu "xem hết" mà ux-reviewer có thể nêu. Phá luật nào? Không (DESIGN §10.1d chỉ nói "mỗi nhóm một hàng cuộn ngang"); cần bổ sung "See All" vào §10.1d.
- Bằng chứng: PH_Collections.png / IP_Collections.png (tiêu đề trơn, tile bám lề trái do board lỗi), AlbumsScreen.swift.

### VIS-11 Settings trên iPhone: một danh sách dài duy nhất, trong khi iPad có sidebar 9 mục có icon
- Màn / thiết bị: Settings · PH, DC (DI/IP đã có sidebar)
- Mức: gợi ý
- Ở đâu: APP (Features/Settings/SettingsScreen.swift:144-165 `compactLayout`, `settingsList` = `groupedList(SettingsGroup.allCases)`)
- Vấn đề: PH_Settings.png: màn hình đầu chỉ chứa "Photo Library" (9 hàng + 2 footer) rồi tới Notifications; toàn bộ ~9 nhóm × 3-10 hàng (Thumbnail Metadata, Playback, People and Pets, File Servers...) nằm trong một cuộn. Icon SF Symbols chỉ có ở sidebar iPad (`item.systemImage`), tức iPhone không có điểm neo thị giác để quét. Ô Search Settings giải quyết một phần, nhưng người không biết tên mục thì phải cuộn.
- Đề xuất: iPhone cũng dùng **cùng** `SettingsSection.allCases` (đã có `systemImage`) làm trang gốc: `List(.insetGrouped)` 9 hàng `Label(item.title, systemImage:)` + chevron, bấm đẩy `detailRoot(for:)` (đã tồn tại và đã được compact stack dùng khi cửa sổ co lại: comment ở dòng 149-150). Giữ ô search ở đầu. Đây vẫn "đủ mọi chức năng" (luật NF-05 §37) vì chỉ thêm 1 tầng điều hướng, và bằng đúng hình dạng Settings hệ thống mà DESIGN §10.1f lấy làm chuẩn. Chi phí: ~30 dòng + sửa §10.1 ("compact = danh sách mục, bấm vào mở nhóm"); đổi deep-link `openSettings(at:)` để push thêm 1 tầng. Rủi ro: thêm 1 chạm cho thao tác thường (Re-index).
- Bằng chứng: PH_Settings.png vs IP_Settings.png; SettingsScreen.swift:144-165.

### VIS-12 Accent rò vào tầng A ngoài danh sách đã duyệt
- Màn / thiết bị: Support, SupportThread, Camera Database, Advanced Search/Chart Editor (AutocompleteTokenField), DateRange, Onboarding · mọi thiết bị
- Mức: nên sửa (hoặc cập nhật DESIGN)
- Ở đâu: APP (Support/SupportModel.swift:166-168 `status.tint`; SupportScreen.swift:224-229 vote; Settings/CameraDatabaseScreen.swift:80 checkmark; Shared/AutocompleteTokenField.swift:82; Statistics/DateRangePickerSheet.swift:172-185; Onboarding/OnboardingScreen.swift:42,82)
- Vấn đề: DESIGN §4/§10.6: accent chỉ cho "phần ShotDex tự vẽ: badge chọn, editor active, chart", mọi control chuẩn giữ nhìn mặc định hệ thống. Thực tế accent amber xuất hiện cạnh control xanh hệ thống trong các list/form tầng A: dấu check chọn sensor format (hàng chuẩn của `List`, vốn là xanh hệ thống trong mọi form iOS), nút `plus.circle` gợi ý token, nút vote, chữ trạng thái "Planned / In Progress" (amber) bên cạnh "Shipped" (xanh lá) và "Considering" (xám), ô ngày chọn trong calendar. Kết quả: trong cùng một màn Settings, Toggle xanh lá hệ thống + checkmark amber + nút "Add" xanh dương.
- Đề xuất: chia hai nhóm. (a) Control chuẩn (check hàng, `plus.circle` gợi ý, "Add"): bỏ accent, dùng `.tint`/mặc định hệ thống. (b) Thứ ShotDex tự vẽ và mang nghĩa trạng thái (trạng thái ticket, vote, day-range): **ghi vào DESIGN §10.6 một dòng "chỉ báo trạng thái tự vẽ"** để chúng hợp lệ; trạng thái dùng màu có nghĩa chứ không dùng accent (Planned = `.blue`? hệ thống; In Progress = `.orange` là cảnh báo cố định theo §4 nên cũng không) — gợi ý đơn giản nhất: nhãn trạng thái luôn `.secondary`, chỉ Shipped `.green`; vote chọn = `.primary` đậm + `arrowtriangle.up.fill`. Chi phí: 8 dòng + 1 dòng DESIGN.
- Bằng chứng: grep `appAccent` trên Features (kết quả ở trên); PH_Support.png.

### VIS-13 Radius viết thẳng số thay vì token; vài chỗ ngoài thang
- Màn / thiết bị: Statistics, Library, Detail, Rule row, Video Trim, Server Browser, Widget preview
- Mức: nit
- Ở đâu: APP — Statistics/ChartCard.swift:237 (`cornerRadius: 16`; `InsightsCard` đã dùng `AppTheme.Radius.lg` nên hai card cạnh nhau hai nguồn), Library/LibraryScreen.swift:1250 (`12`), Library/PhotoDetailScreen.swift:1739 (`GlassPanel(cornerRadius: 28)`), Albums/SmartAlbumRuleRow.swift:157 và Settings/PhotoWidgetSettingsScreen.swift:794 (`8`), Library/VideoTrimScreen.swift:237 (`4`, ngoài thang), ServerImport/ServerBrowserScreen.swift:922 (`4`, **không** `.continuous`), Settings/PhotoWidgetPreview.swift:156,162 (`6`, ngoài thang)
- Vấn đề: DESIGN §5 chỉ cho 8/12/16/22/28 và bắt buộc `.continuous` qua `RoundedRectangle.app(_:)`.
- Đề xuất: thay bằng `RoundedRectangle.app(AppTheme.Radius.lg/md/sm/xxl)`. Hai giá trị 4 và 6 là chi tiết rất nhỏ (tay cầm trim, nhãn badge): hoặc dùng `sm` (8) hoặc thêm vào DESIGN một ngoại lệ có tên như `r-track`. Chi phí: ~10 dòng.
- Bằng chứng: các dòng trên (grep `cornerRadius: [0-9]`).

### VIS-14 Khoảng cách ngoài thang lan khắp màn tầng A/B/C
- Màn / thiết bị: nhiều màn
- Mức: nit (hệ thống)
- Ở đâu: APP — grep `.padding(... 6|10|14|18|22|28)` ngoài Editing/VideoStudio ra ~40 điểm. Tiêu biểu: Library/FilterTokenBar.swift:116,126; Library/SelectionBarViews.swift:35,134 (18); Library/CompareScreen.swift:493 (18), 701 (10), 721 (14); Albums/SmartAlbumConditionsBar.swift:51 (14), 71, 87 (10); Support/SupportScreen.swift:200 (6); ServerImport/ServerBrowserScreen.swift:185,765; ServerUpload/ServerUploadSheet.swift:268 (6); ServerImport/ServerDownloadSheet.swift:204, ServerEditFetchSheet.swift:61 (6); Features/Albums/AlbumsScreen.swift:354 (`.padding(.top, 4)` ok)
- Vấn đề: §6 "không dùng 6, 10, 14, 18 cho khoảng cách". Hầu hết là padding bên trong chip/pill (VIS-08 sẽ xoá phần lớn) hoặc `.padding(.vertical, 6)` trên hàng list (bản thân List đã có inset).
- Đề xuất: sau khi có component pill dùng chung (VIS-08) thì còn lại ~15 điểm; sửa dần theo thang (6 → 4 hoặc 8; 10 → 8 hoặc 12; 14 → 12 hoặc 16; 18 → 16 hoặc 20). Cân nhắc một lint nhỏ trong `Tools/` grep các literal này để không phình thêm. Chi phí thấp, nhưng mỗi thay đổi 2pt phải chụp sim.
- Bằng chứng: grep ở trên.

### VIS-15 Nút ⋯ ở header card (Statistics): vùng chạm ~22pt, và nằm quá gần nội dung
- Màn / thiết bị: Statistics · PH, DC (ngón tay), IP (con trỏ)
- Mức: nên sửa
- Ở đâu: APP (ChartCard.swift:~249-256 `Image(systemName: "ellipsis.circle").font(.title3)`; InsightsCard.swift:42-52)
- Vấn đề: `Menu` chỉ bọc một `Image` cỡ `.title3` (~22pt), không có `frame(minWidth: 44, minHeight: 44)`. Dưới "44×44 chạm tối thiểu" (DESIGN §6). Ngoài ra mỗi card có icon `ellipsis.circle` xám nổi bật 7-8 lần trên một màn, rất nhiễu, là hành động ít dùng (Edit/Duplicate/Delete) mà chiếm quyền thị giác ngang tiêu đề.
- Đề xuất: `Image(systemName: "ellipsis")` (không vòng), `.font(.body.weight(.semibold))`, `frame(width: 44, height: 44)` + `contentShape(.rect)`, và đặt padding âm `-8` để giữ canh phải 16; hoặc chuyển Edit/Duplicate/Delete vào `contextMenu` + giữ nút ⋯ chỉ khi `editMode`. Cho InsightsCard tương tự. Chi phí: 5 dòng.
- Bằng chứng: PH_Statistics.png (hai nút ⋯ ở Insights và Top Camera), mã nguồn.

### VIS-16 Ba công thức empty state; DESIGN.md mô tả công thức thứ tư
- Màn / thiết bị: Library, Places, Trips, Collections, Duplicates, Statistics, Metadata · mọi thiết bị
- Mức: nên sửa (nhất quán)
- Ở đâu: APP — `ContentUnavailableView` ×21 (Albums:109,194; Duplicates:226,243; Statistics:121,150...), hand-rolled symbol 44pt trong Places/PlacesMapScreen.swift:84-96 và Places/TripsScreen.swift:55-67 (đúng chữ DESIGN §11), hand-rolled `.largeTitle` + `.footnote` trong Library/LibraryScreen.swift:764-800
- Vấn đề: §11 nói "icon 44pt secondaryLabel + một câu `.subheadline` + tối đa một nút `.borderedProminent`", nhưng phần lớn màn dùng `ContentUnavailableView` của hệ thống (symbol ~48-60, tiêu đề `.title2.bold`, mô tả `.subheadline`). Places/Trips (hai màn cùng họ "Collections → Utilities") thì theo tài liệu và trông nhỏ, nhạt hơn Duplicates cạnh nó. Library lại tự vẽ lần thứ ba với `.largeTitle`.
- Đề xuất: theo nguyên tắc 1 (iOS-native trước), **sửa DESIGN §11 thành "dùng `ContentUnavailableView` (Label + description + tối đa một action `.borderedProminent`)"** và đổi Places, Trips, và 2 nhánh trong Library về component đó; icon theo hệ thống. Chi phí: ~4 file, bỏ ~60 dòng.
- Bằng chứng: grep ContentUnavailableView; TripsScreen.swift:55-67; LibraryScreen.swift:764-800; DESIGN.md §11.

### VIS-17 Chừa chỗ chrome cho iOS < 26 viết tay 90pt ở 4 màn thay vì token
- Màn / thiết bị: Collections, Statistics, ServerBrowser, Duplicates · iOS 17-25
- Mức: nit
- Ở đâu: APP (Albums/AlbumsScreen.swift:363-365 `Color.clear.frame(height: 90)`; Statistics/StatisticsScreen.swift:289; ServerImport/ServerBrowserScreen.swift:202; Duplicates/DuplicatesScreen.swift:70)
- Vấn đề: DESIGN §6: "Màn cuộn nào cũng dùng `AppTheme.Size.bottomChromeClearance`, không tự viết nhánh `#available`" (token trả 8 trên iOS 26, 100 trước đó). Cả bốn màn vẫn tự viết `if #unavailable(iOS 26.0)` với 90 (hoặc spacer riêng), nên số này (90) lệch token (100) 10pt: đúng bệnh mà doc comment của token nói đã từng xảy ra ("two of them disagreeing on the number").
- Đề xuất: thay bằng `Color.clear.frame(height: AppTheme.Size.bottomChromeClearance)` bỏ nhánh `#available`. Chi phí: 4 chỗ; chụp sim iOS 18.6 để xác nhận.
- Bằng chứng: AlbumsScreen.swift:363; grep `unavailable(iOS 26`.

### VIS-18 "Uploaded to Server": glyph hàng lệch từ điển icon, hàng tổng đứng ngoài, mã tự đặt 12 thay vì token
- Màn / thiết bị: Uploaded to Server · PH, IP, DI, DC
- Mức: nit
- Ở đâu: APP (ServerUpload/UploadedToServerScreen.swift:~108 `externaldrive.connected.to.line.below`, ~43 `photo.on.rectangle`, `HStack(spacing: 12)`)
- Vấn đề: DESIGN §8: Upload/Uploaded to Server = `server.rack`; `externaldrive.connected.to.line.below` là glyph đĩa của "ô Network" trong Collections (dấu "đây là folder trên server"). Ở đây nó dùng cho hàng đích (mỗi hàng = một folder trên server): đúng nghĩa với Network nhưng không có dòng nào trong từ điển. Hàng tổng "All Uploaded Photos 712" nằm trong section riêng *sau* footer của section trên (PH_UploadedToServer.png), nên đọc ra như hàng phụ trong khi nó là hàng quan trọng nhất (mở toàn bộ ảnh). `spacing: 12` dùng số thay vì `AppTheme.Spacing.md`.
- Đề xuất: đưa "All Uploaded Photos" lên đầu thành section đầu (không header), rồi section "Where They Are"; glyph hàng tổng `server.rack`; ghi "Hàng đích server trong Uploaded to Server = `externaldrive.connected.to.line.below`" vào từ điển §8. Chi phí: 10 dòng.
- Bằng chứng: PH_UploadedToServer.png; UploadedToServerScreen.swift.

### VIS-19 Photo Info (Metadata): bảng kính trên ảnh, chữ phụ `.secondary` trên ảnh sáng/tối đều khó đọc; thanh tiêu đề đè lên bảng
- Màn / thiết bị: Metadata · IP (rõ nhất), PH, DI, DC
- Mức: nên sửa (cần chụp sim để xác nhận)
- Ở đâu: BOARD cho phần vẽ (PH_Metadata.png vẽ chữ chồng lên ảnh và nội dung tràn ra khỏi panel, đó là lỗi board), nhưng IP_Metadata.png gợi ý một vấn đề APP có thật: Library/MetadataPanel.swift dùng `.foregroundStyle(.secondary)` (dòng 161,181,287,310,319) trên `GlassPanel(cornerRadius: 28)` đặt trên ảnh bất kỳ; ở IP_Metadata.png nhãn "Lens Range", "Firmware / Software", "Exposure Program" đã chồng lên đường chân trời sáng-tối.
- Vấn đề: DESIGN nguyên tắc 2: chrome không tranh chấp với ảnh nhưng cũng phải đọc được. Văn bản nhiều dòng trên Liquid Glass phụ thuộc ảnh nền: ảnh trời sáng + `.secondary` ≈ 2:1. Thanh tiêu đề (pill ngày/RAW/camera) cũng đè lên đỉnh panel (y 30-85 vs panel bắt đầu y 85, IP_Metadata.png) tạo viền chạm nhau.
- Đề xuất: panel dùng nền kính **dày** cho nội dung dài (`.regularMaterial` bên trong `GlassPanel`, hoặc `glassEffect(.regular.tint(.black.opacity(0.35)))`), và `.primary` cho giá trị, `.secondary` chỉ cho nhãn nhưng nền đã đủ tối. Không dùng `Color(.label)` kiểu `.secondary` trên ảnh. Dịch panel xuống `top = safeArea.top + 52 + 12`. Chi phí: 1 modifier + 1 padding; kiểm bằng ảnh trời trắng. Yêu cầu: chụp sim IP và PH với một ảnh sáng (ví dụ ảnh tuyết) ở trạng thái Photo Info mở.
- Bằng chứng: IP_Metadata.png, PH_Metadata.png; MetadataPanel.swift:161-319.

### VIS-20 Compress trên iPad: form cột 660pt giữa màn, preview và nút nằm trong cùng một cột dài; vùng đen hai bên
- Màn / thiết bị: Compress · IP, DI
- Mức: gợi ý
- Ở đâu: APP (Editing/CompressionScreen.swift:128-144 `maximumFormWidth`)
- Vấn đề: IP_Compress.png: cột ~660pt ở giữa 1376pt, hai bên đen trống ~360pt mỗi bên, trong khi preview chỉ cao 250pt (nhỏ nhất ở màn to nhất). Với một công cụ mà ảnh là chính (nguyên tắc 2) thì preview nên lớn hơn form. DI_Compress.png (669pt cao) phải cuộn mới thấy nút "Resize".
- Đề xuất: ở regular width + landscape (hoặc `usesSidebar`-giống) chia hai cột: trái = preview/gallery full-height (≥60% rộng), phải = form 360pt + nút ghim đáy, đúng hình dạng "stage + panel" của DESIGN §10.3; ở portrait/compact giữ cột hiện tại. Chi phí: ~40 dòng bố cục, dùng lại `CompressionPreview`. Cân nhắc kỹ với luật §10.1c "không to hơn": ở đây là thêm vùng ảnh, không phải phóng to nút.
- Bằng chứng: IP_Compress.png, DI_Compress.png.

### VIS-21 Hàng drill "Insights" và nhiều hàng khác dùng chevron `>` đậm mà ở list hệ thống chevron mờ; nhiều dạng chevron
- Màn / thiết bị: Statistics (Insights), ServerList, UploadedToServer, Support · PH
- Mức: nit
- Ở đâu: APP (Statistics/InsightsCard.swift:~118 `.font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)`) vs `NavigationLink` chuẩn của `List`
- Vấn đề: chevron "tự vẽ" ở Insights = `.footnote.semibold.tertiary`; chevron hệ thống trong `NavigationLink` = `.callout`-ish, `.tertiaryLabel`. Ở board, các chevron `>` ở Insights (12pt) và ở ServerList (14pt, đậm hơn) nhìn khác cỡ. Đây là lỗi nhỏ nhưng cho thấy trong một màn tab Statistics có cả hàng tự vẽ và `NavigationLink` mà cạnh nhau.
- Đề xuất: giữ như vậy, ghi vào DESIGN "chevron tự vẽ trong card = `.footnote.weight(.semibold)` `.tertiary`" để mọi chỗ (InsightsCard, footers, NetworkShortcutTile) dùng chung. Chi phí: 1 dòng tài liệu.
- Bằng chứng: PH_Statistics.png vs PH_ServerList.png.

### VIS-22 BOARD: nhiều board không phản ánh app, nên không thể dùng làm bằng chứng thị giác
- Màn / thiết bị: Main, PH/IP/DI/DC các màn liệt kê
- Mức: nên sửa (cho canvas, không cho app)
- Ở đâu: BOARD (build/design/app/project/*.dc.html)
- Vấn đề (đã xác minh bằng cách đọc board, không phải app):
  1. **Template rò**: `{{c.name}}` (Collections tiles, SmartAlbumEditor), `{{p.ft}}/{{p.dur}}/{{p.meta}}` (Main, LibrarySelect, AdvancedSearch), `{{p.title}}/{{p.sub}}` (Trips), `{{p.date}}` (Creations), `{{h.title}}` (OnThisDay), `{{k.k}}` (Search), `{{p.badge}}/{{p.name}}` (ServerBrowser), `{{c.title}}` (Duplicates).
  2. **Sheet vẽ chồng lên màn gốc** thay vì thay thế: ServerForm (list server xuyên qua form), SmartAlbumEditor, AdvancedSearch, ChartEditor, DateRange, Share (tab bar thấy xuyên qua sheet).
  3. **Swift Charts và ảnh không vẽ**: Statistics có khoảng trống thay cho chart (PH_Statistics.png), Library/LibrarySelect/Duplicates/OnThisDay/AlbumDetail không có ô ảnh; Collage canvas trắng.
  4. **Control hệ thống vẽ xám/trắng**: mọi Toggle là pill trắng không phân biệt on/off (PH_Settings.png, PH_Compress.png), nút Cancel của Compress vẽ xanh trong khi Settings "Done" vẽ xám; tile bám lề trái x=0 không có inset 16 (PH_Collections.png) dù code dùng `.padding(.horizontal)`.
  5. **Màn gốc trống ở tablet**: Collections IP chỉ có 1 tile mỗi hàng.
- Đề xuất: sửa renderer trước khi dùng canvas để review thị giác/design-parity: (a) clone-fill dữ liệu mẫu cho mọi `{{...}}`; (b) mỗi board sheet chỉ vẽ sheet + scrim, không vẽ màn dưới (hoặc làm mờ); (c) thay Swift Charts bằng khối SVG tĩnh; (d) vẽ Toggle on/off đúng màu hệ thống; (e) thêm ảnh mẫu (đã có ảnh núi ở Viewer, tái dùng). Đây là việc của người sở hữu `Tools/design-board`, không phải của app. Cho đến khi sửa, đừng báo "app lệch board" khi board xám.
- Bằng chứng: Main.png, PH_Collections.png, PH_ServerForm.png, PH_SmartAlbumEditor.png, PH_Statistics.png, PH_Search.png, PH_Trips.png, PH_Duplicates.png.

---

## Quy tắc DESIGN.md chưa có / cần sửa (đề xuất cho tài liệu)
1. **Màu chữ trên accent** (VIS-01): đen cho tầng D và mọi chỗ ngoài badge lưới; thêm token.
2. **Active state của tool tầng D ngoài photo editor** (VIS-07): hiện có hai quy tắc (amber ở §9, trắng ở §10.3); nên ghi rõ photo editor là ngoại lệ duy nhất.
3. **Component nút chính tầng D** và **segmented tầng D** chưa có tên trong §9 (VIS-07).
4. **Chỉ báo trạng thái tự vẽ ở tầng A** (VIS-12): được dùng accent hay không, và trạng thái ticket/vote lấy màu gì.
5. **Thanh điều kiện lọc** (`FilterTokenBar`, `SmartAlbumConditionsBar`, `AdvancedSearchBar`): kích thước pill (32 vs 34) và chrome nổi vs dải `.bar` (VIS-08).
6. **Empty state** (VIS-16): công thức §11 đã lệch 21 chỗ dùng; nên chuyển sang `ContentUnavailableView`.
7. **Section header của Collections** có chevron "See All" (VIS-10).
8. **Hero theo chiều cao** (VIS-09): §10.1e chỉ nhìn size class.
9. **Số liệu** (VIS-03): "mọi số đếm hiển thị cho người dùng dùng `.formatted(.number)`"; hiện §7.3 chỉ nói monospacedDigit.
10. **Lỗi tài liệu**: tiêu đề §4 "Màu" nhưng mục con đánh số 3.1/3.2/3.3/3.4; Checklist §14 dòng "Icon lấy từ từ điển mục 7" thực ra là mục 8; §3 trỏ "mục 4" cho thang radius nhưng nó ở §5, và "mục 5/10" cho spacing/animation (§6/§11). Đánh số lại để checklist không dẫn nhầm.
