# FS-07 — Statistics

`FS-07` · tier A · `ShotDex/Features/Statistics/` · `Data/Database/StatisticsQueries.swift` · `ChartStore`
· test `ChartDashboardTests` · `StatsDateScopeTests` · cập nhật 2026-10-01

**Một câu:** tab Statistics — một thẻ **Insights** nói bằng lời thói quen chụp của người dùng, rồi bên dưới là
dashboard biểu đồ do người dùng tự dựng; chạm vào đâu cũng mở Library lọc sẵn.

Nguồn: [intent 2026-09-30, mục 5](../../_intents/2026-09-30-user-wishes-research.md). Hướng đã ghi ở
[OV-01 §3](../../00-overview/OV-01-product-goals-and-scope.md) ("nhận xét cá nhân hoá", "tổ hợp body+lens ưa dùng").

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 01 | [Dashboard biểu đồ](01-dashboard.md) | đặc tả biểu đồ, lưu trữ, thẻ, ô soạn, khoảng thời gian, bố cục cột |
| 02 | [Insights](02-insights.md) | danh mục câu, ngưỡng, lời văn, tiêu cự tương đương, thẻ, ẩn, hiệu năng |
| 03 | [Tiêu chí nghiệm thu](03-acceptance-criteria.md) | AC-1…18 |

## 1. Người dùng cần gì

Người chụp muốn biết mình **thật sự** chụp tiêu cự nào, hay cầm cặp body + lens nào, bao nhiêu ảnh chụp chậm,
tháng nào chụp nhiều. Hôm nay họ phải tự dựng biểu đồ mới thấy; người không dùng ShotDex thì tự viết script
exiftool. Lần đầu mở Statistics phải trả lời ngay, bằng lời, từ chính ảnh của họ.

## 2. Phạm vi

**Có:**
- dashboard biểu đồ tự dựng (FS-07.01), lần đầu gieo 6 biểu đồ trả lời các câu ở §1;
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

## 4. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Dải tiêu cự của Insights (chia trong SQL) lệch mốc với biểu đồ phân bố (chia trong Swift) | test đặt ảnh đúng ở mốc 20, 27,99, 28 mm và so hai đường |
| Máy dev đã có cờ "đã gieo" → không thấy bộ gieo 6 biểu đồ | app chưa release; xoá app hoặc xoá bảng biểu đồ trên máy dev |
| Chuyển từ full sang `.limited`: bảng metadata còn giữ dòng của ảnh ngoài tập được cấp không | ❓ chưa đọc tới — kiểm ở `/plan` với BD-03 |
| Sim không cấp được `.limited` bằng lệnh | AC-14 cần máy thật |
| Ngân sách 500 ms không có test khoá | đo tay ở `/verify` (AC-13); vượt thì mở intent mới |
