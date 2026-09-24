# FS-03.12 — Panel phone: lưới 40pt, một kiểu chip, một kiểu slider

`FS-03.12` · tier D · `Features/Editing/PhotoEditorScreen.swift` · `EditorSliderRow.swift`
· `Domain/Editing/EditorLayoutMetrics.swift` · intent [2026-09-24-editor-phone-panel](../../_intents/2026-09-24-editor-phone-panel.md)
· cập nhật 2026-09-24

**Một câu:** panel phone cao 264pt, mọi hàng trên một lưới 40pt, một kiểu chip và một kiểu slider cho cả
editor (sidebar iPad cũng vậy), accent chỉ còn trên Save.

Mask trong panel: [FS-03.05](05-local-masks.md) · Markup trong panel: [FS-05.01](../FS-05-markup/01-layers-and-draw.md)
· số đo gốc: [prototype](../../_intents/assets/2026-09-24-editor-phone-panel/ShotDex%20Editor%20Prototype.dc.html).

## 1. Người dùng cần gì

Đổi nhóm mà mắt không phải tìm lại slider. Nhìn panel là biết cái gì đang chọn mà không bị màu accent kéo đi khắp
nơi. Tạo mask hay thêm chữ bằng một chạm, không mở sheet che mất ảnh.

## 2. Phạm vi

**Có:** phone và Duo màn ngoài (đường không sidebar) — khung panel, lưới hàng, dải chọn, chip, slider, bánh xe,
băng lệnh trên. Sidebar iPad / Duo trong: **chỉ** kiểu slider và chip.

**Cố ý không có:** đổi bố cục sidebar (rail, header, Apply giữ accent); Collage và Video Studio (giữ kiểu slider
và chip cũ); thêm hay bớt chức năng nào (luật của intent).

## 3. Khung panel

| Tầng | Cao | Chi tiết |
|---|---|---|
| Vùng thông số | **185** | đệm trên 8 · dải chọn 40 (nếu có) · hàng cuộn · fade đáy 22 về màu panel |
| Dải nhóm | 54 | Back 38 · bánh xe · Save 42×38 |
| Vùng home | 25 | |

- Panel **264** thay 246; 18pt thêm lấy từ ảnh. Bo **22** hai góc trên, **không nét mảnh** mép trên.
- **Hàng thứ n của mọi nhóm nằm cùng một y.** Nhóm không có dải chọn bắt đầu hàng 1 ở chỗ dải chọn.
- Mọi loại hàng cao **40**: slider · công tắc · màu · font · hint (chữ 12pt mờ). Hai nhóm được miễn: bảng màu
  custom của Markup (FS-05.02) và hàng thumbnail của Presets.
- Panel **không đổi chiều cao** trong bất kỳ trạng thái nào.

## 4. Chip và dải chọn

- **Một kiểu chip**: cao 30, bo 8, đệm ngang 8, icon 15pt hoặc chấm màu 8pt cách chữ 4, chữ 13pt trắng; chọn = nền trắng 20% chữ đậm,
  không chọn = nền trắng 6%. Không accent, không viền, không chấm "đã chỉnh".
- **Swatch** (băng màu, điểm màu, thumbnail mask/layer) là ngoại lệ duy nhất: chọn = vòng trắng cách 2pt;
  không chọn = mờ 70%.
- Chip trong dải cách nhau 8, dải đệm ngang 12. Dải chữ **≤5 mục chia đều bề ngang, không cuộn**; >5 mục cuộn ngang, bề rộng tự nhiên. Dải swatch chia đều.
  Chip chia đều mà một nhãn không đủ chỗ cho icon + chữ thì **cả dải** bỏ icon, giữ chữ 13pt (`EditorStripLayout.showsIcons`) — một chip thiếu icon cạnh ba chip có icon đọc như một loại chip khác. Grade (4 chip, "Highlights" ~65pt) vì vậy chỉ có chữ trên cả 402 và 375.

