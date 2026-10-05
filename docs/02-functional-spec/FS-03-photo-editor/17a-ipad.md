# FS-03.17a — Editor iPad 13" (ngang và dọc)

`FS-03.17a` · tier D · `Features/Editing/` · cập nhật 2026-10-01

**Một câu:** iPad đặt ảnh bên trái và cột 280 cố định bên phải ở cả hai chiều xoay; chỉ vùng ảnh đổi
(1096×1032 ngang, 752×1376 dọc). Luật chung: [17](17-wide-design.md) §3.

## 1. Khung (mọi bảng `IP*`, `IPP*`)

| Vùng | Ngang 1376×1032 | Dọc 1032×1376 |
|---|---|---|
| Vùng ảnh | x0–1096, cao hết màn | x0–752, cao hết màn |
| Cột | x1096–1376, 280, nền panel đặc, không đường kẻ ở mép | x752–1032, như ngang |
| Băng trái | Back x16 · Undo x62 · Redo x101, y16, đĩa 34 | như ngang |
| Băng phải | kết thúc x1080: History 837 · Reset All 876 · Revert 915 · Recall 954 · Compare 1000 · Save 1046 | kết thúc 16pt trước cột, cùng thứ tự |
| Histogram | góc trên cột: 256×120, bo 12, nền trắng 5%, hiện cả trong công cụ | như ngang |
| Danh sách | từ dưới histogram tới trên dải công cụ, mờ dần 26pt ở đáy | như ngang |
| Dải công cụ | chân cột, cao 60 + 12; 6 ô | như ngang |
| Trong công cụ | dải thành ✕ 38 · tên · ✓ 44×38 trắng | như ngang |

- Con trỏ trên một đĩa băng: vòng sáng 40 + tooltip tên (bảng IP1 vẽ trên History).
- Slider trong cột xếp chồng: nhãn và số một dòng, track dưới, hàng cao 50. Temp/Tint/Vibrance/Saturation track màu.

## 2. Theo màn

- **Edit** (IP1/IPP1): danh sách phẳng LIGHT · CURVE · COLOR · MIX · POINT · GRADE · EFFECTS · … như iPhone, đủ
  slider của code (bảng chỉ vẽ mẫu — D17). Không ↺ từng nhóm, không chấm "đã chỉnh".
- **Curve** (IP8/IPP8): nhóm trong Edit, không phải công cụ. Point | Region · đồ thị 248×248 · kênh 2×2 dưới đồ thị
  · Reset · gợi ý. Histogram kênh đang chọn mờ sau lưới.
- **Presets** (IP2/IPP4): chip Presets · My Looks · LUTs, Amount, lưới 2 cột ô 124×89. **My Looks** (IP9/IPP9): Save
  Current và Import XMP Preset hai ô đầu, look nhập ghi "Imported", gợi ý "Hold a look for Rename · Share ·
  Export As · Delete."
- **Transform** (IP3/IPP5): khung cắt, thước và Rotate/Flip trên ảnh ([17](17-wide-design.md) §5). Cột: CROP (lưới tỉ
  lệ 3 cột theo danh sách của code, D16) · Reset · STRAIGHTEN (Straighten Tool · Auto) · UPRIGHT (6 chip 3+3) · GEOMETRY.
- **Mask** (IP4/IPP2): thanh cọ dọc x24 trên ảnh — Vẽ · Xoá · Size (slider dọc) · Feather · Flow · Mask Overlay.
  Cột: MASKS + New Mask + Invert · danh sách mask có thành phần +/− và mắt ẩn · ADD TO MASK · lưới 14 loại · slider.
- **Mask chưa có gì** (IP10/IPP10): "No masks yet — choose an area to adjust." + lưới 3 cột 14 loại vùng; Face
  Skin · Eyes · Lips mờ khi ảnh không có mặt. Chooser nằm trong cột, không còn sheet.
- **Heal** (IP5/IPP6): thanh nổi Heal · Clone · Red Eye · Size · Feather · Opacity · Visualize Spots. Cột: SPOTS · n
  + Clear All (giữ đỏ, có xác nhận) · danh sách điểm có mắt ẩn · SELECTED SPOT (New Source · Delete) · VIEW.
- **Markup** (IP6/IPP7): khung chọn lớp ([17](17-wide-design.md) §5). Cột: LAYERS + New Layer · danh sách lớp · thuộc
  tính lớp (hàng B · I · U | căn lề là một nút xoay vòng | Size px) · ADD A LAYER lưới 3 cột.
