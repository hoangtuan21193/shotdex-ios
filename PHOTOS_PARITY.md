# ShotDex ⟷ iOS Photos — Feature Parity

Tracker cho đợt bổ sung tính năng còn thiếu so với app Photos (iOS 18/26).
Khảo sát gốc: 122 mục — 27 CÓ, 44 MỘT PHẦN, 51 KHÔNG.

**Quy ước:** `[ ]` chưa làm · `[x]` xong (đã build pass + commit) · `[-]` bỏ qua, không có public API · `[~]` làm một phần, có ghi chú.

**Quyết định phạm vi (chốt với chủ dự án 2026-09-19):**
- Commit thẳng `main`, mỗi tính năng một commit build-pass.
- Có làm: App Intents, Spotlight, Widget target, Share Extension, hỗ trợ iPad.
- Vision **không** được đưa vào `IndexPipeline`. OCR/Live Text chạy on-demand khi mở ảnh. People & Pets là pass quét riêng, người dùng tự bấm trong Settings.
- Library grid: Years / Months / Days / All làm **mặc định**, thay chế độ `.flat` hiện tại.

---

## Phase A — Thao tác asset qua PhotoKit

- [x] A1 `PhotoLibraryService`: hide/unhide, sửa creationDate, sửa location, xoá khỏi album, rename/delete album, restore/xoá vĩnh viễn, favorite hàng loạt
- [-] A2 Album Hidden + Recently Deleted — iOS 16+ giấu ảnh ẩn khỏi mọi app trừ Photos; đã đo trên iOS 26: `.smartAlbumAllHidden` trả 0, `includeHiddenAssets` cũng không thấy ảnh nào. Hành động **Hide vẫn chạy**, chỉ không duyệt/bỏ ẩn được
- [x] A3 Sheet Adjust Date & Time, sheet Adjust Location (chọn trên bản đồ)
- [x] A4 Context menu khi giữ tile (xem trước + 11 hành động, 3 nhóm) + Select All
- [x] A5 Bulk: favorite, hide, adjust date, adjust location, copy
- [~] A6 Album CRUD — service layer xong hết (rename/delete/sắp xếp tay/folder), Remove from album đã lên UI; còn phần UI cho rename/delete/folder
- [~] A7 Viewer có menu ⋯: Add to Album, Duplicate, Copy, Select Text in Photo, Adjust Date & Time, Adjust Location, Show on Map, Hide. **Còn thiếu**: Show in All Photos, Print riêng (hiện đi qua share sheet hệ thống)
- [ ] A8 Tuỳ chọn Share (kèm/không kèm vị trí, bản gốc/bản sửa), Revert to Original, nút Auto-enhance, Copy & Paste edits, giữ tay xem bản gốc trong viewer
- [~] A9 Badge trên tile: favorite/Live/Portrait/Panorama/HDR/Slo-mo/Time-lapse xong; pull-to-refresh xong. **Không làm được**: badge "edited" (PhotoKit không expose cờ chỉnh sửa trên `PHAsset`, chỉ có cách duyệt `PHAssetResource` từng ảnh — quá đắt cho lưới đang cuộn). Filter Screenshots cần cột `mediaSubtypes` trong DB, xem mục riêng bên dưới
- [ ] A10 Kéo thả ảnh ra app khác và thả vào album

## Phase B — Duyệt và xem

