# FS-01.05 — Lọc và sắp xếp

`FS-01.05` · `Features/Shared/RuleBuilderSections.swift` · `AdvancedSearchSheet`
· `Core/Models/FilterCriteria.swift` · `SortOption` · cập nhật 2026-11-07 (§5.1 sắp theo dung lượng)

**Một câu:** một bộ dựng điều kiện dùng chung cho Advanced Search và Smart Album, cộng một menu lọc nhanh
trên toolbar.

## 1. Quy tắc

- **Hai nguồn điều kiện loại trừ nhau**: đặt truy vấn nâng cao thì xoá bộ lọc đơn giản, và ngược lại — lưới
  chỉ có một nguồn.
- **Bộ dựng điều kiện dùng chung**: sửa một chỗ thì cả sheet Advanced Search lẫn sheet Smart Album đồng bộ.
- Một điều kiện **không được hiện ở hai chỗ**.
- **Mọi phép sắp xếp kết thúc bằng id ảnh làm tiêu chí phá hoà**, và ngày chụp rỗng luôn xếp cuối — thứ tự
  phải giống nhau giữa hai lần chạy cùng một truy vấn.

## 2. Advanced Search

- Mở từ nút trong ô tìm kiếm hoặc mục **Advanced Filter…** trong menu lọc.
- Sheet gồm: **một hàng** loại media (All / Photo / Video) + khớp tất cả / bất kỳ · **danh sách điều kiện**
  (mỗi dòng một điều kiện, nút thêm, nút xoá). Số ảnh khớp sống nằm **dưới tiêu đề, cạnh nút Search**
  ([05b §3](05b-gear-menu-missing-data-and-sheet.md)); sheet có nháp chưa áp thì không vuốt đóng được (§4 ở đó).
- Thứ tự chọn nguồn khi nạp lưới: đường nhanh của hệ thống (khi không lọc gì và đang sắp theo ngày) →
  truy vấn nâng cao → bộ lọc đơn giản.
- Nút **Search** (tắt khi không có điều kiện hợp lệ) áp truy vấn rồi chuyển về tab Library.
- Khi truy vấn nâng cao đang bật, thanh chip đổi sang bản của nó: mỗi điều kiện là một chip có `x`, chữ
  **rút gọn** (`ISO 100`, `f > 1.4`, `focal 50mm–85mm`) thay câu dài. **Edit** và **Clear** ghim cố định ở
  mép phải.
- Số ảnh khớp **không chiếm chỗ trên thanh điều kiện** — nó nằm ở chân lưới, sau ảnh cuối.
- **Save as Smart Album** mở sheet smart album với chính các điều kiện đang có — biến một lần tìm thành một
  album lưu vĩnh viễn.

## 3. Ảnh / video và kiểu chụp

- Thư viện index cả ảnh lẫn video nên **ảnh/video là một chiều lọc riêng**. Cột loại media có từ bản đầu;
  migration chỉ thêm **chỉ mục**.
- Loại media lưu bằng **chuỗi** để đi qua JSON của smart album cho đẹp, và có cầu nối sang số của hệ thống —
  thay cho hằng số `== 2` rải rác khắp nơi.
- Trong bộ dựng điều kiện, nó là **một dải chọn All / Photo / Video** ở đầu sheet. Đó là lối tắt của **đúng
  một điều kiện** nên biên dịch qua cùng một đường và hiện chip như mọi điều kiện khác; nó **không** nằm
  trong menu chọn trường của dòng điều kiện.
- Trong bộ lọc đơn giản, chọn **cả hai** loại hoặc **không chọn gì** đều nghĩa là không ràng buộc.
- **Panoramas** là mục duy nhất không chỉ hỏi mặt nạ bit của hệ thống: nó hỏi `mediaSubtypes` **hoặc**
  cột `isPanorama`, vì panorama do ShotDex ghép không mang cờ của hệ thống
  ([FS-14 §7](../FS-14-panorama/01-screen-and-flow.md)).
