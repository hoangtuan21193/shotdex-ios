# Search giống Photos — plan thực thi

> Chốt 2026-11-14 sau 1 vòng · nguồn: .planboard/search-photos/plan.json
> Spec: docs/02-functional-spec/FS-01-library/03c-search-like-photos.md (FS-01.03c)

## Nguyên tắc
- Theo thứ tự; xong task thì tick và chạy phần "Kiểm tra".
- Đi chệch quyết định đã chốt: dừng, hỏi người dùng.
- Không bỏ chức năng nào (A8). Mỗi AC một commit, `git commit -- <paths>`.

## Việc cần làm

### 1. Tài liệu + design
- [x] 1.1 Intent — `docs/_intents/2026-11-14-search-like-photos.md`
- [x] 1.2 Spec FS-01.03c + AC — `docs/02-functional-spec/FS-01-library/03c-search-like-photos.md`, trỏ từ 03-search.md
- [x] 1.3 Board PH/IP/DI/DC/MAC_Search (gõ: gợi ý + kết quả; trống: Gần đây + thư viện; có viên), sáng + tối, publish 4 canvas

### 2. Chỉ mục (A1, A6)
- [x] 2.1 Migration `search_group`, `search_group_asset`, FTS5 `search_group_fts`, `search_text_fts` — `ShotDex/Data/Database/AppDatabase+SearchIndex.swift`
- [x] 2.2 `SearchIndexStore` dựng/cập nhật nhóm từ photo_metadata, place, album, keyword, caption — sau batch indexer
- [x] 2.3 `SearchIndexQueries`: suggestions(prefix, within tokens), results(tokens, text), counts — chạy nền, huỷ được
  - Kiểm tra: `/test SearchIndexTests`

### 3. Domain
- [x] 3.1 Ranker gợi ý, token model ↔ FilterCriteria/SmartAlbumQuery — `ShotDex/Domain/Search/`
- [x] 3.2 Ngày: năm/tháng/mùa/thứ/today (D5) — `SearchIntentParser`
- [x] 3.3 "Có phải…?" (D6) — `SearchSpelling`
- [x] 3.4 Từ vựng parser dựng một lần (A3)

### 4. UI iOS (iPhone/iPad/Duo, iOS 26 tab + sheet trước 26)
- [x] 4.1 Dòng gợi ý (D1), viên trong ô (D3), kết quả trong Search + Mở trong Library (D2) — `SearchSuggestionsScreen.swift`, `RootTabView.swift`
- [x] 4.2 Ô trống: Gần đây nhanh (A4) + Trong thư viện (D4); báo chưa index xong (A7)

### 5. Mac
- [x] 5.1 Menu gợi ý có số ảnh, viên, kết quả trong cửa sổ — `ShotDexMac/MacRootWindow.swift`, `MacSearchScope.swift`

### 6. Kiểm chứng
- [~] 6.1 (iPhone 26.5 sáng+tối, iPad, Duo inner, Mac đạt; 18.6 không có runtime; A6 chờ quyết) `/build`, `/test` lớp liên quan, ui-drive iPhone 26.5 + iPad + Duo, Mac build + mac-shot, `/verify FS-01.03c`

## Ngoài phạm vi
- Tìm theo nội dung ảnh (cảnh, chữ trong ảnh, người) — ShotDex không có nhận dạng; AI search hiện có giữ nguyên.