- **Markup chưa có lớp** (IP11/IPP11): "No layers yet." + lưới 3 cột 11 loại lớp.
- **Nhiều ảnh** (IP7/IPP3): filmstrip 96 dưới vùng ảnh, ô 72 bo 8, ảnh đang mở vòng trắng 2pt, "2 / 7", ô Sync 72 —
  chạm mở menu Sync Look · Sync Everything · Apply Previous · Auto Sync ngay trên nút.
- **Save** (IP12/IPP12): sheet 540 giữa màn, nền tối mờ 55% sau ([17](17-wide-design.md) §3).

⚠️ CẦN QUYẾT: **ô look có ảnh thật** (IP9): bảng vẽ thumbnail ảnh đang sửa với từng look; code vẽ glyph. Render 49 look
× ảnh 124×89 mỗi lần mở Presets tốn máy (NF-01). Phương án: (a) thumbnail render nền, cache theo ảnh; (b) giữ glyph
và sửa bảng.

⚠️ CẦN QUYẾT: **Add to Mask** (IP4) vẽ Add · Subtract, code có thêm Intersect. Bỏ Intersect là mất chức năng —
đề xuất giữ ba chip, sửa bảng.

⚠️ CẦN QUYẾT: **menu Sync** (IP7) vẽ menu tự vẽ 280 rộng có dòng phụ. Đề xuất dùng menu hệ thống có dòng phụ (giống
iPhone PH17); `design-parity` so menu theo nhãn, không theo khung.

## 3. Tiêu chí nghiệm thu

Thiết bị: iPad Pro 13" M5, iOS 26.5; AC-18…AC-21 chạy thêm trên 18.6. Script: `ShotDexUITests/scripts/fs0317-ipad-landscape.json`
và `fs0317-ipad-portrait.json` (⚠️ chưa có). Ảnh test 3:2 không có mặt người.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-18 | ngang, mở ảnh | vào editor | `design-parity` PASS `IP1_Edit` | ⚠️ chưa có |
| AC-19 | ngang | chạm Presets; chọn My Looks | PASS `IP2_Presets`, `IP9_MyLooks` | ⚠️ chưa có |
| AC-20 | ngang | chạm Transform; vuốt thước +2,4° | PASS `IP3_Transform` (lưới 8×8 khi đang xoay) | ⚠️ chưa có |
| AC-21 | ngang, chưa có mask | chạm Mask | PASS `IP10_NewMask` | ⚠️ chưa có |
| AC-22 | ngang | chọn Brush, vẽ một nét | PASS `IP4_Mask` | ⚠️ chưa có |
| AC-23 | ngang, 3 điểm sửa | chạm Heal | PASS `IP5_Heal` | ⚠️ chưa có |
| AC-24 | ngang, chưa có lớp | chạm Markup | PASS `IP11_NewLayer` | ⚠️ chưa có |
| AC-25 | ngang | thêm Text, xoay −8° | PASS `IP6_Markup` | ⚠️ chưa có |
| AC-26 | ngang, 7 ảnh | mở editor từ chọn nhiều, chạm Sync | PASS `IP7_Batch` | ⚠️ chưa có |
| AC-27 | ngang | Edit, cuộn tới CURVE | PASS `IP8_Curve` | ⚠️ chưa có |
| AC-28 | ngang | chạm Save | PASS `IP12_Save` | ⚠️ chưa có |
| AC-29 | dọc | lặp AC-18…AC-28 | PASS `IPP1`…`IPP12` (12 bảng) | ⚠️ chưa có |
| AC-30 | ngang, trong Mask | xoay iPad sang dọc | vẫn trong Mask, mask và nét còn nguyên, PASS `IPP2_Mask` | ⚠️ chưa có |
| AC-31 | iOS 18.6, ngang và dọc | lặp AC-18, AC-22, AC-28 | PASS như 26.5 | ⚠️ chưa có |
| AC-32 | ngang, Edit | chạm một điểm cách mép ngoài đĩa History 4pt (ngoài phần vẽ 34, trong vùng 44) | History mở; dump: mọi đĩa icon-only có nhãn khác rỗng | ⚠️ chưa có |

**Chưa chứng minh được:** AC-18…AC-32 — chưa có code.
