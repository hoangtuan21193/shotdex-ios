# QA-01 — Chiến lược kiểm thử

`QA-01` · `ShotDexTests/` · `ShotDexUITests/` · cập nhật 2026-09-22

**Một câu:** tầng nào được test bằng gì, và hôm nay đã phủ tới đâu.

## 1. Quy tắc

- Test phủ **tầng logic thuần và tầng dữ liệu**. Cái gì cần test thì phải nằm ở hai tầng đó, **không nằm
  trong giao diện**.
- Test tầng dữ liệu chạy trên **một database trong bộ nhớ**, dựng mới cho từng ca.
- **Không giả lập giao diện.** Một test vẫn xanh khi xoá mất phần code nó kiểm là một test hỏng.
- Giao diện được đo bằng **kịch bản chạy trên máy ảo**: ảnh chụp cộng một bản kê phần tử **có số đo**,
  không phải bằng những câu khẳng định mơ hồ.

## 2. Đã phủ — tầng logic

Chuẩn hoá tên máy và tên ống kính · bộ đọc truy vấn tìm kiếm · bộ hiểu câu tiếng Việt và tiếng Anh (mọi
phép so sánh và mọi cách nói về ngày, kèm ca chống hồi quy cho cú pháp cũ) · lớp chặn kết quả của model ·
chuẩn hoá chuỗi địa điểm và khoá ô lưới · tiêu cự tương đương · tra khổ cảm biến · dựng bản ghi metadata ·
định dạng thông số (kể cả tiêu đề ngày) · mật độ lưới · chia nhóm ngày · **phép quyết định "ảnh này có cần
đọc lại không"** · cửa sổ ngày của Ngày-này-năm-xưa · lịch nhắc (chọn ngày, định danh, thành phần thời
gian, đi qua múi giờ, lỗ giờ mùa hè, ngày 29/2) · câu chữ của lời nhắc · dấu vân tay ảnh (thứ tự bit, ảnh
phẳng và ảnh có dải, ổn định qua việc thu nhỏ) · gom nhóm ảnh trùng (trùng khít và gần trùng, ngưỡng, chuỗi
nối, thứ tự tốt-nhất-trước, 5.000 ảnh cùng dấu vân tay vẫn rẻ).

## 3. Đã phủ — tầng dữ liệu

Các lần đổi lược đồ · truy vấn lưới (lọc, tìm, sắp) · truy vấn thống kê · truy vấn Ngày-này-năm-xưa (chỉ
năm trước, cả ảnh lẫn video, biên ngày theo giờ địa phương, chỉ cộng dung lượng những dòng đã biết) · nạp
cơ sở dữ liệu cảm biến · kho dấu vân tay (bỏ video, tính lại khi ảnh vừa sửa, chỉ thử lại dòng rỗng khi
được dùng mạng, dọn dòng mồ côi) · cache nhóm trùng (ghi rồi đọc lại đúng, dữ kiện đọc lại từ bảng chính,
gỡ một ảnh thì nhóm còn một ảnh tan đi, số việc còn lại đúng bằng danh sách việc).

Phần đọc EXIF được test trên **ảnh mẫu nhỏ có EXIF** đi kèm bộ test.

**Kernel Core Image so với golden** ([FS-16](../02-functional-spec/FS-16-metal-kernels.md)): cả 40 kernel
chạy trên ảnh vào 48×48 dựng bằng code và trên ảnh thật thu nhỏ, lệch ≤ 1/255 so với ảnh đã chụp trước.
Chụp lại chỉ bằng file đánh dấu trong `build/`, và lần chụp nào cũng cố ý đỏ để không lọt qua cổng. Ảnh chạy qua cả pipeline (có filter của Apple) giữ golden riêng cho từng bản iOS lớn; đổi runtime simulator thì phải chụp thêm bản mới.

## 4. Chưa phủ

| Vùng | Trạng thái |
|---|---|
| Model và các lớp dựng, ghép, xuất của Video Studio | **không có test** — đây là vùng lỗi đã được báo |
| Tiêu chí nghiệm thu của Video Studio và của editor ảnh | chưa viết |
| Hiệu năng, bộ nhớ | không có cổng chặn hồi quy ([NF-01](../04-non-functional-design/NF-01-performance.md)) |
| Trợ năng | không có test tự động |

## 5. Cổng chặn

Một lệnh cài đặt sẽ gắn cổng chặn vào **lúc đẩy code lên**: nó build và chạy **toàn bộ** test, và ghi một
mẫu đo vào file số liệu. Một lệnh khác đọc các mẫu đó so với ngưỡng đã khai; vượt ngưỡng thì **sinh ra một
bản ghi ý định mới**. **Cổng chạy trên máy, không phải trên máy chủ.**
