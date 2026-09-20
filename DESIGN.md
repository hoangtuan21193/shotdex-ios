## 1. Nguyên tắc gốc

1. **iOS-native trước, tùy biến sau.** Dùng control và font ngữ nghĩa của SwiftUI. Chỉ vẽ tay khi hệ thống không có sẵn (jog dial, histogram, mask overlay, grid ảnh).
2. **Ảnh là nội dung chính.** Chrome không bao giờ tranh chấp với ảnh: nền tối, kính mờ, không đổ màu lên ảnh.
3. **Một hành động — một chỗ.** Cùng một hành động (Delete, Share, Compare, Compress) phải nằm cùng vị trí, cùng icon, cùng nhãn ở mọi màn hình.
4. **Accent là biến, không phải hằng.** Không hardcode màu accent. Đọc từ `\.appAccent` (environment) hoặc `EditorTheme.accent`. Xem `AppAccentTheme.swift`.
5. **Không tạo hệ thống thứ hai.** Nếu cần một bề mặt/kính/nút mới, mở rộng component chung, không copy style vào file feature.

---

## 2. Bốn tầng bề mặt (Surface tiers)

Mỗi màn hình phải khai báo rõ mình thuộc tầng nào. Không trộn hai tầng trong cùng một vùng.

| Tầng | Dùng khi | Nền | Component gốc |
| --- | --- | --- | --- |
| **A. System** | Danh sách, form, cài đặt, thống kê, rule builder | `Color(.systemGroupedBackground)` + `List`/`Form` | SwiftUI chuẩn |
| **B. Content** | Lưới ảnh, album, kết quả tìm kiếm | `Color(.systemBackground)`, ảnh tràn viền | `PhotoGridCollectionView` |
| **C. Glass chrome** | Thanh nổi trên ảnh: tab bar, selection bar, nút tròn, panel trạng thái | Kính mờ trong suốt | `GlassPanel`, `GlassIconButton`, `LiquidGlassTabBar`, `.glassBackground(_:)` |
| **D. Tool (dark)** | Toàn màn hình chỉnh sửa: Photo Editor, Compare, Compress, Collage, Video Studio | `EditorTheme.background` (đen) / `panelSolid` `#0F1012` | `EditorTheme`, `.editorGlass()`, `EditorPillLabel` |

**Collage và Video Studio thuộc tầng D**, không có ngoại lệ: cả hai thao tác trực tiếp lên pixel/khung hình nên cần nền trung tính để đánh giá màu. Kéo theo đó, bước chọn layout collage và **timeline video** phải nằm **trong màn hình** tầng D — không được tách ra thành sheet hệ thống, vì như vậy màn hình lại lai hai tầng.

**Panel ngữ cảnh Video Studio là panel trượt IN-SCREEN, không phải sheet hệ thống** (2026-08-12). Inspector của Video Studio (thông số của clip/chữ/sticker/nhạc đang chọn, và các global tool) trượt lên từ đáy màn hình khi có selection và trượt xuống khi bỏ chọn — trông như bottom sheet (grabber 36×5, bo góc trên `Radius.lg`, nền `panelSolid`, kéo xuống để đóng) nhưng vẽ trong màn hình. Hai lý do, cả hai đều bắt buộc: (1) giữ đúng quy tắc tầng D ở trên; (2) các picker của studio (font, media, nhạc, sticker) **là** sheet hệ thống mở từ chính panel này — UIKit không present được sheet từ một view đang present sheet khác, nên inspector mà là sheet thì mọi nút Replace/Font sẽ im lặng không mở. Panel dùng `EditorTheme.animation` + `.transition(.move(edge: .bottom))` và **trượt đè lên** hàng công cụ + bottom bar — **không đẩy layout bên dưới**, để timeline đứng yên đúng vị trí user vừa cuộn tới.

**Quy tắc chọn tầng cho màn hình mới**

- Người dùng đang thao tác trực tiếp lên pixel của ảnh → **D**.
- Người dùng đang chọn/duyệt ảnh → **B**, chrome nổi dùng **C**.
- Người dùng đang nhập điều kiện, tùy chọn, cài đặt → **A**.
- Không bao giờ dùng **A** bên trong **D** (không nhét `Form` vào editor tối) và ngược lại.

---

## 3. Nguồn token: `AppTheme` và `EditorTheme`

Hai file, phân vai rõ:

- **`AppTheme`** (`App/Theme/AppTheme.swift`) giữ **hình học và chuyển động dùng chung cho cả bốn tầng**: thang radius (mục 4), thang spacing và các hằng kích thước (mục 5), animation (mục 10). Không chứa màu — tầng A/B/C đã có system color lo light/dark miễn phí.
- **`EditorTheme`** giữ **bảng màu tối đặc thù** của tầng D và các font token của editor, nhưng đọc radius/spacing/animation từ `AppTheme` thay vì tự định nghĩa.

Một nguồn cho hình học, hai bảng cho màu. Không nhân đôi bảng màu.

---

## 4. Màu

### 3.1 Accent

```swift
@Environment(\.appAccent) private var accent   // view thường
EditorTheme.accent                              // static token trong editor
```

Không dùng `Color.accentColor`, không dùng `.orange`, không hardcode `#EB9526`. Trong `ButtonStyle` phải truyền accent vào qua init (xem `CompressionChoiceStyle`) vì `@Environment` không resolve trong `makeBody`.

### 3.2 Bảng màu tầng A/B/C

Chỉ dùng system color để tự có light/dark:

