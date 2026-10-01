# FS-07.03 — Tiêu chí nghiệm thu

`FS-07.03` · `ShotDexTests/StatisticsInsightsTests.swift` (mới) · `ShotDexTests/ChartDashboardTests.swift`
· `ShotDexUITests/scripts/statistics-*.json` (mới) · cập nhật 2026-10-01

**Một câu:** 18 tiêu chí cho thẻ Insights, điều kiện *trong tháng* và lần đầu mở Statistics; dashboard biểu đồ
(FS-07.01) chưa có AC riêng ngoài bộ gieo.

Dữ liệu dựng trên database trong bộ nhớ. "Ảnh" là ảnh tĩnh có tên máy, trừ khi ghi khác.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | thư viện đã cấp quyền, index xong, 0 dòng | mở Statistics | "No Indexed Photos"; không có thẻ Insights, không có biểu đồ | ⚠️ chưa có |
| AC-2 | 49 ảnh có tên máy + 200 ảnh chụp màn hình không EXIF + 30 video | tính Insights | 0 câu; thẻ có đúng một dòng "Insights appear once 50 photos have camera info — 49 so far." | ⚠️ chưa có |
| AC-3 | 1.000 ảnh iPhone 13 Pro: 850 ở 26 mm tương đương (mô-đun chính), 150 ở 77 mm (tele) | tính Insights | câu đầu "85% of your photos are at 26 mm equivalent."; bộ lọc đi kèm = tiêu cự tương đương 25,5–26,5 mm | ⚠️ chưa có |
| AC-4 | X-T5: 300 ảnh 23 mm thật / 35 mm tương đương, 100 ảnh 33 / 50; thêm 100 ảnh 23 mm của một máy chưa biết cảm biến | tính Insights | câu tiêu cự nêu **35 mm**, không nêu 23 mm; tỉ lệ 75% trên mẫu số 400; dùng biến thể nêu mẫu số vì 400/500 = 80% < 90% | ⚠️ chưa có |
| AC-5 | 1.000 ảnh có máy + ống: 420 iPhone 15 Pro + mô-đun 6.765mm, 180 iPhone 15 Pro + mô-đun 9mm, 400 EOS R6 + RF 85mm F1.2 L USM | tính Insights | câu cặp là "EOS R6 with RF 85mm F1.2 L USM took 40% of your photos." — hai mô-đun iPhone là hai cặp, không gộp thành 60% | ⚠️ chưa có |
| AC-6 | 500 ảnh có tốc độ + tiêu cự tương đương 50 mm: 90 ảnh 1/15 s, 410 ảnh 1/250 s | tính Insights | câu "18% of your photos were shot slower than 1/focal length.", không có mũi tên, VoiceOver không đọc là nút; đổi thành 20 ảnh 1/15 s + 480 ảnh 1/250 s (4%) thì không có câu | ⚠️ chưa có |
| AC-7 | số đã gom đưa thẳng vào luật chọn: tiêu cự 85% ở 26 mm · cặp đầu 40% · chụp chậm 18% · tháng 08/2026 có 1.240 ảnh, trung vị 300 | chạy luật chọn hai lần | đúng 3 câu, thứ tự tiêu cự → cặp → chụp chậm; không có câu tháng bận nhất; hai lần cho danh sách giống hệt | ⚠️ chưa có |
| AC-8 | mọi mẫu câu, với số đếm 1 và 2, phần trăm 99,6 và 100 | dựng chuỗi | "1 photo" / "2 photos" từ biến thể plural; 99,6% ghi "99%"; không chuỗi nào chứa từ trong danh sách cấm (§4) | ⚠️ chưa có |
| AC-9 | dữ liệu AC-3 trên simulator | chạm câu tiêu cự | sang tab Library, bộ lọc tiêu cự tương đương 25,5–26,5 mm đang bật, lưới đếm 850 ảnh | ⚠️ chưa có |
| AC-10 | 200 ảnh có tiêu cự thật, 180 trong số đó của máy chưa biết cảm biến | tính Insights | không có câu tiêu cự; chân thẻ "180 photos are from cameras with an unknown sensor size."; chạm mở Settings → Unknown Cameras | ⚠️ chưa có |
| AC-11 | cài mới, dữ liệu AC-3, chưa từng gieo | mở Statistics | thẻ Insights ở trên cùng; bên dưới đúng 6 biểu đồ theo thứ tự Top Camera · Total Photos & Videos · Equivalent Focal Length · Body + Lens · Slow Shutter · Photos per Month (3 chuỗi thân máy) | ⚠️ chưa có — `ChartDashboardTests.seedDefaultsAreTopCameraAndTotal` đang khoá 2 biểu đồ, phải sửa |
| AC-12 | 1.000 ảnh EOS R6: 600 với RF 50mm F1.2 L USM (150 ảnh 1/15 s, còn lại 1/250 s), 400 với RF 85mm F1.2 L USM ở 1/250 s; rải đều 10 tháng → đúng 3 câu; iOS 26.5 và 18.6 | mở Statistics trên iPhone 402×874, iPad 13" ngang, iPad 11" dọc, Duo trong 951×669 | Insights trên mọi biểu đồ, trải hết bề rộng; câu xếp 1 cột ở iPhone, 3 ở iPad 13" ngang, 2 ở 11" dọc và Duo trong; Duo trong thấy ≥ 120pt thẻ biểu đồ đầu; cùng 3 nhãn câu ở mọi máy, cả hai nhánh iOS | ⚠️ chưa có — cần script ui-drive + `Tools/sim-shot` cho iPad và Duo |
| AC-13 | 55.000 dòng: 40.000 iPhone ở 3 mô-đun, 10.000 EOS R6 ở 4 ống, 3.000 không EXIF, 2.000 video | tính Insights | cả lượt ≤ 500 ms, ngoài luồng chính; không truy vấn nào trả về quá 500 dòng | ⚠️ chưa có — đo tay trong `/verify`, ghi số đo vào báo cáo verify |
| AC-14 | quyền `.limited`, 312 ảnh được cấp: 265 ở 26 mm tương đương, 47 ở 77 mm | mở Statistics | câu "85% of your photos are at 26 mm equivalent."; chân thẻ "Based on 312 photos you've shared with ShotDex" + Manage mở bộ chọn ảnh của hệ thống | ⚠️ chưa có — sim không cấp được `.limited` bằng lệnh; cần máy thật |
| AC-15 | AC-11 vừa gieo 6 biểu đồ | xoá lần lượt cả 6, rồi mở lại app | mỗi biểu đồ xoá được bằng menu Delete; còn "No Charts" và thẻ Insights; mở lại app vẫn 0 biểu đồ, không gieo lại | ⚠️ chưa có |
| AC-16 | dữ liệu AC-3, thẻ Insights đang hiện | chọn Hide Insights trong menu của thẻ, mở lại app, rồi bật Settings → Display → Show Insights | thẻ biến mất, biểu đồ đầu lên trên cùng; mở lại app vẫn ẩn; bật Show Insights thì thẻ quay lại với cùng câu | ⚠️ chưa có |
| AC-17 | 2.140 ảnh không ghi ống, không ghi tiêu cự: 06/2026 có 300, 07/2026 280, 08/2026 1.240, 09/2026 320 | mở Statistics, chạm câu tháng bận nhất | câu "August 2026 was your busiest month: 1,240 photos." có mũi tên; sang Library, điều kiện *trong tháng* August 2026 đang bật, lưới đếm 1.240 ảnh | ⚠️ chưa có |
| AC-18 | dữ liệu AC-17 | tạo smart album có điều kiện *trong tháng* August 2026 | album đếm 1.240 ảnh; đổi sang July 2026 thì 280 | ⚠️ chưa có |

**Chưa chứng minh được:** AC-1…18 — tất cả. Test đã có chỉ chạm phần lân cận: `DatabaseTests.statsAggregates`
(tổng hợp và dải tiêu cự tương đương), `ChartDashboardTests.binnedIsoHistogram` (chia dải). Không cái nào khoá câu Insights.
