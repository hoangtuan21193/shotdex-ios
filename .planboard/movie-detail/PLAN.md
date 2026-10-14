# Movies: trang chi tiết phim — plan thực thi

> Chốt ngày 2026-10-15, sau 1 vòng · nguồn: .planboard/movie-detail/plan.json

## Việc cần làm
- [x] **1 Spec + board** — FS-23.08, AC-59…66; PH/IP/DI/DC/MAC_MovieDetail + canvas.json
- [ ] **2 Track âm thanh trước khi phát** — MatroskaSubtitleReader đọc cả track audio; Plex audio streams; AVAsset; id `file:n`; player khớp `file:n` — `Domain/Movies`, `Data/Movies`, `MoviePlayerModel`
  - Kiểm tra: `/test MovieAudioTrackTests` + test mới
- [ ] **3 Ảnh nền Plex** — migration v38 `artPath`, PlexLibrarySync lưu `art`, MoviePosterLoader tải ảnh nền
- [ ] **4 MovieDetailScreen + MovieDetailModel** — đẩy từ MoviesScreen; Resume/Play/From Beginning; Download/Remove/Retry; ⋯; Audio/Subtitles mở MovieTracksPanel qua engine dò; Version (Plex)
- [ ] **5 Long-press thêm Play; Duo ngoài rút gọn; iPad/Duo trong hai cột**
- [ ] **6 Test + ui-drive + design-parity** — AC-59…66; iOS 26.5 và 18.6; iPhone, iPad, Duo