| Vai trò | Token |
| --- | --- |
| Nền màn hình | `.systemGroupedBackground` |
| Nền card/section | `.secondarySystemGroupedBackground` |
| Nền control phụ | `.secondarySystemFill` |
| Chữ chính / phụ / mờ | `.label` / `.secondaryLabel` / `.tertiaryLabel` |
| Đường kẻ | `.separator` |
| Phá hủy | `.red` (system) |
| Thành công | `.green` (system) |
| Cảnh báo | `.orange` (system) |

### 3.3 Bảng màu tầng D

Chỉ dùng token trong `EditorTheme`: `background`, `panel`, `panelSolid`, `panelTopHairline`, `panelDivider`, `stickyHeader`, `control`, `sliderTrack`, `hairline`, `secondaryText`, `dimText`, `clipping`, `maskRow`, `activeRow`, `glass`, `glassLight`, `glassStroke`, `timelineSelection`, `timelineDestructive`.

`timelineSelection` (`#57BFD1`) chỉ dùng cho **trạng thái chọn trong Video Studio timeline** (clip/băng/overlay đang chọn) — cố ý khác accent để "đang chọn" (xanh) không đụng "đang bật" (vàng accent). `timelineDestructive` (`#FF6B5E`) là glyph phá hủy trong panel ngữ cảnh Video Studio.

Thiếu token thì **thêm vào `EditorTheme`**, không viết `Color(white: 0.13)` trong file feature.

### 3.4 Biểu đồ

`ChartPalette.colors` theo thứ tự đã định. Không tự chọn màu series.

---

## 5. Bo góc (radius scale)

Chỉ dùng 5 giá trị. `style: .continuous` là bắt buộc cho mọi `RoundedRectangle`.

| Token | Giá trị | Dùng cho |
| --- | --- | --- |
| `r-sm` | **8** | Chip nhỏ, badge, thumbnail nhỏ, ô nhập trong rule row |
| `r-md` | **12** | Card, preset chip, hàng danh sách tùy biến, nút lớn |
| `r-lg` | **16** | Section/panel, khung preview, chart card |
| `r-xl` | **22** | Thanh kính nổi (selection bar, action bar) |
| `r-2xl` | **28** | Panel kính lớn (metadata panel, sheet kính) |
| `Capsule` | — | Pill, token filter, tab bar, nút tròn |

Thumbnail trong lưới ảnh: vuông, không bo (do `PhotoGridCollectionView` quản lý).

**Ngoại lệ có tên — timeline Video Studio.** Băng timeline cao 28–32pt, thang chung quá lớn. Chỉ trong `Features/VideoStudio/`:

| Token | Giá trị | Dùng cho |
| --- | --- | --- |
| `r-track` | **6** | băng clip/chữ/lọc/nhạc, ô chuyển cảnh, nút thêm trên rãnh |
| `r-cell` | **10** | ô lệnh trong dải lệnh inspector |
| `r-export` | **19** | pill Export |

Định nghĩa trong `VideoStudioMetrics` (`trackRadius`/`commandCellRadius`/`exportPillRadius`). **Không** dùng ba giá trị này ở màn khác.

---

## 6. Khoảng cách và kích thước

- **Spacing scale:** 4 / 8 / 12 / 16 / 20 / 24. Không dùng 6, 10, 14, 18 cho khoảng cách.
- **Lề ngang màn hình:** 16 (tầng A/B), 16 (tầng D panel), 20 (chrome nổi tầng C).
- **Chiều cao chạm tối thiểu:** 44×44. Nút tròn kính: **52×52** (`GlassIconButton`). Nút icon trong action bar tối: **40×40** trong capsule padding 4.
- **Nút hành động chính (full width):** cao **50**, `r-md`.
- **Pill / token:** cao **28** (tầng D, `EditorPillLabel`) hoặc **32** (tầng A/B).
- **Segmented control:** cao **32**, container `r-sm`+2.
- **Khoảng trống đáy cho chrome nổi:** `AppTheme.Size.bottomChromeClearance` — **8** trên iOS 26 (thanh tab native tự chừa safe area), **100** trước 26 (tab bar tuỳ biến nổi đè lên nội dung). Màn hình cuộn nào cũng dùng token này, không tự viết nhánh `#available`.

---

## 7. Chữ

### 7.1 Tầng A/B/C — dùng font ngữ nghĩa

`.largeTitle` (title màn hình gốc) · `.headline` (tiêu đề section, nhãn Toggle) · `.body` (nội dung) · `.subheadline` (phụ) · `.footnote` (ghi chú, cảnh báo) · `.caption`/`.caption2` (nhãn dưới thumbnail).

Không viết `.font(.system(size:))` ở tầng A/B/C trừ khi khớp glyph với icon (ví dụ `GlassIconButton` dùng size 18 medium — đã là chuẩn).

### 7.2 Tầng D — dùng token `EditorTheme`

`panelTitle` 19 semibold · `groupLabel` 11.5 bold · `rowLabel` 12 · `rowValue` 11.5 mono · `tabLabel` 10.5 · `pillLabel` 11 semibold · `maskTitle` 14.5 semibold · `maskSubtitle` 11.5.

### 7.3 Số liệu

Mọi con số thay đổi theo thời gian thực (%, MB, đếm tiến trình, EXIF) dùng `.monospacedDigit()`.

---

## 8. Icon

- Chỉ dùng **SF Symbols**. Không dùng ảnh PNG cho icon.
- Kích thước: 18 medium (nút chrome), 17 medium (tab bar), 20 (hàng danh sách), 13/11 semibold (pill tầng D).
- **Từ điển icon dùng chung** — không được đổi ở từng màn hình:

