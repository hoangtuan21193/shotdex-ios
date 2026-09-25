# Kế hoạch — Menu Filter trong album

| Trường | Giá trị |
|---|---|
| Đặc tả | `docs/02-functional-spec/FS-06-collections/09-album-filter-menu.md` |
| Ngày | 2026-09-25 |
| Trạng thái | **gần xong** (2026-09-25, `/verify`) — 14/14 task + sửa sau review (`fbaddd2`); 13/16 AC xanh đủ, AC-14/15/16 thiếu một phần; gate: 1331/1332, đỏ ở test bộ nhớ focus stack (FS-01.10, chạy riêng xanh — tách việc riêng) |

## 1. Hiểu đúng chưa

Album Detail và Smart Album có menu Filter của Library, thay cho nút Sort riêng. Menu gồm Favorites,
Photos/Videos Only, Capture Kind, và Advanced Filter chỉ lọc trong album. Sort By nằm trong menu; Aspect
Ratio Grid là thiết lập chung.
Đang lọc thì có hàng chip với `x` và Clear. Mỗi lần mở album là All Items. Ảnh đã chọn mà bị lọc ẩn thì bị
bỏ khỏi lựa chọn. Ở Smart Album, bộ lọc thu hẹp thêm điều kiện đã lưu. On This Day và Memories giữ nguyên.
Không có intent gốc (PROCESS §4: đổi hành vi thì bắt đầu từ `/spec`).

## 2. Đối chiếu AC ↔ code

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 Favorites | ❌ | `AlbumDetailModel.fetch` `AlbumsModel.swift:663` chỉ có điều kiện "duyệt được", không có trạng thái lọc | thêm lọc vào model, tạo điều kiện truy vấn Photos từ bộ lọc |
| AC-2 Photos/Videos Only | ❌ | như trên | như trên |
| AC-3 Capture Kind | ❌ | như trên; Panoramas do ShotDex ghép chỉ có trong index (`PhotoMediaSubtype.swift:41`) | bit kiểu chụp của hệ thống + danh sách id panorama từ index |
| AC-4 Sort nhớ theo album | ✅ logic, ❌ vị trí | `AlbumSortStore` `AlbumsModel.swift:523`, `setSortOrder` `:647`; nút riêng `AlbumDetailScreen.swift:552` | chuyển vào `Sort By ▸` của menu chung; logic giữ nguyên |
| AC-5 không có Album Order | ✅ | `supportsAlbumOrder` `AlbumsModel.swift:639`, lọc ở `AlbumDetailScreen.swift:555` | giữ, chụp dump khoá lại |
| AC-6 Smart Album lọc chồng | ❌ | `SmartAlbumDetailModel.load` `SmartAlbumDetailModel.swift:64` chỉ chạy truy vấn đã lưu | thêm truy vấn "đã lưu VÀ bộ lọc" trong `LibraryQueries` |
| AC-7 Smart Album Sort | ❌ | sắp cố định `sort: .default` `SmartAlbumDetailModel.swift:64` | dùng lại `AlbumSortStore` (smart ⇒ mặc định Newest) |
| AC-8 lọc ra rỗng | ❌ | Library có sẵn `LibraryScreen.swift:861` | **Q-A đã chốt**: dùng đúng chữ của Library; spec đã sửa |
| AC-9 mở lại là All Items | ❓ | bộ lọc sẽ sống theo màn nên tự reset; **nhưng** `AlbumDetailScreen.swift:113` dựng model mới mỗi lần thư viện đổi → cũng mất lọc giữa chừng | giữ bộ lọc ở màn, truyền vào model khi dựng lại |
| AC-10 bỏ ảnh bị ẩn khỏi lựa chọn | ❌ | Library cũng **không** làm việc này | **Q-D đã chốt**: làm cho cả Library; FS-01.06 §2 đã thêm luật |
| AC-11 Advanced trong album | ❌ | sheet gắn chặt `LibraryModel` (`AdvancedSearchSheet.swift:9`, `:91` ghi thẳng vào Library); `LibraryQueries` không có truy vấn giới hạn theo tập id | tách sheet khỏi Library; thêm truy vấn giới hạn theo id |
| AC-12 Advanced và lọc nhanh loại trừ nhau | ❌ | luật có ở `LibraryModel.swift:180/191` | cùng luật ở model album |
| AC-13 chip `x`, lưới không bị che | ❌ | `FilterTokenBar` dùng lại được (`FilterTokenBar.swift:92`); lưới có `topInset` (`PhotoGridCollectionView.swift:58`), Library đo chiều cao (`LibraryScreen.swift:699`) | dùng lại cả hai |
| AC-14 `.limited` + biểu ngữ | ❌ | FS-06.01b §2 nói có biểu ngữ Manage; code **không có** (không có `LimitedAccessBanner` trong `AlbumDetailScreen.swift`) | **Q-B đã chốt**: tài liệu đúng — dùng lại `LimitedAccessBanner` (`LibraryScreen.swift:1296`) cho Album và Smart Album |
| AC-15 On This Day / Memories không đổi | ✅ | không đụng `OnThisDayScreen`, `PhotoListScreen` | chỉ chụp khoá lại |
| AC-16 26.5 = 18.6, Duo | ❓ | chưa có UI | `ios26-parity` + `device-layout` sau cùng |
| (Smart Album chip) | ❌ | `SmartAlbumConditionsBar.swift:31` vẽ chip nền phẳng trên nền `.bar`; chip lọc là kính (`FilterTokenBar.swift:56`). Nối vào cùng hàng = hai kiểu chip trên một dòng | **Q-C đã chốt**: trộn hai kiểu trên một dòng, cố ý |

