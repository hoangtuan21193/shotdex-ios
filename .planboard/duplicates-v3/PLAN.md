# Duplicates v3 — giúp người chụp biết giữ ảnh nào — plan thực thi

> Chốt ngày 2026-10-17, sau 1 vòng · nguồn: .planboard/duplicates-v3/plan.json
> Đầu vào: 7 báo cáo agent (3 persona, 2 UX, khảo sát 13 app, ý kiến người dùng); ảnh sim ở build/ux-dup/.

## Nguyên tắc
- Làm theo thứ tự; mỗi task xong thì tick và chạy phần "Kiểm tra".
- Cần đi chệch một quyết định đã chốt: dừng lại, hỏi người dùng.
- Design đi trước code; board và code khớp (CLAUDE.md global). Mỗi AC một commit.
- Build: `/build`; test: `/test <Class>`; UI: `/ui-drive` + `Tools/sim-shot`; full suite một lần ở cuối.

## Việc cần làm

### 1. Plan → Design (tài liệu)
- [ ] **1.1 Intent** — `docs/_intents/2026-10-17-duplicates-v3.md`
  - Theo: A8
  - Xong khi: nêu vấn đề "ảnh nào tốt hơn", 3 persona, link báo cáo, 10 quyết định.
- [ ] **1.2 Spec FS-06.06 + 06b viết lại với AC** — `docs/02-functional-spec/FS-06-collections/06-duplicates.md`, `06b-duplicates-marks-merge-delete.md`
  - Theo: D1–D12, A1–A7; 06b §1 D2 (session-lived) được thay bởi D12.
  - Xong khi: mỗi quyết định có ít nhất một AC kiểm chứng được.
- [ ] **1.3 Board Duplicates trên canvas iPhone / iPad / Duo** (sáng + tối) — `docs/design/{iphone,ipad,duo}/project/*Duplicates*.dc.html`, `PH_BurstFrames.dc.html`
  - Theo: D2, D4, D5, D7–D11
  - Xong khi: sửa board tại chỗ (không thêm board biến thể), publish lên 3 canvas, `Tools/design-board render` không lỗi.

### 2. Nền dữ liệu
- [ ] **2.1 Bảng lưu lựa chọn, nhóm đã duyệt, Keep all, Not duplicates** — `ShotDex/Data/Database/AppDatabase.swift`, store mới, `Features/Duplicates/DuplicateReviewSession.swift`
  - Theo: D12, A1
  - Xong khi: lựa chọn còn sau khi kill app; id đã bị xoá tự rơi; không đụng photo_metadata.
  - Kiểm tra: `/test` lớp store mới + migration test.
- [ ] **2.2 Bảng điểm chất lượng + face rect** — `AppDatabase.swift`
  - Theo: D1, D8

### 3. Gom nhóm
- [ ] **3.1 Gom một lần, mỗi cụm một loại (Copy · Smaller copy · Same moment · Look-alike · Screenshot)** — `ShotDex/Domain/Duplicates/DuplicateGrouper.swift`
  - Theo: D4
  - Xong khi: không member nào ở hai loại; Bursts PhotoKit đổ vào Same moment.
  - Kiểm tra: `/test DuplicateGrouperTests`
- [ ] **3.2 Bracket / focus stack / panorama set từ EXIF; khác tiêu cự > 10% không gộp; Copy đòi cùng giây chụp hoặc file hash** — `DuplicateGrouper.swift`
  - Theo: D5
  - Kiểm tra: `/test DuplicateGrouperTests`
- [ ] **3.3 Nhận diện ảnh xuất (Lightroom), bản gửi lại (WhatsApp/Zalo), album membership** — `ShotDex/Domain/Duplicates/DuplicateReview.swift`
  - Theo: D10, A2

### 4. Chấm chất lượng
- [ ] **4.1 Đo nét / mắt / cháy sáng cho member nhóm sau khi gom** — `ShotDex/Domain/Duplicates/DuplicateScanPipeline.swift`
  - Theo: D1
  - Xong khi: chỉ đo ảnh đã vào nhóm; hủy được; fixture không có mặt người.
- [ ] **4.2 Thứ hạng + lý do + điểm yếu; favorite/edited/album không bao giờ tự chọn xoá** — `DuplicateReview.swift`
  - Theo: D1, A2, A7 (Easiest first)
  - Kiểm tra: `/test DuplicateReviewTests`

### 5. Giao diện
- [ ] **5.1 Màn tóm tắt hai phần + sheet xem trước Dọn nhanh; dòng Collections "~X GB to free"** — `Features/Duplicates/DuplicatesScreen.swift`, `Features/Albums/AlbumsScreen.swift`
  - Theo: D2
- [ ] **5.2 Hàng lọc theo loại thay 4 tab; bề rộng cố định; header một dòng** — `DuplicatesScreen.swift`
  - Theo: D4, A6
- [ ] **5.3 Thẻ bộ nguyên liệu với Merge to HDR / Panorama / Focus Stack, không nút xoá** — `DuplicatesScreen.swift`
  - Theo: D5
- [ ] **5.4 Tile: chạm mở to, vòng 44pt đánh dấu; caption khác biệt 2 dòng; nhóm ≥ 12 gập + "Show all"; giữ viền đỏ 0.6s + haptic trước khi gập** — `DuplicatesScreen.swift`
  - Theo: D7, D9, D10
- [ ] **5.5 Màn chọn khung chung: khung lớn + dải phim, zoom đồng bộ, Zoom to face, chấm đỏ, Keep picks; nút ở dưới, vuốt xuống đóng** — `Features/Bursts/BurstFramesScreen.swift`, `BurstFramesModel.swift`
  - Theo: D8, A6
- [ ] **5.6 Xoá: sheet danh sách ảnh sắp xoá, "N in albums", keeper nhận album/favorite/vị trí, thông báo sau xoá + Open Photos** — `DuplicatesScreen.swift`, `DuplicatesModel.swift`
  - Theo: D11
- [ ] **5.7 Chữ mới (US English) + Ignored list + quét hiện dần + banner quyền** — `DuplicatesScreen.swift`, `Resources/Localizable.xcstrings`
  - Theo: A1, A3, A4, A5
- [ ] **5.8 iPad / Duo inner / Duo cover theo board**
  - Theo: tất cả
  - Kiểm tra: `/screens duplicates`

### 6. Test
- [ ] **6.1 /verify FS-06.06** — mọi AC có bằng chứng; agent design-parity, iphone-ux-review chạy lại.
- [ ] **6.2 Full suite + sim-clean**

## Ngoài phạm vi
- Undo thật sau khi xoá (iOS không cho phép); thùng rác riêng trong app (D11 option bị loại).
- Lưới 4 khung zoom cùng lúc trên iPhone (D8 option bị loại).
