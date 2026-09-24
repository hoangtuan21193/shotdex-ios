# FS-14 — Ghép panorama

`FS-14` · tier D · `ShotDex/Features/Editing/` (màn mới, **không** trùng tên `PanoramaScreen` của viewer)
· `ShotDexKit/Render/` (bộ ghép) · test `ShotDexTests/Panorama*Tests.swift` · cập nhật 2026-09-23

**Một câu:** chọn một chuỗi khung chồng mép, ⋯ → **Combine Photos ▸ Panorama**, nhận một ảnh panorama mới trong
thư viện; ảnh gốc không bị đụng.

Nguồn: [intent](../../_intents/2026-09-23-panorama-stitch-from-selection.md) ·
[spike](../../_intents/2026-09-23-panorama-stitch-spike.md) (mọi con số "đo được" dưới đây lấy từ đó).

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 01 | [Màn hình và luồng](01-screen-and-flow.md) | lối vào, trạng thái, panel, sắp khung tay, lưu, lỗi |
| 02 | [Đường ghép](02-stitching-pipeline.md) | căn ảnh, giải camera, chiếu, bù sáng, trộn, warp, xuất file |

## 1. Người dùng cần gì

Người chụp máy rời xoay máy bấm 3–15 khung (có khi 2–3 hàng) rồi phải mang sang máy tính để ghép.
Họ cần ghép ngay trong thư viện, chất lượng ngang Lightroom Photo Merge, ra một tấm vẫn mang tên máy
và ống kính đã chụp để lọc và thống kê không lạc mất nó.

## 2. Phạm vi

**Có:** một hàng ngang hoặc dọc, lưới nhiều hàng, vòng 360° · ba phép chiếu Spherical / Cylindrical /
Perspective · Boundary Warp 0–100 · Auto Crop · bù sáng giữa khung · tự dò thứ tự và vị trí, sửa tay
khi dò sai · không trần số khung, không trần kích thước (Size 25–100%, mặc định 100%, kèm ước lượng px/MP/MB/thời gian) · ảnh ghép là "panorama" ở viewer, bộ lọc, bộ sưu tập.

**Cố ý không có:**
- Fill Edges (lấp mép bằng nội dung bịa) — không nằm trong câu 6 của intent; là ảnh do app vẽ ra.
- Ghép HDR — chuyện của intent Lightroom parity, câu 4.
- **Giữ HDR gain map của khung gốc** (bỏ 2026-09-23, sau khi đo). Ảnh ghép ra là **SDR**; không gian
  màu vẫn là Display P3 khi có khung P3. Lý do là một con số, không phải một ưu tiên: gắn dữ liệu phụ
  vào bộ ghi JPEG làm bộ nhớ tăng **theo số pixel ảnh chính** — +92 MB ở 24 MP, +369 MB ở 96 MP,
  **+1 230 MB ở 300 MP** — nên cái ghi-theo-luồng mà cả tính năng dựa vào biến mất đúng ở cỡ ảnh mà
  tính năng này sinh ra để phục vụ. Hệ quả người dùng thấy: panorama ghép từ ảnh iPhone HDR trông
  nhạt hơn ảnh gốc khi xem cạnh nhau.
- Lối vào trong Edit extension — trần ~120 MB ([NF-02](../../04-non-functional-design/NF-02-memory-and-resources.md)).
- Điểm khống chế tay kiểu PTGui — sửa tay chỉ ở mức kéo cả khung ([01 §5](01-screen-and-flow.md)).

## 3. Dữ liệu

| | |
|---|---|
| Đọc từ | PhotoKit: bản render hiện tại của từng khung (đã gồm chỉnh sửa), tải từ iCloud khi cần |
| Ghi vào | **một asset mới** qua đường lưu ảnh mới, từ **file trên đĩa** — không qua bộ nhớ |
| Database | thêm **một cột** `photo_metadata.isPanorama` ở `v18-panoramaFlag` — cờ hệ thống **hoặc** thẻ XMP của ShotDex, một câu trả lời cho viewer, bộ lọc và bộ sưu tập (§7 của [01](01-screen-and-flow.md)); ảnh mới được index như mọi ảnh ([BD-03](../../01-basic-design/BD-03-metadata-indexing-flow/README.md)) |
| Người dùng tự nhập? | không — vị trí khung sửa tay chỉ sống trong phiên, không lưu |

