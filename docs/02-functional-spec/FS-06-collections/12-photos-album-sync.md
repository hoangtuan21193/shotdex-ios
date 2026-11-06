# FS-06.12 — Giữ smart album thành một album trong Photos

`FS-06.12` · tier B · `Features/Albums/SmartAlbumEditorSheet.swift` · `Features/Albums/SmartAlbumDetailScreen.swift` ·
`Data/Sources/PhotoLibraryService.swift` (`createAlbum`, `addAssets`, `removeAssets`) · bảng mới · cập nhật 2026-11-06

**Một câu:** người dùng bật một công tắc trên smart album, ShotDex giữ một **album thật trong app Photos** luôn có
đúng những ảnh đó. Nhờ vậy người dùng mở được tập ảnh ấy trong Photos để làm những việc chỉ Photos làm được, trước
hết là **Move to Shared Library**.

Nguồn: [intent 2026-11-06-photos-album-from-smart-album](../../_intents/2026-11-06-photos-album-from-smart-album.md).
Liền kề: [08 Smart Album](08-smart-albums.md) · [11 Shared Library](11-shared-library.md) · điều kiện Also on Server
[FS-19.07 §7](../FS-19-photo-sources/07-on-server-check.md) · lượt kiểm nền [FS-19.07 §6](../FS-19-photo-sources/07-on-server-check.md).

## 1. Người dùng cần gì

Gia đình hai Apple Account, iCloud đầy. Ảnh đã có trên NAS (smart album *Also on NAS Home › Shared*) cần đưa vào iCloud
Shared Library. PhotoKit **không có API** đưa ảnh vào Shared Library (SDK iOS 27.1, kiểm 2026-11-06). Chỉ app Photos
làm được: chọn ảnh → Move to Shared Library. Smart album của ShotDex không hiện trong Photos, và tập ảnh lớn dần mỗi
đợt kiểm NAS, qua nhiều ngày. Chép tay một lần thì album đứng yên.

## 2. Phạm vi

**Có:**
- Công tắc **Keep in Photos** trên smart album. Bật lần đầu thì tạo một album thường trong Photos.
- Đồng bộ liên tục: thêm ảnh mới khớp, bỏ ảnh không còn khớp. Album Photos **luôn bằng** smart album (người dùng chốt
  2026-11-06: ghi đè cả thay đổi tay trong Photos).
- Chạy khi app ở trước mặt **và ở nền**, cùng lượt kiểm On Server (người dùng chốt 2026-11-06).
- Dòng trạng thái trên màn smart album, kèm một câu hướng dẫn Move to Shared Library.
- Mọi smart album bật được, không riêng Also on Server.

**Cố ý không có:**
- Chuyển ảnh vào Shared Library. PhotoKit không cho. Người dùng tự làm trong Photos.
- Biết ảnh nào đã ở Shared Library. Đó là spike của [FS-06.11](11-shared-library.md). Chưa có API thì không đoán.
- Xoá ảnh. Đồng bộ chỉ thêm/bỏ ảnh **khỏi album**, không bao giờ xoá ảnh khỏi thư viện.
- Album thường của người dùng làm đích. ShotDex chỉ đụng album do chính nó tạo cho smart album đó.
- Mac — ngoài phạm vi lần này (intent Q7). Thư viện Photos trên Mac là việc riêng.
- Folder Photos (`PHCollectionList`) để gom các album đồng bộ.

## 3. Trạng thái màn hình

Dòng trạng thái nằm dưới thanh điều kiện của smart album, sau dòng tiến độ On Server nếu có. Dùng cùng kiểu chữ phụ.

| Trạng thái | Hiển thị |
|---|---|
| tắt | không có dòng |
| đang tạo / đang đồng bộ | `Updating album in Photos…` |
| đã đồng bộ | `In Photos · 1,284 photos · Updated 2 min ago` (album trong Photos cùng tên smart album nên không nhắc lại tên — tên dài làm dòng bị cắt trên iPhone 402pt) và dưới đó `To share these, open the album in Photos and choose Move to Shared Library.` |
| chờ (smart album còn đang kiểm On Server) | như *đã đồng bộ*. Album chỉ có ảnh đã kiểm xong, số đếm tăng dần |
| album bị xoá trong Photos | `The album was deleted in Photos. Keep in Photos is off.` Công tắc về tắt |
| quyền `.limited` / bị từ chối | công tắc tắt và không bật được. Chân công tắc ghi `Needs Full Photos Access.` + nút mở Settings |
| lỗi ghi PhotoKit | `Couldn't update the album in Photos. Will try again.` Lần sau thử lại |

