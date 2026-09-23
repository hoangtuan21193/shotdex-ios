# FS-01 — Library

`FS-01` · tier A/B · `ShotDex/Features/Library/` · `Features/Shared/PhotoGridCollectionView.swift`
· test `GridDensityTests` · `JustifiedGridRowsTests` · `SearchParserTests` · `SearchIntentParserTests`
· `CompareLayoutTests` · cập nhật 2026-09-22

**Một câu:** tab chính của app — cả thư viện trong một lưới, tìm bằng câu tiếng Việt hoặc tiếng Anh, lọc
bằng rule, chọn hàng loạt rồi làm gì đó với chúng.

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 01 | [Nguồn dữ liệu của lưới](01-photo-grid-and-data-source.md) | `items` đến từ đâu, first paint hai pha, neo đáy, giữ chỗ đọc |
| 01b | [Engine lưới, pinch và cử chỉ](01b-grid-engine-and-gestures.md) | layout tự viết, zoom liên tục, lưới theo tỉ lệ, section, vuốt chọn, nhãn tile |
| 02 | [Nav bar và thanh điều kiện](02-navigation-and-condition-bar.md) | chrome kính, lề trên của lưới, chip điều kiện |
| 03 | [Tìm kiếm](03-search.md) | query DSL, parser câu tự nhiên, AI translator iOS 26, màn search |
| 04 | [Tìm theo địa điểm](04-place-search.md) | cột place, lưới geocode ~110m, pass riêng, giới hạn |
| 05 | [Lọc và sắp xếp](05-filtering-and-sorting.md) | Advanced Search, media type, capture kind, các trục lọc, sort |
| 06 | [Chọn nhiều ảnh](06-multi-select.md) | overlay toàn màn, vuốt chọn, context menu, bộ điều phối hành động ảnh |
| 07 | [Khôi phục trạng thái](07-state-restoration.md) | cái gì là scene state, cái gì là preference |
| 08 | [Compare](08-compare.md) | nhiều card cùng zoom, chạm để đánh dấu xoá |
| 09 | [Ghép nhiều ảnh](09-photo-stacking.md) | menu Combine Photos theo việc: focus stack, panorama, xoá người, vệt sáng, giảm nhiễu |

## Quy tắc chung

- **Một lưới ảnh dùng chung cho mọi lưới ảnh** — Library, Album Detail, Smart Album Detail,
 On This Day, màn danh sách ảnh. Không có bản SwiftUI thứ hai.
- **Mọi lưới chạy chế độ lưới phẳng** — ngày đi lên title, không chèn dòng ngày dính vào lưới.
  On This Day là ngoại lệ (`.custom`) vì section của nó là "cùng ngày qua các năm".
- **Grid không được nhảy**: mọi reload giữ chỗ đọc, trừ bốn ca nêu ở [01](01-photo-grid-and-data-source.md).
- **Ảnh hiện trước, metadata điền sau** — index chạy nền chỉ để bơm overlay, filter và sort metric.
- Chức năng trên iPhone và iPad **giống hệt nhau**; màn rộng cho **nhiều nội dung hơn**, không phải nội
  dung to hơn ([NF-05](../../04-non-functional-design/NF-05-device-and-os-compatibility.md)).

## Đã gỡ

**Cull** (rating 0–5, cờ pick/reject) đã gỡ hoàn toàn: bảng `photo_cull` bị drop ở `v16`. Ảnh đã mang
**favorite của PhotoKit** — một bit, đồng bộ sang Photos, người dùng đã có sẵn; cờ pick/reject là trục thứ
hai trả lời cùng câu hỏi và sao 0–5 là trục thứ ba. ShotDex giữ đúng cái Photos giữ, còn việc *chọn* thì
Compare làm. Luật migration rút ra: [BD-02 §4](../../01-basic-design/BD-02-database-design.md).

## Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