- **Unsupported RAW** là mục thứ hai không do hệ thống định nghĩa: ảnh RAW-only của máy mà iOS trên máy "chưa
  đọc được", tra trong bảng phán quyết ([FS-03.04b §2, §5](../FS-03-photo-editor/04b-unsupported-raw.md)). Máy
  "chưa biết" không khớp. Mục này cũng có trong menu lọc của màn album: ở đó lọc bằng danh sách id ảnh từ index,
  giới hạn trong tập id của album, như Panoramas do ShotDex ghép (người dùng chốt 2026-10-01). Mọi kiểu chụp khác
  vẫn do hệ thống định nghĩa.
- **Kiểu chụp** là một menu con trong menu lọc: Screenshots · Live Photos · Portrait · Panoramas · HDR ·
  Time-lapse · Slo-mo · Cinematic · Unsupported RAW. Là **menu con** chứ không phải chín hàng phẳng, vì chín
  hàng sẽ chôn mất mục "Advanced Filter…".
  - Dữ liệu là bitmask kiểu chụp của hệ thống, nên "một trong các loại này" là một phép hợp của các phép
    kiểm bit trong SQL.
  - Row ghi **trước khi có cột đó** mang giá trị rỗng và **không khớp gì cả**, đúng nghĩa "index chưa biết
    nó là gì" → có một lượt điền bù chạy lúc mở app, đọc kiểu chụp **sẵn trong bộ nhớ** (không đọc file,
    không đụng EXIF), theo lô 2.000.

## 4. Các trục lọc

| Trục | Cách lọc |
|---|---|
| Hãng máy · Thân máy | hai danh sách chọn nhiều **độc lập**, không phân cấp |
| Ống kính | chọn nhiều, danh sách phẳng (phân biệt prime/zoom đã có ở tầng logic, chưa lên giao diện) |
| ISO | chính xác · khoảng · nhóm nhanh ≤100 · 101–400 · 401–1600 · 1601–6400 · >6400 |
| Tốc độ | chính xác · khoảng · nhóm nhanh chậm hơn 1/30 · 1/30–1/125 · 1/126–1/500 · nhanh hơn 1/500 |
| Khẩu | chính xác · khoảng · nhóm nhanh f/1.0–2.0 · f/2.1–4.0 · f/4.1–8.0 · nhỏ hơn f/8 |
| Tiêu cự | thật + tương đương Full Frame; chính xác · khoảng · nhóm theo góc nhìn |
| Khổ cảm biến | Full Frame · APS-H · APS-C · Micro Four Thirds · 1-inch · Compact · Medium Format · Smartphone · Unknown |
| Tháng chụp | **trong tháng**: một tháng + năm, khớp trọn tháng theo lịch địa phương; chip `Aug 2026`. Bộ lọc đơn giản nhận nó từ câu "tháng bận nhất" của Statistics ([FS-07.02 §2](../FS-07-statistics/02-insights.md)); bộ dựng điều kiện có nó ở trường ngày chụp |
| Sao | **ít nhất N sao** (1–5) hoặc **chưa chấm**, chọn một. Sao hiện hành = sao chờ của ShotDex nếu có, không thì sao của Photos ([FS-01.12 §4](12-rating-and-flags.md)); chip `★ ≥ 3` / `Unrated` |
| Cờ | **Picks · Rejected · Unflagged**, chọn nhiều (OR trong trục). Đọc từ bảng cờ riêng; chip `Picks` / `Rejected` / `Unflagged` |
| Khung giờ chụp | Night · Blue Hour · Golden Hour · Sunrise · Sunset · Day, chọn một ([03b §1–2](03b-time-of-day-and-acceptance.md)) |
| Vị trí | **Has Location / No Location**, theo toạ độ — không theo tên địa điểm ([05b §2](05b-gear-menu-missing-data-and-sheet.md)) |
| Dữ liệu thiếu | phép **is missing** trên các trường có thể rỗng ([05b §2](05b-gear-menu-missing-data-and-sheet.md)) |