## 4. Hành vi

- **Bật:** công tắc **Keep in Photos** ở cuối Smart Album editor, dưới Conditions (§6). Chân công tắc:
  `ShotDex keeps an album in Photos with exactly these photos.` Lưu sheet là tạo album tên = tên smart album. Trùng
  tên với album có sẵn thì **vẫn tạo album mới** (Photos cho phép trùng tên), không bao giờ dùng album có sẵn.
- **Đồng bộ:** tập đích = các mục **Photos** smart album khớp lúc đó, kể cả lọc của chính nó, **không** kể menu Filter
  tạm của màn ([FS-06.09](09-album-filter-menu.md)). Ảnh riêng của nguồn thư mục/server (không có PHAsset) bị bỏ qua.
  So với nội dung hiện tại của album trong Photos: thêm phần thiếu, bỏ phần thừa.
- **Khi nào:** sau mỗi lần tập khớp có thể đổi — lưu sheet, xong một đợt kiểm On Server, PhotoKit báo đổi thư viện
  (thêm, xoá, sửa metadata), index ghi xong một lô. Gom lại: tối đa một lượt mỗi 10 giây cho mỗi album. Ở nền: chạy ở
  cuối lượt nền của `OnServerBackground` (`afterPass`). Album không có điều kiện On Server thì chưa có slot nền riêng —
  nó đồng bộ khi app về trước mặt (2026-11-07, theo code).
- **Lô:** thêm/bỏ tối đa 500 ảnh mỗi `performChanges`, ngoài main thread. Huỷ được giữa lượt (app ra nền hết giờ):
  lượt sau tính lại từ đầu, vì so với nội dung thật của album nên không mất gì.
- **Đổi tên smart album:** đổi tên album trong Photos theo. Người dùng tự đổi tên trong Photos thì lần sau bị ghi đè
  (cùng luật ghi đè).
- **Tắt** công tắc hoặc **xoá smart album:** ShotDex thôi đụng tới album; album còn nguyên trong Photos với ảnh của nó.
  Hộp xoá smart album nói thêm: `The album "Shared NAS" stays in Photos.`
- **Album bị xoá trong Photos** (change observer thấy collection không còn): tắt đồng bộ, ghi trạng thái §3. Không tạo
  lại tự động.
- **Bật lại sau khi tắt:** **dùng lại** album cũ nếu nó còn trong Photos (người dùng chốt 2026-11-06 — có thể đã chia
  sẻ hay đặt nó vào folder trong Photos), rồi đồng bộ đè như thường. Album cũ đã bị xoá → tạo album mới. Vì vậy tắt
  công tắc chỉ đặt `isEnabled = 0`, giữ `collectionLocalId`.
- **Hướng dẫn:** câu `To share these, open the album in Photos and choose Move to Shared Library.` chỉ là chữ, không
  có nút (người dùng chốt 2026-11-06). Không có URL công khai mở thẳng một album trong Photos.

## 5. Dữ liệu

- Bảng riêng `smart_album_photos_album` (migration mới): `smartAlbumId` (khoá chính), `collectionLocalId`,
  `isEnabled`, `lastSyncedAt`, `lastError`, `assetCount`. Đây là lựa chọn của người dùng, **không** nằm trong
  `photo_metadata` và không bị Clear Local Metadata Index xoá ([BD-02](../../01-basic-design/BD-02-database-design.md)).
  Không khoá ngoại tới `smart_albums`: xoá smart album thì xoá dòng này trong cùng transaction.
- App chưa release → không tương thích ngược.
- Tập đích tính bằng **một** truy vấn smart album hiện có. Nội dung album Photos đọc bằng một `PHAsset.fetchAssets(in:)`.
  Hiệu hai tập tính trên `Set<String>` của `localIdentifier`, không truy vấn từng ảnh ([NF-01](../../04-non-functional-design/NF-01-performance.md)).

## 6. Ràng buộc

- **Tier B**, hàng chuẩn của Form (toggle + chân chữ). Không token, màu hay bo góc mới ([DESIGN.md](../../../DESIGN.md)).
  Công tắc nằm trong **editor**, section cuối dưới Conditions (người dùng chốt 2026-11-06). Layout hai cột (Duo trong) đặt nó cuối cột trái, dưới Match. Duo trong 951×669: section
  này được phép nằm dưới mép (cuộn mới thấy); FS-06.08 AC-4 (3 điều kiện + Add Condition thấy trọn) vẫn phải đạt.
