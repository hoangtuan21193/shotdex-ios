# Intent: Những gì photographer đòi mà ShotDex chưa có (đợt nghiên cứu 30/9)

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan@karabiner.tech |
| Ngày | 2026-09-30 |
| Trạng thái | accepted — người dùng 2026-10-01: "spec đi" |
| Tiến độ | **đang làm** (2026-10-02) — 4 plan đã duyệt (icloud 18 · raw 21 · privacy 24 · stats 17 task), task 18/18 icloud (gần xong: AC máy thật, Duo), task 16/17 stats, task 21/21 raw (gần xong: thiết bị khác, máy thật cho AC-4/AC-10/AC-12), task 24/24 privacy (gần xong: task 4 + /verify trên máy, task 10 xong qua modal FS-02.06), 69/91 AC xanh (FS-03.04b AC-1, AC-12, AC-2, AC-3, AC-14, AC-4, AC-9, AC-6, AC-7, AC-8, AC-10, AC-11, AC-5, AC-16, AC-17, AC-13, AC-15, AC-18; FS-08.06 AC-17, AC-3, AC-4, AC-5, AC-10, AC-7, AC-20, AC-6, AC-9, AC-16, AC-15, AC-13, AC-22, AC-12, AC-18, AC-8, AC-2, AC-11; FS-07 AC-1, AC-2, AC-3, AC-4, AC-5, AC-6, AC-7, AC-8, AC-9, AC-10, AC-11, AC-15, AC-16, AC-17, AC-18; FS-02.06 AC-17, AC-11, AC-1, AC-6, AC-7, AC-14, AC-18, AC-8, AC-16, AC-9, AC-10, AC-12, AC-3, AC-4, AC-5, AC-15, AC-13, AC-2); burst chờ đo máy thật; đợt 2 có spec (79 AC), mọi lựa chọn đã chốt 2026-10-02, chờ canvas + /plan; đợt 2: 5 plan đã duyệt 2026-10-03 (rating 19 · caption 22 · export 16 · watermark 16 · video look 16 task — video look chờ khung Video Studio mới); đợt 2 **đang làm**: rating task 2/19, 2/81 AC xanh (FS-01.12 AC-1, AC-11) |
| Nguồn | phản hồi người dùng — nghiên cứu diễn đàn 2026-09-30 (Apple Community, Adobe Community, Lightroom Queen, DPReview, MacRumors, Hacker News, review App Store; Reddit chặn truy cập nên không có) + đối chiếu code cùng ngày |
| Spec sinh ra từ đây | đợt 1: [FS-02.06](../02-functional-spec/FS-02-photo-detail/06-icloud-originals.md) (mục 1, 15 AC) · [FS-03.04b](../02-functional-spec/FS-03-photo-editor/04b-unsupported-raw.md) (mục 2, 12 AC) · [FS-08.06](../02-functional-spec/FS-08-settings/06-share-metadata-privacy.md) (mục 3, 14 AC) · [FS-07](../02-functional-spec/FS-07-statistics/README.md) (mục 5, 15 AC) · [FS-02.05](../02-functional-spec/FS-02-photo-detail/05-burst-selection.md) (mục 12, 12 AC) · đợt 2: [FS-01.12](../02-functional-spec/FS-01-library/12-rating-and-flags.md) 11 AC + [FS-01.12b](../02-functional-spec/FS-01-library/12b-culling-pass.md) 8 AC (mục 9) · [FS-02.07](../02-functional-spec/FS-02-photo-detail/07-caption-and-keywords.md) (mục 14, 16 AC) · [FS-03.07b](../02-functional-spec/FS-03-photo-editor/07b-export-to-files.md)/[07c](../02-functional-spec/FS-03-photo-editor/07c-export-acceptance-criteria.md) (mục 4, 15 AC) · [FS-05.04](../02-functional-spec/FS-05-markup/04-watermark-on-export.md) (mục 6, 15 AC) · [FS-12.06c](../02-functional-spec/FS-12-video-studio/06c-photo-looks.md) (mục 8, 16 AC) |

Người dùng muốn gom **mọi** chức năng người dùng mong mà ShotDex chưa có vào một intent (2026-09-30). Các mục
dưới đây độc lập với nhau. Lúc sang Design, mỗi mục sẽ vào `FS-*` của chính nó, không thành một spec chung.

## Problem — vấn đề

### Những gì đã có, không nằm trong intent này