| Nhóm | Dải chọn | Hàng (thứ tự) |
|---|---|---|
| Curve | RGB · Red · Green · Blue (chấm màu kênh) | bố cục hôm nay, đổi kiểu chip + slider; gợi ý thành hàng hint |
| Color Mix | All + 8 băng màu, 9 swatch chia đều | như hôm nay |
| Point Color | chưa có điểm: không dải, giữa vùng là đĩa ống hút 40 + một dòng hướng dẫn · có điểm: swatch điểm + chip ống hút cuối dải (bật = nền trắng 20%) | như hôm nay |
| Grade | Shadows · Midtones · Highlights · Global (icon, bỏ chấm màu vùng) | như hôm nay |
| Presets | Presets · My Looks · LUTs | hàng thumbnail 62 · Amount |
| Crop | mọi tỉ lệ, có icon, cuộn | Straighten · Rotate / Flip / Reset (chip) · footnote (hint) |
| Mask, Markup | xem FS-03.05, FS-05.01 | |

- Presets: ô đầu tab My Looks là **+ Save Current**, ô đầu tab LUTs là **Import .cube**; giữ lâu ô vẫn ra menu xoá.
- Point Color: pill lấy mẫu trên ảnh ("Drag on the photo · Lift to pick") chỉ hiện khi đã có điểm; chưa có
  điểm thì dòng hướng dẫn trong panel thay nó.

## 5. Slider

