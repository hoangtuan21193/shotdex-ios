# FS-18.01b — Menu bar, phím tắt, chuột phải, kéo thả

`FS-18.01b` · board `MAC_MenuBar` · `MAC_ContextMenu` · `MAC_Collections` · cập nhật 2026-10-04

**Một câu:** mọi lệnh có một dòng trên menu bar với một phím cố định; toolbar giữ phần hay dùng, chuột phải giữ
phần theo ngữ cảnh.

## 1. Luật

- **Mọi lệnh ở toolbar hay inspector đều có dòng trên menu bar.** Dòng không áp dụng được thì mờ, không ẩn.
- Thứ tự menu: **ShotDex · File · Edit · View · Image · Go · Window · Help**.
- **Một danh sách phím duy nhất** dựng cả menu, tooltip và bảng Keyboard Shortcuts (Help › ⌘/). Tooltip ghi phím.
- Phím do ShotDex đặt không dùng ⌃ (⌃⌘F, ⌃⌘S của hệ thống giữ nguyên). Thứ tự modifier ⌃⌥⇧⌘.
- Undo ghi tên việc vừa làm ("Undo Rotate").
- Lệnh có tên giống nút của nó: ⌘⌫ ghi đúng chữ của nút xoá trên màn đang mở; tên đích xoá theo FS-19.
- Lệnh xoá tấm Reject đặt tên theo đích, menu và nút Cull cùng chữ: có file đi Thùng rác → **Move N Rejected…**;
  chỉ ảnh Photos → **Delete N Rejected…** ([FS-01.12b](../FS-01-library/12b-culling-pass.md)); chỉ ảnh NAS → **Hide N Rejected…**.
- Khi **Video Studio** là cửa sổ chính: menu **Image** đổi thành **Clip**, ⌘E là **File › Export…**, Image › Edit tắt.

## 2. Bản đồ phím chuẩn

| Menu | Lệnh · phím |
|---|---|
| ShotDex | Settings… ⌘, · Hide ⌘H · Hide Others ⌥⌘H · Quit ⌘Q |
| File | New Window · New Album ⌘N · New Album with Selection ⇧⌘N · New Smart Album… ⌥⌘N · New Video Project · New Chart… |
| File | Add Folder… ⇧⌘O · Add Photos Library · Connect to Server… ⌘K · Import from Card… (FS-20) |
| File | Open ⌘O · Open in New Window ⌥⌘O · Show in Finder ⇧⌘R · Reveal in Photos · Upload to Server… ⇧⌘U |
| File | Export ▸ Export N Photos… ⇧⌘E · Export Unmodified Originals… ⌥⇧⌘E · Export EXIF as CSV… · Share ▸ · Eject "‹ổ›" · Remove Source… · Close ⌘W · Print… ⌘P |
| Edit | Undo ⌘Z · Redo ⇧⌘Z · Cut/Copy/Paste ⌘X ⌘C ⌘V · Select All ⌘A · Deselect All ⇧⌘A |
| Edit | Copy Edits ⇧⌘C · Paste Edits ⇧⌘V · Sync Edits ▸ (Sync Look… · Sync Everything… · Apply Previous · Auto Sync) · Revert to Original… · Search ⌘F · Advanced Search… |
| View | as Grid ⌘1 · as List ⌘2 · Sort By ▸ · Filter ▸ · Filter and Sort… ⇧⌘L · Show Filter Bar · Zoom In ⌘+ · Zoom Out ⌘− |
| View | Show Info on Thumbnails ⇧⌘M · Show File Type Badges · Group by Day · Show Original \\ · Show Clipping |
| View | Hide Sidebar ⌃⌘S · Show Inspector ⌥⌘I · Hide Toolbar ⌥⌘T · Customize Toolbar… · Play Slideshow ⌥⌘S · Enter Full Screen ⌃⌘F |
| Image | Edit ⌘E · Compare ⌥⌘C · Quick Look Space · Get Info ⌘I · Rotate Counterclockwise ⌘R · Rotate Clockwise ⌥⌘R |
| Image | Favorite . · Rating ▸ 0–5 · Pick P · Reject X · Clear Flag U · Start Culling Pass ⌥⌘P · Keywords… ⇧⌘K |
| Image | Adjust Date and Time… · Adjust Location… · Editor ▸ · Create ▸ (Collage… · Video Project…) · Combine Photos ▸ (Focus Stack… · Panorama… · HDR… · Stack Exposures…) · Resize… |
| Image | Keep Only This · Merge N Groups… · Rescan Duplicates · Move N Rejected… (§1) · Duplicate ⌘D · Hide ⌘L · Move to Trash ⌘⌫ |
| Go | Back ⌘[ · Forward ⌘] · Enclosing Album ⌘↑ · All Photos ⌥⌘1 · Favorites ⌥⌘2 · Videos ⌥⌘3 · RAW ⌥⌘4 · Recently Added ⌥⌘5 · Statistics ⌥⌘6 |
| Go | On This Day · Albums · Places · Trips · Duplicates · Collages · Video Projects · On Server · Go to Date… (không phím) |
| Window | Minimize ⌘M · Zoom · Fill · Video Studio ⌥⌘V · Activity ⌥⌘0 · Bring All to Front · danh sách cửa sổ |
| Help | ShotDex Help · Search Syntax · Keyboard Shortcuts ⌘/ · ShotDex Support… |

