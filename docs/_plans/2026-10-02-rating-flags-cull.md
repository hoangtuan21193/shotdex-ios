# Kế hoạch — Sao, cờ Pick/Reject và lượt lọc Cull (FS-01.12 + FS-01.12b)

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-01.12`](../02-functional-spec/FS-01-library/12-rating-and-flags.md) 11 AC (AC-11 thêm lúc duyệt) · [`FS-01.12b`](../02-functional-spec/FS-01-library/12b-culling-pass.md) 8 AC · dòng đi kèm ở [BD-02 §2–§4](../01-basic-design/BD-02-database-design.md) (hai bảng mới + cột `rating`), [FS-01.05 §4–§5](../02-functional-spec/FS-01-library/05-filtering-and-sorting.md) (trục sao/cờ, menu lọc, viên Delete), [FS-06.08 §2](../02-functional-spec/FS-06-collections/08-smart-albums.md) (trường sao/cờ) |
| Intent | [2026-09-30-user-wishes-research](../_intents/2026-09-30-user-wishes-research.md) mục 9 |
| Ngày | 2026-10-02 |
| Trạng thái | **approved 2026-10-03** — 19 task code = 19 commit (19 AC; task 2 mang AC-11 mới và là hạ tầng dùng chung với FS-02.07), đi sau 2 việc chuẩn bị (P1–P2) và 3 phép đo (M1–M3). Quyết định ở §9 |

> Dòng `Tiến độ` của intent đã ghi lúc duyệt 2026-10-03. Task đầu tiên ghi `**đang làm**` theo `docs/PROCESS.md` §2.

> **Chủ của đường "updated dù ngày sửa không đổi"**: plan này (task 2, `IndexRunChanges`). Plan
> [caption-keywords](2026-10-02-caption-keywords.md) task 20 chỉ tiêu thụ nó. Cũng ở đây: hàm dùng chung "đóng dấu
> ngày sửa sau khi app ghi thuộc tính Photos" (nếu M1 nói cần) và protocol ghi `PhotoPropertyWriting` — plan nào
> commit trước thì tạo, plan kia thêm phương thức của mình vào cùng chỗ.

## 1. Hiểu đúng chưa

Ba trục độc lập: favorite (Photos), **cờ** Pick / Reject / không cờ (chỉ ShotDex, bảng `photo_flag`, không đồng bộ),
**sao** 0–5. Sao có hai chỗ lưu: dưới iOS 27 ở bảng `pending_photo_rating` của app; từ iOS 27 ở chính Photos
(`PHAsset.rating`, `PHAssetChangeRequest.rating` — header SDK 27.1 `PHAsset.h:71`, `PHAssetChangeRequest.h:39`), có cột
`photo_metadata.rating` chỉ để lọc nhanh, đọc lại được từ ảnh như favorite. **Sao hiện hành = dòng chờ nếu có, không
thì cột Photos** — một luật cho mọi đời iOS. Lần mở app đầu trên iOS ≥ 27 chuyển cả bảng chờ lên Photos bằng **một**
khối thay đổi (giữ sao Photos đã có, bỏ dòng ảnh đã xoá, `.limited` chỉ ghi ảnh thấy được, lỗi thì giữ nguyên và thử
lại lần mở sau). Đặt sao/cờ ở menu giữ-lâu, ⋯ của chế độ chọn, ⋯ của viewer và phím `0–5 P X U`; thấy trên ô lưới
(góc dưới-trái, Rejected mờ 45 %), dòng 2 bảng thông tin viewer, VoiceOver; lọc bằng hai hàng Picks/Rejected + menu con
Rating trong menu lọc dùng chung, Advanced Filter và smart album. Màn **Cull** tier D mới đi tuần tự cả buổi chụp
(theo ngày chụp, cũ trước; mở ở ảnh đầu chưa cờ), một chạm/phím/vuốt mỗi tấm, đặt cờ thì sang tấm sau, có undo, thẻ
tóm tắt ở tấm cuối, và **Delete Rejected** qua hộp thoại xoá của hệ thống — từ thẻ tóm tắt hoặc viên đỏ trên thanh
điều kiện khi lọc Rejected. Hôm nay **không có dòng code nào** của tính năng này: bảng cũ đã bị gỡ ở `v15`/`v16`, và
`grep "#available(iOS 27"` = 0.

## 2. Phép đo và việc chuẩn bị — làm đầu tiên

| # | Việc | Cách làm | Quyết định nó lái |
|---|---|---|---|
| P1 | DESIGN.md §8 thêm 4 dòng từ điển icon: sao `star`/`star.fill`, Pick `flag.fill`, Reject `xmark`, lượt lọc `flag.2.crossed` (spec FS-01.12 §6 đòi "trước khi code") | một commit docs, chép đúng symbol spec đã chốt | mọi task UI |
| P2 | Board trên canvas [editor](../design/README.md) **đã có** từ Version 60: `PH23`–`PH28`, `IP15`–`IP19`, `IPP15`, `DI14`, `DIP14`, `DC15` (ô lưới có glyph, dòng 2 viewer, menu lọc, Cull × 4 máy, thẻ tóm tắt, viên Delete) | **export** `project/` của canvas vào `build/design/editor/project/`, `Tools/design-board render`, ghi **tên board** vào cột "Chứng minh" của từng task bên dưới — không chờ vẽ | mọi task UI có board để `design-parity` |
| M1 | Sao trên PhotoKit, sim iPhone 17 **iOS 27.0** (chọn bằng `id=`): ghi `rating` cho 1 / 300 / 2.000 asset trong **một** `performChanges` — được không, bao lâu, có hộp thoại không; `modificationDate` có đổi không; id có vào `updatedLocalIdentifiers` của `fetchPersistentChanges` không; `PHChange` có bị `isStructural` coi là đổi cấu trúc không (`PhotoLibraryService.swift:1231-1244`); `PHFetchOptions.predicate` có nhận khoá `rating` không; video có sao không | **cùng bộ probe** với FS-02.07 M1 (`CaptionKeywordProbeTests` — đổi tên `PhotoPropertyProbeTests` nếu sao đo trước): chạy trong test bundle host là app, tự bỏ qua khi OS < 27 hoặc chưa có quyền, không chạy trong `Tools/gate`. Ảnh nhiễu sinh bằng ImageIO, không mặt người, `simctl addmedia`; quyền bằng một chạm *Allow Full Access* qua `ui-drive` | ngày sửa đổi → task "đóng dấu ngày sửa" (hàm chung với FS-02.07) trong task 7; không vào `updated` → cột sao chỉ tươi qua walk đầy, AC-11 không đạt như viết: ghi số đo vào FS-01.12 §10 và hỏi (❓-2); không nhận predicate `rating` → màn album lọc sao bằng danh sách id (task 5) |
| M2 | **Máy thật** 55k: một khối 10.000 yêu cầu sao (trần? thời gian, RAM đỉnh); 800 lần ghi trong 10 phút (nhiệt, pin — FS-01.12b §7); xoá ảnh chỉ iCloud không tải | log `IndexTrafficMonitor` + Instruments | có trần → chia khối 1.000 nối tiếp (spec FS-01.12 §10) và **AC-3 "đúng 1 khối" phải sửa** (❓-1). Không chặn task nào trước task 9 |
| M3 | `Tools/ui-drive` có gửi được **phím cứng** không (`XCUIElement.typeKey` trên iPad sim 26.5 và 27.0) | một script 2 bước trên viewer: `typeKey "f"` rồi dump trạng thái favorite | được → thêm bước `key` vào driver (`ShotDexUITests/UIDriverTests`), mọi AC phím có ui-drive; không → AC phím chứng minh bằng unit test của bảng phím + model, ảnh chụp sau khi chạm (❓-4) |

## 3. Đối chiếu AC ↔ code

### FS-01.12

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 iOS 26.5, viewer, phím `4` → 1 dòng chờ A=4; bảng chính không đổi; Clear index + index lại vẫn lọc ra A | ❌ (một phần ✅) | không bảng, không phím: bảng `photo_cull` đã bị xoá ở `v16` (`Data/Database/AppDatabase.swift:375-378`); phím viewer chỉ có `F`, `I`, Delete, ⌘S (`Features/Library/PhotoDetailScreen.swift:674-732`). ✅ Clear index chỉ gọi `MetadataStore.deleteAll()` (`Features/Settings/SettingsScreen.swift:78` → `Data/Database/MetadataStore.swift:284-294`), chỉ xoá `photo_metadata` + trạng thái index — bảng mới sẽ sống qua nó | migration mới (số kế tiếp **lúc commit**; hôm nay `v27`, FS-02.07 cũng lấy một số): `photo_flag`, `pending_photo_rating`, cột `photo_metadata.rating` + chỉ mục. `PhotoMarksStore` + `PhotoMarks` (chỉ mục trong bộ nhớ). Phím `0–5` + menu con **Rating ▸** trong ⋯ viewer; dòng 2 bảng thông tin. Test khoá "Clear index không đụng bảng sao/cờ" |
| AC-2 iOS 27, chọn 300 → ⋯ Rating ★★★ → 1 khối 300 yêu cầu; đọc lại = 3; bảng chờ 0; lưới không nạp lại | ❌ (một phần ✅) | không có ⋯ Rating (`Features/Library/SelectionBarViews.swift:301-330`, khối Favorite); không có writer PhotoKit cho sao. ✅ thay đổi chỉ nội dung không tăng `assetChangeToken` nên lưới và index không chạy lại (`Data/Sources/PhotoLibraryService.swift:58-68`, `:1214-1222`, `:1231-1244`) — **chờ M1** xác nhận ghi sao là thay đổi nội dung | `PhotoPropertyWriting` (protocol, Data; bản PhotoKit sau `#available(iOS 27, *)`, bản giả cho test) — **một** `performChanges` cho cả lệnh; ghi xong cập nhật `photo_metadata.rating` + xoá dòng chờ của các id đó. Rating ▸ / Flag ▸ trong ⋯ chọn + menu giữ-lâu + phím cho lựa chọn |
| AC-3 lần mở đầu trên iOS 27: 1.240 dòng chờ, 5 ảnh đã xoá, 3 ảnh Photos có sao → 1 khối 1.232; 3 giữ sao Photos; bảng chờ 0; banner một lần | ❌ | — | `RatingMigrationPlan` (Domain, thuần) + `RatingMigrationPass` (Data) chạy trong `.task` lúc mở app (`App/ShotDexApp.swift:93-101`, sau first paint, cạnh `backfillMediaSubtypes`); banner qua `AppBannerModel.show` (`App/AppBanner.swift:59`), số nhiều qua String Catalog. **Phụ thuộc M2** (❓-1) |
| AC-4 như AC-3, khối lỗi → giữ 1.240; lọc ★≥1 vẫn đủ; không banner; lần mở sau thử lại đúng 1 lần | ❌ | — | nhánh lỗi của pass; cờ "đã thử trong lần mở này" trong bộ nhớ, không lưu đĩa |
| AC-5 iOS 27 `.limited` thấy 200/1.240 → 200 yêu cầu; 1.040 ở lại; không gỡ dòng nào | ❌ | — | `RatingMigrationPlan` nhận `accessIsFull`; dưới `.limited` id không fetch được **không** bị coi là đã xoá |
| AC-6 A favorite, `P` rồi `X` → Picked rồi Rejected; favorite không đổi | ❌ (một phần ✅) | ✅ favorite đi đường riêng, chỉ khi bấm `F`/menu (`App/AssetActionsCoordinator.swift:96-117`); ❌ không có cờ | `PhotoMarks.setFlag` (ba trạng thái loại trừ, không bao giờ gọi đường favorite); phím `P X U` + **Flag ▸**; glyph cờ + sao trên ô, Rejected mờ 45 %, VoiceOver |
| AC-7 10 ảnh, Rating ★★★ & Up + Picks → 2 ảnh; chip "★ ≥ 3", "Picks"; x Picks → 6 | ❌ | `FilterCriteria` không có trục sao/cờ (`Core/Models/FilterCriteria.swift:112-148`, `isEmpty` `:150-167`); SQL ở `Data/Database/LibraryQueries.swift:324-468` (favorite `:404-406`); menu `Features/Shared/PhotoFilterMenu.swift:54-90` (6 hàng); chip `Features/Library/FilterTokenBar.swift:161-320`; màn album hỏi Photos và id (`Domain/Filtering/AlbumFilter.swift:42-80`, `needsIndex` `:103-109`, assert ở `Features/Albums/AlbumsModel.swift:642`, `:719`) | `ratingFilter` + `flags` trong `FilterCriteria` (giải mã khoan dung có sẵn `:207-226`), SQL `IN (SELECT …)` theo mẫu `RAWVerdictStore.unreadableSQL` (`Data/Database/RAWVerdictStore.swift:30-38`), hai hàng + menu con, chip, nhánh album bằng danh sách id (`AlbumFilterPredicate.identifierPredicate`) |
| AC-8 smart album "Best" = cờ là Pick VÀ sao ít nhất 4 (12) → Reject 1 → 11; một điều kiện cờ lạ chỉ nó rơi | ❌ (cơ chế ✅) | ❌ `RuleField` không có `rating`/`flag` (`Core/Models/SmartAlbumQuery.swift:30-48`, kind `:21-27`, toán tử `:118-126`). ✅ trường lạ rơi ra nhờ `LossyRule` (`:389-395`, test `ShotDexTests/SmartAlbumRuleDecodingTests.swift:27`); giá trị chọn lạ → `clause` trả nil (mẫu `Data/Database/SmartAlbumSQLBuilder.swift:63-74`) | `RuleField.rating` (kind mới `.rating`, toán tử `is` · `atLeast` · `atMost`) + `RuleField.flag` (kind `.choice`: pick · reject · unflagged); SQL; hàng soạn (`Features/Albums/SmartAlbumRuleRow.swift`), chip (`SmartAlbumConditionsBar.swift`). Tên trường `rating`/`flag` dùng lại — `v15`/`v16` đã chạy xong (BD-02 §4), không sửa migration cũ |
| AC-9 B Rejected bị xoá trong Photos → dòng cờ gỡ; C `.limited` bị bỏ khỏi phần chia sẻ → dòng cờ còn | ❌ | lượt index gỡ dòng ở hai chỗ: walk đầy (`Domain/Indexing/IndexPipeline.swift:524-532`) và lịch sử thay đổi (`:711-718`); **dưới `.limited` walk đầy cũng gỡ dòng `photo_metadata` của ảnh không chia sẻ** (fetch chỉ trả ảnh thấy được) — nên "cùng lúc" không thể làm nguyên văn | gỡ dòng sao/cờ đi **cùng** lượt index gỡ dòng nhưng chỉ khi quyền đầy đủ (`UserMarkRemovalPolicy`, Domain); xoá từ app (`LibraryModel.swift:1387-1399` và 6 chỗ giống nó) luôn gỡ. Đi qua `IndexRunChanges` của task 2 |
| AC-10 iOS 27, A 2★, ghi lỗi, phím `5` → ô và viewer về 2★ ≤ 1 s; "Couldn't save rating." + Try Again; bảng chờ không dòng | ❌ | — | `PhotoMarks` giữ giá trị lạc quan theo id, lỗi thì bỏ và tăng `version`; banner có hành động |

