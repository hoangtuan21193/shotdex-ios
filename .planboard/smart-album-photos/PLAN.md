# Smart Album giống Photos — plan thực thi

> Chốt ngày 2026-11-13, sau 1 vòng · nguồn: .planboard/smart-album-photos/plan.json
> Spec: docs/02-functional-spec/FS-06-collections/08-smart-albums.md §3c, AC-20…AC-37

## Nguyên tắc
- Làm theo thứ tự; mỗi task xong thì tick và chạy phần "Kiểm tra".
- Cần đi chệch một quyết định đã chốt: dừng lại, hỏi người dùng.
- Không bỏ chức năng nào (A6). Mỗi AC một commit, `git commit -- <paths>` (checkout dùng chung).

## Việc cần làm

### 1. Tài liệu + design
- [x] **1.1 Intent** — `docs/_intents/2026-11-13-smart-album-like-photos.md`
- [x] **1.2 Spec §3c + AC-20…37** — `docs/02-functional-spec/FS-06-collections/08-smart-albums.md`
- [x] **1.3 Board editor + album** — `docs/design/{iphone,ipad,duo,mac}/project/*SmartAlbum*.dc.html`, publish 4 canvas
  - Xong khi: board vẽ D1–D5 (sáng + tối), render sạch bằng `Tools/design-board render`

### 2. Model + index + SQL
- [x] **2.1 Đơn vị ngày + notInLast** — `ShotDex/Core/Models/SmartAlbumQuery.swift`, `SmartAlbumRule+Display.swift`, `ShotDex/Data/Database/SmartAlbumSQLBuilder.swift` — AC-33, 34
- [x] **2.2 Trường Photo + 2 cột mới** — `PhotoMetadata.swift`, migration, composer/indexer, SQL — AC-35, 36
- [x] **2.3 insertRule(after:), đổi trường giữ giá trị** — model — AC-21, 23
- [x] **2.4 Duplicate / rename** — `SmartAlbumStore.swift` — AC-31, 32
  - Kiểm tra: `/test SmartAlbumOperatorTests`, `/test SmartAlbumRuleDecodingTests`, test mới

### 3. Editor (iPhone/iPad/Duo)
- [x] **3.1 Match ẩn khi 1 điều kiện, −/+ trên dòng, thanh đếm đáy, lưu lỗi báo** — `RuleBuilderSections.swift`, `SmartAlbumRuleRow.swift`, `SmartAlbumEditorSheet.swift` — AC-20, 22, 24–27

### 4. Album đang mở + Collections
- [x] **4.1 ⋯ menu, chạm thanh điều kiện mở editor, cập nhật tại chỗ, tự cập nhật** — `SmartAlbumDetailScreen.swift`, `SmartAlbumDetailModel.swift`, `SmartAlbumConditionsBar.swift` — AC-28–30
- [x] **4.2 Menu ô: Rename / Duplicate** — `AlbumsScreen.swift`, `AlbumsModel.swift` — AC-31, 32

### 5. Mac
- [x] **5.1 §3c-Mac** — `ShotDexMac/Albums/*` — AC-37

### 6. Kiểm chứng
- [~] **6.1** (iPad 26.5 + Mac đã chạy; iPhone/Duo/18.6 chưa — xem báo cáo) `/build`, `/test` lớp liên quan, sim iPhone 26.5 + 18.6, iPad, Duo; Mac build + mac-shot; `/verify FS-06.08`

## Ngoài phạm vi
- Photo is hidden / selfie / long exposure / ProRes / referenced / unable to upload (không đọc được).