## 3. Dùng lại, không làm lần hai

- Menu: tách `filterMenu` của Library (`LibraryScreen.swift:1175`) thành **một view dùng chung**, nhận phần
  Sort và có/không Advanced. Library và hai màn album cùng gọi.
- Chip: `FilterTokenBar` + `ActiveConditionChip`. Chân lưới: tách `countFooter` (`LibraryScreen.swift:753`).
- Sort: `AlbumSortOrder`, `AlbumSortStore`, `librarySort`. Gợi ý trong sheet: `FilterSuggestionCache`.
- Album danh sách id có thứ tự: đường `.ordered` đang phục vụ album kiểu chụp (`AlbumsModel.swift:733`).

## 4. File đổi và tầng

| File | Đụng gì | Tầng |
|---|---|---|
| `Domain/Albums/AlbumFilterPredicate.swift` (mới) | bộ lọc → điều kiện truy vấn Photos (favorite, loại, bit kiểu chụp, id panorama) | Domain, test được |
| `Data/Database/LibraryQueries.swift` | lưới/đếm cho "truy vấn đã lưu VÀ bộ lọc" và "giới hạn trong tập id" | Data, test DB |
| `Features/Albums/AlbumsModel.swift` (`AlbumDetailModel`) | trạng thái lọc, nạp lại, Advanced | Features model |
| `Features/Albums/SmartAlbumDetailModel.swift` | sort + lọc chồng | Features model |
| `Features/Shared/PhotoFilterMenu.swift` (mới) | menu dùng chung | Features view |
| `Features/Library/AdvancedSearchSheet.swift` | bỏ phụ thuộc `LibraryModel`: truy vấn ban đầu, gợi ý, hàm đếm, hàm áp, nhãn nút | Features view |
| `LibraryScreen` · `AlbumDetailScreen` · `SmartAlbumDetailScreen` · `SmartAlbumConditionsBar` | gọi menu chung, chip, chân lưới, trạng thái rỗng | Features view |

Không đổi lược đồ, không có dữ liệu người dùng tự nhập (điều kiện Advanced chỉ sống trong phiên).

## 5. Thứ tự task — mỗi task một commit