### FS-01.12b

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 Cull 240 ở ảnh 37: `P`, `3`, ⌘Z ×2 | ❌ | — | `CullSession` (Domain, thuần): vị trí, tự sang ảnh sau khi đặt **cờ**, đứng lại khi đặt **sao**, ngăn undo lùi về đúng ảnh |
| AC-2 iPhone: vuốt lên ở 1× → Pick + sang 11; ở 2× vuốt xuống là kéo ảnh | ❌ | viewer đã có mẫu UIKit `UISwipeGestureRecognizer` trên pager (`PhotoDetailScreen.swift:3016-3030`) — SwiftUI gesture chết trong nội dung host của `UIScrollView` (memory); `ZoomableImageView` báo mức phóng qua `onZoomChange` (`Features/Library/ZoomableImageView.swift:16`) | recognizer dọc chỉ bật khi mức phóng = 1 (`CullGesturePolicy`, thuần) |
| AC-3 chọn 240, 36 sớm nhất có cờ → mở ở ảnh 37, "37 / 240" | ❌ | lối vào: ⋯ chọn, Combine ở `SelectionBarViews.swift:213-227`; `PhotoCommand` (`Features/Shared/PhotoCommand.swift:6-58`); ⋯ viewer `PhotoDetailScreen.swift:744` | `CullSession.start` (ngày chụp tăng dần, phá hoà bằng id, ngày rỗng cuối — luật FS-01.05 §1); màn `Features/Library/Cull/`; lối vào **Cull N Photos** ngay sau Combine Photos + **Cull From Here** |
| AC-4 240 ảnh, đặt `X` ở ảnh cuối → thẻ "240 photos · 52 picks · 120 rejected · 68 unflagged" + 3 nút | ❌ | — | `CullSummary` (thuần) + thẻ |
| AC-5 4 máy: 5 sao, Pick, Reject, Undo, ✕, bộ đếm ≥ 44×44, trong vùng an toàn; Duo ngoài không x > 382 | ❌ | — | bố cục §5 theo máy; đo bằng `Tools/ui-drive` dump + `Tools/sim-shot` |
| AC-6 album X 240 ảnh/120 Rejected, ngoài X 30 Rejected → viên Delete 120 → đúng 120 id; 30 kia còn; 120 dòng cờ gỡ; banner 30 ngày | ❌ (một phần ✅) | ✅ xoá qua `PHAssetChangeRequest.deleteAssets` → hộp thoại hệ thống (`Data/Sources/PhotoLibraryService.swift:961-966`), chỉ id truyền vào; lọc album bằng danh sách id có sẵn (`AlbumsModel.swift:756`, `:784`). ❌ không viên Delete trên thanh điều kiện (`FilterTokenBar.swift:92-135`, ba màn: `LibraryScreen.swift:539`, `AlbumDetailScreen.swift:289`, `SmartAlbumDetailScreen.swift:257`) | `RejectedDeletion` (Domain: id = ảnh lưới đang hiện ∩ Rejected) + chỗ nối `deleteAssets` giả được cho test; viên đỏ ghim cạnh Clear; gỡ dòng cờ sau khi xoá |
| AC-7 Cancel ở hộp thoại → 0 ảnh mất, 120 vẫn Rejected | ❌ (cơ chế ✅) | ✅ PhotoKit làm cả mẻ hoặc không gì; Cancel ném `PHPhotosError.userCancelled` (doc `PhotoLibraryService.swift:957-960`) | nhánh huỷ: không đổi gì; nhánh lỗi: thông báo + Try Again (NF-04) |
| AC-8 50 ảnh chỉ iCloud, mất mạng → bản có trên máy + glyph mây; 50 cờ ghi; 0 yêu cầu bản gốc | ❌ (một phần ✅) | ✅ `requestDetailImage` cỡ màn có cờ mạng (`PhotoLibraryService.swift:573-628`); glyph mây theo `OriginalFetching.probe` (`Data/Sources/OriginalFetcher.swift:52-66`), sim giả lập bằng `-ShotDexFakeICloud` (`Data/Sources/FakeOriginalFetcher.swift:1-40`) | trang Cull chỉ xin bản **cỡ màn**, không có đường bản gốc (khác `PhotoDetailPage`, nơi phóng kéo bản gốc); cờ ghi không cần ảnh |

