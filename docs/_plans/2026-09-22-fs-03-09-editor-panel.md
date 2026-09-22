# Kế hoạch — Panel editor màn rộng theo Lightroom iPad

| Trường | Giá trị |
|---|---|
| Sửa đặc tả trước khi làm | **AC-19** — bỏ 'núm tròn 28pt', đổi thành 'vùng bắt chạm ≥44pt, giữ vạch' |
| Đặc tả | `docs/02-functional-spec/FS-03-photo-editor/09-wide-screen-and-batch-editing.md` (30 AC) |
| Intent | `docs/_intents/2026-09-22-editor-panel-lightroom-layout.md` |
| Ngày | 2026-09-22 |
| Trạng thái | nháp — chờ duyệt |

## 1. Hiểu đúng chưa

Panel màn rộng (iPad + Duo màn trong) đổi từ **8 nhóm phẳng, chỉ Light mở** sang **5 thẻ gập sẵn**:
Curve chui vào Light, Mix/Point/Grade thành tab trong Color, Geometry về Crop. Panel bỏ hàng Look, bỏ nút
Auto, bỏ chân panel — `Save` lên hàng lệnh (đã dồn một bên), `Reset` thành nút ↺ trên từng thẻ. Cột ngắn
(Duo) giữ histogram trong panel ở 56pt thay vì trả nó lên band. Cộng ba thứ nhìn: thẻ nổi, **vùng chạm slider 44pt**
(giữ vạch, không làm núm tròn), và canvas không được hẹp lại. Markup đổi hàng bốn nút Add thành một nút `+` và đưa công cụ vẽ vào panel.
`ShotDexEdit` bị xoá, thay bằng action extension EX-05.

**Điện thoại không đụng** — bánh xe 14 chip giữ nguyên, nên `EditorGroup` (14 case) **không được xoá case
nào**; chỉ danh sách section của sidebar đổi.

## 2. Chỗ nào trong code

| File | Đụng gì | Mới / sửa |
|---|---|---|
| `ShotDex/Domain/Editing/EditorLayoutMetrics.swift` | **bỏ vế `width > height` ở `usesSidebar` (`:75`)** — iPad dọc vào layout rộng; | `sidebarHistogramHeight` thêm biến thể 56 cho cột ngắn; thêm `sidebarCardSpacing` (8 / 6 cột ngắn), `sidebarSliderHitWidth` 44; bỏ số của chân panel | sửa |
| `ShotDex/Domain/Editing/EditorAdjustmentCatalog.swift` | nguồn duy nhất của nhóm — thêm khái niệm **section của sidebar** (5) tách khỏi **group** (14 case cho phone) | sửa |
| `ShotDex/Features/Editing/PhotoEditorScreen.swift` | `sidebarParameterGroups` 8→5; `sidebarColumn` bỏ hàng Look + chân panel; `sidebarSectionBody` nhận curve vào Light, tab vào Color, geo vào Crop; `commandBand` dồn cụm + mang `Save` | sửa |
| `ShotDex/Features/Editing/EditorSidebar.swift` | `EditorSidebarSection` thành **thẻ** (nền `EditorTheme.control`, `Radius.lg`), thêm nút ↺ trên header | sửa |
| `ShotDex/Features/Editing/EditorSliderRow.swift` | nới **vùng bắt chạm** lên 44pt (vạch giữ nguyên, `:158`), trạng thái mờ khi slider cha = 0 | sửa |
| `ShotDex/Features/Editing/EditorTheme.swift` | thêm `rowDisabled = 0.35` (cùng số với `dimText` nhưng khác vai trò) | sửa |
| `ShotDex/Features/Editing/EditorToolPanels.swift` | Crop panel nhận 6 slider Geometry + Upright vào cùng danh sách cuộn | sửa |
| `ShotDex/Features/Editing/EditorMaskPanels.swift` | trạng thái "chưa có mask" → **5 thẻ mờ** + `+` | sửa |
| `ShotDex/Features/Editing/EditorChromeModel.swift` | `expandedSidebarGroups` mặc định **rỗng**; thêm quy đổi khoá cũ | sửa |
| `ShotDex/Features/Editing/PhotoEditorController.swift` | `EditorGroup.crop` → `cropGeometry` (raw value đổi → **cần quy đổi khoá đã lưu**) | sửa |
| `ShotDex/Features/Editing/EditorDrawingCanvas.swift` + `drawTopBar` | màn rộng: công cụ vẽ vào panel thay vì thanh nổi | sửa |
| `ShotDex/Domain/Editing/EditorAutoTone.swift` | **xoá** | xoá |
| `ShotDexTests/EditorAdjustmentCatalogTests.swift` (phần Auto) | **xoá** phần test Auto | sửa |
| `ShotDexEdit/**` (4 file) + pha Embed trong `project.pbxproj` | **xoá target** | xoá |
| `ShotDexEditAction/` | target mới (EX-05) | mới |
| `ShotDexTests/EditorPanelLayoutTests.swift` | nhận toàn bộ AC số học mới | sửa |

