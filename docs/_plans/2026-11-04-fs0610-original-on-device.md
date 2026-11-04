# Kế hoạch — FS-06.10 Bản gốc trên máy

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-06.10`](../02-functional-spec/FS-06-collections/10-original-on-device.md) (14 AC) |
| Intent | [2026-11-04-smart-album-local-original](../_intents/2026-11-04-smart-album-local-original.md) |
| Ngày | 2026-11-04 |
| Trạng thái | duyệt 2026-11-04 — loop [FS0610_LOOP](FS0610_LOOP.md) |

## 1. Hiểu đúng chưa

Mỗi máy tự kiểm, không dùng mạng, xem từng ảnh Photos đã có **mọi** resource gốc trên máy chưa (ảnh, video của Live
Photo, video, bản render nếu đã sửa). Kết quả ghi vào một bảng riêng, chạy tiếp được khi bị cắt, không mất khi index
lại. Trường **Original** (*On This iPhone* / *iCloud Only*) của bộ dựng điều kiện và mục bật/tắt trong menu Filter
đọc bảng đó. Ảnh chưa kiểm không vào bên nào. Quét lại toàn bộ chỉ khi có màn đang dùng trường này và lần quét trước đã
quá 24 giờ. Ảnh PhotoKit báo đổi thì về *chưa kiểm*.

## 2. Đối chiếu AC ↔ code

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 spike | ❌ | `OnServerSpike.swift:135` đọc KVC `locallyAvailable` cho **một** resource, chỉ có trong DEBUG | mở rộng spike: đo (a) và (b) trên mọi resource, máy thật 55k |
| AC-2 is / is not / chưa kiểm | ❌ | chưa có trường. Có mẫu để chép: `SmartAlbumSQLBuilder.swift:204-226`, `OnServerPresenceSQL.swift:24-47` (chưa kiểm không vào bên nào) | trường `.choice` mới + mệnh đề `IN (… state)`, không dùng `NOT IN` |
| AC-3 Live Photo | ❌ | `OriginalFetcher.swift:75-89` chỉ chọn một resource | hàm thuần ở Domain: danh sách resource → trạng thái |
| AC-4 ảnh đã sửa | ❌ | như AC-3 | như AC-3 |
| AC-5 không mạng | ⚠️ gần có | `OriginalFetcher.probe` đã tắt mạng (`:95`) | dùng lại probe cho từng resource, test đếm request |
| AC-6 chạy tiếp | ❌ | `OnServerCheck` không có con trỏ, tiến độ nằm trong trạng thái DB | dùng chính các dòng trạng thái làm con trỏ (kiểm ảnh *chưa có dòng / chưa kiểm* trước) |
| AC-7 index lại | ❌ | mẫu: `kept_items` (`AppDatabase+Kept.swift:14-26`) và `photo_flag` (`AppDatabase.swift:616`), index không đụng (`MetadataStore.swift:37-58`) | migration `v58`: bảng riêng theo assetId, không khoá ngoại |
| AC-8 PhotoKit đổi | ❌ | `PhotoLibraryService.swift:1253-1285` bỏ qua `changedObjects` | đọc ảnh đổi ở đó, đánh dấu *chưa kiểm* |
| AC-9 `.limited` | ❌ | mẫu chữ có sẵn: `OnServerProgressLine.swift:50-53` | đếm tổng theo ảnh app thấy được |
| AC-10 kết hợp Source | ❌ | `SmartAlbumSQLBuilder.swift:16-33` nối AND/OR sẵn | có ngay khi có AC-2; thêm test |
| AC-11 menu Filter | ❌ iOS · ❌ Mac | iOS: `PhotoFilterMenu.swift:59-69`, `LibraryQueries.swift:418`, `FilterTokenBar.swift:370`, `LibraryModel.swift:188-205` (loại trừ với truy vấn nâng cao). Album dùng đường PhotoKit (`AlbumFilter.swift:46`), nên phải truyền danh sách id. **Mac: nút Filter đang là nút rỗng** (`MacRootWindow.swift:193`) | iOS làm theo mẫu Favorites; Mac dựng popover (Q1) |
| AC-12 Mac Download Originals | ❌ | trường dùng chung nên có sẵn; Mac cần chạy lượt kiểm trong app hoặc helper (`MacAgent.swift:79-116`) | chạy lượt kiểm trong app Mac (helper chỉ lo việc server) |
| AC-13 chỉ is / is not | ✅ sẵn khi thêm `.choice` | `SmartAlbumQuery.swift:158-174` `.choice` → [is, is not] | viết test lặp qua mọi trường (chưa có test nào làm thế) |
| AC-14 khớp board | ❌ | board chưa có trường mới | T0 vẽ board trước, cuối cùng chạy `design-parity` |

**Dùng lại, không làm lại:** chọn trường và phép (`SmartAlbumRuleRow.swift:43-61`, `choiceValues`) · probe tắt mạng
(`OriginalFetcher.swift:91-150`) · khuôn của lượt nền: `OnServerCheck` (`@MainActor @Observable`, các closure môi
trường để test, bộ đếm generation) · dòng tiến độ (`OnServerProgressLine`, `refreshOnServer` trong
`SmartAlbumDetailModel.swift:85-104`) · chip (`FilterTokenBar.tokens`) · đổi bộ lọc thành rule
(`SmartAlbumQuery.migrating`, `:418-462`, phải thêm trường mới vào đây, không thì Save as Smart Album làm rơi nó).

## 3. Câu hỏi ⚠️ — đã trả lời (người dùng, 2026-11-04)

- **Q1 — Mac chưa có menu Filter** (`MacRootWindow.swift:193` là nút rỗng): **làm luôn popover** theo
  [FS-18.02 §5](../02-functional-spec/FS-18-mac-app/02-library-viewer-cull.md) và FS-18 **AC-35**, cộng mục
  *Original on This Mac* (đã thêm vào FS-18.02 §5).
- **Q2 — câu cảnh báo khi xoá:** **không cần**. AC-15 đã bỏ khỏi FS-06.10, hộp xoá giữ như hôm nay.

## 4. File đổi

| File | Đụng gì | Tầng |
|---|---|---|
| `Domain/ICloud/OriginalPresence.swift` | mới: các resource kèm kết quả từng cái → *có / không / chưa biết* | Domain |
| `Data/Database/AppDatabase+OriginalPresence.swift` | mới: migration `v58-originalPresence` | Data |
| `Data/Database/OriginalPresenceStore.swift` | mới: ghi trạng thái, đánh dấu *chưa kiểm*, lấy lô kế tiếp, đếm tiến độ | Data |
| `Data/Sources/OriginalPresenceCheck.swift` | mới: lượt nền theo khuôn `OnServerCheck`, lô 200, nhường, tắt mạng | Data |
| `Data/Sources/OriginalFetcher.swift` | probe từng resource được, không chỉ resource chính | Data |
| `Data/Sources/PhotoLibraryService.swift` | đọc `changedObjects`, báo ảnh đổi | Data |
| `Core/Models/SmartAlbumQuery.swift` · `SmartAlbumRule+Display.swift` | trường **Original**, giá trị, nhãn, `migrating` | Core |
| `Data/Database/SmartAlbumSQLBuilder.swift` · `LibraryQueries.swift` | mệnh đề bảng trạng thái | Data |
| `Core/Models/FilterCriteria.swift` · `Features/Shared/PhotoFilterMenu.swift` · `Features/Library/FilterTokenBar.swift` · `Domain/Filtering/AlbumFilter.swift` | mục bật/tắt, chip, danh sách id cho album | Core/Features |
| `Domain/OnServer/OnServerProgressLine.swift` (hoặc file chữ mới cạnh nó) · `SmartAlbumDetailModel.swift` · `SmartAlbumDetailScreen.swift` · `MacSmartAlbumScreen.swift` | dòng tiến độ, kích hoạt khi mở | Features |
| `App/AppDependencies.swift` · `ShotDexMac/MacDependencies.swift` · `ShotDexApp.swift` | nối lượt kiểm, chạy khi vào trước mặt | App |
| `ShotDexMac/MacRootWindow.swift` · `ShotDexMac/Library/MacFilterPopover.swift` (mới) | nút Filter mở popover; popover dùng chung model lọc với Library | Features (Mac) |
| `docs/design/*/project/*SmartAlbumEditor*`, `*SmartAlbum*`, `PH_LibraryMore` | trường mới, dòng tiến độ, mục menu | Design |

## 5. Thứ tự task (một task = một commit)

| # | Task | AC | Test kèm |
|---|---|---|---|
| T0 | board: trường Original trong editor (4 máy + Mac), dòng tiến độ trong `PH_/MAC_SmartAlbum`, mục menu `PH_LibraryMore`; publish canvas | AC-14 (đích) | — |
| T1 | spike: harness DEBUG đo (a) probe mọi resource tắt mạng và (b) KVC trên 55k; báo cáo vào `docs/_intents/` | AC-1 | đo tay trên iPhone thật của người dùng |
| T2 | test lặp qua mọi trường cho phép (khoá AC-13 trước khi có trường mới) | AC-13 | `SmartAlbumOperatorTests.everyFieldOperators` |
| T3 | Domain: danh sách resource → trạng thái | AC-3, AC-4 | `OriginalPresenceTests` (resource giả) |
| T4 | migration v58 + store | AC-6, AC-7 | `OriginalPresenceStoreTests` (in-memory, có upsert metadata) |
| T5 | trường Original + SQL + chip + `migrating` | AC-2, AC-10, AC-13 | `OriginalPresenceRuleTests` |
| T6 | lượt kiểm nền (chọn cách đo theo T1), tắt mạng, `.limited` | AC-5, AC-9 | `OriginalPresenceCheckTests` (môi trường giả, đếm request) |
| T7 | kích hoạt: vào trước mặt, mở màn có trường + luật 24 giờ, PhotoKit đổi → chưa kiểm | AC-8 | `OriginalPresenceCheckTests.changedAssetRechecked` |
| T8 | dòng tiến độ ở màn smart album iOS + Mac | AC-14 (một phần) | `OriginalPresenceProgressTests` + ảnh |
| T9 | menu Filter iOS: mục bật/tắt, chip, Library + album | AC-11 | `Tools/ui-drive` + ảnh 26.5 và 18.6 |
| T10 | Mac: lượt kiểm trong app, trường trong smart album, dòng tiến độ | AC-12 | đo tay + ảnh `mac-shot` |
| T11 | Mac: popover Filter and Sort 360×480 (FS-18.02 §5) dùng chung `FilterCriteria`, chip trên thanh lọc, dòng phụ *N of M photos*, mục *Original on This Mac* | FS-18 AC-35, AC-11 (Mac) | `mac-filter-popover.json` + `design-parity` `MAC_FilterPopover` |
| T12 | `design-parity` mọi board đã đụng, `/verify FS-06.10` | AC-14 | agent `design-parity` |

T11 là việc của FS-18 (AC-35), nằm trong plan này vì người dùng chọn làm cùng. T1 cần iPhone thật của người dùng. T3–T5 không phụ thuộc T1, làm song song được. T6 chờ T1 chọn cách đo.

## 6. Rủi ro

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| Cách (a) quá 2 giờ cho 55k, buộc phải dùng KVC | vừa | spike T1 đo trước khi viết T6; KVC chỉ dùng sau khi người dùng chốt |
| `changedObjects` tới dồn dập khi iCloud đồng bộ (change-token storm) | cao | gộp theo debounce 1s đã có; chỉ đánh dấu *chưa kiểm*, không kiểm ngay |
| Lượt kiểm tranh tài nguyên với index lúc mới cài | vừa | chạy sau index, nhường như các lượt chậm khác (NF-01 §1.5) |
| Migration v58 | thấp | bảng mới, không đụng bảng cũ; xoá bảng thì chỉ mất công kiểm lại |
| Duo trong 669pt: dòng tiến độ thêm một dòng dưới thanh điều kiện | thấp | dùng chung chỗ của dòng On Server, không thêm hàng mới |

Agent ở bước review: `photokit-guard` (probe, changedObjects, `.limited`) · `data-migration` (v58) ·
`swift-concurrency` (lượt nền) · `perf-profiler` (55k, SQL) · `ios26-parity` (menu Filter) · `device-layout`
(Duo, iPad, Mac).

## 7. Cách chứng minh là xong

- Test: các test ở §5, cộng các test hiện có của smart album và xoá vẫn xanh.
- Ảnh: editor có trường Original; album có dòng tiến độ *Checking originals…* và *checked … ago*; menu Filter bật mục
  mới. Chụp iPhone 26.5 + 18.6, iPad, Duo trong và ngoài, Mac.
- Tài liệu: cột "Chứng minh bằng" của FS-06.10; FS-06.08 §2 thêm hàng cho trường Original; dòng Tiến độ của intent.