- Phone: một hàng 40 — nhãn 78pt (12pt, chữ thường, trắng 60%) · rãnh · số 44pt (11.5pt mono, trắng 60%).
- Sidebar: giữ xếp dọc (nhãn trên, rãnh dưới, cao ≥44), cùng kiểu vẽ và nhãn chữ thường.
- Rãnh 3pt (4pt khi là dải màu, mờ 80%), khe mốc 0 cho thông số hai chiều. Công tắc bật = rãnh trắng đặc. Núm **tròn trắng 18pt** có bóng.
- Vệt trắng 50% từ mốc tới giá trị, **chỉ khi khác mặc định**, không vệt trên rãnh màu. Không quầng sáng.
- Đang kéo **không đổi màu** nhãn, số hay nền hàng. Mọi cử chỉ giữ như [FS-03.01 §7](01-scope-and-panel.md#7-dòng-slider).

## 6. Accent và băng lệnh

- Accent chỉ còn trên **Save** trong toàn editor — trừ rail, header và Apply của sidebar (bố cục sidebar giữ).
- Bánh xe: chip giữa trắng đậm, chip khác trắng 32%, **vạch trắng 16×2** dưới tâm.
- Nút trên băng đang giữ/bật (xem bản gốc…) = đĩa trắng + icon đen.
- Không còn dấu "đã chỉnh" nhìn thấy trên panel phone; VoiceOver vẫn đọc "Edited".

## 7. Đã chốt (2026-09-24)

- **Khoảng cách theo thang `DESIGN.md`**: chip cách nhau 8, đệm chip 8, icon–chữ 4 — không dùng 5 · 6 · 10.
- **Thumbnail mask / lớp bo `r-sm` 8**, không dùng `r-track` 6 của Video Studio.
- **Hàng 40pt là miễn trừ tầng D** khỏi luật chiều cao theo cỡ chữ (NF-06) và chạm 44: chữ co tối đa 0,85,
  không cắt ở `.accessibility1`. Sidebar vẫn ≥44.
- **Công tắc bật = rãnh trắng đặc.**
- **Presets miễn lưới 40**: dải nguồn 40 · hàng thumbnail ~90 · Amount 40.
- **Duo màn ngoài dùng panel 264** như phone; ảnh còn ~332pt trong cảnh 382×644.
- **Crop không lặp Vertical · Horizontal**; hai slider đó ở Geometry.
- Còn treo từ trước, spec này không đổi: bánh xe 14 chip hay 9 chip — [FS-03.01 §5](01-scope-and-panel.md#5-dải-nhóm).

## 8. Tiêu chí nghiệm thu

Máy: iPhone 17 (402pt, iOS 26.5) và iPhone 16 Pro (iOS 18.6) · iPhone SE 3rd gen (375pt) · Duo ngoài · iPad.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | màn 402×874 | dựng panel | panel 264 = 185 + 54 + 25, mọi loại hàng 40, dải chọn 40 | `EditorPanelLayoutTests.thePhonePanelIsA264SlabOnA40PointGrid` |
| AC-2 | một ảnh, lần lượt Light · Curve · Mix · Grade · Effects | dump khung slider hàng 1 | cùng y ±0,5pt ở cả năm nhóm | `iphone-panel-grid.json`, 2026-09-25 — iPhone 17 Pro 402 iOS 26.5: tâm hàng 1/2/3 = 638/678/718 ở Light · Curve · Mix · Grade · Effects · Color; SE 375 iOS 18.6: 431/471 ở cả năm |
| AC-3 | từng nhóm trong bánh xe, không đang giữ nút nào | chụp panel + băng | không pixel nào mang màu accent ±8 ngoài nút Save | `Tools/accent-check` trên 15 ảnh iPhone 17 26.5, 2026-09-25 (Light…Markup + Presets): 0 px; `KEEP_SAVE=1` bắt 11 508 px ở Save |
| AC-4 | màn 375pt | mở Curve, Grade, Presets, Color Mix | mọi dải ≤5 mục và dải 9 swatch nằm trọn trong màn, không cuộn | dump SE 375 iOS 18.6, 2026-09-25: Curve 4 chip, Grade 4 chip, Presets 3 chip, Mix 9 swatch, tất cả trong x 12…363 |
| AC-5 | màn 402pt, nhóm Grade rồi Presets | dump hai dải | chip cách nhau 8 ±0,5, dải cách mép 12; Grade không chip nào có icon; Presets icon cách chữ 4 | `iphone-panel-grid.json` iPhone 17 Pro 402, 2026-09-25: Grade 4 chip và Presets 3 chip cách nhau 8,0, cách mép 12,0; Grade không icon; Presets icon→chữ 5,5–6 theo khung glyph (spacing layout 4 — `EditorStripLayoutTests.equalWidthItemsFitTheNarrowestPhone`) |
| AC-6 | Exposure 0 | kéo lên +0,50 rồi chạm đôi | vệt trắng hiện lúc +0,50, mất khi về 0; nhãn và số không đổi màu lúc kéo | ảnh iPhone 17 26.5, 2026-09-24 (kéo Exposure); `valuesSnapOntoTheirDetentWithinAFixedPointDistance` |
| AC-7 | nhóm Color, B&W tắt | bật B&W | rãnh công tắc trắng đặc, không pixel accent | ảnh iPhone 17 26.5, 2026-09-24 (Color · B&W bật) |
| AC-8 | Dynamic Type `.accessibility1` | mở Light | mọi hàng vẫn 40, không nhãn nào bị cắt thành "…" | `se-panel-a11y.json` với `simctl ui … content_size accessibility-medium`, SE 375 iOS 18.6, 2026-09-25: Light, Grade, Mask, Markup — tâm hàng 431/471/511/551 như cỡ mặc định, không nhãn nào bị cắt (chữ panel cỡ cố định, tầng D) |
| AC-9 | đang giữ nút xem bản gốc | chụp băng | đĩa trắng, icon đen | `iphone-hold-and-import.json` + chụp liên tục từ host, iPhone 17 Pro 26.5, 2026-09-25: lúc giữ 14s đĩa nút = (255,255,255), glyph hai ô vuông đen |
| AC-10 | Crop mở | dump panel | đủ mọi tỉ lệ Free…9:16, có Rotate · Flip · Reset và footnote; **không** có hàng Vertical / Horizontal | ảnh iPhone 17 26.5, 2026-09-24; dump `iphone-panel-grid.json` (crop) iPhone 17 Pro 26.5, 2026-09-25: Free · Original · 1:1 · 4:3 · 3:2 · 16:9 · 4:5 · 9:16, Straighten, Rotate · Flip · Reset, footnote; không có Vertical / Horizontal |
| AC-11 | Presets, có look đang chọn | dump vùng thông số | dải nguồn, hàng thumbnail và Amount nằm trọn trong 185pt, không cần cuộn | ảnh iPhone 17 26.5, 2026-09-24 (Presets) |
| AC-12 | Presets, tab LUTs | chạm ô đầu | mở bộ chọn file .cube | `iphone-hold-and-import.json`, iPhone 17 Pro 26.5, 2026-09-25: LUTs → Import .cube mở bộ chọn tài liệu hệ thống (Recents · Shared · Browse) |
| AC-13 | Duo ngoài | mở Light rồi Mask | panel 264, không nút nào dưới rail 84pt | `duo-cover-panel.json` + `Tools/sim-shot … cover`, iPhone Duo 27.1, 2026-09-25: Light và Mask — tâm hàng 1 y 442 = 678 − 264 + 8 + 20, bánh xe tâm 626 (panel 264); Save kết thúc x 366 < 382 (rail 84 bắt đầu), không nút nào dưới rail |
| AC-14 | iPad, sidebar Light | dump Exposure | núm tròn 18, nhãn chữ thường, hàng ≥44 | `aSliderRowIsBigEnoughToHitAndQuickEnoughToNudge` + `ipad-sidebar-slider.json` và `Tools/sim-shot`, iPad Pro 13 26.5, 2026-09-25: sidebar Light — núm tròn trắng, nhãn chữ thường trên rãnh, bước hàng ≈ 46pt, không vệt accent |
| AC-15 | cả hai nhánh iOS 26.5 và 18.6 | chạy AC-2, AC-3 | kết quả như nhau | AC-2 và AC-3 chạy trên iPhone 17 Pro 26.5 và SE 18.6, 2026-09-25: lưới 40 như nhau, 0 px accent ở 11 nhóm cả hai (`Tools/accent-check`) |
| AC-16 | mọi dòng "Chỗ ở mới" của intent | đi tới từng chức năng | tới được, dùng được | `iphone-panel-inventory.json` + `-2.json`, iPhone 17 Pro 26.5, 2026-09-25 — tới được và có mặt: Text (Font · Size · Color · Content · B/I/Align · Opacity · Outline · Shadow · Width · Leading · Tracking · Rotate · Across · Down), Shape (kiểu · Color · Filled · Thickness · Height · Opacity · vị trí), Magnifier (Zoom · Rim · Opacity · vị trí), `⋯` lớp (8 mục), Draw (Draw · Erase · Select · Ruler · 7 mực · Size · Opacity · Color), Sign → thư viện, Mask (Add/Subtract · Undo · `⋯` Rename · Invert · Duplicate · Hide/Show · Delete · lý do Depth), Presets (Save Current · Import .cube), Optics (Lens Profile · Change · Remove CA · Defringe); lớp Image qua PHPicker (`iphone-image-and-detect.json`, 2026-09-25): Choose Image · Size · Opacity · Rotate · Across · Down; ⚠️ chip shape + "Delete This Shape" của mask ≥2 shape **không có điều kiện để thử**: photo editor không có đường nào tạo shape thứ hai trong một mask, trước đợt này (`0e3c58a`) cũng vậy — chờ quyết định (REVIEW_QUEUE) |

Mask: AC-17…AC-25 ở [FS-03.05 §9](05-local-masks.md#9-tiêu-chí-nghiệm-thu-panel-phone) · Markup: AC-26…AC-38 ở
[FS-05.01 §7](../FS-05-markup/01-layers-and-draw.md#7-tiêu-chí-nghiệm-thu-panel-phone).

Không mạng / ảnh chỉ có trên iCloud: panel không đọc mạng, đường tải ảnh giữ như [FS-03](README.md) — không
có AC riêng ở đây.

**Chưa chứng minh được:** một mục của AC-16 — chip shape của mask nhiều shape, vì không tạo được mask nhiều shape (xem REVIEW_QUEUE "Needs a decision"). `/verify` 2026-09-25: `Tools/gate` xanh (iPhone 17 iOS 27.0, 725s).

## 9. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Kéo-giữ thumbnail để đổi thứ tự chết trong vùng cuộn ngang | cử chỉ đi qua UIKit (memory "SwiftUI gesture trong UIScrollView") |
| Chip 13pt co chữ ở tiếng Đức | co tối đa 0,85, còn tràn thì dải chuyển sang cuộn |
| Máy chưa có sim 375pt (iPhone SE 3rd gen) | tạo sim trước khi chạy AC-4 |
| Hàng thuộc tính chữ dài (≥14 hàng) trong 145pt cuộn | tên hàng đọc được khi cuộn; nhóm được `/plan` xếp lại nếu cần |