**Tầng:** mọi số học bố cục vào `Domain/Editing/EditorLayoutMetrics` + `EditorAdjustmentCatalog` (thuần,
test được không cần sim). View chỉ đọc. Trạng thái gập/mở ở `EditorChromeModel` (session state, **không**
vào recipe, **không** vào History).

## 3. Bảng đối chiếu AC ↔ code

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 danh sách 5 thẻ gập sẵn | ❌ | `PhotoEditorScreen.swift:1493` liệt 8 group; `EditorChromeModel.swift:37` mặc định `[.light]` | đổi danh sách + mặc định rỗng |
| AC-2 histogram trong panel trên Duo | ❌ | `PhotoEditorScreen.swift:1187` `if !isShortColumn`; band lấy lại pill `:860` | bỏ nhánh, thêm biến thể 56pt |
| AC-3 đồ cố định ≤180, vùng cuộn ≥430 | ❌ | số hiện tại: histogram 92+pad, Look 52, chân 74 | tính lại trong metrics + test |
| AC-4 Light mở vừa vùng cuộn Duo | ❌ | đo thật: Light 441pt / vùng cuộn ~430 | phụ thuộc AC-2, AC-3 |
| AC-5 mở section thì cuộn lên đầu | ❌ | `toggleSidebarSection` không cuộn | thêm `ScrollViewReader` |
| AC-6/7/8 slider phụ mờ theo cha | ❌ | không có khái niệm slider cha trong `EditorAdjustmentCatalog` | thêm quan hệ cha–con vào catalog (Domain) |
| AC-9/10 hàng lệnh dồn một bên | ⚠️ **một nửa** | `commandBand(mirrored:)` `:1664` đã lật được cụm, nhưng cụm trái vẫn tách khỏi ⋯ — đo được 869pt trống | gộp mọi nút trừ Back vào một cụm |
| AC-11 curve trong thẻ Light | ⚠️ | curve đã vẽ trong panel (`:1524 case .curve`), nhưng là **section riêng** | chuyển vào cuối `sidebarSectionBody(.light)` |
| AC-12 Color có 4 tab | ⚠️ | Mix/Point đã là segment (`:1499`), **Grade còn là section riêng** (`:1533`) | thêm Grade vào cùng bộ tab |
| AC-13 Crop chứa Geometry | ❌ | `.geo` là group riêng (`:2417`) | gộp vào panel Crop |
| AC-14 iCloud-only, không mạng | ⚠️ **có thể đã đạt** | FS-03.09 §8 tả ảnh giữ chỗ + "Downloading from iCloud…" | chỉ cần test/ảnh chụp chứng minh |
| AC-15 quyền `.limited` | ❌ **và lộ lỗi có sẵn** | editor chỉ mở từ lưới nên `.limited` không tới được ảnh ngoài tập chọn; lối duy nhất là deep link, mà `LibraryScreen.swift:319` dò 3s rồi `return` lặng lẽ | lỗi im lặng đã vào `REVIEW_QUEUE.md`; AC-15 chỉ còn phần "không dựng panel nửa vời" |
| AC-16 gập/mở không vào History | ✅ | `expandedSidebarGroups` là state của view, không đi qua controller | viết test khoá lại |
| AC-17 xoay giữ trạng thái gập | ✅ **đã đo** | iPad 11" M5, 2026-09-22: mở Light + Color → ngang→dọc→ngang, header về **đúng y cũ** (Light 258 · Curve 699 · Color 744 · Grade 1112) | không sửa code; viết test khoá lại ở task 1 |
| AC-18 thẻ nổi 8pt (6pt cột ngắn) | ❌ | `EditorSidebarSection` hiện là hàng phẳng `:198` | dựng thẻ |
| AC-19 vùng chạm núm | ⚠️ **AC phải sửa** | `EditorSliderRow.swift:12` ghi rõ *"There is no round knob"*; vạch ở `:158` | giữ vạch, **chỉ nới vùng bắt chạm lên 44pt**; sửa AC-19 trong FS-03.09 trước khi làm |
| AC-20 canvas không lùi | ✅ **đã đo, AC viết lại** | đo pixel 2026-09-22: ảnh 3:2 chiếm **553/782pt = 71%** canvas trên iPad 11" | AC đổi thành "canvas ≥ 842×782pt"; chỉ cần test số học ở task 2 |
| AC-21 mask: 5 thẻ mờ, không Cancel/Apply | ❌ | hiện là "No masks yet" + nút New Mask (`EditorMaskPanels.swift:31,57`) | dựng trạng thái mờ |
| AC-22 không còn chân panel | ❌ | chân panel ở `sidebarActionRow` | xoá, dời Save |
| AC-23 thẻ giải thích mask dùng ảnh đang mở | ❌ | không có | mới, tốn một lần render preview |
| AC-24 Share → Edit in ShotDex | ❌ | chưa có target | EX-05, tách commit riêng |
| AC-25 pill Save trên band + Reset All trong ⋯ | ⚠️ **một nửa** | band đã biết mang Save (`showsSave:` `:1660`) khi panel ẩn | luôn mang, đổi kiểu dáng thành pill accent |
| AC-26 ↺ từng thẻ = một bước Undo | ❌ | chỉ có Reset All toàn cục | thêm reset theo nhóm vào controller |
| AC-27 xoá Auto | ❌ | `EditorAutoTone.swift` + `hasAuto:` trong catalog + dòng menu | xoá cả ba |
| AC-28 Markup một nút `+` | ❌ | bốn nút Add 67×28 (đo được) | đổi |
| AC-29 ↺ Layers xoá hết, một bước Undo | ❌ | không có | mới |
| AC-30 công cụ vẽ vào panel trên màn rộng | ❌ | `drawTopBar` nổi trên ảnh (`:850`) | rẽ nhánh theo `isWideLayout` |
| AC-31 iPad dọc dùng panel bên | ❌ | `EditorLayoutMetrics.swift:75` còn vế `width > height`; **test `sidebarIsForLandscapeWindowsOnly:485` đang khẳng định điều ngược lại** | bỏ vế, **sửa luôn test đó** (đổi tên và đảo kỳ vọng cho iPad dọc) |
| AC-32 đóng panel ở dọc, nhớ qua xoay | ⚠️ **một nửa** | khoá `SettingsKeys.editorSidebarHidden` đã lưu; nhưng lối đóng đổi từ nút `Hide Tools` sang chạm lại icon rail | sửa theo AC-33/34 |
| AC-33/34 rail đóng mở panel, icon chỉ sáng khi panel mở | ⚠️ **ngược code hiện tại** | `PhotoEditorScreen.swift:1310` — chạm lại đang **về mode edit**, và `:1312` tự mở panel nếu đang đóng | đảo hành vi; `EditorToolRail` đổi nghĩa `selected` thành "panel của mode này đang mở" |
| AC-35 Cancel của Crop | ⚠️ **có đường cũ, đổi chỗ** | luật "thoát Crop không áp khung" đang nằm ở chạm-lại (`:1316 discardingCrop:`) | chuyển logic đó sang nút `Cancel` ở chân panel |
| AC-36 chân panel chỉ ở ba mode dựng hình | ❌ | hôm nay chân panel có ở mọi mode (`sidebarActionRow`) | rẽ nhánh theo `railMode` |
| AC-37 nút nhỏ, phân biệt bằng màu | ❌ | `Save…` đang **240×50** (đo được), chân panel 74pt | `Apply`/`Save` pill 32pt rộng vừa chữ, `Cancel` chữ trần, `↺` đĩa 32pt; chân panel còn **48pt** |