Nhóm góc nhìn (theo tiêu cự tương đương): < 20mm Ultra-wide · 20–34 Wide · 35–69 Standard ·
70–134 Portrait / Short telephoto · 135–299 Telephoto · ≥ 300 Super telephoto.

## 5. Menu lọc trên toolbar

Nút lọc là một mục riêng, **tách khỏi Select**; **không còn nút Sort riêng**. Menu này **dùng chung** với
Album Detail và Smart Album ([FS-06.09](../FS-06-collections/09-album-filter-menu.md)) — một chỗ định nghĩa các dòng.

- Phần `Filter:` — All Items · Favorites · Photos Only / Videos Only (hai công tắc **loại trừ nhau**) ·
  Capture Kind ▸ · **Camera ▸** · **Lens ▸** ([05b §1](05b-gear-menu-missing-data-and-sheet.md)) · **Advanced Filter…**
- Ngay sau Favorites: hai hàng phẳng **Picks**, **Rejected** và menu con **Rating ▸** ([FS-01.12 §7](12-rating-and-flags.md)).
  Bộ lọc Rejected đang bật thì thanh điều kiện có viên đỏ **Delete N** ([FS-01.12b §5](12b-culling-pass.md)).
- Menu con **`Sort By`**: Date Taken (Newest/Oldest) + **Date Modified** (Newest/Oldest) + **File Size**
  (Largest/Smallest) — §5.1. Hệ thống **không
  có** ngày-thêm-vào-thư-viện, chỉ có ngày chụp và ngày sửa — nên nhãn phải ghi đúng là *Modified*.
  Migration thêm chỉ mục cho ngày sửa.
- Đường nhanh của hệ thống mở cho **cả hai kiểu sắp theo ngày**, không chỉ ngày chụp.
- Sắp theo thông số (ISO, tiêu cự, khẩu, tốc độ) **vẫn còn** cho truy vấn nhưng **không xuất hiện trong
  menu**; nếu giá trị đang lưu không nằm trong menu thì menu hiện `Newest`.
- **Không có** ô chọn số cột — pinch để đổi mật độ.

### 5.1 Sắp theo dung lượng (chốt 2026-11-07)

Mục đích: tìm ảnh/video nặng nhất để dọn chỗ. Người dùng chốt trong phiên 2026-11-07 (thay cho intent —
đường tắt "Đổi hành vi đã có" ở `docs/PROCESS.md` §4); đảo dòng cũ "Không có sắp theo dung lượng".

- Hai thứ tự mới trong `SortOption`: **`fileSizeLargest`** và **`fileSizeSmallest`**, nhãn
  `File Size (Largest)` / `File Size (Smallest)`, nằm sau hai dòng Date Modified trong `menuOrders`.
- Giá trị là cột `photo_metadata.fileSize` (byte, đã index — tổng resource gốc). Không đọc PhotoKit lúc sắp.
- Thứ tự SQL: `fileSize DESC|ASC NULLS LAST, creationDate DESC NULLS LAST, assetId` — ảnh **chưa biết dung
  lượng xếp cuối** theo ngày chụp mới nhất (người dùng chốt), cả hai chiều; `assetId` phá hoà (§1).
- Không có đường nhanh PhotoKit (`photoKitSortKey == nil`): lưới đọc từ index như các thứ tự thông số.
  Ảnh iCloud chưa index (`cloudPlaceholderItems`) nối vào **cuối**, sau các hàng `fileSize` rỗng.
- Lựa chọn được lưu như các thứ tự khác (`SettingsKeys.librarySort`) và còn sau khi mở lại app.
- Ảnh và video sắp chung một danh sách; bộ lọc Photos Only / Videos Only vẫn áp trước.
- Mac: popover `Sort By` có field thứ ba **File Size**; hàng `Order` đổi nhãn thành **Largest First /
  Smallest First** khi field là File Size (Newest First ↔ Largest First, cùng một công tắc).
