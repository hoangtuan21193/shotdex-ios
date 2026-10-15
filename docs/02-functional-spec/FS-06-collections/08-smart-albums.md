# FS-06.08 — Smart Album

`FS-06.08` · `Core/Models/SmartAlbumQuery.swift` · `Data/Database/SmartAlbumStore.swift`
· `Features/Albums/SmartAlbumEditorSheet.swift` · bảng `smart_albums` · cập nhật 2026-10-16 (trường Source, Kept — FS-24 D8)

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
| **chữ** | hãng máy, thân máy, ống kính, tên file, địa điểm | chứa · không chứa · đúng bằng · khác · **is missing** (trừ tên file) | so trên **cả bản đã chuẩn hoá lẫn bản gốc**; phép phủ định vẫn khớp cả dòng rỗng → gõ "R6" bắt được "Canon EOS R6" |
| **chọn** | khổ cảm biến · loại media · định dạng file · **cờ** | là · không là (khổ cảm biến có giá trị *Unknown*) | cờ gồm Pick · Reject · Unflagged, đọc từ bảng cờ riêng; định dạng gồm JPEG/HEIC/PNG/TIFF/GIF/DNG/RAW, mỗi cái ứng với một tập đuôi file; RAW gộp nhiều đuôi — **cùng bảng đuôi** của nhãn định dạng trên tile ([FS-03.04b §2](../FS-03-photo-editor/04b-unsupported-raw.md)) |
| **số** | ISO · khẩu · tốc độ · tiêu cự | bằng · lớn hơn · nhỏ hơn · trong khoảng · **is missing** | tốc độ nhận cả `1/500` lẫn số thập phân; tiêu cự có công tắc **thật / tương đương Full Frame** |
| **ngày** | ngày chụp | **đúng ngày** (mặc định) · **trong tháng** · trong N ngày qua · trước · sau · trong khoảng · **is missing** | "đúng ngày" khớp **trọn ngày theo lịch địa phương** nên đúng cả ngày đổi giờ; "trong tháng" khớp trọn một tháng + năm theo lịch địa phương, ô nhập chọn tháng và năm; "N ngày qua" so với thời điểm hiện tại nên luôn sống |
| **favorite** | favorite | — | một dải chọn Favorite / Not favorite |
| **vị trí** | vị trí | — | dải chọn **Has Location / No Location**, theo toạ độ, không theo tên địa điểm (S5) |
| **nguồn** (2026-10-16) | Source | là · không là | giá trị là một nguồn có ảnh (Photos, thư mục, ổ, server — [FS-19](../FS-19-photo-sources/README.md)); khớp ảnh **có bản sao** ở nguồn đó, cùng truy vấn với Source › của menu Filter ([FS-24.03 §2](../FS-24-media-hub/03-photos-tab.md)). Lưu **id bền** của nguồn, không lưu tên: đổi tên không hỏng album; nguồn đã gỡ → chip `NAS Home (removed)`, khớp 0 ảnh, album vẫn mở |
| **đã Keep** (2026-10-16) | Kept on iPhone (`on iPad`, `on Mac`) | — | dải chọn **Kept / Not Kept**, theo bảng thứ đã Keep ([FS-24.09](../FS-24-media-hub/09-keep-on-device.md)); tính sống như mọi trường — Keep thêm / Remove from iPhone thì album đổi ở lần mở kế |
| **sao** | sao | là · ít nhất · nhiều nhất | ô chọn 0–5, 0 = *Unrated*; "ít nhất" chỉ nhận 1–5 (ít nhất 0 là cả thư viện). Sao hiện hành theo [FS-01.12 §4](../FS-01-library/12-rating-and-flags.md) |
| **keyword** (iOS 27) | keyword | có · không có · có keyword bất kỳ · không có keyword nào | hai phép sau không cần giá trị; ô nhập gợi ý keyword của thư viện, nhiều ảnh nhất trước; khớp không phân biệt hoa thường và dấu, trên gương keyword ([FS-02.07 §7](../FS-02-photo-detail/07-caption-and-keywords.md)) |
| **caption** (iOS 27) | caption | chứa · không chứa | trên gương caption, gấp hoa thường + dấu như cột địa điểm |
| **keyword** (iOS 27) | keyword | có · không có · có keyword bất kỳ · không có keyword nào | hai phép sau không cần giá trị; ô nhập gợi ý keyword của thư viện, nhiều ảnh nhất trước; khớp không phân biệt hoa thường và dấu, trên gương keyword ([FS-02.07 §7](../FS-02-photo-detail/07-caption-and-keywords.md)) |
| **caption** (iOS 27) | caption | chứa · không chứa | trên gương caption, gấp hoa thường + dấu như cột địa điểm |