Đối chiếu code 2026-09-30 cho thấy ShotDex đã làm được mấy thứ người dùng hay đòi nhất:

- **Thống kê gear.** Có camera, lens, tiêu cự thật và tiêu cự quy đổi (`Core/Models/ChartSpec.swift:153-166`,
  `Data/Database/MetadataStore.swift:557-564`).
- **Smart album theo EXIF.** Tự cập nhật (`Core/Models/SmartAlbumQuery.swift:30-47`).
- **Sửa ngay trong Photos, không tạo bản trùng, Revert to Original.** Lưu bằng adjustment data của PhotoKit
  (`Data/Sources/PhotoEditingService.swift:409-470`).
- **Sửa hàng loạt.** Copy/Paste Edits, Sync, Paste Edits từ thư viện (`Features/Library/LibraryScreen.swift:298`).
- **Trao đổi preset với Lightroom.** Nhập XMP/preset Lightroom, xuất look ra `.cube`/`.xmp` (`Domain/Editing/LookExchange/`).
- **Dọn ảnh trùng.** Exact, Similar, Series (`Domain/Duplicates/DuplicateGrouper.swift`).
- **Video Studio.** Có tỉ lệ 9:16/4:5/1:1, không watermark, nhạc nhập từ Files.

**Sửa caption và keyword** trước đây ghi là không làm được (`PHOTOS_PARITY.md:84`). SDK iOS 27.1 trên máy này đã có
API ghi (kiểm 2026-09-30), nên đưa vào thành mục 14:
- `PHAssetChangeRequest.caption`, `addKeyword(_:)` / `removeKeyword(_:)`;
- đọc qua `PHAsset.extendedMetadata` (`caption`, `keywords`, `originalFilename`);
- `PHAsset.rating` và `PHAssetChangeRequest.rating` (0–5).

Tất cả có từ iOS 27 (`Photos.framework/Headers/PHAssetChangeRequest.h:38-71`, `PHAssetExtendedMetadata.h`,
`PHAsset.h:71`).

### Những gì người chụp hôm nay không làm được

