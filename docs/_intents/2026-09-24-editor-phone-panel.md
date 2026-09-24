# Intent: Làm lại giao diện panel editor trên phone

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan |
| Ngày | 2026-09-24 |
| Trạng thái | accepted |
| Tiến độ | **đang làm** (2026-09-25) — plan [2026-09-24-fs-03-12-phone-panel](../_plans/2026-09-24-fs-03-12-phone-panel.md): task 21/22, 27/38 AC xanh (còn AC-8, 9, 12, 13, 14, 16, 21, 23, 33, 35, 38) |
| Nguồn | phản hồi người dùng (chủ sở hữu sản phẩm) — bản bàn giao từ Claude Design |
| Spec sinh ra từ đây | [FS-03.12](../02-functional-spec/FS-03-photo-editor/12-phone-panel-grid.md) (+ FS-03.01, 01b, 02, 05 · FS-04.01, 02 · FS-05 README, 01, 02, 03) |

Tham chiếu: [bản bàn giao](assets/2026-09-24-editor-phone-panel/design-handoff.md) và
[prototype](assets/2026-09-24-editor-phone-panel/ShotDex%20Editor%20Prototype.dc.html) (không chạy được vì thiếu
`support.js`; đọc từ mã nguồn). Ưu tiên: **"Đã chốt" > "Chỗ ở mới" > prototype > bản bàn giao.** Hàng thông số
trong prototype là dữ liệu mẫu; danh sách thật lấy từ catalog trong code.

**Luật đọc intent này:** chỉ ghi cái **thay đổi**. Chức năng nào không được nhắc thì giữ nguyên như code hôm nay —
kể cả khi bản bàn giao hay prototype bỏ nó đi (người dùng chốt 2026-09-24: không mất chức năng nào, chỉ đổi giao
diện và bố cục).

Liên quan: [2026-09-22-editor-panel-lightroom-layout](2026-09-22-editor-panel-lightroom-layout.md) (màn rộng).

## Problem — vấn đề

Panel editor trên phone trông như ghép từ nhiều lượt làm khác nhau, và người dùng thấy điều đó mỗi lần đổi nhóm:

- **Hàng slider nhảy chỗ khi đổi nhóm.** Hàng thông số cao 34pt
  ([EditorLayoutMetrics.swift:284](ShotDex/Domain/Editing/EditorLayoutMetrics.swift:284)) nhưng dải chọn đối
  tượng cao 36pt ([EditorLayoutMetrics.swift:44](ShotDex/Domain/Editing/EditorLayoutMetrics.swift:44)) và chỉ
  Grade có nó ([PhotoEditorScreen.swift:2382](ShotDex/Features/Editing/PhotoEditorScreen.swift:2382)). Đổi từ
  Light sang Grade thì slider đầu tiên tụt 36pt.
- **Accent ở khắp nơi, nên accent không còn nghĩa gì.** Vệt slider và `CursorGlow`
  ([EditorSliderRow.swift:169,335](ShotDex/Features/Editing/EditorSliderRow.swift:169)), giá trị khi đang kéo, chip
  chọn (`EditorChipButtonStyle`, [EditorToolPanels.swift:659](ShotDex/Features/Editing/EditorToolPanels.swift:659)),
  chip giữa bánh xe nhóm ([PhotoEditorScreen.swift:3003](ShotDex/Features/Editing/PhotoEditorScreen.swift:3003)) —
  cùng màu với Save.
- **Một khái niệm, nhiều kiểu chip.** Kênh Curve, vùng Grade, chế độ Heal, tỉ lệ Crop, tool Markup mỗi nơi một kiểu.
- **Tạo mask tốn một lớp sheet** ([PhotoEditorScreen.swift:735](ShotDex/Features/Editing/PhotoEditorScreen.swift:735))
  — sheet che tấm ảnh người ta đang định khoanh vùng.