**is missing** (S5) khớp ảnh mà trường đó **rỗng**, là phép cuối trong menu phép, không có ô nhập, và **luôn đủ
dữ liệu** nên không bị bỏ qua khi biên dịch. Bộ dựng dùng chung với Advanced Search, nên hai sheet có **cùng một
tập phép** ([FS-01.05b §2](../FS-01-library/05b-gear-menu-missing-data-and-sheet.md)).

- Có *is missing*: hãng máy, thân máy, ống kính, ISO, khẩu, tốc độ, tiêu cự, ngày chụp, khung giờ chụp, **địa điểm**.
- **Địa điểm *is missing*** khớp ảnh chưa có địa chỉ, **gồm cả ảnh có toạ độ mà lượt tra địa chỉ chưa tới**. Dòng
  điều kiện ghi chú thích thấy được *"Includes photos not yet looked up."* (K3).
- Không có *is missing*: tên file, định dạng, loại media, favorite, vị trí (đã có No Location), khổ cảm biến (đã
  có *Unknown*), sao và cờ (*Unrated* / *Unflagged* là giá trị), nguồn (mọi ảnh có ít nhất một nguồn), đã Keep (*Not Kept*
  là giá trị).
- Danh sách phép dựng từ **loại trường** cộng một danh sách loại trừ; kiểm bằng cách lặp qua mọi trường.
- Tiêu cự: *is missing* theo công tắc đang chọn — *tương đương* rỗng khi máy chưa biết cảm biến dù có tiêu cự thật.
- Ảnh vừa được Adjust Date / Adjust Location rời album *is missing* / *No Location* ngay lần mở kế, vì album tính sống.

Hai trường **sao** và **cờ** mang lại tên trường của bản đã gỡ ở `v15`/`v16`. Không vướng: hai migration đó
đã chạy xong trước khi có album nào dùng tên mới ([BD-02 §4](../../01-basic-design/BD-02-database-design.md)).

Dưới iOS 27 menu chọn trường **không** có keyword và caption (ẩn, không mờ). Hai trường cũng có trong điều kiện của
biểu đồ Statistics — cùng bộ dựng, cùng SQL.

Dưới iOS 27 menu chọn trường **không** có keyword và caption (ẩn, không mờ). Hai trường cũng có trong điều kiện của
biểu đồ Statistics — cùng bộ dựng, cùng SQL.

**Loại media** chỉ đặt được qua dải All / Photo / Video, **không** có trong menu chọn trường
([FS-01.05](../FS-01-library/05-filtering-and-sorting.md)).

## 3. Sheet soạn

Board: `PH_SmartAlbumEditor` · `IP_SmartAlbumEditor` · `DI_SmartAlbumEditor` · `DC_SmartAlbumEditor`.

Bố cục kiểu smart album trên máy tính, dùng chung với Advanced Search ([FS-01.05 §2](../FS-01-library/05-filtering-and-sorting.md)):
tiêu đề kèm **số ảnh khớp** · ô **tên** · **một hàng** loại media + chế độ khớp · mục **Conditions**.

- **Loại media và chế độ khớp chung một hàng cao 44pt** (S4), đúng hàng của bộ dựng dùng chung
  ([FS-01.05b §3](../FS-01-library/05b-gear-menu-missing-data-and-sheet.md)): dải All / Photo / Video bên trái,
  *Match* + dải All / Any bên phải. VoiceOver đọc hai control riêng: *"Media Type"*, *"Match"*.
  - Câu giải thích khớp tất cả / bất kỳ là **một dòng chú thích dưới hàng**; câu "Counts as one of the
    conditions…" thay nó khi khớp bất kỳ và có chọn loại media.
  - Không vừa một dòng (bề ngang 375pt, cỡ chữ trợ năng) → hai dải xuống hai dòng trong cùng hàng, không cắt chữ.
