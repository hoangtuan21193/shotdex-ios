# FS-18.02 — Thư viện, Viewer, Cull, Get Info

`FS-18.02` · board `Main` · `MAC_LibrarySelected` · `MAC_LibraryList` · `MAC_Search` · `MAC_FilterPopover` ·
`MAC_Viewer` · `MAC_Cull` · `MAC_GetInfo` · cập nhật 2026-10-04

**Một câu:** duyệt cả thư viện bằng chuột và bàn phím — lưới hoặc bảng, chọn bằng nhấp, lọc bằng popover, xem
ảnh trong cửa sổ, lọc buổi chụp bằng phím.

Luật lọc, tìm, sao/cờ, Compare giữ nguyên của iOS: [FS-01.03](../FS-01-library/03-search.md),
[FS-01.05](../FS-01-library/05-filtering-and-sorting.md), [FS-01.12](../FS-01-library/12-rating-and-flags.md),
[FS-01.08](../FS-01-library/08-compare.md) (Compare = màn A/B của Duplicates; chế độ 2-Up/Survey của Viewer đã bỏ
2026-10-24). Phần này chỉ ghi chỗ Mac khác.

## 1. Lưới

- Cửa sổ 1440, sidebar hiện, inspector đóng: **7 cột**, ô vuông 165. ⌘+ / ⌘− và pinch trên trackpad đổi số cột.
- Dòng dưới ô (View › Show Info on Thumbnails ⇧⌘M): "ISO 400 · 85mm · f/1.8"; huy hiệu loại file (RAW, HEIC, MOV)
  và thời lượng video bật/tắt ở View và Settings › General. Chữ huy hiệu ≥ 10.
- Glyph trên ô: Picked, Rejected, Favorite, số sao — cùng bộ glyph FS-01.12; ảnh offline thêm glyph Offline (FS-19).
- Đầu nhóm ngày (View › Group by Day, **bật mặc định**): "Monday, September 28 · Kyoto · 48 photos"; cả nhóm từ
  một nguồn thì ghi thêm tên nguồn ("Nara · T7 RAW Archive"). Tắt thì lưới phẳng như iOS.
- *Chốt 2026-10-04:* đầu nhóm ngày là ngoại lệ màn rộng của DESIGN.md §10.2 và
  [FS-01.01b](../FS-01-library/01b-grid-engine-and-gestures.md) (lưới phẳng) — áp cho Mac, iPad, Duo trong (FS-21).

## 2. Chọn

- Nhấp chọn một · ⌘-nhấp thêm/bớt · ⇧-nhấp chọn dải · kéo từ khe hoặc lề thành khung chọn · kéo từ ô là kéo ảnh đi.
- Không có chế độ Select và không có huy hiệu tick: ô chọn có **vòng amber 3**. ⌘A chọn hết, ⇧⌘A bỏ chọn.
- Có chọn thì inspector (`MAC_LibrarySelected`) tóm tắt: "6 Photos", khoảng ngày · dung lượng; nút
  **Edit · Compare · Sync Edits…** rồi **Add to Album · Export… · Share**.
- Inspector còn: Selection (Taken, Formats, số ảnh mỗi nguồn) · Gear (máy, ống, số ảnh) · Exposure Range (ISO, tiêu cự).
- Compare cần ≥ 2 mục; dưới 2 thì nút mờ, không ẩn.
- Inspector còn Keywords (chip đặc = cả lựa chọn có, chip viền đứt "temple 4 of 6" = một phần) và Rating and Flags:
  5 sao (bấm = gán cho cả lựa chọn; bấm lại đúng số sao đang có = bỏ sao), dòng "Mixed · 2 to 4 stars"; Pick · Reject ·
  Clear Flag (segmented; không đoạn nào sáng khi lẫn hay chưa cờ); ô Favorite (chỉ ảnh trong Photos) + "2 of 6 · 4 picked".