## 4. Ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Phụ thuộc | không thêm thư viện; chỉ Vision, Core Image, Accelerate, Metal, ImageIO |
| Bộ nhớ | footprint **không tăng theo kích thước đầu ra** — render theo dải ([02 §6](02-stitching-pipeline.md)) |
| Kit | phần ghép nằm trong ShotDexKit, không import SwiftUI/GRDB ([EX-01](../../03-extensions-and-integrations/EX-01-shotdexkit-and-edit-extension.md)) |
| Thiết bị | iPhone 402×874 · iPad 1376×1032 · Duo trong 951×669 · Duo ngoài 466×678 — cùng một bộ chức năng |
| iOS 26 vs trước | hai nhánh làm được cùng một việc |
| Riêng tư | local-only, không ảnh nào rời máy ([NF-03](../../04-non-functional-design/NF-03-privacy-and-security.md)) |
| Truy cập | nhãn VoiceOver cho mọi khung trên stage và mọi control tự vẽ |

## 5. Tiêu chí nghiệm thu

Bộ khung thử `s1…s8` là khung ảo có đáp án dựng từ ảnh 360° CC0 như trong spike (§1 của spike);
test dựng chúng từ một ảnh 360° nhỏ đóng trong test bundle. "Thời gian" và "footprint" đo trên
**iPhone 17 thật**, bản Release.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | chọn 1 ảnh + 2 video | mở ⋯ → Combine Photos | dòng Panorama hiện nhưng mờ (cần ≥ 2 ảnh) | ⚠️ chưa có — `panorama-entry.json` |
| AC-2 | chọn 6 ảnh s1 + 1 video | ⋯ → Combine Photos ▸ Panorama | màn mở với **6** khung, video bị bỏ, tiêu đề ghi 6 | ⚠️ chưa có — `panorama-entry.json` |
| AC-3 | s1, s2, s3, s6 (thứ tự chọn xáo) | ghép | mọi khung vào panorama; xoay tương đối lệch ≤ 0,1° so với đáp án; đổi thứ tự chọn ra cùng kết quả | ⚠️ chưa có — `PanoramaSolverTests` |
| AC-4 | s5: 5 khung một cảnh + 1 ảnh khác cảnh | ghép | 5 khung vào panorama; ảnh lạc nằm ở dải **Not Placed (1)**; không cặp nào ghép nhầm | ⚠️ chưa có — `PanoramaRegistrationTests` |
| AC-5 | 2 ảnh không chồng mép | ghép | không có preview; thông báo nói khung phải chồng nhau ~30% · Save mờ | ⚠️ chưa có — `PanoramaRegistrationTests` + ảnh |
| AC-6 | một khung ở Not Placed, thả lệch chỗ đúng ≤ 20% bề rộng khung | kéo thả lên stage | khung được căn lại với khung kề, lệch ≤ 1 px ở ảnh 1024; rời Not Placed | ✅ `PanoramaArrangeTests` (8 test; thả lệch 20% về đúng chỗ ≤ 1 px) + ảnh iPhone 17 Pro: kéo khung ra (2,236 → 1,716 px), kéo từ dải trở lại (về 2,236 px), thả chỗ không khớp thì ảnh giữ nguyên và báo lý do |
| AC-7 | s1 (tổng ~260° ngang) | mở panel phép chiếu | Spherical, Cylindrical bật; Perspective mờ kèm một dòng lý do | ⚠️ chưa có — `PanoramaRenderTests` + ảnh |
| AC-8 | s4 (cột dọc 4 khung) | ghép Cylindrical | ảnh ra cao hơn rộng; phần có ảnh ≥ 90% khung bao | ⚠️ chưa có — `PanoramaRenderTests` |
| AC-9 | s1, gain từng khung 0,8–1,25 | ghép | chênh sáng trung bình hai bên mỗi đường nối ≤ 2% | ⚠️ chưa có — `PanoramaRenderTests` |
| AC-10 | s2, Auto Crop bật, Boundary Warp 0 | Save | ảnh ra không có pixel trống; diện tích ≥ 80% vùng có ảnh | ⚠️ chưa có — `PanoramaRenderTests` |
| AC-11 | s2, Boundary Warp 100 | Save | ảnh ra chữ nhật, 0 pixel trống; mọi đoạn thẳng ≥ 200 px của cảnh cong ≤ 3 px | ⚠️ chưa có — `PanoramaRenderTests` |
| AC-12 | s2 ở 6000×4000/khung (10 × 24 MP) | Save | JPEG ở độ phân giải gốc; footprint đỉnh ≤ 500 MB; xong ≤ 120 s | ⚠️ chưa có — đo tay + `PanoramaExportTests` |
| AC-13 | 10 khung cùng máy, cùng ống kính, phơi sáng khác nhau | Save rồi index xong | ảnh mới mang máy, ống kính, ngày, vị trí của khung đầu; không có tốc độ/khẩu/ISO; hiện khi lọc theo máy đó | ⚠️ chưa có — `PanoramaMetadataTests` |
| AC-14 | 3 khung chỉ có trên iCloud, máy mất mạng | ghép | thông báo "3 photos couldn't be downloaded" + Retry; không lưu gì | ⚠️ chưa có — ảnh (sim, mạng tắt) |
| AC-15 | đang lưu ở 60% | Cancel | thư viện không thêm ảnh; thư mục tạm của phiên rỗng | ⚠️ chưa có — `PanoramaExportTests` |
| AC-16 | s8 (méo thùng, không có hồ sơ ống kính) | ghép | hệ số méo ước lượng lệch ≤ 0,01; xoay lệch ≤ 0,2° | ⚠️ chưa có — `PanoramaSolverTests` |
| AC-17 | panorama ShotDex vừa lưu, và một ảnh crop 21:9 | mở ⋯ trong viewer từng ảnh | panorama có View Panorama; ảnh 21:9 không có | ⚠️ chưa có — `panorama-viewer.json` |
| AC-18 | quyền `.limited` | Save | ảnh mới hiện trong lưới Library | ⚠️ chưa có — ảnh (sim, limited) |
| AC-19 | Save thành công | xong lưu | màn đóng, chế độ chọn tắt, viewer mở đúng ảnh vừa lưu | ⚠️ chưa có — `panorama-save.json` |
| AC-20 | đang lưu ở 30% | về màn hình chính 60 s rồi quay lại | lưu chạy tiếp, không bắt đầu lại; ra đúng 1 asset | ⚠️ chưa có — máy thật, iOS 26 và 18 |
| AC-21 | 1 panorama ShotDex + 1 panorama Camera trong thư viện | mở bộ sưu tập Panoramas, rồi lọc Capture Kind → Panoramas | cả hai ảnh có mặt ở cả hai chỗ | ⚠️ chưa có — `PanoramaMetadataTests` + ảnh |
| AC-22 | chọn 120 khung | ⋯ → Combine Photos ▸ Panorama | ước lượng thời gian hiện trước khi ghép; Cancel đóng màn, không làm gì | ⚠️ chưa có — ảnh |
| AC-25 | s2 ghép xong, Size 100% ghi `W × H px` | kéo Size về 50% | dòng ước lượng ghi `round(W/2) × round(H/2)` (±1 px), MP còn ¼; ảnh lưu ra đúng kích thước đó | ✅ `PanoramaSizeEstimateTests` (9 test) + ảnh iPhone 17 Pro: 100% `2,236 × 796 px · 1.8 MP · ~176 KB · ~2s`, 46% `1,025 × 365 px · 0.4 MP · ~37 KB · ~1s` |
| AC-26 | dung lượng trống 500 MB, ảnh ra ước ~2 GB tạm + ảnh | mở panel | dòng ước lượng báo thiếu và thiếu bao nhiêu; Save mờ | ⚠️ một nửa — luật có (`DiskSpace` + `PanoramaSizeEstimator.requiredFreeBytes`, `canSave` tắt khi thiếu) và test phần tính; **câu trên màn chưa chụp được**: simulator còn 11 GB trống và panorama thử chỉ 176 KB, cần máy gần đầy hoặc chuỗi khung lớn |
| AC-27 | panel đang hiện đủ 5 mục | mở trên Duo trong (951×669) và iPhone (402×874) | không mục nào bị cắt, stage còn ≥ 50% chiều cao màn | ⚠️ chưa có — `panorama-panel.json` + `Tools/sim-shot` |
| AC-28 | s2 đã ghép, preview nét đang hiện | kéo Boundary Warp 0 → 100 trong 2 s | preview đổi theo tay ≥ 15 khung/giây; thả tay ≤ 1,5 s có bản nét; mép bản nháp và bản nét lệch ≤ 2 px (ở 1536) | ⚠️ chưa có — `PanoramaRenderTests` (hình học) + đo tay máy thật |
| AC-29 | s1, preview nét đang hiện | chạm Cylindrical | ≤ 150 ms có bản nháp Cylindrical; không chạy lại bước căn ảnh | ⚠️ chưa có — `PanoramaRenderTests` + đo tay |
| AC-23 | s1, một người có mặt ở vùng chồng của khung 2 nhưng không có ở khung 3 | ghép | người đó hiện trọn vẹn hoặc không hiện; không vết cắt đôi, không hai bản | ✅ `PanoramaSeamTests` (buffer) + `PanoramaSeamBlendTests.theJoinGoesRoundTheFigureRatherThanThroughIt` (trên canvas, có kiểm chứng test cắn) + ảnh iPhone 17 Pro: chuỗi 3 khung mượt, không bậc |
| AC-24 | 3 khung iPhone HDR (P3 + gain map) + 1 khung SDR | Save | ảnh ra **P3 và SDR**, không có gain map | ✅ `PanoramaExportTests` — tiêu chí đã đổi 2026-09-23: giữ gain map là **không làm được**, xem §2 |

