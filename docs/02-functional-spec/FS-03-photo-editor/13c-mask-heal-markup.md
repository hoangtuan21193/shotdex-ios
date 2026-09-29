# FS-03.13c — Mask, Heal, Markup trên iPhone

`FS-03.13c` · tier D · `Features/Editing/EditorMaskPhonePanel.swift` · cập nhật 2026-09-28

**Một câu:** ba công cụ dựng hình dùng chung một ngôn ngữ — chưa có gì thì ô lớn chọn loại, có rồi thì một hàng
"[đang chọn] ▼ · + · ⋯" mở ra danh sách dọc, và cọ / vết / bút cùng một kiểu hàng ghim.

Khung, ✕ / ✓: [13a](13a-chrome-and-toolbar.md). Mask làm gì: [FS-03.05](05-local-masks.md), vẽ và zoom:
[FS-03.05b](05b-mask-painting-and-zoom.md). Lớp Markup: [FS-05](../FS-05-markup/README.md).

## 1. Ô chọn loại (Mask và Markup)

- Mở công cụ khi **chưa có** mask / lớp: dòng hướng dẫn 13pt trắng 60% rồi **lưới 4 cột**, ô cao **60**, bo `r-md` 12,
  nền trắng 6%, icon của loại + tên 11,5pt; hàng cách nhau 8. Ô dựng từ danh sách đầy đủ của loại.
- Mask — *"Choose an area to adjust"*, **lưới 4×4**: Subject · Sky · Background · Object / People · Face Skin · Eyes ·
  Lips / Brush · Radial · Linear · Color / Luminance · Depth. Ba ô khuôn mặt giữ ở ngoài, không dời vào People.
