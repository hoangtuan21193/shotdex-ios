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
- **Vùng chạm tối thiểu 44×44pt ở tầng A/B/C**, kể cả khi glyph nhỏ hơn: nút xoá điều kiện trong rule builder, nút ⋯ của
  thẻ chart và thẻ Insights. Glyph giữ cỡ, vùng chạm nới ra. Tầng D theo luật riêng của DESIGN §10.3.
- Slider không có nhãn chữ cạnh nó vẫn phải có nhãn đọc được (Quality trong Settings › Resize Presets › sửa preset đọc
  "Quality, 80 percent").
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

## 3. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | Smart Album editor có 3 điều kiện, iPhone 17 (Q8) | dump phần tử của sheet | nút xoá mỗi điều kiện có khung ≥ 44×44pt | ⚠️ chưa có (script `Tools/ui-drive` dump) |
| AC-2 | Statistics có 4 thẻ chart và thẻ Insights (Q8) | dump phần tử | mỗi nút ⋯ có khung ≥ 44×44pt, glyph vẫn cỡ cũ trên ảnh chụp | ⚠️ chưa có |
| AC-3 | Settings › Resize Presets › sửa một preset, VoiceOver bật, Quality 80% (Q8) | focus slider Quality | VoiceOver đọc "Quality, 80 percent", vuốt lên tăng 1 bậc | ⚠️ chưa có |

## 4. Việc còn nợ

- Đưa mọi literal hiển thị vào String Catalog.
- Kiểm layout khi chuỗi dài hơn ~30% (tiếng Đức).
- Soi lại control tự vẽ khi RTL.
- Không có test accessibility tự động — hiện chạy agent thủ công *(cần xác nhận)*.
