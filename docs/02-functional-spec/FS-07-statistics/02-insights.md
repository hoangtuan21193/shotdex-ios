# FS-07.02 — Nhận xét rút từ dữ liệu (Insights)

`FS-07.02` · `Features/Statistics/` · `Domain/Statistics/` (mới) · `Data/Database/StatisticsQueries.swift`
· test `ShotDexTests/StatisticsInsightsTests.swift` (mới) · cập nhật 2026-10-02

**Một câu:** đầu màn Statistics có một thẻ **Insights** gồm tối đa 3 câu khẳng định về chính thư viện của
người dùng; chạm một câu là mở Library lọc đúng những ảnh câu đó nói tới.

## 1. Quy tắc

- **Chỉ nói về dữ liệu của người dùng.** Không khuyên, không so với người khác, không nhắc sản phẩm không có
  trong thư viện.
- **Số đến từ SQL.** Gom nhóm, chia dải, đếm tháng đều chạy trong database — kể cả chia dải tiêu cự.
- **Luật chọn câu là hàm thuần**: nhận các con số đã gom. Không đọc đồng hồ, không đọc database. Cùng đầu vào
  → cùng danh sách câu, cùng thứ tự.
- **Luôn tính trên All Time**; khoảng thời gian của từng biểu đồ không ảnh hưởng tới Insights.
- **Chỉ ảnh tĩnh.** Video không vào mẫu số nào; ảnh thiếu trường cần dùng thì đứng ngoài câu đó.

## 2. Danh mục

Ngưỡng chung: **≥ 50 ảnh có tên máy**. Dưới ngưỡng thì không tính loại nào.

| Loại | Câu (nguồn `en`) | Hiện khi | Chạm |
|---|---|---|---|
| Tiêu cự | "85% of your photos are at 26mm equivalent." | xem §5 | Library lọc tiêu cự tương đương |
| Cặp body + lens | "EOS R6 with RF 85mm F1.2 L USM took 40% of your photos." | ≥ 50 ảnh có cả máy lẫn ống · ≥ 2 cặp · cặp đầu ≥ 20% | Library lọc máy **và** ống |
| Chụp chậm | "18% of your photos were shot slower than 1/focal length." | ≥ 50 ảnh có tốc độ + tiêu cự tương đương · tỉ lệ ≥ 5% | không chạm được — câu không có mũi tên |
| Tháng bận nhất | "August 2026 was your busiest month: 1,240 photos." | ≥ 3 tháng có ảnh · tháng đầu ≥ 50 ảnh và ≥ 2 × trung vị các tháng | Library lọc **trong tháng** đó |

- **Điều kiện "trong tháng"** (tháng + năm của ngày chụp) là điều kiện mới của bộ lọc Library **và** smart album.
  Ghi nó vào [FS-01.05](../FS-01-library/05-filtering-and-sorting.md) và
  [FS-06.08](../FS-06-collections/08-smart-albums.md) cùng lượt làm.
- "Chụp chậm" không chạm được: bộ lọc không có điều kiện so hai cột, và spec này không thêm.

"Chụp chậm" nghĩa là thời gian phơi dài hơn 1 chia tiêu cự tương đương — cùng luật với truy vấn tỉ lệ chụp
chậm đã có.

## 3. Chọn và xếp

- Thứ tự cố định: tiêu cự → cặp body + lens → chụp chậm → tháng bận nhất.
- Hiện **tối đa 3 câu** — 3 câu đầu qua ngưỡng. Không câu nào qua ngưỡng → thẻ không hiện, không có câu lấp chỗ.
- Hoà điểm trong một loại: tiêu cự ngắn hơn trước · tên máy rồi tên ống a→z · tháng gần đây hơn trước.

## 4. Luật lời văn

- Câu là **một mẫu trọn vẹn** trong String Catalog có chỗ điền; không ghép mảnh câu.
- Số nhiều dùng biến thể plural của catalog, không dùng markup inflect ([NF-06](../../04-non-functional-design/NF-06-accessibility-and-localization.md)).
- Phần trăm là số nguyên theo định dạng phần trăm của hệ thống. Từ 99,5% tới dưới 100% ghi **99%**;
  "100%" chỉ khi đúng là tất cả.
- Tiêu cự qua bộ định dạng thông số của app ("26mm", không dấu cách — giống chip, overlay và Info; người dùng
  chốt 2026-10-01); tháng ghi tháng + năm theo locale, gom theo giờ địa phương ([01](01-dashboard.md) §5).
- Không động từ khuyên hay phán: *buy, sell, upgrade, should, try, consider, recommend, need, better,
  worse*. Có test quét mọi mẫu.
- Mẫu số không phủ ≥ 90% ảnh có tên máy → câu dùng biến thể nêu rõ mẫu số
  ("…of your photos with a known equivalent focal length…").

## 5. Tiêu cự: tương đương, dải, điện thoại