| Hành động | Symbol |
| --- | --- |
| Share | `square.and.arrow.up` |
| Delete | `trash` |
| Compare | `rectangle.split.2x1` |
| Compress / Resize | `arrow.down.right.and.arrow.up.left` |
| Collage | `rectangle.split.2x2` |
| Video Studio | `film` |
| Thêm vào album | `rectangle.stack.badge.plus` |
| Nhân bản | `plus.square.on.square` |
| Export EXIF | `doc.badge.arrow.up` |
| Thêm hành động | `ellipsis` (menu) |
| Lưu về Photos | `arrow.down.circle.fill` |
| Crop | `crop` |
| Duplicates (utility) | `square.on.square` |
| Rescan / làm lại | `arrow.clockwise` |

Adjustment icon lấy từ `PhotoAdjustmentKind.systemImage`; mask icon từ `PhotoMaskComponentKind.systemImage`. Không tự chọn lại.

---

## 9. Component dùng chung (bắt buộc tái sử dụng)

| Cần gì | Dùng cái này | File |
| --- | --- | --- |
| Panel kính nổi | `GlassPanel(cornerRadius:)` | `App/Glass/GlassPanel.swift` |
| Nút tròn kính | `GlassIconButton` | `App/Glass/GlassIconButton.swift` |
| Tab bar | `LiquidGlassTabBar` | `App/Glass/LiquidGlassTabBar.swift` |
| Nền kính cho shape bất kỳ | `.glassBackground(_ shape:)` | `Library/SelectionBarViews.swift` |
| Kính trong editor tối | `.editorGlass(cornerRadius:…)` (rounded rect) hoặc `.editorGlass(_ shape:)` (circle/capsule) | `Editing/EditorTheme.swift` |
| Pill trạng thái trên ảnh | `EditorPillLabel` | `Editing/EditorTheme.swift` |
| Hàng slider có nhãn + giá trị | `EditorSliderRow` | `Editing/EditorSliderRow.swift` |
| Lưới ảnh | `PhotoGridCollectionView` | `Shared/PhotoGridCollectionView.swift` |
| Thanh chọn nhiều ảnh | `SelectionBarViews` | `Library/SelectionBarViews.swift` |
| Card biểu đồ | `ChartCard` | `Statistics/ChartCard.swift` |
| Chip điều kiện lọc | `FilterTokenBar` | `Library/FilterTokenBar.swift` |
| Ô nhập khoảng số | `NumericRangeField` | `Shared/NumericRangeField.swift` |
| Ô nhập token gợi ý | `AutocompleteTokenField` | `Shared/AutocompleteTokenField.swift` |
| Section rule builder | `RuleBuilderSections`, `SmartAlbumRuleRow` | `Shared/`, `Albums/` |

**Kính: chỉ ba đường vào** — `GlassPanel`, `GlassIconButton`, `.glassBackground` / `.editorGlass`. Không viết `.background(.ultraThinMaterial, in:)` trực tiếp trong file feature mới.

Mọi helper glass phải giữ nhánh `if #available(iOS 26.0, *) { glassEffect(...) } else { ultraThinMaterial + stroke + shadow }`.

**Nút tròn/pill trong tầng D** (Compare, Video Studio, editor) dùng `.editorGlass(_ shape:)` — kính **tối**, không dùng `.glassBackground` (kính sáng tầng C, chữ trắng khó đọc trên nền tối). Màu glyph theo một quy tắc: **inactive** = trắng (`.white` / `.white.opacity(0.9)`), **active** = nền accent + glyph **đen**, **disabled** = `.white.opacity(0.28)`. Không trộn glyph accent với glyph trắng cho cùng một vai trò. Trạng thái **đánh dấu phá hủy** (card Compare mở từ Duplicates: viền đỏ 3pt quanh card, nút chữ đổi `Delete` → `Keep`) = đĩa `.red` + glyph trắng — bản phá hủy của "active", không dùng accent cho nó.

---

## 10. Mẫu bố cục theo loại màn hình

### 10.1 Màn hình danh sách / cài đặt (tầng A)
`NavigationStack` → `List` (`.insetGrouped`) → `Section` có header chữ hoa nhỏ. Hành động phá hủy ở section cuối, màu `.red`. Nút chính dùng `.borderedProminent`, nút phụ `.bordered`.

### 10.1b Safe area ngang (2026-09-19)

**Không màn nào được `.ignoresSafeArea()` cả bốn cạnh.** Lưới ảnh muốn tràn lên dưới nav bar và tab bar thì dùng `.ignoresSafeArea(edges: .vertical)`; cạnh ngang phải giữ.

Lý do đo được trên **iPhone Duo** (iOS 27.1): màn ngoài rộng 466pt nhưng safe area chừa **84pt bên phải** cho dải hệ thống dọc (status bar + tab bar của OS nằm dọc ở đó). `LibraryScreen` bỏ qua cả bốn cạnh nên lưới trải 466pt trong khi app chỉ có 382pt — cột phải nằm **dưới** status bar và tab rail. Các màn lưới khác đã dùng `.ignoresSafeArea(edges: .bottom)` nên không dính.

Viewer là ngoại lệ có lý: **chỉ pager ảnh** tràn viền, còn chrome (nút đóng, action bar) nằm ngoài lớp đó và vẫn tôn trọng safe area.

### 10.1c Màn rộng: nhiều cột, đừng phóng to (2026-09-19)

Nguyên tắc chung cho regular width (iPad, màn trong iPhone Duo 867pt): **màn rộng hơn = nhiều nội dung hơn, không phải nội dung to hơn.**

