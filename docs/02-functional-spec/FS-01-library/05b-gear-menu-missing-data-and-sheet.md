# FS-01.05b — Menu Camera/Lens, dữ liệu thiếu, sheet Advanced Search

`FS-01.05b` · `Features/Shared/PhotoFilterMenu.swift` · `RuleBuilderSections` · `AdvancedSearchSheet`
· `Data/Database/SmartAlbumSQLBuilder.swift` · cập nhật 2026-10-02

**Một câu:** lọc theo máy và ống kính từ menu Filter, tìm ảnh thiếu dữ liệu để sửa, và một sheet Advanced
Search gọn hơn không mất nháp khi vuốt nhầm. Phần tiếp của [05](05-filtering-and-sorting.md) (S1, S5, S4, C1).

## 1. Camera ▸ và Lens ▸ trong menu Filter (S1)

- Hai menu con nằm trong phần `Filter:`, sau Capture Kind ▸, trước Advanced Filter….
- Mỗi menu con: **tối đa 8 dòng**, máy (ống kính) có **nhiều ảnh nhất trước**; dòng ghi tên đã chuẩn hoá và số ảnh
  có dấu phân cách (`X-T5` · `18,200`). Hơn 8 thì phần còn lại đi qua Advanced Filter… ngay bên dưới.
- Chạm một dòng = bật/tắt, có dấu chọn. Trong một trục là **hoặc**; Camera với Lens là **và**.
- Chọn xong thành **token có `x` trên thanh điều kiện** — cùng token của bộ lọc đơn giản đang có cho máy và ống kính.
- Đây là bộ lọc đơn giản: chọn khi truy vấn nâng cao đang bật thì truy vấn nâng cao bị xoá ([05 §1](05-filtering-and-sorting.md)).
- Số đếm là **một câu gom nhóm** đọc cùng danh mục gợi ý, không chạy lúc mở menu. Quyền `.limited` → chỉ đếm ảnh thấy được.
- Index chưa có máy (ống kính) nào → menu con đó không hiện. Ảnh không tên máy/ống kính không thành dòng — đó là việc của §2.
- Cùng các dòng trên iPhone, iPad, Duo inner, Duo cover; iOS 26 và trước 26 (menu của hệ thống).
- **Có ở cả ba lưới dùng menu này**: Library, Album Detail, Smart Album ([FS-06.09](../FS-06-collections/09-album-filter-menu.md)).
  Trong album, 8 dòng và số đếm tính **trong phạm vi album** (smart album: trong tập ảnh nó đang khớp), không phải cả thư viện.

Board: menu Filter đang mở chưa có board — cần vẽ trên `Main`, `Main` (iPad), `IP_AlbumDetail` (cả sáng, tối).

## 2. Dữ liệu thiếu (S5)

| Trường | "is missing" nghĩa là | Chip |
|---|---|---|
| Camera Brand · Camera Model · Lens | tên rỗng | `No Camera Brand` · `No Camera` · `No Lens` |
| ISO · Aperture · Shutter Speed · Focal Length | số rỗng | `No ISO` · `No Aperture` · `No Shutter` · `No Focal Length` |
| Date Taken | ảnh không ngày chụp | `No Date` |
| Time of Day | không khung giờ ([03b §1](03b-time-of-day-and-acceptance.md)) | `No Time of Day` |
| Place | không tên địa điểm: không toạ độ, **hoặc** có toạ độ mà chưa tra địa điểm ([04](04-place-search.md)) | `No Place` |
| **Location** (trường mới, chọn một) | Has Location = có toạ độ · No Location = không toạ độ | `Has Location` · `No Location` |

- "is missing" là phép cuối trong menu phép so sánh của các trường trên, không có ô nhập. Dòng Place is missing
  có chú thích **"Includes photos not yet looked up."**
- Không có "is missing": Filename, File Type, Media Type, Favorite, Sao, Cờ (luôn có giá trị; "Unrated",
  "Unflagged" là giá trị), Sensor Format (đã có `Unknown`), Location (đã có Has / No Location).
- Place is missing ≠ No Location: No Location hỏi toạ độ; Place hỏi tên địa điểm, nên gồm cả ảnh có toạ độ chưa tra.
- **"Thiếu" chỉ đếm ảnh tĩnh đã đọc EXIF xong** (đã đọc, hoặc đã kết luận không EXIF), với mọi trường trên.
  Video và dòng chưa đọc xong (chưa đọc, chờ iCloud) **không** tính. *Vì* lúc đang index 40.000 ảnh, `No Lens`
  không được ra cả thư viện. Has Location thì đếm mọi ảnh và video có toạ độ.