- **Draw nhường cả đáy màn cho `PKToolPicker`**
  ([EditorDrawingCanvas.swift:99](ShotDex/Features/Editing/EditorDrawingCanvas.swift:99)): panel ShotDex biến mất
  lúc vẽ. Thêm layer Markup phải qua menu lồng hai tầng
  ([EditorTextPanel.swift:41-54](ShotDex/Features/Editing/EditorTextPanel.swift:41)); drawing là một lớp cố định
  ở đáy, không đổi thứ tự được.
- **Slider nhìn cũ**: nhãn VIẾT HOA 10.5pt, con trỏ vạch 4×14.

Mức độ: không chặn thao tác nào, nhưng là panel người dùng nhìn nhiều nhất trong app.

## Proposed outcome — kết quả mong muốn

- Panel phone cao 264, vùng thông số 185, **lưới hàng 40pt**, bo trên 22, không nét mảnh. Đổi qua
  lại hai nhóm bất kỳ, slider hàng 1 đứng yên.
- **Accent chỉ còn trên nút Save, trong toàn editor.**
- Một kiểu chip, một kiểu slider (núm tròn 18pt, vệt trắng 50%, nhãn chữ thường) — trên phone **và** sidebar.
- Không còn dấu "đã chỉnh" nhìn thấy trên panel phone.
- Mask và Markup chọn loại ngay trong panel, một chạm là có; có rồi thì dải đầu là thumbnail · `+` · tên · `⋯`.
- Vẽ bằng panel ShotDex, không còn `PKToolPicker` ở đáy màn.

### Đã chốt với người dùng (2026-09-24)

| # | Chủ đề | Chốt |
|---|---|---|
| 1 | Bánh xe nhóm | chip giữa trắng (icon + chữ weight 600, nét 1.9), chip khác white .32 (nét 1.6), vạch trắng 16×2 dưới tâm |
| 2 | Băng lệnh trên | nút đang giữ/bật (Before/After…) = nền trắng + icon đen, thay accent |
| 3 | Dấu "đã chỉnh" | bỏ dấu nhìn thấy trên panel phone (VoiceOver vẫn đọc "Edited"; sidebar không đổi) |
| 4 | Markup | mô hình layer như Mask. Chưa có layer / chạm `+`: tiêu đề "Add a layer" + 3 hàng chip cuộn ngang — ① Text · Image · Sign ② Pen · Marker ③ Rectangle · Oval · Speech bubble · Arrow · Line · Magnifier. Có layer: dải thumbnail · `+` · tên · `⋯`; hàng dưới là thuộc tính layer đang chọn (thứ tự ở "Chỗ ở mới") |
| 5 | Layer nét vẽ | mỗi lần vẽ = một layer, xếp thứ tự như text/image; chọn layer nét vẽ rồi vẽ tiếp thì vẽ vào layer đó |
| 6 | `⋯` của layer | Rename · Duplicate · Hide/Show · Bring forward · Send backward · Save as Preset · Delete · Remove all layers; giữ-kéo thumbnail để đổi thứ tự |
| 7 | PencilKit | giữ `PKCanvasView`, **ẩn `PKToolPicker`**, panel lái `canvas.tool` |
| 8 | Mask chọn loại | tiêu đề "Choose an area to adjust" + 3 hàng chip: Subject · Sky · Background · Face skin · Eyes · Lips / Brush · Linear · Radial / Color · Luminance · Depth. Một chạm tạo mask, không sheet |
| 9 | Presets | target strip Presets · My Looks · LUTs trên hàng thumbnail |
| 10 | Màu custom Markup | Recent chỉ trong phiên; eyedropper lấy màu từ ảnh |
| 11 | Thiết bị | phone + Duo màn ngoài đổi bố cục; sidebar màn rộng chỉ đổi kiểu slider + chip |
| 12 | Crop | bố cục prototype: target strip tỉ lệ có icon (mọi `CropAspect`, cuộn nếu không vừa) → Straighten → hàng chip Rotate · Flip · Reset → footnote dạng hàng hint |
| 13 | Panel → PencilKit | chip loại mực Pen · Marker · Pencil · Fountain · Monoline · Watercolor · Crayon → `PKInkingTool(type, color:, width:)`; Size → `width` (trong `validWidthRange`); Opacity → alpha của `color`; Color → swatch · custom · eyedropper; Erase → `PKEraserTool(.vector / .bitmap, width:)`; Select → `PKLassoTool()`; Ruler → `canvas.isRulerActive`; double-tap / squeeze Pencil → `UIPencilInteraction` (không còn picker lo việc này). Lasso chỉ chọn trong layer đang chọn |
| 14 | Color Mix | "All" + 8 swatch, 9 mục chia đều, không cuộn |
| 15 | Slider iPad / Duo trong | cùng kiểu vẽ với phone (núm tròn 18, vệt white .5, track 3pt, nhãn chữ thường, không accent); giữ xếp dọc nhãn trên · track dưới |
| 16 | Máy nghiệm thu | iPhone 17 (402pt) cho vị trí hàng; sim 375pt (iPhone SE 3rd gen) cho dải chia đều; Duo ngoài; iPad |
| 17 | Dải thumbnail Markup + Mask | chạm chọn một layer / mask trên ảnh → dải thumbnail tự cuộn tới mục đó, đưa vào giữa; hai đường chọn (ảnh ⇄ thumbnail) luôn khớp nhau (theo Procreate / Canva) |

