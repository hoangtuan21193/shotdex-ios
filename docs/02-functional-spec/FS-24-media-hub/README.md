# FS-24 — Media hub: Photos · Movies · Music · Search

`FS-24` · tier A/B/C theo phần · mã hiện có: `ShotDex/App/RootTabView.swift`, `Features/Albums/`, `Features/Movies/`,
`Data/Sources/ImportedMusicStore.swift`; mới (đề xuất): `Features/Music/`, `Data/Music/`, `Domain/Music/` · test: đề xuất
`ShotDexTests/Music*Tests.swift`, `GlobalSearch*Tests.swift`, `Keep*Tests.swift` · cập nhật 2026-10-16

**Một câu:** ShotDex thành app quản lý media cá nhân — ba tab Photos, Movies, Music và một Search chung; nhạc trên máy,
NAS và Plex nghe được (cả khi khoá máy), mọi thứ mang đi offline bằng một nút Keep on iPhone; phần ảnh giữ nguyên độ sâu.

Nguồn: [intent 2026-10-15-media-hub](../../_intents/2026-10-15-media-hub.md) (accepted, câu 1–12 đã trả lời). Board: mọi board tiêu đề
"Media hub · …" trên 4 canvas, liệt kê theo thiết bị ở [§5](#5-board). Board là nguồn đúng cho UI; spec lệch board thì ghi ⚠️.

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 01 | [Khung app](01-navigation-and-shell.md) | 3 tab + Search, ⚙, mini player, hai nhánh iOS, theo thiết bị, thanh menu Mac |
| 02 | [Cái gì dời đi đâu](02-what-moves.md) | bảng mọi lối vào hôm nay → chỗ mới; không mất chức năng nào |
| 03 | [Tab Photos](03-photos-tab.md) | Library \| Collections, Filter thêm Source/Kept, Utilities có Statistics, Sources |
| 04 | [Tab Movies](04-movies-tab.md) | kệ Movies · TV Shows · Clips, thẻ Review, Utilities; thay FS-23.01 §1, §4 |
| 05 | [Thư viện nhạc](05-music-library.md) | nguồn Files/NAS/Plex, đọc tag, duyệt, playlist, From Movies, gộp My Music |
| 06 | [Player nhạc](06-music-player.md) | hàng đợi, shuffle/repeat, gapless, sleep timer, lời bài, lock screen, chủ âm thanh |
| 07 | [Music › Statistics](07-music-statistics.md) | giờ nghe, nghệ sĩ, định dạng, nguồn, đếm lượt |
| 08 | [Search chung](08-search.md) | scope All · Photos · Movies · Music, nhóm kết quả, cú pháp ảnh, tìm trong tab |
| 09 | [Keep on iPhone](09-keep-on-device.md) | một nút offline cho ảnh, album, phim, clip, playlist; dung lượng; gỡ |
| 10 | [Convert, Extract Audio](10-convert-extract-audio.md) | đổi sang MP4, tách tiếng thành bài nhạc |
| 11 | [Settings › Sources & Backup](11-settings-sources-backup.md) | một hàng mỗi nguồn, Browse, Backup, Kept |
| 12 | [Dữ liệu](12-data.md) | thư mục, bảng mới, gộp My Music, riêng tư |
| 13 | [Theo thiết bị](13-devices.md) | iPhone, iPad sidebar theo tab, Duo trong/ngoài, Mac, truy cập |
| 14 | [Tiêu chí 1/4](14-acceptance-criteria.md) · [2/4](14b-acceptance-criteria.md) · [3/4](14c-acceptance-criteria.md) · [4/4](14d-acceptance-criteria.md) | AC-1…AC-137 (AC-102…137: các quyết định 2026-10-16 và spike S-M1) |

## 1. Người dùng cần gì

- Ảnh, phim, nhạc nằm rải ở Photos, Files, NAS; muốn xem, nghe, mang đi offline và sao lưu ở **một** app.
- Nghe nhạc trên NAS như nghe Apple Music: liên tục khi khoá máy, điều khiển từ lock screen và tai nghe.
- Mở app là thấy app làm ba loại media, không loại nào nằm trong góc tiện ích của loại khác.

## 2. Phạm vi

**Có:** khung 3 tab + Search; Photos = Library + Collections (Statistics vào Utilities); tab Movies từ FS-23; thư viện và
player nhạc (Files, NAS SMB/WebDAV/SFTP, Plex); Music Statistics; Search chung; Keep on iPhone cho mọi loại; Convert và
Extract Audio; Settings › Sources & Backup; gộp My Music của Video Studio; Now Playing cho cả phim.

**Cố ý không có:** nhạc app Music hệ thống, CarPlay, EQ, crossfade (intent câu 4, 6) · backup nhạc (câu 8) · tải từ
YouTube/streaming, bẻ DRM (pháp lý) · tra tag/lời/bìa trên mạng (riêng tư) · đồng bộ playlist, lượt nghe với Plex · chấm sao
nhạc (không có trên board) · nung phụ đề khi Convert.

## 3. Ràng buộc chung

| Mặt | Ràng buộc |
|---|---|
| Chỉ thêm | mọi lối vào hôm nay còn ([02](02-what-moves.md)); AC-2 đi hết bảng |
| Pháp lý | chỉ file người dùng tự có; DRM không phát, nói lý do |
| Dữ liệu | bảng riêng, không cột `photo_metadata` ([12](12-data.md), BD-02) |
| Dependency | không thêm: AVFoundation cho nhạc, VLCKit (đã có) chỉ cho phim; spike S-M1…M3 trước `/plan` |
| iOS | 17 tối thiểu; iOS 26 và 17–25 làm cùng việc (NF-05 §1.6); `Menu` không đặt trong phụ kiện tab bar 26 |
| Thiết bị | iPhone 402×874 · iPad 1376×1032 · Duo trong 951×669 (≤ 334pt khối không cuộn) · Duo ngoài 466×678 · Mac |
| Đĩa | Keep, Convert, Extract cần cỡ + 1 GB trống; không bao giờ tự xoá thứ đã Keep (NF-02) |
| Design trước code | board ở §5 là nguồn đúng; màn nào chưa có board thì vẽ trước khi code |
| Bắt đầu code | sau khi plan duyệt, FS-23 đóng và `Tools/gate` xanh (intent câu 11) |

## 3b. Quyết định đã chốt (2026-10-16)

Mọi câu hỏi mở (⚠️) của bản 2026-10-15 đã chốt sau 3 vòng planboard (`.planboard/fs24-media-hub/DECISIONS.md`); mỗi chỗ trong
spec ghi `Chốt 2026-10-16 (D#/A#)`. Tóm tắt:

| ID | Chốt | Ở đâu |
|---|---|---|
| D1 | vào Video Studio thì nhạc tự Pause, ra không tự phát lại | [06 §7](06-music-player.md) · AC-64 |
| D2 | Settings › Playback **Movie Audio in Background**, mặc định bật: khoá máy/chuyển app phim chạy tiếp chỉ tiếng; tắt = dừng như FS-23; PiP không đổi | [06 §6](06-music-player.md) · AC-102…107 |
| D3 | xin entitlement CarPlay ngay, bản đầu không làm CarPlay | [06 §9](06-music-player.md) |
| D4 | OGG/Opus/APE bỏ qua, đếm số file ở hàng nguồn | [05 §1](05-music-library.md) · AC-38 |
| D5 | chuyển video Photos → Movies xong thì hỏi bằng hộp xoá của hệ thống; Cancel giữ cả hai | [04 §3](04-movies-tab.md) · AC-16, 126, 127 |
| D6 | lệnh ngược là **Remove from iPhone/iPad/Mac** cho mọi loại | [09 §1](09-keep-on-device.md) · AC-19, 128 |
| D7 | Keep ảnh Photos hỏi **mỗi lần**: Originals (đầu) · Viewing Copies 2732 px HEIC · Cancel, có cỡ ≈; không cài đặt mặc định | [09 §2a](09-keep-on-device.md) · AC-77, 98, 108…117 |
| D8 | Source và Kept là bộ lọc tạm **và** luật Smart Album | [03 §2](03-photos-tab.md), FS-06.08 §2 · AC-118…121 |
| D9 | ô Statistics như mọi ô, không số tóm tắt | [03 §3](03-photos-tab.md) · AC-8 |
| D10 | iPhone Music Statistics đủ 8 thẻ | [07 §2](07-music-statistics.md) · AC-122 |
| D11 | Settings › Playback › **Clear Listening History…** có hỏi lại | [07 §3](07-music-statistics.md) · AC-123…125 |
| A1–A18 | Claude tự quyết (A1–A17 người dùng OK; A18 sau spike S-M1): token đáy 164 (A1), ẩn phụ kiện iOS 26 ở màn con (A2), component mini player 56/52 (A3), sửa FS-21.01 §2 (A4), Duo 669pt chấp nhận (A5), menu Controls Mac (A6), DESIGN §13 lưới Utilities (A7), Show As (A8), tự đọc FLAC (A9), spike S-M2 + dự phòng (A10), vẽ board thiếu trước `/plan` (A11), icon Keep (A12), tự đọc ID3v2 cho MP3, M4A giữ AVFoundation (A18, sau S-M1), Convert qua VLCKit + spike S-M3 (A13), nhóm Metadata/Drives/Cache trên iPhone/Duo (A14), ba bảng nguồn (A15), NF-03 §2c (A16), mini player khi sidebar iPad phủ (A17) | các phần 01–13 · AC-5, 6, 40, 86, 129…137 |

**Còn lại trước `/plan`:** board ở §5 đã vẽ đủ (PLAN mục 2); còn chạy spike S-M2, S-M3 ở §4 (PLAN mục 3; S-M1 đã xong, Đi). Không còn câu hỏi nào mở
trong spec; spike hỏng thì quay lại hỏi người dùng.

## 4. Spike trước `/plan`

| Spike | Hỏi | Chặn |
|---|---|---|
| S-M1 | **Đi** (2026-10-16, [báo cáo](../../_intents/2026-10-16-fs24-s-m1-flac-tags-spike.md)): tự đọc FLAC (A9) — byte qua mạng 734 KB → 8 KB/file, bền với khối hỏng; thêm bộ đọc ID3v2 cho MP3 (A18). Còn chưa đo: iOS 27, máy thật, NAS thật, 200 file thật | [05 §2](05-music-library.md) · AC-135…137 |
| S-M2 | AVFoundation phát qua cầu byte SMB/SFTP: tua, nối bài gapless, AirPlay, khoá máy; hỏng → dự phòng A10 | [06 §1](06-music-player.md) |
| S-M3 | VLCKit 4 alpha đưa khung + tiếng ra cho bộ mã hoá MP4, tốc độ ≥ 1× (A13); hỏng → hỏi lại | [10](10-convert-extract-audio.md) |

## 5. Board

Đủ theo PLAN mục 2 (2026-10-16): mọi màn ở §1–§13 có board trên cả 4 canvas; danh sách lấy từ `canvas.json`
(board có tiêu đề "Media hub · …"), theo thứ tự trên canvas. Canvas và link: [docs/design/README.md](../../design/README.md).

- **iPhone** (24): `Main` · `PH_Search` · `PH_Collections` · `PH_Statistics` · `PH_Movies` · `PH_HubMusic` · `PH_HubMusicStats` · `PH_HubSources` · `PH_NowPlaying` · `PH_UpNext` · `PH_Lyrics` · `PH_SleepTimer` · `PH_MusicAlbum` · `PH_MusicArtist` · `PH_MusicPlaylist` · `PH_MoviesReview` · `PH_WatchHistory` · `PH_Subtitles` · `PH_TVShow` · `PH_Convert` · `PH_ExtractAudio` · `PH_SettingsPlayback` · `PH_KeepPhotos` · `PH_Kept`.
- **iPad** (22; `Main` đã có từ trước, không mang tiêu đề "Media hub"): `IP_Search` · `IP_Collections` · `IP_Settings` · `IP_Movies` · `IP_Music` · `IP_MusicStats` · `IP_NowPlaying` · `IP_UpNext` · `IP_Lyrics` · `IP_SleepTimer` · `IP_MusicAlbum` · `IP_MusicArtist` · `IP_MusicPlaylist` · `IP_MoviesReview` · `IP_WatchHistory` · `IP_Subtitles` · `IP_TVShow` · `IP_Convert` · `IP_ExtractAudio` · `IP_SettingsPlayback` · `IP_KeepPhotos` · `IP_Kept`.
- **Duo** (49; `DI_` màn trong, `DC_` màn ngoài; Up Next màn trong là pane phải của `DI_NowPlaying`): `Main` · `DI_Search` · `DI_Collections` · `DI_Statistics` · `DC_Library` · `DC_Search` · `DC_Collections` · `DC_Statistics` · `DI_Movies` · `DI_MoviesHome` · `DI_Music` · `DI_MusicStats` · `DI_SourcesBackup` · `DC_Movies` · `DC_MoviesHome` · `DC_Music` · `DC_MusicStats` · `DC_SourcesBackup` · `DI_NowPlaying` · `DI_Lyrics` · `DI_SleepTimer` · `DI_MusicAlbum` · `DI_MusicArtist` · `DI_MusicPlaylist` · `DI_MoviesReview` · `DI_WatchHistory` · `DI_Subtitles` · `DI_TVShow` · `DI_Convert` · `DI_ExtractAudio` · `DI_SettingsPlayback` · `DI_KeepPhotos` · `DI_Kept` · `DC_NowPlaying` · `DC_UpNext` · `DC_Lyrics` · `DC_SleepTimer` · `DC_MusicAlbum` · `DC_MusicArtist` · `DC_MusicPlaylist` · `DC_MoviesReview` · `DC_WatchHistory` · `DC_Subtitles` · `DC_TVShow` · `DC_Convert` · `DC_ExtractAudio` · `DC_SettingsPlayback` · `DC_KeepPhotos` · `DC_Kept`.
- **Mac** (31; Settings › Playback nằm ở `MAC_SettingsGeneral`): `Main` · `MAC_Search` · `MAC_FilterPopover` · `MAC_ContextMenu` · `MAC_MenuBar` · `MAC_Collections` · `MAC_SmartAlbumEditor` · `MAC_Statistics` · `MAC_SettingsGeneral` · `MAC_SettingsSources` · `MAC_Movies` · `MAC_SettingsSourcesBackup` · `MAC_MoviesHome` · `MAC_Music` · `MAC_MusicStatistics` · `MAC_SearchAll` · `MAC_MoviesReview` · `MAC_WatchHistory` · `MAC_Subtitles` · `MAC_TVShow` · `MAC_Convert` · `MAC_ExtractAudio` · `MAC_NowPlaying` · `MAC_UpNext` · `MAC_Lyrics` · `MAC_SleepTimer` · `MAC_MusicAlbum` · `MAC_MusicArtist` · `MAC_MusicPlaylist` · `MAC_KeepPhotos` · `MAC_Kept`.

Board khác đã sửa theo FS-24 mà tiêu đề không mang "Media hub": Smart Album editor (`PH_SmartAlbumEditor`, `IP_SmartAlbumEditor`,
`MAC_SmartAlbumEditor`, Duo tương ứng), trang phim `*_MovieDetail` (Keep on / Keeping / Kept on ‹thiết bị›). Năm mặc định nhỏ ở
intent mục 12 (Pinned iPad, On Server, số ảnh + Offline + thẻ nhớ ở Sources, tên Sources & Backup, mini player chỉ ở màn gốc)
đã viết vào spec như đã chốt.

## 6. Tài liệu khác phải đổi khi duyệt

| Tài liệu | Đổi |
|---|---|
| FS-23.01 §1, §4, §5, §6 · FS-23.02 §4 · FS-23.07 · FS-23.08 | lối vào là tab Movies; trang chủ có kệ; **đã sửa 2026-10-16:** chữ Download → Keep on iPhone / Remove from iPhone (D6), phim chạy tiếp tiếng ở nền (D2) |
| FS-21.01 §2 | sidebar iPad theo tab — **đã sửa 2026-10-16** (A4) |
| FS-06.01 §2 | thứ tự Collections, People and Pets/Network tắt sẵn; Utilities dạng lưới |
| FS-07 README | lối vào Statistics |
| FS-08.01b | hàng Sources → Sources & Backup; câu chân trang |
| FS-12.08 §3 | My Music → thư viện Music |
| NF-03 §2c | Plex nhạc — **đã sửa 2026-10-16** (A16) |
| DESIGN.md | §6 khoảng đáy mini player + số đo mini player · §8 icon Keep · §9 component mini player · §13 lưới Utilities/Sources — **đã sửa 2026-10-16** (A1, A3, A7, A12) |
| FS-06.08 §2 | trường Source, Kept on iPhone trong rule builder — **đã sửa 2026-10-16** (D8) |
| FS-08.03 §3 | Playback thêm Movie Audio in Background, Clear Listening History… — **đã sửa 2026-10-16** (D2, D11) |
| OV-01 | viết lại mục tiêu sản phẩm (intent Outcome) — việc của `/plan` |
| BD-02 §3 | đăng ký bảng mới khi làm migration |

## 7. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| AVFoundation không đọc byte qua SMB như mong đợi | spike S-M2; phương án dự phòng ở 06 §1 |
| Phụ kiện tab bar iOS 26 hiện ở màn con | bỏ phụ kiện khi push (A2, 01 §2); AC-5 kiểm cả 26.5 |
| Bản xem 2732 px không sửa/xuất được khi offline | hộp D7 nói rõ hai bản; đường tải bản gốc hiện có xử lý (09 §2a) |
| hub to, một lần làm | `/plan` chia task theo phần 01–13, mỗi AC một commit |
