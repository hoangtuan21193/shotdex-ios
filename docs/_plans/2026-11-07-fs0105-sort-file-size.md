# Kế hoạch — Sắp Library theo dung lượng

| Trường | Giá trị |
|---|---|
| Đặc tả | `docs/02-functional-spec/FS-01-library/05-filtering-and-sorting.md` §5.1, AC-S1…AC-S14 (commit `35086961`) |
| Ngày | 2026-11-07 |
| Trạng thái | chờ duyệt (⚠️ đã quyết hết) |

## 1. Hiểu đúng chưa

Library (iPhone, iPad, Duo, Mac) có thêm hai thứ tự File Size (Largest) và File Size (Smallest), lấy từ cột
`photo_metadata.fileSize` đã index sẵn. Ảnh chưa biết dung lượng xếp cuối theo ngày chụp, rồi tới placeholder
iCloud. Thanh cuộn ngày bị ẩn khi đang sắp theo dung lượng. Album Detail và Smart Album giữ nguyên. Không có intent —
đi đường tắt "đổi hành vi đã có" (`docs/PROCESS.md` §4).

## 2. Đối chiếu AC ↔ code

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-S1 | ❌ | `SortOption.swift:4` không có case dung lượng; `LibraryQueries.swift:603` `orderClause` | thêm `fileSizeLargest`/`fileSizeSmallest` + clause `fileSize DESC NULLS LAST, creationDate DESC NULLS LAST` (`assetId ASC` đã tự nối ở `:620`) |
| AC-S2 | ❌ | như trên | clause `fileSize ASC NULLS LAST, creationDate DESC NULLS LAST` |
| AC-S3 | ✅ sau khi có S1 | `LibraryQueries.swift:13` `gridItems(matching:sort:)` áp `whereClause` trước `ORDER BY` | chỉ viết test |
| AC-S4 | ✅ sau khi có S1 | `:620` mọi clause kết thúc bằng `assetId ASC`; `DatabaseTests.swift:684` đã kiểm hậu tố cho mọi case | test thứ tự hai lần chạy |
| AC-S5 | ❌ | `SortOption.swift:46` `menuOrders` 4 phần tử; `photoKitSortKey` `default: nil` (`:33`) đã đúng cho case mới | nối 2 case vào `menuOrders`, `displayName` |
| AC-S6 | ✅ sau khi có S5 | `LibraryModel.swift:256` `storedSort()` chấp nhận mọi phần tử của `menuOrders` | chỉ viết test |
| AC-S7 | ✅ | `LibraryModel.swift:463` `merging` — thứ tự không phải Date Taken thì `rows + cloud` | chỉ viết test |
| AC-S8 | ❌ | chỉ có `idx_photo_metadata_modificationDate` (`AppDatabase.swift:304`); migration cuối `v62-creatorRights` | migration `v63-fileSizeIndex`, tên index theo lệ cũ `idx_photo_metadata_fileSize` (spec ghi `photo_metadata_on_fileSize` — sửa spec theo lệ repo) |
| AC-S9 | ❌ | `LibraryCountLine.swift:42` `LibrarySortField` chỉ có 2 field; `MacFilterPopover.swift:207–220` nhãn Newest/Oldest cứng | thêm `.fileSize`; nhãn hàng Order theo field |
| AC-S10 | ❌ | `LibrarySortField.init(_:)`, `isNewestFirst` (`LibraryCountLine.swift:54,67`) | map 2 case mới; `MacFilterPopoverLogicTests.sortPairCoversEveryMenuOrder` (`:62`) sẽ tự phủ |
| AC-S11 | ✅ sau S5 (chữ AC đã sửa) | lưới neo đáy: `LibraryModel.swift:496` đảo mảng, phần tử đầu thứ tự nằm **ở đáy**, chỗ lưới mở ra | chụp ảnh |
| AC-S12 | ❌ (chưa chụp) | menu dùng `ForEach(SortOption.menuOrders)` (`LibraryScreen.swift:1240`) — cùng code cho cả hai nhánh iOS | script + ảnh |
| AC-S13 | ❌ | `LibraryScreen.swift:773` overlay `PhotoGridScrubber` luôn có | bọc overlay theo `sort.showsDateScrubber` (thuộc tính mới trên `SortOption`, true cho 4 thứ tự ngày) |
| AC-S14 | ❌ (đã quyết, mục 7) | `IP_MenuBar.dc.html:277` vẽ View ▸ Sort By, nhưng **iPad không có menu bar Sort By nào trong code** (`ShotDexApp.swift:156` chỉ có `VideoStudioCommands`). `MAC_MenuBar.dc.html:207` vẽ field + hướng, còn code Mac (`MacLibraryCommands.swift:57–63`) là **6 dòng phẳng** từ `menuOrders` | sửa 3 board, publish canvas iPad + Mac |

## 3. Tái dùng

- `SortOption.menuOrders` lái cả 3 menu (iPhone/iPad/Duo `LibraryScreen.swift:1240`, Mac View menu
  `MacLibraryCommands.swift:61`, Mac popover qua `LibrarySortField`) — thêm case một chỗ, menu tự có dòng.
- `LibraryModel.merging` đã xếp placeholder cuối cho thứ tự thông số — không viết lại.
- Bảng List của Mac đã có cột Size, đang sắp **cục bộ** (`MacPhotoTable.swift:491–514`).
  `MacTableColumn.sortOption(ascending:)` (`:419`) thêm `case .size: ascending ? .fileSizeSmallest : .fileSizeLargest`
  → bấm đầu cột Size và chọn trong menu là **một** thứ tự SQL, đầu cột tự hiện mũi tên đúng (`column(for:)` `:430`).
  Bỏ `.size` khỏi danh sách sắp cục bộ. Không thêm AC mới: đó là AC-S9 ở dạng bảng; ghi vào spec §5.1.

