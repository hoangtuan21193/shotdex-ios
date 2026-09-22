# FS-12.06 — Tầng màu

`FS-12.06` · `Domain/Video/VideoInputTransform.swift` · `VideoMaskRenderer` · `ColorNode`
· cập nhật 2026-09-22

**Một câu:** grade video dùng lại đúng model, đúng phép render và đúng test đã có cho ảnh — chỉ nối thêm
vào compositor.

Scope, LUT nhập ngoài và tracker: [FS-12.06b](06b-scopes-luts-and-tracking.md).

## 1. Quy tắc

- **De-log đứng đầu chuỗi** — mọi look áp lên một ảnh log phẳng là đang chỉnh trên sai ảnh.
- **Không đoán hằng số**: profile nào không có hàm truyền công bố thì **không có mặt**.
- **Grade là một chuỗi node nối tiếp**, không phải một bộ tham số phẳng.
- Panel **nói ra cái nó không làm được**, thay vì liệt kê rồi không làm gì.

## 2. De-log

Năm profile: **None · HLG · S-Log3 · V-Log · Generic Log**. Mỗi cái là hàm truyền đã công bố: nghịch đảo
về scene-linear rồi mã hoá lại Rec.709, dựng thành **256 mẫu** cho một lượt tra màu (chạy trong sRGB —
đường cong định nghĩa trên code value, không trên ánh sáng).

- **Apple Log và C-Log3 cố ý vắng mặt**: hằng số của chúng không có ở đây, và một đường de-log *gần* đúng
  **tệ hơn không có** vì nó trông hợp lý mà sai ở vùng tối.
- Đây là **hàm truyền, không phải chuyển gamut**: footage wide-gamut giữ nguyên primaries, và panel nói
  đúng câu đó.
- Test: đơn điệu đen→trắng · hai nhánh HLG gặp nhau tại 0,5 · mỗi profile đưa **18% xám** về đúng code nhà
  sản xuất công bố · transform nở dải tương phản.

## 3. Primaries

Ba bánh xe shadows / midtones / highlights / global **dùng lại bánh xe màu của photo editor**, kèm
luminance từng vùng.

## 4. Power window và qualifier

Bốn loại: **window tròn · window tuyến tính · dải luminance · dải màu**. Mỗi cái có adjustments riêng, đảo
được, ẩn được, xoá được.

- Model là **đúng model mask của photo editor** nên một window có cùng nghĩa ở cả hai màn.
- **Renderer thì không dùng chung**: đường vẽ mask của ảnh gắn với một actor và cache theo **một tấm ảnh
  tĩnh**, còn compositor chạy trên hàng đợi của AVFoundation, 30 khung/giây, mỗi khung một ảnh khác. Gọi
  sang không hợp lệ, và đánh dấu nó là an-toàn-gọi-chéo là nói dối về cache. Nên có một renderer riêng
  dựng lại **đúng ngữ nghĩa** bằng Core Image thuần, không state dùng chung.
- **Brush, subject và sky không có**: brush vẽ theo hình học của một tấm ảnh tĩnh; subject và sky cần một
  lượt phân đoạn **mỗi khung** mà render 30fps không có ngân sách.

## 5. Node chain

Mỗi node mang đủ **adjustments + color + curve + mask riêng**, chạy theo đúng thứ tự trong chuỗi.

Cân bằng ở node 1, look ở node 2, window ở node 3 — ba node mỗi cái làm một việc thì **đọc được và tắt lẻ
được**; một node làm ba việc thì là một đống slider.

| Thao tác | Ghi chú |
|---|---|
| Thêm | chèn **ngay sau** node đang chọn |
| Nhân bản | mask cũng được cấp id mới |
| **Bypass** | node vẫn nằm trong chuỗi, không làm gì — cách kiểm tra node đó thực sự đóng góp cái gì |
| Đổi tên · reset · xoá | xoá node cuối cùng thì **tự sinh lại một node rỗng** — grade không có node là panel không có gì để chỉnh |
| **Đổi thứ tự** | thứ tự **chính là** grade: window trước một lượt contrast khác hẳn window sau nó |

- Node tắt và node rỗng bị bỏ qua khi tính "có grade hay không", nên **thêm node rỗng không tốn pass render
  nào**.
- UI: hàng chip ở đầu panel Color đọc từ trái sang phải, chấm nhỏ trên node "có làm gì đó", giữ lâu ra
  menu. Mọi mục bên dưới panel sửa **node đang chọn**.
- **Không chép**: parallel/layer mixer, outside node, key nối giữa các node — chúng cần một đồ thị có
  input/output đặt tên và một canvas để nối dây. Chuỗi nối tiếp chỉ cần một danh sách, và nó là hình dạng
  của đa số grade thật.

## 6. Tiêu chí nghiệm thu

Xem [README](README.md).
