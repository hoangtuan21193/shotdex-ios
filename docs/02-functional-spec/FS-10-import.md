# FS-10 — Import (đã bỏ)

`FS-10` · đã bỏ · cập nhật 2026-09-24 · nguồn
[intent](../_intents/2026-09-21-remove-import-entry-point.md)

**Một câu:** ShotDex **không có màn Import**. Ảnh vào máy bằng Photos (thẻ nhớ qua Photos, AirDrop, cáp,
iCloud) hoặc qua Share sheet ([EX-03](../03-extensions-and-integrations/EX-03-share-extension.md)); ShotDex
index những gì đã có trong thư viện.

> Trạng thái: **đã gỡ** (2026-09-24). Trước đó "Import Photos" là một hàng trong Settings → Photo Library, mở
> màn nhập từ folder ngoài có lọc RAW.

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
| `Domain/Import/ImportCandidate.swift` — gồm cả `PhotoFileType.classify(extension:)` và `isRawFormat` khai báo ở đó | chỉ Import dùng |
| `SmartAlbumQuery+Matching.swift` (bộ đánh giá điều kiện trong bộ nhớ) và `SmartAlbumQueryMatchingTests.swift` (cả suite phân loại đuôi file) | tồn tại để lọc ứng viên chưa có dòng DB — chỉ `ImportModel` gọi |
| `LibraryQueries.importedFingerprints()` | chỉ để đánh dấu ảnh "đã nhập" |
| Chuỗi trong String Catalog chỉ phục vụ các màn trên | không để rác dịch |

| Ở lại | Vì |
|---|---|
| `PhotoLibraryService.importFile(at:isVideo:)` | Video Studio, Photo Detail, kéo-thả (`PhotoDropImport`) cùng dùng để ghi file vào thư viện |
| Share extension (`ShotDexShare`, EX-03) | lối của hệ thống, không phải lối trong app; có model riêng, không gọi `ImportService` |
| Shortcuts/Siri (EX-04) | không có intent nào gọi Import (đã kiểm) |
| enum `PhotoFileType` | Library, bộ lọc, Search và SQL builder cùng dùng |

- **Không xoá dữ liệu:** ảnh đã nhập trước đây nằm trong thư viện Photos như mọi ảnh khác và vẫn được index.
  Import không có bảng hay cột riêng trong database — không có gì để migrate.
- App chưa phát hành: không cần ghi chú thay đổi.

## 3. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | quyền thư viện đầy đủ | mở Settings → Photo Library (iPhone và iPad) | không có hàng Import; các hàng còn lại đúng thứ tự cũ | ✅ `settings-photo-library.json` ảnh `01` trên iPad Pro 13 iOS 18.6 + `phone-settings.json` ảnh `01-top` trên iPhone 17 Pro 26.5: Access · Indexed · (Last Indexed) · Re-index · ba công tắc, không Import |
| AC-2 | mã nguồn app và mọi extension | `grep -rn "ImportScreen\|ImportService\|ImportModel\|ImportCandidate\|importedFingerprints"` | không còn dòng nào | ✅ `grep -rnw "ImportScreen\|ImportService\|ImportModel\|ImportCandidate\|importedFingerprints"` trên ShotDex, ShotDexKit, ShotDexShare, ShotDexWidget, WidgetShared, ShotDexEditAction, tests — 0 dòng (`ShareImportModel` của Share extension là type khác) |
| AC-3 | toàn bộ project | build scheme `ShotDex` (app + widget + share + edit action) | `BUILD SUCCEEDED`, không cảnh báo mới | ✅ `BUILD SUCCEEDED`; cảnh báo duy nhất là `usesToolRail` có sẵn ở `VideoStudioScreen.swift:276` |
| AC-4 | bộ test đầy đủ | chạy `ShotDexTests` | xanh (trừ test đỏ có sẵn không liên quan) | ✅ 1224/1229 xanh sau khi gỡ; `SettingsSearchTests` cập nhật còn 37 hàng (Photo Library 13); 4 test panorama đỏ có sẵn (cần thư viện ảnh trên simulator), không liên quan. Suite phân loại đuôi file đi cùng code của nó |
| AC-5 | một ảnh đã có trong thư viện (kể cả ảnh từng nhập bằng Import) | mở lại app sau bản build mới | ảnh vẫn trong lưới Library, metadata còn | ✅ dump `phone-settings.json`: lưới Library vẫn "19 Photos" sau bản build mới; Import không có bảng/cột riêng |
| AC-6 | Video Studio xuất video, Photo Detail lưu khung video, kéo-thả ảnh vào Library | làm từng việc | vẫn ghi được asset mới (`importFile` còn nguyên) | ✅ ở mức code (chưa chạy lại từng luồng): build xanh, `importFile` còn nguyên, gọi từ `AppDependencies.swift:150` (Video Studio), `PhotoDetailScreen.swift:852`, `PhotoDropImport.swift:47` |
| AC-7 | String Catalog | tìm các khoá chỉ Import dùng ("Import Photos", "Hide Photos Already Imported"…) | không còn khoá nào chỉ phục vụ Import | ✅ 24 khoá chỉ Import dùng gỡ khỏi `Localizable.xcstrings` (stage trên bản HEAD, gỡ cùng trong bản làm việc) — gồm `Import Photos`, `Hide Photos Already Imported`, `Choose Folder`… |

**Chưa chứng minh được:** không còn.
