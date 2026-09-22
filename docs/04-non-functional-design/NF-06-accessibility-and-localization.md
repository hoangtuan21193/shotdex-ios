# NF-06 — Khả năng truy cập và đa ngôn ngữ

`NF-06` · `Resources/Localizable.xcstrings` · mọi view tự vẽ chrome
· kiểm bằng agent `a11y-voiceover` · `localization` · cập nhật 2026-09-22

**Một câu:** VoiceOver và Dynamic Type phải đúng ở mọi control tự vẽ; localization mới đi được một phần.

## 1. Luật

- Mọi control **tự vẽ** (tab bar kính, glass button, album card, tile lưới, control editor và timeline)
  phải có nhãn trợ năng và trait đúng **trạng thái hiện tại**.
- Lưới ảnh duyệt được bằng VoiceOver — không gộp cả lưới thành một phần tử.
- Dynamic Type: chữ không được cắt ở cỡ accessibility. Không đặt chiều cao cứng cho hàng có chữ.
- Haptic không thay thế phản hồi nhìn được.
- Số, ngày, đơn vị đi qua bộ định dạng của hệ thống / bộ định dạng thông số của app, **không nối chuỗi tay**.
- **Số nhiều dùng plural variation trong String Catalog, KHÔNG dùng `^[…](inflect: true)`.** Markup đó
  **không resolve trong app này**: tiếng Anh là ngôn ngữ nguồn và mọi giá trị trong catalog bằng đúng key,
  nên Xcode **không sinh thư mục ngôn ngữ tiếng Anh**; lookup rơi về chính cái key (kèm markup), mà grammar agreement chỉ
  áp cho giá trị lấy **từ bảng localization**. Swift dùng key nội suy thường
, catalog khai biến thể số ít / số nhiều cho `en`.

## 2. Tình trạng localization

| Hạng mục | Tình trạng |
|---|---|
| String Catalog (nguồn `en`, có vùng `vi`) | có |
| Đã dịch `vi` | **chỉ** chuỗi reminder "Ngày này năm xưa" + section Notifications trong Settings |
| Phần còn lại | chưa localize — còn literal tiếng Anh |

## 3. Việc còn nợ

- Đưa mọi literal hiển thị vào String Catalog.
- Kiểm layout khi chuỗi dài hơn ~30% (tiếng Đức).
- Soi lại control tự vẽ khi RTL.
- Không có test accessibility tự động — hiện chạy agent thủ công *(cần xác nhận)*.
