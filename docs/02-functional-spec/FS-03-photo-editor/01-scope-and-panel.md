# FS-03.01 — Phạm vi và bố cục panel

`FS-03.01` · `Features/Editing/PhotoEditorScreen.swift` · `Domain/Editing/EditorLayoutMetrics.swift`
· cập nhật 2026-09-22

**Một câu:** editor toàn màn nền đen, một hàng lệnh nổi ngang tai thỏ, và một panel cao **đúng 246pt ở mọi tab**.

Các thông số chỉnh và Crop: [FS-03.01b](01b-adjustments-and-crop.md).

## 1. Quy tắc

- Chỉ sửa được **ảnh**; video không hiện nút Edit.
- **Ảnh không bao giờ bị panel đè.** Thứ tự dọc: băng trên → ảnh (vừa khung) → panel.
- **Không có kính mờ hay khối nổi trên ảnh** — ngoại lệ duy nhất là thẻ histogram khi bung to.
- **Panel cao đúng 246pt ở mọi tab** — dải chọn đối tượng ăn **vào trong** vùng thông số, không cộng thêm.
- **Một kiểu slider dùng chung cho cả editor** — sửa kiểu dáng chỉ sửa một chỗ.

## 2. Ba tầng theo chiều dọc

| Tầng | Chiều cao | Nội dung |
|---|---|---|
| Băng trên | **48pt hoặc bằng vùng an toàn trên**, lấy cái lớn hơn | hàng lệnh nổi |
| Ảnh | phần còn lại, vừa khung | khung dựng |
| Panel | **246** = 167 vùng thông số + 54 dải nhóm + 25 vùng an toàn dưới | tấm đặc, có một nét mảnh ở mép trên |

48pt chỉ là **sàn thiết kế**: băng nở tới hết vùng an toàn (~59pt trên máy có tai thỏ) để một tấm ảnh dọc
bắt đầu **dưới đáy tai thỏ**, không bị nó cắt mép. Hàng nút vẫn cách mép trên 11pt nên luôn ngang tai thỏ
dù băng cao hơn.

## 3. Hàng lệnh nổi

Cao 37pt, nút tròn **34pt** (đĩa gần đen mờ, biểu tượng trắng), cách mép màn **20pt** — đủ để nút ngoài cùng
không bị **góc bo của màn** cắt. Tai thỏ chia đôi băng:

- **Cụm trái**: hoàn tác · làm lại · **giữ để xem bản gốc** (đang giữ thì đĩa chuyển màu accent, biểu tượng đen).
- **Cụm phải**: **histogram thu nhỏ** (nở từ sát mép phải tai thỏ ra tới nút ⋯) rồi nút **⋯**.

**Menu ⋯** gom mọi lệnh không đủ chỗ cạnh tai thỏ, và **đổi theo tab đang mở**:

| Phần | Mục |
|---|---|
| Luôn có | Reset All (mờ khi chưa sửa gì) · History · gọi lại bản đã lưu / đổi nguồn (khi có) · **Auto Enhance** · **Revert to Original** |
| Khi ở Crop | Rotate 90° · Flip Horizontal |
| Khi đang sửa mask | hiện/ẩn lớp phủ đỏ · đảo vùng chọn |

**Revert to Original ≠ Reset All**: Reset All chỉ hoàn tác **phiên đang mở**, còn Revert bảo hệ thống **vứt
mọi bản sửa đã lưu lên ảnh**, kể cả bản sửa trong app Photos. Nên nó có hộp xác nhận và **đóng luôn editor**
— thứ đang sửa không còn nữa. Chỉ hiện khi ảnh cho phép.

## 4. Histogram

- Thu gọn (mặc định): một dải nhỏ cao 34pt vẽ độ sáng cộng ba đường màu, cập nhật theo thời gian thực.
- Bấm vào thì bung thành **thẻ nổi trên ảnh** 152×86: tiêu đề, chấm báo cháy sáng, nút đóng, đồ thị ba kênh
  và dải cháy, thang 0 / giữa / 255.
- **Kéo được tới bốn góc** và nhớ góc đã chọn; chạm vào thẻ hoặc nút đóng thì thu lại. Hai trạng thái nối
  nhau bằng một hoạt ảnh liền mạch.
