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
8. **Không ghi dòng không đổi.** Lượt quét lặp lại (nguồn server/folder mỗi lần app về trước mặt) chỉ ghi dòng có
   giá trị thật sự khác: `UPDATE … WHERE cột IS NOT ?`, upsert có `WHERE` ở `DO UPDATE`. "Lần đọc cuối" của nguồn là
   một cột `sources.lastListedAt` (v68), không phải `MAX(lastSeenAt)` buộc ghi mọi bản sao. *Vì* một UPDATE trúng
   dòng là ghi đĩa và đánh thức mọi observer của bảng dù giá trị y hệt — iPad 14/11: 4,3 GB ghi trong 6 giờ, app đơ
   mỗi lần mở lại. Test `ServerSourceIndexTests.unchangedPassWritesNoFileRows`.
9. **Diff thay đổi PhotoKit không chạy trên main.** `changeDetails(for:)` của cả thư viện và của từng asset đổi chạy
   trong `LibraryChangeClassifier` (hàng đợi riêng); main chỉ nhận kết quả. *Vì* backlog iCloud sau nhiều giờ
   khoá main vài giây — bấm Albums không ăn (14/11).
10. **Màn danh sách mở ngay từ cache.** Albums giữ bản danh sách lần trước trong Caches (`albums-list.json`: id,
   tên, số, id ảnh bìa) và hiện nó ngay khi khởi động lạnh, rồi đếm lại ở nền và thay. Không màn trống chờ đếm.
11. **Không đọc DB trên main khi chuyển tab hay quay lại app.** Đếm ảnh theo nguồn, bảng thumbnail file, map lưới
   55k đều chạy nền; đếm theo nguồn khi mở màn bỏ qua nếu vừa đếm < 15 s.
12. **Việc bù khi app active chạy giãn, không dồn.** Chỉ việc nhẹ (widget, Looks inbox) chạy ngay; đọc nguồn, kiểm tra
   on-server, ảnh gốc, backup, Keep in Photos chạy lần lượt sau 2 s, cách nhau 2 s, huỷ nếu app xuống nền lại.
   *Vì* trace iPad 14/11: sáu truy vấn quét toàn thư viện (0,5–0,8 s CPU mỗi cái) chạy cùng lúc trên sáu lõi ngay
   lúc app quay lại.

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