- **Image › Editor ▸** (khi Editor đang mở): Adjust A · Crop C · Mask M · Heal H · Markup K · Invert Mask ⇧I ·
  Show Mask Overlay O · Visualize Spots Y · Flip Horizontal · Flip Vertical · New Snapshot · **Done ⌘↩** (ảnh Photos).
- **Clip** (Video Studio) và phím riêng của nó thuộc [FS-12.17b](../FS-12-video-studio/17b-keyboard-and-pointer.md).

- Menu Clip có **A** Select Tool · **B** Blade Tool · **T** Add Text · **N** Snapping; bốn phím này thuộc danh sách
  phím chung của FS-12.17b §3, chạy trên mọi thiết bị có bàn phím.

- Không phím: Rescan, Merge N Groups…, Show in Library, Advanced Search…, Go to Date…, New Window.

## 3. Phím theo màn

| Màn | Phím |
|---|---|
| Lưới, bảng | mũi tên dời lựa chọn (⇧ nới) · Return mở Viewer · Space Quick Look (Space lần nữa đóng) |
| Viewer | ← → ảnh trước/sau · **Z** Fit ↔ 100% · Return mở Editor · Esc về lưới · **.** và F favorite · I info ([FS-02.01b](../FS-02-photo-detail/01b-closing-and-keyboard.md) §2) |
| Cull | ← → · 0–5 · P · X · U · Z · ⌘Z · G lưới · Esc xong ([FS-01.12b](../FS-01-library/12b-culling-pass.md)) |
| Editor | ⇧⌘C / ⇧⌘V chép/dán edit · \\ Show Original · ⌃⌘S sidebar · [ ] cỡ cọ · ⇧[ ⇧] độ mềm · ⌥ tẩy · Return áp crop · Esc huỷ công cụ · ⌫ xoá lớp |

- **Z là phím phóng ở mọi bề mặt xem** (Viewer, toàn màn, Compare, Cull). Space không bao giờ là phóng.

- **"." luôn là Favorite** trên Mac, như Photos cho Mac. Video đang dừng: **← →** lùi/tiến một khung; video đang phát:
  ← → lật trang như iOS. "," không gán. *Chốt 2026-10-04:* khác FS-02.01b §2 (iOS: ". ," bước khung, ← → luôn lật trang).
- **Một bảng phím Editor** cho Mac và iPad có bàn phím (FS-21): dòng Editor ở trên. iPad bỏ ⌘C/⌘V, ⌘\\, ⌘0 của
  DESIGN.md §10.3; fit ⇄ 100% là Z như mọi bề mặt xem.

## 4. Menu chuột phải

- Không cột phím tắt, ẩn dòng không áp dụng được, **≤ 12 dòng** + menu con.
- Trên ảnh (`MAC_ContextMenu`): Open N Photos · Quick Look · Edit · Get Info · Rating ▸ · Flag ▸ · Favorite ·
  Add to Album ▸ · Share ▸ · Export N Photos… · Show in Finder · Move to Trash.
- Add to Album ▸: New Album with Selection · New Album… · rồi danh sách album phẳng.
- Ảnh trong Photos: Show in Finder đổi thành Reveal in Photos; dòng xoá theo FS-19.
- Ảnh trên ổ offline: ẩn Edit, Export, Show in Finder; giữ Rating, Flag, Favorite, Add to Album (FS-19).
- Trên hàng sidebar, card Collages/Video Projects, header bảng: menu riêng theo board của màn đó.

## 5. Kéo thả

| Kéo | Thả lên | Kết quả |
|---|---|---|
| ảnh (1…n) | hàng album trên sidebar | hàng tô amber + huy hiệu số; thêm vào album; ⌘Z gỡ |
| ảnh | timeline Video Studio | thành clip tại điểm thả (FS-12) |
| ảnh | Finder / app khác | bản đã chỉnh (render) nếu có chỉnh, không thì file gốc; giữ **⌥** lúc thả → luôn file gốc |
| thư mục, ổ, thẻ nhớ từ Finder | Sources, vùng thả trạng thái trống | thêm nguồn (FS-19) / mở Import from Card (FS-20) |
| file ảnh lẻ (1…n, không phải thư mục) | bất kỳ đâu trên cửa sổ thư viện | hỏi (dưới) |

- Bản render khi kéo ra theo mức metadata của [FS-08.06](../FS-08-settings/06-share-metadata-privacy.md); không kèm `.xmp`.
- Thả file ảnh lẻ: hộp "Add “‹thư mục›” as a Source?" với **Add Folder** · **Copy to Photos Library** · Cancel.
  Add Folder thêm thư mục chứa file làm nguồn (FS-19); Copy to Photos Library chép file vào Photos, không thêm nguồn.
- File lẻ đến từ nhiều thư mục: Add Folder thêm từng thư mục; thư mục đã là nguồn hay nằm trong nguồn thì bỏ qua.