**Tái dùng được, đừng làm lại:** `EditorValueSlider` (một kiểu slider cho cả editor — sửa vùng chạm ở **một** chỗ là xong cả app), `EditorSidebarSection` (chỉ cần khoác nền thẻ), `commandBand(mirrored:)` (đã có đường lật),
`WidgetDeepLink` (EX-05 dùng lại, không đẻ tuyến deep link thứ hai), `EditorHistogramSparkline`.

## 4. Ba chỗ đã chốt (2026-09-22)

| # | Chuyện | Hỏi |
|---|---|---|
| Q1 | Núm slider | **Chốt: giữ vạch, không làm núm tròn.** Tôn trọng quyết định đã ghi ở `EditorSliderRow.swift:12`. Chỉ nới **vùng bắt chạm lên 44pt** quanh vạch — đủ cho Pencil và trỏ chuột, không đổi diện mạo, không đụng hàng 34pt của điện thoại. **AC-19 phải sửa lại trong FS-03.09.** |
| Q2 | Khoá đã lưu | **Chốt: viết bước quy đổi một lần** — đọc raw value `crop`, ghi lại thành `cropGeometry`, kèm test đọc giá trị cũ. |
| Q3 | Ba AC chưa kết luận | **Task 0 đã chạy.** AC-20: đã đạt sẵn (71%), AC viết lại thành "canvas không lùi dưới 842×782pt". AC-15: không có đường code, và lộ một lỗi im lặng có sẵn → đã ghi vào `REVIEW_QUEUE.md`. AC-17: đang đo trên máy. |