**Dashboard Statistics.** `StatisticsScreen` xếp `ChartCard` thành **các cột độc lập** (`HStack` các `LazyVStack`, spacing 16), **không** dùng `LazyVGrid`: lưới cho mọi ô trong một hàng chiều cao của ô cao nhất, nên một card KPI cạnh một bar chart để lại lỗ hổng đúng bằng chiều cao bar chart. Card chia vòng tròn theo index (`index % count`) nên giữ thứ tự đọc mà cột vẫn khít. Số cột = số card rộng ≥ **320pt** nhét vừa, chặn trong **2…3** — 2 cột ở iPad 11" dọc và màn trong Duo, 3 cột ở iPad 13" dọc và iPad ngang. Compact width (mọi iPhone) giữ nguyên `List` một cột. Edit mode cũng quay về `List` ở mọi size class, vì kéo-đổi-thứ-tự và nút xóa đỏ là affordance của `List`; thoát edit mode thì về lại cột.

**Chừa chỗ cho chrome nổi ở đáy.** Nội dung cuộn phải kết thúc **cách tab bar nổi một khoảng**, không dừng sát nó: bottom inset của scroll view dừng đúng ở tab bar nên section/card cuối trông như dính. Collections chừa `Spacing.xxl * 2` (48pt) dưới stack; Statistics chừa hằng `bottomClearance = 48` ở cả hai nhánh (`List` và cột). Khoảng chừa này **cộng thêm** spacer 60/90pt của chrome custom pre-iOS 26, không thay nó. Lưới ảnh là ngoại lệ có chủ đích — ảnh cố ý cuộn dưới bar.

**Lưới ảnh.** `GridDensity.columns(forDensity:width:isRegularWidth:)` quy đổi density đã lưu theo bề rộng thật rồi siết thêm `regularTileScale = 0.7`, trần cột `resolvedColumnRange = 1...20` (density mà pinch chạm tới vẫn là `columnRange = 1...8`). Density 3 ra 9 cột ở iPad 11" dọc, 13 cột khi xoay ngang, 9 cột ở màn trong Duo — ô ảnh giữ khoảng 85–105pt ở mọi bề rộng.

### 10.2 Màn hình lưới ảnh (tầng B + C)
Lưới tràn viền, không padding. **Không lưới ảnh nào chèn header ngày** (2026-09-19) — Library, Album, Smart Album và `PhotoListScreen` đều chạy `sectionMode: .flat`, ảnh trôi liền mạch. Ngày của ảnh đang ở mép trên viewport hiện ở **title giữa top bar** (Library) hoặc dòng phụ dưới tên album, do `PhotoGridCollectionView.onVisibleDateChange` đẩy lên. Cấp độ ngày/tháng/năm lấy theo density đã lưu, không theo số cột đã vẽ, để màn rộng không tự nhảy sang gom theo năm. `OnThisDayScreen` vẫn có header vì section của nó là "cùng ngày qua các năm", không phải chia ngày. Chrome nổi đè lên lưới bằng `safeAreaInset(edge:)` hoặc overlay, luôn dùng kính tầng C. Khi vào chế độ chọn: lưới mờ đi, selection bar trượt lên từ đáy.

### 10.3 Công cụ toàn màn hình (tầng D)

**Màn rộng (≥ 700pt) — editor ảnh xếp như Lightroom trên desktop** (2026-09-19). Ngưỡng đo theo **bề rộng cửa sổ thật** (`EditorLayoutMetrics.sidebarMinCanvasWidth`), không theo size class: iPad Split View hẹp giữ layout điện thoại, iPhone xoay ngang thì không.

