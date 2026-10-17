# FS-07.01 — Dashboard biểu đồ

`FS-07.01` · `Features/Statistics/` · `Data/Database/StatisticsQueries.swift` · `ChartStore` · bảng `stat_charts`
· cập nhật 2026-10-02

**Một câu:** một bảng điều khiển biểu đồ **do người dùng tự dựng** — mỗi thẻ là một đặc tả biểu đồ, có
khoảng thời gian riêng. Thẻ, ô soạn, thanh công cụ và trạng thái màn: [01b](01b-cards-editor-and-states.md).

## 1. Quy tắc

- **Tên cột chỉ đến từ một danh sách đóng trong mã, không bao giờ từ chữ người dùng gõ** → câu truy vấn
  dựng bằng chuỗi vẫn **không có bề mặt tấn công**; chỉ giá trị được truyền vào dạng tham số.
- **Tổng hợp chạy trong database**, không gom trong Swift (trừ việc chia nhóm cho biểu đồ phân bố).
- Mọi truy vấn chạy **ngoài luồng chính**, áp kết quả trên luồng giao diện.
- **Khoảng thời gian thuộc về từng biểu đồ** — không còn một nút chọn chung cho cả màn.
- Điều kiện lọc của biểu đồ **dịch bằng chính bộ dịch của smart album**.

## 2. Một biểu đồ mô tả bằng gì

Loại biểu đồ · **trục X** (nhóm theo) · **trục Y** (đo cái gì) · **điều kiện lọc** · tách chuỗi (chỉ biểu đồ
đường) · giới hạn N mục đầu · **khoảng thời gian**.

| Thành phần | Giá trị |
|---|---|
| Loại | cột ngang · vành khuyên · đường theo thời gian · **một con số** |
| Trục X | nhóm rời rạc (thân máy, hãng, ống kính, **cặp thân máy + ống**, khổ cảm biến, favorite) · nhóm theo dải số (ISO, khẩu, tốc độ, tiêu cự thật, tiêu cự tương đương) · theo thời gian (ngày, tháng, năm) · **theo chu kỳ**: giờ trong ngày (0–23), thứ trong tuần (Mon…Sun) |
| Trục Y | **số ảnh** (mặc định) + trung bình / trung vị / tổng / nhỏ nhất / lớn nhất trên một trường số + **tỉ lệ chụp chậm hơn 1/tiêu cự tương đương** |

- Mỗi loại biểu đồ **tự khai** trục X và phép đo nào hợp lệ với nó — cùng một khuôn với chỗ khai phép so
  sánh hợp lệ của từng trường điều kiện.
- **Trung vị chỉ hợp lệ với biểu đồ một-con-số** — trung vị theo từng nhóm không có cách viết rẻ trong SQL;
  bảng hợp lệ chặn ngay ở giao diện.
- Nhóm theo dải số **dùng lại đúng các mốc chia** mà bộ lọc của Library đang dùng. Lọc theo định dạng file
  thì **hoãn** vì chưa có cột riêng.
- **Giờ trong ngày** và **thứ trong tuần** (mọi thiết bị, FS-18 04 §2) chỉ đi với **cột**: vẽ cột đứng theo thứ tự
  đồng hồ, **đủ** 24 giờ / 7 ngày kể cả nhóm 0 ảnh, tuần bắt đầu Thứ Hai. Tính trên thời điểm chụp đổi sang **múi giờ
  hiện tại của máy** — như trục ngày/tháng/năm; giờ địa phương lúc chụp (FS-01.03b §1) chưa có cột riêng. Bấm cột chưa
  mở Library (chưa có bộ lọc giờ/thứ — FS-18 AC-57). Test `ChartDashboardTests.hourAndWeekdayBins`.
- Mỗi trục X ứng với **một cột cố định** và một cách dựng bộ lọc để **bấm vào là mở Library đã lọc sẵn**.

## 3. Lưu trữ

Mỗi biểu đồ là một dòng gồm id, **đặc tả dạng JSON** và vị trí. Mã hoá và giải mã JSON **tự viết** (giống
smart album) để tránh bẫy lồng kiểu dữ liệu của thư viện database.

Lần cài đầu gieo **bảy** biểu đồ, theo thứ tự:

