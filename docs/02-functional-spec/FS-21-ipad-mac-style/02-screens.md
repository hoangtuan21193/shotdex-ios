# FS-21.02 — Từng màn iPad (1): Library, Search, Viewer, Editor, Collections, Statistics

`FS-21.02` · nhánh màn rộng của `Features/Library`, `Search`, `PhotoDetail`, `Editing`, `Collections`, `Statistics`
· cập nhật 2026-10-04

**Một câu:** mỗi màn nói thứ gì dời đi đâu so với iPad hôm nay; luật khung (sidebar, toolbar, inspector) ở [01](01-shell.md).

## 1. Library — `Main`, `IP_LibrarySelect`, `IP_LibraryList`, `IP_SourceIndexing`

- Tiêu đề toolbar là tên hàng sidebar đang chọn ("All Photos", "2026 Japan"); dòng phụ đếm ảnh · video.
- Ô lưới: nhãn định dạng trên-trái (HEIC · RAW · JPG · MOV), thời lượng trên-phải, dòng EXIF 12 ở đáy kèm glyph sao,
  cờ, favorite, Live — cùng nội dung lớp phủ Display của iPhone ([FS-08](../FS-08-settings/README.md) › Display).
- Chế độ **List** (`IP_LibraryList`): bảng hàng 44, cột Name · Date · Camera · Lens · Focal · Aperture · Shutter · ISO ·
  Rating, chạm tiêu đề cột để sắp; khi chọn có cột tick. iPhone có cùng chế độ qua ⋯ ([01b §5](01b-windows-and-access.md)).
- Dải trạng thái nguồn (đang thêm 33% · Pause · Stop; ổ offline · Locate · Remove Source) nằm đầu nội dung — luật ở FS-19.
- Thanh điều kiện (chip, Match all, Edit/Clear) nằm ngay dưới toolbar như FS-01.02 §3.

- **Đầu nhóm ngày** trong lưới khi ở khung FS-21 (bề rộng ≥ 700): dòng "Monday, September 28 · Kyoto · 48 photos"
  giữa các nhóm, cấp ngày/tháng/năm theo mật độ đã lưu. Ngoại lệ màn rộng của DESIGN §10.2, cùng Mac; iPhone, Duo
  và bố cục iPhone < 700 giữ lưới phẳng, ngày trên tiêu đề.

## 2. Search và lọc — `IP_Search`, `IP_AdvancedSearch`

- Search là **ô trên toolbar** (rộng ~264), không còn tab. Điều kiện thành token trong ô (Brand Sony · Focal 85mm),
  mỗi token có nút xoá; ⌘F đặt con trỏ vào ô.
- Chạm ô trống: popover 400 rộng dưới ô liệt kê **Recents dạng hàng** (câu + số ảnh) kèm Clear Recent Searches.
  Gõ: cùng popover chuyển sang gợi ý — "In this search" (số ảnh), smart album khớp, Recent khớp.
- Dưới toolbar: dải phạm vi All Sources · Photos Library · Folders and Drives · Servers (FS-19) và Save as Smart Album….
- Advanced Search: form sheet 700×640 trên Library mờ; luật nháp và Discard Changes? giữ như FS-01.05b §5.
- Filter and Sort (toolbar): cùng các dòng của menu Filter hôm nay (FS-01.05b), mở dạng menu từ nút.

- Không có hàng thẻ Recents trên iPad ở khung FS-21 — phần iPad của FS-01.03b §5 thay bằng popover trên. Duo inner
  giữ 5 thẻ; bố cục iPhone < 700 giữ 3 thẻ.

## 3. Viewer — `IP_Viewer`, `IP_Metadata`, `IP18_ViewerRating`, `IP19_ViewerMenu`, `IP_Share`, `IPP16_InfoKeywords`

- Mở **trong cửa sổ**: sidebar ẩn, Back về lưới đúng chỗ cuộn và lựa chọn. Vuốt ngang vẫn lật ảnh, pinch phóng.
- Toolbar: Show Sidebar · Back · tên file + nhãn định dạng, dòng phụ ngày · "12 of 112"
  · `[Zoom · Favorite · Rotate Counterclockwise · Share · Delete · ⋯]` · Hide Inspector · **Edit**.
- Single · 2-Up · Survey đã bỏ 2026-10-24; Compare từ chế độ chọn là màn A/B của Duplicates ([FS-01.08](../FS-01-library/08-compare.md)).
- Filmstrip cao 100 ở đáy vùng ảnh, ô 64, ô hiện tại viền amber; chạm ô để nhảy.
- Inspector 360 (thay cột Photo Info): Rating and Flag (5 sao 44 · None/Pick/Reject) · Histogram · Caption and
  Keywords · Camera and Lens (+ 4 ô ISO/Focal/Aperture/Shutter) · Location (bản đồ) · File (Source, Original, Dimensions)
  · **Get Info** → form sheet 700×640, bảng EXIF hai cột, Show All Raw Metadata.
- Share: popover từ nút Share — Copy · Save to Files · Share With Location · Share Without Location (FS-08.06).
- Dọc: toolbar Back · Favorite · Info · Share · ⋯ · Delete · Edit; Info là sheet dưới cao 576 có Done.

