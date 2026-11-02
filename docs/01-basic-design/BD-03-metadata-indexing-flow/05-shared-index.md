# BD-03.05 — Chỉ đọc bản gốc, và dữ liệu index dùng chung qua iCloud

`BD-03.05` · `Domain/Indexing/SharedIndex.swift` · `Data/Sources/IndexShareService.swift`
· `Data/Sources/IndexReadPolicy.swift` · `Data/Database/SharedIndexStore.swift` (migration `v45-sharedIndex`)
· `ShotDexMac/Settings/MacIndexingSettings.swift` · test `SharedIndexStoreTests` · cập nhật 2026-11-02

**Một câu:** Mac đọc được ảnh rất nhanh khi bản gốc đã nằm trên máy; mỗi ảnh chỉ cần một máy đọc, các máy
khác cùng tài khoản iCloud lấy kết quả qua CloudKit.

Intent: [mac-local-only-index](../../_intents/2026-11-02-mac-local-only-index.md) ·
[icloud-shared-index](../../_intents/2026-11-02-icloud-shared-index.md).

## 1. Chỉ đọc bản gốc (`IndexReadPolicy.readsOriginalsOnly`)

- **Mac:** công tắc *Index Only Photos Downloaded to This Mac* (Settings › General › Indexing), mặc định **tắt**.
- **iPhone/iPad/Duo:** bật khi một Mac trên cùng tài khoản bật *Index for iPhone and iPad* và máy này không bật
  *Index on This Device* (Settings › Photo Library).
- Khi bật: `ExifReader` chỉ thử đọc bản gốc trên máy. Không có bản gốc thì trả `pendingICloud`: không đọc bản
  thu nhỏ, không tải gì từ iCloud, không tính vào số lần đọc lỗi. `allowNetwork` của lượt chạy luôn là false,
  nên không tự thử lại qua mạng và không hiện thẻ "iCloud không phản hồi".
- **Index Now** (Mac) chạy `reindexIncomplete` với mạng được phép, tức thang đọc đầy đủ như trước.
- Dòng *Not Indexed on This Mac* đếm các dòng `pendingICloud`: ảnh chưa có thông số, bất kể nguồn. Ảnh đã nhận dữ
  liệu từ máy khác thì đã thành `indexed`, nên không còn trong số này.
- Mac đọc song song **24** ảnh (iPhone vẫn 12): ảnh Mac đọc đa phần là bản gốc trên ổ nhanh.

## 2. Dữ liệu index dùng chung

- **Khoá:** `PHCloudIdentifier` của ảnh, là id duy nhất mọi máy cùng iCloud Photos đều thống nhất. Ảnh chưa lên
  iCloud thì không có id này, nên không chia sẻ được.
- **Dùng lại khi nào:** khi `modificationDate` (giây) trùng với ảnh trên máy. Lệch ngày nghĩa là ảnh đã bị sửa:
  máy tự đọc lại và đẩy bản mới lên.
- **Chia sẻ những gì:** `RawExif` (thông số máy, ống kính, phơi sáng, thẻ panorama) và ô địa điểm đã tra
  (`place_cells`). Thông số được chuẩn hoá lại tại máy nhận, nên bảng cảm biến hay mapping máy ảnh người dùng tự
  đặt vẫn áp dụng. Dữ liệu người dùng tự nhập không đi qua đây.
- **CloudKit:** container `iCloud.com.hoangtuan.shotdex`, private database, zone `SharedIndex`. Có ba loại
  record: `PhotoExif` (tên = cloud id), `PlaceCell` (tên = cell key) và `IndexSettings` (một record, chứa
  `macIndexesForAll` và `macName`).
- **Lưu trên máy:** `shared_exif` (cloud id → ngày sửa và JSON của EXIF, cùng nguồn `local` hoặc `cloud`) và
  `cloud_outbox` (những gì chờ đẩy lên). Hai bảng này tách khỏi `photo_metadata` vì indexer ghi đè cả dòng của
  bảng đó.
- **Thứ tự trong một lượt:** kéo dữ liệu về trước, chờ tối đa 30 s. Sau đó tới lượt index: với mỗi lô 200 ảnh, ảnh
  nào đã có kết quả khớp ngày thì ghép từ kết quả đó, không mở file. Hết lượt, `adoptSharedResults` lấp các dòng
  còn chờ từ dữ liệu vừa kéo về, rồi đẩy outbox lên. Ô địa điểm được đẩy lên thêm một lần nữa khi bước tra địa
  điểm xong.
