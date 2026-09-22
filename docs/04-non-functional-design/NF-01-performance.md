# NF-01 — Hiệu năng

`NF-01` · `Domain/Indexing/` · `Features/Shared/PhotoGridCollectionView.swift` · `Data/Database/`
· test `IndexDiffTests` · `GridDensityTests` · `ChunkedLookupCacheTests` · `AsyncLimiterTests` · cập nhật 2026-09-22

**Một câu:** ngân sách hiệu năng ở quy mô thư viện thật — mốc làm việc 55.000 ảnh.

## 1. Luật bắt buộc

1. **Không query database trên mỗi cell.** Lưới đọc từ snapshot đã nạp; tra cứu phụ đi qua
 cache tra cứu theo chunk / cache tra cứu theo chunk.
2. **Không decode ảnh trên main thread.** Mọi decode nằm trong service/actor.
3. **Không quét lại toàn thư viện** để trả lời "có gì mới không" — dùng change history của Photos.
4. **Không preheat ảnh full-screen theo từng cell.** Thang yêu cầu ảnh là `fast → exact → network`.
5. **Mọi pass chậm (hash, Vision, geocoding) phải**: resume được, cancel tức thì, nhường khi người dùng
   đang tương tác, và nhường theo nhiệt độ máy.
6. **Cache phải có trần** — bounded theo chunk budget, bị **thay** chứ không tích luỹ, nhả sạch khi
   memory warning.
7. Mọi `ORDER BY` kết thúc bằng tiebreaker id ảnh — thứ tự không đổi giữa hai lần chạy cùng query.

## 2. Mốc quy mô

| Đại lượng | Giá trị |
|---|---|
| Thư viện tham chiếu | **55.000** ảnh (máy thật, đo 54.968) |
| Batch index | 200 asset ([BD-03](../01-basic-design/BD-03-metadata-indexing-flow/README.md)) |
| Batch scan chủ thể (Vision) | 100, đọc song song 4 ([FS-06.04](../02-functional-spec/FS-06-collections/04-people-and-pets.md)) |
| Page size Album Detail | 120 ([FS-06.01](../02-functional-spec/FS-06-collections/01-tabs-tokens-and-album-management.md)) |

## 3. Số đã đo

| Tình huống | Số đo |
|---|---|
| Full walk PhotoKit khi **không có gì mới** | 472ms dict + 2.929ms fast-pass + 3.098ms diff = **6,8 s mỗi lần mở app** |
| Materialize 55k `PHAsset` | ~930 ms |
| Decode 55k row từ SQLite | ~350 ms — lý do pha 2 đi đường DB |
| Dựng bảng LUT film look | 3 ms (mono) → ~13 ms (look nhiều hue band), cache 24 look |
| Chi phí sàn đường iCloud | ~1 MB/ảnh dù metadata chỉ ~64 KB |

Nguồn: [BD-03](../01-basic-design/BD-03-metadata-indexing-flow/README.md),
[FS-01.01](../02-functional-spec/FS-01-library/01-photo-grid-and-data-source.md),
[FS-03.02](../02-functional-spec/FS-03-photo-editor/02-film-simulation-and-presets.md).

## 4. Ràng buộc còn treo

- **Không có cổng chặn hồi quy hiệu năng**: không benchmark trong test suite, không CI. Mọi số ở trên là
  đo tay một lần *(cần xác nhận lại với code)*.