- Lựa chọn có cả video: tiêu đề "N Items"; chỉ video: "N Videos". Thanh tiêu đề: "6 selected · 214.8 MB".
- Ô lưới vẽ dấu ở góc dưới trái: cờ (⚑ Pick, ✕ Reject) · ♥ · ★n — cùng nguồn với cột Rating của bảng.
- Lựa chọn giữ qua sắp xếp, đổi Grid/List, nạp lại; ảnh đã xoá rời lựa chọn.
- Tình trạng 2026-11-07 (Mac loop hàng 8): Edit, Compare, Sync Edits…, Export… chưa có (đến cùng màn của chúng);
  thêm/gỡ keyword cho cả lựa chọn có từ hàng 8b (ô "Add keyword to all N", × trên chip đặc, bấm chip viền đứt = thêm cho cả N;
  ảnh trong Photos qua Photos trên macOS 27, ảnh file vào sidecar). Mac đọc keyword của Photos vào index (mirror) như iOS 27. Inspector mở bằng nút trên toolbar; ⌘I là Get Info (§8, hàng 9–10).

## 3. Bảng (⌘2)

- Cột: ảnh nhỏ · Name · Date · Camera · Lens · Focal · Aperture · Shutter · ISO · Rating · Source · Size.
- Hàng **28**, ảnh nhỏ 20, nền xen kẽ; header 28 có vạch chia. Nhấp header sắp xếp, nhấp lại đảo chiều.
- Cột kéo đổi rộng, kéo đổi chỗ, ẩn/hiện qua menu chuột phải trên header; bảng rộng hơn cửa sổ thì cuộn ngang.
- Hàng chọn: nền amber khi bảng đang focus, xám khi không. Lưới và bảng giữ chung một lựa chọn.
- Mac (2026-11-07): Date, Focal, Aperture, Shutter, ISO sắp bằng thứ tự của thư viện (lưới theo cùng); Name, Camera,
  Lens, Rating, Source, Size sắp riêng trong bảng (ở nền). Bấm cột lần đầu: Date/ISO/Focal/Rating/Size lớn trước, còn lại
  A→Z. View › as Grid ⌘1 · as List ⌘2; chế độ nhớ qua lần mở. Lựa chọn chung giữa lưới và bảng: hàng sau (LibrarySelected).

## 4. Search

- ⌘F vào ô search trên toolbar. Câu gõ thành token (Camera, Focal, ISO…) theo parser FS-01.03; token là capsule
  có nút ×.
- Bảng gợi ý 560 rộng ngay dưới ô: dòng "Search “‹câu›” · 284 ↩" · Lenses in These Results · Cameras (thay máy
  đang lọc) · Saved Searches (smart album) · Recent · Advanced Search… + một dòng "Try …".
- Thanh phạm vi dưới toolbar: **All Sources · Photos Library · Folders · Servers** + số kết quả · Save as Smart Album….
- Phạm vi là điều kiện nguồn (FS-19) — cùng điều kiện mà smart album và biểu đồ dùng.

## 5. Filter and Sort

- Nút toolbar mở **popover 360×480**, mũi tên 12 trỏ vào nút. Bên trong: Sort By + chiều · Show (All · Photos · Videos)
  · Marks (Favorites · Picks · Rejected) · **Original on This Mac** ([FS-06.10](../FS-06-collections/10-original-on-device.md)) · Rating · Camera · Lens · Focal (Actual · Full-Frame Equivalent) · ISO · Aperture.
- Đáy popover: **Advanced Filter…** (mở sheet ≤ 640×560, cùng sheet với Advanced Search…) · **Save as Smart Album…**;
  góc trên: Reset.
- Điều kiện đang bật nằm trên **thanh lọc** dưới toolbar (View › Show Filter Bar): chip "Canon EOS R6 Mark II ×".
- Dòng phụ toolbar: "212 of 55,231 photos". Một điều kiện chỉ nằm ở một chỗ (FS-01.05 §1).

## 6. Viewer trong cửa sổ (D9, D10)

- Toolbar: sidebar · ◀ ▶ · tên file + huy hiệu định dạng, dòng phụ "Sunday, September 27, 2026 at 5:42 PM · 12 of 112"
  · nhóm Fit ▾ · Favorite · Rotate Counterclockwise · Share ·
  inspector · **Edit** (nút viền, không nổi bật — Edit là điều hướng, không phải lệnh chốt).
- Vùng ảnh nằm trên **nền cửa sổ**, không giếng tối. Filmstrip đáy, ảnh hiện tại vòng amber 2.
- Inspector 300: Rating and Flag · Histogram · Caption and Keywords · Camera and Lens (4 ô ISO/Focal/Aperture/Shutter
  + "−0.3 EV · Aperture Priority · Multi-segment") · Edits · Location (bản đồ, Show on Map) · File (nguồn, đường dẫn,
  Size, Dimensions, Format).