### Phần spec không có AC riêng

| Mục | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| BD-02 §1, §2: cột `rating` "đọc lại từ ảnh như favorite, đồng bộ lại khi thư viện báo thay đổi" | ❌ — nay là **FS-01.12 AC-11** (thêm lúc duyệt, ⚠️-2) | cột chưa có; `needsReindex` bỏ qua id có ngày sửa không đổi (`IndexPipeline.swift:316-331`, `:740-747`), nên id trong `changes.updated` (`:695`) mà chỉ đổi sao/favorite không bao giờ được đọc lại; tập `updated` không ra khỏi hàm. Favorite hôm nay cũng chỉ tươi khi đổi trong app (`MetadataStore.updateFavorite` `:128`) | task 2 (hạ tầng dùng chung FS-02.07 AC-10) |
| FS-01.05 §5 menu lọc 9 hàng, iOS 26 và trước 26 giống nhau | ❌ | 6 hàng hôm nay (`PhotoFilterMenu.swift:54-90`) | task 5 |
| FS-01.12 §7 dòng 2 viewer `★★★★☆ · Picked` | ❌ | dòng 2 do `PhotoInfoPanelSummary` chọn theo bề rộng (`Domain/Presentation/PhotoInfoPanelSummary.swift`, `PhotoDetailScreen.swift:1036-1150`) | thêm đoạn sao/cờ vào summary (ưu tiên trên thông số phơi sáng khi thiếu chỗ) — task 1 (sao), task 3 (cờ) |