- **Xung đột:** khi kéo về, bản đọc tại chỗ có ngày sửa mới hơn được giữ. Khi đẩy lên, dùng `.allKeys` (ghi đè), vì
  bản mới nhất là bản cần giữ. Ô địa điểm đã tra được tại chỗ thì giữ nguyên.
- **Tắt hoặc không có iCloud:** mọi lời gọi thành no-op và index chạy như trước khi có tính năng này. Bản Mac ký
  thiếu entitlement iCloud cũng không crash: `IndexShareService.isEntitled` chặn trước khi tạo container.

## 3. Tiêu chí nghiệm thu

| AC | Cho | Khi | Thì | Chứng minh |
|---|---|---|---|---|
| AC-1 | Mac bật *Index Only…*, 1 ảnh có bản gốc và 1 ảnh chỉ trên iCloud | chạy index | ảnh local thành `indexed`, ảnh iCloud thành `pendingICloud`; 0 byte qua mạng; không có lượt tự thử lại | ⚠️ chưa kiểm (cần Mac đã ký với iCloud và thư viện thật) |
| AC-2 | như AC-1 | bấm *Index Now* | ảnh iCloud được đọc qua mạng và thành `indexed` | ⚠️ chưa kiểm |
| AC-3 | một ảnh đã đọc trên máy A (cùng ngày sửa) | máy B index | máy B ghép từ dữ liệu của A, không mở file (`exifReads` không tăng) | ⚠️ chưa kiểm (cần hai máy thật) |
| AC-4 | ảnh đã sửa trên máy B sau khi A đọc | máy B index | B đọc lại, bản của B có ngày mới hơn và thắng khi A kéo về | `SharedIndexStoreTests.aNewerReadWinsOverAnOlderRemoteRow` (store) · phần thiết bị ⚠️ chưa kiểm |
| AC-5 | đọc lại thư viện, EXIF không đổi | lưu lại | không xếp hàng đẩy lại | `SharedIndexStoreTests.anUnchangedReadIsNotQueuedAgainAfterPush` |
| AC-6 | dòng kéo từ máy khác về | lưu | không vào outbox | `SharedIndexStoreTests.aRowFromAnotherDeviceIsNotQueued` |
| AC-7 | một ô địa điểm tra được trên máy A | máy B có ảnh trong ô đó | ảnh của B có tên địa điểm, không gọi geocoder; ô B đã tự tra thì giữ nguyên | `SharedIndexStoreTests.placeCellsTravelBothWays` |
| AC-8 | Mac bật *Index for iPhone and iPad* | iPhone kéo dữ liệu về | iPhone chỉ đọc bản gốc trên máy; Settings có dòng *Index on This Device* ghi tên Mac | ⚠️ chưa kiểm (cần iPhone thật cùng iCloud) |
| AC-9 | Mac tắt *Share Index Across Devices* khi đang bật *Index for…* | — | *Index for…* tự tắt và trạng thái "tắt" vẫn được đẩy lên, để iPhone thôi chờ Mac | ⚠️ chưa kiểm |
| AC-10 | bản Mac ký thiếu entitlement iCloud | mở app, chạy index | không crash; index chạy như trước | đã chạy bản build không ký với `-ShotDexDemoLibrary` (2026-11-02) |

**Chưa chứng minh được:** AC-1/2/3/8/9 và phần thiết bị của AC-4. Cần (a) Xcode đăng nhập Apple ID để tạo
profile có iCloud cho bản Mac, (b) simulator: máy này đang không có runtime iOS nào dùng được, (c) hai máy thật
cùng tài khoản iCloud Photos. Unit test mới chỉ mới **biên dịch** được (`build-for-testing`), chưa chạy được vì
không có simulator.

## 4. Còn treo (spike trên máy thật)

- `cloudIdentifierMappings` theo lô lớn: tốc độ, và ảnh Shared Library hay ảnh chưa upload xong thì sao.
- `PHAsset.modificationDate` của cùng một ảnh có khớp giữa Mac và iPhone không. Nếu không khớp thì AC-3 không bao
  giờ xảy ra, và phải đổi khoá so sánh (ví dụ hash của các trường EXIF).
- Quota và throttle của CloudKit khi đẩy lần đầu 50–100 nghìn record.
- Schema CloudKit được tạo tự động ở môi trường Development. Trước khi phát hành phải **Deploy Schema Changes**
  sang Production trong CloudKit Console.
