# Kế hoạch — Also on Server + Keep in Photos

| Trường | Giá trị |
|---|---|
| Đặc tả | [FS-19.07 §7](../02-functional-spec/FS-19-photo-sources/07-on-server-check.md) + [07b §5](../02-functional-spec/FS-19-photo-sources/07b-on-server-check-ac.md) (AC-246…259) · [FS-06.12](../02-functional-spec/FS-06-collections/12-photos-album-sync.md) (AC-1…17) |
| Ngày | 2026-11-06 |
| Trạng thái | đang làm — người dùng cho phép tự plan và làm luôn (2026-11-06), loop: [ALSO_ON_SERVER_LOOP.md](ALSO_ON_SERVER_LOOP.md) |
| Board | đã vẽ, commit `74008bba`: `PH_/IP_/DI_/DC_/MAC_SmartAlbumEditor`, `PH_/IP_/DI_/DC_/MAC_SmartAlbum` |

## 1. Hiểu đúng chưa

1. Trường mới **Also on Server** (Yes/No + server + folder) thay cho "Source là nguồn server". Source chỉ còn Photos và
   nguồn thư mục/ổ đĩa. Chip `Also on NAS Home › Shared` / `Not on …`. Rule cũ `Source is <server>` tự đổi sang
   trường mới. So khớp, tiến độ, cổng xoá giữ nguyên FS-19.07.
2. Công tắc **Keep in Photos** trên smart album (iOS, không Mac): ShotDex giữ một album thật trong Photos luôn bằng tập
   ảnh Photos của smart album, đồng bộ ghi đè, cả ở nền. Mục đích: người dùng mở album đó trong app Photos → Move to
   Shared Library (PhotoKit không có API).

## 2. Bảng đối chiếu AC ↔ code

### FS-19.07 §5 (Also on Server)

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-246 | ❌ | `RuleField` không có trường này (`Core/Models/SmartAlbumQuery.swift:33-73`); menu Source lấy mọi nguồn (`Features/Shared/RuleBuilderSections.swift:160-167`) | thêm `.alsoOnServer`; lọc server khỏi lựa chọn Source |
| AC-247 | ❌ | `selectableCases` :151-161 không phụ thuộc nguồn | ẩn trường khi không có nguồn server (lọc trong `RuleBuilderSections`/Mac sheet) |
| AC-248 | ❌ | `favoriteEditor` `SmartAlbumRuleRow.swift:321` là mẫu dải Yes/No | `alsoOnServerEditor`: dải Yes/No + menu Server + `folderButton`; chọn sẵn server khi chỉ có một |
| AC-249 | ⚠️→quyết | `isValid` choice cần `text` (:349-352) | rule không có server = chưa đủ, bị bỏ qua (đúng spec); thêm dòng *Choose Server* |
| AC-250 | ✅ một phần | `choiceMenu` xoá folder khi đổi id (:214) | làm y vậy trong menu Server mới + test |
| AC-251 | ✅ SQL | `OnServerPresenceSQL.present/missing` (`Data/Database/OnServerPresenceSQL.swift:24,36`) | `clause(for:)` cho `.alsoOnServer` gọi thẳng present/missing; test chuyển từ `OnServerRuleTests` |
| AC-252 | ❌ | `SmartAlbumRule+Display.swift:25-42` ra `Source is …` | nhánh mới `Also on <name> › <folder>` / `Not on …` |
| AC-253 | ❌ | JSON không biết loại nguồn (`LossyRule` :577) | **quyết (2026-11-06, tự quyết theo lệnh người dùng):** đổi ở tầng Data — `SmartAlbumStore.fetchAllOrdered` + mọi chỗ nạp query có DB chuẩn hoá rule `.source` trỏ tới nguồn server thành `.alsoOnServer` (`isExactly`→Yes, `isNot`→No). SQL cũ `sourceClause` vẫn hiểu server nên không có khoảnh khắc sai |
| AC-254 | ✅ SQL | rule còn `text` nên còn hợp lệ; `isServer` sai + không có bản sao → khớp 0 | không nở ra cả thư viện; khoá bằng test |
| AC-255 | ❌ | `AdvancedSearchSheet.swift:210` dùng `compactDisplaySummary` | cùng nhánh hiển thị mới |
| AC-256 | ❌ | `SmartAlbumDetailModel.swift:88-89` tìm `.source` server | tìm `.alsoOnServer` trước, rồi `.source` server (rule chưa chuẩn hoá) |
| AC-257 | ❓ | cần chụp | `/screens` Duo, iPad |
| AC-258 | ❌ | `MacSmartAlbumEditorSheet.swift:90-97` dùng `SmartAlbumRuleRow` chung | tự có khi row chung đổi; đổi `folderSources`/server list Mac |
| AC-259 | ✅ | `PhotoDeletionGate` không phụ thuộc trường rule | test lại với rule mới |

