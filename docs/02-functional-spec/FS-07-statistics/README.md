# FS-07 — Statistics

`FS-07` · tier A · `ShotDex/Features/Statistics/` · `Data/Database/StatisticsQueries.swift` · `ChartStore`
· test `ChartDashboardTests` · `StatsDateScopeTests` · `StatisticsOverviewTests` · cập nhật 2026-10-24

**Một câu:** tab Statistics — một thẻ **Insights** nói bằng lời thói quen chụp của người dùng, rồi bên dưới là
dashboard biểu đồ do người dùng tự dựng; chạm vào đâu cũng mở Library lọc sẵn.

Nguồn: [intent 2026-09-30, mục 5](../../_intents/2026-09-30-user-wishes-research.md). Hướng đã ghi ở
[OV-01 §3](../../00-overview/OV-01-product-goals-and-scope.md) ("nhận xét cá nhân hoá", "tổ hợp body+lens ưa dùng").

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 01 | [Dashboard biểu đồ](01-dashboard.md) | đặc tả biểu đồ, lưu trữ, thẻ, ô soạn, khoảng thời gian, bố cục cột |
| 01b | [Thẻ, ô soạn, trạng thái màn](01b-cards-editor-and-states.md) | kiểu vẽ thẻ, định dạng số, màu, thanh công cụ, ô soạn, quyền / đang index / chờ iCloud |
| 02 | [Insights](02-insights.md) | danh mục câu, ngưỡng, lời văn, tiêu cự tương đương, thẻ, ẩn, hiệu năng |
| 03 | [Tiêu chí nghiệm thu](03-acceptance-criteria.md) | AC-1…61 |

## 1. Người dùng cần gì

Người chụp muốn biết mình **thật sự** chụp tiêu cự nào, hay cầm cặp body + lens nào, bao nhiêu ảnh chụp chậm,
tháng nào chụp nhiều. Hôm nay họ phải tự dựng biểu đồ mới thấy; người không dùng ShotDex thì tự viết script
exiftool. Lần đầu mở Statistics phải trả lời ngay, bằng lời, từ chính ảnh của họ.

## 2. Phạm vi

**Có:**
- dashboard biểu đồ tự dựng (FS-07.01), lần đầu gieo 7 biểu đồ (thêm Top Lens) trả lời các câu ở §1;
- thẻ Insights với bốn loại câu: tiêu cự, cặp body + lens, chụp chậm, tháng bận nhất;
- chạm câu → Library lọc sẵn (trừ câu chụp chậm); iPhone, iPad, Duo cùng một tập câu;
- điều kiện **trong tháng** mới cho bộ lọc Library và smart album;
- **không gì cố định**: mỗi biểu đồ gieo xoá được, thẻ Insights ẩn được.

**Cố ý không có:**
- lời khuyên mua, bán, nâng cấp — vì đó không phải dữ liệu của người dùng, và intent cấm;
- so với người dùng khác, hay thống kê "trung bình" — không có server, không analytics;
- câu sinh bằng mô hình ngôn ngữ — câu phải kiểm được bằng test, cùng đầu vào cùng kết quả;
- Insights trong widget, thông báo, Shortcuts — chưa có ai đòi;
- chọn khoảng thời gian cho Insights — câu nói về thói quen trên cả thư viện;
- câu "ống lâu không dùng" — dễ đọc thành gợi ý bán ống;
- tên ống gọn cho mô-đun điện thoại ("Main · 24 mm") — một spec riêng cho cả app; spec này dùng tên EXIF.

## 3. Ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Hiệu năng | lượt Insights ≤ 500 ms ở 55.000 ảnh, ngoài luồng chính ([NF-01](../../04-non-functional-design/NF-01-performance.md)) |
| Dữ liệu | chỉ đọc bảng metadata chính; không cột, không bảng mới ([BD-02](../../01-basic-design/BD-02-database-design.md)) |
| Riêng tư | tính trên máy, không gửi đi đâu ([NF-03](../../04-non-functional-design/NF-03-privacy-and-security.md)) |
| Thiết bị | iPhone 402×874 · iPad 1376×1032 và 1032×1376 · Duo trong 951×669 · Duo ngoài 466×678 |
| iOS 26 vs trước | hai nhánh cùng tập câu, cùng hành vi chạm; spacer chrome nổi giữ như dashboard |
| Truy cập | mỗi câu một phần tử VoiceOver; chữ không cắt ở cỡ accessibility ([NF-06](../../04-non-functional-design/NF-06-accessibility-and-localization.md)) |
| Ngôn ngữ | mẫu câu trọn vẹn trong String Catalog, số nhiều bằng biến thể plural; bản `vi` chưa dịch như phần còn lại của app |

