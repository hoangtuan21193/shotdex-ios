# FS-18.03 — Editor và xuất

`FS-18.03` · tier D · board `MAC_Edit` · `MAC_EditPhotos` · `MAC_EditBatch` · `MAC_Export` · các `MAC_Edit*` theo công cụ
· cập nhật 2026-10-04

**Một câu:** cùng editor và cùng recipe với iPhone, xếp như Lightroom trên desktop — công cụ trên toolbar, inspector
320 bên phải, filmstrip ở đáy; ảnh thư mục tự lưu, ảnh Photos chốt bằng Done.

Công cụ (thông số, mask, heal, markup, preset) làm gì: [FS-03](../FS-03-photo-editor/README.md). Phần này chỉ ghi
bố cục Mac, cách lưu và sheet xuất.

## 1. Bố cục

- Mở trong cửa sổ chính (⌘E, Return từ Viewer); sidebar ẩn, nút sidebar mở panel **Presets and History**
  (My Looks · Film · LUTs, Snapshots, History) ở chỗ sidebar (`MAC_EditPresets`).
- Toolbar: sidebar · ◀ ▶ · tên file, dòng phụ "2026 Japan · Fujifilm X-T5 · XF56mmF1.2 R WR · 3 of 48" ·
  segmented **Adjust · Crop · Mask · Heal · Markup** (316) · nhóm Undo · Redo · Before and After · Fit ▾ · Export ·
  inspector · trạng thái lưu (§2).
- Inspector **320**: thẻ histogram (bật clipping bóng/sáng, dòng ISO · tiêu cự · khẩu · tốc) · Look ▾ + Amount ·
  các nhóm gập theo thứ tự pipeline: Light · Tone Curve · Color · Color Mixer · Point Color · Grading · Effects ·
  Lens Blur · Detail · Optics · Calibration.
- Hàng slider **24**: nhãn · rãnh · ô số. Kéo để chỉnh, nhấp đúp để về mặc định (tooltip ghi đúng câu đó);
  chuột phải: Reset · Enter Value…. Ô số gõ trực tiếp được.
- Filmstrip đáy: ô 84×56, ảnh đang sửa vòng trắng, ảnh đã sửa có huy hiệu; chữ "3 of 48".
- Không có gì nổi trên ảnh ngoài thẻ histogram trong inspector; canvas là vùng duy nhất nhận kéo/zoom/vẽ.
- Màu: luôn tối kể cả chrome cửa sổ (D10); accent chỉ trên lệnh chốt (Done, Export).
- Cửa sổ dưới 1100 rộng: segmented thành 5 icon có tooltip, inspector đè lên mép phải ảnh khi mở; cửa sổ không
  tự nới ([01](01-window-and-navigation.md) §4). ⌥⌘O đưa Editor sang cửa sổ riêng.

### 1a. Đã dựng (row 31, 2026-11-15)

`ShotDexMac/Editor/` (`MacEditorModel`, `MacEditorPage`, `MacEditorInspector`):

