# FS-04.02 — Grading và Tone Curve

`FS-04.02` · `Features/Editing/EditorColorPanel.swift` · `EditorCurveOverlay` · `EditorCurvePanel`
· `Domain/Editing/ToneCurveMath.swift` · cập nhật 2026-09-24

**Một câu:** bốn vùng sáng × ba slider, và một đồ thị curve nằm **đè lên chính tấm ảnh nó đang sửa**.

## 1. Quy tắc

- **Không dùng bánh xe màu trong panel** — panel cao cố định 264pt không đủ chỗ, và cả panel nên nói cùng
  một ngôn ngữ: dòng slider.
- Đồ thị curve **đè lên ảnh**, không phải một màn riêng — bản chỉnh mù không thấy ảnh đã bị xoá.
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

## 4. Đồ thị trên ảnh

Chọn chip **Curve** (ngay sau Light) → đồ thị vẽ lên ảnh, ở lớp **không bị phóng theo ảnh**.

| Thành phần | Chi tiết |
|---|---|
| Khung | vuông, căn giữa ảnh, cạnh = min(rộng, cao **của khung dựng**) − 2×16, tối thiểu 120, kẹp trong khung dựng |
| Nền | lớp tối 0,18 + **histogram của kênh đang chỉnh** vẽ mờ phía sau |
| Lớp vẽ | lưới chia ba + đường chéo gốc + đường cong + điểm kéo 13pt (vùng chạm 26pt) |

- **Tính theo khung dựng, không theo ảnh**: ảnh ngang được khung rộng bằng màn hình, tràn lên vùng đen, thay
  vì bị bóp theo chiều cao ảnh.
- Cử chỉ: kéo điểm để dời (điểm đầu và cuối trượt dọc mép, điểm giữa bị kẹp giữa hai hàng xóm) · **kéo trên
  vùng trống = thêm điểm** · **chạm đôi lên điểm = xoá**.
- **Mờ đi khi đang giữ tay** (mô hình Snapseed): ngón chạm thì lớp tối, lưới, đường chéo, histogram và các
  điểm khác mờ về **0,10**, còn đường cong và điểm đang kéo giữ **0,45**, để thấy ảnh đổi live phía sau;
  nhả tay thì trở lại bình thường.
- Khi đồ thị đang hiện, **mọi cử chỉ mức ảnh bị tắt** (như khi cắt ảnh) — nếu không, cử chỉ của khung dựng
  nuốt mất cú kéo trên đồ thị. Thẻ histogram nổi cũng thu lại.

## 5. Panel Curve

Dải chọn kênh **RGB / Red / Green / Blue**, mỗi chip một chấm màu của kênh — cộng nút Reset cho kênh đang
chọn và một dòng nhắc (hàng hint). Kênh đang
chọn dùng chung giữa panel và đồ thị.

**Preset** (có test): Linear · Soft S · Strong S · Brighten · Darken · Fade · Matte. Áp vào kênh đang chọn
là **một** bước hoàn tác; chip sáng lên khi các điểm của kênh trùng preset.

Menu ⋯ khi đang ở Curve có thêm **Show/Hide Graph** (chỉ trong phiên; ẩn thì ảnh trở lại trần, cử chỉ ảnh
quay về, panel hiện nút bật lại) và **Reset Curve**.

## 6. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