Mọi AC đã đọc tới file. Chưa kết luận được — xem §9 ❓.

## 4. Tái dùng

| Có sẵn | Dùng cho |
|---|---|
| `ServerUploadIndex` / `UnsupportedRAWIndex` (`Features/ServerUpload/ServerUploadIndex.swift`; grid đọc qua environment + `version`, `PhotoGridCollectionView.swift:195-203`, `:605-620`) | `PhotoMarks`: map cờ + map sao chờ + giá trị lạc quan, `version` → `refreshVisibleCells()`; NF-01 luật 1 |
| `applyStatusBadges` + `updateAccessibilityLabel` (`PhotoGridCollectionView.swift:2267-2330`), khung glyph góc dưới-trái 5pt (`:2129-2142`) | glyph cờ, `★N`, VO "3 stars, Picked" — không dựng hàng thứ hai |
| `RAWVerdictStore.unreadableSQL` (`IN (SELECT …)` không cần alias) | SQL lọc cờ/sao ở `LibraryQueries`, `SmartAlbumSQLBuilder`, `StatisticsQueries` |
| `AlbumFilterPredicate.identifierPredicate` (cắt 500 id) | lọc sao/cờ trong màn album |
| `LossyRule` + `clause` trả nil cho giá trị lạ | AC-8 "chỉ điều kiện lạ rơi ra" — không viết bộ giải mã mới |
| `AppBannerModel.show(_:actionTitle:action:)` | "Moved 1,232 star ratings to Photos.", "Couldn't save rating." + Try Again, banner Recently Deleted |
| `backfillMediaSubtypes` (`App/AppDependencies.swift:350-375`): lô 2.000, chỉ đọc `PHAsset` trong bộ nhớ | điền cột `rating` (NULL → giá trị Photos) lần đầu chạy trên iOS 27 |
| `PHAssetChangeRequest.deleteAssets` qua `PhotoLibraryService.deleteAssets` + `metadataStore.deleteAssets` sau đó (7 chỗ gọi) | Delete Rejected; gỡ dòng cờ đi cùng `deleteAssets` |
| `ZoomableImageView`, `requestDetailImage`, `startCachingDetailImages` | trang Cull (không dùng `PhotoDetailPage` vì đường phóng của nó kéo bản gốc — AC-8) |
| Nút ẩn mang phím tắt (`Features/Collage/CollageScreen.swift:376-386`, `PhotoDetailScreen.swift:1623-1637`) | phím `0–5 P X U` ở viewer, chế độ chọn, Cull — gọi đúng hàm mà mục menu gọi |
| `CompareScreen` video tắt tiếng mặc định (`CompareScreen.swift:790-800`) | video trong Cull |
| `FakeOriginalFetcher` (`-ShotDexFakeICloud`) | AC-8 trên sim |
| `PhotoCommand` (tên + icon một chỗ) | `.cull` "Cull N Photos" / `flag.2.crossed` |
| tier-D `editorGlass` + luật nút "đang bật" (DESIGN.md, memory `tierD-glass-button-sync`) | Pick bật = đĩa accent + glyph đen, Reject bật = đĩa đỏ + glyph trắng — không token mới |

## 5. File đổi