- Luôn dùng **tiêu cự tương đương full-frame**, không bao giờ tiêu cự thật: XF 23mm trên X-T5 là "35mm".
- Tiêu cự tương đương làm tròn tới mm. Hiện câu khi:
  1. một giá trị chiếm ≥ 50% → câu nêu giá trị đó;
  2. không thì **nhóm góc nhìn** của bộ lọc Library ([FS-01.05 §4](../FS-01-library/05-filtering-and-sorting.md):
     Ultra-wide < 20 · Wide 20–34 · Standard 35–69 · Portrait 70–134 · Telephoto 135–299 · Super telephoto ≥ 300)
     đông nhất ≥ 50% → câu nêu nhóm đó ("Wide, 20–34mm"). Chạm câu thì Library lọc **đúng nhóm đó**, nên số trong
     câu bằng số ảnh trên lưới (người dùng chốt 2026-10-01);
  3. không thì gộp nhóm đó với nhóm kề đông hơn, ≥ 50% → câu nêu hai nhóm gộp; vẫn thiếu → không có câu.
- Ảnh có tiêu cự thật mà ≥ 50% không quy đổi được (máy chưa biết cảm biến) → không có câu tiêu cự; chân thẻ
  hiện "N photos are from cameras with an unknown sensor size." mở Settings → Unknown Cameras.
- **Mỗi mô-đun camera của điện thoại là một ống**: iPhone 15 Pro chính và tele đếm riêng, vì EXIF ghi tên ống
  khác nhau cho từng mô-đun.
- Tên ống trong câu là **tên EXIF đã chuẩn hoá**, giống nhãn bộ lọc sau khi chạm ("iPhone 15 Pro back triple
  camera 6.765mm f/1.78"). Tên gọn kiểu "Main · 24 mm" cho cả app là một spec riêng, chưa viết; câu đổi theo khi có.

## 6. Thẻ Insights

| Bề rộng | Bố cục |
|---|---|
| Hẹp (iPhone, Duo ngoài) | một thẻ đủ bề ngang, các câu xếp dọc, ngăn bằng đường kẻ |
| Rộng (iPad) | một thẻ trải hết bề rộng nội dung; câu chia vào **cùng số cột** như dashboard (2…3) |
| Rộng + cửa sổ thấp (Duo trong 669pt) | các câu xếp **một hàng**, mỗi câu một cột (tối đa 3, cột ≥ 280pt); thẻ ~120pt ở 669, không cắt chữ; bề rộng không đủ thì về số cột của dashboard |

- Lần đầu mở: thẻ Insights ở trên cùng, bên dưới là 6 biểu đồ gieo ([FS-07.01 §3](01-dashboard.md)).
- **Ẩn được**: menu của thẻ có **Hide Insights**. Lựa chọn nhớ trong Settings — Settings → **Display**, nhóm
  **Statistics**, có công tắc **Show Insights** để bật lại. Mục Settings tên "Thumbnail Metadata" đổi thành
  **Display**, gồm hai nhóm: Thumbnail Metadata và Statistics (người dùng chốt 2026-10-01). Không ẩn từng câu.

- Thẻ dùng đúng kiểu thẻ biểu đồ ([DESIGN.md](../../../DESIGN.md) — bo 16, nền, lề 16); không token mới.
- Mỗi câu: biểu tượng hệ thống của loại + câu + mũi tên nếu chạm được. Chữ xuống dòng, không cắt ở cỡ accessibility.
- VoiceOver: mỗi câu là một phần tử, nhãn là chính câu đó; câu chạm được có trait nút, câu không chạm được thì không.
- Duo trong 669pt: thẻ Insights không đẩy biểu đồ đầu ra khỏi màn — **≥ 120pt** của thẻ biểu đồ đầu tiên thấy
  được khi chưa cuộn. "Cửa sổ thấp" theo [NF-05 §4](../../04-non-functional-design/NF-05-device-and-os-compatibility.md) (< 720pt).
- Cỡ chữ accessibility trên cửa sổ thấp: câu xuống dòng, thẻ cao lên; không câu nào kết thúc bằng "…".

| Trạng thái | Hiển thị |
|---|---|
| chưa index ảnh nào | "No Indexed Photos" của dashboard; không có thẻ Insights |
| dưới ngưỡng chung | thẻ có một dòng "Insights appear once 50 photos have camera info — 32 so far." |
| đang index | câu tính trên phần đã index; **không chân thẻ** — dải "Still reading photo info · N%" đầu màn nói thay ([FS-07.01b §5](01b-cards-editor-and-states.md)) |
| quyền `.limited` | câu tính trên tập được cấp; **không chân thẻ** — banner Limited Access + Manage đầu màn nói thay |
| lỗi truy vấn | "Couldn't compute insights." + **Try Again**; biểu đồ không bị ảnh hưởng |

## 7. Tính ở đâu, tốn bao nhiêu

- Mở tab Statistics là tính lại, chạy ngoài luồng chính, **không chặn** các thẻ biểu đồ.
- Mỗi loại là một hoặc hai câu truy vấn gom nhóm trên các cột đã có chỉ mục; kết quả trả về không quá vài trăm dòng.
- Ngân sách: cả lượt ≤ **500 ms** trên thư viện 55.000 ảnh ([NF-01](../../04-non-functional-design/NF-01-performance.md)).
  Đo tay trong `/verify`; không có test benchmark.
- Đọc: bảng metadata chính. Ghi: không gì — không cột mới, không bảng mới ([BD-02](../../01-basic-design/BD-02-database-design.md)).