| # | Biểu đồ | Loại · trục X · trục Y |
|---|---|---|
| 1 | Top Camera | cột ngang · thân máy · số ảnh · 5 mục đầu |
| 2 | Top Lens | cột ngang · ống kính · số ảnh · 5 mục đầu |
| 3 | Total Photos & Videos | một con số · — · số ảnh |
| 4 | Equivalent Focal Length | cột ngang · dải tiêu cự tương đương · số ảnh |
| 5 | Body + Lens | cột ngang · cặp thân máy + ống · số ảnh · 5 mục đầu |
| 6 | Slow Shutter | một con số · — · tỉ lệ chụp chậm hơn 1/tiêu cự tương đương |
| 7 | Photos per Month | đường theo tháng · tách chuỗi theo thân máy, 3 mục đầu · số ảnh |

- **Không biểu đồ nào cố định**: cả bảy sửa và xoá được như biểu đồ người dùng tự dựng.
- Bộ gieo có **số thế hệ**, hiện là **3**. Mỗi thế hệ chạy **một lần duy nhất** — bảng người dùng cố ý xoá
  sạch không được tự mọc lại.
- Máy đã qua thế hệ trước: lần mở Statistics đầu tiên sau khi cập nhật thêm **một lần** các biểu đồ còn
  thiếu vào **cuối** bảng, theo đúng thứ tự trên; không đụng biểu đồ đang có.

| Máy đang ở | Thêm vào cuối |
|---|---|
| chưa gieo | cả bảy, đúng thứ tự |
| thế hệ 1 (Top Camera, Total Photos & Videos) | Top Lens · Equivalent Focal Length · Body + Lens · Slow Shutter · Photos per Month |
| thế hệ 2 (bộ sáu, không có Top Lens) | Top Lens |

- Không có migration dữ liệu: chỉ cờ thế hệ lên 3. *Vì app chưa phát hành (CLAUDE.md, 2026-09-23).*

## 4. Thẻ và ô soạn

Đặc tả ở [FS-07.01b](01b-cards-editor-and-states.md): kiểu vẽ thẻ, định dạng số, màu, thanh công cụ, ô soạn,
trạng thái màn (quyền, đang index, chờ iCloud).

## 5. Khoảng thời gian

Mỗi biểu đồ mang khoảng của riêng nó, lưu trong đặc tả; khoảng tuỳ chọn lưu bằng hai mốc thời gian **trọn
ngày**.

- Có sẵn All Time / This Year / This Month + **Custom Range…** mở một bảng chọn khoảng dạng lịch (các tháng
  xếp dọc, chạy từ ảnh cũ nhất tới nay).
- Ảnh **không có ngày chụp** không lọt vào bất kỳ khoảng nào → chỉ xuất hiện ở biểu đồ để All Time.
- **Mọi phép gom theo thời gian** (ngày, tháng, năm — biểu đồ đường, "Photos per Month", câu tháng bận nhất của
  Insights, điều kiện *trong tháng*) dùng **giờ địa phương** của máy, không dùng UTC (người dùng chốt 2026-10-01).
  Vì ảnh chụp tối 31/8 ở UTC+7 phải nằm ở tháng 8 trên biểu đồ, giống bộ lọc.

## 6. Bố cục

| Bề rộng | Bố cục |
|---|---|
| Hẹp | một cột |
| Rộng | **các cột độc lập kiểu masonry** |

- **Không dùng lưới**: lưới ép mọi ô trong một hàng cao bằng ô cao nhất, nên một thẻ một-con-số đứng cạnh
  một biểu đồ cột để lại đúng một lỗ bằng chiều cao biểu đồ cột.
- Thẻ chia vòng tròn vào các cột để giữ thứ tự đọc. Số cột tính theo bề rộng với **bề rộng thẻ tối thiểu
  320pt**, chặn trong **2…3** — ra **2 cột** ở iPad 11" dọc và màn trong Duo, **3 cột** ở iPad 13" dọc và
  iPad ngang.
- **Chế độ sửa quay về một cột ở mọi bề rộng** — kéo đổi thứ tự và nút xoá đỏ là ngôn ngữ của danh sách;
  sửa, nhân bản và xoá vẫn có trong menu của từng thẻ nên bố cục nhiều cột không mất chức năng nào.
- **Chừa 48pt dưới thẻ cuối**, cộng thêm chỗ cho thanh chrome tự vẽ ở bản iOS trước 26 — vùng cuộn dừng
  đúng ở tab bar nổi nên không chừa thì thẻ cuối dính vào nó.
- Thẻ Insights ([FS-07.02](02-insights.md)) đứng **trên** mọi biểu đồ, không bị chia vòng tròn vào cột.
- Dải trạng thái (Limited, đang index, chờ iCloud — [01b §5](01b-cards-editor-and-states.md)) đứng trên thẻ
  Insights, trải hết bề rộng nội dung ở mọi bố cục.