- **Số ảnh khớp** (S4) nằm **ngay dưới tiêu đề sheet, cạnh nút Save**: iOS 26 là phụ đề của thanh điều hướng,
  trước 26 là tiêu đề hai dòng. *"Matches 1,284 photos"* — có dấu phân cách, số ít *"Matches 1 photo"*.
  - Chân mục Conditions **không còn** số đếm. Không có điều kiện hợp lệ → không hiện dòng đếm.
- Mỗi điều kiện là một dòng hai tầng: menu chọn trường + menu phép so sánh + nút **"−"** ở tầng trên, ô nhập
  giá trị ở tầng dưới (vẫn vuốt để xoá được). Cộng nút **"Add Condition"** — **không** hiện sẵn cả loạt
  trường như bản cũ.
- Số ảnh khớp **cập nhật sống**: chạy ngoài luồng chính, chờ 300ms và **huỷ lượt cũ khi có lượt mới**, nên
  không bắn một câu đếm toàn thư viện theo từng phím.
- **Gợi ý ngay dưới ô nhập** cho máy và ống kính: nguồn là một bộ nhớ đệm dùng chung (ba câu quét danh sách
  riêng biệt chạy ngoài luồng chính rồi cache; index xong thì làm mới). Lọc theo chuỗi con không phân biệt
  hoa thường, **tối đa 12 và dừng quét ngay khi đủ**; vẫn gõ tự do được.
- Tiêu cự có nhãn **"mm"** cố định bên phải và ô chỉ nhận chữ số — để không gõ đơn vị vào giá trị.
- Nút Save tắt khi tên rỗng hoặc không có điều kiện hợp lệ; lúc lưu chỉ giữ điều kiện hợp lệ.
- **Thay đổi chưa lưu không mất vì vuốt nhầm** (C1). Sheet **có thay đổi** khi tên, chế độ khớp, loại media
  hay điều kiện hợp lệ khác lúc mở; một dòng điều kiện trống vừa thêm không tính.
  - Có thay đổi: vuốt xuống (và chạm ra ngoài sheet trên iPad) thì sheet **bật về và hiện ngay** alert
    *"Discard Changes?"* · **Discard** (đỏ) · **Keep Editing** — như Mail (K4). Cancel mở cùng alert.
  - Không có thay đổi: vuốt và Cancel đóng ngay, không hỏi. Save không bao giờ hỏi.
  - Ra nền rồi vào lại: thay đổi còn nguyên. Duo inner (compact height): sheet toàn màn, không vuốt được, chỉ có Cancel.

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
- **Đóng viewer thì lưới đưa tới ảnh vừa xem** (Q7), cùng luật với Library và On This Day
  ([FS-06.07 §4](07-on-this-day.md)): ô của ảnh cuối cùng trong viewer không thấy trọn thì lưới cuộn, không hoạt
  ảnh, tới khi ô thấy trọn; ô đã thấy trọn thì lưới đứng yên.
- Giữ lâu trên tile → menu Edit / Delete.
- Menu Filter / Sort trên thanh trên, lọc chồng lên điều kiện đã lưu: [FS-06.09](09-album-filter-menu.md). Menu
  này dùng chung với Library nên có cả mục kiểu chụp **Unsupported RAW** ([FS-01.05 §3](../FS-01-library/05-filtering-and-sorting.md)).

## 7. Tiêu chí nghiệm thu

