# FS-01.12 — Chấm sao và cờ Pick/Reject

`FS-01.12` · tier B (lưới, viewer) · `Features/Library/` · `Features/Shared/PhotoGridCollectionView.swift`
· `Data/Database/` (2 bảng mới) · nguồn intent [user-wishes-research](../../_intents/2026-09-30-user-wishes-research.md)
mục 9 · cập nhật 2026-10-02

**Một câu:** chấm 0–5 sao và cắm cờ Pick/Reject cho từng ảnh bằng một chạm hoặc một phím, lọc và làm smart album
theo đó. Lượt lọc qua cả buổi chụp và Delete Rejected: [12b](12b-culling-pass.md).

## 1. Người dùng cần gì

Sau một buổi chụp 300–800 khung, người chụp đi qua từng tấm, quyết giữ hay bỏ, chấm điểm tấm giữ, rồi dọn.
Favorite của Photos chỉ có một bit nên không chứa được "bỏ" lẫn "giỏi tới đâu". Lightroom và Photo Mechanic làm
việc này bằng P/X và 1–5. Trên ShotDex hôm nay phải mở Compare theo từng nhóm.

## 2. Vì sao đưa lại (đảo quyết định đã gỡ ở `v16`)

- Lần trước gỡ vì "sao và cờ trả lời cùng câu hỏi với favorite". Người dùng 2026-09-30 chốt ngược lại. Ba
  trục trả lời ba câu khác nhau:
  - favorite là "tấm tôi thích", đồng bộ sang Photos;
  - cờ là quyết định giữ hay bỏ của **một lượt lọc**;
  - sao là thứ hạng giữa các tấm giữ.
- **iOS 27 có sao trong chính Photos** nên sao không còn là trục riêng của app. Nó đi theo ảnh sang Mac và iCloud.
- Compare vẫn là chỗ so cạnh nhau. Lượt lọc ([12b](12b-culling-pass.md)) là chỗ đi tuần tự từng tấm. Hai việc khác nhau.

## 3. Phạm vi

**Có:** sao 0–5 và cờ Pick / Reject / không cờ cho ảnh **và video** · glyph trên ô lưới · đặt trong lưới
(menu giữ-lâu, chế độ chọn), viewer và lượt lọc · phím tắt · bộ lọc nhanh, Advanced Filter, smart album ·
**Delete Rejected** ([12b](12b-culling-pass.md)) · chuyển sao sang Photos một lần khi máy lên iOS 27.

**Cố ý không có:**
- Cờ trong Photos — Photos không có khái niệm này. Cờ nằm trên máy này, **không** đồng bộ iCloud.
- Pick tự bật favorite — người dùng chốt hai thứ độc lập.
- Nhãn màu kiểu Lightroom — không ai đòi. Thêm vào là trục thứ tư.
- Cờ trong Compare — chạm ở Compare chỉ có một nghĩa là đánh dấu xoá ([FS-01.08 §1](08-compare.md)).
- Câu tìm kiếm kiểu "ảnh 5 sao" — v1 dùng bộ lọc. Parser thêm sau, không đổi dữ liệu.
- Ghi sao vào file (XMP) — app không ghi đè file gốc.

## 4. Dữ liệu

| Dữ liệu | iOS 17–26 | iOS 27 trở lên |
|---|---|---|
| Sao | bảng **Sao chờ lên Photos** của ShotDex | sao của Photos; cột sao trong bảng metadata chính chỉ để lọc nhanh, đọc lại được từ ảnh |
| Cờ | bảng **Cờ** của ShotDex | như cột bên trái — luôn ở bảng riêng |

- Cả hai đều là dữ liệu người dùng tự nhập nên **không** nằm trong cột nào của bảng metadata chính. Cột sao trên
  iOS 27 là ngoại lệ có lý: nó **đọc lại được** từ ảnh, giống favorite ([BD-02 §1](../../01-basic-design/BD-02-database-design.md)).
- **Sao hiện hành của một ảnh = sao trong bảng chờ nếu có, không thì sao của Photos.** Một luật duy nhất cho
  cả hai đời iOS. Sao còn chờ (chưa lên Photos được) vẫn lọc đúng. Dưới 27 cột Photos luôn bằng 0.