## 4. Chỗ nào trong code

| File | Đụng gì | Tầng |
|---|---|---|
| `ShotDex/Core/Models/SortOption.swift` | 2 case, `displayName`, `menuOrders`, `showsDateScrubber` | Domain/model |
| `ShotDex/Data/Database/LibraryQueries.swift` | `orderClause` 2 dòng | Data |
| `ShotDex/Data/Database/AppDatabase.swift` | migration `v63-fileSizeIndex` | Data |
| `ShotDex/Domain/Filtering/LibraryCountLine.swift` | `LibrarySortField.fileSize`, nhãn hướng | Domain |
| `ShotDex/Features/Library/LibraryScreen.swift` | overlay scrubber có điều kiện | Features (view chỉ đọc cờ) |
| `ShotDexMac/Library/MacFilterPopover.swift` | nhãn Order theo field | Features Mac |
| `ShotDexMac/Library/MacPhotoTable.swift` | cột Size → `SortOption` | Features Mac |
| `ShotDexTests/…` | `LibraryQueriesSortTests` (mới), `DatabaseTests`, `MacFilterPopoverLogicTests`, `LibraryModelSortTests` (mới) | Test |
| `docs/design/{ipad,mac}/project/*.dc.html` | theo câu trả lời mục 7 | Design |
| `ShotDexUITests/scripts/library-sort-filesize.json` | mới | UI driver |

## 5. Thứ tự task (một task = một commit)

| # | Task | AC | Test |
|---|---|---|---|
| 1 | `SortOption` + `orderClause` | S1, S2, S5 | `LibraryQueriesSortTests.fileSizeLargest/Smallest`, `SortOptionTests.menuOffersFileSize` |
| 2 | khoá hành vi có sẵn bằng test | S3, S4, S6, S7 | `fileSizeRespectsFilter`, `fileSizeIsStable`, `LibraryModelSortTests.restoresFileSize/placeholdersLast` |
| 3 | migration index | S8 | `DatabaseTests.fileSizeSortUsesIndex` (EXPLAIN QUERY PLAN) |
| 4 | ẩn scrubber | S13 | ảnh trước/sau |
| 5 | Mac: `LibrarySortField.fileSize`, nhãn Order, cột Size | S9, S10 | `MacFilterPopoverLogicTests.fileSizeField/fileSizeDirection` + ảnh `mac-shot` |
| 6 | board iPad/Mac theo quyết định mục 7, publish lên canvas | S14 | `Tools/design-board render` + `design-parity` |
| 7 | script ui-drive, chụp iPhone 26.5 + 18.6 + iPad | S11, S12 | `library-sort-filesize.json` + ảnh |

Gộp S1/S2/S5 vào một commit: ba AC là một thay đổi enum, tách ra thì commit giữa không build được.

## 6. Rủi ro

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| `ASC NULLS LAST` không khớp thứ tự index (SQLite xếp NULL đầu khi ASC) → Smallest vẫn sắp bằng temp B-tree trên 55k hàng | cao | AC-S8 chỉ đòi Largest. Đo Smallest trên DB 55k; nếu > 300 ms thì báo, không tự thêm index biểu thức |
| Migration chạy trên DB thật 55k hàng | thấp | `CREATE INDEX` mất ~1 s, có đường lùi (DROP INDEX); `data-migration` xem lại |
| Bảng Mac: bỏ sắp cục bộ cột Size → giá trị `mac.library.localSort` đã lưu = `size` | thấp | đọc lại thì đổi sang `SortOption` tương ứng, hoặc bỏ qua (app chưa release, không back-compat) |
| Duo 669pt: menu thêm 2 dòng | thấp | menu hệ thống tự cuộn; chụp ở bước 7 nếu đủ giờ |
| Index đầu chưa xong | đã chốt | như thứ tự ISO, không UI mới |

## 7. Đã quyết (2026-11-07)

1. **AC-S11** — sửa chữ theo code: ảnh lớn nhất ở ô dưới cùng, chỗ lưới mở ra (lưới neo đáy như thứ tự ngày).
2. **iPad menu bar** — giữ `IP_MenuBar` là thiết kế đi trước; View ▸ Sort By còn Date Taken · Date Modified · File Size
   rồi hướng; bỏ Name/ISO/Focal Length/Aperture/Shutter Speed. Không thêm code menu bar iPad.
3. **Mac menu bar** — `MAC_MenuBar` vẽ lại thành 6 dòng phẳng như code (`menuOrders`). Không đổi code menu Mac.

## 8. Agent ở giai đoạn Deploy

`data-migration` (task 3), `ios26-parity` (task 4, menu cả hai nhánh), `design-parity` (task 6), `device-layout` (task 7, iPad/Duo).

## 9. Cách chứng minh là xong

- Test: các tên ở mục 5, chạy bằng `/test` từng lớp (không full suite).
- Ảnh: iPhone 17 26.5 + 18.6 (menu mở, lưới Largest, scrubber ẩn/hiện), iPad 13", Mac popover + bảng.
- Tài liệu: cột "Chứng minh bằng" của AC-S1…S14; §5.1 thêm tên index và cột Size Mac.