- Khi thẻ mở, chỗ của dải nhỏ **giữ nguyên kích thước nhưng để trống** nên nút ⋯ **không dịch**.
- Histogram **luôn mô tả cả bức ảnh**.

## 5. Dải nhóm

54pt: `[Back 38] [bánh xe nhóm] [Save 42]`.

- **Save** là dấu tick 42×42 **tròn, nền accent, biểu tượng đen** — nút chính duy nhất; nó chốt khung cắt
  rồi mở bảng lưu.
- **Bánh xe nhóm** là một dải cuộn ngang có điểm dừng, gồm 14 chip: Light · Curve · Color · Mix · Point ·
  Grade · Effects · Detail · Optics · Geo · Crop · Mask · Markup · Presets (mỗi chip rộng 58, cao 42).
- **Chip nằm giữa khung là nhóm đang mở**: vuốt → nhả → dừng → đổi nhóm ngay (một thao tác); chạm một chip
  lệch tâm thì nó cuộn vào giữa rồi mới đổi. Có haptic khi đổi.
- **Dấu hiệu đang chọn là màu chữ**, chip giữa dùng màu accent, chip thường xám. **Không có thanh hay hõm
  màu accent** — một đường vàng chạy ngang panel là nhiễu. Hai mép dải mờ dần 26pt.
- Đây là **tầng cuộn ngang duy nhất**, và nó nằm ngay trên vùng vạch home: vùng đó nuốt vuốt **dọc**, nên
  vuốt ngang ở đây không xung đột.

## 6. Vùng thông số

167pt; hoặc **36pt dải chọn + 131pt cuộn** khi tab có dải chọn — chỉ **Grade** dùng (chip Shadows /
Midtones / Highlights / Global, mỗi chip có một chấm màu của vùng).

- Nội dung một nhóm là **danh sách dòng cuộn dọc**; không có dải chọn mục con.
- **Không còn nút Auto hay Reset trên tiêu đề nhóm nào.** Tiêu đề nhóm chỉ còn chữ, và **chỉ hiện khi một
  tab có nhiều hơn một nhóm** (Detail khi ảnh là RAW, và trình sửa mask); tiêu đề rỗng thì thu về **không
  chiếm chỗ**. Tiêu đề **nằm trên** phần cuộn, nếu không slider trượt đè lên làm nó đọc như đang trôi mất.
- Nút riêng của từng tab nằm **trong panel và trong menu ⋯**: Crop có hàng Rotate · Flip · Reset ở đầu
  panel; mask có nút cộng/trừ vùng ngay trong phần hình dạng, và nút xoá mask trong menu của nó.

## 7. Dòng slider

Cao **34pt**: `[nhãn 88pt][rãnh][số 40pt]`, lề ngang 14pt.

| Thành phần | Chi tiết |
|---|---|
| Nhãn | tiếng Anh in hoa, cỡ nhỏ, xám; đang chỉnh thì trắng đặc; **co chữ tối đa 0,75** |
| Số | chữ số đều bề rộng, trắng; đang chỉnh thì màu accent |
| Rãnh trung tính | cao 4pt, xám mờ |
| Rãnh có màu (Temp/Tint) | cao 6pt, **không tô accent đè lên** |
| Con trỏ | **một vạch trắng 4×14 có quầng sáng** — **không có núm tròn, không dùng slider của hệ thống** |
| Khe mốc 0 | **chỉ vẽ cho thông số hai chiều** |

**Cử chỉ** (gom trong một lớp nhận chạm duy nhất):

- Kéo ngang **ở bất kỳ đâu trên dòng** để đổi giá trị (theo độ dịch so với bề rộng rãnh).
- **Giữ yên 300ms rồi kéo = chế độ tinh chỉnh**, độ nhạy còn một phần tư.
- Kéo dọc thì nhường cho cuộn · **chạm đôi = đưa về mặc định** · **giữ lên cột số = mở bàn phím số**.
- Hút vào mốc 0 kèm haptic.

**Mọi** slider trong editor — Light, Color, Effects, Detail, Mixer, Grade, Point, độ nghiêng khi cắt, cọ
mask, màu chữ, cường độ look — đều vẽ bằng **một** thành phần này; hai kiểu dòng còn lại chỉ là vỏ mỏng đọc
danh mục thông số.

## 8. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
