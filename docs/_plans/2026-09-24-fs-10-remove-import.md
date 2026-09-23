# Kế hoạch — Bỏ Import (FS-10)

| Trường | Giá trị |
|---|---|
| Đặc tả | `docs/02-functional-spec/FS-10-import.md` |
| Ngày | 2026-09-24 |
| Trạng thái | xong 2026-09-24 — 7/7 AC |

## 1. Hiểu đúng chưa

Gỡ lối Import duy nhất (hàng trong Settings → Photo Library) và toàn bộ code chỉ nó dùng. Không thay bằng lối
khác. Giữ mọi thứ còn người dùng khác: `importFile` (Video Studio, Photo Detail, kéo-thả), Share extension,
`PhotoFileType`. Không có dữ liệu nào để migrate.

## 2. Đối chiếu AC ↔ code

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 | ❌ | `SettingsScreen.swift:393-397` hàng `.importPhotos`; `:99` `fullScreenCover` | gỡ hàng, cover, state `isImportPresented`, case `.importPhotos` (`SettingsRowLabel.swift:31,102,144`) |
| AC-2 | ❌ | `Features/Import/`, `Data/Sources/ImportService.swift`, `Domain/Import/ImportCandidate.swift`, `AppDependencies.swift:25,149`, `LibraryQueries.swift:111` | xoá |
| AC-3 | — | — | build sau khi gỡ |
| AC-4 | ⚠️ | `SmartAlbumQueryMatchingTests` test bộ đánh giá trong bộ nhớ (chỉ Import dùng) + `PhotoFileTypeClassifyTests.classifiesImageVsVideoVsOther` dùng `ImportCandidate.classify` | gỡ suite matcher cùng `SmartAlbumQuery+Matching.swift`; giữ `PhotoFileTypeClassifyTests`, bỏ đúng test dùng `ImportCandidate` |
| AC-5 | ✅ | Import không có bảng/cột riêng; ảnh nhập là asset Photos thường | ảnh lưới sau khi gỡ |
| AC-6 | ✅ | `importFile` ở `PhotoLibraryService`, gọi từ `AppDependencies.swift:152`, `PhotoDetailScreen.swift:852`, `PhotoDropImport.swift:47` | không đụng |
| AC-7 | ⚠️ | String Catalog đang có một bản viết lại lớn chưa commit của phiên khác | gỡ khoá chỉ Import dùng trên **bản HEAD** rồi stage bằng `git update-index`, và gỡ đúng các khoá đó trong bản làm việc — không commit phần viết lại của người khác |

## 3. Thứ tự task

| # | Task | AC | Test |
|---|---|---|---|
| 1 | Gỡ hàng Settings + code Import + matcher + fingerprints; sửa test | AC-1–4, 6 | build + full test |
| 2 | Gỡ chuỗi Import khỏi String Catalog | AC-7 | grep catalog |
| 3 | `/verify`: ảnh Settings iPhone 26.5 + iPad 18.6, ảnh lưới | AC-1, 5 | ui-drive |

## 4. Rủi ro

| Rủi ro | Xử lý |
|---|---|
| Một chỗ ngoài `Features/Import` dùng lén type Import | build là cổng; grep AC-2 |
| Catalog: đụng bản viết lại chưa commit | stage bản HEAD đã sửa, không `git add` file làm việc |