| # | Task | AC | Test kèm |
|---|---|---|---|
| 1 | Menu dùng chung; Album Detail đổi nút Sort thành menu (chỉ Sort By + Aspect Ratio Grid) | AC-4, AC-5 | ui-drive `album-filter-menu.json` dump menu, album người dùng + Recently Added |
| 2 | Favorites: bộ lọc ở màn → model, chip, chân lưới `x of y`, giữ lọc khi thư viện đổi | AC-1, AC-9 | `AlbumFilterPredicateTests.favorites` + ui-drive |
| 3 | Photos Only / Videos Only | AC-2 | `AlbumFilterPredicateTests.mediaKinds` |
| 4 | Capture Kind (gồm Panoramas từ index) | AC-3 | `AlbumFilterPredicateTests.captureKinds` |
| 5 | Trạng thái rỗng, chữ của Library | AC-8 | ui-drive |
| 6 | `x` / Clear, lưới được trả chiều cao hàng chip | AC-13 | ui-drive + dump khung hàng ảnh đầu |
| 7 | Bỏ ảnh bị lọc ẩn khỏi lựa chọn — album | AC-10 | ui-drive (pill đếm) |
| 7b | Cùng luật cho Library (FS-01.06 §2) | FS-01.06 §2 | ui-drive: chọn 3 ảnh, bật Favorites, pill còn số ảnh favorite |
| 8 | Biểu ngữ `.limited` ở Album và Smart Album | AC-14 | chụp tay trên sim ở chế độ limited |
| 9 | Smart Album: Sort By nhớ theo album | AC-7 | ui-drive |
| 10 | Smart Album: lọc chồng + chip kính nối vào hàng điều kiện | AC-6 | `DatabaseTests.smartAlbumQueryAndCriteria` + ui-drive |
| 11 | Tách sheet Advanced; truy vấn giới hạn theo id; Apply ở lại album | AC-11 | `DatabaseTests.queryRestrictedToAssetIds` (gồm 20.000 id) + ui-drive |
| 12 | Advanced ↔ lọc nhanh loại trừ nhau trong album | AC-12 | ui-drive |
| 13 | Chụp On This Day, Memories (không đổi) | AC-15 | ui-drive |
| 14 | Đối chiếu 26.5 / 18.6, Duo | AC-16 | agent `ios26-parity`, `device-layout` |

Số trong AC (40 ảnh, 12 favorite…) được chứng minh bằng test với dữ liệu dựng sẵn. Chạy ui-drive thì dùng
đúng số ảnh đang có trên sim (11 ảnh), không giả vờ có 40.

## 6. Rủi ro

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| Truy vấn với 20.000 id vượt giới hạn tham số của SQLite | cao nếu dùng `IN (?,?,…)` | truyền một mảng JSON và dùng `json_each`, hoặc bảng tạm; test 20.000 id |
| Lấy id của album 20.000 ảnh từ Photos trên luồng chính | vừa | làm ngoài luồng chính như `AlbumsModel.loadSnapshot` |
| Model dựng lại khi thư viện đổi → mất lọc, mất lựa chọn | chắc chắn nếu không xử lý | bộ lọc sống ở màn; task 2 |
| Tách sheet Advanced làm hỏng luồng Search của Library | vừa | Library giữ nguyên hành vi; chụp lại luồng Advanced Search của Library ở task 11 |
| Hàng chip trên Duo trong (669pt) che hàng ảnh đầu | vừa | đo bằng dump ở task 6 và task 14 |
| PhotoKit: điều kiện favorite/bit kiểu chụp trong truy vấn Photos | thấp | `photokit-guard` duyệt task 2–4 |

## 7. Agent cho giai đoạn Deploy

`photokit-guard` (task 2–4, 11) · `perf-profiler` (task 11, album lớn) · `swift-concurrency` (nạp id ngoài
luồng chính) · `component-consistency` (menu, chip) · `copy-consistency` (trạng thái rỗng) · `ios26-parity` ·
`device-layout`.

## 8. Cách chứng minh là xong

- Test: `AlbumFilterPredicateTests` (mới), `DatabaseTests` thêm 2 ca; `/test` xanh.
- Màn hình: Album Detail và Smart Album — không lọc · đang lọc · rỗng · đang chọn, trên 26.5 và 18.6;
  Duo trong khi đang lọc; Library Advanced Search sau khi tách sheet.
- Tài liệu: cột "Chứng minh bằng" của FS-06.09 sau từng task; FS-06.01b §3 (bỏ "nút Sort riêng"); FS-01.05 §5
  (menu dùng chung).