- Dòng chú Unknown của Statistics đếm theo **cùng định nghĩa** này, nên hai số khớp nhau.
- **Từ Statistics**: chạm dòng "N photos without this info." dưới một biểu đồ ([FS-07.01 §4](../FS-07-statistics/01-dashboard.md))
  → tab Library mở với **truy vấn nâng cao**: "is missing" của trục biểu đồ + khoảng ngày và điều kiện của
  biểu đồ đó. Lưới ra **đúng N** ô. Trục Sensor Format → `Sensor Format is Unknown`.
- Sửa xong bằng Adjust Location / Adjust Date → ảnh đổi ngày sửa → index đọc lại → ảnh rời lưới đang lọc.

Board: `PH_AdvancedSearch`, `IP_AdvancedSearch`, `DI_AdvancedSearch`, `DC_AdvancedSearch` (menu phép có "is missing").

## 3. Bố cục sheet Advanced Search (S4)

- **Loại media và chế độ khớp chung một hàng**: dải All / Photo / Video bên trái, `Match` + dải All / Any bên phải.
  Hàng cao **44pt**; hai dải có hai nhãn VoiceOver riêng "Media Type" và "Match". Câu giải thích khớp tất
  cả/bất kỳ thành **chú thích dưới hàng**. Lấy lại ~200pt so với hai section. Smart Album editor và Chart editor
  dùng đúng hàng này, cùng chữ.
- Không vừa một dòng (cỡ chữ trợ năng) → hai dải xuống hai dòng **trong cùng một hàng**, không cắt chữ.
- **`Matches N photos` nằm ngay dưới tiêu đề "Advanced Search"**, cạnh nút Search: iOS 26 dùng phụ đề của
  thanh điều hướng, trước 26 là tiêu đề hai dòng. Số có dấu phân cách, số ít/nhiều qua String Catalog.
  Chân section Conditions **không còn** số đếm. Không có điều kiện hợp lệ → không hiện dòng đếm.
- Bộ dựng dùng chung nên Smart Album editor và Chart editor nhận cùng hàng gộp; số đếm ở hai sheet đó ghi ở FS của chúng.

Board: `PH_AdvancedSearch`, `IP_AdvancedSearch`, `DI_AdvancedSearch`, `DC_AdvancedSearch` (sáng, tối).

## 4. Nháp chưa áp không mất khi vuốt (C1)

- Sheet **có nháp** khi điều kiện hợp lệ, chế độ khớp hoặc loại media khác lúc mở. Một dòng điều kiện trống vừa thêm không tính.
- Có nháp: vuốt xuống (và chạm ra ngoài sheet trên iPad) **không đóng** — sheet bật về **và hiện ngay** `.alert`
  **Discard Changes?** · `Discard` (đỏ) · `Keep Editing` ([DESIGN.md §10.4](../../../DESIGN.md)). Cancel mở cùng alert đó.
- Không nháp: Cancel và vuốt đóng ngay, không hỏi. Search (Apply trong album) không bao giờ hỏi.
- Ra nền rồi vào lại: nháp còn nguyên. Discard → lưới giữ truy vấn đang áp trước khi mở sheet.

