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

## 3. Sửa nhiều ảnh

- ⌘-nhấp trên filmstrip chọn thêm ảnh: ảnh đang sửa vòng trắng, ảnh chọn thêm vòng amber 2.
- Edit › Sync Edits ▸ Sync Look… / Sync Everything… mở sheet **"Sync to 6 Photos"** (≤ 640×560):
  cột **The Look** (bật sẵn) và cột **This Frame Only** (Crop and Straighten, Masks, Heal and Clone Spots, Red Eye,
  Markup Layers, Upright Guides — tắt sẵn, kèm câu giải thích).
- Từng nhóm có ô tick riêng; popup Sync Preset nhớ bộ tick. Ảnh bị bỏ qua liệt kê kèm lý do ngay trong sheet.
- Apply Previous, Auto Sync, nháp theo ảnh: theo [FS-03.09b](../FS-03-photo-editor/09b-batch-editing-and-reference.md).
- Ô tick theo từng nhóm có trên **mọi thiết bị** (FS-03.09b thêm) — luật NF-05 ở [05](05-platform-and-distribution.md) §5.

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

## 5. File sinh ra: chỗ và tên

| Lệnh | Ghi vào | Tên |
|---|---|---|
| Save as Copy | cạnh ảnh gốc (ảnh Photos: asset mới trong Photos) | `‹tên› (edited).‹đuôi›` |
| Combine Photos | cạnh **khung đầu** của bộ (Save To: Same Folder as Frames) | `‹tên khung đầu› (‹chế độ›).jpg`, ví dụ `DSC09812 (Panorama).jpg` |
| Resize | Save To trong inspector, mặc định Pictures › ShotDex Resized; không bao giờ thư mục nguồn | tên gốc |
| Export Files | folder đã chọn trong sheet | mẫu tên của sheet |

- Trùng tên ở đích: thêm **" (2)"**, " (3)"… trước đuôi (`DSCF4127 (edited) (2).jpg`), trừ khi sheet đặt Replace / Skip.
