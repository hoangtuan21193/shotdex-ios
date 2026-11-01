# Intent: Giữ ảnh và video trên máy để xem offline, mở từ Collections

| Trường | Giá trị |
|---|---|
| Tác giả | Hoang Tuan (lời người dùng), Claude soạn |
| Ngày | 2026-10-19 |
| Trạng thái | accepted — người dùng 2026-10-20 (đồng ý cả 9 phương án mặc định) |
| Tiến độ | **gần xong** (2026-10-20) — code thẳng theo mockup (người dùng chọn bỏ /spec, /plan): tab Utilities, sheet Keep, màn On This iPhone, bộ tải PhotoKit/server/thư mục, viewer mở file giữ; test `KeptStoreTests` + `KeptFileStoreTests` xanh; chụp iOS 26.5 + 18.6. iPad + Duo (2026-10-21): tên theo máy (On This iPad), Utilities 4 nhóm thành 4 cột ở regular width, board `IP_Utilities`/`IP_OnThisIPad`/`IP_KeepOnIPad`, `DI_*`/`DC_*` Utilities/OnThisIPhone/KeepOnIPhone, rail Duo có tab Utilities. Chưa thử: giữ cả album PhotoKit, video, mở khi tắt mạng thật, Mac (sau FS-18). Chưa commit |
| Nguồn | phản hồi người dùng 2026-10-19 |
| Spec sinh ra từ đây | (điền khi sang Design) |

## Problem — vấn đề

Người dùng hỏi: "hiện tại đã có chức năng lưu offline video và ảnh chưa? collection phải có chỗ để truy cập ảnh và video
offline". Câu trả lời hôm nay là **chưa**. Người dùng không chọn được ảnh, video hay album nào để chắc chắn còn xem được
khi không có mạng (trên máy bay, ở nơi không có sóng, khi rời mạng nhà có NAS).

Những gì đang có thì không làm được việc này:

- **Ảnh trong thư viện Photos có bản gốc trên iCloud.** Máy của người dùng bật Optimize Storage (memory
  `grid-thumbnail-optimize-storage`). Hệ thống chỉ giữ bản xem nhỏ. Không có mạng thì mở ảnh chỉ thấy bản mờ, còn video
  thì không phát được. ShotDex chỉ tải bản gốc tạm thời để Share/Export rồi bỏ (`ShotDex/App/OriginalDownloadModel.swift:11`,
  `ShotDex/App/AssetActionsCoordinator.swift:254-267`). PhotoKit không có lệnh nào để "ghim" một ảnh ở lại trên máy.
- **Ảnh và video trên server/NAS** (FS-15, FS-17, FS-19) chỉ xem được khi tới được server. Cách duy nhất để có bản trên
  máy là **Save to Photos** (`ShotDex/Features/ServerImport/ServerDownloadModel.swift:96`). Cách đó chép file vào thư viện
  Photos: lên iCloud, trộn vào thư viện ảnh và sinh ảnh trùng. Bảng `server_downloads` chỉ ghi lịch sử, không phải danh sách
  giữ offline (`ShotDex/Data/Database/AppDatabase.swift:490-502`).
- **File chỉ có trên cloud** (iCloud Drive, Dropbox… qua Files) hiện thành ô giữ chỗ. Mỗi lần chỉ tải được một file khi
  mở (`ShotDex/Features/Sources/CloudDownloadPanel.swift:160`). FS-19.01b §4 có lệnh "Download 412 Files…" nhưng chưa
  làm, và nó cũng không nói file tải về có được giữ lại không.
- **Cache preview** (FS-19.01b §5) chỉ giữ bản 2400px có trần và bị xoá dần. Nó không phải lời hứa "cái này xem được
  offline", và không có phần nào cho video.
- **Collections không có chỗ nào để vào** (`ShotDex/Features/Albums/AlbumsScreen.swift:799-804` chỉ có Cloud và Network).
  Library không lọc được theo "có trên máy" (`ShotDex/Core/Models/FilterCriteria.swift` không có trường Source hay Kept).

Lịch sử: ý "Keep on iPhone" cho ảnh và album (Originals hay Viewing Copies 2732 px, quyết định D7), cùng bộ lọc Source/Kept
(D8), từng nằm trong `docs/_intents/2026-10-15-media-hub.md:19-20, 140-143`. Intent đó ghi phần ảnh "sẽ có intent/spec
riêng" khi gỡ hub ngày 16/10. File này là intent riêng đó. README FS-01 của Movik cũng trỏ về một intent `offline-photos`
chưa từng được viết.