- Hai bảng tách nhau. Bảng sao **sẽ rỗng dần** trên iOS 27, còn bảng cờ thì sống mãi. Gộp lại thì "dòng rỗng"
  mang hai nghĩa.
- **Clear local metadata index** (Settings) không đụng hai bảng này.
- Gỡ dòng: ảnh bị xoá thì dòng sao và dòng cờ được gỡ, **cùng lúc** lượt index gỡ dòng metadata của ảnh đó.
  - Quyền `.limited` thì **không bao giờ gỡ**: ảnh không thấy chưa chắc đã bị xoá.
- Lưới **không hỏi database theo từng ô** ([NF-01](../../04-non-functional-design/NF-01-performance.md) luật 1):
  - cờ và sao chờ đọc từ một chỉ mục id trong bộ nhớ, giống glyph đã-lên-server;
  - sao iOS 27 đọc thẳng từ ảnh, giống favorite.

## 5. Chuyển sao sang Photos khi lên iOS 27

- Chạy **một lần** sau first paint ở lần mở app đầu tiên trên iOS ≥ 27, chỉ khi bảng sao chờ còn dòng.
- **Một** khối thay đổi PhotoKit cho cả lô. Cả lô tạo **một** thay đổi thư viện. Thay đổi đó chỉ là thay đổi
  nội dung, nên lưới không nạp lại và lượt index không chạy lại
  ([FS-01.01](01-photo-grid-and-data-source.md)).
- Ảnh mà Photos **đã có** sao khác 0 thì giữ sao của Photos và bỏ dòng chờ. Vì người dùng có thể đã chấm trên
  Mac sau khi lên 27, mà ghi đè thì mất một quyết định họ làm trong app của Apple.
- Ghi xong: xoá các dòng đã ghi và các dòng bị bỏ. Banner một lần: "Moved 1,232 star ratings to Photos."
- **Lỗi:** PhotoKit làm cả khối hoặc không làm gì → giữ mọi dòng, không banner, thử lại ở lần mở app sau, mỗi
  lần mở app tối đa một lần.
- **`.limited`:** chỉ ghi ảnh thấy được. Dòng còn lại ở lại và vẫn lọc đúng. Chúng đi lên Photos ở lần mở app
  sau khi người dùng chia sẻ thêm ảnh.
- **Đặt sao trên iOS 27** (một ảnh hay 300 ảnh chọn) cũng là **một** khối thay đổi cho cả lệnh. Ghi lỗi thì ô
  trả về sao cũ và hiện "Couldn't save rating." kèm **Try Again** ([NF-04](../../04-non-functional-design/NF-04-empty-and-error-states.md)).

## 6. Đặt sao và cờ — theo bề mặt

| Bề mặt | Cách đặt |
|---|---|
| Menu giữ-lâu trên ô | nhóm 1, sau Favorite: **Rating ▸** (None · ★ … ★★★★★) và **Flag ▸** (Pick · Reject · Clear Flag) |
| Chế độ chọn | ⋯ có hai menu con giống hệt, áp cho mọi ảnh đang chọn. Phím 0–5 / P / X / U áp cho lựa chọn |
| Viewer | phím 0–5 / P / X / U, và hai menu con trong ⋯ (§7) |
| Lượt lọc | một chạm, một phím hoặc một cú vuốt ([12b](12b-culling-pass.md)) |

- **Phím:** `0` bỏ sao · `1`–`5` đặt sao · `P` Pick · `X` Reject · `U` bỏ cờ. Chúng không đụng phím có sẵn
  của viewer (`F` favorite, `I` info, Delete, ⌘S). Phím gắn vào chính nút hoặc mục menu, nên phím và chạm chạy
  cùng một đường. Giữ ⌘ trên iPad thì phím hiện trong bảng phím tắt của hệ thống.