**Chưa chứng minh được:** cả 29 — chưa có dòng code nào. Thời gian và footprint (AC-12, AC-28, AC-29) là **mục tiêu đề xuất**,
spike chỉ đo trên Mac.

## 6. Quyết định

Đã chốt 2026-09-23: luôn JPEG · vượt 65535 px thì thu nhỏ và báo trước · vào nền vẫn lưu tiếp + màn luôn
sáng · lưu xong mở ảnh trong viewer · màn rộng dùng cột phải · "panorama" = cờ hệ thống hoặc thẻ XMP của
ShotDex, cho cả viewer, bộ lọc và bộ sưu tập · không trần số khung, trên 50 thì báo ước lượng thời gian ·
P3 khi có khung P3, ảnh ra SDR (gain map: xem §2) · đường nối tránh vật chuyển động · AC-12 là mục tiêu, chốt ở `/verify` · Size là slider 25–100% trong panel, một dòng ước lượng px · MP · MB · thời gian · preview hai tầng: nháp khi kéo, nét khi thả.
**Không còn câu treo.**

## 7. Tài liệu phải sửa khi Build

- [FS-01.06](../FS-01-library/06-multi-select.md) — menu con Combine Photos (theo intent menu mục đích, làm trước FS-14).
- [FS-02.04 §8](../FS-02-photo-detail/04-actions-and-extras.md) — View Panorama theo định nghĩa mới (cờ hệ thống hoặc thẻ ShotDex).
- [FS-01.05](../FS-01-library/05-filtering-and-sorting.md), [FS-06.01](../FS-06-collections/01-tabs-tokens-and-album-management.md) — Panoramas lấy từ index, không từ album của Photos.
- [BD-03](../../01-basic-design/BD-03-metadata-indexing-flow/README.md) — indexer đọc thẻ panorama XMP.
- `DESIGN.md` §10.3b — thêm một dòng cho màn này.

