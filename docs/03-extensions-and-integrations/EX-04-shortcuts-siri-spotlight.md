# EX-04 — Shortcuts, Siri, Spotlight và Handoff

`EX-04` · `ShotDex/App/Intents/` · test `IntentRoutingTests` · cập nhật 2026-09-22

**Một câu:** mọi đường vào app từ bên ngoài đều quy về **một yêu cầu điều hướng duy nhất**.

## 1. Quy tắc

- **Lệnh từ ngoài không tự làm việc.** Tiến trình chạy lệnh không có sẵn các thành phần của app — mỗi lệnh
  chỉ **ghi lại một yêu cầu** rồi mở app.
- Yêu cầu phải được lấy ra ở **cả hai thời điểm**: lúc màn gốc khởi tạo **và** lúc giá trị đổi — lệnh mở app
  đã ghi yêu cầu **trước khi** màn gốc tồn tại, nên không có thay đổi nào để bắt.
- **Spotlight không index từng ảnh.**
- Handoff dùng **định danh đám mây**, không dùng định danh nội bộ của máy.

## 2. Các lệnh

Mở Library · Tìm ảnh (có tham số câu tìm) · Xem Favorites · Xem ảnh của một máy · Xem Statistics · Xem
Places · Xem Trips — **tất cả đều mở app** khi chạy.

- Tham số "máy ảnh" ánh xạ sang **so khớp chứa**, không phải **so khớp đúng bằng**: tên máy người ta nói ra
  ("R6") hiếm khi trùng nguyên văn giá trị đã index.
- Các câu thoại gợi ý sẵn cho Siri **bắt buộc chứa tên app** — đó là yêu cầu của hệ thống, không phải lựa
  chọn văn phong.

## 3. Spotlight

App chỉ index **bộ sưu tập**: smart album, thân máy, ống kính.

- **Không index từng ảnh**: thư viện có thể tới sáu chữ số, và Spotlight sẽ giữ một bản sao metadata **ra
  ngoài** kho của app — trái cam kết ở [NF-03](../04-non-functional-design/NF-03-privacy-and-security.md).
- **Ghi đè toàn bộ thay vì so sánh sai khác**: tập nhỏ, và so sánh sai khác sẽ để sót những dòng của thiết
  bị đã rời thư viện.
- Chạm một kết quả thì hệ thống đưa app một hoạt động, và app dịch nó thành **cùng một yêu cầu điều hướng**
  như các lệnh khác.

## 4. Handoff

- Viewer công bố một hoạt động "đang xem ảnh này" cho ảnh đang mở, để máy khác mở tiếp đúng ảnh đó.
- **Dữ liệu mang theo là định danh đám mây**: định danh nội bộ chỉ có nghĩa trên chính máy cấp nó — đưa sang
  iPad là gọi tên một tấm ảnh không tồn tại. Hệ quả: **chỉ ảnh nằm trong iCloud Photos mới handoff được**;
  ảnh chỉ có trên máy thì **không công bố gì cả**, thay vì công bố một thứ chắc chắn hỏng ở đầu kia.
- Công bố lại ở **mỗi lần đổi trang**, và huỷ khi đóng viewer — biểu ngữ Handoff luôn đúng tấm đang trước mắt.
- Đầu nhận dịch định danh đám mây về định danh nội bộ rồi đẩy vào **cùng đường điều hướng** với lệnh và
  Spotlight; Library mở viewer bằng đúng hàm "mở một ảnh đã lưu" — cùng một bài toán: lưới phải có ảnh đó
  trước đã, mà lưới thì có thể còn đang tải.

## 5. Ràng buộc còn treo

- Handoff **chưa chạy thật**: máy ảo không đăng nhập iCloud nên không có định danh đám mây để đo.
- Bấm chạy một App Shortcut trong app Shortcuts **trên máy ảo luôn báo lỗi** — hạn chế của máy ảo, không
  phải lỗi app; danh sách lệnh vẫn hiện đúng.

## 6. Tiêu chí nghiệm thu

Có **6 ca test** cho phần định tuyến. Phần còn lại **chưa viết** — xem
[README — Việc còn nợ](../README.md#6-việc-còn-nợ).
