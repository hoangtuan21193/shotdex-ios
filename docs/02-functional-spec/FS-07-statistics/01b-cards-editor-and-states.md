# FS-07.01b — Thẻ, ô soạn, thanh công cụ và trạng thái màn

`FS-07.01b` · `Features/Statistics/` (`ChartCard`, `ChartEditorSheet`, `StatisticsScreen`, `ChartPalette`)
· cập nhật 2026-10-02

**Một câu:** một biểu đồ trông thế nào trên thẻ, soạn bằng gì, và Statistics nói gì khi quyền, index hay
iCloud chưa cho đủ dữ liệu. Đặc tả biểu đồ và bộ gieo: [FS-07.01](01-dashboard.md).

## 1. Thẻ biểu đồ

- Mỗi thẻ là một hàng **có nền bo góc riêng**; danh sách bỏ đường kẻ và thêm lề, nên các biểu đồ là những
  khối rời chứ không dính thành một mảng — mà vẫn kéo sắp xếp và vuốt xoá được.
- Tiêu đề thẻ: tên + **khoảng thời gian của chính nó** + menu Edit / Duplicate / Delete.
- Kiểu vẽ: cột ngang (bo góc, tô phẳng) · vành khuyên (lỗ giữa 0,6) · đường theo thời gian. Vẽ bằng Swift
  Charts ở cả ba kiểu.
- **Cột ngang có N mục đầu ≤ 5** (C4): tên ghi **ngay trên thanh của nó**, căn theo mép đầu thanh; giá trị và
  phần trăm ở cuối dòng tên. **Không có danh sách nhãn bên dưới**. Mỗi mục cao 44pt, cả mục là vùng chạm.
  - 5 mục → khối biểu đồ 240pt (5 × 44 + 20), thay cho 160pt biểu đồ + ~220pt danh sách.
  - Tên cặp thân máy + ống được 2 dòng, tên khác 1 dòng; cỡ chữ accessibility thì xuống dòng, mục cao lên.
- Cột ngang có N > 5 và vành khuyên: biểu đồ + danh sách nhãn bên dưới như cũ — danh sách là chú giải màu
  và là chỗ chạm.
- VoiceOver: mỗi mục là một phần tử, nhãn "X-T5, 22,640 photos, 34%"; mục mở được Library thì có trait nút.
- Chạm một cột, một lát hay một hàng **rời rạc hoặc theo dải** thì mở Library đã lọc sẵn. Biểu đồ **theo
  thời gian không mở được**; chạm một điểm trên biểu đồ đường chưa được đặc tả.
- Nhóm **"Unknown" bị ẩn khỏi biểu đồ**, thay bằng dòng chú "N photos without this info." — **chạm được**
  (S5): mở Library với điều kiện "is missing" của trục đó + khoảng ngày và điều kiện của biểu đồ, lưới ra đúng
  N ô ([FS-01.05b §2](../FS-01-library/05b-gear-menu-missing-data-and-sheet.md)). N đếm theo cùng định nghĩa "thiếu" ở đó.

Board: `PH_Statistics` · `IP_Statistics` · `DI_Statistics` · `DC_Statistics` (thẻ Top Camera, Top Lens, Body + Lens).

## 2. Số và màu

- **Mọi số đếm và phần trăm** trên Statistics định dạng theo vùng của máy (Q4): giá trị cột, phần trăm, con
  số lớn của thẻ một-con-số, dòng "N photos without this info.", nhãn trục số, dải tiến độ.
  - en-US: "22,640" · "34%". de-DE: "22.640" · "34 %".
- **Không** định dạng như số đếm: năm và tháng trên trục ("2026", "2026-08"), ISO ("ISO 3200"), khẩu, tốc
  độ, tiêu cự, dung lượng — giữ cách ghi của bộ định dạng EXIF dùng chung.