- Mở bằng **Edit** / ⌘E trên viewer — chỉ bật cho ảnh có bản file (thư mục, ổ, NAS) và ảnh demo; ảnh chỉ có trong
  thư viện Photos: Edit mờ, tooltip "Photos library pictures can't be edited here yet" (row 40). Editor thay cả vùng chi
  tiết (sidebar đã ẩn từ viewer), các ảnh của viewer thành filmstrip. ◀ / ⌘[ / Esc về viewer trên ảnh đang sửa; chọn
  nơi khác ở sidebar cũng lưu rồi đóng editor.
- Toolbar: ◀ · tên file + dòng phụ "nguồn · máy · ống · 12 of 226" · **Adjust** · Crop · Mask · Heal · Markup (Crop
  ở §1b; ba cái sau mờ, tooltip "comes in a later version", rows 34–36) · Undo (⌘Z) · Redo (⇧⌘Z) · Before and After (`\`, chữ
  "Original" trên ảnh; chỉnh gì là tự tắt) · Fit ▾ (Actual Size mờ tới khi có render 1:1) · inspector (⌥⌘I) · "✓ Edited
  · Saved" / "Saving…" / "Couldn't Save — Try Again" (bấm để ghi lại) · **Revert to Original…** (hỏi lại; ⌘Z lấy
  lại). Presets and History, ▶, Export chưa hiện (rows 37, 39).
- Canvas đen; vẽ bằng `PhotoRenderService` của kit, mỗi lúc một lần vẽ, yêu cầu mới nhất thắng: trong lúc kéo slider
  ảnh 1000px qua base đã giải mã, thả tay 90 ms sau vẽ 2400px, histogram tính từ ảnh sạch. Vẽ lỗi: giữ khung cũ, dòng
  "ShotDex can't show this edit. Undo or change it to try again." Clipping: hai nút góc thẻ histogram, lớp đỏ/xanh `ClippingOverlay`
  làm ngoài main.
- Inspector 320: thẻ histogram (ba kênh, ISO · tiêu cự · khẩu · tốc) · **Look** (các look của `PhotoFilter`) +
  **Amount** · nhóm theo thứ tự board. Có slider: Light (mở sẵn), Color, Effects, Detail, Optics (Lens Profile +
  Manual + Defringe) — lấy từ `EditorAdjustmentCatalog` chung với iPhone, cùng thang và cách ghi số. Tone Curve,
  Lens Blur, Calibration: mở ra ghi "This group comes in a later version."; Tone Curve, Color Mixer, Point Color,
  Grading ở §1c.
  Nút ↺ cạnh tên nhóm khi nhóm có giá trị khác mặc định.
- Hàng slider 24: tên · rãnh 3pt (tô từ điểm 0 ra, vạch ở 0, núm 12pt, trung tính) · ô số có khung (Return hoặc rời ô
  là áp; không phải số thì trả lại). Kéo dịch giá trị theo quãng kéo (nhấp không đổi gì); nhấp đúp về mặc định (tooltip
  ghi đúng câu đó); chuột phải Reset · Enter Value…. Một lần kéo là một bước Undo; Undo giữ riêng cho từng ảnh suốt phiên.
- Filmstrip 84×56: ảnh đang sửa viền trắng, ảnh đã sửa có huy hiệu, ảnh lưu lỗi có dấu ⚠; "12 of 226". Bấm ô khác:
  lưu ảnh đang mở rồi mở ảnh kia.
- **Lưu**: ảnh thư mục/ổ/NAS tự lưu 400 ms sau thay đổi cuối và ngay khi rời ảnh/editor (`PhotoRecipeStore` +
  sidecar), ghi lần lượt theo thứ tự; ⌘Q ghi ngay. Lý do không sửa được, nói trên canvas: ảnh iCloud Drive chưa tải ·
  ổ/server không nối · ảnh Photos (Done là row 40). Demo: ảnh demo sửa được như ảnh thư mục.
- Chưa có: Auto của Light, ⌥⌘O cửa sổ riêng, bố cục icon dưới 1100pt, Done cho ảnh Photos, Actual Size, phím ←/→ đổi
  ảnh, Return mở editor từ viewer, Edit trong menu chuột phải / menu Photo.

### 1b. Crop (row 32, 2026-11-15, board `MAC_EditCrop`)

`ShotDexMac/Editor/MacEditorCrop.swift`, toán ở `ShotDex/Domain/Editing/CropFrameEditing.swift` (test
`CropFrameEditingTests`). Cùng recipe với iPhone (`PhotoCropRecipe`, `PhotoUprightRecipe`, các slider Geo).

- **Crop** trong capsule công cụ bật chế độ Crop; **Adjust** hoặc **Esc** (ở đâu cũng được) về Adjust. Không có
  Done/Cancel: mỗi thay đổi tự lưu như mọi chỉnh khác, ⌘Z lùi từng bước (một lần kéo = một bước).
- Canvas: cả ảnh đã xoay/lật/nghiêng (khung crop không áp; mask và lớp chữ tạm ẩn vì nằm trong toạ độ đã cắt),
  ngoài khung tối 55%, lưới 1/3, góc chữ L 20×3 và thanh 20×3 giữa mỗi cạnh. Kéo góc: góc đối diện đứng yên; kéo
  cạnh: cạnh đối diện đứng yên; kéo trong khung: dời khung. Con trỏ đổi theo chỗ đặt. Khung không bao giờ ra ngoài
  ảnh — kể cả khi ảnh đang nghiêng (kéo dừng ở mép ảnh). Kéo khung không vẽ lại ảnh.
- Inspector, nhóm **Crop**: Aspect ▾ (Free · Original · 3:2 … — "Original · 3:2" khi tỉ lệ ảnh có tên) ·
  🔒 khoá tỉ lệ (mở = Free; khoá lại giữ đúng tỉ lệ khung đang có nếu nó có tên, không thì tỉ lệ đã chọn trước, mặc
  định Original — khoá không làm khung nhảy) · ⇅ đổi chiều (3:2 ↔ 2:3, 16:9 ↔ 9:16, 4:5 ↔ 5:4, 4:3 ↔ 3:4; Free xoay
  khung quanh tâm; 1:1 và Original của ảnh vuông mờ). Chọn tỉ lệ = khung đổi dáng quanh tâm, giữ diện tích
  (khác iPhone: Original không trả về cả ảnh). Dòng **Size** "354 × 354 px" + "93% of original". ↺ Rotate Left / ↻
  Rotate Right (khung xoay theo, tỉ lệ khoá đổi chiều theo), Flip Horizontal, Flip Vertical. ↺ nhóm: cả ảnh, không
  xoay/lật, Free; góc nghiêng giữ — ↺ chỉ hiện khi còn gì để trả. Lật ảnh đang nghiêng đổi dấu góc (chân trời giữ
  thẳng). Bấm Crop là Fit.
- **Straighten**: Angle ±45° (slider + ô số "+2.4°", đọc được cả "2,4" theo locale); khung tự co vào trong ảnh và
  lớn lại khi góc về (khung trước khi nghiêng được nhớ tới khi chính khung đổi); tỉ lệ khoá giữ đúng theo pixel.
  **Straighten Tool**: kéo một đường dọc theo thứ phải nằm ngang (hoặc đứng) trên ảnh, thả tay là ảnh xoay cho đường
  đó thẳng, công cụ tự tắt. **Auto**: pass Level của Upright đọc ảnh gốc (ngoài main), ghi vào góc; nút có vòng
  quay khi đang đọc; không thấy đường nào: "No level line found in this photo."; góc đã đúng: "Already level."; không
  đọc được ảnh: "ShotDex couldn't read this photo. Try again." ↺ nhóm: góc về 0.
- **Upright** Mode ▾: Off · Auto · Level · Vertical · Full (Guided chưa có trên Mac). Đọc ảnh gốc 1024px ngoài main,
  có vòng quay nhỏ; không thấy gì: "No straight lines found in this photo."; Off xoá và dừng lượt đang đọc. Đọc trên
  queue riêng, không giữ luồng của pool; đổi ảnh huỷ lượt đang chạy. Đổi ảnh cũng tắt Straighten Tool.
- **Geometry**: Vertical · Horizontal · Rotate · Aspect · Scale · Offset X · Offset Y + **Constrain Crop**, lấy từ
  `EditorAdjustmentCatalog` như iPhone (cùng thang, Scale ghi 0 = 100%). ↺ nhóm.
- Kit: `CropAspect` thêm `twoThree`, `threeFour`, `fiveFour` và `swapped` — iPhone thấy chúng trong More.
- Chưa có: Upright Guided, Return chốt crop (Return trong ô số đang dùng để áp số), phím tắt R/A cho công cụ.

### 1c. Màu (row 33, 2026-11-17, board `MAC_EditColor`)

`ShotDexMac/Editor/MacEditorColor.swift`. Bốn nhóm của inspector Adjust dùng chung recipe và thang số với iPhone
(`ToneCurveAdjustments`, `PhotoColorRecipe`: mixer, points, grading; số hiện ×100, hue grading theo độ).

- **Tone Curve**: Point · Region; ở Point chọn kênh RGB · đỏ · lục · lam. Khung 130pt: lưới ¼, histogram độ sáng của
  ảnh phía sau, đường chéo gạch, đường cong theo màu kênh. Kéo một điểm (hai đầu chỉ đi dọc, điểm giữa nằm giữa hai
  điểm kề); bấm lên đường cong là thêm điểm ngay chỗ đường đang đi rồi kéo tiếp (không sát điểm có sẵn); nhấp đúp điểm giữa
  hoặc chuột phải › Remove Point là xoá; chuột phải › Reset <kênh> Curve. Dòng gợi ý dưới khung nói cách thêm/xoá. Nhãn
  "In 128 · Out 152" (0–255) cạnh điểm đang cầm. Region: Highlights · Lights · Darks · Shadows ±100, khung vẽ đường
  của bốn vùng (không kéo được). ↺ nhóm: đường thẳng lại, Region về 0.
- **Color Mixer**: Hue · Saturation · Luminance · All; tám dải Red…Magenta, rãnh tô màu theo dải (hue: hai màu kề,
  saturation: xám → màu, luminance: tối → sáng), số "+8" / "−12". Tab có chỉnh mang dấu "•". All: mỗi dải ba hàng
  dưới tên dải, ↺ riêng từng dải đã chỉnh. Black & White bật: nhóm thành **Black & White Mix** (tám dải, độ sáng của
  từng màu khi thành xám — `grayMixer`, như iPhone).
- **Point Color**: ô màu của từng màu đã chọn (tối đa 8; bấm để chọn), **Pick Color** → "Picking…": trên ảnh hiện
  kính lúp 92pt 10×10 điểm ảnh, ô giữa có khung, viền theo màu đang trỏ, mã hex dưới; bấm (hoặc nhấn giữ, rê, thả)
  là thêm màu đó — lấy từ khung đã chỉnh đang hiện (như Lightroom, như iPhone) — và ống hút tự cất; thả ngoài ảnh,
  Esc, hay bật Before and After đều cất ống hút (không rời editor). Đang hút: "Click a color in the photo · Esc to
  cancel"; đủ 8: "8 of 8 colors — remove one to pick another". 🗑 xoá màu đang chọn. Hue · Saturation · Luminance ±100 (rãnh theo màu đã chọn), Range 0–100
  (mặc định 50). Chưa có màu: "Pick a color in the photo to change only that color." ↺ nhóm: xoá hết.
- **Grading**: Shadows · Midtones · Highlights · Global; Hue 0–360° (rãnh cầu vồng), Saturation 0–100 (xám → hue),
  Luminance ±100; Blending (mặc định 50) và Balance ±100 dùng chung bốn vùng. ↺ nhóm.
- Hàng số chung `MacEditorValueRow` (cùng kéo, nhấp đúp, gõ số "−12"/"2,4" như hàng Light; Reset ở chuột phải).
- Chưa có: hình bánh xe màu của Grading (board vẽ slider, đã theo board), điểm đường cong bằng bàn phím, Point Color
  trên ảnh RAW chưa xử lý (lấy màu từ khung hiện — như iPhone).

### 1d. Heal (row 34, 2026-11-17, board `MAC_EditHeal`)

`ShotDexMac/Editor/MacEditorHeal.swift`. Cùng recipe với iPhone (`PhotoHealingSpot`, `PhotoRedEyeSpot`), cùng phần
kit (`suggestedSource`, `HealingSourceFinder`, `RedEyeLocator`, `SpotVisualizer`). Spot nằm trong khung đã cắt.

- **Heal** trong capsule công cụ (Esc về Adjust). Ảnh hiện đã cắt như Adjust.
- Trên ảnh: cọ theo con trỏ (vòng cỡ, vòng gạch là feather, dấu +). **Bấm** = spot tròn, nguồn đặt sẵn bên cạnh;
  **kéo** = spot nét cọ dọc đường kéo (tối đa 128 điểm lấy đều suốt đường); bấm/kéo vòng của spot = chọn và dời; kéo vòng nguồn (gạch) của spot đang chọn =
  dời nguồn. Spot đang chọn: vòng 2pt, nguồn gạch, đường nối, chấm giữa; spot khác: vòng mảnh (khi Show Spot Pins
  bật; tắt thì chỉ spot đang chọn).
- Inspector **Retouch**: Heal · Clone · Red Eye. Heal/Clone: Size ("40 px" — bán kính tính bằng pixel của ảnh gốc
  trên cạnh ngắn của khung đã cắt),
  Feather, Opacity (cho spot mới, và spot đang chọn). Red Eye: Pupil, Darken, **Fix Red Eye** (tìm mọi đồng tử đỏ ngoài
  main; không thấy: "No red eyes found."); bấm ảnh = một mắt ở đồng tử Vision thấy gần đó.
- **Spots** (Red Eye: Eyes): số lượng, **Clear All…** (hỏi "Remove every spot from this photo?", ⌘Z lấy lại), mỗi
  dòng: ảnh nhỏ quanh spot · "Spot 1" · "Heal · circle · top left" · 👁 ẩn/hiện vòng viền của spot trên ảnh
  (spot vẫn sửa ảnh — ảnh xem phải giống ảnh lưu).
  **New Source** (chỗ tốt kế tiếp quanh spot, không quay lại chỗ đã thử; hết chỗ: "No other source found for this
  spot.") · **Delete Spot** (⌫). Trống: dòng hướng dẫn.
- **View**: Visualize Spots (bản đồ cạnh trắng-đen phủ ảnh, làm ngoài main, làm lại sau mỗi lần vẽ) · Threshold
  (chỉ bật khi Visualize) · Show Spot Pins (mặc định bật, ô cam như board).
- Đang chọn một spot thì **bấm chỗ trống chỉ bỏ chọn** (lần bấm sau mới thêm); đầu nhóm Retouch ghi slider đang sửa
  "Spot 3" hay "New spots". Over spot/nguồn con trỏ thành bàn tay, cọ ẩn đi. Delete / ⌘⌫ xoá spot đang chọn. Clear All…
  chỉ xoá danh sách đang hiện (spot, hoặc mắt). Ảnh chưa có để đọc: "The photo is still loading — try again in a
  moment." Fix Red Eye / New Source có trạng thái đang làm ("Finding…").
- Nhóm gập được (mũi tên như board). Chưa có: chọn spot bằng phím Tab, đổi cỡ spot bằng kéo mép vòng.

### 1e. Mask (row 35, 2026-11-17, board `MAC_EditMask`)

`ShotDexMac/Editor/MacEditorMask.swift`. Cùng recipe với iPhone (`PhotoMask`, `PhotoMaskComponent`, `BrushStroke`) và
cùng renderer: vùng tự nhận (Subject, Sky, Object, People, Depth) do `PhotoRenderService` dựng lúc vẽ; lớp đỏ phủ mask
đang chọn là `showsMaskOverlay`/`selectedMaskID` của renderer, chỉ trên khung hiện (khung sạch cho histogram, ống hút).

- **Mask** trong capsule công cụ (Esc về Adjust). Chưa có mask: trên ảnh "Add a mask with + in Masks".
- **Masks**: **+** ▾ Subject · Sky · Background · Object · People | Brush · Linear Gradient · Radial Gradient | Color
  Range · Luminance Range · Depth Range → "Mask n" một vùng, được chọn. Dòng mask: ▸ mở vùng, ảnh nhỏ hình mask
  (`maskThumbnails`, ngoài main), tên, "Sky − Brush" (`MaskAreaSummary`), 👁 bật/tắt mask (lưu, `isVisible`). Dòng vùng:
  dấu +/−/∩, tên, "Subtract · 2 strokes" / "Add · detected". Chuột phải mask: Rename Mask… · Duplicate Mask · Invert
  Mask · Show Overlay · Add/Subtract/Intersect Area ▸ · Reset Mask Adjustments · Delete Mask; chuột phải vùng: Invert
  Area · Delete Area (vùng cuối xoá luôn mask). Dưới danh sách: Add ▾ · Subtract ▾ · Intersect ▾ (thêm vùng vào mask
  đang chọn), Show Overlay (ô cam + ô đỏ) · Invert.
- **Vùng đang chọn** (tên vùng): Brush — Paint · Erase, Size (px ảnh gốc, đường kính), Feather, Flow; kéo trên ảnh là
  vẽ, vòng cọ + lõi gạch theo con trỏ. Linear/Radial — kéo trên ảnh là đặt (linear: đầu→cuối, ba vạch; radial: tâm
  + hai bán kính, vòng trong gạch theo feather), Feather. Luminance — Darkest, Brightest, Smoothness. Color — ô màu,
  bấm ảnh lấy màu, Range. Depth — Far, Near. Object — bấm ảnh chọn vật. Mọi vùng: Opacity. Gợi ý trên ảnh theo loại.
- **<Tên mask> Adjustments**: các slider của `EditorAdjustmentCatalog` scope `.mask` (Light, Color với Hue, Effects,
  Detail với Moiré/Defringe), cùng thang với iPhone; ↺ = Reset Mask Adjustments.
- Một lần kéo (nét cọ, gradient, slider) là một bước Undo; Undo xoá mất vùng/mask đang chọn thì bỏ chọn.
- Vùng tự nhận: dòng vùng ghi "detecting…" → "detected" / "nothing found" (từ `resolvedAutomaticMaskComponentIDs`
  / `emptyAutomaticMaskComponentIDs` của renderer sau mỗi lần vẽ); trên ảnh "Finding it in the photo…" rồi "No sky
  found in this photo" (Subject/People/Object tương tự). Background = Subject **đảo ở vùng** (không đảo cả mask — thêm
  vùng sau không bị đảo theo); `MaskAreaSummary` đọc cả hai dạng là "Background".
- Delete / ⌘⌫ xoá vùng đang chọn (vùng cuối: cả mask). Lớp đỏ tạm tắt khi đang kéo một slider của mask (thấy kết
  quả), bật lại khi thả. Mask đang tắt (👁): Adjustments mờ + "This mask is off…". Đổi ảnh: cọ về Paint.
- Khác board: Brush có thêm Opacity; Adjustments là bộ `.mask` dùng chung với iPhone (có Whites/Blacks/Brilliance/
  Brightness, chưa có Amount, Temp/Tint/Hue chưa có rãnh màu); People không có menu con; nút Add/Subtract/Intersect
  là menu hệ thống không nền.
- Chưa có: People theo từng người/phần (iPhone có), đổi màu overlay, Color/Curve/Point Color riêng của mask
  (`tint`, `curve`, `pointColors`), kéo tay nắm gradient sau khi đặt (kéo lại là đặt lại), vùng mặt (Face Skin…).

### 1f. Markup (row 36, 2026-11-17, board `MAC_EditMarkup`)

`ShotDexMac/Editor/MacEditorMarkup.swift`. Cùng recipe với iPhone (`PhotoOverlay`): renderer nướng lớp vào khung hiện
(không vào khung sạch); đo chữ/hình bằng `TextOverlayLayout` / `ShapeOverlayLayout` của kit nên khung chọn ôm đúng chữ.

- **Markup** trong capsule (Esc về Adjust). Trên ảnh: bấm một lớp = chọn và kéo dời; bấm chỗ trống = bỏ chọn; lớp đang
  chọn có khung trắng, 4 tay nắm góc (kéo = to/nhỏ theo khoảng cách tới tâm), núm xoay trên cuống + nhãn góc "−8°"
  (dương = theo chiều kim đồng hồ, bắt 0° trong ±2°). Delete / ⌘⌫ sau khi bấm lớp trên ảnh = xoá lớp.
- **Layers**: + ▾ (các loại thêm được), dòng: ô ký hiệu (hình mang màu của nó), "Text 1" / "Arrow 1", "Skógafoss ·
  Georgia 60 px" / "Orange · 3 pt" / "300% zoom", 👁; trên cùng là lớp nằm trên. Chuột phải: Bring to Front · Send to
  Back · Delete Layer.
- **Add Layer** (11 nút theo board): Text · Image… (chọn file, lưu vào `OverlayImageStore`) · Signature · Pen ·
  Highlighter (mờ, "comes in a later version" — cần khung vẽ PencilKit) · Rectangle · Oval · Speech Bubble · Arrow (cam)
  · Line · Magnifier.
- **Lớp đang chọn** (tên + 🗑 + ↺ Reset Style giữ chữ/chỗ/góc): Text — ô chữ (Return/rời ô là lưu), Font (System +
  các họ có sẵn trên Mac: Helvetica Neue, Avenir Next, Futura, Georgia…), Weight (Light…Bold), B · I · căn lề (bấm
  xoay vòng), cỡ "60 px" (gõ, hoặc ▲▼ ×1.1); Color: giếng màu + Trắng · Đen · Cam · Đỏ; Opacity; Shadow. Hình: Color,
  Filled (hình đổ được), Line px, Size px, Opacity. Kính lúp: Zoom %, Size, Opacity.
- Thêm Text: ô chữ nhận phím ngay, chữ được chọn sẵn; mỗi lớp một ô chữ (chữ gõ dở không rơi sang lớp khác, rời ô / đổi
  ảnh vẫn giữ). Lớp ẩn được chọn: khung mờ, không kéo được. Delete sau khi chọn lớp trên ảnh hoặc trong danh sách.
  Weight chỉ liệt kê các mức họ chữ có; B mờ khi họ không có Bold (System: Regular/Bold). Núm xoay: nhấp đúp = 0°;
  bắt 0/45/90…° trong ±2°; hàng **Turn** trong cài đặt lớp. Nhóm lớp đang chọn nằm trên lưới Add Layer; dưới lưới:
  "Signature, Pen and Marker come in a later version." Ảnh chèn thu về ≤2048px khi nhập (ImageIO), đúng tỉ lệ thật.
- Khác board: không có New York (mặt chữ hệ thống ẩn, renderer không mở được theo tên — ảnh sẽ âm thầm ra font khác);
  không có U (gạch chân — recipe không có); token `{camera}`… chưa thay trên Mac (chữ hiện nguyên văn).
- Chưa có: Signature/Pen/Highlighter, đổi tên lớp, chỉnh trong ô ảnh (bấm đúp vào chữ), kéo tay nắm bằng phím.

### 1g. Presets and History (row 37, 2026-11-17, board `MAC_EditPresets`)

`ShotDexMac/Editor/MacEditorPresets.swift`: panel 228 ở chỗ sidebar, mở bằng nút sidebar trên toolbar editor (⌥⌘P).
Dùng chung với iPhone: `LookPresetStore` (file Looks/looks.json), `PhotoFilter` theo `FilmLookCategory`,
`EditorSnapshotStore` (bảng `editor_snapshot`), `PhotoEditHistory.timeline/jump`, `EditorAdjustmentSummary.describeChange`.

- **Presets**: + (lưu look của ảnh này thành My Look, hỏi tên gợi ý; ảnh chưa có look: "This photo has no look to save
  yet.") · Search Presets (lọc mọi nhóm, mở hết khi đang tìm) · Amount (độ mạnh look, `filterIntensity`) · nhóm My
  Looks / Basic / Film / B&W có số đếm, gập được. Rê chuột lên một look: ảnh xem thử sau 160 ms, dòng phụ "Previewing
  “Harbour” · 3 of 48"; rời ra là về. Bấm = áp (một bước Undo); look đang áp có ✓. Chuột phải My Look: Apply Look ·
  Rename… · Update with Current Settings · Duplicate · Share… · Export As ▸ ShotDex Look (.shotdexlook) · Lightroom
  Preset (.xmp) · 3D LUT (.cube, mờ — cần render bảng) · Delete Look… (hỏi; ảnh đã sửa bằng nó giữ nguyên). Film: Apply
  · Remove Look.
- **Snapshots**: + (tên "Snapshot n"), dòng tên + ngày; rê = xem thử, bấm = áp; chuột phải Apply / Delete.
- **History**: mọi bước của phiên ảnh này, mới nhất trên cùng ("Filter Classic Chrome", "Exposure +0.65"…, cuối là
  "Opened"); bước đang hiện tô nền, bước sau nó (Redo tới được) mờ; bấm = nhảy tới bước đó. Clear (hỏi; ảnh giữ nguyên,
  Undo không lùi qua được nữa).
- Sau review: Update with Current Settings… hỏi "Replace “X” with this photo's settings?" và ghi **tại chỗ** (look nhập
  từ Lightroom giữ nguồn, cài đặt được đặt tên, file gốc — `LookPresetStore.replace`); Duplicate chép cả look; + từ chối
  tên đã có; câu báo nằm ngay dưới tiêu đề Presets; My Look đang áp có ✓ trắng; Amount mờ khi chưa có look; xem thử
  không bao giờ lọt vào ống hút/Heal/bản đồ bụi (`cleanImage` chỉ từ khung thật) và tắt ngay khi có thay đổi thật,
  Undo, nhảy History, đổi ảnh; nhãn History đầu là "Opened" hoặc "Earlier" (sau Clear, hay khi bước đầu đã rơi khỏi
  100 bước); Clear = "Forget these steps?" · Clear Steps; xoá snapshot có hỏi; Export ghi đè file bằng một bước
  (`replaceItemAt`), lỗi thì báo. Panel gắn sát mép trái (board vẽ panel kính nổi bo 18 — giữ cột gắn, cùng kiểu
  inspector bên phải).
- Demo: looks ghi vào thư mục tạm, xoá mỗi lần mở — không đụng looks thật.
- Chưa có: LUTs (cần kho LUT của iPhone), ảnh nhỏ cho từng look (board có), .cube, kéo look lên ảnh khác.

## 2. Hai kiểu lưu (D16)

| Ảnh | Toolbar | Lưu |
|---|---|---|
| Thư mục, ổ ngoài, NAS | "✓ Edited · Saved" + **Revert to Original…**, **không có Done** | tự lưu sau mỗi thao tác (thả slider, áp crop, thêm mask); recipe vào sidecar (FS-19) |
| Thư viện Photos | **Revert to Original…** + **Done** (⌘↩) | Done ghi bản sửa vào Photos như Save Changes của [FS-03.06](../FS-03-photo-editor/06-saving-recipe-and-live-photo.md) §2 |

- File ảnh gốc ở thư mục **không bao giờ bị ghi**; hash nội dung không đổi khi sửa (FS-19).
- Ảnh thư mục: ◀/Esc rời editor, bản sửa đã nằm sẵn trong sidecar. Undo/Redo sống trong phiên mở ảnh đó.
- Ảnh Photos: Done → bản sửa thấy được trong app Photos và trên iPhone qua iCloud Photos; Revert của Photos vẫn dùng được.
- **Rời ảnh Photos khi chưa Done là tự Done**: ◀, Esc, chọn ảnh khác trên filmstrip, đóng cửa sổ, ⌘Q đều ghi bản
  sửa vào Photos như bấm Done rồi mới rời. Không có hộp "Discard Changes"; bỏ sửa là Revert to Original… hoặc ⌘Z.
- Chưa đổi gì từ lúc mở thì rời không ghi gì. Ghi lỗi (Photos từ chối, hết chỗ) → ở lại editor, bản sửa còn nguyên,
  câu báo lỗi như Done của FS-03.06.
- *Chốt 2026-10-04:* khác hộp hỏi của [FS-03.13a](../FS-03-photo-editor/13a-chrome-and-toolbar.md) trên iOS — *vì trên
  Mac ảnh thư mục tự lưu, hai kiểu ảnh phải rời editor giống nhau.*
- Ảnh trên ổ offline: ⌘E và Edit mờ; inspector ghi "‹nguồn› is offline" (FS-19).
- RAW mà macOS đang chạy chưa đọc được: theo [FS-03.04b](../FS-03-photo-editor/04b-unsupported-raw.md), câu báo ghi
  phiên bản macOS ("macOS 26 can’t read RAW files from the Sony A1 II yet…").

### 2a. Đã dựng (row 40, 2026-11-17, board `MAC_EditPhotos`)

- **Mở được ảnh Photos:** ảnh chỉ có bản trong thư viện Photos (`photo_copies` toàn `photos`) không còn báo "chưa sửa
  được". Editor mở qua `PhotoEditingService` của iPhone: phiên sửa (`requestContentEditingInput`, tải iCloud nếu cần),
  file gốc ra thư mục tạm (RAW nếu có, như iPhone; copy file chạy ngoài main actor), recipe Photos đang giữ
  (adjustment data của ShotDex) là điểm xuất phát. Bản nháp trong `photo_recipes` chỉ thắng khi nó được ghi **sau** lần
  Photos đổi ảnh gần nhất (`modificationDate`) — việc làm ở đây chưa vào Photos (mất điện, Done hỏng lúc đóng cửa sổ):
  mở ra với Done sáng. Nháp cũ hơn thì bỏ, để một bản sửa làm trên iPhone sau đó không bị ghi đè. Fetch `PHAsset` chạy ngoài main actor. Đọc không được → "ShotDex couldn't read this picture from the
  Photos library. If it is in iCloud, check the connection, then open it again."
- **Toolbar:** không có "✓ Edited · Saved" (chưa gì vào Photos trước Done); **Revert to Original…** rồi **Done**
  (viên 36pt chữ đen trên `accentFill` như board, ⌘↩; Export và Sync dùng cùng kiểu nút `MacPushButtonStyle`), sáng
  khi bản sửa khác bản Photos đang giữ (tooltip lúc mờ: "Photos has this edit — nothing new to save"). Đang ghi: vòng
  quay nhỏ trong nút, bề rộng không đổi; ghi xong: "✓ Saved to Photos" 3 s. Photos chỉ đổi khi Done.
  Tiêu đề phụ: `Photos Library · iPhone 16 Pro · 24 mm · 3 of 48` — camera có sẵn của điện thoại ghi tiêu cự tương
  đương thay cho tên lens.
- **Done** = Save Changes của FS-03.06 §2: render full size, `PHContentEditingOutput` + adjustment data = recipe,
  định dạng giữ như gốc (HEIC ra HEIC). Photos nhận rồi thì là xong, kể cả khi mở lại phiên cho lần Done sau không
  được (lần Done sau tự mở). Done thứ hai khi một Done đang ghi thì chờ cái đang ghi, không ghi hai lần.
- **Rời là Done:** ◀ Back, Esc, chọn ảnh khác trên filmstrip (hay ◀ ▶), đóng cửa sổ, ⌘Q đều ghi trước rồi mới rời.
  Không có hộp hỏi. Bấm ảnh khác hay ◀ trong lúc đang ghi: ghi xong (kể cả những chỉnh làm trong lúc ghi — ghi thêm
  lượt nữa) thì tới đích bấm sau cùng; ghi hỏng thì ở lại, kêu bíp và mở luôn lý do.
  ⌘Q ghi mọi editor có bản sửa chưa ghi (chờ tối đa 30 s), rồi hỏi Quit lại từ đầu để các câu hỏi upload / common
  photos vẫn tới lượt; hỏng hay quá 30 s thì hộp hỏi **Stay** / **Quit Anyway** (thoát, bản sửa giữ làm nháp — lần mở
  sau nháp mới hơn Photos nên quay lại với Done sáng).
- **Lỗi:** ở lại editor, bản sửa còn nguyên; toolbar "Not Saved to Photos" (đỏ) — bấm mở lý do ("Photos didn't take
  the edit. Your changes are still here — click Done to try again." / đĩa đầy). ◀ và Esc lúc đó thử ghi lại, không rời.
- **Revert to Original…** trên ảnh Photos đưa bản sửa về gốc như ảnh thư mục; hộp xác nhận nói rõ Done (hay rời editor)
  ghi bản gốc vào Photos, ⌘Z lấy lại tới lúc đó. Revert của chính app Photos vẫn dùng được. "Gốc" là bản Photos đưa
  cho phiên sửa (như iPhone): ảnh đã sửa bằng app Photos thì là bản Photos đã render.
- **Demo:** `-ShotDexSection editPhotos` biến mọi ảnh demo thành ảnh chỉ có trong Photos và mở viewer; Done ghi vào
  bộ nhớ của lần chạy, **không bao giờ gọi PhotoKit**. `-ShotDexDemoDoneFails` làm Done hỏng để thấy câu báo lỗi.
- **Chưa dựng:** Done bấm từ editor không có giới hạn thời gian / nút huỷ (⌘Q có 30 s); chữ token (`{camera}`) trong lớp Text được ghi đúng như thấy trên canvas — Mac chưa điền token
  (iPhone điền trước khi render); đóng cửa sổ khi Done hỏng không có chỗ báo (bản nháp còn trong database, mở lại thấy); Live Photo
  giữ chuyển động theo FS-03.06 §3 chưa kiểm trên Mac; chọn nguồn RAW/JPEG khi ảnh có cặp (dùng nguồn mặc định).

## 3. Sửa nhiều ảnh

- ⌘-nhấp trên filmstrip chọn thêm ảnh: ảnh đang sửa vòng trắng, ảnh chọn thêm vòng amber 2.
- Edit › Sync Edits ▸ Sync Look… / Sync Everything… mở sheet **"Sync to 6 Photos"** (≤ 640×560):
  cột **The Look** (bật sẵn) và cột **This Frame Only** (Crop and Straighten, Masks, Heal and Clone Spots, Red Eye,
  Markup Layers, Upright Guides — tắt sẵn, kèm câu giải thích).
- Từng nhóm có ô tick riêng; popup Sync Preset nhớ bộ tick. Ảnh bị bỏ qua liệt kê kèm lý do ngay trong sheet.
- Apply Previous, Auto Sync, nháp theo ảnh: theo [FS-03.09b](../FS-03-photo-editor/09b-batch-editing-and-reference.md).
- Ô tick theo từng nhóm có trên **mọi thiết bị** (FS-03.09b thêm) — luật NF-05 ở [05](05-platform-and-distribution.md) §5.

### 3a. Đã dựng (row 38, 2026-11-17, board `MAC_EditBatch`)

`ShotDexMac/Editor/MacEditorSync.swift` + filmstrip. Nhóm và cách chép dùng chung với iPhone (`EditorSyncGroup`,
`EditorSyncGroups.apply`, `.look` / `.everything`).

- Filmstrip: **⌘-click** chọn thêm/bỏ một ảnh để đồng bộ, **⇧-click** chọn một dải (từ ảnh chọn trước); click thường
  vẫn mở ảnh. Ảnh đang sửa vòng trắng 3, ảnh chọn vòng cam, ảnh khác tối đi. Cuối filmstrip "5 selected / of 226",
  **Clear** và **Sync 4…** (⇧⌘S); dòng phụ toolbar "5 of 226 selected · máy · ống".
- Sheet **"Sync to 4 Photos"** (640): "From DSC04111.HEIC to the other selected photos"; popup Sync Look / Sync
  Everything / Custom (khi tick tay); cột The Look (15 nhóm) và This Frame Only (6 nhóm + câu giải thích), mỗi dòng ô
  tick + chi tiết của ảnh này ("3 sliders", "off", "3:2 · +2.4°", số mask…); ảnh không ghi được nêu ngay trong sheet
  với lý do (ảnh Photos, file không tới được, macOS không đọc được RAW — "Convert it to DNG…"), đọc ngoài main lúc
  mở sheet ("Checking…"); Check All · Check None · Cancel (Esc) · **Sync N Photos** (Return; mờ khi đang kiểm, không
  còn ảnh hay không tick gì). Bộ tick nhớ cho lần sau.
- Đồng bộ: ghi lần lượt ngoài main (`PhotoRecipeStore` + sidecar), mỗi ảnh nhận một bước Undo của chính nó (mở ảnh
  đó, ⌘Z là về như trước); xong: "Synced to 4 photos." (có lỗi thì nói số ảnh không lưu được) và huy hiệu đã sửa.
- Sau review: ghi Sync xếp sau autosave đang chờ; trong lúc ghi filmstrip khoá, cuối strip "Syncing 2 of 4…"; xong thì
  bỏ chọn và báo "Synced to 4 photos. ⌘Z in each photo undoes it." (tự ẩn sau 8 s); ảnh có recipe đọc lỗi bị bỏ qua
  (không coi là ảnh trống — sẽ xoá các nhóm khác của nó) và mang dấu ⚠; sheet nói "Replaces the checked groups on N
  photos… ⌘Z in each photo undoes it", lý do khi nút Sync mờ, "off" khi nhóm đó không chép gì (cùng phép thử với lúc
  chép), số ít/số nhiều; Esc bỏ chọn trước khi rời editor; tooltip ô ảnh nói ⌘/⇧-click; VoiceOver: "Add to Sync".
- Chưa có: Apply Previous, Auto Sync, Edit › Sync Edits trong menu, popup Sync Preset có tên.

## 4. Sheet Save and Export (D16, D17)

Mở bằng nút Export trên toolbar editor hoặc File › Export ▸ Export N Photos… ⇧⌘E. Sheet ≤ **640×560**, thân cuộn.

| Khối | Ô |
|---|---|
| Đầu | "Save and Export", dòng "DSCF4127.RAF · Fujifilm X-T5 · in “2026 Japan”", popup Preset |
| Output | segmented **Save as Copy · Export Files** — **không có "Save Edit"** (D16) |
| Destination | Save To (folder gần đây, connection server đã lưu, Choose…) · Date Folders · If a File Exists (Keep Both · Replace · Skip) |
| File Name | mẫu tên với token (Original Name, Date, Time, Camera, Lens, Number), dòng ví dụ "2026-09-28_Kyoto_001.jpg" |
| Photo | Export As · Version · Size (danh sách Resize preset) · Format · **Color Space** · Quality |
| Watermark | Add Watermark · preset · Text · Placement · Size · Opacity · ảnh xem trước |
| Metadata | ba mức của [FS-08.06](../FS-08-settings/06-share-metadata-privacy.md) |
| Chân | **Save Preset…** sát trái · Cancel · **Export**; dòng "1 photo · about 1.1 MB · 412 GB free on “T7”" |

- **Save as Copy**: ảnh thư mục, ổ, NAS → file **`‹tên› (edited).jpg`** cạnh ảnh gốc (đuôi theo Format); ảnh Photos →
  asset mới trong Photos (như Save Copy của iOS).
- **Export Files**: ghi vào folder đã chọn. Câu dưới segmented: "Edits already save on their own. … ShotDex never
  edits the original."
- **Color Space** (D17): popup **Original · sRGB · Display P3 · Adobe RGB**, mặc định **Original** ("keeps the photo’s
  profile"). Theo NF-05 việc này cũng làm được trên iPhone/iPad: luật "không có picker color space" của
  [FS-03.04](../FS-03-photo-editor/04-raw-and-render-graph.md) bỏ ở mọi thiết bị.
- Settings › Editing ghi: "Exports keep the original’s color profile unless you pick sRGB, Display P3 or Adobe RGB
  in the Export sheet."
- Chạy, Cancel, trùng tên, đích đầy, đích mất kết nối: luật của [FS-03.07b](../FS-03-photo-editor/07b-export-to-files.md)
  và [FS-03.07c](../FS-03-photo-editor/07c-export-acceptance-criteria.md). Tiến độ nằm trong Activity, không modal.

### 4a. Đã dựng (row 39, 2026-11-17, board `MAC_Export`)

- **Lối vào:** nút **Save and Export** (`square.and.arrow.up`) trên toolbar editor, giữa Fit và Inspector; **⇧⌘E**. Sheet
  640×560, tối như editor; thân cuộn, hai cột 286pt (trái Destination + Photo, phải File Name + Watermark).
- **Đầu:** "Save and Export", dòng `tên · máy · in “nguồn”`, popup **Preset** (Custom khi lựa chọn không khớp preset nào).
  Segmented **Save as Copy · Export Files** (`MacEditorSegments`), câu giải thích đổi theo lựa chọn — Save as Copy ghi
  luôn tên sẽ ra (`DSCF4127 (edited).jpg`).
- **Save as Copy:** Destination chỉ một dòng "Beside the original"; không có File Name, Export As, Version (bản copy
  luôn là bản đã sửa, đúng tên `(edited)`). Photo (Size · Format · Color Space · Quality · Metadata) và Watermark vẫn áp dụng. Ghi bằng
  `OutputNaming.editedCopy` cạnh file gốc (` (2)` khi trùng). Ảnh chỉ có trong Photos chưa mở được trong editor, nên
  nhánh "asset mới trong Photos" chưa có (row 40).
- **Export Files:** Save To (≤ 5 folder gần đây, `ExportFolderStore`), dòng Folder (`Ổ › Folder`, ổ trong máy cũng gọi
  bằng tên ổ, ví dụ `Macintosh HD › Exports`) + **Choose…** (trình chọn folder của hệ thống), Date Folders (ví dụ
  `2026/2026-09-28` bên cạnh), If a File Exists. Photo thêm **Export As** (Unmodified Original ẩn các hàng render, ghi
  câu "Original files are copied as they are…"). File Name: popup ba mẫu dựng sẵn + Custom, ô mẫu (token dạng
  `{date}`), 8 chip `FileNameChip.all` xếp theo dòng, dòng "Example:". Tên, trùng tên, Date Folders đi qua
  `FileExportPlan.make` như iPhone; Replace hỏi một lần ("Replace 1 file in “Exports”?") trước byte đầu, và thay file
  cũ bằng `replaceItemAt` (file cũ chỉ mất khi file mới đã đủ). **Ảnh gốc không bao giờ bị ghi đè:** xuất vào chính
  folder của ảnh mà tên trùng tên gốc thì luôn đánh số (Keep Both), so theo định danh file (symlink, hai đường mount
  cùng một folder vẫn nhận ra), và lần ghi nào trỏ đúng vào file gốc đều bị chặn. Chân sheet nói trước: Skip sẽ bỏ ảnh
  này, hay tên sẽ được đánh số để giữ tên gốc.
- **Bookmark trên Mac:** `ExportFolderStore` tạo và mở bookmark `.withSecurityScope` (sandbox); iOS giữ như cũ.
- **Watermark:** Add Watermark, **Edit…** (popover: một ô chữ, Save tạo hoặc sửa preset chữ trong
  `SignaturePresetStore`; token `{camera}`… được điền theo ảnh), Text (preset), Placement (9 vị trí), Size, Opacity
  (`WatermarkPlacement`), thẻ xem trước: ảnh nhỏ có dấu + dòng `2048 × 1365 px · JPEG 80% · about 1.1 MB`. Bật Add
  Watermark mà chưa có chữ thì Export mờ.
- **Chân:** Save Preset… (đặt tên; trùng tên thì ghi đè), dòng `1 photo · about 1.1 MB · 412 GB free on “T7”`
  (ổ rút: "Connect “T7” or choose another folder."), Cancel, **Export** / **Save Copy** (accent). Export mờ thì chân
  sheet nói vì sao bằng chữ đỏ: chưa có folder, ổ rút, folder mất, mẫu tên rỗng, watermark chưa có chữ hay không còn chữ
  nào cho ảnh này, một lần export trước còn đang ghi.
- **Chạy:** sheet đóng ngay; render (`render` → `resize` → dấu → Color Space → `write`) chạy ngoài main actor trên một
  renderer riêng (preview của editor không phải xếp hàng sau nó), ghi tên tạm `.‹tên›.‹số›.shotdex-part` rồi đổi tên;
  Date Folders chỉ được tạo lúc ghi. Toolbar (gọn, để "Edited · Saved" và Revert không bị đẩy vào menu tràn): "Saving…" + **Stop** (huỷ,
  xoá file tạm, ghi "Stopped — nothing was written."); xong thì "✓ Saved" + nút folder (Show in Finder; tên file ở
  tooltip, tự ẩn sau 20 s), hoặc **Not Written** / **Not Exported** (đỏ) — bấm vào mở popover lý do bằng lời có việc
  cần làm (Skip, ổ đầy, folder chỉ đọc, ổ rút, không render được, tên là ảnh gốc) — ở lại tới khi bấm ✕. Ghi chú thuộc về lần
  export, đổi ảnh không làm mất. Activity › Background: "Exporting DSCF4127.RAF" khi đang ghi; lỗi thì thành "Couldn't
  export DSCF4127.RAF" kèm lý do, ở lại tới lần export sau — đóng editor giữa chừng vẫn thấy.
- **Nhớ:** lựa chọn của sheet (`mac.export.choices`) và preset (`mac.export.presets`) trong UserDefaults; Metadata luôn
  bắt đầu từ mức của Settings, Version luôn Edited (như iPhone).
- **Chưa dựng:** watchdog cho ổ rút giữa lúc ghi (iPhone bỏ sau 2 s; Mac chờ hệ thống báo lỗi — Stop vẫn bấm được),
  xuất nhiều ảnh (sheet là của ảnh đang mở; File › Export N Photos… từ lưới chưa có), connection server
  trong Save To, Save as Copy cho ảnh Photos, editor watermark đầy đủ (logo, nhiều lớp — Edit… chỉ sửa chữ), chip token
  nằm trong ô như board (ô là chữ `{date}`), lựa chọn Live Photo Video.

## 5. File sinh ra: chỗ và tên

| Lệnh | Ghi vào | Tên |
|---|---|---|
| Save as Copy | cạnh ảnh gốc (ảnh Photos: asset mới trong Photos) | `‹tên› (edited).‹đuôi›` |
| Combine Photos | cạnh **khung đầu** của bộ (Save To: Same Folder as Frames) | `‹tên khung đầu› (‹chế độ›).jpg`, ví dụ `DSC09812 (Panorama).jpg` |
| Resize | Save To trong inspector, mặc định Pictures › ShotDex Resized; không bao giờ thư mục nguồn | tên gốc |
| Export Files | folder đã chọn trong sheet | mẫu tên của sheet |

- Trùng tên ở đích: thêm **" (2)"**, " (3)"… trước đuôi (`DSCF4127 (edited) (2).jpg`), trừ khi sheet đặt Replace / Skip.