- Edits của ảnh thư mục: "Edited in ShotDex · 7 adjustments", "Saved automatically · image file never edited",
  nút **Revert to Original** · **Copy Edits**.
- Caption và keyword lưu khi gõ: ảnh Photos theo [FS-02.07](../FS-02-photo-detail/07-caption-and-keywords.md), ảnh
  thư mục/server vào sidecar (FS-19).
- Ảnh trên ổ offline: hiện preview đã lưu; Edit, Export, Show in Finder mờ, inspector ghi nguồn đang offline (FS-19).
- Phím: "." Favorite; video đang dừng thì ← → bước một khung ([01b](01b-menus-shortcuts-and-drag.md) §3).

## 7. Cull (D12)

Luật đi từng tấm, phím, undo và tóm tắt theo [FS-01.12b](../FS-01-library/12b-culling-pass.md). Mac, tầng D:

- Image › Start Culling Pass ⌥⌘P. Toolbar: View **Loupe · Grid** · nhóm Reject · 1–5 sao · Pick · Show ▾ · Undo ·
  nút chữ **Move N Rejected…** (tên theo đích, [01b](01b-menus-shortcuts-and-drag.md) §1). Nút này không nổi bật:
  nút nổi bật không bao giờ là lệnh xoá ([01](01-window-and-navigation.md) §3); 0 Reject thì mờ.
- Loupe trái, lưới 360 bên phải (ô 108, số khung ≥ 10). Ảnh đang xét: vòng trắng.
- **Dải phím** ở đáy: P Pick · X Reject · U Clear Flag · Z Zoom · ⌘Z Undo · G Grid · Esc Back, công tắc
  **Advance After**, nút **Hide**. Ẩn rồi thì lần mở Cull sau vẫn ẩn; View menu bật lại.
- Dải phím chỉ có chữ, công tắc và Hide — không lệnh xoá trong 60pt đáy (MAC_STYLE).
- Dòng đếm "120 rejected in this pass". Xoá tấm Reject: hộp xác nhận nói đích từng phần —
  "84 go to the Trash, 30 to Recently Deleted. 6 on NAS Home can’t be deleted from ShotDex and will be hidden." (FS-19).

## 8. Get Info (⌘I)

- Panel tiện ích **420×640**, không modal, đi theo ảnh đang chọn; nút thu nhỏ/phóng to tắt.
- Đầu: ảnh nhỏ · tên · "Sony A7 IV · FE 24-70mm F2.8 GM II" · "35 mm · f/2.8 · 1/250 s · ISO 400 · 48.2 MB".
- Ô sửa: Title · Caption · Keywords (chip) · Rating · Flag (None · Pick · Reject) · Date + Adjust… · Location + Adjust…
  · Creator · Copyright. Lưu khi gõ; ảnh thư mục ghi "Saved as you type to ‹tên›.xmp next to the file."
- Dưới: EXIF (Make, Model, Exposure, Aperture, ISO, Focal Length, Metering, White Balance) + **Show All Raw Metadata**.
- **Nhiều ảnh chọn**: đầu panel ghi "6 Photos" + khoảng ngày; mọi ô sửa áp cho **cả lựa chọn**. Ô mà các ảnh
  khác giá trị ghi **"Mixed"** (chữ phụ); gõ hay chọn giá trị mới thì ghi cho cả N ảnh, ô không chạm giữ nguyên từng ảnh.
- Keywords nhiều ảnh: hiện mọi chip có trong lựa chọn; thêm chip → thêm cho cả N, × trên chip → gỡ khỏi cả N.
- EXIF nhiều ảnh: dòng cùng giá trị ghi giá trị, khác nhau ghi "Mixed"; Show All Raw Metadata mờ.
- Panel mở bằng ⌘I (Image › Get Info) hoặc Get Info trên menu chuột phải (chỉ mở, không đóng); không lấy bàn phím tới khi
  bấm vào một ô (như Info của Photos). Ảnh chỉ có trong Photos: Title tắt (Photos giữ tiêu đề), ghi "Saved as you type to Photos."
- Tình trạng 2026-11-07 (Mac loop hàng 9): Creator, Copyright, Date/Location **Adjust…** và **Show All Raw Metadata** chưa có
  (hàng 9b); EXIF chỉ hiện trường có trong index (Make, Model, Exposure, Aperture, ISO, Focal Length, Lens, Size) — Metering và
  White Balance chưa được đọc vào index.