## 4. Card ở tab Utilities (2026-10-24)

Statistics không còn là một hàng trong nhóm Explore của tab Utilities (nhóm đó đã bỏ, Places và Trips gỡ khỏi app):
nó là **card riêng trên cùng** tab Utilities (board `PH_Utilities`, `IP_`, `DI_`, `DC_Utilities`;
[FS-06.01 §5b](../FS-06-collections/01-tabs-tokens-and-album-management.md)).

- **Nội dung:** tiêu đề `Statistics` `.headline` + chevron; ba số **Photos · Cameras · Lenses** (`.title2` đậm,
  mono-digit, nhãn `.caption` màu phụ); biểu đồ cột số ảnh theo **12 tháng gần nhất**, chỉ ba nhãn tháng (đầu · giữa · cuối, viết tắt 3 chữ, nằm dưới đúng cột), không trục
  dọc. Một chuỗi nên một sắc (DESIGN.md §3.4): tháng nhiều nhất `ChartPalette.emphasis`, các tháng khác
  `ChartPalette.quiet`.
- **Chạm:** cả card là một nút mở dashboard Statistics (FS-07.01) — nơi liệt kê biểu đồ và thêm biểu đồ như cũ.
- **Bố cục:** điện thoại: số trên, biểu đồ dưới. Màn rộng (≥ 2 cột nhóm): card trải hết bề ngang trên các cột, số bên
  trái, biểu đồ bên phải — không kéo 12 cột ra cả bề ngang dưới hàng số.
- **Dữ liệu:** `StatisticsQueries.overview(months:now:calendar:)` — số ảnh hiện (cùng điều kiện ẩn với dashboard),
  số `normalizedCameraModel` và `normalizedLensModel` khác nhau, bỏ giá trị rỗng/NULL; đếm theo **tháng lịch giờ máy**
  cho 12 tháng kết thúc ở tháng hiện tại, tháng không có ảnh là 0 (không bỏ trống). Chạy ngoài luồng chính, nạp lại khi
  thư viện đổi (`assetChangeToken`); trước lần nạp đầu card giữ kích thước, chữ ở dạng placeholder.
- **VoiceOver:** một phần tử: "Statistics", giá trị "N photos, N cameras, N lenses, Busiest month ‹tháng năm›, N
  photos".
- **Test:** `ShotDexTests/StatisticsOverviewTests.swift` — đếm máy/ống bỏ rỗng, 12 tháng có số 0 và không lấy ảnh
  ngoài cửa sổ, thư viện rỗng.

## 5. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Nhóm tiêu cự của Insights (chia trong SQL) lệch mốc với nhóm góc nhìn của bộ lọc Library | dùng chung mốc của bộ lọc; test đặt ảnh đúng ở mốc 19,999 / 20 / 34,999 / 35 mm và so số câu với số lưới sau khi chạm |
| Máy đã có cờ "đã gieo" → không thấy bộ gieo 7 biểu đồ | bộ gieo có số thế hệ, hiện là 3; máy ở thế hệ cũ được thêm các biểu đồ còn thiếu vào cuối, một lần ([01](01-dashboard.md) §3) |
| Chuyển từ full sang `.limited`: bảng metadata còn giữ dòng của ảnh ngoài tập được cấp không | đo trên máy thật trong task của AC-14, trước khi viết code của nó |
| Sim không cấp được `.limited` bằng lệnh | AC-14 cần máy thật |
| Ngân sách 500 ms không có test khoá | đo tay ở `/verify` (AC-13); vượt thì mở intent mới |