- Bố cục: `[sidebar công cụ] | [canvas ảnh]`, sidebar **trái hoặc phải do người dùng chọn** (menu ⋯ → Tools Panel, mặc định phải), **kéo đổi rộng 280–420pt**, **thu gọn được**. Cả ba lưu `@AppStorage`.
- Sidebar từ trên xuống: Back · "Edit" · nút thu gọn → **histogram luôn hiện** (đọc liên tục lúc kéo slider, không giấu sau một cú chạm) → hàng lệnh undo/redo/before-after/fit-fill/⋯ → **dải 4 tool chiếm stage** (Crop · Mask · Markup · Presets) → **6 panel tham số xổ được** → nút `Save…` chiếm hết bề ngang ở đáy.
- **Hai loại công cụ, hai affordance.** Tool chiếm stage thì **loại trừ nhau** (chỉ một cái giữ được crop frame / mask overlay), nên chúng là **radio strip**, không phải disclosure — một tam giác xổ hứa "mở bao nhiêu cũng được" là nói dối về chúng. Chạm lại tool đang bật để tắt. Tham số thì mở chồng thoải mái, xếp **theo thứ tự pipeline**: Light → Curve → Color → Grade → Detail → Effects. `Mix` và `Point` là **segment bên trong Color** (Lightroom lồng HSL y hệt), `Optics`/`Geo` chưa có tham số thì **không có dòng** — "coming soon" là UI chưa ship, không phải empty state. Danh sách phẳng 14 section cũ cao hơn cả sidebar: đóng hết vẫn phải cuộn.
- **Không có chiều cao cố định cho section.** Panel trong sidebar không được tự cuộn dọc (`\.editorPanelScrolls == false`): mỗi section cao đúng bằng nội dung, scroll của sidebar lo phần tràn. Scroll lồng vừa bẫy ngón tay vào sai danh sách, vừa buộc phải đoán một hằng số chiều cao vì scroll view không có intrinsic height.
- **Không có command band khi sidebar đang mở**: band chỉ xuất hiện lúc sidebar thu gọn, mang theo Back/undo/redo/⋯/Save và nút mở lại sidebar. Hai dải chrome cùng lúc là ăn 56pt của ảnh để lặp lại thứ sidebar đã có.
- **Không đặt control nổi đè lên stage**: stage nuốt mọi chạm trong bounds của nó (zoom, pan, vẽ mask, crop handle) — đo trên iPad, nút overlay ở đó không nhận tap. Chrome phải là view anh em của stage (band hoặc sidebar).
- **Fit ⇄ Fill**: double-tap lên ảnh, và nút tương ứng trong hàng lệnh sidebar (`arrow.up.left.and.arrow.down.right` khi đang fit, `arrow.down.right.and.arrow.up.left` + nền accent khi đang fill). Fill phóng ảnh tới khi phủ kín canvas — phần thừa bị **stage** cắt, không đụng gì tới bản edit. Một cử chỉ không ai nhìn thấy thì chưa phải là tính năng, nên phải có cả nút. Điện thoại giữ double-tap = full-bleed: ở đó canvas gần vuông rồi, giấu chrome mới là thứ mua thêm chỗ, còn màn rộng đã có nút thu gọn sidebar làm việc đó.
- **Bàn phím cứng** (2026-09-19): ⌘Z / ⇧⌘Z undo-redo, ⌘S mở save sheet, ⌘C/⌘V copy-paste edits, ⌘0 fit⇄fill, ⌘\\ thu/mở sidebar, Esc = Back. Đặt trong lớp nút ẩn `editorKeyboardShortcuts` chứ không gắn vào nút thật: hai lệnh nằm trong `Menu`, mà phím tắt của mục menu chỉ bắn khi menu đang mở.
- **Apple Pencil** (2026-09-19): `PKCanvasView.drawingPolicy = .default` (không phải `.anyInput`) và brush mask ưu tiên `touch.type == .pencil` — Pencil vẽ, ngón tay pan, lòng bàn tay bị bỏ. Trước đó bàn tay chạm trước thành nét vẽ, Pencil tới sau bị tính là ngón thứ hai.
- **Chuột phải / giữ lâu** (2026-09-19): mỗi slider row có context menu `Reset` + `Enter Value…`, stage có menu giống hệt ⋯ (Auto Enhance, Copy/Paste Edits, Reset All, History). Trước đó reset là double-tap và nhập số là two-finger tap — hai cử chỉ không ai nhìn thấy, và trackpad bấm phải thì không có gì xảy ra ở bất kỳ đâu trong editor.
- **Chữ trong sidebar scale theo Dynamic Type** (`EditorTheme.sidebarTitle/sidebarGroupLabel/sidebarToolLabel/sidebarActionLabel`, header section dùng `@ScaledMetric`). Slab 246pt của điện thoại vẫn giữ size cố định theo §7.2 — nó không có chỗ để giãn; sidebar thì đã bỏ hết chiều cao cố định nên giãn được.
- **Panel trong sidebar không tự xưng tên** (`\.editorPanelShowsTitle == false`): header section cách đó 44pt đã ghi "Mask" rồi, panel ghi "Masks" lần nữa bằng font to hơn là cùng một tên hai lần.
- **Tone curve vẽ trong sidebar, không đè lên ảnh** (`chrome.showsCurveOnStage == false`): sidebar đủ rộng cho một plot dùng được, và màn to là để xem ảnh.

Điện thoại (< 700pt) giữ nguyên cấu trúc cố định từ trên xuống:
1. **Top bar** — trái `Cancel`, giữa tiêu đề inline, phải `Done`/`Save`. Không đặt hành động lạ ở đây.
2. **Stage** — ảnh/preview, nền đen, chiếm phần lớn không gian.
3. **Panel** — nền `panelSolid`, hairline trên `panelTopHairline`, các tier ngăn bằng `panelDivider`.
4. **Tab row** (nếu có nhiều nhóm công cụ) — dưới cùng panel.

Tiến trình dài chạy: `safeAreaInset(edge: .bottom)` với `ProgressView` + đếm `Processing N of M` + nút `Cancel` màu đỏ. Với tác vụ hàng loạt cần **khóa toàn màn hình** (Compress batch): dùng **modal giữa màn hình** — scrim `Color.black.opacity(0.6)` phủ kín nuốt mọi chạm, thẻ `panelSolid` bo `Radius.lg` chứa `ProgressView` xoay + thanh `ProgressView(value:)` + đếm + `Cancel` đỏ; nội dung dưới `.disabled(true)`.

### 10.3b Ghép ảnh (2026-09-19)

- **Không còn cull** (gỡ 2026-09-20). Cờ pick/reject rồi sao 0–5 đều đã bỏ, bảng `photo_cull` drop ở `v16-dropCull`. Ảnh chỉ mang **favorite của PhotoKit** — một bit, đồng bộ sang Photos. Ba trục trả lời cùng một câu hỏi "tấm này có được không" là hai trục thừa. Việc *chọn* thuộc về màn Compare (`Keep Only This`), không phải một thang điểm rải khắp app.
- **Combine Photos** (`PhotoStackScreen`) theo đúng khung tầng D §10.3: Cancel/tiêu đề/Save · stage đen · một panel. Mỗi mode kèm **một câu nói mode đó dùng để làm gì**, không mô tả phép toán — phép toán đã nằm ngay trong preview.

### 10.4 Sheet
- Sheet nhập liệu ngắn → `.presentationDetents([.medium])`.
- Sheet có danh sách dài → `[.medium, .large]`.
- Sheet toàn nội dung → `[.large]`.
- Luôn có `NavigationStack` + `.navigationBarTitleDisplayMode(.inline)`, `Cancel` trái, hành động xác nhận phải.

