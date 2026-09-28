# FS-04.02 — Grading và Tone Curve

`FS-04.02` · `Features/Editing/EditorColorPanel.swift` · `EditorCurveGraph` · `EditorCurvePanel`
· `Domain/Editing/ToneCurveMath.swift` · cập nhật 2026-09-29

**Một câu:** bốn vùng sáng × ba slider, và một đồ thị curve **trong panel**, ảnh không bị che.

## 1. Quy tắc

- **Không dùng bánh xe màu trong panel** — panel cao cố định 264pt không đủ chỗ, và cả panel nên nói cùng
  một ngôn ngữ: dòng slider.
- Đồ thị curve **nằm trong panel, ở mọi layout** ([FS-03.13b §2](../FS-03-photo-editor/13b-edit-and-transform.md#2-curve-trong-panel)),
  không phải một màn riêng và không đè lên ảnh — ảnh luôn thấy trọn lúc kéo.
- Curve dựng bảng tra bằng nội suy **giữ tính đơn điệu**, nên đường không tự đảo chiều giữa hai điểm.
- Một cú kéo = **một** bước hoàn tác.

## 2. Grading

Dải chọn vùng **chia đều, có icon** (kiểu chip chung của [FS-03.12](../FS-03-photo-editor/12-phone-panel-grid.md#4-chip-và-dải-chọn)):
**Shadows · Midtones · Highlights · Global**.

Mỗi vùng ba dòng:

| Dòng | Dải | Rãnh |
|---|---|---|
| Hue | 0…360°, **không có mốc 0** | dải màu trọn phổ |
| Saturation | 0…100 | xám → màu của vùng |
| Luminance | ±100 | dải trung tính |

Reset đưa hue và saturation về 0. Dưới đường kẻ là **Blending** (0…100, mặc định 50) và **Balance** (±100,
dải xám tối → trắng, đọc là "nghiêng về shadow / nghiêng về highlight").

Bánh xe màu vẫn dùng ở ô chọn màu của overlay — không xoá.

**Cách grading áp vào ảnh**: độ sáng tính theo chuẩn Rec.709; **Blending quyết định các vùng chồng lên nhau
bao nhiêu**, còn **Balance dời mốc chia shadow và highlight**. Mỗi vùng áp hai thứ: một lớp màu **trung tính
về độ sáng** (chỉ thêm sắc, không làm sáng khung hình) và một phép nâng/hạ độ sáng **tự giới hạn** ở hai
đầu. Thứ tự: shadows → midtones → highlights → global.

## 3. Tone Curve — model và render

- Bốn chuỗi điểm: RGB chung và ba kênh riêng. Khối curve **chỉ được ghi vào công thức khi khác đường thẳng**.
- Bảng tra dựng 256 mức, có test.
- Curve chạy **ngay sau khối màu**, trong không gian sRGB có kẹp giá trị (cùng lý do với bảng màu film:
  đường cong định nghĩa trên giá trị đã mã hoá gamma). Đường RGB chung được **nướng vào từng kênh** thay vì
  chạy thành một lượt riêng.

## 4. Đồ thị

iPhone: hàng **Curve** (ngay sau Light) → **Edit Curve** mở công cụ con ✕ · Curve · ✓ (FS-03.13b §2). Sidebar
iPad / Duo: đồ thị vuông dưới mục Curve, trong khối Light.

| Thành phần | Chi tiết |
|---|---|
| Khung | vuông; **220×220** trong công cụ Curve của iPhone, rộng bằng sidebar trên màn rộng |
| Nền | lớp tối 0,18 + **histogram của kênh đang chỉnh** vẽ mờ phía sau |
| Lớp vẽ | lưới chia ba + đường chéo gốc + đường cong + điểm kéo 13pt (vùng chạm 26pt) |

- Cử chỉ: kéo **từ một điểm** để dời (điểm đầu và cuối trượt dọc mép, điểm giữa bị kẹp giữa hai hàng xóm) ·
  **chạm vào vùng trống = thêm điểm ngay trên đường**, ở mức vào chỗ chạm, nên đường chưa đổi cho tới khi kéo ·
  **chạm đôi lên điểm = xoá**. Kéo từ vùng trống không làm gì: trong sidebar cú kéo đó là cuộn danh sách.
- Thẻ histogram nổi thu lại khi Curve mở — đồ thị đã có histogram.

## 5. Panel Curve

iPhone: đồ thị bên trái, cột phải rộng 120 gồm chip kênh **RGB / Red / Green / Blue** (chia dọc, cao 30, tên giữa chip,
chấm màu 10pt của kênh **ghim mép trái**), chip **Reset** cho kênh đang chọn và hint *"Tap the line to add a point.
Drag to move it, double-tap to remove it."*. Sidebar: chip kênh ngang, Reset, hint, hàng preset.

**Preset** (có test): Linear · Soft S · Strong S · Brighten · Darken · Fade · Matte. Áp vào kênh đang chọn
là **một** bước hoàn tác; chip sáng lên khi các điểm của kênh trùng preset. iPhone: trong ⋯ → **Preset Shapes**.

**Region** (parametric, FS-03.15a §1): sidebar có chip Point · Region; iPhone chọn ở ⋯ → **Curve Type**, và
vùng thông số đổi thành bảy slider có chip Point · Region ở đầu để quay lại.

Menu ⋯ khi đang ở Curve có thêm **Reset Curve**. Show/Hide Graph đã bỏ: đồ thị không còn đè lên ảnh.

## 6. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