| Tầng | File | Đổi |
|---|---|---|
| Domain | `Domain/Marks/PhotoMarkTypes.swift` (mới) | `PhotoFlag` (pick, reject), `StarRating` (0–5), `RatingFilter` (any, atLeast(n), unrated), `PhotoFlagFilter` (picks, rejected, unflagged); nhãn chip; câu VO "3 stars, Picked" |
| Domain | `Domain/Marks/MarkKeyCommand.swift` (mới) | bảng phím → hành động (`0–5 P X U`, Cull thêm ←/→ Z ⌘Z Esc); không đụng `F I Delete ⌘S` (test) |
| Domain | `Domain/Marks/RatingMigrationPlan.swift` (mới) | từ (dòng chờ, sao Photos của ảnh fetch được, `accessIsFull`) → yêu cầu ghi, dòng xoá, dòng giữ, số cho banner |
| Domain | `Domain/Marks/UserMarkRemovalPolicy.swift` (mới) | xoá từ app → gỡ; index thấy biến mất → gỡ chỉ khi quyền đầy đủ |
| Domain | `Domain/Marks/RejectedDeletion.swift` (mới) | id cần xoá = lưới đang hiện ∩ Rejected; nhãn "Delete 120" |
| Domain | `Domain/Cull/CullSession.swift`, `CullSummary.swift`, `CullGesturePolicy.swift` (mới) | thứ tự, ảnh mở đầu, tự sang ảnh, undo, thẻ tóm tắt, vuốt chỉ ở 1× |
| Domain | `Domain/Indexing/IndexPipeline.swift` | `IndexRunChanges` giao ra sau mỗi lượt (task 2); so lệch favorite/sao trong walk đầy |
| Domain | `Domain/Indexing/MetadataComposer.swift` | `AssetInfo.rating` |
| Domain | `Domain/Presentation/PhotoInfoPanelSummary.swift` | đoạn `★★★★☆ · Picked` ở dòng 2 |
| Core | `Core/Models/FilterCriteria.swift` | `ratingFilter`, `flags`; `isEmpty`, `activeConditionCount`, giải mã khoan dung |
| Core | `Core/Models/SmartAlbumQuery.swift` | `RuleField.rating`, `.flag`; `RuleFieldKind.rating`; `RuleOperator.atLeast`, `.atMost`; `isValid` |
| Core | `Core/Models/PhotoMetadata.swift`, `Data/Sources/PhotoMetadata+PhotoKit.swift` | cột `rating` (NULL = chưa đọc) — **file thứ hai đang có thay đổi chưa commit của phiên khác**: stage đúng đường dẫn |
| Data | `Data/Database/AppDatabase.swift` | migration `v27-ratingsAndFlags` (số lấy lúc commit) |
| Data | `Data/Database/PhotoMarksStore.swift` (mới) | CRUD cờ và sao chờ theo lô, map đầy cho chỉ mục, mệnh đề SQL sao hiện hành |
| Data | `Data/Database/MetadataStore.swift` | `updateAssetFacts` (favorite + sao, theo lô), `updateRating(ids:)`, `assetIdsMissingRating`, `deleteAssets(ids:removesUserMarks:)`; `updateFactsAndStatus` (`:69-94`) mang thêm `rating` |
| Data | `Data/Database/LibraryQueries.swift`, `SmartAlbumSQLBuilder.swift` | mệnh đề sao/cờ |
| Data | `Data/Sources/PhotoPropertyWriting.swift` (mới, **dùng chung FS-02.07**) | protocol + bản PhotoKit (`#available(iOS 27, *)`, một `performChanges` mỗi lệnh) + bản giả đếm khối/yêu cầu; hàm "đóng dấu ngày sửa" nếu M1 cần |
| Data | `Data/Sources/RatingMigrationPass.swift` (mới) | chạy một lần mỗi lần mở app trên iOS ≥ 27 khi bảng chờ còn dòng |
| Data | `Data/Sources/PhotoMarks.swift` (mới, `@MainActor @Observable`) | chỉ mục trong bộ nhớ + `setRating(ids:)`, `setFlag(ids:)` trả về bản ghi undo; chọn chỗ lưu theo `#available(iOS 27)` (tiêm được để test cả hai) |
| App | `App/AppDependencies.swift`, `App/ShotDexApp.swift` | dựng store/marks/pass, đưa `PhotoMarks` vào environment, gọi backfill + pass trong `.task` |
| Features | `Features/Shared/PhotoGridCollectionView.swift` | glyph, mờ 45 %, VO |
| Features | `Features/Shared/PhotoTileContextMenu.swift` | Rating ▸, Flag ▸ sau Favorite |
| Features | `Features/Library/SelectionBarViews.swift`, `App/SelectionBarModel.swift` | Rating ▸, Flag ▸ (khối Favorite), **Cull N Photos** sau Combine, phím cho lựa chọn |
| Features | `Features/Library/PhotoDetailScreen.swift` | Rating ▸, Flag ▸ ở nhóm đầu ⋯, **Cull From Here**, phím ẩn, dòng 2 |
| Features | `Features/Shared/PhotoFilterMenu.swift`, `Features/Library/FilterTokenBar.swift`, `Domain/Filtering/AlbumFilter.swift`, `Features/Albums/AlbumsModel.swift` | hai hàng + Rating ▸, chip, viên Delete, nhánh album bằng id |
| Features | `Features/Albums/SmartAlbumRuleRow.swift`, `SmartAlbumConditionsBar.swift`, `Features/Shared/RuleBuilderSections.swift` | ô chọn 0–5, Pick/Reject/Unflagged |
| Features | `Features/Library/Cull/CullScreen.swift`, `CullModel.swift`, `CullPager.swift`, `CullSummaryCard.swift` (mới) | màn tier D |
| Features | `PhotoBrowsingSource` (`PhotoDetailScreen.swift:14-40`) | `allPhotoIds()` (mặc định = id đã nạp; Albums trả cả fetch result) cho Cull From Here (❓-6) |
| Test | `PhotoMarksStoreTests`, `PhotoMarksTests` (writer giả), `RatingMigrationPlanTests`, `RatingMigrationPassTests`, `UserMarkRemovalPolicyTests`, `MarkKeyCommandTests`, `CullSessionTests`, `CullSummaryTests`, `CullGesturePolicyTests`, `RejectedDeletionTests`, `IndexRunChangesTests`; mở rộng `DatabaseTests`, `IndexDiffTests`, `SmartAlbumRuleDecodingTests`, `AlbumFilterTests`, `PhotoInfoPanelSummaryTests` | |
| UI test | `ShotDexUITests/scripts/rating-*.json`, `cull-*.json`; bước `key` cho driver nếu M3 cho phép | |
| Docs | DESIGN.md §8 (P1); FS-01.12/12b cột chứng minh; BD-02 §2 (cột NULL = chưa đọc); FS-01.01b §6 (glyph sao/cờ); FS-01.06 §3 (Cull N Photos, Rating ▸/Flag ▸); FS-02.04 (⋯ viewer); FS-06.09 (menu album có Picks/Rejected/Rating); FS-02.07 §8 (đường updated đã dựng ở đây) | |

Logic chọn chỗ lưu, kế hoạch chuyển sao, luật gỡ dòng, phạm vi xoá, phiên Cull và bảng phím đều ở Domain/Data, thuần
và test trên GRDB trong bộ nhớ. View chỉ đọc `PhotoMarks` và gọi model.

## 6. Thứ tự task

Mặc định ✅ → ⚠️ → ❌; ở đây không AC nào ✅ trọn (phần ✅ được khoá test trong task của AC đó), nên thứ tự đi theo
phụ thuộc: lược đồ → đường đồng bộ → cờ/glyph → lọc → iOS 27 → chuyển sao → Cull. Mỗi task một commit,
`/build` sau mỗi commit; task UI thêm `/screens` (iPhone 17 26.5 **và** 27.0, iOS 18.6, iPad 13" dọc + ngang qua
`Tools/sim-shot`, Duo trong + ngoài) và **`design-parity` trên board P2** (board có sẵn trên canvas V60). Test chạy
`/test <Class>` theo task; full suite một lần khi xong cả intent.