- [~] B1 Years / Months / Days — pinch 1–3 cột = ngày, 4–6 = tháng, 7+ = năm; Library bật lại date header làm mặc định; thanh cuộn ngày có nhãn ngày khi kéo. **Còn thiếu**: tên địa điểm trong header (chờ D1 Places, `LibraryGridItem` chưa có cột place)
- [ ] B2 Toggle lưới theo tỉ lệ gốc
- [x] B3 Media Types collections — section riêng trong Collections, 16 subtype (Videos, Selfies, Live, Portrait, Panorama, Time-lapse, Slo-mo, Cinematic, Bursts, Screenshots, Screen Recording, Animated, Long Exposure, RAW, Spatial); album rỗng tự ẩn như Photos
- [ ] B4 Recently Viewed / Recently Shared / Recently Saved
- [x] B5 Live Photo: badge LIVE trong viewer (bấm để phát, `PHLivePhotoView` phủ lên ảnh tĩnh nên giữ nguyên zoom/paging), badge `livephoto` trên tile, **Save as Video** trích `PHAssetResource.pairedVideo` thành clip mới
- [ ] B6 Portrait: đọc depth data, hiển thị, chỉnh độ mờ nền
- [ ] B7 Video: tua từng khung, chỉnh dải slo-mo, trim ngay trong viewer
- [ ] B8 Burst stack, viewer panorama
- [ ] B9 Filmstrip dưới viewer
- [ ] B10 Slideshow
- [ ] B11 Gộp ảnh trùng (giữ bản tốt nhất, hợp nhất metadata)
- [ ] B12 Hiển thị HDR đầy đủ
- [ ] B13 Markup: hình khối, kính lúp
- [ ] B14 Import: bỏ qua ảnh đã nhập, xoá sau khi nhập, nhập thẳng vào album
- [ ] B15 Toggle autoplay, thống kê dung lượng thư viện

### Việc phát sinh

- [ ] Thêm cột `mediaSubtypes` vào `photo_metadata` (migration GRDB + `MetadataComposer`) — mở khoá filter Screenshots / Live / Portrait / Panorama và rule smart album theo loại phương tiện

## Phase C — Hệ thống

- [ ] C1 App Intents + Shortcuts + Siri
- [ ] C2 CoreSpotlight
- [ ] C3 Widget (Home Screen + Lock Screen)
- [ ] C4 Share Extension
- [ ] C5 Handoff qua NSUserActivity
- [ ] C6 Photo editing extension
- [ ] C7 Hỗ trợ iPad (sizeClass, sidebar, landscape, phím tắt)
- [ ] C8 Rà soát Dynamic Type toàn app

## Phase D — Tự dựng phần Apple Intelligence

- [ ] D1 Places: bản đồ duyệt ảnh, gom cụm
- [ ] D2 Trips: gom theo ngày + vị trí
- [ ] D3 Memories / Featured Photos: tự chọn + dựng phim qua Video Studio
- [ ] D4 People & Pets: pass quét Vision riêng, opt-in trong Settings
- [x] D5 Live Text on-demand trong viewer — `ImageAnalysisInteraction`, chỉ phân tích khi bật từ menu, tự tắt khi lật sang ảnh khác
- [ ] D6 Tách chủ thể / tạo sticker trong viewer
- [ ] D7 Pinned Collections + tuỳ biến thứ tự màn Collections

## Không có public API — bỏ qua

- [-] Visual Look Up (không có API)
- [-] Clean Up / xoá vật thể bằng Apple Intelligence (không có API)
- [-] Live Photo effects Loop / Bounce / Long Exposure (`PHAssetPlaybackStyle` chỉ đọc)
- [-] Đổi key photo của Live Photo (không có API)
- [-] Caption / title của PHAsset (`PHAssetChangeRequest` không có thuộc tính này)
- [-] Spatial Scene 3D, Custom Memory Movie theo prompt, Events (không có API)
- [-] iCloud Shared Photo Library, Shared with You, subscriber/comment của Shared Album (không có API)
- [-] Cinematic mode focus edit (không có API)
- [-] Portrait Lighting (không có API)
- [-] Utilities gợi ý bằng ML: Receipts, Handwriting, Illustrations, QR, Documents (không có API)
- [-] Holiday Events, Transfer to Mac, Lock Screen Photo Shuffle (thuộc hệ điều hành)
- [-] Sort "Recently Added" (PhotoKit không expose ngày thêm vào thư viện)
- [-] Recently Deleted: duyệt / khôi phục / xoá vĩnh viễn — `PHAssetCollectionSubtype` không có `recentlyDeleted`, không fetch được
- [-] Duyệt album Hidden / bỏ ẩn — hệ thống chặn, xem mục A2