- Hiệu năng: **không thêm index** cho `fileSize`. Đo 2026-11-07 trên 55.000 hàng (10 % `fileSize` rỗng, SQLite
  3.54, đúng cột và `ORDER BY` của `gridItems`): sắp toàn bảng 82 ms; có index `fileSize` thì 100 ms — index không
  phủ cột nên mỗi hàng thêm một lần tra rowid, và hai khoá phá hoà vẫn phải sắp. Script đo:
  `docs/_plans/2026-11-07-fs0105-sort-file-size.md` §6.

Đã chốt 2026-11-07:

- **Scrubber chỉ hiện ở bốn thứ tự ngày** (Date Taken / Date Modified); File Size và các thứ tự thông số
  ẩn nó. Cùng lý do, lưới Library trên **Mac bỏ tiêu đề ngày** khi thứ tự không phải ngày (thêm 2026-11-07 sau
  review: chia theo ngày trên danh sách sắp theo dung lượng ra một tiêu đề cho gần như mỗi ảnh).
- **Chỉ Library.** Album Detail / Smart Album giữ `AlbumSortOrder` như cũ.
- **Board:** `MAC_MenuBar` (View ▸ Sort By) vẽ lại thành 6 dòng phẳng như code (`menuOrders`: Date Taken
  Newest/Oldest, Date Modified Newest/Oldest, File Size Largest/Smallest). `IP_MenuBar` là thiết kế đi trước
  (iPad chưa có menu này trong code): Sort By còn Date Taken · Date Modified · File Size rồi hướng; bỏ Name/ISO/
  Focal Length/Aperture/Shutter Speed. `MAC_FilterPopover` thêm field File Size. `PH_LibraryMore` chỉ vẽ
  `Sort By ▸` đóng — không sửa. Bảng List iPad (`IP_LibraryList`) không thêm cột Size — ngoài phạm vi.
- **Mac, bảng List:** cột Size đã có và đang sắp cục bộ; bấm đầu cột Size giờ chọn `fileSizeLargest` /
  `fileSizeSmallest` — cùng một thứ tự với menu và popover.
- **Lần index đầu chưa xong:** như các thứ tự thông số — ảnh chưa vào `photo_metadata` chưa có mặt, dòng đếm
  `N of M` cho thấy thiếu; không thêm UI.

## 6. Chip điều kiện

- Mỗi chip có nút `x`, chữ ngắn và ký hiệu (`ISO 100`, `ISO ≥ 100`, `f 1.4–2.8`, `focal > 50mm`).
- **Clear** ghim ngoài vùng cuộn ngang nên không bị điều kiện dài đẩy khỏi màn.
- Giữ nguyên bộ lọc khi mở ảnh rồi quay lại.

## 7. Tiêu chí nghiệm thu

### 7.1 Sắp theo dung lượng (§5.1)