## 5. Thứ tự task

Nguyên tắc: ✅ trước (khoá lại bằng test) → số học Domain → view → thứ mới → target mới.

| # | Task | AC | Test kèm |
|---|---|---|---|
| 0 | ✅ **xong 2026-09-22** — AC-20 đã đạt sẵn (71%), AC-17 đã đạt sẵn (xoay giữ nguyên), AC-15 ❌ + một lỗi im lặng vào `REVIEW_QUEUE.md` | AC-15, 17, 20 | — |
| 1 | Test khoá **ba** hành vi đang đúng: gập/mở không vào History; xoay giữ trạng thái gập; canvas không lùi dưới 842×782pt | AC-16, 17, 20 | `EditorPanelLayoutTests` |
| 2 | Metrics + catalog: **bỏ vế `width > height`**, 5 section, quan hệ slider cha–con, histogram 56, thẻ 8/6pt, bỏ số chân panel | AC-1, 3, 6, 18, 31 | test số học thuần + sửa `sidebarIsForLandscapeWindowsOnly` |
| 3 | `EditorChromeModel`: mặc định gập hết + **quy đổi khoá `crop` → `cropGeometry`** | AC-1, 16 | test đọc raw value cũ |
| 4 | `EditorSidebarSection` thành thẻ + nút ↺ theo nhóm | AC-18, 26 | test + ảnh chụp |
| 5 | Bỏ hàng Look, chân panel **chỉ còn ở Crop/Mask/Markup** dạng `[↺] [Cancel] [Apply]`, `Save` pill lên band, `Reset All` vào ⋯ | AC-22, 25, 35, 36 | ảnh chụp 3 khổ |
| 5b | Rail: chạm lại = đóng panel, icon chỉ sáng khi panel mở, bỏ `Hide Tools` | AC-32, 33, 34 | `ui-drive` ba nhịp |
| 5c | Kiểu nút: `Save`/`Apply` pill 32pt rộng vừa chữ, `Cancel` chữ trần, `↺` đĩa 32pt | AC-37 | dump đo `width`/`height` |
| 6 | Dồn hàng lệnh một bên theo `sidebarEdge` | AC-9, 10 | dump `ui-drive` |
| 7 | Gộp nhóm: curve → Light, Grade → tab Color, Geometry → Crop (đổi tên `cropGeometry`) | AC-11, 12, 13 | dump + test |
| 8 | Histogram 56pt trên cột ngắn, bỏ pill band | AC-2, 3, 4 | test + ảnh Duo |
| 9 | Mở section thì cuộn lên đầu | AC-5 | dump trước/sau |
| 9b | Kiểm khổ dọc: panel bên + Hide Tools nhớ trạng thái qua xoay | AC-31, 32 | `ui-drive` hai hướng |
| 10 | Slider phụ mờ + `EditorTheme.rowDisabled`; nới vùng chạm slider lên 44pt (giữ vạch) | AC-6, 7, 8, 19 | test + ảnh |
| 11 | Xoá Auto (nút, menu, `EditorAutoTone`, test) | AC-27 | build + grep |
| 12 | Mask: 5 thẻ mờ khi chưa có mask | AC-21 | ảnh |
| 13 | Thẻ giải thích mask dùng ảnh đang mở | AC-23 | ảnh |
| 14 | Markup: nút `+`, ↺ Layers, công cụ vẽ vào panel | AC-28, 29, 30 | ảnh |
| 15 | Xoá target `ShotDexEdit` khỏi project | — | build 6 target |
| 16 | Dựng `ShotDexEditAction` + deep link (EX-05) | AC-24 | thử tay trên sim |
| 17 | ~~Ảnh ≥60% canvas~~ — đã đạt sẵn; chỉ còn test khoá canvas không lùi (gộp vào task 2) | AC-20 | test số học |

Task 15 và 16 **tách khỏi lượt panel** được — nếu muốn ship panel trước thì dừng ở task 14.

## 5b. Tìm thấy khi chụp màn (task 3)

- **Ảnh không nằm giữa canvas ở khổ dọc.** iPad 11" dọc: ảnh 3:2 chiếm y≈395…650pt trong canvas 52…1194pt,
  tức **lệch lên trên tâm ~100pt**. Ngang thì không thấy lệch. Nghi ngờ canvas vẫn chừa chỗ cho filmstrip
  (72pt) dù filmstrip không hiện. Kiểm ở task 5 hoặc 9b.