| # | Task | AC | Test / chứng minh |
|---|---|---|---|
| P1 | DESIGN.md §8 bốn icon | — | commit docs |
| P2 | export board V60 (`PH23`–`PH28`, `IP15`–`IP19`, `IPP15`, `DI14`, `DIP14`, `DC15`), ghi tên board vào bảng này | — | `Tools/design-board render` |
| M1 | đo PhotoKit sao trên sim 27.0 (§2) | (AC-2, AC-3, AC-7, task 2) | số đo vào FS-01.12 §10 cùng commit; nếu ngày sửa đổi → bật phần "đóng dấu" của task 7 |
| M3 | đo phím cứng qua ui-drive | (AC-1, AC-6, b-AC-1) | thêm bước `key` hoặc ghi ❓-4 |
| 1 | migration (`photo_flag`, `pending_photo_rating`, `photo_metadata.rating` + chỉ mục); `PhotoMarksStore`; `PhotoMarks` (chế độ chờ); `RatingFilter` + SQL sao hiện hành; phím `0–5` + Rating ▸ ở viewer; dòng 2 sao | AC-1 | `PhotoMarksStoreTests.pendingRowOnly` (1 dòng, `photo_metadata` so từng cột trước/sau), `.clearIndexKeepsMarks` (`deleteAll` + `saveBatch` lại → lọc ★≥4 ra A), migration test; `MarkKeyCommandTests.noClashWithViewerKeys`; `PhotoInfoPanelSummaryTests.appendsStars`; ui-drive phím `4` (theo M3); board dòng 2 viewer |
| 2 | **Đường dùng chung "updated dù ngày sửa không đổi"**: `IndexRunChanges { changed (inserted ∪ updated, kể cả id `needsReindex` bỏ qua), deleted, isFullWalk, accessIsFull }` giao cho các bên đăng ký sau mỗi lượt; bên đầu tiên là `AssetFactsRefresher` (favorite + sao Photos, không đọc file); walk đầy so lệch favorite/sao ngay lúc duyệt; điền `rating` NULL trên iOS 27 theo lô 2.000 | **AC-11** · hạ tầng cho FS-02.07 AC-10 | `AssetFactsRefresherTests.ratingChangedInPhotosReachesFilter` (iOS 27 giả: sao A đổi, ngày sửa không đổi → lượt tăng dần → lọc ★ ≥ N có A, `ExifReader` giả = 0 lần đọc); `IndexRunChangesTests.skippedUpdatedIdsAreDelivered`, `.fullWalkFlag`; `IndexDiffTests.factsDriftWithoutEdit`; `DatabaseTests.updateAssetFactsBatch`, `.ratingBackfillOnlyNulls`; log 0 lần `ExifReader` |
| 3 | cờ: `setFlag` ba trạng thái; phím `P X U` + Flag ▸ viewer; glyph hàng trạng thái (RAW không đọc được trước, rồi cờ, tim, `★N`, rồi kiểu chụp, server cuối — FS-01.12 §7), ô Rejected mờ 45 %, VO; dòng 2 "Picked" | AC-6 | `PhotoMarksTests.pickThenRejectReplaces`, `.flagNeverTouchesFavorite` (writer favorite giả = 0 lần gọi); `PhotoInfoPanelSummaryTests.appendsFlag`; ảnh ô lưới 4 máy ở mật độ dày nhất (hàng glyph không tràn); `a11y` dump nhãn; board ô lưới |
| 4 | gỡ dòng sao/cờ: đăng ký vào `IndexRunChanges.deleted` khi `accessIsFull`; 7 đường xoá từ app luôn gỡ (`deleteAssets(ids:removesUserMarks:)`) | AC-9 | `UserMarkRemovalPolicyTests` (đầy đủ → gỡ; `.limited` → giữ; xoá từ app dưới `.limited` → gỡ); `PhotoMarksStoreTests.indexDeletionRemovesRejected` (đếm Rejected giảm 1); sim iPhone: xoá B trong app Photos bằng công cụ MCP (iPhone, **không** Duo), rồi bỏ C khỏi phần chia sẻ bằng một chạm tay (❓-5) |
| 5 | `FilterCriteria.flags` + menu (Picks, Rejected sau Favorites, Rating ▸ chọn một), chip `★ ≥ 3` / `Unrated` / `Picks` / `Rejected` / `Unflagged`, `isEmpty` tắt đường nhanh khi có bộ lọc mới, nhánh album bằng id (Photos predicate nếu M1 cho phép) | AC-7 | `DatabaseTests.ratingAndPicksFilter` (10 ảnh → 2; bỏ Picks → 6), `FilterTokenBarTests.ratingChipLabel`, `AlbumFilterTests.flagsByIdentifiers`; `ShotDexUITests/scripts/rating-filter.json` (menu → chip → x); ảnh menu nhánh iOS 26 + 18.6; board menu lọc |
| 6 | `RuleField.rating` / `.flag`, toán tử `atLeast` / `atMost`, SQL, hàng soạn, chip | AC-8 | `SmartAlbumMarksTests.bestPicksAtLeastFour` (12 → Reject 1 → 11, đếm chân sheet = lưới), `SmartAlbumRuleDecodingTests.unknownFlagValueDropsOnlyThatRule`; ảnh trình sửa trên Duo trong |
| 7 | iOS 27: `PhotoPropertyWriting` (một khối mỗi lệnh), `PhotoMarks` chế độ Photos, ghi xong cập nhật cột + xoá dòng chờ của id đó; Rating ▸ / Flag ▸ ở ⋯ chọn + menu giữ-lâu; phím cho lựa chọn; đóng dấu ngày sửa nếu M1 cần | AC-2 | `PhotoMarksTests.photosModeOneBlock300` (writer giả: 1 khối, 300 yêu cầu, 0 dòng chờ, đọc lại = 3); sim 27.0: ui-drive chọn 300 → Rating ★★★, log không có lượt nạp lưới / lượt index; board ⋯ chọn |
| 8 | ghi lỗi: lạc quan → trả về ≤ 1 s, banner "Couldn't save rating." + Try Again, không dòng chờ | AC-10 | `PhotoMarksTests.photosWriteFailureReverts` (writer giả ném; `version` tăng; 0 dòng chờ), `.tryAgainRetriesSameIds`; ảnh banner trên iPhone + iPad |
| 9 | `RatingMigrationPlan` + `RatingMigrationPass` sau first paint, một khối, giữ sao Photos ≠ 0, xoá dòng đã ghi/bỏ/ảnh đã xoá, banner một lần | AC-3 | `RatingMigrationPlanTests.twelveFortyCase` (1.240 / 5 / 3 → 1.232), `RatingMigrationPassTests.bannerOnce` (writer giả, 2 lần mở → 1 banner), String Catalog số nhiều. **Đi sau M2** nếu M2 đã có số; nếu có trần → dừng, hỏi sửa AC-3 |
| 10 | lỗi khối: giữ cả 1.240, không banner, thử lại tối đa một lần mỗi lần mở | AC-4 | `RatingMigrationPassTests.failureKeepsAllAndRetriesNextLaunch`; `DatabaseTests.pendingStillFilters` |
| 11 | `.limited`: chỉ ghi ảnh thấy được, không gỡ dòng không thấy | AC-5 | `RatingMigrationPlanTests.limitedWritesVisibleOnly` (200 / 1.040) |
| 12 | màn Cull khung + `CullSession.start` + lối vào **Cull N Photos** (sau Combine, ở 4 màn có chế độ chọn) và **Cull From Here** (`allPhotoIds`) | b-AC-3 | `CullSessionTests.startsAtFirstUnflaggedByCaptureDate` (240, 36 có cờ → 37), `.nilDatesLast`; ảnh lối vào ⋯; board Cull iPhone |
| 13 | phím `P X U 0–5 ←/→ Z ⌘Z Esc`, tự sang ảnh khi đặt cờ, đứng lại khi đặt sao, undo lùi về đúng ảnh, rung nhẹ | b-AC-1 | `CullSessionTests.pickAdvancesStarStaysUndoReturns` (đúng chuỗi AC-1); ui-drive phím (theo M3) |
| 14 | thẻ tóm tắt ở ảnh cuối + Delete N Rejected… / Review Unflagged / Done | b-AC-4 | `CullSummaryTests.counts` (52 / 119 + X → 120, 68), `.reviewUnflaggedSubset`; ảnh thẻ 4 máy; board thẻ |
| 15 | vuốt dọc: lên Pick, xuống Reject, chỉ ở 1×; đang phóng thì kéo ảnh | b-AC-2 | `CullGesturePolicyTests`; ui-drive iPhone `swipe` theo điểm ở 1× rồi sau pinch 2× (dump cờ ảnh 10, 11) |
| 16 | trang Cull chỉ xin cỡ màn (±2 trang, có mạng — FS-01.12b §2), glyph mây, ghi cờ không cần ảnh, video tắt tiếng | b-AC-8 | `CullModelTests.neverRequestsOriginal` (`OriginalFetching` giả đếm `fetch` = 0, target ≠ `PHImageManagerMaximumSize`); sim `-ShotDexFakeICloud cloud=all,stall` 50 ảnh; mất mạng thật → máy thật |
| 17 | viên **Delete N** trên thanh điều kiện (Library, Album, Smart Album) + nút ở thẻ tóm tắt → `RejectedDeletion`, gỡ dòng cờ, banner Recently Deleted không Undo | b-AC-6 | `RejectedDeletionTests.onlyVisibleRejected` (240 / 120 trong X, 30 ngoài X còn), `PhotoMarksStoreTests.deletedRejectedRowsGone`; ảnh thanh điều kiện iPhone 402 (viên + Clear không đẩy chip ra khỏi màn — memory `hstack-greedy-column-overflow`), cả hai nhánh iOS 26; board viên Delete |
| 18 | Cancel / lỗi khi xoá | b-AC-7 | `RejectedDeletionTests.cancelChangesNothing` (deleter giả ném `userCancelled`), `.failureOffersTryAgain` |
| 19 | bố cục 4 máy: iPad filmstrip 72 + dòng EXIF, Duo trong ảnh ~500pt, Duo ngoài hàng 340pt trong 382pt; mọi control ≥ 44×44 | b-AC-5 | `Tools/ui-drive` dump trên iPhone 17, iPad 13", Duo trong, Duo ngoài (Duo bằng `ui-drive` + `sim-shot`, **không** công cụ MCP); `design-parity` cả 4 board |