### 10.5 Presentation
- **Sheet** cho tùy chọn/nhập liệu (Filter, Advanced Search, Smart Album Editor, Chart Editor, History).
- **fullScreenCover** cho công cụ chiếm toàn bộ ảnh (Viewer, Compare, Compress, Collage, Video Studio). Công cụ cần xem ảnh trong lúc kéo (Curve) **không** mở màn riêng — vẽ overlay lên stage của editor, mờ đi khi giữ tay (`EditorCurveOverlay`).
- - **Xác nhận Discard/Huỷ dùng `.alert` 2 nút** (Discard đỏ + Keep Editing), **không** dùng `confirmationDialog`: iOS 26 vẽ dialog thành popover nổi và **ẩn nút role `.cancel`**, chỉ còn nút đỏ (Photo Editor, Video Studio, Collage đều đã đổi 2026-09-06).
- Payload của `fullScreenCover(item:)` phải là struct `Identifiable` chứa sẵn dữ liệu (xem `CompressionPresentation`) — không đọc lại state ngoài.

### 10.6 Chế độ chọn nhiều ảnh
Một mẫu duy nhất cho Library, Album Detail, Smart Album Detail, On This Day — **bắt chước app Photos** (2026-09-18):
- **Nav bar không ẩn khi chọn**: tiêu đề màn hình (và dòng ngày dưới nó ở Library) đứng nguyên vị trí như lúc duyệt; header ngày dính của lưới cũng không nhảy lên. Chỉ tab bar ẩn.
- Nav bar khi chọn: các nút duyệt (Settings/Sort/Select) ẩn; leading là button chữ **`Compare`**, trailing là **⋯** (Collage, Video, Compare, Resize & Compress, Add to Collection, Export EXIF, Duplicate — dòng nào screen không cấp thì không hiện) và **×** (thoát chọn). Nút vào chế độ chọn ghi **chữ `Select`**, không dùng icon.
- Thanh nổi duy nhất ở đáy (`SelectionOverlay`): `[ Share (tròn kính) · pill đếm · Delete (tròn kính) ]`. Pill đếm ghi `N selected・{dung lượng}`, chưa chọn gì thì ghi `Select Items`; **pill là button cao 48pt, cùng kính/hiệu ứng với nút tròn**, nhãn `Show Selected (N・{size})` — chạm mở `SelectedItemsSheet` liệt kê ảnh đã chọn (chạm ô = bỏ chọn, có `Deselect All`).
- Nút **Filter** đứng đầu nhóm trailing (vẫn hiện khi đang chọn, kiểu Photos); `Select` (lúc duyệt) và `×` (lúc chọn) **tách sang capsule kính riêng** bằng `ToolbarSpacer(.fixed)`. Không có nút Sort riêng — sort nằm trong menu filter.
- Icon chrome ở mọi tab dùng `.tint(.primary)`, kể cả tab Collections (Settings, `+`, calendar) — accent chỉ cho trạng thái active/selected.
- Hành động không khả dụng thì **làm mờ** (dòng menu `.disabled`, nút tròn opacity 0.3), không ẩn. Compare yêu cầu ≥ 2 ảnh (không có trần trên).
- **Accent cố định là amber, KHÔNG còn setting và KHÔNG còn là tint toàn app (2026-09-19)**: `AppAccent.color` / `.uiColor` là hằng số (amber của icon, hai biến thể light/dark), phát qua `\.appAccent`; `ShotDexApp` **không** `.tint(...)`. Mọi control chuẩn của hệ (nav bar, menu, sheet, toggle, tab bar đang chọn) giữ **mặc định iOS**; accent chỉ dùng cho phần ShotDex tự vẽ: badge chọn ảnh trong lưới, trạng thái active của editor (`EditorTheme.accent`), chart. Chrome kính nổi (gear, filter, Select, ×, +, calendar, ⋯) luôn `.tint(.primary)` monochrome; `UIButton` tự dựng (icon Advanced Search trong search field) phải set `tintColor = .label`.
- **Glass của selection bar là Liquid Glass sáng gốc** (`glassBackground` / `glassEffect`), giống thanh nổi của app Photos — trong suốt, có vibrancy, **không** đè tint tối. Glyph **monochrome** `.primary` (đen/trắng theo hệ, vibrancy lo độ đọc), **không** accent. Accent chỉ dành cho trạng thái active/selected. Icon chrome ở toolbar (Select/Settings/Sort) cũng `.tint(.primary)` monochrome, không ăn theo accent vàng toàn app. **Badge chọn ảnh trong lưới dùng accent, kiểu app Photos** (2026-08-12): ô đã chọn = check trắng trên đĩa **accent** (`checkmark.circle.fill`, palette `[.white, accent]`) + viền accent 3pt + thumbnail mờ nhẹ (`alpha 0.82`); ô chưa chọn = `circle` viền trắng. Đây là ngoại lệ có tên của "accent chỉ cho active" — badge lưới là chỉ báo chọn/chưa chọn nên ăn theo accent như app Photos. Accent lấy qua `UIColor(AppAccentTheme.stored.color)` vì cell là UIKit.

---

## 11. Trạng thái, chuyển động, phản hồi

- **Empty state:** icon SF Symbol 44pt `.secondaryLabel` + một câu mô tả `.subheadline` + tối đa một nút `.borderedProminent`.
- **Loading:** `ProgressView` có nhãn (`"Preparing original…"`). Tiến trình xác định thì dùng `ProgressView(value:)`.
- **Lỗi:** `.alert` với tiêu đề danh từ (`"Compression Error"`), nội dung là `error.localizedDescription`, một nút `OK`.
- **Xác nhận phá hủy:** `.confirmationDialog` với `titleVisibility: .visible`, nút phá hủy `role: .destructive` ghi rõ hậu quả, nút hủy `role: .cancel`.
- **Animation:** `EditorTheme.animation` (easeOut 0.22) cho đổi trạng thái; `EditorTheme.panelSpring` (spring 0.32/0.85) cho panel trượt. Không tự viết duration khác.
- **Haptic:** `.sensoryFeedback(.selection, trigger:)` khi đổi tab/preset; `.impact` khi kết thúc kéo slider; `.success` khi export xong.