Dữ liệu chung (S): DB in-memory 6 hàng — A 48 MB (2026-01-03), B 3 MB (2026-05-01), C 3 MB (2026-05-01, id
lớn hơn B), D video 210 MB (2025-12-24), E `fileSize` NULL (2026-06-10), F `fileSize` NULL (2026-02-02).

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-S1 | (S) | `LibraryQueries.items(sort: .fileSizeLargest)` | thứ tự D, A, B, C, E, F | ⚠️ chưa có — `LibraryQueriesSortTests.fileSizeLargest` |
| AC-S2 | (S) | `.fileSizeSmallest` | thứ tự B, C, A, D, E, F — NULL vẫn cuối, B trước C nhờ `assetId` | ⚠️ chưa có — `LibraryQueriesSortTests.fileSizeSmallest` |
| AC-S3 | (S), bật Videos Only | `.fileSizeLargest` | chỉ D | ⚠️ chưa có — `LibraryQueriesSortTests.fileSizeRespectsFilter` |
| AC-S4 | (S) chạy hai lần | `.fileSizeLargest` | hai mảng id giống hệt | ⚠️ chưa có — `LibraryQueriesSortTests.fileSizeIsStable` |
| AC-S5 | `SortOption` | đọc `menuOrders` | 6 phần tử, hai phần tử cuối là `.fileSizeLargest`, `.fileSizeSmallest`; cả hai có `photoKitSortKey == nil` | ⚠️ chưa có — `SortOptionTests.menuOffersFileSize` |
| AC-S6 | `UserDefaults[librarySort] = "fileSizeLargest"` | tạo `LibraryModel` mới | `model.sort == .fileSizeLargest` (không rơi về mặc định) | ⚠️ chưa có — `LibraryModelSortTests.restoresFileSize` |
| AC-S7 | lưới đọc từ index + 2 placeholder iCloud chưa index | `.fileSizeLargest` | placeholder nằm sau mọi hàng có `fileSize`, kể cả NULL | ⚠️ chưa có — `LibraryModelSortTests.placeholdersLast` |
| AC-S8 | 55.000 hàng, 10 % `fileSize` rỗng | sắp `.fileSizeLargest` / `.fileSizeSmallest` toàn bảng | ≤ 150 ms mỗi chiều trên Mac M-series; không có migration index | số đo trong plan §6 (82 / 83 ms) |
| AC-S9 | Mac popover, sort = Date Taken / Newest First | chọn field File Size | `library.sort == .fileSizeLargest`; hàng Order hiện `Largest First` | ⚠️ chưa có — `MacFilterPopoverLogicTests.fileSizeField` |
| AC-S10 | Mac, sort = `.fileSizeSmallest` | `LibrarySortField(sort)` + `isNewestFirst` | `.fileSize`, `false` | ⚠️ chưa có — `MacFilterPopoverLogicTests.fileSizeDirection` |
| AC-S11 | iPhone 17 (26.5), Library | mở Filter and sort ▸ Sort By, chọn File Size (Largest) | menu có 6 dòng, dấu ✓ ở dòng vừa chọn; ô dưới cùng của lưới (chỗ lưới mở ra) là ảnh lớn nhất demo library | ⚠️ chưa có — `ShotDexUITests/scripts/library-sort-filesize.json` + ảnh |
| AC-S12 | như AC-S11 trên iOS 18.6 (nhánh pre-26) và iPad 13" | cùng thao tác | cùng kết quả; menu không cắt chữ | ⚠️ chưa có — cùng script, 2 máy + ảnh |
| AC-S13 | iPhone 17, sort = File Size (Largest), cuộn lưới | đổi Sort By về Date Taken (Newest) | trước: không có scrubber mép phải; sau: scrubber hiện | ⚠️ chưa có — ảnh trước/sau từ AC-S11 |
| AC-S15 | Mac, Library, sort = File Size (Largest) | mở lưới | không có tiêu đề ngày; đổi về Date Taken thì tiêu đề ngày hiện lại | ⚠️ chưa có — ảnh `mac-shot` trước/sau |
| AC-S14 | board `IP_MenuBar`, `MAC_MenuBar`, `MAC_FilterPopover` | `Tools/design-board render` | Mac menu: 6 dòng phẳng như `menuOrders`; iPad menu: field Date Taken · Date Modified · File Size; popover có File Size; không còn Name/ISO/Focal Length/Aperture/Shutter Speed | ⚠️ chưa có — PNG render + `design-parity` |

**Chưa chứng minh được:** AC-S1…AC-S15 — chưa có code.

### 7.2 Phần cũ

Menu Camera/Lens, dữ liệu thiếu, bố cục và nháp của sheet Advanced Search: [05b §5](05b-gear-menu-missing-data-and-sheet.md)
AC-1…AC-27. **Chưa viết** cho phần cũ — xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ). Hai mục mới có AC ở spec
sinh ra chúng: *trong tháng* ở [FS-07.03](../FS-07-statistics/03-acceptance-criteria.md) AC-17, AC-18;
*Unsupported RAW* ở [FS-03.04b](../FS-03-photo-editor/04b-unsupported-raw.md) AC-13. Trục *sao* và *cờ*: [FS-01.12](12-rating-and-flags.md) AC-7.