- Cờ có ba trạng thái loại trừ nhau. Đặt Pick trên ảnh Rejected thì thay cờ, không cộng.
- Glyph và icon: sao `star` / `star.fill`, Pick `flag.fill`, Reject `xmark`, lượt lọc `flag.2.crossed`. Bốn icon
  này phải thêm vào từ điển [DESIGN.md §8](../../../DESIGN.md) trước khi code.
- **Màu, không token mới:** tier D dùng luật nút có sẵn. Pick đang bật = đĩa accent + glyph đen. Reject đang bật =
  đĩa đỏ + glyph trắng, là bản phá huỷ của "đang bật". Sao đã chấm màu trắng, chưa chấm trắng 28%. Glyph trên ô
  lưới màu trắng, có bóng như mọi glyph trạng thái khác.

## 7. Hiển thị và lọc

Chốt 2026-10-02.

- **Ô lưới:** sao và cờ nằm trong hàng glyph trạng thái ở **góc dưới-trái** (glyph 10pt, cách mép 5pt).
  - Thứ tự: glyph RAW không đọc được ([FS-03.04b §3](../FS-03-photo-editor/04b-unsupported-raw.md)) đứng đầu, rồi
    cờ, favorite, "★4" (sao 10pt + số caption2 semibold, chỉ khi ảnh có ≥ 1 sao), các glyph kiểu chụp, server cuối.
  - Ô Rejected mờ ảnh còn 45%. Hàng glyph không ẩn theo bề rộng ô ([FS-01.01b §6](01b-grid-engine-and-gestures.md)).
- **Viewer:** chỉ đọc. Dòng 2 của bảng thông tin **trên-trái** (cạnh X) nối thêm `★★★★☆ · Picked`.
  - Đặt qua ⋯ (hai menu con Rating ▸ và Flag ▸ ở nhóm đầu) và phím. Chrome của viewer giữ nguyên.
  - Ảnh không sao, không cờ thì dòng 2 không thêm gì.
- **Menu lọc:** hai hàng phẳng **Picks** và **Rejected** ngay sau Favorites (một chạm, như Favorites), cộng
  menu con **Rating ▸** (Any · ★ & Up … ★★★★★ · Unrated, chọn một).
  - Menu dài thêm 3 hàng, tổng 9 hàng; Advanced Filter… vẫn hiện trên iPhone.
- **Sao chấm trên máy ảnh:** v1 không đọc. Sao trong file (Sony, Fuji ghi được) không thành sao của ShotDex.
  *Vì trên iOS 27 đọc nó thành một lần ghi Photos cho mỗi ảnh mới.*

## 8. Thiết bị và iOS

- Cùng chức năng trên iPhone 402×874, iPad 1376×1032, Duo trong 951×669, Duo ngoài 466×678. Phone có đủ mọi
  thứ iPad có. Phím chạy ở mọi máy có bàn phím cứng.
- iOS 17–26 và 27 khác nhau **chỉ ở chỗ lưu sao** (§4). Giao diện không rẽ nhánh.
- Menu giữ-lâu, ⋯ của chế độ chọn và menu lọc giống nhau ở nhánh iOS 26 và nhánh trước 26.
- **VoiceOver:** ô lưới đọc thêm "3 stars, Picked" sau các trạng thái có sẵn.