- Phần trăm trên thẻ làm tròn tới số nguyên. Số đổi trong lúc chạy (dải tiến độ) dùng chữ số đều bề rộng.
- **Màu biểu đồ là amber của app, kiểu "C"** (người dùng chốt 2026-10-04, thay C3 indigo):
  - một chuỗi (cột ngang, cột, một đường): mọi thanh tô accent nhạt (38% sáng / 45% tối), **thanh lớn nhất**
    tô accent đầy; tô phẳng, không dải màu. *Vì thẻ phải trả lời "cái nào nhiều nhất" trong một cái liếc.*
  - nhiều chuỗi và vành khuyên: bảng màu dùng chung theo thứ tự amber · xanh dương · xanh ngọc · tím · ô liu ·
    hồng, đã kiểm mù màu trên nền sáng và tối. Lát / chuỗi thứ 7 trở đi tô **xám trung tính**, không lặp màu;
    biểu đồ đường giới hạn tối đa **6 chuỗi** trong trình sửa.
  - Màu cụ thể và luật chung: DESIGN.md §3.4.

## 3. Thanh công cụ

- Trái: nút Back về Collections (màn đẩy từ Utilities, tiêu đề inline **Statistics**; không còn nút Settings). Phải: **một** nút `+` mở menu **Add Chart** · **Reorder Charts** (C6). Không còn nút ⇅.
- Chưa có biểu đồ nào: Reorder Charts mờ, không ẩn; Add Chart vẫn dùng được.
- Đang sắp xếp: dashboard về một cột kéo-thả; nút `+` nhường chỗ cho nút chữ **Done**. Done → bố cục cũ.
- iOS 26 và trước 26 cùng hai mục menu và cùng nút Done.
- Nút menu giữ glyph `+`: chỗ người dùng đã quen thêm biểu đồ, và câu "Tap + to add a chart." vẫn đúng.

Board: `PH_Statistics` · `IP_Statistics` · `DI_Statistics` · `DC_Statistics` (thanh công cụ + menu mở).

## 4. Ô soạn

- **Ô soạn** soi gương ô soạn smart album: tên · loại · trục X · trục Y · tách chuỗi và N mục đầu · mục
  **Conditions** nhúng **bộ dựng điều kiện dùng chung** · mục **Date Range** · **xem trước sống** ở cuối,
  vẽ bằng dữ liệu thật của bản nháp. Xem trước **không** dời lên đầu lượt này.
- **Sheet Date Range xếp tháng theo bề rộng** (2026-10-12): tháng hẹp nhất 210pt (7 ngày × 30pt), cách nhau 24,
  lề 16 — iPhone và cover Duo một cột (hàng thứ chung ở trên, ngày cao 36); form sheet trên iPad và Duo inner
  (~650pt, chồng lên New Chart) 2 tháng một hàng, thấy 4 tháng cùng lúc. Từ 2 cột trở lên mỗi tháng có hàng thứ riêng, ngày cao 32 để hai hàng tháng vừa
  669pt. Tháng hiện tại luôn đóng hàng cuối (ô trống chèn trước tháng cũ nhất). `DateRangeMonthLayout`.
  Board: `PH_DateRange` · `IP_DateRange` · `DI_DateRange` · `DC_DateRange`.
- **Tên để trống vẫn lưu được** (C2): Save bật khi cấu hình hợp lệ (loại cần trục X thì đã chọn trục X, phép
  đo hợp lệ). Tên trống hay chỉ có dấu cách → biểu đồ mang **tên gợi ý** đang hiện mờ trong ô tên: tên trục X
  ("Camera Model"), hoặc tên phép đo khi là một-con-số trên cả thư viện ("Average ISO").
- Xem trước vẽ ngay khi cấu hình hợp lệ, không chờ tên.
- Mục Conditions dùng **hàng gộp Media Type + Match** (S4) của bộ dựng điều kiện dùng chung
  ([FS-01.05b §3](../FS-01-library/05b-gear-menu-missing-data-and-sheet.md)) — cùng hàng với Advanced Search và
  Smart Album editor. Hàng cao 44pt; hai lựa chọn vẫn có nhãn VoiceOver riêng ("Media Type", "Match").
  - Câu giải thích "Photos must match every condition below." và câu "Counts as one of the conditions…" thành
    chú thích dưới hàng đó.
  - Ô soạn biểu đồ **không hiện số ảnh khớp** — đã có xem trước sống.