Phần cũ (§1, §2 trừ *is missing* / vị trí, §4–§5) **chưa có AC** — xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
Điều kiện *trong tháng*: [FS-07.03](../FS-07-statistics/03-acceptance-criteria.md) AC-18. Điều kiện *sao* và *cờ*:
[FS-01.12](../FS-01-library/12-rating-and-flags.md) AC-8. Trường *nguồn* và *đã Keep*: [FS-24.14d](../FS-24-media-hub/14d-acceptance-criteria.md) AC-118…121.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | (S4) iPhone 402×874, iOS 26.5 và 18.6 | mở *New Smart Album* | dải All / Photo / Video và dải Match All / Any nằm cùng một hàng (minY lệch ≤ 2pt), hàng cao 44pt; dòng chú thích khớp tất cả nằm dưới hàng; VoiceOver đọc *Media Type* và *Match* thành hai control | ⚠️ chưa có — đề xuất `Tools/design-board compare` trên `PH_SmartAlbumEditor` |
| AC-2 | (S4) điều kiện *Camera Model contains R6* khớp 1.284 ảnh, thêm 5 điều kiện nữa; iOS 26.5 và 18.6 | cuộn danh sách tới nút Add Condition | *Matches 1,284 photos* vẫn ngay dưới tiêu đề, cạnh Save (26.5: phụ đề thanh điều hướng; 18.6: dòng hai của tiêu đề); chân Conditions không có số đếm | ⚠️ chưa có |
| AC-3 | (S4) như AC-2 | gõ 3 ký tự vào ô giá trị trong 200ms | đúng 1 câu đếm chạy, bắt đầu ≥ 300ms sau phím cuối; dòng đếm đổi một lần | ⚠️ chưa có |
| AC-4 | (S4) Duo inner 951×669, sheet có tên + 3 điều kiện | mở sheet | tiêu đề + dòng đếm, tên, hàng media/khớp, 3 điều kiện và Add Condition thấy trọn không cần cuộn | ⚠️ chưa có — `DI_SmartAlbumEditor` |
| AC-5 | (S5) 100 ảnh, 30 không có ống kính | thêm *Lens is missing*, Save tên "No Lens" | dòng đếm *Matches 30 photos*; album mở ra 30 ảnh | ⚠️ chưa có — đề xuất `SmartAlbumMissingRuleTests` |
| AC-6 | (S5) mọi trường của bộ dựng | mở menu phép của từng trường | hãng máy, thân máy, ống kính, ISO, khẩu, tốc độ, tiêu cự, ngày chụp, khung giờ, địa điểm có *is missing* là mục cuối; tên file, định dạng, loại media, favorite, vị trí, khổ cảm biến, sao, cờ, nguồn, đã Keep (FS-24 D8) không có | ⚠️ chưa có — test lặp qua mọi trường |
| AC-7 | (S5) 100 ảnh, 40 không toạ độ | chọn vị trí *No Location*, rồi *Has Location* | lần lượt *Matches 40 photos*, *Matches 60 photos* | ⚠️ chưa có |
| AC-8 | (S5) album *No Location* 40 ảnh | Adjust Location 5 ảnh của nó trong viewer, đóng viewer | album còn 35 ảnh, tile ở Collections ghi 35 | ⚠️ chưa có |
| AC-9 | (S5) khớp bất kỳ: *Lens is missing* (30 ảnh) hoặc *ISO is missing* (20 ảnh, 10 trùng) | xem dòng đếm | *Matches 40 photos* | ⚠️ chưa có |
| AC-10 | (S5) album lưu với *Date Taken is missing* và một điều kiện có phép lạ trong JSON | mở lại app, mở album | điều kiện *is missing* còn nguyên; điều kiện lạ rơi ra, album vẫn mở | ⚠️ chưa có — mở rộng `SmartAlbumRuleDecodingTests` |
| AC-11 | (C1, K4) *New Smart Album*, gõ tên "Night" | vuốt sheet xuống | sheet bật về và alert *Discard Changes?* hiện ngay (Discard đỏ, Keep Editing); Keep Editing → tên "Night" còn nguyên | ⚠️ chưa có |
| AC-12 | (C1) như AC-11 | chạm Cancel, rồi Discard | cùng alert hiện; Discard đóng sheet, Collections không có album mới | ⚠️ chưa có |
| AC-13 | (C1) mở *Edit Smart Album* của album có sẵn, không sửa gì | vuốt sheet xuống | sheet đóng ngay, không có alert | ⚠️ chưa có |
| AC-14 | (C1) như AC-11 | cho app ra nền 60 s rồi mở lại | sheet còn mở, tên "Night" và các điều kiện còn nguyên | ⚠️ chưa có |
| AC-15 | (Q7) smart album 300 ảnh, lưới density 3 | mở ảnh thứ 5, vuốt tới ảnh thứ 120, đóng viewer | ô ảnh 120 thấy trọn trên lưới | ⚠️ chưa có |
| AC-16 | (S5, K3) 100 ảnh: 20 không toạ độ, 30 có toạ độ nhưng lượt tra địa chỉ chưa tới, 50 có địa chỉ | thêm *Place is missing* | dòng điều kiện ghi *Includes photos not yet looked up.*; *Matches 50 photos* | ⚠️ chưa có |
| AC-17 | (C1) như AC-11, trên iPad 1376×1032 | chạm ra ngoài sheet | sheet không đóng; alert *Discard Changes?* hiện | ⚠️ chưa có |
