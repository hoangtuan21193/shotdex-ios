# FS-06.08 — Smart Album

`FS-06.08` · `Core/Models/SmartAlbumQuery.swift` · `Data/Database/SmartAlbumStore.swift`
· `Features/Albums/SmartAlbumEditorSheet.swift` · bảng `smart_albums` · cập nhật 2026-09-22

**Một câu:** một bộ lọc có tên, lưu lại được — **không phải** smart album của hệ thống, vì hệ thống không
cho app tạo smart album có điều kiện riêng.

## 1. Quy tắc

- Điều kiện lưu thành **một chuỗi JSON trong một cột chữ** (cột giữ nguyên tên cũ nên **không cần đổi lược
  đồ**).
- Phải **tự mã hoá và tự giải mã chuỗi đó**, không dựa vào cơ chế lồng kiểu dữ liệu của thư viện database:
  lúc giải mã, thư viện đưa cả **dòng database** cho kiểu lồng bên trong, khiến nó không thấy danh sách điều
  kiện và **im lặng cho ra một truy vấn rỗng → album khớp cả thư viện**.
- Điều kiện chưa đủ dữ liệu bị **bỏ qua** khi biên dịch — một dòng đang gõ dở không được làm kết quả về 0
  (khi khớp tất cả) hay nở rộng ra (khi khớp bất kỳ).
- Giải mã **khoan dung**: một điều kiện lạ thì **rơi ra**, không giết cả album
  ([BD-02](../../01-basic-design/BD-02-database-design.md)).

## 2. Model

Một truy vấn gồm **chế độ khớp** (tất cả = VÀ, bất kỳ = HOẶC) và **danh sách điều kiện**; mỗi điều kiện gồm
trường, phép so sánh và giá trị. Loại trường quyết định phép so sánh hợp lệ và ô nhập:

| Loại | Trường | Phép so sánh | Ghi chú |
|---|---|---|---|
| **chữ** | hãng máy, thân máy, ống kính, tên file | chứa · không chứa · đúng bằng · khác | so trên **cả bản đã chuẩn hoá lẫn bản gốc**; phép phủ định vẫn khớp cả dòng rỗng → gõ "R6" bắt được "Canon EOS R6" |
| **chọn** | khổ cảm biến · loại media · định dạng file | là · không là | định dạng gồm JPEG/HEIC/PNG/TIFF/GIF/DNG/RAW, mỗi cái ứng với một tập đuôi file; RAW gộp nhiều đuôi |
| **số** | ISO · khẩu · tốc độ · tiêu cự | bằng · lớn hơn · nhỏ hơn · trong khoảng | tốc độ nhận cả `1/500` lẫn số thập phân; tiêu cự có công tắc **thật / tương đương Full Frame** |
| **ngày** | ngày chụp | **đúng ngày** (mặc định) · trong N ngày qua · trước · sau · trong khoảng | "đúng ngày" khớp **trọn ngày theo lịch địa phương** nên đúng cả ngày đổi giờ; "N ngày qua" so với thời điểm hiện tại nên luôn sống |
| **favorite** | favorite | — | một dải chọn Favorite / Not favorite |

**Loại media** chỉ đặt được qua dải All / Photo / Video, **không** có trong menu chọn trường
([FS-01.05](../FS-01-library/05-filtering-and-sorting.md)).

## 3. Sheet soạn

Bố cục kiểu smart album trên máy tính: ô **tên** · dải **khớp tất cả / bất kỳ** kèm câu mô tả · mục
**Conditions**.

- Mỗi điều kiện là một dòng hai tầng: menu chọn trường + menu phép so sánh + nút **"−"** ở tầng trên, ô nhập
  giá trị ở tầng dưới (vẫn vuốt để xoá được). Cộng nút **"Add Condition"** — **không** hiện sẵn cả loạt
  trường như bản cũ.
- Chân sheet hiện **số ảnh khớp, cập nhật sống**: chạy ngoài luồng chính, chờ 300ms và **huỷ lượt cũ khi có
  lượt mới**, nên không bắn một câu đếm toàn thư viện theo từng phím.
- **Gợi ý ngay dưới ô nhập** cho máy và ống kính: nguồn là một bộ nhớ đệm dùng chung (ba câu quét danh sách
  riêng biệt chạy ngoài luồng chính rồi cache; index xong thì làm mới). Lọc theo chuỗi con không phân biệt
  hoa thường, **tối đa 12 và dừng quét ngay khi đủ**; vẫn gõ tự do được.
- Tiêu cự có nhãn **"mm"** cố định bên phải và ô chỉ nhận chữ số — để không gõ đơn vị vào giá trị.
- Nút Save tắt khi tên rỗng hoặc không có điều kiện hợp lệ; lúc lưu chỉ giữ điều kiện hợp lệ.

## 4. Biên dịch sang truy vấn

Mỗi điều kiện thành một mệnh đề, nối bằng VÀ (khớp tất cả) hoặc HOẶC (khớp bất kỳ). Cùng một bộ dịch được
dùng cho lưới và cho câu đếm.

Bộ lọc đơn giản (chỉ VÀ) vẫn là đường của drill-down từ Statistics, của ô tìm kiếm và của chip trên thanh
điều kiện.

## 5. Tương thích ngược

Bộ giải mã **khoan dung**: đọc được dạng mới; không thấy danh sách điều kiện thì thử đọc dạng bộ lọc cũ và
chuyển sang điều kiện (chế độ khớp tất cả), để album lưu từ trước khi có bộ dựng điều kiện vẫn ra ảnh.

## 6. Hiển thị và mở

- Tile nằm trong mục "Smart Albums"; số ảnh và ảnh bìa tính **sống** (một câu đếm và một câu lấy đúng một
  ảnh), chạy ngoài luồng chính. Album 0 ảnh **vẫn hiện**.
- Chạm thì **mở chồng trong tab Collections**, **không** nhảy sang tab Library.
- Màn chi tiết có một thanh điều kiện **chỉ đọc** ở trên (số ảnh khớp, nhãn khớp tất cả/bất kỳ khi có nhiều
  hơn một điều kiện, và một chip mô tả từng điều kiện), rồi tới lưới. Model của nó soi gương model Library
  nên dùng chung viewer, chế độ chọn, Compare và xoá.
- Giữ lâu trên tile → menu Edit / Delete.
- Menu Filter / Sort trên thanh trên: [FS-06.09](09-album-filter-menu.md) (spec, chưa làm).

## 7. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