### FS-06.12 (Keep in Photos)

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 | ❓ | cần iPhone thật có Shared Library | không làm được ở đây; code vẫn làm (người dùng bảo), ghi rõ chưa chứng minh |
| AC-2…8, 10, 12-15, 17 | ❌ | không có bảng/sync nào; `createAlbum/addAssets` `PhotoLibraryService.swift:1146,1162`, `removeAssets/renameAlbum` `+Assets.swift:105,135` | `PhotosAlbumSync` mới |
| AC-9 | ⚠️→quyết | xoá smart album **không có hộp xác nhận** (`AlbumsScreen.swift:520-524`) | **quyết:** chỉ khi Keep in Photos đang bật mới hỏi, câu `The album "…" stays in Photos.` — không thêm ma sát cho album thường |
| AC-11 | ❌ | `PhotoLibraryService.authorizationState` :62 | công tắc disable + chân chữ + nút Settings |
| AC-16 | ❓ | cần chụp | `/screens` |

## 3. Tái dùng

- `OnServerPresenceSQL.present/missing` (không đổi chữ ký), `SmartAlbumRuleRow.folderButton`, `SourceFolderPicker`,
  `favoriteEditor` làm mẫu dải, `SourceStore.serverConnections()`.
- `PhotoLibraryService.createAlbum/addAssets/removeAssets/renameAlbum`, change observer (`collectionChangeToken`,
  `onAssetsChanged`), `OnServerCheck.generation`/`onBatch`, `OnServerBackgroundService.run`.
- `LibraryQueries.whereClause(for:)` để lấy id; thêm `photoKitIds(matching:)` (chỉ mục có bản Photos, `kind='photos'`).

## 4. File đổi

| File | Tầng | Việc |
|---|---|---|
| `Core/Models/SmartAlbumQuery.swift` | model | `RuleField.alsoOnServer`, `RuleFieldKind.server` (không operator, `boolValue` = Yes/No), `isValid` |
| `Core/Models/SmartAlbumRule+Display.swift` | model | chip/summary |
| `Data/Database/SmartAlbumSQLBuilder.swift` | Data | `serverPresenceClause` |
| `Domain/SmartAlbums/SmartAlbumRuleNormalizer.swift` (mới) | Domain | `.source`(server) → `.alsoOnServer`, thuần, test được |
| `Data/Database/SmartAlbumStore.swift` | Data | gọi normalizer khi fetch |
| `Features/Albums/SmartAlbumRuleRow.swift`, `Features/Shared/RuleBuilderSections.swift`, `ShotDexMac/Albums/MacSmartAlbumEditorSheet.swift` | Features | editor |
| `Features/Albums/SmartAlbumDetailModel.swift` | Features | rule tiến độ |
| `Data/Database/AppDatabase+PhotosAlbumSync.swift` (mới) | Data | migration `v61-smartAlbumPhotosAlbum` |
| `Data/Database/SmartAlbumPhotosAlbumStore.swift` (mới) | Data | bảng liên kết |
| `Domain/SmartAlbums/PhotosAlbumDiff.swift` (mới) | Domain | hiệu hai tập, chia lô 500 |
| `Data/Sources/PhotosAlbumSync.swift` (mới) | Data | service `@MainActor`, PhotoKit qua protocol để test |
| `Features/Albums/SmartAlbumEditorSheet.swift`, `SmartAlbumConditionsBar.swift`, `SmartAlbumDetailScreen.swift`, `AlbumsScreen.swift`/`AlbumsModel.swift` | Features | công tắc, dòng trạng thái, hộp xoá |
| `App/AppDependencies.swift`, `App/OnServerBackgroundService.swift` | App | nối kích hoạt |