Ai bị ảnh hưởng: người dùng chính của app, khi mang máy theo mà không có mạng; người giữ thư viện trên NAS. Mức độ: hôm
nay trong app không có cách nào làm việc này.

## Proposed outcome — kết quả mong muốn

1. **Một hành động "giữ trên máy"** cho một ảnh, một video, một lựa chọn nhiều mục và một album. Hành động này dùng được
   cho mọi nguồn: thư viện Photos (kể cả bản gốc đang ở iCloud), server/NAS và thư mục cloud. Mục đã giữ thì mở được
   đầy đủ khi máy ở chế độ máy bay: ảnh ở độ nét đầy màn, video phát hết.
2. **Collections có mục "Offline"** (tên chốt ở spec) liệt kê mọi thứ đang giữ, đi theo nguồn hoặc album, với dung lượng
   đã dùng và còn trống. Library lọc được theo "có trên máy" (D8 cũ).
3. **Tải có tiến độ, tải dở thì tải tiếp**, không ăn hết bộ nhớ máy. Hết chỗ thì không bắt đầu và nói rõ lý do.
4. **Bản giữ không trộn vào thư viện Photos**: không lên iCloud Photos, không sinh ảnh trùng, không vào bản sao lưu
   iCloud của máy. Bỏ giữ thì lấy lại chỗ ngay. Bản giữ là của người dùng: app không tự xoá, kể cả khi nguồn mất kết nối.
5. Album đã giữ thì **ảnh mới thêm vào album cũng được giữ** (nếu chốt như vậy, xem câu 4).

## Affected users and systems — phạm vi ảnh hưởng

- **Màn hình:** Collections (mục mới), Library (bộ lọc, glyph "có trên máy" trên ô), viewer (nút giữ, trạng thái tải),
  menu chọn nhiều mục (SelectionOverlay), Album detail, server browser/On Server, Settings (dung lượng, xoá hết).
- **Thiết bị:** iPhone, iPad, Duo trong và ngoài, Mac (FS-18 đang làm; trên Mac "offline" chủ yếu là ổ rời và server).
  Design canvas phải có board cho mục mới trên cả 4 thiết bị, sáng và tối.
- **Tầng code:** Data (bảng giữ offline riêng, kho file trong Application Support, bộ chạy tải), Data/Sources (PhotoKit
  tải bản gốc, `RemoteFileClient` cho SMB/SFTP/WebDAV), Features (Albums, Library, Viewer, Selection), Domain (query bộ
  lọc). Extension không đụng (widget và share chỉ đọc nếu cần).
- **Dữ liệu đã lưu:** thêm bảng mới. Danh sách giữ là dữ liệu người dùng chọn, nên **không** để trong `photo_metadata`
  (indexer ghi đè cả hàng). App chưa phát hành nên không cần lo tương thích ngược.
- **Tham khảo Movik** (`/Users/hoangtuan/Project/movik-ios`). Movik đã làm phần tải phim offline, đang chạy và có test:
  - Trạng thái stream → queued → downloading → onDevice/missing, chỉ ghi ở một chỗ (`Movik/Core/Models/Movie.swift:71-82`,
    `Movik/Data/Database/MovieStore.swift:300-312`).
  - Bộ chạy tải mỗi lần một mục, ghi tiến độ 2 giây một lần, chặn khi hết chỗ (dung lượng cần + 1 GB dư)
    (`Movik/Data/Movies/MovieDownloadRunner.swift:31-32, 215-274, 395-416`).
  - Kho file `Application Support/Movies/<id>/` với thư mục tạm `.incoming/<id>.part`, `isExcludedFromBackup`. Lúc mở
    app có lượt dọn: chỉ đánh `missing`, không bao giờ xoá hàng (`Movik/Data/Movies/MovieFileStore.swift:3-95`).
  - Tải tiếp bằng `RemoteFileClient.resumeDownload` cho SMB/SFTP/WebDAV, mỗi khúc 4 MB
    (`Movik/Domain/ServerUpload/RemoteFileClient.swift:200-240`). Đường background `URLSession` dùng cho WebDAV
    (`Movik/Data/Movies/MovieBackgroundTransfer.swift`). Trên iOS 26 có continued task cho đường foreground
    (`Movik/App/MovieBackgroundService.swift:47-88`).
  - Nguồn mất kết nối thì bản trên máy vẫn ở lại (`MovieStore.swift:62-80`). Không có trần, và app không tự xoá (NF-02 của
    Movik).
  - **Movik không có:** tải bản gốc từ PhotoKit (không đi qua URLSession, nên không chạy nền được), giữ theo album, và màn
    danh sách Offline riêng (Movik chỉ có chip lọc "On This iPhone").

