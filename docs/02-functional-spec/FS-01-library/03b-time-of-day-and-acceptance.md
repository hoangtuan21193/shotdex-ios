# FS-01.03b — Khung giờ chụp, từ không hiểu, Recents màn rộng

`FS-01.03b` · `Domain/Filtering/SearchIntentParser.swift` · `Data/Sources/SearchService.swift`
· `Features/Library/SearchSuggestionsScreen.swift` · cập nhật 2026-10-02

**Một câu:** "85mm night" ra ảnh đêm chụp bằng ống 85mm; từ app không hiểu thì nói ra, không lặng lẽ lọc theo
tên file. Phần tiếp của [03](03-search.md); mục ID planboard trong ngoặc (S2, Q3, Z2).

## 1. Khung giờ chụp (S2)

Mỗi ảnh mang **một** khung giờ, tính lúc index ([BD-03.02 §4](../../01-basic-design/BD-03-metadata-indexing-flow/02-exif-read.md)),
lưu ở bảng metadata chính ([BD-02 §2](../../01-basic-design/BD-02-database-design.md)).

| Khung | Có toạ độ: độ cao mặt trời | Không toạ độ: giờ địa phương lúc chụp |
|---|---|---|
| Night | dưới −6° | từ 20:00 tới trước 05:00 |
| Blue hour | từ −6° tới dưới −4° | — |
| Golden hour | từ −4° tới +6° | — |
| Day | trên +6° | từ 05:00 tới trước 20:00 |

- **Có toạ độ thì luôn theo mặt trời**, kể cả khi EXIF có giờ. *Vì* 20:00 ở Fukuoka ngày 21/6 mặt trời
  còn ở −5,9° — giờ xanh, không phải đêm.
- Blue hour và Golden hour mang thêm **nửa ngày**: sáng (mặt trời đang lên) hay chiều (đang lặn).
- Giờ địa phương = giờ đồng hồ máy ảnh ghi vào EXIF lúc chụp, kèm độ lệch múi giờ khi có.
- Ảnh không toạ độ, ngoài khung đêm → **Day** (05:00–20:00). Không toạ độ thì không bao giờ ra giờ xanh hay giờ vàng.
- **Video và ảnh không có giờ EXIF** (chụp màn hình, ảnh quét), không toạ độ: lấy thời điểm chụp của hệ thống,
  đổi sang **múi giờ hiện tại của máy** lúc index. Biết trước cái giá: video quay ở múi giờ khác rồi index ở nhà
  bị đọc theo giờ ở nhà.
- **Không có thời điểm chụp nào** (không EXIF, hệ thống cũng không có ngày) → không khung nào.
- Sửa vị trí hay ngày chụp bằng Adjust Location / Adjust Date làm ảnh đổi ngày sửa → index đọc lại → khung tính lại.

## 2. Từ khoá

| Gõ | Thành điều kiện | Chip |
|---|---|---|
| `night` · `đêm` · `ban đêm` | khung giờ là Night | `Night` |
| `blue hour` · `giờ xanh` | Blue hour, cả hai nửa | `Blue hour` |
| `golden hour` · `giờ vàng` | Golden hour, cả hai nửa | `Golden hour` |
| `sunset` · `hoàng hôn` | Golden hour nửa chiều | `Sunset` |
| `sunrise` · `bình minh` | Golden hour nửa sáng | `Sunrise` |

- `sunset` / `sunrise` **chỉ** là giờ vàng của nửa đó, không gồm giờ xanh — giờ xanh có từ riêng.
- Khớp **nguyên cụm, nguyên từ** như [03 §3](03-search.md): `night` trong `nightscape` không khớp.
- Bộ dựng điều kiện có trường **Time of Day**, chọn một: Night · Blue Hour · Golden Hour · Sunrise · Sunset · Day.
  Model iOS 26 dùng đúng sáu giá trị đó; giá trị lạ bị lớp chặn bỏ.

