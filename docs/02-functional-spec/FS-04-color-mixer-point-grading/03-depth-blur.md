# FS-04.03 — Depth Blur

`FS-04.03` · `ShotDexKit/DepthImageReader.swift` · cập nhật 2026-09-22

**Một câu:** làm mờ hậu cảnh ảnh Portrait bằng chính bản đồ độ sâu của máy ảnh — và hai filter sẵn có của
Apple đều không dùng được.

## 1. Quy tắc

- Hàng **Depth Blur** ở **đầu nhóm Effects**, và **chỉ hiện khi ảnh có bản đồ độ sâu** — ảnh thường không
  có một slider chết nằm đó.
- **Không có trong mask**: mask đã giới hạn vùng rồi, còn depth blur có ý riêng về vùng.
- **Chạy đầu chuỗi**, trên ảnh chưa chỉnh.
- Dán công thức từ ảnh Portrait sang ảnh không có độ sâu → **trả ảnh gốc**, không lỗi, không đoán.

## 2. Đọc độ sâu

Đọc **bản đồ chênh lệch** (và bản đồ độ sâu nếu không có) cùng **mặt nạ chân dung** ngay từ file nguồn —
không phải đi qua lớp dữ liệu độ sâu của khung hình.

- Việc "ảnh này có độ sâu không" đo **một lần lúc nạp nguồn**, chạy ngoài luồng chính vì phải mở file.
- Chỉ đọc đầy đủ khi công thức thực sự có độ mờ > 0 — đó là một lần giải mã file thứ hai.

## 3. Vì sao chạy đầu chuỗi

Đây là **thuộc tính lúc chụp đang được quyết lại**, không phải một lớp phủ lên kết quả.

Làm mờ sau khi đã chỉnh tone và màu là làm mờ một phiên bản ống kính chưa từng thấy, và bản đồ sẽ không còn
khớp sau khi cắt hoặc nắn ảnh.

## 4. Hai filter của Apple đều không dùng được

| Filter | Vì sao bỏ |
|---|---|
| Bộ dựng ảnh chân dung của chính Apple | thiếu dữ liệu hiệu chỉnh và metadata phụ của máy ảnh thì nó **trả ảnh y nguyên** — đo được: ảnh test kẻ sọc ra với độ tương phản sọc không đổi |
| Bộ làm mờ theo mặt nạ (đúng filter cho việc này, chuyển tiếp liên tục) | trên máy ảo nó **không bao giờ render xong** một ảnh 240pt — phải giết lượt chạy test ở mốc 10 phút |

**Thay bằng hai bản làm mờ Gauss** (bán kính `r×0,45` và `r`) trộn ngược vào theo mặt nạ độ sâu qua hai
nấc: vài lượt, xong trong mili-giây.

## 5. Mặt nạ và bán kính

- Mặt nạ = **đảo** bản đồ chênh lệch (giá trị cao = ở gần), **nhân với đảo của mặt nạ chân dung** khi có —
  mặt nạ đó biết tóc và mép người dừng ở đâu, chính xác hơn bản đồ độ sâu vốn chỉ có 1/4 độ phân giải.
- Bán kính = **3,5% cạnh ngắn × giá trị slider**, nên cùng một slider cho ra cùng độ mờ ở bản xem trước và
  ở bản xuất.

## 6. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