- Board phải vẽ trước khi code: `PH_/IP_/DI_/DC_SmartAlbumEditor` (công tắc) và `PH_/IP_/DI_/DC_SmartAlbum` (dòng
  trạng thái + câu hướng dẫn). Cả bản sáng và tối.
- Nhánh iOS 26 / trước 26: không khác về hành vi. Dòng trạng thái theo vị trí thanh điều kiện của từng nhánh.
- Không chặn main thread; 55.000 ảnh thêm lần đầu chạy theo lô 500 ảnh, có tiến độ (`Updating album in Photos… 12,000 of 55,000`).
- Chữ qua String Catalog, tiếng Anh kiểu Mỹ; số đếm qua FormatStyle; plural qua catalog.
- Không test bằng ảnh có mặt người.

## 7. Tiêu chí nghiệm thu

Thư viện thử trên simulator iPhone 17 iOS 26.5 (và 18.6 cho AC-UI). Không có ảnh mặt người.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | spike, iPhone thật, Shared Library 2 người, album "Sync Test" 20 ảnh do ShotDex đồng bộ | trong Photos: Select All → Move to Shared Library; mở ShotDex, chờ một lượt đồng bộ | ghi: `localIdentifier` của 20 ảnh có đổi không; album còn 20 ảnh không; lượt đồng bộ có thêm/bỏ ảnh nào không. Đạt khi 0 ảnh bị thêm/bỏ | ⚠️ chưa có — spike, ghi số vào intent. **Không đạt thì dừng spec** và quay lại intent |
| AC-2 | smart album "Shared NAS" khớp 120 ảnh, quyền Full | bật Keep in Photos, Save | Photos có một album mới "Shared NAS" chứa đúng 120 ảnh đó; dòng trạng thái `In Photos · 120 photos · Updated …` | `PhotosAlbumSyncTests.createsAndFills` (công tắc + dòng: ảnh ở AC-16) |
| AC-3 | đã có album "Shared NAS" do người dùng tạo, 5 ảnh | bật Keep in Photos cho smart album cùng tên | album mới được tạo; album của người dùng vẫn 5 ảnh, không bị đụng | `PhotosAlbumSyncTests.neverAdoptsUserAlbum` |
| AC-4 | album đồng bộ 120 ảnh; một đợt On Server kiểm xong thêm 30 ảnh khớp và 4 ảnh thôi khớp | xong đợt kiểm | trong ≤ 10 s album Photos có 146 ảnh: 30 ảnh mới có, 4 ảnh kia không còn; 4 ảnh vẫn còn trong thư viện | `PhotosAlbumSyncTests.followsMatchChanges` (≤ 10 s: `PhotosAlbumSync.minimumGap`, nối kích hoạt ở task 8) |
| AC-5 | album đồng bộ 120 ảnh; người dùng trong Photos thêm tay 3 ảnh khác và bỏ 2 ảnh của album | mở ShotDex | sau một lượt album lại đúng 120 ảnh của smart album | `PhotosAlbumSyncTests.overwritesManualEdits` |
| AC-6 | smart album khớp 100 ảnh, 10 trong đó chưa kiểm On Server xong | đồng bộ | album Photos có 90 ảnh; 10 ảnh chưa kiểm không có | theo SQL Also on Server: chưa kiểm không vào Yes (`AlsoOnServerRuleTests.yesNoUncheckedAndServerOnly`); sync lấy đúng tập đó (`SmartAlbumPhotosAlbumStore.photoKitIds`) |
| AC-7 | smart album gồm 50 mục Photos + 8 ảnh chỉ có trên nguồn thư mục | đồng bộ | album Photos có 50 ảnh; không lỗi vì 8 mục không có PHAsset | `PhotosAlbumSyncTests.ignoresNonPhotosItems` |
| AC-8 | album đồng bộ 120 ảnh | tắt Keep in Photos | album Photos còn 120 ảnh; lượt đồng bộ sau không đụng tới nó (thêm 5 ảnh khớp: album vẫn 120) | `PhotosAlbumSyncTests.offLeavesAlbum` |
| AC-9 | album đồng bộ 120 ảnh | xoá smart album | hộp xoá có câu `The album "Shared NAS" stays in Photos.`; sau xoá album Photos còn 120 ảnh; bảng `smart_album_photos_album` không còn dòng | hộp `AlbumsScreen.deletingKeptSmartAlbum` (ảnh: AC-16); store: `PhotosAlbumSyncTests.deleteKeepsPhotosAlbum` |
| AC-10 | album đồng bộ | xoá album trong Photos, mở ShotDex | công tắc tắt; dòng `The album was deleted in Photos. Keep in Photos is off.`; không album mới nào được tạo | `PhotosAlbumSyncTests.deletedInPhotosTurnsOff` (dòng chữ: ảnh ở AC-16) |
| AC-11 | quyền `.limited` | mở editor | công tắc Keep in Photos tắt, không bật được; chân ghi `Needs Full Photos Access.` + nút mở Settings | `SmartAlbumEditorSheet.keepInPhotosSection` (ảnh ở AC-16) |
| AC-12 | smart album khớp 55.000 ảnh | bật Keep in Photos | không `performChanges` nào quá 500 ảnh; main thread không chặn > 100 ms; dòng tiến độ đếm lên; giết app giữa lượt → mở lại, album về đủ 55.000, không ảnh trùng | `PhotosAlbumSyncTests.batchesAndResumes` (lô 500; main thread: chụp ở task 11) |
| AC-13 | PhotoKit ném lỗi ở lô thứ 2 | đồng bộ | dòng `Couldn't update the album in Photos. Will try again.`; lượt sau thử lại và album đủ | `PhotosAlbumSyncTests.retriesAfterError` |
| AC-14 | album đồng bộ, app ra nền, On Server kiểm xong ở nền thêm 12 ảnh khớp | mở Photos (không mở ShotDex) | album có thêm 12 ảnh | `OnServerBackgroundService.afterPass` → `PhotosAlbumSync.syncNow`; máy thật: S3 |
| AC-15 | đổi tên smart album "Shared NAS" → "Family NAS" | Save | album Photos đổi tên "Family NAS" | `PhotosAlbumSyncTests.followsRename` |
| AC-17 | album đồng bộ "Shared NAS" 120 ảnh, đã tắt; người dùng thêm tay 2 ảnh vào album trong Photos | bật lại Keep in Photos | không album mới nào được tạo; "Shared NAS" về đúng 120 ảnh của smart album. Album cũ đã bị xoá trong Photos → một album mới được tạo | `PhotosAlbumSyncTests.reenableReusesAlbum` |
| AC-16 | iPhone 402×874, Duo trong 951×669, Duo ngoài 466×678, iPad 1376×1032; iOS 26.5 và 18.6 | mở editor có 3 điều kiện + Keep in Photos; mở smart album đã đồng bộ | công tắc, chân chữ, dòng trạng thái thấy trọn, không cắt chữ; lệch ≤ 2pt so với board vẽ mới; Duo trong vẫn đạt FS-06.08 AC-4 (công tắc được phép nằm dưới mép) | ⚠️ chưa có — design-parity trên `PH_/IP_/DI_/DC_SmartAlbumEditor`, `PH_/IP_/DI_/DC_SmartAlbum` |

**Chưa chứng minh được:** AC-1 (cần iPhone thật có Shared Library), AC-9 hộp xoá, AC-11, AC-14, AC-16 — task 7, 8, 11.

## 8. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Move to Shared Library đổi `localIdentifier` hoặc tách ảnh khỏi album → đồng bộ thêm/bỏ lung tung | spike AC-1 trước khi code; không đạt thì dừng |
| Ghi đè xoá mất thay đổi người dùng cố ý làm trong Photos | chân công tắc nói rõ "exactly these photos"; người dùng đã chọn ghi đè |
| App sửa thư viện Photos ở nền, người dùng bất ngờ | chỉ đụng album ShotDex tạo; không bao giờ xoá ảnh; dòng trạng thái ghi lần cập nhật cuối |
| 55.000 ảnh thêm một lượt làm Photos/iCloud đồng bộ nặng | lô 500, gom lượt 10 s; đo trên máy thật cùng S3 |
| Hai máy (vợ/chồng) cùng bật cho smart album cùng tên → hai album trùng tên trong Photos chung? | album thường thuộc thư viện riêng của từng Apple Account — không trùng. Ghi lại nếu spike AC-1 thấy khác |