- **Nền Viewer theo sáng/tối của hệ thống** ở mọi thiết bị (iPhone, iPad, Duo, Mac) — Viewer không phải tầng D
  (MAC_STYLE v3). Inspector và sheet Info đi theo; luật "luôn tối" của FS-02.03b §2 bỏ.

## 4. Editor ngang — `IP1_Edit` … `IP24_FileName`

- Tầng D. Toolbar: Show Sidebar · Back · tên file ▾ (Edit Version) + dòng phụ "Photos Library · Fujifilm X-T5 · 3 of 48"
  · segmented **Adjust · Crop · Mask · Heal · Markup** · `[Undo · Redo]` `[Before and After · Zoom · ⋯]` · Hide Inspector · **Save**.
- ⋯: History · Copy Edits · Paste Edits · Recall Last ShotDex Edit · Reset All · Revert to Original (đỏ, có xác nhận).
- Inspector 360: histogram có hai nút cảnh báo cháy sáng/tối · Look + Amount · các nhóm Light · Tone Curve · Color ·
  Color Mixer · Point Color · Grading · Effects · Lens Blur · Detail · Optics · Calibration, **mở/gập** từng nhóm, Auto, Reset.
- Sidebar trái 320 (tối): Presets — My Looks · Presets · LUTs, và History. Nhiều ảnh: filmstrip 100 dưới ảnh, ô 88×60.
- **Lưu giữ kiểu iOS**: Save mở sheet Save Edit 600 (Save Changes · Save Copy, JPEG | HEIC, Metadata — FS-03.17 D6).
  Không tự lưu như Mac; lưu ảnh nguồn thư mục/server theo FS-19.

## 5. Editor dọc — `IPP1_Edit` … `IPP20_FileName`

- Giữ **cột inspector** ~360 bên phải (ảnh 668 rộng), không thành sheet — chỉnh ảnh cần thấy cả ảnh lẫn slider.
- Toolbar một hàng (Back · Undo · Redo · Before and After · Zoom · ⋯ · Hide Inspector · Save), nút 44; segmented công
  cụ là hàng thứ hai ở y 92. Presets mở sidebar **phủ** (`IPP4_Presets`).

## 5b. Editor: iPad theo board, iPhone đổi tên

- Editor iPad theo board, thay FS-03.17 §3 và FS-03.17a (cột 280, băng đĩa nổi, dải 6 công cụ, danh sách phẳng).
- Một công cụ một tên ở mọi thiết bị: **Edit → Adjust**, **Transform → Crop** cả trên iPhone và Duo.
- iPhone và Duo **giữ bố cục** FS-03.13 (dải 6 công cụ, panel 246, danh sách phẳng); nhóm gập được chỉ ở iPad.

## 6. Collections — `IP_Collections`, `IP_AlbumDetail`, `IP_SmartAlbum*`, `IP_OnThisDay`, `IP_Duplicates`, `IP_Creations`, `IP_VideoProjects*`

- Không còn tab: hàng sidebar **Albums** mở trang album theo board (hero On This Day + Recently Viewed/Shared, Smart/My Albums,
  Media Types); công cụ đã sang trang Utilities (`IP_Utilities`: card Statistics trải ngang trên cùng, dưới là Library · Create ·
  Elsewhere thành cột độc lập, 2026-10-24) và nhóm Utilities của sidebar, mỗi hàng mở thẳng màn của nó; On This iPad (`IP_OnThisIPad`) và sheet Keep
  (`IP_KeepOnIPad`) theo intent `2026-10-19-keep-offline`. Toolbar trang album: Sort By · `+` (New Album,
  New Smart Album, Customize).
- Album, smart album: header + lưới như Library; Edit Smart Album là form sheet 700×640.
- Places và Trips: đã gỡ khỏi app 2026-10-24 (board `IP_Places`, `IP_Trips` xoá theo).
- Collages: lưới theo tháng, thẻ 242×224, `+` New Collage.
- Duplicates: segmented Exact · Similar · Series · Bursts (kèm số nhóm) trên toolbar, Rescan, ⋯, **Delete N Photos** cuối
  phải (chữ đỏ, không tô); danh sách nhóm 360 trái + chi tiết nhóm phải, thay lưới thẻ xếp gạch.

- Số đo trang album ở 1016pt theo board: hero **764×150**, tile album **159**. DESIGN §10.1e (hero 260 ở regular) và
  §10.1d (tile 192) đổi theo cho khung FS-21; iPhone và Duo giữ số của hai mục đó.

## 7. Statistics — `IP_Statistics`, `IP_ChartEditor`, `IP_DateRange`

- 3 cột thẻ 328 ở 1016pt — đúng luật ≥ 320, 2…3 cột (FS-07.01 §6); Insights trải hết bề rộng. Biểu đồ kiểu C (DESIGN §3.4).
- Đầu mỗi thẻ: đổi kiểu vẽ (donut/cột, cột/đường) và ⋯ 44; iPhone đổi kiểu qua ⋯ của thẻ ([01b §5](01b-windows-and-access.md)).
- `+` trên toolbar: Add Chart · Reorder Charts (FS-07.03 AC-29). Chart editor form sheet 700×640 xem trước sống;
  Date Range là sheet chồng, hai tháng một hàng.
