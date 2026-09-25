# FS-06 — Collections

`FS-06` · tier A/B · `ShotDex/Features/Albums/` · `Features/Duplicates/` · `Domain/Places/`
· `Domain/Duplicates/` · `Domain/OnThisDay/` · cập nhật 2026-09-22

**Một câu:** tab thứ hai — album, bản đồ, chuyến đi, ảnh trùng, ngày này năm xưa, và những bộ lọc người
dùng tự lưu.

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 01 | [Bố cục tab](01-tabs-tokens-and-album-management.md) | hàng hero, tile cover, Media Types, Utilities, Customize, Pinned |
| 01b | [Album Detail, quản lý và Creations](01b-album-management-and-creations.md) | paging, sort theo album, rename/delete, Collages + Video Projects, kéo thả |
| 02 | [Places](02-places-map.md) | gom cụm theo lưới độ, nhãn pin |
| 03 | [Memories và dựng phim](03-memories-and-movie-builder.md) | màn danh sách ảnh, bộ dựng memory, nút film |
| 04 | [People and Pets](04-people-and-pets.md) | pass Vision opt-in — chỉ đếm, không nhận diện |
| 05 | [Trips](05-trips.md) | định nghĩa "nhà", khoảng hở, gộp chuyến |
| 06 | [Duplicates](06-duplicates.md) | perceptual hash, ba mức, cache, merge, xoá |
| 07 | [On This Day](07-on-this-day.md) | hero, màn chi tiết, reminder 7 ngày |
| 08 | [Smart Album](08-smart-albums.md) | model rule, editor, compile SQL, tương thích ngược |
| 09 | [Menu Filter trong album](09-album-filter-menu.md) | Filter/Sort giống Library ở Album Detail và Smart Album, Advanced trong album |

## Quy tắc chung

- **Tab này liệt kê album** — không vẽ Folders, không vẽ số đếm trên tile.
- Thứ **nhận ra bằng ảnh** thì làm tile cover; thứ **chọn từ danh sách biết trước** thì làm hàng.
- Mọi thứ đắt (quét Vision, hash, geocode) là **pass riêng người dùng tự bấm**, resume được, cancel được —
  không bao giờ nằm trong index pass.
- App **không đoán hộ**: Memories chỉ dựng từ chuyến đi / năm / nơi; Duplicates không tự chọn tấm nào xoá;
  People and Pets chỉ đếm.
- Lưới trong mọi màn con là lưới ảnh dùng chung dùng chung
  ([FS-01](../FS-01-library/README.md)).

## Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
