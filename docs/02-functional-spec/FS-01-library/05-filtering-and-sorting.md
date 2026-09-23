# FS-01.05 — Lọc và sắp xếp

`FS-01.05` · `Features/Shared/RuleBuilderSections.swift` · `AdvancedSearchSheet`
· `Core/Models/FilterCriteria.swift` · `SortOption` · cập nhật 2026-09-22

**Một câu:** một bộ dựng điều kiện dùng chung cho Advanced Search và Smart Album, cộng một menu lọc nhanh
trên toolbar.

## 1. Quy tắc

- **Hai nguồn điều kiện loại trừ nhau**: đặt truy vấn nâng cao thì xoá bộ lọc đơn giản, và ngược lại — lưới
  chỉ có một nguồn.
- **Bộ dựng điều kiện dùng chung**: sửa một chỗ thì cả sheet Advanced Search lẫn sheet Smart Album đồng bộ.
- Một điều kiện **không được hiện ở hai chỗ**.
- **Mọi phép sắp xếp kết thúc bằng id ảnh làm tiêu chí phá hoà**, và ngày chụp rỗng luôn xếp cuối — thứ tự
  phải giống nhau giữa hai lần chạy cùng một truy vấn.

## 2. Advanced Search

- Mở từ nút trong ô tìm kiếm hoặc mục **Advanced Filter…** trong menu lọc.
- Sheet gồm: **loại media** (All / Photo / Video) · **khớp tất cả / khớp bất kỳ** · **danh sách điều kiện**
  (mỗi dòng một điều kiện, nút thêm, nút xoá, và một dòng đếm số ảnh khớp sống).
- Thứ tự chọn nguồn khi nạp lưới: đường nhanh của hệ thống (khi không lọc gì và đang sắp theo ngày) →
  truy vấn nâng cao → bộ lọc đơn giản.
- Nút **Search** (tắt khi không có điều kiện hợp lệ) áp truy vấn rồi chuyển về tab Library.
- Khi truy vấn nâng cao đang bật, thanh chip đổi sang bản của nó: mỗi điều kiện là một chip có `x`, chữ
  **rút gọn** (`ISO 100`, `f > 1.4`, `focal 50mm–85mm`) thay câu dài. **Edit** và **Clear** ghim cố định ở
  mép phải.
- Số ảnh khớp **không chiếm chỗ trên thanh điều kiện** — nó nằm ở chân lưới, sau ảnh cuối.
- **Save as Smart Album** mở sheet smart album với chính các điều kiện đang có — biến một lần tìm thành một
  album lưu vĩnh viễn.

## 3. Ảnh / video và kiểu chụp

- Thư viện index cả ảnh lẫn video nên **ảnh/video là một chiều lọc riêng**. Cột loại media có từ bản đầu;
  migration chỉ thêm **chỉ mục**.
- Loại media lưu bằng **chuỗi** để đi qua JSON của smart album cho đẹp, và có cầu nối sang số của hệ thống —
  thay cho hằng số `== 2` rải rác khắp nơi.
- Trong bộ dựng điều kiện, nó là **một dải chọn All / Photo / Video** ở đầu sheet. Đó là lối tắt của **đúng
  một điều kiện** nên biên dịch qua cùng một đường và hiện chip như mọi điều kiện khác; nó **không** nằm
  trong menu chọn trường của dòng điều kiện.
- Trong bộ lọc đơn giản, chọn **cả hai** loại hoặc **không chọn gì** đều nghĩa là không ràng buộc.
- **Panoramas** là mục duy nhất không chỉ hỏi mặt nạ bit của hệ thống: nó hỏi `mediaSubtypes` **hoặc**
  cột `isPanorama`, vì panorama do ShotDex ghép không mang cờ của hệ thống
  ([FS-14 §7](../FS-14-panorama/01-screen-and-flow.md)). Mọi kiểu chụp khác vẫn do hệ thống định nghĩa.
- **Kiểu chụp** là một menu con trong menu lọc: Screenshots · Live Photos · Portrait · Panoramas · HDR ·
  Time-lapse · Slo-mo · Cinematic. Là **menu con** chứ không phải tám hàng phẳng, vì tám hàng sẽ chôn mất
  mục "Advanced Filter…".
  - Dữ liệu là bitmask kiểu chụp của hệ thống, nên "một trong các loại này" là một phép hợp của các phép
    kiểm bit trong SQL.
  - Row ghi **trước khi có cột đó** mang giá trị rỗng và **không khớp gì cả**, đúng nghĩa "index chưa biết
    nó là gì" → có một lượt điền bù chạy lúc mở app, đọc kiểu chụp **sẵn trong bộ nhớ** (không đọc file,
    không đụng EXIF), theo lô 2.000.

## 4. Các trục lọc

| Trục | Cách lọc |
|---|---|
| Hãng máy · Thân máy | hai danh sách chọn nhiều **độc lập**, không phân cấp |
| Ống kính | chọn nhiều, danh sách phẳng (phân biệt prime/zoom đã có ở tầng logic, chưa lên giao diện) |
| ISO | chính xác · khoảng · nhóm nhanh ≤100 · 101–400 · 401–1600 · 1601–6400 · >6400 |
| Tốc độ | chính xác · khoảng · nhóm nhanh chậm hơn 1/30 · 1/30–1/125 · 1/126–1/500 · nhanh hơn 1/500 |
| Khẩu | chính xác · khoảng · nhóm nhanh f/1.0–2.0 · f/2.1–4.0 · f/4.1–8.0 · nhỏ hơn f/8 |
| Tiêu cự | thật + tương đương Full Frame; chính xác · khoảng · nhóm theo góc nhìn |
| Khổ cảm biến | Full Frame · APS-H · APS-C · Micro Four Thirds · 1-inch · Compact · Medium Format · Smartphone · Unknown |

Nhóm góc nhìn (theo tiêu cự tương đương): < 20mm Ultra-wide · 20–34 Wide · 35–69 Standard ·
70–134 Portrait / Short telephoto · 135–299 Telephoto · ≥ 300 Super telephoto.

## 5. Menu lọc trên toolbar

Nút lọc là một mục riêng, **tách khỏi Select**; **không còn nút Sort riêng**.

- Phần `Filter:` — All Items · Favorites · Photos Only / Videos Only (hai công tắc **loại trừ nhau**) ·
  **Advanced Filter…**
- Menu con **`Sort By`**: Date Taken (Newest/Oldest) + **Date Modified** (Newest/Oldest). Hệ thống **không
  có** ngày-thêm-vào-thư-viện, chỉ có ngày chụp và ngày sửa — nên nhãn phải ghi đúng là *Modified*.
  Migration thêm chỉ mục cho ngày sửa.
- Đường nhanh của hệ thống mở cho **cả hai kiểu sắp theo ngày**, không chỉ ngày chụp.
- Sắp theo thông số (ISO, tiêu cự, khẩu, tốc độ) **vẫn còn** cho truy vấn nhưng **không xuất hiện trong
  menu**; nếu giá trị đang lưu không phải sắp theo ngày thì menu hiện `Newest`.
- **Không có** sắp theo dung lượng (dù đã index), và **không có** ô chọn số cột — pinch để đổi mật độ.

## 6. Chip điều kiện

- Mỗi chip có nút `x`, chữ ngắn và ký hiệu (`ISO 100`, `ISO ≥ 100`, `f 1.4–2.8`, `focal > 50mm`).
- **Clear** ghim ngoài vùng cuộn ngang nên không bị điều kiện dài đẩy khỏi màn.
- Giữ nguyên bộ lọc khi mở ảnh rồi quay lại.

## 7. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