1. **Không biết ảnh đang phải tải từ iCloud, hay chỉ có bản xem trước.** Máy bật Optimize Storage thì phần lớn
   ảnh gốc nằm trên iCloud.
   - Editor chỉ hiện spinner "Downloading from iCloud…", không có phần trăm. `requestContentEditingInput` không
     đặt progress handler (`PhotoEditingService.swift:632-650`).
   - Share và Resize tải ảnh gốc mà không báo gì (`Features/Shared/PhotoShareSheet.swift:15-30`).
   - Không chỗ nào cảnh báo "máy mới có bản xem trước". Không chỗ nào tải trước ảnh gốc trước khi Resize hay export.
   - Trên diễn đàn có than phiền về nút tải bản gốc bị treo ([Apple Community 254682918](https://discussions.apple.com/thread/254682918)).
2. **Mở RAW của máy mới thì chỉ nhận một câu lỗi chung chung.** Câu "This RAW format can't be decoded on this device."
   (`ShotDexKit/Models/PhotoEditingModels.swift:1652`):
   - không nêu tên máy ảnh;
   - không gợi ý chuyển sang DNG;
   - chỉ hiện lúc mở editor, trong thư viện không có dấu gì.

   Apple thường hỗ trợ RAW máy mới chậm từ 6 tháng trở lên.
3. **Không chọn được bỏ vị trí cho từng lần chia sẻ hay xuất.** Hiện chỉ có một công tắc chung Include Location
   trong Settings (`Features/Settings/SettingsScreen.swift:489`). Công tắc Include Metadata lúc lưu thì bỏ hết
   hoặc giữ hết (`PhotoEditorScreen.swift:3608`), không có lựa chọn chỉ bỏ vị trí. Video không được xử lý phần này.
4. **Không xuất ảnh ra Files được.**
   - Resize chỉ lưu ngược vào Photos.
   - Không có mẫu đặt tên file.
   - Upload lên server không áp được preset kích thước hay định dạng
     (`ShotDex/Features/Settings/CompressionPresetsScreen.swift`, `Domain/ServerUpload/ServerUploadPlan.swift`).
5. **Có dữ liệu nhưng không nhận được câu trả lời "mình thật sự chụp tiêu cự nào".**
   - Dashboard thống kê do người dùng tự dựng. Lần đầu mở chỉ có Top Camera và Total Photos.
   - Các query đã viết sẵn nhưng chưa có UI gọi: `summary()`, `focalLengthHistogram()`, `slowShutterShare()`,
     `cameraMonthlyTrend()` (`Data/Database/StatisticsQueries.swift:130-285`).
   - Không có nhận xét kiểu "85% ảnh của bạn ở 24–35mm". Đây là hướng OV-01 §3 đã ghi mà chưa làm.
   - Người dùng ngoài kia phải tự viết script exiftool để biết điều này
     ([TidBITS 09/2025](https://tidbits.com/2025/09/25/tracking-my-iphone-camera-usage-with-a-deep-dive-into-exif-data/)).
6. **Watermark/chữ ký chỉ đóng được trong editor.** Resize, Share và export lên server không có lựa chọn
   đóng dấu (`Data/Sources/SignaturePresetStore.swift` không được dùng ngoài editor).
7. **Video Studio không khớp cắt clip theo nhịp nhạc.** Tìm `beat`, `onset`, `tempo`, `bpm` trong code không ra gì.
   Làm reel từ ảnh mà không bám nhịp là thiếu đúng thứ các app reel thu tiền theo tuần.
8. **Look đã lưu trong editor ảnh không dùng được trong Video Studio.** Video chỉ có một LUT cho cả project
   (`Domain/Video/VideoProjectModels.swift:446-495`). Muốn video cùng tông với ảnh, người dùng phải xuất look
   ra `.cube` rồi tự nhập lại.
9. **Không chấm sao, không đánh dấu giữ/loại được.** Chấm sao 0–5 và cờ pick/reject đã bị gỡ ở migration `v16`
   (`AppDatabase.swift:376-378`, lý do ghi ở `FS-01-library/README.md` §Đã gỡ). Người chụp vẫn đòi lọc ảnh
   nhanh sau buổi chụp. **Người dùng 2026-09-30 chọn đưa lại cả chấm sao lẫn pick/reject**, tức là đảo quyết định cũ.
10. **Không làm việc được với ảnh và video nằm trên SSD ngoài.**
    - Người dùng 2026-09-30: *không làm màn import*, nhưng phải sửa ảnh, dựng video, tạo video, ghép ảnh… được
      ngay với file trên SSD.
    - Hôm nay editor, collage và Video Studio chỉ nhận `PHAsset`.
    - Intent [network-folder-edit](2026-09-29-network-folder-edit.md) (đang làm) mở đường này cho folder mạng và
      folder cloud. Ổ ngoài chưa được gọi tên ở đâu và chưa được thử.
11. **Không dùng được màn hình ngoài để xem ảnh lớn.** App chỉ có một `WindowGroup` (`App/ShotDexApp.swift:25`)
    và không có scene riêng cho màn hình ngoài. Lưới thư viện không đi được bằng bàn phím. Adobe có một yêu cầu
    tương tự từ 11/2022 vẫn chưa làm
    ([Adobe idea](https://community.adobe.com/t5/lightroom-ecosystem-cloud-based-ideas/p-external-display-support-on-ipad/idc-p/14731862)).
12. **Burst chỉ xem được, không có bước chọn khung đẹp nhất rồi bỏ phần còn lại.** Hiện chỉ có "Show All Frames"
    (`PhotoLibraryService+Assets.swift:165`).
13. **App chưa có cách nào để người dùng trả tiền.** Không có StoreKit (tìm `StoreKit`, `Product`, `Transaction`
    không ra gì). Nghiên cứu cho thấy người dùng mệt vì subscription:
    - Adobe tăng $9.99 lên $14.99, CapCut tăng khoảng $78 lên $180 một năm.
    - Người dùng sẵn lòng mua đứt khoảng $30–60.
    - Hai điều bị ghét nhất là khoá chức năng xuất và watermark.

    **Người dùng 2026-09-30 chọn mua đứt một lần.**
14. **Không sửa được caption và keyword.**
    - Keyword chỉ hiện chỉ-đọc ở Info (`Data/Sources/AssetMetadataReader.swift:481`), không lọc được.
    - iOS 27 mở API cho cả hai (xem trên). Photos của Apple đã cho làm việc này.
    - ShotDex là app quản lý thư viện mà lại không làm được.

## Proposed outcome — kết quả mong muốn

- **iCloud.** Người dùng luôn biết một ảnh gốc có trên máy hay chưa, đang tải được bao nhiêu phần trăm. Trước
  khi xuất hay sửa hàng loạt, ảnh gốc được tải về trước. Không bao giờ âm thầm xuất ra bản xem trước.
- **RAW chưa hỗ trợ.** App nói rõ máy ảnh nào iOS này chưa đọc được và cần làm gì (chuyển DNG). Ảnh đó có dấu
  ngay trong thư viện, không đợi tới lúc mở editor.
- **Riêng tư khi chia sẻ.** Mỗi lần chia sẻ hay xuất, người dùng chọn giữ hết, bỏ vị trí, hoặc bỏ hết metadata.
  Mặc định lấy từ Settings. Áp cho cả video.
- **Xuất ra Files.** Xuất ảnh ra bất kỳ thư mục nào trong Files (kể cả SSD ngoài), dùng preset kích thước và định
  dạng sẵn có, tên file theo mẫu. Upload lên server cũng dùng được preset đó.
- **Nhận xét thống kê.** Mở Statistics lần đầu là thấy ngay: tiêu cự hay dùng, cặp body + lens hay dùng, tỉ lệ
  chụp chậm, xu hướng theo tháng. Có vài câu nhận xét rút từ dữ liệu của chính người dùng.
- **Watermark lúc xuất.** Resize, Share và export lên server có lựa chọn đóng watermark hoặc chữ ký đã lưu.
- **Video theo nhịp nhạc.** Video Studio tìm nhịp của bài nhạc và cắt clip theo nhịp đó.
- **Look dùng chung.** Look đã lưu và film simulation của editor ảnh chọn được thẳng trong Video Studio, cho cả
  project hoặc từng clip.
- **Chấm sao và cờ.** Chấm sao 0–5 và cờ pick/reject, nhanh bằng một chạm hoặc một phím. Lọc và smart album được
  theo sao và cờ. Có một lượt lọc ảnh sau buổi chụp chạy toàn bằng bàn phím hoặc vuốt.
- **SSD ngoài.** Ảnh và video trên SSD ngoài sửa được, đưa vào Video Studio, collage, Combine (HDR/panorama)
  được mà không cần nhập vào Photos. Kết quả lưu ở chỗ người dùng chọn.
- **Màn hình ngoài.** Trên iPad nối màn hình ngoài: ảnh lớn ở màn ngoài, iPad làm bàn điều khiển. Đi được
  trong thư viện bằng bàn phím.
- **Burst.** Chọn khung đẹp nhất, bỏ phần còn lại trong một bước.
- **Caption và keyword (iOS 27).** Sửa caption và keyword cho một hoặc nhiều ảnh. Lọc và smart album được theo
  keyword. Dưới iOS 27 thì chỉ đọc.
- **Mua đứt.** Mua một lần mở khoá bản đầy đủ. Không khoá chức năng xuất, không watermark, trước khi mua có cách
  dùng thử.

## Affected users and systems — phạm vi ảnh hưởng

- **Màn hình.** Library (lưới, lọc, chọn nhiều), Photo Detail, Editor, Resize, Share sheet, Statistics,
  Smart Albums, Collections → Utilities, Video Studio, Settings, và màn mua hàng (mới).
- **Thiết bị.** iPhone, iPad, Duo trong, Duo ngoài. Riêng màn hình ngoài chỉ iPad (và Duo nếu có cổng hình).
  Theo luật "phone có mọi tính năng của iPad", mọi thứ khác phải có trên cả iPhone.
- **Tầng code.**
  - Domain: nhận xét thống kê, phát hiện nhịp, mẫu tên file, luật lọc theo sao.
  - Data: `PhotoEditingService` (progress), `StatisticsQueries`, và **bảng mới** cho sao và cờ.
  - Features: hầu hết các màn kể trên.
  - ShotDexKit: render look cho video.
  - Extension: Share extension phải tôn trọng lựa chọn bỏ vị trí.
- **Dữ liệu đã lưu.**
  - Sao và cờ là dữ liệu người dùng tự nhập. Pick/reject, và sao trên iOS 17–26, nằm ở **bảng riêng**, không nằm
    trong `photo_metadata` (BD-02 §4).
  - Bảng `photo_cull` cũ đã bị drop, bảng mới là migration mới.
  - Trên iOS 27 sao nằm trong Photos. Lúc chuyển sang Photos phải dùng một change request cho cả lô, để không kích
    một cơn bão thay đổi thư viện.
  - App chưa release nên không cần tương thích ngược.
  - Mẫu tên file và lựa chọn riêng tư mặc định lưu trong Settings.
  - Việc mua lưu qua StoreKit, không lưu trong DB.

## Constraints — ràng buộc

- **Dữ liệu ở lại trên máy.** Không server của ShotDex, không tài khoản, không analytics.
  - Tìm nhịp nhạc, nhận xét thống kê và so khung burst đều chạy trên máy.
  - StoreKit chỉ nói chuyện với App Store.
- **Không thêm dependency** ngoài GRDB, vì StoreKit 2, AVFoundation và Vision đều là framework hệ thống. Ngoại lệ
  đã có sẵn: swift-collections của FS-15.
- **Không bao giờ âm thầm xuất ra bản xem trước** thay cho ảnh gốc (bài học Optimize Storage trong memory).
- **Không tự ghi đè file gốc trên SSD** (cùng luật với network-folder-edit).
- **Nhánh iOS 26 và bản dưới 26 đều phải chạy.**
  - Màn hình ngoài và các API của iOS 27 (nếu dùng) chỉ bật theo `#available`.
  - Deployment target vẫn là iOS 17.
- **Share extension.** Không vượt trần bộ nhớ khoảng 120MB khi bỏ metadata hay đóng watermark trong extension.
- **Mua đứt là thật sự mua đứt.**
  - Không subscription, không khoá chức năng xuất, không watermark cho người chưa mua.
  - Phần giới hạn của bản dùng thử phải nói rõ trước khi người dùng bấm vào.
- **Không làm màn Import** (người dùng 2026-09-30). FS-10 giữ nguyên. SSD ngoài là nơi *làm việc tại chỗ*,
  không phải đường nhập ảnh vào Photos.
- **Caption, keyword và sao trên Photos chỉ có từ iOS 27.** Dùng qua `#available(iOS 27)`; bản dưới 27 không được
  hỏng.

## Open questions — câu hỏi còn treo

### Đã chốt (người dùng 2026-09-30)

1. **Sao 0–5.**
   - Trên iOS 27 dùng `PHAsset.rating` của Photos.
   - Trên iOS 17–26 lưu trong bảng riêng của ShotDex. Lên iOS 27 thì chuyển sang Photos một lần rồi dùng API.
2. **Pick/reject.**
   - Luôn lưu trong bảng riêng, độc lập với favorite của Photos.
   - Lọc được theo Rejected, có lệnh "Delete Rejected" (hỏi xác nhận) để dọn sau buổi chụp.
3. **Mua đứt.**
   - Dùng đầy đủ 14 ngày.
   - Sau đó vẫn duyệt thư viện, lọc và xem thống kê. Editor, xuất và Video Studio cần mua.
   - Không watermark, không subscription. Giá chốt ở `/spec` (khoảng $30–60).
4. **File trên SSD ngoài.** Lưu giống network-folder-edit: hỏi nơi lưu lúc xuất, không bao giờ ghi đè file gốc.
   Một cách làm cho mọi nguồn file (mạng, cloud, SSD).
5. **Thứ tự làm, 3 đợt.**
   - Đợt 1: 1 (iCloud), 2 (RAW chưa hỗ trợ), 3 (riêng tư khi chia sẻ), 5 (nhận xét thống kê), 12 (burst).
   - Đợt 2: 9 (sao và cờ), 14 (caption và keyword), 4 (xuất ra Files), 6 (watermark), 8 (look cho video).
   - Đợt 3: 7 (nhịp nhạc), 10 (SSD), 11 (màn hình ngoài), 13 (mua đứt).
6. **Màn hình ngoài** làm cho iPad và iPhone cắm cáp (gồm Duo): cùng một scene external display cho mọi máy.

### Để lại cho `/spec`, không cần người dùng trả lời

- **Rút SSD ra giữa chừng**, lúc đang sửa, đang dựng video hay đang xuất. Project Video Studio đang trỏ tới file
  trên SSD thì sao? Cần thử trên máy thật có SSD.
- **Nhận xét thống kê.** Câu nào đủ dữ liệu mới hiện (ngưỡng số ảnh), và viết sao để không thành lời khuyên mua
  hàng.
- **Tìm nhịp nhạc.** Dùng thuật toán nào có sẵn trong Accelerate/AVFoundation, và độ trễ chấp nhận được.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