**Design canvas:** không board nào đang có bị đổi. Ô lưới, dòng 2 của viewer, menu lọc (§7) và màn Cull
([FS-01.12b](12b-culling-pass.md)) đã vẽ trên canvas [ShotDex Photo Editor](https://claude.ai/artifact/T4tEUQrJtxBbi48HokiL9F)
(Version 60), nối vào hàng thiết bị: `PH23`–`PH28`, `IP15`–`IP19`, `IPP15`, `DI14`, `DIP14`, `DC15`.

## 9. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | iOS 26.5, ảnh A chưa có sao, viewer đang mở A | bấm phím `4` | bảng sao chờ có đúng 1 dòng A = 4; bảng metadata chính không đổi; sau **Clear local metadata index** và index lại, lọc ★ ≥ 4 vẫn ra A | ✅ `PhotoMarksStoreTests.pendingRowOnly`, `.clearIndexKeepsMarks`, `.currentRatingIsPendingElsePhotos`; phím thật qua `ShotDexUITests/scripts/rating-viewer-key.json` (iPhone 17 26.5: phím `4` → dòng 2 `116.3 MB · ★★★★☆`, Rating ▸ đánh dấu ★★★★, None xoá) |
| AC-2 | iOS 27, chọn 300 ảnh chưa có sao | ⋯ → Rating ▸ ★★★ | đúng 1 khối thay đổi PhotoKit mang 300 yêu cầu; đọc lại 300 ảnh có sao = 3; bảng sao chờ có 0 dòng; lưới không nạp lại | ✅ `PhotoMarksTests.photosModeOneBlock300` (writer giả: 1 khối / 300 yêu cầu, đọc lại = 3, 0 dòng chờ, cột `rating` = 3, ngày sửa đóng dấu lại), `.restampLeavesUnreadEditsAlone`, `.photosModeUndoIsOneBlock`; sim iPhone 17 **iOS 27.0** `ShotDexUITests/scripts/rating-selection-27.json` (chọn 3 → ⋯ Rating ▸ ★★★ → ô `★3`, chế độ chọn và vị trí cuộn giữ nguyên — lưới không nạp lại; None xoá). Thay đổi chỉ nội dung, không cấu trúc: số đo M1 §10. 300 ảnh qua UI chưa chạy (chọn từng ô) |
| AC-3 | lần mở app đầu trên iOS 27: bảng sao chờ có 1.240 dòng, trong đó 5 ảnh đã bị xoá và 3 ảnh Photos đã có sao khác | app mở xong first paint | đúng 1 khối thay đổi mang 1.232 yêu cầu; 3 ảnh giữ sao của Photos; bảng chờ còn 0 dòng; banner "Moved 1,232 star ratings to Photos." hiện đúng một lần | ✅ `RatingMigrationPlanTests.twelveFortyCase` (1.240 / 5 / 3 → 1.232), `RatingMigrationPassTests.bannerOnce` (writer giả: 1 khối, 2 lần mở → 1 banner, chuỗi số nhiều "Moved 1,232 star ratings to Photos."), `.starSetDuringTheMoveSurvives`; sim iPhone 17 iOS 27.0: 42 dòng chờ (40 ảnh thật + 2 id đã mất) → mở app → 0 dòng chờ, 40 ô `★3` đọc từ Photos (`ShotDexUITests/scripts/rating-migration-27.json`). ⚠️ banner trên sim chưa bắt được khung (đã tắt trước ảnh chụp); máy thật: trần khối (M2) |
| AC-4 | như AC-3, khối thay đổi trả lỗi (giả lập) | app mở | bảng chờ vẫn 1.240 dòng; lọc ★ ≥ 1 vẫn ra đủ ảnh còn tồn tại; không banner; lần mở app sau thử lại đúng 1 lần | ✅ `RatingMigrationFailureTests.failureKeepsAllAndRetriesNextLaunch` (khối lỗi → 40/40 dòng còn, lọc ★ ≥ 1 vẫn đủ, không banner, lần gọi thứ hai trong cùng lần mở = không chạy, lần mở sau ghi 1 khối), `.pendingStillFilters` |
| AC-5 | iOS 27, quyền `.limited` thấy 200 trong 1.240 ảnh có dòng chờ | app mở | khối thay đổi mang đúng 200 yêu cầu; 1.040 dòng ở lại; không dòng nào bị gỡ vì "ảnh không thấy" | ✅ `RatingMigrationLimitedTests.limitedWritesVisibleOnly` (200 / 1.040, 0 gỡ), `.limitedKeepsTheRest` (qua pass: 1 khối 10, 40 dòng ở lại). ⚠️ trên sim `.limited` cần một chạm tay vào hộp chọn ảnh |
| AC-6 | ảnh A là favorite, không cờ | bấm `P`, rồi `X` | sau `P`: A Picked, vẫn favorite; sau `X`: A Rejected, không còn Picked, vẫn favorite; favorite của Photos không đổi ở cả hai bước | ✅ `PhotoMarksTests.pickThenRejectReplaces`, `.flagNeverTouchesFavorite` (đường cờ không có writer favorite; dòng metadata giữ nguyên); phím thật qua `ShotDexUITests/scripts/rating-grid-glyphs.json` (iPhone 17 26.5: `P` `5` / `X` `1` / `P` / `3` trên 4 ảnh liền → ô lưới `⚑ ★5`, `× ★1` mờ, `⚑`, `★3`; VoiceOver "5 stars, Picked", "1 star, Rejected") |
| AC-7 | thư viện 10 ảnh: sao 0,0,1,2,3,3,4,5,5,5; Picked là ảnh 5★ thứ nhất và ảnh 3★ thứ nhất | bật Rating ★★★ & Up + Picks | lưới còn đúng 2 ảnh (5★ Picked, 3★ Picked); thanh có chip "★ ≥ 3" và "Picks"; bấm x chip Picks → 6 ảnh | ✅ `MarkFilterTests.ratingAndPicksFilter` (10 → 2, chip `★ ≥ 3` + `Picks`, x Picks → 6), `.unratedUnflaggedAndRejected`, `.flagsByIdentifiers` + `.ratingByIdentifiersAndPhotos` (màn album, theo id); `ShotDexUITests/scripts/rating-filter.json` (iPhone 17 26.5: menu 9 hàng lọc, Picks + ★★★ & Up → 1 ảnh, x Picks → 2). ⚠️ nhánh trước 26 chưa chụp: driver treo lúc launch trên iPad 18.6 |
| AC-8 | smart album "Best" = cờ **là** Pick VÀ sao **ít nhất** 4, khớp 12 ảnh | Reject 1 ảnh trong đó rồi mở lại album | album còn 11; JSON album chứa một điều kiện cờ lạ thì chỉ điều kiện đó rơi ra, album không thành "mọi ảnh" | ✅ `SmartAlbumMarksTests.bestPicksAtLeastFour` (12 → Reject 1 → 11, đếm = lưới), `.ratingOperatorsAndFlagNegation`, `SmartAlbumRuleDecodingTests.unknownFlagValueDropsOnlyThatRule`. ⚠️ ảnh trình sửa (hàng sao 0–5) chưa chụp |
| AC-9 | ảnh B Rejected, quyền đầy đủ; ảnh C Rejected, quyền `.limited` và C vừa bị bỏ khỏi phần chia sẻ | xoá B trong app Photos; đổi phần chia sẻ để bỏ C | sau thay đổi thư viện: dòng cờ của B bị gỡ, số Rejected giảm 1; dòng cờ của C còn nguyên | ✅ phần dưới PhotoKit: `UserMarkRemovalPolicyTests.indexDeletionRemovesRejected` (B gỡ, Rejected 3 → 2; C còn), `.limitedIndexRunKeeps`, `.deletionFromTheAppAlwaysRemoves`; đường xoá trong app đi qua một chỗ (`PhotoLibraryService.deleteAssets` → `onAssetsDeleted`). ⚠️ trên sim chưa: cần xoá B trong app Photos và một chạm tay vào hộp chọn `.limited` (plan ❓-5) |
| AC-10 | iOS 27, ảnh A 2★, ghi sao trả lỗi (giả lập) | bấm `5` | ô và viewer quay về 2★ trong ≤ 1 s; có "Couldn't save rating." + Try Again; bảng sao chờ không có dòng | ✅ `PhotoMarksTests.photosWriteFailureReverts` (về 2★ ngay khi lệnh ghi trả về, báo một lần, 0 dòng chờ), `.tryAgainRetriesSameIds`; sim iPhone 17 iOS 27.0 `ShotDexUITests/scripts/rating-write-failure-27.json` với `-ShotDexFailRatingWrites` (DEBUG): phím `5` → sau 1,1 s dòng 2 không còn sao, banner "Couldn't save rating." + Try Again. ⚠️ ảnh iPad chưa chụp |
| AC-11 | iOS 27, sao của ảnh A đổi trong app Photos (hoặc máy khác), ngày sửa của A không đổi | lượt index tăng dần kế tiếp chạy xong | lọc ★ ≥ N (N = sao mới) có A; 0 lần đọc file của A | ✅ `AssetFactsRefresherTests.ratingChangedInPhotosReachesFilter` (refresher không có reader; mọi cột trừ `rating` giữ nguyên), `IndexRunChangesTests.skippedUpdatedIdsAreDelivered`, `IndexDiffTests.factsDriftWithoutEdit` (walk đầy), `.ratingBackfillOnlyNulls` (thêm 2026-10-03) |

**Chưa chứng minh được:** không AC nào thiếu test; còn phần máy thật/sim ghi ⚠️ trong từng dòng (M2 trần khối, `.limited` trên sim, AC-9 xoá trong app Photos). AC-9 trên sim (đang làm theo plan [rating-flags-cull](../../_plans/2026-10-02-rating-flags-cull.md)).

## 10. Rủi ro

| Rủi ro | Xử lý |
|---|---|
| PhotoKit có trần số yêu cầu trong một khối thay đổi không | đo trên máy với 10.000 ảnh trước `/plan`. Có trần thì chia khối 1.000 ảnh, chạy nối tiếp; thay đổi thư viện đã gộp 1 s nên vẫn ≤ 10 nhịp |
| Đổi sao trên iOS 27 có làm đổi ngày sửa của ảnh, kéo theo index lại cả lô không | đo trên máy với AC-2. Nếu có thì lượt index bỏ qua ảnh chỉ đổi sao, như favorite |
| Cờ không đồng bộ: người dùng lọc trên iPad thì iPhone không thấy | ghi rõ ở §3. Đồng bộ cờ cần server hoặc iCloud của app, nằm ngoài intent |
| Lên iOS 27 bằng cách khôi phục backup sang máy mới | bảng cờ và bảng chờ đi theo backup của app; luật §5 chạy như thường |

**Số đo M1 (2026-10-03, sim iPhone 17 iOS 27.0, thư viện 10.092 asset, `ShotDexTests/PhotoPropertyProbeTests`):**

| Đo | Kết quả |
|---|---|
| Ghi `rating` trong **một** `performChanges` | 1 ảnh 0,01–0,03 s · 300 ảnh 0,17–0,25 s · 2.000 ảnh 1,1–1,35 s; không lỗi, không hộp thoại; đọc lại đủ 100 % |
| `modificationDate` | **đổi** với mọi ảnh mà sao thật sự đổi giá trị (ghi lại cùng giá trị thì không đổi gì). Đổi favorite cũng đổi ngày sửa. → app ghi sao xong phải đóng dấu ngày sửa mới vào `photo_metadata`, không thì lượt index kế đọc lại cả lô (plan task 7) |
| `fetchPersistentChanges` | id đổi sao nằm trong `updatedLocalIdentifiers` (299/299, 1.700/1.700, 300/300); 0 inserted, 0 deleted |
| `PHChange` của fetch all-photos | 1 thông báo cho cả khối; chỉ `changedIndexes`, `isStructural` = không → lưới không nạp lại |
| `PHFetchOptions.predicate` `rating >= 3` | nhận, đếm đúng |
| Video | nhận sao, đọc lại đúng |
| Một khối **10.000** (M2 phần làm được trên sim, `.tenThousandInOneBlock`) | 7,7 s, không lỗi, đọc lại 10.000/10.000, 1 thông báo, không cấu trúc — sim không có trần tới 10.000 |
| Trần trên máy 55k, nhiệt, pin, ảnh chỉ iCloud | chưa đo — M2 trên máy thật; AC-3 làm theo "đúng 1 khối" như viết, trần trên máy (nếu có) sẽ đổi AC-3 (plan ❓-1) |

Hệ quả cho AC-11: trong thực tế sao đổi ở Photos hay máy khác **luôn** đổi ngày sửa, nên lượt index tăng dần đọc
lại ảnh đó một lần (chấp nhận, như sửa ảnh — plan §7). AC-11 khoá trường hợp ngày sửa đứng yên: id có trong
`updated` mà `needsReindex` bỏ qua vẫn được làm tươi favorite và sao, không đọc file.
