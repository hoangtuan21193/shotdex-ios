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
- Places: bản đồ + inspector 300 của cụm đang chọn. On This Day: lưới theo năm, Show Trip mở Trips.
- Duplicates: segmented mức khớp **Exact · Similar · Series · Bursts**, danh sách nhóm 340 bên trái, hai bản cạnh
  nhau, Rescan, **Merge N Groups…**; chỉ gom trong một nguồn (D7, FS-19,
  [FS-06.06](../FS-06-collections/06-duplicates.md)).
- Collages (`MAC_Creations`): thẻ theo tháng; chuột phải Open in Collage · Show in Library · Export… · Share… ·
  Remove from Collages…. Video Projects: thẻ project, New Video Project, xác nhận xoá bằng alert.

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

- Một cửa sổ rộng cố định **720**, cao ≤ **640** (thân cuộn); toolbar 5 pane **General · Sources · Editing · Servers ·
  Cameras**; tiêu đề cửa sổ theo pane; nút thu nhỏ/phóng to tắt. **Không có nút Save** — đổi là áp ngay.

| Pane | Có gì | Từ mục iOS |
|---|---|---|
| General | Group Photos By · Open Photos (In the Same Window · In a New Window) · File Type Badge · Info on Thumbnails · Focal Length (Actual · Full-Frame Equivalent) · View Full HDR · Autoplay Videos · Show Insights in Statistics · On This Day Reminder | Display, Playback, Notifications |
| Sources | nguồn ảnh, quyền, `.xmp` sidecar, ổ và index, preview, People and Pets, Library Size, Re-index, Clear Local Metadata Index, các dòng Privacy — chi tiết FS-19 | Sources (tên mới của Photo Library, FS-21), People and Pets, Library Size, Privacy |
| Editing | file mở khi có RAW+JPEG · câu về color profile · Export Defaults (Size, Format and Quality, File Names, If a File Exists, Metadata When Sharing, Watermark When Sharing) · bảng Presets | Export, Sharing |
| Servers | bảng Connections (Name · Host · Protocol · Folder · Status) · Local Network Access · Keep Mac Awake While Uploading · Server Thumbnails | File Servers ([FS-15.01](../FS-15-server-upload/01-servers-and-settings.md)) |
| Cameras | bảng máy, popup Sensor Format sửa tại chỗ; "Review Unknown Cameras" ở Sources nhảy tới đây | Camera Database (FS-08.03 §7) |

- Không có hàng Accent Color (D11). Support mở từ menu Help, không từ Settings.
- **Không có Widgets** (Mac bản đầu không có widget), **không có pane Privacy** — các dòng Privacy nằm trong Sources —
  và **không có ô tìm**: 5 pane đủ ngắn để nhìn hết ([FS-08.01](../FS-08-settings/01-layout-and-search.md) là của iOS).

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
