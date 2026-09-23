# FS-10 — Import (đã bỏ)

`FS-10` · đã bỏ · cập nhật 2026-09-24 · nguồn
[intent](../_intents/2026-09-21-remove-import-entry-point.md)

**Một câu:** ShotDex **không có màn Import**. Ảnh vào máy bằng Photos (thẻ nhớ qua Photos, AirDrop, cáp,
iCloud) hoặc qua Share sheet ([EX-03](../03-extensions-and-integrations/EX-03-share-extension.md)); ShotDex
index những gì đã có trong thư viện.

> Trạng thái: **spec, chưa build** (2026-09-24). Hôm nay "Import Photos" vẫn là một hàng trong Settings →
> Photo Library, mở màn nhập từ folder ngoài có lọc RAW.

## 1. Vì sao bỏ

Settings là nơi chỉnh cách app cư xử; Import là một hành động lên thư viện, đứng lạc giữa các công tắc index.
Người dùng chốt: ShotDex là app **đọc** thư viện ảnh của hệ thống, không phải app quản lý file — một lối Import
riêng tạo cảm giác ShotDex có kho ảnh riêng, mà nó không có. Không thay bằng lối vào nào khác (menu ⋯ của
Library và nút ở Collections đều đã bị bác).

## 2. Cái gì ra đi, cái gì ở lại

| Ra đi | Vì chỉ Import dùng |
|---|---|
| Hàng **Import Photos** và `fullScreenCover` của nó trong `SettingsScreen`, case `.importPhotos` của `SettingsRowLabel` | lối vào duy nhất |
| `Features/Import/` (`ImportScreen`, `ImportModel`) | chỉ Settings mở |
| `Data/Sources/ImportService.swift`, `AppDependencies.importService` | chỉ `ImportModel` gọi |
| `Domain/Import/ImportCandidate.swift` | chỉ Import dùng |
| `SmartAlbumQuery+Matching.swift` (bộ đánh giá điều kiện trong bộ nhớ) và phần test của nó | tồn tại để lọc ứng viên chưa có dòng DB — chỉ `ImportModel` gọi |
| `LibraryQueries.importedFingerprints()` | chỉ để đánh dấu ảnh "đã nhập" |
| Chuỗi trong String Catalog chỉ phục vụ các màn trên | không để rác dịch |

| Ở lại | Vì |
|---|---|
| `PhotoLibraryService.importFile(at:isVideo:)` | Video Studio, Photo Detail, kéo-thả (`PhotoDropImport`) cùng dùng để ghi file vào thư viện |
| Share extension (`ShotDexShare`, EX-03) | lối của hệ thống, không phải lối trong app; có model riêng, không gọi `ImportService` |
| Shortcuts/Siri (EX-04) | không có intent nào gọi Import (đã kiểm) |
| `PhotoFileType` và test phân loại đuôi file | Library, bộ lọc và index cùng dùng |

- **Không xoá dữ liệu:** ảnh đã nhập trước đây nằm trong thư viện Photos như mọi ảnh khác và vẫn được index.
  Import không có bảng hay cột riêng trong database — không có gì để migrate.
- App chưa phát hành: không cần ghi chú thay đổi.

## 3. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | quyền thư viện đầy đủ | mở Settings → Photo Library (iPhone và iPad) | không có hàng Import; các hàng còn lại đúng thứ tự cũ | ⚠️ chưa có — `settings-photo-library.json` dump + ảnh |
| AC-2 | mã nguồn app và mọi extension | `grep -rn "ImportScreen\|ImportService\|ImportModel\|ImportCandidate\|importedFingerprints"` | không còn dòng nào | ⚠️ chưa có — lệnh grep trong `/verify` |
| AC-3 | toàn bộ project | build scheme `ShotDex` (app + widget + share + edit action) | `BUILD SUCCEEDED`, không cảnh báo mới | ⚠️ chưa có — build |
| AC-4 | bộ test đầy đủ | chạy `ShotDexTests` | xanh; test phân loại đuôi file vẫn còn và xanh | ⚠️ chưa có — test |
| AC-5 | một ảnh đã có trong thư viện (kể cả ảnh từng nhập bằng Import) | mở lại app sau bản build mới | ảnh vẫn trong lưới Library, metadata còn | ⚠️ chưa có — ảnh lưới |
| AC-6 | Video Studio xuất video, Photo Detail lưu khung video, kéo-thả ảnh vào Library | làm từng việc | vẫn ghi được asset mới (`importFile` còn nguyên) | ⚠️ chưa có — build + `PhotoDropImport` gọi `importFile` |
| AC-7 | String Catalog | tìm các khoá chỉ Import dùng ("Import Photos", "Hide Photos Already Imported"…) | không còn khoá nào chỉ phục vụ Import | ⚠️ chưa có — grep catalog |

**Chưa chứng minh được:** cả 7 — chưa build.