---

## 12. Chữ trong UI (copywriting)

- Tiêu đề màn hình là danh từ hoặc động từ + tân ngữ, số nhiều theo số lượng thật: `Compress Photo` / `Compress 8 Photos`.
- Nút là động từ: `Save to Photos`, `Continue Export`, `Cancel Export and Remove Copies`.
- Giải thích đặt dưới control, `.footnote`/`.caption`, `.secondary`, một câu.
- Dung lượng ước lượng có tiền tố `~`; dùng `ByteCountFormatter` với `countStyle: .file`.
- Không dùng emoji trong UI.

---

## 13. Accessibility

- Mọi nút icon-only phải có `accessibilityLabel`.
- Trạng thái chọn dùng `accessibilityAddTraits(.isSelected)`.
- Không truyền đạt thông tin chỉ bằng màu — luôn kèm icon hoặc chữ (ví dụ hàng "2 failed" có cả icon tam giác).
- Hỗ trợ Dynamic Type ở tầng A/B; tầng D dùng size cố định nhưng phải chịu được `.accessibility1` mà không cắt chữ (dùng `.fixedSize()` như `EditorPillLabel`).
- **Chrome tự dựng cũng phải scale, hoặc bỏ chữ đi** (2026-09-19): `LiquidGlassTabBar` (tab bar pre-26) từng khoá icon 17 / nhãn 10 nên ở cỡ accessibility nó là thành phần duy nhất trên màn không đổi gì. Giờ cả hai `@ScaledMetric` **có trần** (24 / 15), và **ở cỡ accessibility thì bỏ hẳn nhãn, chỉ còn icon** — ba nhãn cỡ đó không nằm vừa chiều ngang một chiếc iPhone, mà bóp chúng còn tệ hơn là để icon đứng một mình (VoiceOver vẫn đọc tên tab từ `accessibilityLabel` của nút).
- **Màn trước-khi-xin-quyền phải cuộn được**: `OnboardingScreen` xếp bốn lời hứa trong một `VStack` cố định, nên ở cỡ accessibility SwiftUI cắt mỗi dòng thành một dòng kết thúc bằng "…" — một màn xin quyền không nói nổi nó xin để làm gì. Bọc `ScrollView` + `.scrollBounceBehavior(.basedOnSize)` (ở cỡ thường vẫn là màn tĩnh), nút Continue ghim ngoài scroll.
- **Chrome tầng D phải nở ở regular width** (2026-09-19): luật "màn rộng = nhiều nội dung hơn" áp cho **nội dung**; nút và nhãn của công cụ thì không. Nút lệnh tròn 34 (compact) → **44** (regular); nhãn toolbar 9.5 → 11; tile template 52 → 68. Chip 28pt được giữ nguyên về hình nhưng **bắt buộc có target 44** (pad → `contentShape` → pad âm) chứ không phóng to chip.
- **Trắng mờ của tầng D có tên, không viết literal** (2026-09-20): ngoài `hairline` 0.09 / `panelDivider` 0.07 / `panelTopHairline` 0.10 đã có, thêm ba tên cho timeline — **`trackBorder` 0.12** (viền clip chưa chọn, đường nền dưới ruler), **`trackChip` 0.08** (nền chip trung tính: pill timecode, pill inspector chưa chọn), **`emptyLane` 0.04** (rail của lane chưa có gì — khẽ hơn divider vì nó là *một chỗ*, không phải một cạnh). Ba giá trị này trước đó bị gõ lại rải rác 9 chỗ. `DESIGN.md` không có thang opacity dạng nấc: thiếu thì **đặt tên trong `EditorTheme`**, không chọn bừa một số trong file feature.
- **Một control, một chất liệu — kể cả khi layout đổi chỗ của nó** (2026-09-20): nút Back của Video Studio nằm ở bottom bar khi hẹp và ở top band khi ≥700pt. Hai chỗ vẽ hai kiểu (đĩa phẳng `0.08` vs `.editorGlass`) nên kéo rộng cửa sổ iPad là thấy nó **đổi chất liệu giữa chừng**. Nguyên tắc "một hành động — một chỗ" mở rộng: cùng một hành động ở hai layout mode thì cùng glyph, cùng nhãn **và cùng chất liệu**.
- **Panel phụ trợ tiêu chiều mà stage đang dư** (2026-09-20): cùng một inspector, hai hình dạng. Cửa sổ **ngang** (rộng > cao) thì khung bị giới hạn chiều cao, nên inspector là **cột dọc** và tiêu chiều rộng; cửa sổ **dọc** thì ngược lại, inspector **neo ngang** dưới nội dung và tiêu chiều cao. Chọn sai chiều là cắt đúng vào chiều đang thiếu — đo bằng diện tích khung còn lại, không bằng cảm giác. Kèm một sàn: stage còn lại không được hẹp hơn màn một chiếc điện thoại. **Luật này áp cho MỌI chrome thường trực, không riêng inspector** (2026-09-20): rail công cụ dọc của Video Studio cũng vậy — chỉ dựng khi cửa sổ **ngang** (`usesToolRail`), còn tablet **dọc** thì tool về hàng ngang dưới timeline. Ở màn dọc khung hình bị bề rộng giới hạn và đã thừa chiều cao, nên một rail 92pt là 92pt cắt thẳng khỏi khung để tiết kiệm 62pt của thứ đang dư. Câu hỏi luôn là *chiều nào đang thiếu*, không phải *màn này có to không*.
- **Chiều cao thừa của màn cao thì tiêu vào nội dung, không tiêu vào đen** (2026-09-20): một khung 16:9 không kéo cao được, nên màn dọc luôn dư. Luật: phần dư **trả về quanh khung đang xem** (đen cân trên–dưới, như mọi NLE) và **các track/lane thì nở theo bề rộng cửa sổ**; không bao giờ đổ hết phần dư cho một băng rồi để nội dung dính lên đỉnh một vùng trống — đó là thứ đọc ra là "màn hình hỏng", không phải "màn hình rộng rãi". Ảnh xem trước trong track phải xin đúng cỡ pixel của ô sau khi nở, nếu không lane cao hơn chỉ đổi mờ nhỏ lấy mờ to.
- **Ô có kích thước cứng mà bên trong là chữ thật thì kích thước đó phải `@ScaledMetric`** (2026-09-19). Token album/utility/smart album (`AlbumTokenMetrics`: 60 cao × 190 rộng × thumbnail 44), thẻ Memory (260×150) và thẻ On This Day (cao 150) đều scale theo `.subheadline`/`.headline`. Đo ở `accessibility-extra-large` trước khi sửa: "Recently Viewed" ra "Rece…", thumbnail đè lên tiêu đề, câu dưới On This Day cụt. Hàng `LazyHGrid` chứa token phải scale **cùng một con số**, nếu không hàng sẽ cắt token bên trong.
- **Hai hành động phá hủy ngược nghĩa nhau thì không đặt cạnh nhau** (2026-09-20): "xoá mấy cái này" và "xoá tất cả trừ mấy cái này" mà là hai nút kề nhau là thứ dễ bấm nhầm nhất một màn có thể có. Gom vào **một Menu**, mỗi hàng là một câu nói hết hậu quả kèm số ảnh bị mất, hai hàng đỏ **cách nhau bằng `Section`**, và `.menuOrder(.fixed)` để hàng phá hủy không đổi chỗ khi menu mở ngược lên. Chữ trong hàng phải **vừa một dòng** (menu iPhone ~250pt): hàng phá hủy xuống dòng là hàng bị đọc lướt.
- **Hành động hàng loạt thì để user chọn trước, đừng gắn nút lên từng item** (2026-09-20): nút trên mỗi card tốn một dòng chiều cao *mỗi card* và nhân bản hành động phá hủy ra khắp màn. Chọn (badge tròn góc trên-phải như Photos) rồi một control duy nhất ở top-right — xem §Compare.
- **Gesture của nội dung lồng trong list thì tách theo số ngón, đừng tách theo mode** (2026-09-20): một ngón luôn cuộn list, hai ngón mới pinch/pan nội dung (`UIScrollView.panGestureRecognizer.minimumNumberOfTouches = 2`). Bật/tắt pan theo mức zoom nghĩa là đúng lúc user zoom vào để soi thì list hết cuộn. Chỉ dùng khi gesture đó là view state **chung** của cả màn (compare mirror zoom/pan sang mọi card), vì ngón thứ hai lúc đó đã đặt sẵn từ cú pinch.
- **Động từ của công cụ phải có chữ, không chỉ glyph** (2026-09-19): `accessibilityLabel` trả lời cho VoiceOver, không trả lời cho người đang nhìn. Một hàng glyph trần trong chrome tầng D — vương miện giữa hai mũi tên, ba icon layout ở góc phải — là nơi user dừng lại hỏi "nút này để làm gì". Luật: **control nào mang một động từ riêng của công cụ** (promote, swap, đổi chế độ xem) thì kèm nhãn chữ (10pt semibold dưới glyph, hoặc segmented chữ) — nền kính phía sau vốn đã là cái nền mà chữ cần. Miễn trừ: glyph hệ thống mà nghĩa đã cố định ngoài app (✕ đóng, ↑ share, thùng rác, sao rating, cờ). Tên riêng của một trường phái (Lightroom `Survey`/`Compare`) thì chữ thôi chưa đủ: thêm **một dòng mô tả thoáng qua** khi đổi.
- **Và ô đó rộng thêm ở regular width nếu chữ vẫn cắt** (2026-09-19): `AlbumTokenMetrics.width(isRegularWidth:)` = 190 compact / **240 regular**. 190 chỉ chừa ~120pt cho tiêu đề, đủ cắt "Recently Viewed" ngay ở cỡ chữ mặc định — chấp nhận được trên điện thoại, vô lý trên iPad khi cạnh nó còn 800pt trống. Đây **không phải** ngoại lệ của luật "màn rộng = nhiều nội dung hơn, không phải to hơn": token vẫn chứa đúng chừng đó thứ ở đúng cỡ đó, chỉ là chữ thôi bị cắt.

---

## 14. Checklist trước khi merge một màn hình mới

- [ ] Đã khai báo tầng bề mặt (A/B/C/D) và không trộn tầng.
- [ ] Không có màu hardcode; accent đọc từ environment hoặc `EditorTheme`.
- [ ] Mọi radius nằm trong 8/12/16/22/28/Capsule, đều `.continuous`, đọc từ `AppTheme`.
- [ ] Mọi khoảng cách nằm trong scale 4/8/12/16/20/24, đọc từ `AppTheme`.
- [ ] Font là token ngữ nghĩa hoặc `EditorTheme.*`, không có `.system(size:)` tùy hứng.
- [ ] Kính đi qua `GlassPanel` / `GlassIconButton` / `.glassBackground` / `.editorGlass`.
- [ ] Icon lấy từ từ điển mục 7.
- [ ] Có empty state, loading state, error alert.
- [ ] Nút icon-only có `accessibilityLabel`.
- [ ] Hành động trùng tên với màn hình khác thì nằm cùng vị trí, cùng icon.