## Constraints — ràng buộc

- Không thêm dependency. Dùng lại lớp `RemoteFileClient` sẵn có của ShotDex (cùng gốc với Movik).
- Không chép file vào thư viện Photos để "giữ". Không âm thầm sửa hay xoá `PHAsset`.
- Không tự xoá bản giữ để lấy chỗ (luật Movik NF-02). Cache preview của FS-19.01b §5 vẫn tự quản theo trần riêng. Hai thứ
  không được lẫn vào nhau.
- Không tải ngầm khi người dùng chưa bấm (FS-19.01b §4: lượt index không bao giờ tải file).
- Không được làm đầy máy: kiểm dung lượng trước khi tải và giữ lại một khoảng dư.
- Giữ cả hai nhánh iOS 26 và trước 26 (chạy nền, chrome).
- Quét 55k ảnh không được chậm đi: glyph "có trên máy" không được truy vấn theo từng ô.
- Không dùng ảnh có mặt người khi test (memory `no-face-photos-in-tests`).

## Đã chốt 2026-10-20

- Người dùng đồng ý cả 9 phương án mặc định bên dưới.
- Màn tên **On This iPhone**, không dùng "Offline" (chữ đó đã là badge của nguồn mất kết nối).
- **Tab Utilities mới** nằm bên phải Collections: cả nhóm Utilities chuyển từ Collections sang tab này, và On This iPhone
  nằm trong đó. Collections còn On This Day, albums, Media Types và Sources. Tab bar: Library · Collections · Utilities · Search.
- Người dùng chọn code thẳng theo mockup (bỏ `/spec` và `/plan`, trái với PROCESS.md §4, do người dùng quyết định).

## Open questions — câu hỏi còn treo (đã trả lời: dùng mặc định)

Mỗi câu có phương án mặc định Claude đề xuất. Người dùng trả lời.

1. **Ảnh và video Photos: giữ bằng cách nào?** PhotoKit không ghim được bản gốc. Các cách:
   (a) tải bản gốc về rồi chép vào kho riêng của app. Chiếm chỗ gấp đôi nếu sau này Photos cũng tải về.
   (b) chỉ hướng dẫn người dùng bật "Download and Keep Originals" của hệ thống. Cách này áp cho cả thư viện, không chọn
   được từng mục.
   (c) như (a), nhưng chỉ chép khi bản gốc đang không có trên máy.
   **Mặc định đề xuất: (c).**
2. **Giữ bản gốc hay bản xem?** (D7 cũ) Ảnh: Original, hay Viewing Copy 2732 px nhẹ hơn khoảng 10 lần. Video: bản gốc,
   hay bản nén HEVC 1080p. **Mặc định: hỏi một lần khi giữ, mặc định chọn Viewing Copy; RAW luôn giữ bản xem.** Có nên
   cho đổi trong Settings?
3. **Gồm những nguồn nào trong v1?** Photos/iCloud, server/NAS (SMB, SFTP, WebDAV), thư mục cloud qua Files.
   **Mặc định: cả ba**, vì Collections cần một chỗ chung.
4. **Album đã giữ có tự giữ ảnh mới không?** **Mặc định: có**, kèm dòng "Keeps new photos added to this album". Smart
   Album cũng vậy?
5. **Mục trong Collections trông ra sao?** Một hàng "Offline" ở Utilities, mở ra lưới theo nguồn/album, có dung lượng và
   "Remove All". Hay là nhóm riêng? Cần mockup trên canvas iPhone trước (memory `design-questions-need-visuals`).
6. **Có trần dung lượng không?** Movik không có trần. **Mặc định: không có trần, chỉ hiện dung lượng và chặn khi máy còn
   dưới mức dư.**
7. **Mac có phần này không?** Trên Mac, ảnh thường đã có sẵn trên ổ. **Mặc định: Mac chỉ có phần cho server/ổ rời, làm
   sau FS-18.** Người dùng chốt lại 2026-10-21: để sau FS-18 — chưa vẽ board Mac, chưa code.
8. **Tải nền khi app đóng:** chấp nhận PhotoKit chỉ tải khi app mở, cộng continued task trên iOS 26 như Movik? **Mặc định:
   có.**
9. **Gom hay tách code với Movik?** Chép mẫu code (kho file, bộ chạy, trạng thái) sang ShotDex, hay tách thành package
   dùng chung? **Mặc định: chép mẫu, chưa tách package** (luật: không thêm dependency, và hai app đang thay đổi nhanh).

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
