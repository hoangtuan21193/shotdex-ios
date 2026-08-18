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

**Nút tròn/pill trong tầng D** (Compare, Video Studio, editor) dùng `.editorGlass(_ shape:)` — kính **tối**, không dùng `.glassBackground` (kính sáng tầng C, chữ trắng khó đọc trên nền tối). Màu glyph theo một quy tắc: **inactive** = trắng (`.white` / `.white.opacity(0.9)`), **active** = nền accent + glyph **đen**, **disabled** = `.white.opacity(0.28)`. Không trộn glyph accent với glyph trắng cho cùng một vai trò.

---

## 10. Mẫu bố cục theo loại màn hình

### 10.1 Màn hình danh sách / cài đặt (tầng A)
`NavigationStack` → `List` (`.insetGrouped`) → `Section` có header chữ hoa nhỏ. Hành động phá hủy ở section cuối, màu `.red`. Nút chính dùng `.borderedProminent`, nút phụ `.bordered`.

### 10.2 Màn hình lưới ảnh (tầng B + C)
Lưới tràn viền, không padding. Chrome nổi đè lên lưới bằng `safeAreaInset(edge:)` hoặc overlay, luôn dùng kính tầng C. Khi vào chế độ chọn: lưới mờ đi, selection bar trượt lên từ đáy.

### 10.3 Công cụ toàn màn hình (tầng D)
Cấu trúc cố định từ trên xuống:
1. **Top bar** — trái `Cancel`, giữa tiêu đề inline, phải `Done`/`Save`. Không đặt hành động lạ ở đây.
2. **Stage** — ảnh/preview, nền đen, chiếm phần lớn không gian.
3. **Panel** — nền `panelSolid`, hairline trên `panelTopHairline`, các tier ngăn bằng `panelDivider`.
4. **Tab row** (nếu có nhiều nhóm công cụ) — dưới cùng panel.

Tiến trình dài chạy: `safeAreaInset(edge: .bottom)` với `ProgressView` + đếm `Processing N of M` + nút `Cancel` màu đỏ. Với tác vụ hàng loạt cần **khóa toàn màn hình** (Compress batch): dùng **modal giữa màn hình** — scrim `Color.black.opacity(0.6)` phủ kín nuốt mọi chạm, thẻ `panelSolid` bo `Radius.lg` chứa `ProgressView` xoay + thanh `ProgressView(value:)` + đếm + `Cancel` đỏ; nội dung dưới `.disabled(true)`.

### 10.4 Sheet
- Sheet nhập liệu ngắn → `.presentationDetents([.medium])`.
- Sheet có danh sách dài → `[.medium, .large]`.
- Sheet toàn nội dung → `[.large]`.
- Luôn có `NavigationStack` + `.navigationBarTitleDisplayMode(.inline)`, `Cancel` trái, hành động xác nhận phải.

### 10.5 Presentation
- **Sheet** cho tùy chọn/nhập liệu (Filter, Advanced Search, Smart Album Editor, Chart Editor, History).
- **fullScreenCover** cho công cụ chiếm toàn bộ ảnh (Viewer, Compare, Compress, Collage, Video Studio, Curve Editor).
- Payload của `fullScreenCover(item:)` phải là struct `Identifiable` chứa sẵn dữ liệu (xem `CompressionPresentation`) — không đọc lại state ngoài.

### 10.6 Chế độ chọn nhiều ảnh
Một mẫu duy nhất cho Library, Album Detail, Smart Album Detail, On This Day:
- Hàng trên: nút Share (tròn kính) · khay thumbnail đã chọn (cuộn ngang, có nút ✕ từng ảnh) · nút đóng (tròn kính); nhãn `N Photos Selected` ngay dưới.
- Hàng dưới: ba cụm — [Collage, Video] · [Compare, Compress, ⋯] · [Delete].
- Hành động không khả dụng thì **làm mờ** (`.tertiaryLabel` / opacity 0.32), không ẩn. Compare yêu cầu ≤ 4 ảnh.
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