19 task code; M2 chạy song song trên máy thật và chỉ chặn task 9.

## 7. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| **Migration đụng nhau**: FS-02.07 (bảng gương) cùng lấy `v27`, cùng sửa `MetadataStore.deleteAssets`, `RuleField`, `RuleBuilderSections`, ⋯ chọn | cao | số lấy lúc commit sau `main` mới nhất; một migration gồm cả ba thay đổi lược đồ; `git commit -- <paths>`, không stash/checkout/`add -A` (memory `two-agents-shared-checkout`). Đường lùi: bảng mới độc lập, cột `rating` NULL được — bỏ thì chỉ mất bộ lọc, không mất dữ liệu người dùng |
| **Dữ liệu người dùng**: cờ và sao chờ không đọc lại được từ đâu | — | bảng riêng (BD-02 §1); Clear index không đụng (test task 1); gỡ chỉ khi xoá thật và quyền đầy đủ (task 4) |
| **Ghi sao làm đổi `modificationDate`** (M1) → lượt index kế đọc lại EXIF cả lô 1.232 ảnh, ảnh chỉ iCloud kéo bản gốc khi mạng được phép | vừa | hàm chung với FS-02.07: sau `performChanges`, đọc lại ngày sửa và ghi vào `photo_metadata` cùng transaction với cột `rating` → `needsReindex` thấy không đổi. Sửa từ Mac vẫn kéo một lần đọc lại (chấp nhận, như sửa ảnh) |
| **Trần PhotoKit** mỗi khối (M2) | thấp–vừa | chia khối 1.000 nối tiếp; khi đó AC-3 "đúng 1 khối" sai — dừng và hỏi (❓-1) |
| **`PHAsset` cũ trong bộ nhớ đệm của lưới**: thay đổi chỉ nội dung không làm mới `ChunkedLookupCache` (`LibraryModel.swift:259-270`, `:536`) — glyph tim hôm nay cũng vậy | chắc chắn | glyph sao đọc `PhotoMarks` trước (dòng chờ + giá trị vừa ghi trong phiên), `PHAsset.rating` sau; thay đổi từ máy khác hiện khi chunk được nạp lại. Glyph tim cũ → một dòng `REVIEW_QUEUE.md`, không làm ở đây |
| **Phím trong `Menu` đang đóng** không chạy trên iOS | cao | nút ẩn mang phím, gọi đúng hàm của mục menu (mẫu `CollageScreen.swift:376`); phím vẫn hiện trong bảng phím tắt khi giữ ⌘ — kiểm trên iPad (`ipad-multitasking`) |
| **Hàng glyph tràn ô** ở lưới dày (tới 7 glyph + `★5`), spec cấm ẩn theo bề rộng | vừa | đo ở mật độ dày nhất trên iPhone 402 và Duo ngoài; quá rộng thì cắt **phải** bằng clip của ô — hỏi lại trước khi bớt glyph |
| **Duo trong 669pt** (Cull: 52 + 60 + 56 + vùng an toàn, ảnh ~500pt) và **Duo ngoài** rail 84pt | vừa | task 19; `duo-ux-review` + `device-layout` |
| **Concurrency**: `PhotoMarks` `@MainActor`, ghi store ngoài luồng chính, callback PhotoKit; pass chuyển sao chạy cùng lúc người dùng đặt sao | vừa | mọi ghi đi qua `PhotoMarks` (một chỗ tuần tự), pass đọc lại dòng chờ ngay trước khi ghi và chỉ xoá dòng có `ratedAt` ≤ lúc đọc; `swift-concurrency` duyệt |
| **Bộ nhớ**: map cờ/sao 55k id; pager Cull | thấp | vài MB; pager dùng `detailImageCache` có trần (12 ảnh / 160 MB, `PhotoLibraryService.swift:97-103`); `memory-leak` |
| **iOS 27 sau `#available`**: test chạy trên sim 26.5 | chắc chắn | chế độ lưu tiêm được; writer giả không cần API 27; probe M1 tự bỏ qua dưới 27 |
| **Nhiệt/pin**: 800 lần ghi Photos trong 10 phút ở Cull trên iOS 27 | thấp | M2 máy thật; thay đổi gộp 1 s và chỉ nội dung |
| **Album chỉ còn một điều kiện lạ** → truy vấn rỗng khớp cả thư viện (hành vi có sẵn, `SmartAlbumSQLBuilder.swift:17-27`) | thấp | ngoài AC-8 (album "Best" còn điều kiện sao); ghi `REVIEW_QUEUE.md` |
| Banner đè khay của `SelectionOverlay` khi chế độ chọn giữ nguyên sau Rating 300 ảnh | vừa | đo frame bằng `ui-drive dump` (cùng rủi ro ở plan FS-02.07) |

## 8. Phản biện (điền sau khi chạy `challenger`)

| Phản đối | Trả lời / thay đổi |
|---|---|
| … | … |

## 9. Quyết định (người dùng duyệt 2026-10-03)

Người dùng chấp nhận mọi đề nghị của plan. ⚠️ đã vào spec trong cùng commit duyệt; ❓ thành việc có chủ.

### ⚠️ lệch giữa tài liệu và code — đã quyết