- Object và People thuộc [FS-03.15d](15d-mask-additions.md): chưa land thì không hiện, các ô sau dồn lên (còn 3 hàng).
- Panel 344: dòng + 3 hàng vừa trọn, hàng 4 cuộn dọc. Panel 264: thấy 2 hàng, hàng 3 và 4 **cuộn dọc**.
- Loại không dùng được mờ 35% và nói lý do như [FS-03.05 §2](05-local-masks.md#2-chọn-loại-mask).
- Markup — *"Add a layer"*: Text · Image · Sign · Pen / Marker · Rectangle · Oval · Speech bubble / Arrow · Line · Magnifier.
- **Một chạm là tạo**, chọn luôn và sang màn chỉnh. `+` trên hàng đang chọn mở lại lưới với tiêu đề *"New Mask"* /
  *"New Layer"* và `‹`; `‹` không tạo gì.

## 2. Mask đã có mask

- **Hàng trên 40**: thumbnail 30×30 bo 8 · **tên mask 14,5pt đậm + ▼** và dòng phụ 11,5pt các vùng ("Sky − Brush") ·
  chip **Mask Overlay** · `+` 30×30 · `⋯` 30×30. `+` là **nút tạo duy nhất** = mask mới.
- **Mask mới tên "Mask n"** với mọi loại vùng, n = số mask của ảnh sau khi thêm; Rename của ⋯ đổi được (chốt E4).
  - Loại vùng chỉ đọc ở **dòng phụ**: mọi vùng theo thứ tự, vùng trừ sau "−" ("Sky − Brush"; Background đọc "Background").
  - *Vì* mask nhiều vùng mà tên theo vùng đầu sẽ sai. Cùng luật ở [FS-03.05 §3](05-local-masks.md#3-chỉnh-mask-đang-chọn).
- **Chạm tên / ▼ → danh sách dọc** thay vùng thông số: tiêu đề "Masks · n masks"; mỗi mask một hàng 40 (thumbnail ·
  tên · dòng phụ · 👁), dưới mask đang chọn là các **vùng** (⊕ cộng / ⊖ trừ / ⊗ giao) rồi **Add area** · **Subtract area** ·
  **Intersect area** (Intersect của [FS-03.15d §1](15d-mask-additions.md) — thêm 2026-09-29 để iPhone không mất nó);
  cuối danh sách **New Mask**. Hàng đang chọn nền trắng 8%, bo 8.
- Chạm một hàng = chọn mask / vùng đó và **đóng danh sách**. 👁 = ẩn / hiện hiệu ứng của mask đó (như Hide / Show
  của ⋯, thumbnail mờ 35%).
- **Add / Subtract / Intersect area** mở lưới ô với tiêu đề *"Add to Mask 1"* / *"Subtract from Mask 1"* / *"Intersect with Mask 1"*, **đủ mọi loại vùng**, dựng
  từ danh sách như lưới chọn loại (§1). Chạm một loại thêm vùng với chế độ đó. Background làm vùng = Subject đảo (vùng có cờ đảo riêng).
- Dòng phụ hàng trên đọc "Subtracting" khi vùng đang chọn là vùng trừ.
- ⋯ của mask giữ [FS-03.05 §3](05-local-masks.md#3-chỉnh-mask-đang-chọn): Hide / Show · Rename · Invert · Duplicate ·
  Delete This Shape · Delete. Hàng Add / Subtract + Undo cũ và dải thumbnail cuộn ngang **bỏ**.
- Dưới hàng trên: hàng cọ ghim (§3, chỉ khi vùng đang chọn là Brush) rồi **slider của mask là một danh sách dài**
  như Edit, nhãn dính + mục lục (LIGHT · COLOR · DETAIL · EFFECTS · MASK · SHAPE).

## 3. Hàng cọ ghim và phủ đỏ

- Tạo Brush → **vẽ ngay**, không chạm thêm. Hàng cọ **một hàng 40 ghim** dưới hàng trên, không cuộn theo danh sách:
  **[Vẽ][Tẩy]** (chip 40×30, icon) · vạch 1×20 · viên **Size · Feather · Flow** chia đều, mỗi viên chữ + số mono.
- **Chạm một viên** → cả hàng thành slider của viên đó + nút ✓ 30×30 bên phải; ✓ trả hàng về. **Giữ viên rồi kéo
  ngang** đổi giá trị ngay trên viên, cùng độ nhạy slider.
- Đang đổi Size: **vòng xem trước** cỡ cọ hiện giữa ảnh (hiển thị, không nhận chạm). Size là cỡ **trên màn**: zoom
  vào thì nét nhỏ trên ảnh ([FS-03.05b §2](05b-mask-painting-and-zoom.md#2-cỡ-cọ-theo-màn-hình)).
- Số đọc 0–100 không `%` như FS-03.05 §3. Opacity và Clear Strokes của Brush ở nhóm MASK · SHAPE của danh sách.
- **Phủ đỏ tự động**: ngón đang vẽ → hiện; nhấc tay → mờ dần trong ~1,5s; kéo một slider → tắt để thấy hiệu ứng.
- Chip **Mask Overlay** bật (nền trắng 20%) = **ghim** phủ đỏ: hiện cả lúc kéo slider. Chip tắt = về luật tự động.
- Luật phủ đỏ này áp cho **mọi layout**, kể cả sidebar — một nút cùng tên, một hành vi. Thời gian mờ 1,5s là số
  mới, phải vào `DESIGN.md`.

## 4. Heal

Cùng kiểu hàng với cọ; panel dùng hết chỗ, từ trên xuống:

| Hàng | Nội dung |
|---|---|
| chế độ | **Heal · Clone** chia đều, có icon; Red Eye là ô tiếp theo khi [FS-03.15c](15c-retouch-and-red-eye.md) land |
| cọ ghim | viên **Size · Feather · Opacity** — cùng hành vi viên của §3 |
| SELECTED SPOT | chip **New Source · Delete Spot** — mờ 0,35 và không nhận chạm khi chưa chọn vết |
| SPOTS · n | công tắc **Visualize Spots** (+ slider Threshold khi bật) · chip **Show Spot Pins · Clear All** |

- Chạm ảnh thêm vết, kéo vòng nguồn đổi nguồn như [FS-03.11 §2](11-parity-with-lightroom.md#2-xoá-vết-heal--clone).
- **Clear All** hỏi xác nhận khi có **từ 2 vết** (1 vết thì gỡ luôn): tiêu đề "Clear all spots?", nút phá huỷ
  **"Clear All Spots"**; là **một** bước Undo; mờ khi 0 vết.
- **Không có Remove** (tô lên vật để xoá): tạm bỏ tới khi Apple có model hỗ trợ; không chip, không chỗ giữ sẵn.
- Opacity, New Source, Visualize Spots + Threshold, Show Spot Pins, Clear All thuộc FS-03.15: chưa land thì **không
  hiện**, không nút mờ; thứ tự giữ chỗ để chúng hiện đúng vị trí.

## 5. Markup

- **Hàng trên**: thumbnail · **tên lớp ▼** + dòng phụ (chữ đã thay token, hoặc loại lớp) · `+` · `⋯`. Không chip overlay.
  Chạm lớp trên ảnh cũng chọn lớp đó.
- **Danh sách lớp** (chạm ▼): "Layers · n layers · front to back"; hàng 40: **≡** · thumbnail · tên · 👁; **đầu danh
  sách = trên cùng ảnh**. Kéo ≡ **theo chiều dọc** đổi thứ tự, một bước Undo; cuối danh sách **Add Layer**.
  Thay cú giữ-kéo thumbnail trong dải ngang của FS-05.01 §6. ⋯ của lớp giữ nguyên các mục.
- Lớp chữ: hàng Font (tên font) · **B** · **I** · **nhóm căn lề 3 nút liền** (trái · giữa · phải, một nút sáng) rồi các
  hàng thuộc tính theo thứ tự FS-05.01 §6. VoiceOver đọc nhóm "Text alignment", từng nút "Align left / center / right".
- **Pen / Marker**: hàng 1 **[Vẽ][Tẩy]** · vạch · viên **Size · Opacity** · chấm màu đang dùng 26; hàng 2: 7 ô màu
  chia đều; hàng 3: chip **Select · Ruler**. Hàng cuối Rotate · Across · Down.
- **Chạm chấm màu → trang con trong panel**: lưới loại mực (dựng từ danh sách mực, hôm nay 7: Pen · Marker · Pencil ·
  Fountain · Monoline · Watercolor · Crayon) rồi bảng màu, như trang bảng màu custom của FS-05.02; `‹` về hàng bút.
- Loại lớp khung thoại tên **"Speech bubble"** như FS-05.01 — "Bubble" đã là tên một hình bokeh của Lens Blur.

## 6. Tiêu chí nghiệm thu

Máy: iPhone 17 iOS 26.5 và 18.6, ảnh 3:2 (panel 344) nếu không ghi khác. Tiếp số của 13b.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-25 | ảnh chưa có mask, ảnh 3:4 (panel 264) | chạm Mask | lưới 4 cột đủ mọi mục của danh sách vùng, mỗi mục một lần, Face Skin · Eyes · Lips là ô riêng; thấy 2 hàng, các hàng sau tới được bằng cuộn dọc; không cuộn ngang | ✅ `MaskPhonePanelTests.chooserTilesCoverEveryKindOnce` · `iphone-mask-list.json` (ảnh 3:4, panel 264: 2 hàng, cuộn dọc ra hàng 3–4) |
| AC-26 | như AC-25 | chạm Brush rồi kéo một ngón 100pt trên ảnh | có 1 mask, 1 nét, không cần chạm thêm; hàng trên "Mask 1 ▼ · Mask Overlay · + · ⋯", dòng phụ "Brush"; hàng cọ ghim | ✅ `MaskPhonePanelTests.brushTileDrawsImmediately` · `MaskAreaSummaryTests.subtitleListsEveryArea` · `iphone-mask-brush-row.json` (hàng trên "Mask 1 ▼ · Brush · Mask Overlay · + · ⋯"); hàng cọ ghim: AC-30 |
| AC-27 | 1 mask | chạm `+` rồi `‹` | vẫn 1 mask, mask cũ vẫn chọn | `MaskPhonePanelTests.plusThenBackMakesNothing` (vẫn 1 mask, mask cũ vẫn chọn) |
| AC-28 | Mask 1 = Sky − Brush, Mask 2 = Radial, Mask 1 chọn | chạm ▼ | danh sách đúng thứ tự: Mask 1 · Sky ⊕ · Brush ⊖ · Add area · Subtract area · Intersect area · Mask 2 · New Mask | ✅ `MaskPhonePanelTests.listPutsAreaActionsUnderTheSelectedMask` · `iphone-mask-areas.json` (1-list, 4-list-two-areas) |
| AC-29 | danh sách mở, Mask 1 = Sky | Subtract area → Brush | lưới "Subtract from Mask 1" có mọi loại của danh sách (cả Background, Color, Luminance, Depth); Mask 1 có 2 vùng, vùng 2 là trừ; danh sách đóng; dòng phụ "Subtracting" | ✅ `MaskPhonePanelTests.subtractAreaAddsASubtractingBrush` · `MaskIntersectTests.anInvertedAreaIsItsComplement` · `iphone-mask-areas.json` (2-subtract-grid, 3-subtracting) |
| AC-30 | Brush, Size 40 | chạm viên Size, kéo slider tới 60, chạm ✓ | hàng về 3 viên, viên Size đọc 60; lúc kéo có vòng xem trước trên ảnh | ✅ `iphone-brush-pills.json`: Size mặc định 50 (không phải 40 như AC ghi) → kéo tới 69, ảnh lúc giữ tay (hold-1) có vòng xem trước giữa ảnh, ✓ về 3 viên đọc "Size 69" |
| AC-31 | Brush, chip Mask Overlay tắt, trên iPhone 17 và iPad 13" sidebar | vẽ 1 nét, nhấc, chờ 2s, rồi kéo Exposure | lúc vẽ có phủ đỏ; 2s sau nhấc không còn; lúc kéo không có. Bật chip rồi kéo Exposure: phủ đỏ còn. Hai máy như nhau | ✅ `MaskOverlayPolicyTests.autoOverlayFollowsPaintAndYieldsToSliders` · `iphone-mask-overlay-policy.json` + `ipad-mask-overlay-policy.json` (ảnh lúc giữ tay: vẽ có phủ; 2s sau nhấc không; kéo slider không; ghim rồi kéo còn — hai máy như nhau) |
| AC-32 | Brush trên SE 375 và Duo ngoài 326pt | dump hàng trên và hàng cọ | không nhãn nào thành "…", chip đọc "Mask Overlay", mọi nút trong khung, `+` và `⋯` ≥30pt | ✅ SE 375 iOS 18.6 `se-mask-fit.json` ("Mask Overlay" đủ chữ, + và ⋯ 30pt) · Duo ngoài 326 `duo-cover-editor.json` (chip rút thành "Overlay" theo 13d §3 vì "Mask 1" bị cắt; "Mask 1", "Feather 45" đủ chữ) |
| AC-33 | Heal, 3 vết, vết 2 chọn | dump panel, rồi Delete Spot | hàng chế độ không có Remove, không nút mờ vì chưa có; còn 2 vết, nhãn "SPOTS · 2", hàng SELECTED SPOT mờ | ✅ `PhotoHealingTests.deletingASpotLeavesNonePicked` · `iphone-heal-markup.json` (hàng chế độ Heal · Clone · Red Eye, không Remove; sau Delete Spot: "SPOTS · 2", SELECTED SPOT mờ) |
| AC-34 | Markup, 3 lớp: Text 1 · Drawing 1 · Logo (trên → dưới) | mở danh sách, kéo ≡ của Logo lên đầu | thứ tự Logo · Text 1 · Drawing 1, ảnh vẽ Logo trên cùng; một Undo trả thứ tự cũ | ✅ `MarkupPhonePanelTests.verticalListRestacksTheLayer` · `iphone-layer-list.json` (danh sách "Layers · 3 layers · front to back", kéo ≡ đổi thứ tự) |
| AC-35 | lớp chữ căn trái | chạm nút giữa của nhóm căn lề | chữ căn giữa; đúng 1 trong 3 nút sáng | `MarkupPhonePanelTests.alignmentGroupIsARadio` (nhóm "Text alignment", nút "Align left/center/right") |
| AC-36 | ảnh chưa có lớp, quyền `.limited` | Add a layer → Pen, chạm chấm màu, thử từng loại mực | tạo 1 lớp nét vẽ, vẽ được ngay; trang con có mọi loại mực của danh sách và bảng màu, không dải cuộn ngang; lớp Image mở bộ chọn ảnh hệ thống, không xin thêm quyền | ✅ `MarkupPhonePanelTests.everyInkIsReachable` · `iphone-markup-ink.json` (lưới 11 loại lớp 4 cột; Pen vẽ ngay; trang con đủ 7 mực + bảng màu, không cuộn ngang); lớp Image dùng `PHPickerViewController` (`EditorSignatureImagePicker.swift:43`, không xin quyền) — phần quyền `.limited` ⚠️ chưa chạy trên sim (thư viện sim đang Full Access) |

**Chưa chứng minh được:** AC-25…AC-36 — chưa có code.