### Chỗ ở mới cho chức năng đang có

Những chức năng mà bản bàn giao/prototype không vẽ chỗ. `/spec` được đổi chỗ, không được bỏ. Luật chung: hàng
ghi trong bản bàn giao là **các hàng đầu**; phần còn lại xếp tiếp bên dưới, vùng thông số cuộn.

| Chức năng hôm nay | Chỗ ở mới |
|---|---|
| Text: Opacity, Outline, Shadow, Width, Leading, Tracking, Bold, Italic, Alignment (`EditorTextDetailPanel.swift:98-330`) | sau Font · Size · Color; Bold · Italic · Alignment chung một hàng chip |
| Shape: đổi kiểu, fill, Filled, Thickness, Height, Opacity (`:383-464`) | hàng chip kiểu → Color → Filled → Thickness → Height → Opacity |
| Image: Choose/replace, Opacity (`:347-373`) | hàng chip Choose Image → Opacity |
| Magnifier: Zoom, màu + độ dày viền, Opacity (`:471-509`) | Zoom → Rim color → Rim width → Opacity |
| Rotate · Across · Down (`:520-551`) | ba hàng cuối của mọi layer |
| Thư viện chữ ký (`EditorSignatureSheet.swift`) | chip Sign mở thư viện |
| Mực, eraser, lasso, ruler (chốt #13) | hàng 1: chip Draw · Erase · Select + Ruler; hàng 2: chip loại mực; rồi Size · Opacity · Color |
| Mask: chọn shape trong mask nhiều shape, Add/Subtract (chế độ), Undo (`EditorMaskPanels.swift:382-400,494-544`) | hàng đầu dưới dải mask: chip shape (khi ≥2) · công tắc Add/Subtract · Undo |
| Mask ⋯ | Rename · Invert · Duplicate · Delete This Shape (khi ≥2) · Delete |
| Lý do loại mask bị tắt (`EditorNewMaskOption.swift:84`) | chạm chip mờ → tiêu đề đổi thành lý do trong 3s |
| Presets: Save Current, Import .cube (`EditorToolPanels.swift:89-231`) | ô đầu tab My Looks = + Save Current; ô đầu tab LUTs = Import .cube |
| Công tắc B&W, Chromatic Aberration, Lens Correction, Filled, Ruler | trạng thái bật phải rõ khi không có accent |

## Affected users and systems — phạm vi ảnh hưởng

- **Thiết bị**: iPhone (402pt và 375pt), Duo màn ngoài 466×678 sau rail 84pt; iPad + Duo trong chỉ kiểu slider/chip.
- **Code**:
  - Domain: `EditorLayoutMetrics.swift` (246/167/36/34/88/40 → 264/185/40/40/78/44 + hằng mới).
  - Features/Editing: `PhotoEditorScreen.swift` (panel, target strip, wheel, băng lệnh, phép tính giả định 246 —
    dòng 585, 1111), `EditorSliderRow.swift` (inline + stacked), `EditorToolPanels.swift`, `EditorCurveOverlay.swift`,
    `EditorColorPanel.swift`, `EditorMaskPanels.swift`, `EditorTextPanel.swift`, `EditorTextDetailPanel.swift`,
    `EditorOverlayColorControl.swift`, `EditorHealPanel.swift`, `EditorDrawingCanvas.swift`, `EditorTheme.swift`,
    `EditorAdjustmentPanel.swift`, `EditorSidebar.swift`.
  - ShotDexKit: `PhotoOverlayModels.swift` / `PhotoDrawingModels.swift` — drawing vào ngăn xếp overlay, **một
    `PKDrawing` cho mỗi layer**; `PhotoRenderService+Drawing.swift` rasterize theo từng layer, theo thứ tự layer.
  - Tests: `EditorPanelLayoutTests.swift`; UI scripts `ipad-panel-verify.json`, `ipad-rail-band.json`.
  - Docs: `FS-03.01` (panel 246), FS-03 mask và markup; `DESIGN.md` §7 tier D.
- **Dữ liệu đã lưu**: recipe đổi từ một drawing thành các layer nét vẽ. App chưa release — không migration; decode
  vẫn khoan dung (`LossyArray`).
- **Extension**: nhiều layer nét vẽ = nhiều lần rasterize; vẫn phải nằm trong trần bộ nhớ extension.

## Constraints — ràng buộc

- **Không mất chức năng nào.** Thay đổi dữ liệu duy nhất là chốt #5. Mỗi dòng "Chỗ ở mới" cần AC riêng ở `/spec`.
- `DESIGN.md` §7 cập nhật cùng lượt (panel 264, lưới 40, bo 22, không nét mảnh, một kiểu chip, núm tròn, accent chỉ
  trên Save).
- Panel không đổi chiều cao trong mọi trạng thái (bảng màu custom, detect mask, đổi tool). 18pt thêm lấy từ ảnh.
- Phone có đủ mọi thứ iPad có; dải dựng bằng `allCases` / catalog.
- Nhánh iOS 26 và pre-26 cùng chạy. Không thêm dependency.

## Open questions — câu hỏi còn treo

Đều cho `/spec` đo và đề xuất, không chặn việc duyệt intent:

1. **Lasso** có dời nét sang layer khác được không (PencilKit chỉ chọn trong một canvas)? → `prior-art`.
2. **Luật chia đều / cuộn** của dải: bản bàn giao nói ≤5 mục chia đều, nhưng Color Mix 9 mục chia đều (chốt #14).
   Cần một ngưỡng chung (≥ N pt mỗi mục ở 375). → `/spec`.
3. **Curve** — target strip kênh + Reset + gợi ý (hàng hint) + hàng preset có vừa 185pt? Reset và preset chung một
   hàng hay hai? → `device-layout`.
4. **Presets** — strip 40 + thumbnail ~90 + Amount 40 = 170 trên 177pt: vừa nhưng phá lưới 40. Chấp nhận? → `/spec`.
5. **Duo màn ngoài** — panel 264 + band ~48 → ảnh còn ~366pt. → `duo-ux-review`.
6. **Giữ-kéo thumbnail** trên dải cuộn ngang: ngưỡng giữ để không cướp cử chỉ cuộn (Drag/LongPress SwiftUI chết
   trong UIScrollView — memory "SwiftUI gesture trong UIScrollView"). Mask có dùng chung không? → `iphone-ux-review`.
7. **Trạng thái bật của công tắc** khi không có accent: trắng đặc? nhãn On? → `a11y-voiceover`.
8. **Drawing cũ** (một `PKDrawing` ở đáy): đọc thành layer nét vẽ đầu tiên (đề xuất) hay bỏ qua? → `/spec`.
9. **Layer nét vẽ không được chọn** hiển thị bằng ảnh rasterize tĩnh hay `PKCanvasView` chỉ-xem? Ảnh hưởng bộ
   nhớ. → `memory-leak`.
10. **Crop trong prototype có Vertical · Horizontal** (slider của Geometry): lặp trong Crop, hay Crop chỉ có
    Straighten? → `/spec`.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
