# Movies: offline, stream, Plex, poster — plan thực thi

> Chốt ngày 2026-10-14, sau 1 vòng · nguồn: .planboard/movies-library/plan.json

## Nguyên tắc
- Làm theo thứ tự; mỗi task xong thì tick và chạy phần "Kiểm tra".
- Cần đi chệch một quyết định đã chốt: dừng lại, hỏi người dùng.

## Việc cần làm

### 1. Intent và spec
- [ ] **1.1 Intent thêm stream + Plex** — `docs/_intents/2026-10-14-offline-movies.md`
  - Theo: D1, D4, D5
  - Xong khi: Proposed outcome + Open questions ghi thư viện nhiều nguồn, stream, Plex; ghi lý do đổi.
- [ ] **1.2 FS-23.01 thành thư viện nhiều nguồn** — `docs/02-functional-spec/FS-23-offline-movies/01-library-and-import.md`
  - Theo: D1, D2, D3, D6, D7, D9, A1, A2, A5
  - Xong khi: nguồn (thư mục NAS/Files, Plex, file chép thẳng), trạng thái 3 loại, dấu ✓ + bộ lọc, mờ khi xa nhà, Grid/List, search, sort, menu + và menu phim.
- [ ] **1.3 FS-23.07 Plex mới** — `docs/02-functional-spec/FS-23-offline-movies/07-plex.md`
  - Theo: D4, D5, A3, A4, A6
- [ ] **1.4 Bảng Audio & Subtitles gộp** — `02-player.md` §3/§3b, `03-subtitles.md` §2
  - Theo: D8
- [ ] **1.5 Dữ liệu, riêng tư, AC** — `05-data.md`, `06-acceptance-criteria.md`, `README.md`, `NF-03`
  - Xong khi: bảng nguồn phim, token Plex ở Keychain, cache metadata/poster; AC cho stream, badge, mờ, Plex, Grid/search/sort, bảng gộp.
  - Kiểm tra: mọi file ≤ ~120 dòng; không còn "Find Online" hay hai nút Audio/Subtitles.

### 2. Board 4 canvas
- [ ] **2.1 iPhone** — `docs/design/iphone/project/`: PH_Movies (Grid, tweak list/offline/menu), PH_MoviesAdd → Add a Source, PH_PlexSignIn, PH_MovieTracks thay PH_MovieAudio + PH_MovieSubtitles, player nút "Audio & Subtitles".
  - Kiểm tra: `Tools/design-board render … --dark`
- [ ] **2.2 iPad, Duo, Mac** — cùng bộ, giao agent theo thiết bị.
- [ ] **2.3 Publish + commit**, trả lời thread comment rồi resolve.

## Ngoài phạm vi
- Chọn chất lượng khi tải Plex (D5) · poster TMDB (D6) — để sau.
