# FS-18.04 — Các màn còn lại

`FS-18.04` · board `MAC_Collections` · `MAC_AlbumDetail` · `MAC_Statistics` · `MAC_Settings*` · `MAC_CameraDatabase` ·
`MAC_Collage` · `MAC_Compress` · `MAC_Merge` · `MAC_VideoStudio*` · `MAC_Support` · cập nhật 2026-10-04

**Một câu:** mỗi màn của iOS có một chỗ trên Mac — điểm đến ở sidebar, công cụ tầng D trong cửa sổ, Settings và
Support là sheet trên cửa sổ Library (2026-11-07: ít cửa sổ); Settings là cửa sổ riêng của hệ thống.

## 1. Albums và các điểm đến (D19)

- Sidebar › Collections › Albums mở màn **Albums**: toolbar "Albums" + "38 albums · 7 smart albums", **Sort By ▾**,
  một nút **+** (New Album ⌘N · New Smart Album… ⌥⌘N · Customize).
- Thứ tự theo [FS-06.01](../FS-06-collections/01-tabs-tokens-and-album-management.md) §2: hàng hero (On This Day +
  Recently Viewed / Recently Shared) → Pinned → People and Pets → Smart Albums → My Albums.
- Cover 135, **tên nằm trên đáy cover, không số dưới cover, không thư mục album** (D19). Số chỉ ở sidebar.
- Album: đầu trang cover 104 · tên · "August 9 – 22, 2026 · Reykjavík, Vík, Höfn, Akureyri" ·
  "412 photos · 18 videos · 61.4 GB"; lưới cùng engine với Library (8 cột ở 1440), Grid/List như Library.
- Smart album: sheet **640×560**, Match all/any, nhóm điều kiện lồng, thân cuộn
  ([FS-06.08](../FS-06-collections/08-smart-albums.md)); điều kiện Source thêm theo FS-19.
- On This Day: lưới theo năm (§1.1). (Places với inspector cụm và nút Show Trip đã bỏ cùng Places/Trips, 2026-10-24.)
- Duplicates: segmented mức khớp **Exact · Similar · Series · Bursts**, danh sách nhóm 340 bên trái, hai bản cạnh
  nhau, Rescan, **Merge N Groups…**; chỉ gom trong một nguồn (D7, FS-19,
  [FS-06.06](../FS-06-collections/06-duplicates.md)).
- Collages (`MAC_Creations`): thẻ theo tháng; chuột phải Open in Collage · Show in Library · Export… · Share… ·
  Remove from Collages…. Video Projects: thẻ project, New Video Project, xác nhận xoá bằng alert.

### 1.0 Màn Albums (board `MAC_Collections`) — trạng thái 2026-11-07

- Đã có: toolbar ◀ ▶ · "Albums" + "6 albums · 2 smart albums" · **Custom Order ▾** (Custom Order = thứ tự trong
  Photos · Name · Most Photos — PhotoKit không có ngày tạo album; nhớ qua lần mở, chỉ áp My Albums) · **Search Albums**
  (lọc theo tên ở mọi mục, cả People and Pets; số ở đầu mục theo kết quả; không khớp: "No Results") · nút **+** amber
  48×36 (New Album… → hộp đặt tên, tạo trong Photos — album rỗng vẫn hiện, bìa "No photos"; không đủ quyền: mờ kèm gợi ý
  System Settings; New Smart Album… → sheet).
- Thẻ hero **On This Day**: ảnh mới nhất của ngày, "On This Day" · ngày · "26 photos from 3 years"; bấm → On This Day.
  Không có ảnh: nền xám + "Nothing from earlier years today". Bên phải **Recently Viewed** / **Recently Shared** (4 ảnh
  nhỏ, từ `RecentActivityStore`; Mac ghi lại mỗi lần Share), chỉ hiện khi có.
- Mục: **Pinned** (`CollectionPinStore`, chung khoá với iOS; chuột phải › Pin / Unpin; thẻ đã ghim có dấu ghim) và
  **People and Pets** (ảnh có mặt người / chó mèo theo lượt quét, chỉ hiện khi có) chung một hàng · **Smart Albums N**
  (dấu bánh răng; smart album không ảnh: "No photos") · **My Albums N** (album thường của Photos, cả album rỗng). Thẻ 135
  vuông, góc 12, tên 13 medium dưới.