- **`Light` trông như đang được chọn dù đã gập.** Header vẫn dùng accent của `isActive` (nhóm đang giữ stage)
  trong khi panel gập hết — hai nghĩa trên một dấu hiệu. Task 5b đổi nghĩa "sáng" cho rail; header phải đổi
  cùng lúc, nếu không người dùng đọc `Light` là "đang mở".

## 6. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| ~~Đổi núm slider~~ | — | **đã loại**: giữ vạch, chỉ nới vùng chạm. Không đụng hàng 34pt của phone |
| Quy đổi khoá `cropGeometry` sót chỗ → người dùng cũ mở ra trạng thái lạ | trung bình | Q2 + một test đọc raw value cũ |
| Thẻ + curve làm thẻ Light cao **748pt**, luôn phải cuộn | chắc chắn (đã chấp nhận trong spec) | đo lại trên Duo ở task 7; nếu tệ hơn dự tính thì mở lại chuyện đồ thị co theo cột |
| Panel **Crop & Geometry** dài gấp đôi trên Duo | trung bình | đo ở task 7, có thể phải gập Geometry mặc định |
| Thẻ giải thích mask tốn một lần render preview → giật khi mở danh sách | trung bình | render ở kích thước thumbnail, huỷ được, và chỉ tính khi thẻ thật sự hiện |
| Xoá `ShotDexEdit` làm hỏng pha Embed / chữ ký / release-check | thấp | task 15 chạy `/build` cả 6 target + `/release-check` |
| Sửa `EditorValueSlider` lan sang mixer/grading/point/straighten | cao | đó là **lợi thế** (một chỗ), nhưng phải chụp cả bốn nơi |
| Bánh xe 14 chip của phone lệch mô hình 5 nhóm | chắc chắn | nợ có ghi trong FS-03.01; không sửa trong lượt này |
| **Crop & Geometry trên Duo**: vừa nhận 6 slider Geometry vừa mất 48pt cho chân panel, trong vùng cuộn ~430pt | trung bình | đo ở task 7; không vừa thì Geometry gập mặc định |
| **iPad dọc: ảnh 3:2 tụt còn 27% (11") / 34% (13") chiều cao canvas** | chắc chắn — đã đo | người dùng đã chấp nhận để đổi lấy một editor duy nhất; đường thoát là **Hide Tools** (canvas về 786pt trên 11") |
| Bỏ vế `width > height` kéo theo cả **Split View và Stage Manager**: mọi cửa sổ ≥700×600 giờ vào layout rộng | trung bình | đo ở task 9b; nếu một cửa sổ 700×900 quá chật thì dựng thêm ngưỡng riêng, không quay lại vế cũ |

## 7. Phản biện

Chưa chạy `challenger`. Đáng chạy trước task 2 cho đúng ba chỗ: gom 8 nhóm còn 5 (giấu tool có thật sự
tốt hơn?), bỏ nút Auto (bỏ một tính năng có sẵn), và bỏ chân panel (Save rời khỏi chỗ nó nói rõ sẽ làm gì).

## 8. Cách chứng minh là xong

- **Test**: `EditorPanelLayoutTests` nhận toàn bộ số học mới (5 section, 56pt histogram, thẻ 8/6pt, đồ cố
  định ≤180, vùng cuộn ≥430); test mới cho quan hệ slider cha–con và reset theo nhóm; `Tools/gate` xanh.
- **Ảnh chụp**: iPhone 402×874 (chứng minh **không đổi**), iPad 11" 1210×834, iPad 13" 1376×1032, Duo trong
  951×669, Duo ngoài 466×678 — mỗi khổ ở bốn trạng thái: mặc định gập hết · Light mở · Crop & Geometry ·
  Mask chưa có mask. Cộng cả hai nhánh `#available(iOS 26)`.
- **Tài liệu**: cột "Chứng minh bằng" của cả 30 AC đổi từ `⚠️ chưa có` sang tên test thật; `FS-03.01` gỡ
  cảnh báo khi intent phone xong; `EX-01`/`EX-05` cập nhật khi task 15–16 xong.
- **Agent giai đoạn Deploy**: `device-layout` (bốn khổ màn), `duo-ux-review` + `ipad-ux-review`,
  `design-reviewer` (thẻ, token mới), `a11y-voiceover` (vùng chạm 44pt, thẻ mờ, nút ↺ mới), `ios26-parity`,
  `extension-boundary` (task 15–16), `memory-leak` (thẻ giải thích mask).