## 5. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | (S1) 55.000 ảnh, 11 máy; X-T5 18.200, α7 IV 21.300 nhiều nhất | mở Filter → Camera ▸ | 8 dòng xếp theo số ảnh giảm dần, dòng đầu `α7 IV` · `21,300` | ⚠️ chưa có (đề xuất `DatabaseTests.cameraUsageTopEight`) |
| AC-2 | (S1) như AC-1 | chạm `X-T5` | token `X-T5` trên thanh điều kiện; lưới 18.200 ô | ⚠️ chưa có (đề xuất mở rộng `ipad-filter.json`) |
| AC-3 | (S1) đã chọn X-T5; 1.200 ảnh X-T5 dùng XF 56mm | Lens ▸ → `XF56mm` | hai token; lưới 1.200 ô | ⚠️ chưa có |
| AC-4 | (S1) truy vấn nâng cao ISO ≥ 3200 đang bật | Camera ▸ → `X-T5` | truy vấn nâng cao biến mất; chỉ còn token `X-T5` | ⚠️ chưa có |
| AC-5 | (S1) lần chạy đầu, index chưa đọc EXIF ảnh nào | mở menu Filter | không có Camera ▸, Lens ▸ | ⚠️ chưa có |
| AC-6 | (S1) quyền `.limited`, 300 ảnh được chọn, 120 của X-T5 | Camera ▸ | dòng `X-T5` · `120` | ⚠️ chưa có |
| AC-7 | (S1) album 40 ảnh: 25 X-T5, 15 α7 IV; thư viện có 18.200 ảnh X-T5 | Album Detail → Filter → Camera ▸ | 2 dòng, `X-T5` · `25` trước; chạm → lưới 25 ô, vẫn ở màn album | ⚠️ chưa có (đề xuất `AlbumFilterTests.cameraScopedToAlbum`) |
| AC-8 | (S1) smart album ISO ≥ 3200 khớp 300 ảnh, 90 của α7 IV | Smart Album → Filter → Camera ▸ | dòng `α7 IV` · `90` | ⚠️ chưa có |
| AC-9 | (S1) iPad 13" iOS 26.5, Duo inner, iPhone 17 iOS 18.6 | mở Filter | cùng các dòng, cùng thứ tự trên cả ba | ⚠️ chưa có |
| AC-10 | (S5) 1.000 ảnh tĩnh đã đọc, 140 không toạ độ; thêm 30 video không toạ độ | điều kiện Location is No Location | chip `No Location`; lưới 140 ô | ⚠️ chưa có (đề xuất `DatabaseTests.locationHasAndNo`) |
| AC-11 | (S5) 1.000 ảnh đã đọc: 140 không toạ độ, 60 có toạ độ chưa tra địa điểm | Place is missing | chip `No Place`; lưới 200 ô; dòng điều kiện ghi "Includes photos not yet looked up." | ⚠️ chưa có (đề xuất `DatabaseTests.placeMissingIncludesUnresolved`) |
| AC-12 | (S5) 1.000 ảnh đã đọc, 200 lens rỗng; thêm 50 video và 300 ảnh chưa đọc | Lens is missing | lưới 200 ô — không video, không ảnh chưa đọc | ⚠️ chưa có (đề xuất `DatabaseTests.isMissingSkipsUnreadAndVideo`) |
| AC-13 | (S5) 3 ảnh không ngày chụp | Date Taken is missing | lưới 3 ô, xếp cuối theo luật sắp | ⚠️ chưa có |
| AC-14 | (S5) 8 ảnh không khung giờ | Time of Day is missing | lưới 8 ô | ⚠️ chưa có |
| AC-15 | (S5) năm nay: 250 ảnh tĩnh đã đọc không lens, 40 video, 600 ảnh chưa đọc; biểu đồ Lens This Year ghi "250 photos without this info." | chạm dòng đó | tab Library, chip `No Lens` + khoảng ngày năm nay; lưới 250 ô | ⚠️ chưa có (đề xuất `statistics-unknown-drill.json`) |
| AC-16 | (S5) đang lọc No Location, 140 ô | Adjust Location 140 ảnh, chờ index xong | lưới 0 ô, trạng thái rỗng | ⚠️ chưa có |
| AC-17 | (S5) smart album `No Location` đã lưu | mở lại app, mở album | điều kiện còn, cùng số ảnh | ⚠️ chưa có (đề xuất `SmartAlbumQueryTests.isMissingRoundTrip`) |
| AC-18 | (S4) iPhone 17 402×874, sheet trống | mở Advanced Search | loại media + Match một hàng cao 44 ±2pt; đỉnh dòng điều kiện đầu ≤ 240pt | ⚠️ chưa có (đề xuất `advanced-search-layout.json`, dump) |
| AC-19 | (S4) 3 điều kiện khớp 1.284 ảnh, iOS 26.5 và 18.6 | chờ 300ms sau lần sửa cuối | dưới tiêu đề ghi `Matches 1,284 photos`; chân Conditions không có số | ⚠️ chưa có |
| AC-20 | (S4) Duo inner 951×669 (cửa sổ thấp < 720pt), 3 điều kiện, bàn phím ẩn | mở Advanced Search | 3 điều kiện + Add Condition thấy hết, không cuộn | ⚠️ chưa có |
| AC-21 | (S4) iPhone 17 402pt, cỡ chữ AX3 | mở Advanced Search | hai dải trong một hàng, xuống hai dòng, không chữ nào bị cắt; VoiceOver đọc "Media Type" và "Match" riêng | ⚠️ chưa có |
| AC-22 | (C1) sheet mở trống, thêm ISO > 3200 | vuốt xuống | sheet bật về, vẫn mở; alert Discard Changes? hiện ngay với `Discard`, `Keep Editing`; điều kiện còn | ⚠️ chưa có (đề xuất `advanced-search-discard.json`) |
| AC-23 | (C1) như AC-22, alert đang hiện | chạm Keep Editing | alert đóng; điều kiện ISO > 3200 còn; vuốt lần nữa lại hỏi | ⚠️ chưa có |
| AC-24 | (C1) lưới đang áp f < 2; mở Edit, thêm ISO > 3200 | Cancel → Discard | sheet đóng; lưới vẫn f < 2, không có ISO | ⚠️ chưa có |
| AC-25 | (C1) mở Edit với 2 điều kiện, không sửa gì | vuốt xuống | sheet đóng ngay, không alert | ⚠️ chưa có |
| AC-26 | (C1) iPad 13", sheet có nháp | chạm ra ngoài sheet | sheet vẫn mở, alert Discard Changes? hiện | ⚠️ chưa có |
| AC-27 | (C1) sheet có nháp 2 điều kiện | ra Home 10 giây rồi mở lại app | sheet còn mở, 2 điều kiện còn | ⚠️ chưa có |
