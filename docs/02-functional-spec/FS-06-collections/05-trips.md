# FS-06.05 — Trips

`FS-06.05` · `Domain/Places/TripGrouping.swift` · `TripsScreen` · test `TripGroupingTests` (5 ca)
· cập nhật 2026-10-02

**Một câu:** gom ảnh thành chuyến đi bằng luật **cố ý máy móc** — không "thông minh", nên người dùng đoán
được nó sẽ gom thế nào.

## 1. Định nghĩa một chuyến

Một chuỗi ảnh:

- cách **nhà** hơn **80 km**,
- không đoạn nào hở quá **2 ngày**,
- kéo dài ít nhất **1 ngày**,
- và có ít nhất **8 ảnh**.

## 2. "Nhà"

**Ô 0.5° dày ảnh nhất**, và chỉ tính là nhà khi chiếm **≥ 20%** thư viện.

Dưới ngưỡng đó coi như người dùng chụp khắp nơi (`home = nil`, mọi ảnh đều tính là "đi xa") — không có tín
hiệu nào khác về "nhà" khi chạy offline.

## 3. Cắt và nối

- Khoảng hở đo với ảnh **cuối của chuỗi đang gom**, không phải ảnh vừa duyệt qua — một tấm lạc giữa chừng
  không được reset đồng hồ.
- Một ảnh chụp ở nhà **kết thúc** chuỗi.
- Sau đó một lượt nối lại các chuỗi liền kề **cùng tên địa điểm** và cách nhau ≤ 2 ngày: một tấm sai
  giờ, một lần import từ máy khác, hay một đêm về nhà giữa chuyến sẽ cắt một kỳ nghỉ thành ba.
- Ảnh bìa lấy **giữa chuỗi**, không lấy tấm đầu — ảnh lúc mới tới hiếm khi đáng làm bìa.

## 4. Màn hình

Board: `PH_Trips` · `IP_Trips` · `DI_Trips` · `DC_Trips`.

- Chuyến mới nhất trước. Mỗi chuyến một **thẻ cover cao 160pt**, bo `r-lg`, tên + "ngày · N photos" trên scrim đáy.
  Chạm mở danh sách ảnh của chuyến ([FS-06.03](03-photo-list-and-movie-builder.md)).
- **Compact** (iPhone, Duo cover): một cột trải hết bề ngang nội dung.
- **Regular** (Z2): **lưới cột co giãn 320…440pt**, khoảng cách 16. Bề rộng nội dung 1344 (iPad ngang) → 4 cột
  324pt; 1000 (iPad dọc) → 3 cột 323pt; 835 (Duo inner, sau rail 84) → 2 cột 410pt.
- **Cao giữ 160pt ở mọi size class** — Trips không vào danh sách được to theo cửa sổ của DESIGN §10.1d; màn rộng
  là nhiều chuyến hơn trên một hàng, không phải cover to hơn.
- Ảnh bìa xin theo **bề rộng cột** × 160pt × độ phân giải màn, không theo bề rộng cửa sổ. Ảnh chỉ có trên iCloud
  được tải; chưa về (hay không mạng) thì thẻ là nền xám phụ, tên và ngày vẫn đọc được.

## 5. Tiêu chí nghiệm thu

Luật gom (§1–§3) **chưa có AC** — `TripGroupingTests` (5 ca) chạy nhưng chưa gắn vào AC nào. Xem
[README — Việc còn nợ](../../README.md#6-việc-còn-nợ). Màn hình:

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | (Z2) thư viện có 9 chuyến; iOS 26.5 | mở Trips trên iPad 1376×1032 | 4 cột, mỗi thẻ 324×160pt, 3 hàng (4 + 4 + 1); hàng cuối thẻ căn trái | ⚠️ chưa có — đề xuất `Tools/design-board compare` trên `IP_Trips` |
| AC-2 | (Z2) như AC-1 | xoay iPad sang 1032×1376 | 3 cột, mỗi thẻ ~323×160pt | ⚠️ chưa có |
| AC-3 | (Z2) như AC-1 | mở Trips trên Duo inner 951×669 | 2 cột, mỗi thẻ ~410×160pt | ⚠️ chưa có — `DI_Trips` |
| AC-4 | (Z2) như AC-1; iOS 26.5 và 18.6 | mở Trips trên iPhone 402×874 và Duo cover 466×678 | một cột, thẻ 370×160pt / 350×160pt; pre-26 thẻ cuối không nằm dưới tab bar tự vẽ | ⚠️ chưa có — `PH_Trips`, `DC_Trips` |
| AC-5 | (Z2) như AC-1, iPad @2x | thẻ đầu xin ảnh bìa | kích thước xin là 648×320px (cột 324pt), không phải 2752×320px | ⚠️ chưa có |
| AC-6 | (Z2) máy tắt mạng, bìa của chuyến đầu chỉ có trên iCloud | mở Trips | thẻ đầu là nền xám phụ cao 160pt, tên và ngày hiện đủ; các thẻ khác có bìa | ⚠️ chưa có |