## 3. Từ không hiểu (S2)

- Khi đã có ít nhất một điều kiện, phần chữ còn lại thành **một chip mời**: `"sunsett" not understood · Search filenames?`,
  chữ màu phụ của hệ thống, có `x`. Chip này **không lọc** — lưới ra theo các điều kiện còn lại.
- **Chạm chip** → nó thành điều kiện `Filename contains sunsett` (chip thường), lưới lọc lại.
- `x` trên chip mời → bỏ từ đó, lưới không đổi. Save as Smart Album **không** lưu chip mời.
- Không điều kiện nào hiểu được → vẫn tìm chữ tự do ([03 §1](03-search.md)).
- *Vì* một chip lọc ngầm theo tên file biến cả lần tìm thành 0 ảnh mà không nói vì sao.

Board: `Main`, `Main` (iPad), `Main` (Duo), `DC_Library` (thanh điều kiện có chip mời) · `PH_Search`, `IP_Search`, `DI_Search`, `DC_Search`.

## 4. Dòng "Try:" (Q3)

Thư viện chưa có địa điểm, máy nào → một dòng `Try: Fukuoka · f > 1.2 · ISO over 3200 · before 2020`, qua
String Catalog; bản tiếng Việt `Thử: Fukuoka · f > 1.2 · ISO trên 3200 · trước 2020` nằm trong catalog.
Ba ví dụ có số phải được bộ phân tích hiểu ở **cả hai** ngôn ngữ.

## 5. Recents trên màn rộng (Z2)

- **Compact** (iPhone, Duo cover): 3 thẻ vuông chia đều bề ngang.
- **Regular** (iPad, Duo inner): **một hàng** thẻ vuông 150–200pt, khoảng cách 12pt; số thẻ = số thẻ vừa một
  hàng, tối đa 6. iPad 13" ngang 1376pt → 6 thẻ; Duo inner 951pt → 5 thẻ.
- Thumbnail xin đúng **cạnh thẻ × tỉ lệ màn** (pixel), không phải một cỡ cố định: thẻ 200pt trên @2x → 400px.
  *Vì* cỡ cố định 320px phóng ~2,7× trên thẻ 437pt của iPad.
- Mỗi thẻ vẫn là một truy vấn một ảnh, chỉ bộ phân tích; 6 thẻ = tối đa 10 truy vấn (bỏ câu không còn kết quả).

Board: `IP_Search`, `DI_Search` (đổi) · `PH_Search`, `DC_Search` (giữ, chỉ cỡ thumbnail).

