# FS-01 — Library

`FS-01` · tier A/B · `ShotDex/Features/Library/` · `Features/Shared/PhotoGridCollectionView.swift`
· test `GridDensityTests` · `JustifiedGridRowsTests` · `SearchParserTests` · `SearchIntentParserTests`
· `CompareLayoutTests` · cập nhật 2026-10-02

**Một câu:** tab chính của app — cả thư viện trong một lưới, tìm bằng câu tiếng Việt hoặc tiếng Anh, lọc
bằng rule, chọn hàng loạt rồi làm gì đó với chúng.

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 01 | [Nguồn dữ liệu của lưới](01-photo-grid-and-data-source.md) | `items` đến từ đâu, first paint hai pha, neo đáy, giữ chỗ đọc |
| 01b | [Engine lưới, pinch và cử chỉ](01b-grid-engine-and-gestures.md) | layout tự viết, zoom liên tục, lưới theo tỉ lệ, section, vuốt chọn, nhãn tile |
| 02 | [Nav bar và thanh điều kiện](02-navigation-and-condition-bar.md) | chrome kính, lề trên của lưới, chip điều kiện |
| 03 | [Tìm kiếm](03-search.md) | query DSL, parser câu tự nhiên, AI translator iOS 26, màn search |
| 03b | [Khung giờ, từ không hiểu, Recents màn rộng](03b-time-of-day-and-acceptance.md) | night/golden/blue hour, chip mời tìm tên file, dòng Try:, Recents regular; AC của tìm kiếm |
| 03c | [Search kiểu Photos](03c-search-like-photos.md) | chỉ mục giá trị + FTS5, dòng gợi ý có số ảnh, viên lọc, kết quả trong Search, ngày/mùa/thứ, Did you mean, Mac |
| 04 | [Tìm theo địa điểm](04-place-search.md) | cột place, lưới geocode ~110m, pass riêng, giới hạn |
| 05 | [Lọc và sắp xếp](05-filtering-and-sorting.md) | Advanced Search, media type, capture kind, các trục lọc, sort |
| 05b | [Camera/Lens, dữ liệu thiếu, sheet](05b-gear-menu-missing-data-and-sheet.md) | menu Camera ▸ Lens ▸, is missing + Location, bố cục và nháp Advanced Search; AC |
| 06 | [Chọn nhiều ảnh](06-multi-select.md) | overlay toàn màn, vuốt chọn, context menu, bộ điều phối hành động ảnh |
| 07 | [Khôi phục trạng thái](07-state-restoration.md) | cái gì là scene state, cái gì là preference |
| 08 | [Compare](08-compare.md) | chọn ≥2 ảnh → màn A/B của Duplicates, Keep \| Delete, Delete N |
| 08c | [Compare là chế độ của Viewer](08c-compare-viewer-mode.md) | **đã bỏ 2026-10-24** — lịch sử |
| 09 | [Ghép nhiều ảnh](09-photo-stacking.md) | menu Combine Photos: Focus Stack · Panorama · Stack Exposures (Average/Lighten/Darken) |
| 10 | [Focus Stack](10-focus-stack.md) | căn có co giãn, hai cách ghép, Radius/Smoothing, tô sửa từ một khung |
| 11 | [HDR](11-hdr-merge.md) | loạt bù trừ sáng → một ảnh: radiance từ RAW, căn khung, khử bóng ma bốn mức, Strength |
| 12 | [Sao và cờ](12-rating-and-flags.md) | sao 0–5 (Photos từ iOS 27, bảng riêng trước đó), cờ Pick/Reject, glyph ô, phím, lọc, smart album |
| 12b | [Lượt lọc (Cull)](12b-culling-pass.md) | đi từng tấm bằng chạm/phím/vuốt, undo, thẻ tóm tắt, Delete Rejected |

## Quy tắc chung

- **Một lưới ảnh dùng chung cho mọi lưới ảnh** — Library, Album Detail, Smart Album Detail,
 On This Day, màn danh sách ảnh. Không có bản SwiftUI thứ hai.
- **Mọi lưới chạy chế độ lưới phẳng** — ngày đi lên title, không chèn dòng ngày dính vào lưới.
  On This Day là ngoại lệ (`.custom`) vì section của nó là "cùng ngày qua các năm".
- **Grid không được nhảy**: mọi reload giữ chỗ đọc, trừ bốn ca nêu ở [01](01-photo-grid-and-data-source.md).
- **Ảnh hiện trước, metadata điền sau** — index chạy nền chỉ để bơm overlay, filter và sort metric.
- Chức năng trên iPhone và iPad **giống hệt nhau**; màn rộng cho **nhiều nội dung hơn**, không phải nội
  dung to hơn ([NF-05](../../04-non-functional-design/NF-05-device-and-os-compatibility.md)).

## Sao, cờ và favorite — ba câu hỏi khác nhau

- **Favorite** = "tấm tôi thích". Một bit của Photos, đồng bộ iCloud.
- **Cờ Pick/Reject** = quyết định giữ hay bỏ của một lượt lọc sau buổi chụp. Chỉ ShotDex có, nằm trên máy.
- **Sao 0–5** = thứ hạng giữa các tấm giữ. Từ iOS 27 nó là sao của chính Photos, nên đi theo ảnh sang Mac.
- Ba trục không tự kéo nhau: Pick không bật favorite, Reject không xoá. Luật lưu ở [12](12-rating-and-flags.md) §4.
- Vì sao đưa lại sau khi đã gỡ ở `v16`: người dùng chốt 2026-09-30 rằng người chụp cần lọc nhanh sau buổi chụp,
  và iOS 27 cho sao một chỗ ở trong Photos, nên sao không còn là trục riêng của app.

## Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ). Sao, cờ và lượt lọc có AC riêng ở
[12](12-rating-and-flags.md) §9 và [12b](12b-culling-pass.md) §6.