## 5. Thứ tự task (một task = một commit, push sau mỗi commit)

| # | Task | AC | Test |
|---|---|---|---|
| 1 | Model + SQL + hiển thị `.alsoOnServer` | 251, 252, 254, 255 | `AlsoOnServerRuleTests` (chuyển dữ liệu `OnServerRuleTests`), `SmartAlbumOperatorTests` |
| 2 | Normalizer rule cũ + store | 253 | `SmartAlbumRuleNormalizerTests`, `SmartAlbumRuleDecodingTests` |
| 3 | Editor iOS + Mac: trường, dải, Server, Folder, lọc Source | 246-250, 258 | `SmartAlbumFieldTests` + `/screens` |
| 4 | Tiến độ theo Also on Server | 256, 259 | `OnServerProgressTests` |
| 5 | Migration + store liên kết | FS-06.12 §5 | `SmartAlbumPhotosAlbumStoreTests` |
| 6 | `PhotosAlbumDiff` + `PhotosAlbumSync` (tạo, đồng bộ đè, lô, lỗi, xoá trong Photos, đổi tên, bật lại dùng lại) | 2-8, 10, 12, 13, 15, 17 | `PhotosAlbumSyncTests` (PhotoKit giả) |
| 7 | UI: công tắc editor, dòng trạng thái, hộp xoá, limited | 9, 11, 16 | `/screens` |
| 8 | Kích hoạt: lưu, đợt On Server, đổi thư viện, nền | 4, 14 | `PhotosAlbumSyncTests.runsAfterBackgroundCheck` |
| 9 | Review ×2 + sửa | — | — |
| 10 | Chụp mọi thiết bị, so board, `/verify` từng phần | 16, 257 | ảnh |

## 6. Rủi ro

| Rủi ro | Xử lý |
|---|---|
| Hai session sửa cùng file (Mac loop đang chạy trên `ShotDexMac/*`) | commit chỉ đường dẫn của mình (`git commit -- <paths>`); `fetch` + `rebase` trước push chỉ khi cây sạch đường dẫn của mình; không `stash`/`reset`/`checkout --` |
| Migration số trùng với session khác | đặt tên theo chức năng, kiểm số mới nhất ngay trước commit |
| PhotoKit ghi trên simulator thật | thư viện test không mặt người; chỉ album do test tạo |
| Move to Shared Library đổi id (AC-1) | chưa đo được; ghi rõ |
| Duo trong 669pt: điều kiện thêm một hàng | board cho phép cuộn; AC-4 FS-06.08 vẫn kiểm |

## 7. Agent cho review

Vòng 1: `caveman:cavecrew-reviewer` (diff) + `photokit-guard` + `data-migration`.
Vòng 2: `swift-concurrency` + `ux-reviewer` + `design-parity`.

## 8. Cách chứng minh là xong

- Test: các test trên chạy riêng từng class (`/test`), không full suite (luật gate thủ công).
- Màn chụp: editor (Also on Server, Keep in Photos), smart album (chip, dòng trạng thái synced/updating/deleted), hộp xoá;
  iPhone 26.5 + 18.6, iPad, Duo trong/ngoài, Mac editor; sáng + tối.
- Tài liệu: cột "Chứng minh bằng" của 07b §5 và FS-06.12 §7; dòng Tiến độ của hai intent.
