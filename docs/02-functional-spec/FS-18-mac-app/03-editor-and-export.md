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
