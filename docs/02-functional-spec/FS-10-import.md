# FS-10 — Import từ thẻ nhớ và folder ngoài

`FS-10` · tier B · `Features/Import/` · `Data/Sources/ImportService.swift` · cập nhật 2026-09-22

**Một câu:** nhập ảnh và video từ thẻ SD, USB hay một folder ngoài **có lọc RAW** — thứ app Photos không làm
được lúc nhập.

## 1. Ràng buộc của iOS định hình thiết kế

- **Không nhập trực tiếp từ thân máy ảnh qua USB** như mục Devices của Photos — việc đó cần quyền riêng mà
  Apple không cấp cho app bên thứ ba. App **chỉ đọc được ổ đã gắn qua Files**.
- **Không tự phát hiện lúc cắm thiết bị**: hệ thống không cho app thấy ổ USB hay thẻ SD, và cũng không có
  thông báo khi gắn ổ. Muốn đọc thì **người dùng phải tự chọn folder**.
- Vì vậy nút Import nằm trong **Settings → Photo Library**, không tự ẩn/hiện theo thiết bị; chỉ hiện khi đã
  có quyền đọc thư viện.
- **Không có "xoá sau khi nhập"** — thẻ được đối xử **chỉ-đọc**.

## 2. Luồng

Màn Import mở toàn màn từ Settings, có ngăn xếp điều hướng riêng.

| # | Bước | Chi tiết |
|---|---|---|
| 1 | Chọn folder | ô chọn folder của hệ thống; quyền truy cập folder được **giữ suốt phiên** rồi trả lại lúc đóng màn |
| 2 | Quét nhanh | duyệt đệ quy ngoài luồng chính, phân loại theo đuôi file: ảnh theo bảng định dạng của app, video theo danh sách đuôi (mov/mp4/m4v/avi/mts…), file lạ bỏ. Mỗi file thành một **ứng viên** kèm metadata giữ chỗ để lọc theo định dạng và ngày chạy được ngay. Mới nhất trước |
| 3 | Lưới | thumbnail ảnh giải mã thẳng từ file, video lấy khung đại diện. **RAW ẩn mặc định**, kèm nhãn đếm số RAW đang ẩn; video có nhãn play |
| 4 | Đọc EXIF nền | 8 file song song, dùng **đúng bộ chuẩn hoá tên máy và tra cảm biến** của lượt index; **video không có EXIF**. Xong thì mở khoá lọc theo máy, ống kính và ISO |
| 5 | Lọc | dùng **bộ dựng điều kiện chung**, nhưng đánh giá **trong bộ nhớ** bằng một bản song song của bộ dịch sang SQL — có test giữ hai bên đồng bộ |
| 6 | Nhập | phần giao giữa "đã chọn" và "đang hiện" được chép vào thư viện, **giữ nguyên tên file gốc**. Chạy tuần tự, xong thì tổng kết đã nhập / thất bại |
| 7 | Index | ảnh mới làm thư viện phát tín hiệu thay đổi cấu trúc, và lượt index tăng dần tự nhặt. **Không gọi index thủ công** |

## 3. Bỏ qua ảnh đã nhập

- App lấy sẵn tập **tên file kèm đúng số byte** của mọi ảnh đã có trong index, rồi đánh dấu ứng viên trùng.
- Công tắc **Hide Photos Already Imported** (mặc định bật); chân màn nói rõ có bao nhiêu cái.
- **Dùng tên + đúng số byte chứ không băm nội dung**: màn nhập phải trả lời **trước khi** người dùng chọn gì,
  mà băm cả một thẻ RAW qua USB thì mất vài phút. Hai ảnh khác nhau mà trùng cả tên lẫn số byte chính xác là
  đủ hiếm để chấp nhận.

## 4. Thêm vào album

Ô chọn **Add to Album** thêm mọi ảnh vừa nhập vào một album — chạy **sau cả mẻ** (một lượt ghi thay vì N,
và một mẻ nhập dở vẫn bỏ được phần đã xong vào album).

## 5. Ràng buộc còn treo

Có [ý định bỏ lối vào Import khỏi Settings](../_intents/2026-09-21-remove-import-entry-point.md) — trạng
thái **nháp**, và code hiện vẫn giữ nút.

## 6. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../README.md#6-việc-còn-nợ).