- **Bản nháp chưa lưu không mất vì vuốt nhầm** (C1). Bản nháp *đã đổi* khi bất kỳ trường nào khác lúc mở sheet
  (biểu đồ mới: khác cấu hình mặc định). Đổi rồi đổi lại đúng như cũ là *chưa đổi*.

| Bản nháp | Vuốt xuống | Cancel | Save |
|---|---|---|---|
| chưa đổi | đóng | đóng | lưu, đóng |
| đã đổi | sheet bật về **và** mở ngay alert Discard / Keep Editing | alert "Discard Changes?" — **Discard** (đỏ) · **Keep Editing** | lưu, đóng, không hỏi |

- Vuốt và Cancel mở **cùng một** alert — mẫu của HIG Sheets cho bản nháp chưa lưu.

Board: `PH_ChartEditor` · `IP_ChartEditor` · `DI_ChartEditor` · `DC_ChartEditor` (hàng Media Type + Match,
alert Discard Changes).

## 5. Trạng thái màn

| Trạng thái | Statistics hiện gì |
|---|---|
| quyền Denied | "No Access to Photos" + **Open Settings**, như Library; không biểu đồ, không Insights, menu `+` mờ |
| quyền Restricted | "Photos Access Restricted", không nút |
| quyền Limited | dải **Limited Access** đầu màn, cùng chữ và nút **Manage** như Library; số liệu tính trên tập được cấp |
| đang index, có số | dải "Still reading photo info · 34%" (F2); biểu đồ vẽ phần đã đọc, không nhãn "Partial" trên từng thẻ |
| đang index, chưa có số | dải "Still reading photo info…" — pha ghi dòng trước khi đọc EXIF không báo tiến độ |
| đang index, 0 dòng | dải tiến độ + "Charts appear as ShotDex reads your photos."; không hiện "No Indexed Photos" |
| chờ iCloud | dải "iCloud isn't responding · 1,240 photos not read yet" + **Retry Now** (cùng việc nút trên thẻ của Library) |
| không index, 0 dòng | "No Indexed Photos" |
| 0 biểu đồ | "No Charts" + thẻ Insights |

- Phần trăm làm tròn xuống: 54.970 / 54.971 ghi "99%", không bao giờ "100%" khi lượt còn chạy.
- **Lượt index kết thúc** (xong, huỷ, hay dừng vì iCloud) → nạp lại mọi biểu đồ và Insights **một lần**, kể cả
  khi tab đang mở; dải tiến độ biến mất. Trong lúc chạy, số đứng ở lần nạp gần nhất; mở lại tab thì nạp lại.
- "Chờ iCloud" là đúng lúc Library dựng thẻ "iCloud not responding" ([BD-03.04 §4](../../01-basic-design/BD-03-metadata-indexing-flow/04-progress-and-background.md)).
- Tối đa hai dải, trên thẻ Insights: Limited (đúng banner của Library) trên, tiến độ hoặc iCloud dưới. Dải tiến
  độ / iCloud ≤ 44pt ở cỡ chữ mặc định. Cả hai trải hết bề rộng nội dung; Duo ngoài không lấn dải hệ thống 84pt.
- Quyền đổi lúc app ở nền → về foreground là đổi trạng thái, không cần mở lại app.
- **Một chỗ nói một lần**: thẻ Insights không có chân thẻ riêng cho đang index hay Limited — dải đầu màn nói
  thay ([FS-07.02 §6](02-insights.md)).

Board (mới, chưa vẽ — F3): `PH_Statistics` · `IP_Statistics` · `DI_Statistics` · `DC_Statistics`, mỗi thiết
bị ba trạng thái Limited · Denied · chờ iCloud, cộng một trạng thái đang index (F2). Danh mục chung: [NF-04 §3](../../04-non-functional-design/NF-04-empty-and-error-states.md).