| # | Chỗ lệch | Quyết định | Đổi trong plan / spec |
|---|---|---|---|
| ⚠️-1 | FS-01.12b §2 ghi Cull tải "như pager của viewer", mà viewer tải trước **±1, không mạng** (`PhotoDetailScreen.swift:2991-3011`; FS-02.01 §1) | **tài liệu đúng về con số**: Cull tải trước ±2 trang, cỡ màn, **có mạng**; bỏ cụm "như pager của viewer". Viewer giữ luật cũ | FS-01.12b §2 sửa (nêu rõ khác viewer và vì sao); task 16 |
| ⚠️-2 | BD-02 §1–§2 đòi cột `rating` đồng bộ lại khi thư viện báo thay đổi, nhưng không AC nào đòi | **thêm FS-01.12 AC-11**: "iOS 27, sao của A đổi trong Photos, ngày sửa không đổi → sau lượt index tăng dần kế tiếp lọc ★ ≥ N có A, 0 lần đọc file" | FS-01.12 §9 có AC-11; task 2 nhắm AC-11 (và vẫn là đường FS-02.07 AC-10 tiêu thụ) |
| ⚠️-3 | FS-01.12 §7 "cờ trước favorite, rồi ★4" không nhắc glyph RAW không đọc được, mà code đặt nó đầu tiên (FS-03.04b §3, `PhotoGridCollectionView.swift:2281-2283`) | **code đúng**: glyph RAW không đọc được → cờ → tim → `★N` → kiểu chụp → server | FS-01.12 §7 ghi đủ thứ tự, bắt đầu "sau glyph RAW"; task 3 |

Quyết định kỹ thuật tự chốt (không cần duyệt): cột `rating` cho phép NULL = "chưa đọc trên iOS 27", SQL dùng
`COALESCE(…, 0)` (BD-02 ghi "dưới 27 luôn 0" vẫn đúng về nghĩa); cờ lưu chữ `pick`/`reject` (cùng giá trị JSON của
smart album); phím qua nút ẩn; trang Cull tự dựng trên `ZoomableImageView` thay vì `PhotoDetailPage`; viên Delete
cao 32pt như spec, vùng chạm 44pt; viên chỉ hiện khi **bộ lọc nhanh** Rejected bật, không theo điều kiện cờ trong
Advanced Filter.

### ❓ chưa kết luận được — việc đã chốt

| # | Câu hỏi | Việc đã chốt | Ở task |
|---|---|---|---|
| ❓-1 | PhotoKit có trần yêu cầu mỗi khối không (AC-3 "đúng 1 khối" 1.232) | đo M2 trên máy thật trước task 9; có trần → chia khối 1.000 nối tiếp, task 9 dừng và hỏi sửa AC-3 trước khi code | M2 → task 9 |
| ❓-2 | Ghi sao có đổi ngày sửa, có vào `updated` không; video có sao không | đo M1 trên sim 27.0; đổi ngày sửa → bật phần "đóng dấu ngày sửa" (hàm chung với FS-02.07) trong task 7; không vào `updated` → lượt tăng dần không thấy đổi sao, AC-11 không đạt như viết: ghi số đo vào FS-01.12 §10, task 2 dừng và hỏi | M1 → task 2, 7 |
| ❓-3 | `PHFetchOptions` có lọc theo `rating` không | M1; không thì nhánh album lọc sao bằng danh sách id (`AlbumFilterPredicate.identifierPredicate`) | M1 → task 5 |
| ❓-4 | ui-drive gửi được phím cứng không | M3; được → thêm bước `key` vào driver; không → AC phím chứng minh bằng unit test bảng phím + model, ảnh chụp sau khi chạm | M3 → task 1, 3, 13 |
| ❓-5 | AC-9 cần xoá trong app Photos và đổi phần chia sẻ `.limited` | công cụ MCP sim trên **iPhone** (không Duo) cho phần xoá + một chạm tay của người dùng cho hộp chọn `.limited` | task 4 |
| ❓-6 | Cull From Here trên màn album phân trang: viewer chỉ biết trang đã nạp | thêm `PhotoBrowsingSource.allPhotoIds()` (mặc định = id đã nạp; Albums trả cả fetch result) | task 12 |
| ❓-7 | Rung nhẹ mỗi lần đặt cờ không quan sát được trên sim | kiểm trên máy thật trong `/verify` | `/verify` |

## 10. Cách chứng minh là xong

- **Test**: các file ở §5 theo từng task; `IndexRunChangesTests` cũng là chỗ FS-02.07 task 20 nối vào.
- **Màn hình** (`/screens`, `Tools/ui-drive`, `Tools/sim-shot` cho Duo và iPad ngang): ô lưới có glyph (thưa và dày
  nhất) · ô Rejected mờ · menu giữ-lâu · ⋯ chọn (Rating ▸, Flag ▸, Cull N Photos) · ⋯ viewer + dòng 2 · menu lọc 9
  hàng + chip · trình sửa smart album · banner chuyển sao / lỗi ghi / Recently Deleted · Cull (thường, phóng, thẻ
  tóm tắt) · viên Delete. Trên iPhone 17 (26.5 và 27.0), iOS 18.6 (nhánh trước 26 của menu và thanh điều kiện), iPad
  13" dọc + ngang, Duo trong + ngoài. **`design-parity`** cho mọi board ở P2.
- **Máy thật**: M2 (trần khối, nhiệt 800 lần ghi, xoá ảnh chỉ iCloud), rung, b-AC-8 mất mạng thật.
- **Tài liệu**: cột "Chứng minh bằng" của FS-01.12 và FS-01.12b sau mỗi AC; FS-01.12 §10 (số M1, M2); BD-02 §2;
  FS-01.01b §6; FS-01.06 §3; FS-02.04; FS-06.09; FS-02.07 §8 (đường updated ở đây); DESIGN.md §8 (P1); quyết định
  ⚠️-1…3 đã vào spec lúc duyệt 2026-10-03 (FS-01.12 §7, §8, AC-11; FS-01.12b §2); dòng Tiến độ của intent theo `docs/PROCESS.md` §2.
- **Agent ở Deploy**: `data-migration` (migration, ba bảng, luật gỡ dòng), `photokit-guard` (ghi sao một khối,
  `.limited`, xoá, lịch sử thay đổi), `swift-concurrency` (`PhotoMarks`, pass chuyển sao, `IndexRunChanges`),
  `perf-profiler` (SQL `IN (SELECT …)` ở 55k, hàng glyph khi cuộn), `memory-leak` (pager Cull), `device-layout`,
  `duo-ux-review`, `iphone-ux-review` (vuốt dọc, ngón cái), `ipad-ux-review` + `ipad-multitasking` (phím, bảng phím
  tắt, con trỏ), `a11y-voiceover` (ô lưới, Cull adjustable + action), `ios26-parity` (menu, thanh điều kiện),
  `design-parity`, `design-reviewer`, `hig-components` (menu con, nút phá huỷ), `copy-consistency` + `localization`
  (số nhiều "Moved 1,232 star ratings", "Delete 120"), `test-coverage`, `ux-reviewer` (Delete Rejected, undo),
  `challenger` (§8).
