# FS-18.04 — Các màn còn lại

`FS-18.04` · board `MAC_Collections` · `MAC_AlbumDetail` · `MAC_Statistics` · `MAC_Settings*` · `MAC_CameraDatabase` ·
`MAC_Collage` · `MAC_Compress` · `MAC_Merge` · `MAC_VideoStudio*` · `MAC_Support` · cập nhật 2026-10-04

**Một câu:** mỗi màn của iOS có một chỗ trên Mac — điểm đến ở sidebar, công cụ tầng D trong cửa sổ, Settings và
Support thành cửa sổ riêng.

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
- Sheet sửa biểu đồ 640×560 ([FS-07.01b](../FS-07-statistics/01b-cards-editor-and-states.md)); trang một máy
  (`MAC_StatisticsCamera`) giữ popup khoảng ngày riêng của nó.

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
| General | `MAC_SettingsGeneral` | câu Thumbnail size (chỉ chữ) · File Type Badge · Info on Thumbnails (File Name, Capture Time, ISO, Aperture, Shutter Speed, Focal Length, Megapixels, File Size) · Focal Length (Actual · Full-Frame Equivalent) · **Indexing** (đã có) · **Background** (đã có, [FS-22.06](../FS-22-backup/06-mac.md) §5.4) | View Full HDR · Autoplay Videos · Show Insights in Statistics · On This Day Reminder | Display, Playback, Notifications |
| AI | `MAC_SettingsAI`, `MAC_SettingsAIProvider` | — | cả pane: Use For › AI Search, bảng Providers và sheet sửa provider | AI ([FS-08.07](../FS-08-settings/)) |
| Sources | `MAC_SettingsSources`, `MAC_SettingsSourcesCache` | bảng Photo Sources (Manage Access…, Re-index, Remove…, Grant Access…, Add Folder…, Connect to Server…, thả folder vào bảng) · When a Drive Is Disconnected · Pause Indexing on Battery Power · Prevent Sleep While Indexing · Look Up Place Names · Scan for People and Pets (kèm "N of M items scanned") · Preview Cache (dung lượng, Clear Cache, Cache Size Limit 2/5/10/25/50 GB) · **Index** (đếm, dung lượng, tiến độ, Re-index Library) · Camera Database (số máy chưa rõ, Review Unknown Cameras) · Clear Local Metadata Index | Index New and Changed Files · Preview Cache › Change Location… · Keep Full-Size Previews · Keep Previews of Disconnected Drives | Sources (FS-21), People and Pets, Library Size, Privacy |
| Editing | `MAC_SettingsEditing` | — | cả pane: RAW + JPEG Pairs, Export Defaults, Presets (Mac chưa có editor và Export) | Export, Sharing |
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

## 5. Video Studio

- Cửa sổ riêng (Window › Video Studio ⌥⌘V), tối thiểu **1180×760** ([01](01-window-and-navigation.md) §4).
- 1440×900: media browser trái (chỗ sidebar, "Hide Sidebar"), viewer, inspector 300, timeline trải hết bề ngang.
  Ở 1180×760 (`MAC_VideoStudioCompact`): media browser và inspector thu thành nút toolbar, timeline giữ nguyên.
- Khi nó là cửa sổ chính: menu Clip thay Image, ⌘E = Export…. Chọn trên timeline dùng #57BFD1.
- Kéo ảnh từ cửa sổ thư viện vào timeline thành clip. Mọi thứ bên trong: [FS-12](../FS-12-video-studio/README.md).

## 6. Support

- Help › **ShotDex Support…** mở cửa sổ **760×600**: trái Report a Bug… · Request a Feature… · Your Messages (trạng
  thái, số trả lời chưa đọc) · What People Asked For (bỏ phiếu); phải là hội thoại + ô trả lời + **Send Reply**.
- Câu riêng tư: "No account and no email. A message carries your words, the app and macOS version, the Mac model and
  roughly how many photos you have — never a photo or a name." Luật: [FS-13](../FS-13-support.md), NF-03 §2.
