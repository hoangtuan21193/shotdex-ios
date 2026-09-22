# FS-01.04 — Tìm theo địa điểm

`FS-01.04` · `Data/Database/PlaceStore.swift` · `PlaceGeocodingService` · `PlaceIndexPass`
· migration `v7-places` · cập nhật 2026-09-22

**Một câu:** gõ `da nang` ra ảnh chụp ở Đà Nẵng — làm được nhờ gom việc tra địa chỉ theo **lưới ~110m** thay
vì theo từng ảnh.

## 1. Quy tắc

- **Cột địa điểm cố ý không nằm trong bản ghi metadata**, và được ghi bằng đường riêng: indexer ghi đè cả
  bản ghi, nên một bản ghi mang địa điểm rỗng sẽ **xoá sạch** địa chỉ đã giải mỗi lần index lại.
- Search địa điểm chỉ soi **một cột chuỗi đã chuẩn hoá**.
- Toạ độ đọc từ dữ liệu ảnh của hệ thống, **không** đọc thẻ GPS trong EXIF.
- Đây là phần **duy nhất** của index gửi dữ liệu ra ngoài máy → phải tắt được.

## 2. Chuẩn hoá chuỗi

Cột tìm kiếm = mọi thành phần địa chỉ viết thường + bỏ dấu + bỏ trùng, ghép bằng khoảng trắng. Hai bên so
cùng một chuẩn nên `da nang` khớp `Đà Nẵng` bằng một phép so khớp phẳng.

- Bỏ dấu của hệ thống **không** đổi `Đ` thành `d` (nó là chữ riêng, không phải dấu) → có bảng riêng cho
  `đ ð ø ł þ ß æ œ ı`. Chữ không có dạng Latin (`福岡市`) giữ nguyên.
- "Khớp chính xác" ở đây nghĩa là **khớp trọn từ**, vì cột này là một chuỗi ghép — so bằng nhau sẽ không bao
  giờ khớp.

## 3. Lưới ~110m — lý do việc này khả thi

Gom theo lưới **0,001°**; khoá là hai số nguyên nên ổn định như một khoá chính.

- Ảnh cụm dày trong không gian → thư viện 20.000 ảnh thường chỉ còn vài trăm đến ~2.000 ô lưới.
- **Một yêu cầu mỗi ô thay vì một yêu cầu mỗi ảnh** là khác biệt giữa làm được và không — dịch vụ tra địa
  chỉ bị giới hạn tần suất rất nặng.
- Chỗ nằm đúng biên ô phải trả cho hai ô; mọi lưới cố định đều vậy, và cái giá là vài yêu cầu.
- Kết quả cache **bền trên đĩa** kèm ngôn ngữ và số lần thất bại: index lại, mở lại app, hay thêm ảnh ở nơi
  đã từng đến đều **không cần mạng**.

## 4. Dịch vụ tra địa chỉ

Một cửa duy nhất cho mọi lượt tra trong app.

- iOS 26 dùng API mới của bản đồ; trước đó dùng bộ tra của Core Location.
- Nhịp ~1 yêu cầu / 1,2 giây; thất bại thì giãn gấp đôi, từ 4 lên tối đa 60 giây.
- **Phân biệt "không có dữ liệu ở đây" với "không hỏi được"**: chỉ loại đầu bị đếm là thất bại (bỏ sau 3
  lần). Coi lỗi chế độ máy bay là câu trả lời thật sẽ dán nhãn "không có địa điểm" **vĩnh viễn** cho cả một
  chuyến đi.

## 5. Pass tra địa chỉ

Chạy **sau** run index, **không** nằm trong nó: đọc EXIF là việc cục bộ giới hạn bởi đĩa, còn đây là việc
mạng giới hạn bởi tần suất của người khác — gộp vào sẽ giữ chữ "Indexing…" sáng cả 15 phút.

- Chạy tiếp được **từng ô**; gặp trạng thái bị chặn thì **dừng cả run** (xếp thêm yêu cầu là cách kiếm một
  lệnh chặn dài hơn), lần sau tiếp tục.
- Tiến độ đọc được từ model Library.
- **Settings → "Look Up Place Names"**, mặc định **bật**, và pass đọc lại giá trị này ở **mỗi ô** — tắt
  giữa chừng là dừng ngay.

## 6. Nơi dùng

- Bảng thông tin ảnh đọc địa chỉ từ database trước → có tên ngay, không spinner, **không cần mạng**; chỉ khi
  database chưa có mới gọi dịch vụ.
- Địa điểm là một trường dạng chữ nên **tự** có mặt trong bộ dựng điều kiện, tự vào Smart Album và Advanced
  Search, tự có gợi ý. Chip hiện đúng tên (`Fukuoka`), không phải "place Fukuoka".

## 7. Giới hạn

- Cần mạng cho lần đầu mỗi ô lưới; vùng bản đồ không có dữ liệu thì không ra địa chỉ.
- Bộ lọc chạy **trong bộ nhớ** của màn Import **không đánh giá được** điều kiện địa điểm → điều kiện đó bị
  **bỏ qua** ở đó thay vì trả về "không khớp", vì trả "không khớp" sẽ làm bộ lọc im lặng ra rỗng.

## 8. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