- Chuột phải thẻ: Open · Pin/Unpin · (album Photos) **Rename Album…** (hộp tên) · **Delete Album…** (hỏi lại: "The album
  goes from Photos on all your devices; its photos stay in the library.") · (smart album) **Edit Smart Album…**. Thư viện
  demo không bao giờ gọi Photos: đổi tên / xoá báo "The demo library's albums can't be changed.".
- Bấm thẻ: album của Photos mở như một chỗ của Library (lưới, chọn, menu như Library; tiêu đề là tên album; hàng Albums ở
  sidebar vẫn sáng; **Back ⌘[** về Albums), smart album → màn smart album, People/Pets → lưới ảnh có mặt người / chó mèo.
- **Màn smart album** (board `MAC_SmartAlbum`, 2026-11-07, `MacSmartAlbumHeader`): là Library trên luật của album
  (`LibraryPlace.rules`) nên có đủ toolbar của Library — ◀ ▶ · Grid | List · Filter and Sort · Share · Show Inspector ·
  **Search Album** — viewer (Return / double-click), menu chuột phải, chọn, xoá qua cổng hỏi server trước (FS-19.07 §9).
  Tiêu đề toolbar là tên album, dòng phụ "Smart Album" (đang chọn thì "N selected · size"). Dưới toolbar, header: mỗi
  điều kiện một chip (biểu tượng + chữ, cao 24, nền fill) — **bấm chip mở Edit Smart Album…** — rồi "40 photos"; bên phải
  dòng tiến độ On Server ("Checking · 40 of 226", câu mismatch xuống dòng) và dòng kiểm originals (vòng tiến độ). Ô ảnh
  có dấu "on server". Không có header ngày (một dải ảnh như album). Header ẩn khi viewer mở. Không ảnh nào khớp:
  "No Photos Match". Lượt kiểm On Server / originals xong một đợt thì lưới đọc lại (originals tối đa 3 s một lần).
  Recently Viewed (ảnh đã Quick Look) / Recently Shared (ảnh đã Share) chỉ là ảnh, chưa mở được (chờ Viewer).
- VoiceOver: mỗi thẻ là một nút "Kyoto Autumn, 8 photos, pinned" / "…, smart album"; Pin/Unpin là action.
- Hiệu năng: album đọc lại khi album/ảnh đổi (gom 1 s), phần còn lại (On This Day, People/Pets, bìa smart album) đọc riêng;
  đếm + bìa mỗi album là hai fetch nhẹ (bìa `fetchLimit` 1); bìa ảnh lấy bản trên máy, không chờ mạng; danh sách thẻ dựng
  một lần mỗi lần vẽ, sắp xếp lưu sẵn.
- Chưa có: danh sách album con dưới hàng Albums ở sidebar và kéo ảnh vào album (board vẽ), album dùng chung (Shared),
  thư mục album của Photos, Customize thứ tự mục.

### 1.0b Một album (board `MAC_AlbumDetail`)

- Mở từ Albums hoặc từ danh sách dưới hàng **Albums** ở sidebar (chevron Show/Hide Albums cạnh số, nhớ qua lần mở; mỗi album
  một hàng thụt vào, số ảnh bên phải, tên dài có tooltip; tối đa 12 hàng rồi "Show All Albums…" mở Albums; album đang mở sáng
  hàng của nó; danh sách chỉ đọc khi đang hiện, bằng số ước tính của Photos).
- Đầu trang thay tiêu đề toolbar: bìa 104 góc 12 (ảnh mới nhất) · tên 26 bold · "August 9 – 22, 2026 · Reykjavík, Vík, Höfn,
  Akureyri" (khoảng ngày + tối đa 4 nơi chụp nhiều nhất, khi index biết) · "412 photos · 18 videos · 61.4 GB · 2 selected".
  Đọc ngoài luồng chính khi album đổi.
- Lưới phẳng 8 cột ở 1440 (không chia ngày), Grid/List, Filter and Sort, Share, Inspector, chọn, chuột phải, phím như
  Library; ô tìm "Search Album" tìm trong album (không có thanh phạm vi nguồn); khi tìm, dòng số là "3 of 412 photos" và bìa
  giữ nguyên. Chuột phải có **Remove from Album** (bỏ khỏi album, ảnh còn trong thư viện) và Add to Album không liệt kê
  chính album đang mở. Album rỗng: "Empty Album — add photos with Add to Album". **Back ⌘[** về chỗ đã mở album (Albums
  hoặc chỗ trước ở sidebar). Album bị xoá trong Photos khi đang mở → về Albums.
- Chưa có: kéo ảnh vào một album ở sidebar (board vẽ), toolbar khi bỏ tiêu đề nằm giữa thay vì sát phải (macOS 26+
  `ToolbarSpacer`), sắp xếp riêng của album (Album Order), đổi bìa, Undo cho Remove from Album, mở album 20k ảnh còn chờ
  PhotoKit liệt kê id (~1 s, ngoài luồng chính); hàng sidebar cao 32 thay vì 28 của board (cả sidebar, chờ quyết).

### 1.1 On This Day (board `MAC_OnThisDay`, hành vi theo [FS-06.07](../FS-06-collections/07-on-this-day.md))

- Sidebar › Collections › On This Day, Go › On This Day. Là một **chỗ của Library** (`LibraryPlace.onThisDay`): ảnh
  chụp đúng tháng/ngày này ở các năm trước, đọc từ index bằng một khoảng thời gian mỗi năm (`OnThisDayWindows`,
  giờ máy, 29/2 chỉ năm nhuận) trên pool GRDB — không quét PhotoKit, không chặn click. Mọi nguồn (Photos, thư mục,
  server) đều vào.
- Toolbar: ◀ ▶ · "On This Day" + "October 4 · 26 photos from 3 years" · **Choose Date** (popover lịch tháng +
  Today, Today mờ khi đang là hôm nay; chỉ tháng/ngày được so) · **Play Slideshow** (mờ cho tới khi có
  Viewer) · **Share ▾** (dịch vụ chia sẻ cho ảnh đang chọn; mờ khi chưa chọn) · Show/Hide
  Inspector. Không có Grid/List và Filter and Sort (board không vẽ); ⇧⌘L ở đây kêu beep, không mở gì.
- Lưới: mỗi năm một đoạn, **năm cũ ở trên** (board; FS-06.07 §4 "cùng chiều Library"), đầu đoạn "2021" (15 semibold, như đầu ngày của Library)
  + "5 years ago · Hanoi, Vietnam" (nơi chụp nhiều nhất năm đó, khi index đã biết) + số ảnh bên phải. Chọn, chuột
  phải, phím đánh dấu, inspector như Library.
- Ngày không có ảnh: "Nothing from November 8" + "No photo was taken on this day in an earlier year." + nút
  **Choose Date…**.
- Vào On This Day luôn mở **hôm nay**, và bỏ filter của Library (chỗ này không có nút Filter nên filter không được
  lọc ngầm); một search đang chạy thì giữ. Tiêu đề phụ luôn mở đầu bằng ngày; khi search thu hẹp: "November 7 ·
  12 photos". Năm đếm ngoài luồng chính.
- Lịch của Choose Date là lịch **2024** (năm nhuận) để chọn được 29/2; năm không có nghĩa. Go › **Choose Date…**
  (không phím tắt — ⌥⌘D là của Dock) là đường bàn phím. Ngày chọn được tô màu hệ thống (NSDatePicker không theo
  `tint`) — ngoại lệ control hệ thống, không phải amber.
- "5 years ago" chỉ hiện khi ngày là hôm nay; ngày khác chỉ ghi nơi chụp.
- Mở ra (đổi ngày, vào chỗ) thì cuộn tới năm mới nhất ở đáy; xoá ảnh hay index thêm ảnh thì giữ nguyên chỗ cuộn.
- Thứ tự luôn theo ngày chụp, không theo Sort By của Library; năm tính theo lịch Gregorian (lịch Nhật/Phật lịch
  vẫn đúng ngày).
- Chưa có: lời nhắc hằng ngày trên Mac (Settings › On This Day Reminder), mở thẳng ngày từ thông báo, Slideshow.

### 1.2 Hidden (board `MAC_Hidden`, hành vi theo [FS-19.04 §3](../FS-19-photo-sources/04-deleting-and-duplicates.md))

- Sidebar › Collections › **Hidden** (sau smart album), số bên phải; hàng chỉ hiện khi có ≥ 1 ảnh ShotDex đã ẩn (hoặc
  khi đang mở nó). Không phải album Hidden của Photos.
- Toolbar: "6 Hidden Photos" + "6 photos · ‹nguồn›" (đang chọn: "2 selected · 48 MB") · Share ▾ (mờ khi chưa chọn,
  "Select photos to share") · Show Inspector · nút amber **Unhide** / "Unhide 2 Photos" (⌘L, mờ khi chưa chọn).
  Image › Unhide N Photos ⌘L thay Image › Hide… khi mục này ở trước.
- Ghi chú dưới toolbar: "Photos hidden in ShotDex" + họ rời All Photos, search, album, smart album, Statistics tới khi
  unhide; file không bị đổi; mọi ảnh ở một server thì thêm "These N are still on “NAS Home”, which ShotDex can only
  hide, never delete from."; dòng "The Hidden album in Photos is separate…".
- Lưới chung, theo ngày; chọn, chuột phải, phím đánh dấu, inspector như Library. Unhide bỏ ẩn **mọi** bản sao, ảnh về
  lưới; hết ảnh: "No Hidden Photos"; rời mục thì hàng sidebar biến mất.
- **Hide** trên Mac: Image › **Hide…** ⌘L và chuột phải › **Hide…** trên lựa chọn → hộp "Hide N Photos?" với các lệnh
  của `HideCommandPlan` (Hide, hoặc Hide in Photos · Hide in ShotDex Only khi có ảnh vừa ở Photos vừa ở nơi khác) +
  Cancel (Hide in ShotDex Only đứng đầu và là mặc định — không đụng Photos; khi đụng album Hidden của Photos thì hộp
  nói vậy và nói phải bỏ ẩn trong app Photos); chạy `HideService` ngoài luồng chính, theo thứ tự, rồi lưới, mục Hidden
  và số đếm đọc lại (cả khi chạy dở). Đọc kế hoạch lỗi thì báo lỗi, không đoán. **Undo/Redo** (⌘Z) cho phần ShotDex
  ẩn/bỏ ẩn; phần trong Photos thì không. Menu chuột phải trong mục Hidden không có Hide…. Đọc mục lỗi: "Couldn’t Load
  Hidden Photos" + Try Again, không bao giờ "No Hidden Photos". Thư viện demo không bao giờ gọi Photos.
- Chưa có: Grid/List và Filter and Sort trên mục này (board vẽ; lưới là đủ cho vài ảnh ẩn); tên nơi chụp ở đầu ngày.

### 1.3 Xoá ảnh nhiều bản sao (board `MAC_DeleteCopies`, hành vi theo [FS-19.04 §1–§2](../FS-19-photo-sources/04-deleting-and-duplicates.md))

- Move to Trash (⌘⌫, chuột phải, Image) ở All Photos / album khi **≥ 1 ảnh có ≥ 2 bản sao** → sheet 400 rộng thay hộp
  thường: icon app, tiêu đề **đếm bản sao** khi ảnh nào cũng còn bản ("Remove 1 copy?"), đếm ảnh khi có ảnh mất hết bản
  ("Move 1 photo?", "Delete 1 photo?", "Hide 1 photo?"); lời "DSC04512.ARW has 3 copies. Choose the ones to remove; the
  photo stays in ShotDex with the copies you keep." (nhiều ảnh: một câu chung).
- Danh sách: một ảnh → một hàng mỗi bản sao ("T7 RAW Archive › RAW/2026-09-27", "Photos Library", "NAS Home (hide)") với
  "Shown in ShotDex · goes to …" (bản ShotDex hiện và mở) / "Also stored here · would go to …" / "… · can only be hidden in
  ShotDex" (không gọi là "Backup": bản RAW gốc có thể nằm ở ổ); nhiều ảnh → một hàng mỗi nguồn ("2 photos · the copies
  shown in ShotDex · …"), ô ba trạng thái. Mặc định chỉ bật bản ShotDex hiện (đầu thứ tự FS-19.02 §3); bấm cả hàng
  cũng bật/tắt; VoiceOver đọc mỗi hàng là một nút: tên, on/off/mixed và nơi đến.
- Dưới: lời của `MixedDeletionPlan` theo phần đã chọn + "Files go with their paired JPEG and .xmp sidecar." khi có file vào
  Thùng rác + "N copies stay." + "No copy left: the photo leaves ShotDex." khi ảnh mất hết bản + "Photos asks to confirm its
  part." khi có bản Photos + "You'll be asked once more…" khi có nơi không Thùng rác; "ShotDex never edits file
  contents.". Nút Cancel (Esc) · Move/Delete/Hide chữ đỏ (`redText`), không bao giờ là nút mặc định; không chọn gì →
  "Choose Copies to Remove", nút "Remove" mờ với gợi ý "Tick at least one copy".
- Xong: một dòng ở chân cửa sổ (`MacToast`) "Moved 1 file to the Trash. Hid 1 photo on NAS Home." vài giây; chạy dở
  (server giữ lại ảnh, file không chuyển được) thì hộp lỗi kèm phần đã làm. Một lần xoá một lúc mỗi cửa sổ.
- Xác nhận ở sheet là bước hỏi của ShotDex: chạy luôn, chỉ còn hộp đỏ khi có nơi không Thùng rác và hộp của hệ thống cho
  phần Photos. Ảnh không ảnh nào ≥ 2 bản sao → hộp thường như cũ. Trên Mac mọi hộp gọi Thùng rác là "the Trash"
  (trước đây hộp Mac dùng chữ của iPad "Recently Deleted in Files" — sửa cùng lượt).
- Demo `-ShotDexSection deleteCopies`: ảnh RAW có thêm bản trên ổ "T7 RAW Archive" và "NAS Home"; dịch vụ xoá của demo
  không đụng file thật hay Photos.
- Chưa có: sheet này trong smart album và Duplicates (vẫn hộp thường, cùng một lệnh nên hai hành vi); glyph ổ đĩa cho bản
  sao trên ổ (đang là thư mục); chọn bản sao theo từng ảnh khi nhiều ảnh (hiện theo nguồn).

### 1.4 Soạn smart album (board `MAC_SmartAlbumEditor`, hành vi theo [FS-06.08](../FS-06-collections/08-smart-albums.md) §2–§4, §2b)

- Sheet 640×560 nền `sheet`: tiêu đề 15 semibold ("New Smart Album" / "Edit Smart Album" / "Advanced Filter"), dưới là
  dòng đếm sống "Matches 64 photos" (đếm sau 300 ms, ngoài luồng chính; "· Photos not checked yet aren't counted" khi
  có điều kiện Original; "· 1 incomplete condition ignored" khi có dòng dở; "Add conditions to choose the photos." khi
  chưa có gì).
- Hàng Name (300), Media Type All/Photo/Video (segmented amber; dưới Match any ghi "Counts as one condition under Match
  any."), "Match [all ▾] of the following conditions:".
- Khung điều kiện 590×314 r10 nền `card`, cuộn: mỗi điều kiện **một dòng** 32 — trường 136, phép so 128, giá trị
  (ô chữ có gợi ý cho hãng/thân máy/ống kính, popup cho lựa chọn, số + "s"/"mm" + Actual/FF Equiv., ngày dạng ô,
  tháng/năm, "N days" + stepper, 5 sao), **−** xoá dòng, **+** thêm dòng ngay sau. Also on Server: Yes/No ở chỗ phép
  so, server ở chỗ giá trị, dòng Folder ("All Folders"/thư mục, Choose… duyệt server — đọc server + mật khẩu ngoài luồng
  chính). Favorite: "is / is not".
- **⌥-click +** (dòng ngoài cùng) thêm **nhóm**: dòng "[Any ▾] of the following are true" − (xoá cả nhóm) + (thêm điều
  kiện vào nhóm), các dòng con thụt 20; glyph + đổi thành … khi giữ ⌥, tooltip và VoiceOver action "Add Group" nói
  vậy; nhóm mới được cuộn tới. Luôn còn ít nhất một dòng ngoài cùng (để còn + và ⌥+).
- **?** mở popover giải thích all/any và nhóm. **Cancel** (Esc) đóng không lưu. **Create** / **Save** / **Filter**
  (Return, `accentFill`) tắt khi chưa có tên, tên trùng (báo đỏ), chưa có điều kiện hợp lệ, hoặc tên các album chưa
  đọc xong; ghi album ngoài luồng chính, lỗi ghi hiện "Couldn't save: …" và sheet ở lại.
- Demo `-ShotDexSection smartAlbumEditor`: Albums + sheet với ISO range, Shutter, Date in the last, Rating và nhóm Any
  của hai ống kính.
- Chưa có (board vẽ): phép "is not" / "is in year" cho ngày, đơn vị weeks/months/years cho "is in the last" (model chỉ
  có ngày); sheet hiện giữa cửa sổ (hệ thống) chứ không sát dưới toolbar; nút thêm nhóm chỉ qua ⌥ (không có nút riêng —
  board không vẽ); dựng nhóm trên iOS.

## 2. Statistics (D18)

- Sidebar › Utilities › Statistics, Go ⌥⌘6. Tầng A. Toolbar: ◀ ▶ · "Statistics" + "54,027 photos · 1,204 videos" ·
  dòng "Each photo counted once across sources" · popup **Source** · nút **+** (Add Chart · Reorder Charts).
- **Không có popup ngày chung**: mỗi thẻ có khoảng riêng (All Time · This Year · Last 12 Months…), như
  [FS-07.01](../FS-07-statistics/01-dashboard.md) §1.
- Từ trên xuống: Insights ([FS-07.02](../FS-07-statistics/02-insights.md)) · hàng số (Total Photos & Videos · Slow Shutter
  · Median ISO · Average Equivalent Focal Length · Median Aperture) · thẻ biểu đồ **4 cột** ở 1440, thẻ rộng 282.
- Hai biểu đồ thêm: **Time of Day** (24 cột 0:00–23:59, theo giờ chụp như bộ lọc khung giờ
  [FS-01.03b](../FS-01-library/03b-time-of-day-and-acceptance.md)) và **Photos by Weekday** (Mon…Sun). Chúng dựng trên
  hai trục X mới **giờ trong ngày** và **thứ trong tuần** của FS-07.01 §2 — có ở **mọi thiết bị**, không riêng Mac.
- Nhấp một cột/thanh mở Library đã lọc đúng nhóm đó; tooltip "Click to show 412 photos".
- Kiểu biểu đồ **C**: một chuỗi = amber nhạt + mark đáng chú ý amber đậm có nhãn số; nhiều chuỗi = bảng 6 màu cố
  định, có legend ([DESIGN.md](../../../DESIGN.md) §3.4). Chữ trục ≥ 10.
- Một ảnh có bản sao ở hai nguồn được đếm **một lần** (D7, FS-19). Source = T7 RAW Archive đếm ảnh có bản trên T7.
- **Popup Source là bộ lọc tạm của màn**: áp lên mọi thẻ không có điều kiện Source riêng, không ghi vào định nghĩa
  thẻ nào. Thẻ có điều kiện Source riêng **giữ điều kiện của nó**, bỏ qua popup, và ghi tên nguồn đó trên thẻ.
- Sheet sửa biểu đồ 640×560 ([FS-07.01b](../FS-07-statistics/01b-cards-editor-and-states.md)).
- **Đã dựng (row 28, 2026-11-14)** — `ShotDexMac/Statistics/`:
  - Bộ thẻ mặc định của Mac (`ChartSpec.macDefaultSpecs()`, gieo một lần, cờ `stats.mac.didSeedCharts`; thẻ đã xoá
    không mọc lại): hàng số 5 ô (Total Photos & Videos · Slow Shutter · Median ISO *This Year* · Average Equivalent
    Focal Length · Median Aperture) rồi Top Camera · Top Lens · Photos per Month (*Last 12 Months*, 3 máy, legend) ·
    ISO (*This Year*) · Body + Lens · Equivalent Focal Length · Aperture · Shutter Speed · Photos by Weekday (*This
    Year*) · Time of Day · Photos per Year. iPhone giữ sáu thẻ của FS-07.01 §3. Khoảng mới **Last 12 Months** (tháng
    này và 11 tháng trước) có ở mọi thiết bị.
  - Thẻ xếp vào cột thấp nhất theo thứ tự; 4 cột khi vùng nội dung ≥ 1120pt, ít hơn khi hẹp. Thẻ top-N: tên · số ·
    % (trên số ảnh trong khoảng của thẻ) · thanh, hàng đầu amber đậm; dòng cuối "N photos from other values or without
    this info." Thẻ cột: amber nhạt, cột cao nhất amber đậm kèm số; rê chuột hiện "ISO 401–1600 · 86 photos / Click to
    show 86 photos". Cột 0 ảnh, giờ, thứ và đường không nhấp được (Library chưa có bộ lọc giờ/thứ — AC-57).
  - **⋯** mỗi thẻ (cả ô số), hiện khi rê chuột, luôn có cho bàn phím/VoiceOver: Duplicate (bản sao ngay sau, tên
    "… Copy") · Move Earlier · Move Later (trong hàng của nó: ô số với ô số, thẻ với thẻ) · Delete Chart… (hỏi lại).
  - **+**: New Chart… (row 30) rồi danh sách thẻ để thêm — các thẻ mặc định đang thiếu, rồi một biểu đồ cột cho mỗi trục chưa có.
  - Popup **Source**: All Sources + các nguồn của sidebar; đổi là tính lại mọi thẻ và Insights (lượt cũ đến sau bị
    bỏ). Tên nguồn trên thẻ có điều kiện Source riêng: chưa vẽ (cần sheet sửa, row 30).
  - Nhấp hàng/cột/insight: All Photos với đúng bộ lọc đó (bỏ Advanced Filter đang có).
  - Settings › General › **Show Insights in Statistics** chạy thật (ẩn/hiện thẻ Insights).
  - Mọi truy vấn và mọi lần ghi `stat_charts` chạy ngoài main thread.
- **Sheet sửa biểu đồ (row 30, 2026-11-15)** — board `MAC_ChartEditor`, `MacChartEditorSheet.swift`; kiểu màu **C** đã
  chốt (board `MAC_ChartStyle`, MacTheme `chart*`):
  - Mở: **+ › New Chart…** (⌥⌘N) và **⋯ › Edit Chart…** trên mọi thẻ và ô số. Sheet 640×560: Name (trống → tên gợi ý
    hiện mờ, lưu bằng tên đó) · **Chart Type** Bars · Columns · Donut · Line · Number (Bars/Columns là `drawsColumns` của
    biểu đồ cột; chưa chọn thì theo trục: tên → hàng, số/giờ → cột; iPhone bỏ qua) · Group By (Number có "Nothing — one
    number") · Measure (Photo Count · Average · Median — chỉ Number · Sum · Minimum · Maximum · Slow Shutter Rate; + "Of"
    khi cần trường) · Show **Top N** (stepper 1–20; Line: "Lines" 1–6, tắt tới khi có Split Series) · Split Series (tắt
    ngoài Line, chú "Line charts only.") · Date Range (All Time · This Year · This Month · Last 12 Months).
  - Number nhóm theo một trục đếm **nhóm lớn nhất** (Measure tắt, chú "Counts photos in the biggest group."); ô số ghi tên
    nhóm đó. Đổi sang Number từ kiểu khác bắt đầu không nhóm.
  - **Preview** sống bên phải: thẻ y như dashboard (cùng Source popup), đọc lại 250 ms sau thay đổi cuối, ngoài main;
    dài quá thì cuộn; lỗi đọc → "Couldn't load this chart."
  - **Conditions**: All/Photo/Video + Match all/any + các dòng điều kiện của smart album (`MacRuleLine`, **không nhóm**
    — + chỉ thêm dòng; không chọn thư mục — điều kiện Source đếm cả nguồn). Dòng dở bị bỏ qua, có chú.
  - Thẻ có điều kiện Source riêng ghi tên nguồn cạnh khoảng ngày (cả ô số); popup Source không đổi nó.
  - Cancel / Esc: bản nháp không đổi → đóng; đã đổi → **Discard Changes?** (Discard · Keep Editing). Save: thẻ mới thêm
    cuối và màn cuộn tới nó; sửa thì giữ chỗ, số cũ đứng tới khi số mới về.
  - Donut: sáu màu chuỗi, phần thứ 7 trở đi gộp **Other** xám (không mở được); legend là hàng bấm được.
  - **Chưa làm** (board có): số đo Keeper Rate · Picks · Average Rating · Edited Photos (model chưa có phép đo theo dấu
    rating/flag/edit); Custom… date range; nhóm điều kiện.
- **Trang một máy (row 29, 2026-11-14)** — board `MAC_StatisticsCamera`, `MacStatisticsCameraPage.swift`:
  - **Mở**: bấm một hàng của Top Camera (hàng có chevron ›; các thẻ khác vẫn mở Library). Trang thay dashboard trong
    cùng chỗ; toolbar: **Back** (⌘[, về dashboard) · popup **Source** (chung với dashboard) · **Show in Library** (All
    Photos lọc máy này, cùng nguồn). Back từ Library sau khi nhấp trên trang quay lại **trang**; vào Statistics bằng
    sidebar từ nơi khác thì về dashboard. Chọn lại Statistics trên sidebar khi đang ở trang: không đổi (Back là lối ra).
  - **Mọi số tính trên mọi ngày** — không có popup khoảng ngày (board không vẽ; bỏ ý cũ "giữ popup khoảng ngày riêng").
  - Đầu trang: ô máy ảnh 56pt · tên · `Canon · Full Frame sensor (1.0× crop) · first photo … · latest …` (phần nào
    không biết thì bỏ) · nút **Camera Database…** mở Settings › Cameras (cả khi Settings chưa mở).
  - Sáu ô: Photos (`38% of library`, hay `of this source` khi popup có nguồn) · Lenses Used · Busiest Month (+ số ảnh) ·
    Median ISO · Slow Shutter · Favorites. Ô hẹp: tháng rút gọn rồi bỏ số phụ, không cắt chữ.
  - **Frames in Library**: cột ảnh mỗi tháng (amber nhạt, tháng nhiều nhất amber đậm kèm số) + đường cộng dồn (màu
    chuỗi 2) có trục riêng bên phải và số cuối; legend; câu "Counts photos in your library, not the camera's shutter
    count. Busiest month: …". Ít tháng: cột 14pt.
  - **Lenses on This Body**: 5 ống kính nhiều nhất (bấm = Library lọc máy + ống kính); dòng cuối "N more lenses · M
    photos ›" (hoặc "M photos without lens info") mở mọi ảnh của máy.
  - **Focal Length** (tương đương), **Aperture**, **ISO**: cột như dashboard (nhãn trục là cận dưới của nhóm; tooltip ghi
    cả khoảng; bấm = Library lọc máy + nhóm đó).
  - **Top Rated**: ảnh 5 sao của máy (cùng nguồn), tối đa 8, badge định dạng + ★★★★★, dải tối ở chân sau dòng phơi
    sáng; **Sort By** Newest · Oldest · Highest ISO · Longest Lens (board cũ ghi "Rating" — mọi ảnh ở đây đều 5 sao, đã
    sửa board); **Show All** và bấm một ô = Library lọc máy + 5 sao. Lỗi đọc: "Couldn't load…" + Try Again.
  - Trạng thái: đang đọc (mờ khi đổi nguồn), lỗi (Try Again), máy không có ảnh trong nguồn đang chọn ("No Photos from X
    Here" + Show All Sources).
  - Một lượt đọc ngoài main thread (`StatisticsQueries.cameraProfile` + các truy vấn biểu đồ có bộ lọc máy); lượt cũ bị huỷ.

## 3. Cửa sổ Settings (⌘,)

Cập nhật 2026-11-04 ([intent](../../_intents/2026-11-04-mac-settings-panes.md)): sáu pane theo board, có pane AI; bỏ
Group Photos By và Open Photos (nhóm ảnh và cách mở ảnh chỉnh ở menu View, không ở Settings).

- Một cửa sổ rộng cố định **720**, cao ≤ **640** (thân cuộn); toolbar 6 pane **General · AI · Sources · Editing ·
  Servers · Cameras**; tiêu đề cửa sổ theo pane; nút thu nhỏ/phóng to tắt. **Không có nút Save** — đổi là áp ngay.
- **Hàng chưa có tính năng phía sau** (Mac chưa có viewer, Export, AI Search…) vẫn hiện đúng chỗ trên board nhưng
  **mờ và không bấm được**, kèm chữ phụ "Available in a later version". Board vẽ các hàng đó mờ. Khi tính năng tới Mac,
  hàng sáng lên — không thêm, không dời hàng.
  Chốt 2026-11-04: mờ ở mọi bản; tới lúc nộp App Store mới quyết có ẩn không (App Review 2.1/2.3).

| Pane | Board | Hàng chạy thật | Hàng mờ (chưa có tính năng) | Từ mục iOS |
|---|---|---|---|---|
| General | `MAC_SettingsGeneral` | câu Thumbnail size (chỉ chữ) · File Type Badge · Info on Thumbnails (File Name, Capture Time, ISO, Aperture, Shutter Speed, Focal Length, Megapixels, File Size) · Focal Length (Actual · Full-Frame Equivalent) · **Indexing** (đã có) · **Background** (đã có, [FS-22.06](../FS-22-backup/06-mac.md) §5.4) | View Full HDR · Autoplay Videos · On This Day Reminder (Show Insights in Statistics chạy thật từ row 28) | Display, Playback, Notifications |
| AI | `MAC_SettingsAI`, `MAC_SettingsAIProvider` | — | cả pane: Use For › AI Search, bảng Providers và sheet sửa provider | AI ([FS-08.07](../FS-08-settings/)) |
| Sources | `MAC_SettingsSources`, `MAC_SettingsSourcesCache` | bảng Photo Sources (Manage Access…, Re-index, Remove…, Grant Access…, Add Folder…, Connect to Server…, thả folder vào bảng) · When a Drive Is Disconnected · Pause Indexing on Battery Power · Prevent Sleep While Indexing · Look Up Place Names · Scan for People and Pets (kèm "N of M items scanned") · Preview Cache (dung lượng, Clear Cache, Cache Size Limit 2/5/10/25/50 GB) · **Index** (đếm, dung lượng, tiến độ, Re-index Library) · Camera Database (số máy chưa rõ, Review Unknown Cameras) · Clear Local Metadata Index | Index New and Changed Files · Preview Cache › Change Location… · Keep Full-Size Previews · Keep Previews of Disconnected Drives | Sources (FS-21), People and Pets, Library Size, Privacy |
| Editing | `MAC_SettingsEditing` | RAW + JPEG Pairs · Export Defaults (Size, Format and Quality, File Names, If a File Exists, Metadata When Sharing) · bảng Presets (+, −, Edit…) — §3c | Watermark When Sharing (Share trên Mac gửi file nguyên trạng, chưa đóng dấu) | Export, Sharing |
| Servers | `MAC_SettingsServers` | bảng Connections (Name · Host · Protocol · Folder · Status; Add Connection…, Edit, Test, Delete) · Local Network Access + Open Privacy Settings… · Server Thumbnails (phần của server trong Preview Cache, Clear Cache — không có limit riêng) | — | File Servers ([FS-15.01](../FS-15-server-upload/01-servers-and-settings.md)) |
| Cameras | `MAC_CameraDatabase` | bảng máy (tìm, Sensor Format sửa tại chỗ, Crop Factor, lọc Unknown); "Review Unknown Cameras" ở Sources nhảy tới đây | — | Camera Database (FS-08.03 §7) |

- **Sources › Index** là chỗ xem index tới đâu: đang chạy thì "Indexing 12,400 of 55,231" + thanh tiến độ, xong thì
  "up to date · indexed 2 min ago". Chân sidebar (board `MAC_SourceIndexing`) cũng ghi số và thanh, và **không bị khung
  Common Photos che**: có cả hai thì xếp chồng, index ở trên.
- **Một cache, một limit** (chốt 2026-11-04, theo FS-19 01b §3): thumbnail server nằm trong Preview Cache; limit chỉ ở
  Sources. **Không có hàng `.xmp` sidecar** trên Mac: cull đã bỏ, Mac không ghi `.xmp` (chốt 2026-11-04). Board bỏ theo.
- Remove nguồn và Delete kết nối hỏi lại trước (hộp xác nhận nói rõ ảnh/file trên ổ và server **không** bị xoá). Clear
  Local Metadata Index hỏi lại và giữ bảng dữ liệu người dùng ([BD-02](../../01-basic-design/)).
- Prevent Sleep While Indexing tách khỏi Keep Mac Awake While Copying (Background): một cái cho index, một cái cho chép.
  Pause Indexing on Battery Power dừng index khi Mac chạy pin (máy không có pin: hàng mờ, chữ phụ "This Mac has no
  battery"); Low Power Mode luôn dừng như hôm nay.
  Index New and Changed Files: hàng mờ, luôn bật — index luôn đọc file mới/đổi (chốt 2026-11-04).
- Không có hàng Accent Color (D11). Support mở từ menu Help, không từ Settings.
- **Không có Widgets** (Mac bản đầu không có widget), **không có pane Privacy** — các dòng Privacy nằm trong Sources —
  và **không có ô tìm**: 6 pane đủ ngắn để nhìn hết ([FS-08.01](../FS-08-settings/01-layout-and-search.md) là của iOS).

### 3c. Editing (row 41, 2026-11-17, board `MAC_SettingsEditing`)

- Bỏ dòng "Editing and Export come to the Mac in a later version." — editor (row 31–40) và Save and Export (row 39) đã
  có. Board sửa theo.
- **RAW + JPEG Pairs** — Edit the RAW (mặc định) · Edit the JPEG: file editor mở cho ảnh **chưa sửa** có cặp
  (`photo_copies.pairedPath` khi file chính là RAW và bạn đi kèm không phải phim — Live Photo không bao giờ mở .MOV;
  trạng thái iCloud của file đi kèm đọc từ chính file đó). Ảnh đã sửa giữ file nó được sửa trên: sửa trên JPEG thì được
  ghi lại (`mac.editing.editedOnJPEG`) và lần sau vẫn mở JPEG, kể cả khi đổi lại Edit the RAW; Revert về gốc thì bỏ
  ghi. Ảnh Photos: lần sửa đầu mở bản không-RAW của phiên. Chỉ editor đổi; viewer, Quick Look, Share vẫn dùng RAW.
- **Export Defaults** — là thứ sheet Save and Export mở ra (`mac.export.defaults`); sheet rồi nhớ lựa chọn của chính
  nó (FS-03.07b §3) — **cho tới khi người dùng đổi một mục ở đây**: đổi là xoá trí nhớ của sheet, lần mở sau theo
  Settings. Mở sheet mà không đổi gì không tính là nhớ. Chọn preset tự tạo ở Size lấy luôn định dạng và chất lượng của
  nó; ô File Names ghi khi Return hay rời ô, ô trống là tên gốc (`{original}`). Size (preset Resize, kể cả preset tự tạo), Format and Quality (một popup:
  Same as Original / JPEG / HEIC và 60–100%), File Names (mẫu token, dòng "Example: 2026-09-28_DSC04218.jpg" từ ảnh mẫu),
  If a File Exists (Keep Both · Replace · Skip), **Metadata When Sharing** (`share.metadataLevel`, ba mức của FS-08.06 —
  sheet Export luôn bắt đầu từ mức này). **Watermark When Sharing** mờ: Share trên Mac chưa đóng dấu.
- **Presets** — bảng Name · Type · Details, dòng 28pt xen màu; preset dựng sẵn có ổ khoá, không xoá không sửa. **+** mở
  sheet "New Resize Preset" (Name, Size Long Edge / Exact Size / Original Pixels, cạnh dài hay Rộng × Cao + Fit Inside / Crop to Fill,
  Format, Quality; Save mờ kèm lý do khi tên rỗng, trùng tên preset khác, hay cỡ ngoài 64–20 000 px). **Edit…** (hay bấm đúp) mở cùng sheet cho
  preset tự tạo; preset watermark sửa Name và chữ. **−** hỏi "Delete “Client 2400”?" (nói rõ: lựa chọn export đang dùng nó về Original; watermark thì rời danh sách
  Text của sheet) rồi xoá. − mờ cho preset dựng sẵn và cho watermark có ảnh (ảnh đó các ảnh đã đóng dấu trong editor
  còn dùng — xoá ở Markup). Settings và sheet Export đọc lại preset mỗi khi bên kia ghi. Đếm "7 resize · 3 watermark"
  cạnh tiêu đề. Preset watermark được tạo trong editor (Markup, Edit… của sheet Export).
- Preset bị xoá mà Export Defaults hay sheet Export đang trỏ tới thì sheet về Original (FS-03.07b §3a).

## 4. Collage, Resize, Combine Photos (tầng D, D10)

- Mở **trong cửa sổ chính** như Editor: panel trái thế chỗ sidebar, ◀ hoặc Cancel về nơi đã mở; ⌥⌘O đưa sang cửa sổ
  riêng ([01](01-window-and-navigation.md) §5). File sinh ra: [03](03-editor-and-export.md) §5.
- Luôn tối kể cả chrome; long-running chạy không modal, tiến độ trong màn và Activity.
- **Collage** ([FS-11](../FS-11-collage.md)): panel trái (Photos có stepper, Presets, Layouts for N Photos, khay Set Aside),
  canvas giữa, inspector 300 (Aspect Ratio, Size W×H, Border, Spacing, Corners, Background Fill + ô màu, Blur, Dim,
  Polaroid, Text, Export Size). Toolbar: "Collage" + "4 of 4 photos · 1:1 · Not saved yet" · Undo · Redo ·
  Show Original · inspector · **Export…**.
- **Resize** ([FS-03.07](../FS-03-photo-editor/07-resize-and-compression.md)): toolbar inspector · Cancel ·
  **Resize 8 Photos**; giữa là trước/sau 100% có vạch chia và bảng từng file (Source · Dimensions · Original ·
  Estimated · %); inspector: Size, Quality and Format, Metadata, Save To (mặc định Pictures › ShotDex Resized),
  Delete Originals (đích từng phần theo FS-19).
- **Combine Photos** ([FS-01.09](../FS-01-library/09-photo-stacking.md), [FS-14](../FS-14-panorama/README.md)): tiêu đề
  là tên chế độ ("Panorama"), dòng phụ "8 photos · Sony A7 IV · FE 24-70mm F2.8 GM II"; toolbar Cancel · **Save**;
  dải khung, preview đang căn "Aligning frames, 6 of 8" + Stop; inspector Projection, Edges, Output, Save To.

### 4a. Resize — đã dựng (row 42, 2026-11-17, board `MAC_Compress`)

- **Lối vào:** Image › **Resize…** ⌥⌘R — ảnh đang chọn (chỉ ảnh, video bỏ qua), hay ảnh đang mở trong viewer. Trang thế
  chỗ khu chi tiết của cửa sổ như Editor; ◀ / Cancel / Esc về chỗ cũ — cả khi đang chạy: lượt vẫn chạy, chỉ **Stop**
  dừng nó. Đổi chỗ ở sidebar cũng vậy. Một lượt một lúc: ⌥⌘R khi một lượt còn chạy hỏi "A resize is still running".
- **Toolbar:** ◀ · tiêu đề "Resize" + "8 photos · 194.3 MB from 4 sources" · Inspector (⌥⌘I) · Cancel · **Resize 8 Photos**
  (viên accent chữ đen, ⌘↩). Bật Remove originals thì nút ghi "Resize 8 Photos and Remove Originals" (FS-03.07 §4, D4).
- **Preview** trước/sau cao 372: trái bản gốc, phải **chính file sẽ ghi** (render, thu nhỏ theo preset, nén theo Quality
  rồi đọc lại) — 100% là giữa ảnh ở pixel thật, bên phải là cùng vùng đó của file nhỏ phóng lên cho bằng; Fit là cả ảnh.
  Vạch chia kéo được (VoiceOver: điều chỉnh ±5%). Nhãn: "Original · 7728×5152 · 44.1 MB", "Resized · 2048×1365 · JPEG 80% ·
  ~1.3 MB" (tên preset), nút 100% / Whole Photo, "DSCF4127.RAF · 1 of 8". Làm ngoài main actor, thay đổi cuối thắng;
  đổi ảnh thì xoá ngay hình cũ (vòng quay) chứ không để ảnh cũ dưới tên mới. Không preview trong lúc chạy.
- **Bảng:** Name (ảnh nhỏ) · Source (biểu tượng theo loại) · Dimensions "7728×5152 → 2048×1365" · Original · Estimated ·
  Saved (xanh, "−97%"); hàng tổng "8 photos from 4 sources | 194.3 MB | ~9.4 MB | −95%"; bấm hàng = preview ảnh đó. Ảnh
  chỉ có trên server ghi "Not on this Mac" và bị bỏ qua: hàng tổng thành "7 of 8 photos", dưới bảng một câu "1 photo only
  on NAS Home won’t be resized — its original isn’t on this Mac.", preview nói lý do, không có nhãn "Resized".
- **Ước lượng:** số byte trên mỗi pixel đo bằng cách nén thật ảnh đang preview ở cỡ đích, nhân với số pixel đích của từng
  ảnh — nhanh, "A fast estimate — the final size may differ slightly."
- **Inspector 300:** Size (preset Resize, kể cả tự tạo — lấy luôn định dạng và chất lượng của nó; dòng "Long edge 2048 ·
  Fit"), Quality and Format (Quality 10–100%, Format Same as Original / JPEG / HEIC, Metadata All / All Except Location /
  None), Save To (popup: ShotDex Resized · Choose Folder…; câu "Library photos go back to Photos. Folder and NAS photos go
  to Pictures › ShotDex Resized, never into the folder they came from."), **Remove originals after resizing** (mặc định
  tắt; câu kể theo nguồn: Recently Deleted / Trash / bị ẩn trên NAS), thẻ "194.3 MB → ~9.4 MB" có thanh.
- **Chạy:** từng ảnh một ngoài main actor (bộ nhớ một ảnh): bản gốc + bản sửa ShotDex của nó → preset → định dạng
  (RAW và PNG/TIFF ra JPEG, HEIC giữ HEIC ở Same as Original) → ghi. Ảnh Photos thành ảnh mới trong Photos; ảnh thư mục,
  ổ, NAS vào Pictures › ShotDex Resized (entitlement `assets.pictures.read-write`) hoặc folder đã chọn (bookmark), tên
  gốc + đuôi mới, trùng thì " (2)". Không bao giờ ghi vào thư mục nguồn (folder đã chọn trùng thư mục ảnh thì ảnh đó báo
  lỗi), không đụng bản gốc. Toolbar: "Resizing 3 of 8" + Stop (Stop tới được cả lúc đang render); Activity › Background có
  dòng. Một ảnh lỗi thì sang ảnh sau và được kể tên kèm lý do.
- **Remove originals** chỉ xoá **bản đã dùng để resize** của ảnh đã ghi được, qua đường Move to Trash (bản Photos: Photos
  hỏi rồi vào Recently Deleted; file: vào Trash); các bản sao khác của ảnh giữ nguyên (FS-19.04 §1). Ổ không có Trash:
  giữ bản gốc, không bao giờ xoá hẳn từ đây. Dừng giữa chừng: không xoá gì ("Originals kept because the run was
  stopped."). Toolbar "Removing originals…" (không Stop). Bấm Don't Allow ở hộp của Photos: "You kept the originals in
  Photos." (không phải lỗi).
- **Xong:** inspector (tự hiện) có thẻ "8 saved · 185 MB smaller" thế chỗ thẻ ước lượng (+ "went back to Photos",
  "originals removed", tên tối đa 3 ảnh lỗi với lý do, bỏ qua); toolbar **Show in Finder** (mở folder đích) + **Done**.
  Màn ở lại tới khi Done. Activity › Background giữ dòng kết thúc ("Resized 8 photos · 185 MB smaller", hay "Resize
  finished with problems") tới lượt sau — người đã rời trang vẫn biết.
- **Demo:** `-ShotDexSection resize` mở 8 ảnh mới nhất từ bốn nguồn (thư mục, Photos, ổ, NAS);
  `-ShotDexResizeTest` ghi vào thư mục tạm; ảnh "Photos" của demo không vào Photos, Remove originals của demo không
  xoá gì thật (đường xoá của demo chỉ ghi dòng).
- **Chưa dựng:** Fill kéo neo crop cho một ảnh, watermark, Share N Photos, Cancel gỡ bản đã ghi (Stop giữ những gì đã
  ghi), tải ảnh chỉ có trên server về để resize, ⌥⌘O cửa sổ riêng.

## 5. Video Studio

- Cửa sổ riêng (Window › Video Studio ⌥⌘V), tối thiểu **1180×760** ([01](01-window-and-navigation.md) §4).
- 1440×900: media browser trái (chỗ sidebar, "Hide Sidebar"), viewer, inspector 300, timeline trải hết bề ngang.
  Ở 1180×760 (`MAC_VideoStudioCompact`): media browser và inspector thu thành nút toolbar, timeline giữ nguyên.
- Khi nó là cửa sổ chính: menu Clip thay Image, ⌘E = Export…. Chọn trên timeline dùng #57BFD1.
- Kéo ảnh từ cửa sổ thư viện vào timeline thành clip. Mọi thứ bên trong: [FS-12](../FS-12-video-studio/README.md).

## 6. Support

- Help › **ShotDex Support…** đưa cửa sổ Library lên trước và mở **sheet 760×600** trên nó (không còn cửa sổ riêng, user
  2026-11-07); **Done** (Esc) ở góc trên trái sidebar đóng: trái Report a Bug… · Request a Feature… · Your Messages (trạng
  thái, số trả lời chưa đọc) · What People Asked For (bỏ phiếu); phải là hội thoại + ô trả lời + **Send Reply**.
- Câu riêng tư: "No account and no email. A message carries your words, the app and macOS version, the Mac model and
  roughly how many photos you have — never a photo or a name." Luật: [FS-13](../FS-13-support.md), NF-03 §2.
- Đã làm (2026-11-07, `MacSupportSheet` — trước là `MacSupportWindow`, model chung `SupportModel` — nay trong
  `Tools/mac-membership.shared`): sheet trên cửa sổ Library, **Done** góc trên trái, header thread nằm trên cùng; chữ đang gõ
  (trả lời, báo lỗi) giữ trong model cho lượt chạy này nên Esc không làm mất; trả lời mới chưa đọc hiện số trên Dock
  (đọc lại mỗi lần ShotDex lên trước). Sidebar 228: **Report a Bug…** / **Request a Feature…**
  (nền `fill` r8, mở sheet soạn) · **Your Messages** (tiêu đề, "In Progress · 2 days ago", huy hiệu số trả lời chưa đọc
  `accentFill`; chọn = nền xám `rowSel`; thread đang mở được đánh dấu đã đọc sau 1,5 s trên màn hình, kể cả khi trả lời
  mới tới lúc nó đang mở) · **What People Asked For** (viên "↑ 412": bấm bỏ phiếu, bấm lại rút; chưa bỏ = nền `fill`, đã
  bỏ = nổi `segOn`; mờ khi đang gửi, không bấm chồng) · câu riêng tư ở đáy. Không đọc được danh sách → "Couldn't load." +
  **Try Again**. Phải: tiêu đề 15 semibold + "Bug report · 2 replies"
  + viên trạng thái (amber Planned/In Progress, xanh Shipped, xám còn lại) · thẻ tin đầu (chip Bug/Feature, "You · ngày",
  nội dung) · **Conversation**: bong bóng ShotDex trái nền `card`, You phải nền `accentSoft`, giờ dưới mỗi tin · ô "Add to
  this message" + **Send Reply** (⌘Return, tắt khi trống nhưng vẫn đọc được — `MacFilledButtonStyle`; chữ giữ lại nếu gửi
  lỗi, chỉ xoá nếu không gõ thêm lúc đang gửi). Thread chưa có trả lời: "Sent. A reply from the ShotDex team will appear
  here — there is no notification, so check back." Làm mới khi app trở lại phía trước thì im lặng (không alert khi
  offline), các lần làm mới không chồng nhau, lần cũ về muộn bị bỏ.
- Sheet soạn 480: Title, What happened / What you would like (gợi ý dưới), **Include Diagnostic Log** (checkbox amber; bật
  cho bug, tắt cho feature) + **Read the Log…**, câu "Goes to the ShotDex team… no notification, so check back… Also
  sent…", Cancel (Esc, bấm được cả lúc đang gửi) / **Send** (Return, cần tiêu đề ≥ 4 và nội dung ≥ 10 ký tự). Log đọc
  **lúc bấm Send** (có cả lần tái hiện); số ảnh đếm ngoài luồng chính. Đang gửi: "Sending…"; lỗi: dòng đỏ + **Email This
  Instead** (mailto với tiêu đề và nội dung đã viết), sheet ở lại.
- Bản build không chứng thực được (App Attest) → phần phải thành **Support by Email**: lý do bằng lời thường, địa chỉ
  chọn được, Contact Support by Email (mailto kèm phiên bản app/macOS và model Mac — nói ngay dưới nút; không có app mail
  → báo địa chỉ + Copy Address); nút soạn và bỏ phiếu tắt, câu đáy sidebar đổi theo. Lỗi mạng khi người dùng bấm → alert.
- Demo `-ShotDexDemoLibrary -ShotDexSection support`: ba thread và năm yêu cầu dựng sẵn, không bao giờ gọi máy chủ.
- Chưa có: dòng "Sent with ShotDex 1.0 (24) · macOS · Mac · about 55,000 photos · log …" dưới tin đầu (API không trả lại
  những gì đã gửi); phím ↑↓ giữa các thread; báo có trả lời khi cửa sổ đóng (số trên Help/Dock); hỏi trước khi bỏ bản nháp.
  Việc của dịch vụ chung (`SupportService`/`SupportAttestation`), chưa đụng: lỗi attest tạm thời cũng hạ xuống mail cho cả
  phiên; POST tạo ticket thành công mà đọc body lỗi thì báo lỗi (gửi lại = ticket trùng); `isTestFlightBuild` luôn false
  trên macOS; bản Release Mac chưa có quyền App Attest (`ShotDexMac.entitlements`) nên hiện là màn mail.