## 8. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Khung thử không có thị sai, vật chuyển động → spike lạc quan | `/verify` chạy thêm trên chuỗi chụp tay thật |
| ~~PhotoKit có thể từ chối JPEG 200–700 MP~~ | **đã đo, không từ chối**: 300 MP (30 000 × 10 000, 110,9 MB) vào thư viện qua đường file, `PHAsset` trả đúng kích thước (`PanoramaLibrarySaveTests`) |
| ~~Ghi JPEG kèm gain map có thể không còn ghi theo luồng~~ | **đã đo, đúng như lo**: +1 230 MB ở 300 MP. Gain map bị bỏ khỏi phạm vi (§2) |
| Đường nối tránh vật chuyển động chưa đo chi phí | đo ở `/plan`; AC-23 là cổng |
| Spike dựng preview 8 MP mất 1–2 s trên CPU Mac — chưa đạt 15 khung/giây | bản nháp phải chạy GPU (Core Image/Metal); `/plan` đo trước tiên |
| Boundary Warp giữ đường thẳng chưa viết lần nào (spike chỉ có bản không có ràng buộc đường thẳng) | làm sau cùng; AC-11 là cổng |
| So mọi cặp là n²/2 — 120 khung = 7140 cặp; không trần số khung | lọc cặp ứng viên bắt buộc trên 12 khung ([02 §1](02-stitching-pipeline.md)) |