## 6. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | (S2) ảnh toạ độ 33,590 N 130,402 E, chụp 2026-06-21 19:15 JST | index ghi dòng | khung Golden hour, nửa chiều (mặt trời +2,2°) | ⚠️ chưa có (đề xuất `TimeOfDayTests.sunAltitudeBands`) |
| AC-2 | (S2) cùng toạ độ, 19:55 JST | index ghi dòng | Blue hour, nửa chiều (−5,0°) | ⚠️ chưa có |
| AC-3 | (S2) cùng toạ độ, 20:00 JST, EXIF ghi 20:00 | index ghi dòng | Blue hour (−5,9°), **không** Night — toạ độ thắng giờ | ⚠️ chưa có |
| AC-4 | (S2) cùng toạ độ, 04:50 JST và 05:00 JST | index ghi hai dòng | 04:50 Blue hour nửa sáng (−4,2°); 05:00 Golden hour nửa sáng (−2,4°) | ⚠️ chưa có |
| AC-5 | (S2) ba ảnh không toạ độ, EXIF 20:30 · 04:59 · 05:00 | index ghi dòng | hai ảnh đầu Night; ảnh 05:00 Day, không ảnh nào Golden hour/Blue hour | ⚠️ chưa có |
| AC-6 | (S2) video không toạ độ, thời điểm chụp 2026-06-21 12:00 UTC, máy đang ở múi giờ UTC+9 (21:00 giờ máy) | index ghi dòng | khung Night | ⚠️ chưa có (đề xuất `TimeOfDayTests.deviceZoneFallback`) |
| AC-7 | (S2) ảnh chụp màn hình không toạ độ, không EXIF, 14:00 giờ máy; và một ảnh không có ngày chụp nào | index ghi dòng | ảnh đầu Day; ảnh sau không khung nào, "Time of Day is missing" khớp nó | ⚠️ chưa có |
| AC-8 | (S2) ảnh chỉ có trên iCloud, có toạ độ, EXIF đang chờ iCloud | pha 1 (ghi dòng giữ chỗ) xong | đã có khung giờ, trước khi đọc được EXIF | ⚠️ chưa có |
| AC-9 | (S2) ảnh không toạ độ đã có Night; lần đọc lại tải được 0 byte | index ghi lỗi | khung vẫn Night (luật không đè) | ⚠️ chưa có (đề xuất `IndexDiffTests.failedReadKeepsTimeOfDay`) |
| AC-10 | (S2) 40 ảnh 85mm, 12 trong đó Night | gõ `85mm night`, bấm Search | hai chip `85mm`, `Night`; lưới 12 ô | ⚠️ chưa có (đề xuất `SearchIntentParserTests.timeOfDayWords` + `search-time-of-day.json`) |
| AC-11 | (S2) 5 ảnh Golden hour chiều, 3 Golden hour sáng, 4 Blue hour chiều | gõ `hoàng hôn`, bấm Search | chip `Sunset`; lưới 5 ô — không ảnh giờ xanh nào | ⚠️ chưa có |
| AC-12 | (S2) 40 ảnh 85mm | gõ `85mm sunsett`, bấm Search | chip `85mm` + chip mời `"sunsett" not understood · Search filenames?`; lưới 40 ô, không phải 0 | ⚠️ chưa có |
| AC-13 | (S2) như AC-12, 0 file tên chứa "sunsett" | chạm chip mời | chip thành `Filename contains sunsett`; lưới 0 ô với trạng thái rỗng | ⚠️ chưa có |
| AC-14 | (Q3) index rỗng, ngôn ngữ English | mở Search | dòng đúng chữ `Try: Fukuoka · f > 1.2 · ISO over 3200 · before 2020`; ngôn ngữ Tiếng Việt → bản catalog | ⚠️ chưa có |
| AC-15 | (Q3) ba cụm `f > 1.2`, `ISO over 3200`, `before 2020` và bản tiếng Việt | đưa vào bộ phân tích | mỗi cụm ra đúng một điều kiện, không phần dư | ⚠️ chưa có (đề xuất `SearchIntentParserTests.tryLineExamplesParse`) |
| AC-16 | (Z2) iPad 13" ngang 1376pt, iOS 26.5, 8 câu Recents còn kết quả | mở Search | 6 thẻ một hàng, mỗi cạnh 150–200pt; ảnh xin = cạnh × 2 px | ⚠️ chưa có (đề xuất `search-recents-ipad.json`, dump) |
| AC-17 | (Z2) như AC-16 trên iOS 18.6 | mở Search | cùng 6 thẻ, cùng cỡ | ⚠️ chưa có |
| AC-18 | (Z2) Duo inner 951×669, bàn phím mở, 8 câu Recents | mở Search | 5 thẻ một hàng; ít nhất 1 capsule; không capsule nào đè thẻ | ⚠️ chưa có |
| AC-19 | (Z2) iPhone 17 402pt, 8 câu Recents | mở Search | 3 thẻ vuông; ảnh xin = cạnh × 3 px | ⚠️ chưa có |
| AC-20 | (Z2) quyền `.limited`, 3 trong 8 câu Recents chỉ khớp ảnh ngoài phần được chọn | mở Search trên iPad | các câu đó không có thẻ; còn lại ≤ 6 thẻ | ⚠️ chưa có |
