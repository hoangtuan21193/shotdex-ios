# FS-24.05 — Thư viện nhạc: nguồn, tag, duyệt, playlist

`FS-24.05` · tier B (lưới album) + A (danh sách bài, playlist) · board iPhone `PH_HubMusic` · iPad `IP_Music` · Duo
`DI_Music` / `DC_Music` · Mac `MAC_Music`; trang album iPhone `PH_MusicAlbum` · iPad `IP_MusicAlbum` · Duo `DI_MusicAlbum` / `DC_MusicAlbum` · Mac `MAC_MusicAlbum`; nghệ sĩ iPhone `PH_MusicArtist` · iPad `IP_MusicArtist` · Duo `DI_MusicArtist` / `DC_MusicArtist` · Mac `MAC_MusicArtist`; playlist iPhone `PH_MusicPlaylist` · iPad `IP_MusicPlaylist` · Duo `DI_MusicPlaylist` / `DC_MusicPlaylist` · Mac `MAC_MusicPlaylist` · cập nhật 2026-10-16

**Một câu:** tab Music là thư viện chung của nhạc người dùng tự có — file chép vào máy, thư mục trên NAS, máy chủ
Plex — đọc tag để duyệt theo album, nghệ sĩ, bài, playlist; ở nhà nghe thẳng từ nguồn, cần mang đi thì Keep on iPhone.

## 1. Nguồn

| Nguồn | Thêm ở | Bài vào thư viện |
|---|---|---|
| Thư mục trên connection FS-15 (SMB, SFTP, WebDAV) hoặc thư mục Files | + › Add a Source… › Folder | mọi file nhạc trong thư mục và thư mục con, quét lại khi mở Music |
| Máy chủ Plex | + › Add a Source… › Plex Server | thư viện Music của máy chủ; cùng đăng nhập với Movies ([FS-23.07](../FS-23-offline-movies/07-plex.md)) |
| File chép thẳng ("Files") | + › Add Music Files… (Files), Share sheet / AirDrop | chép ngay vào máy, coi như đã Keep |

- Một connection hay một máy chủ Plex chỉ đăng nhập **một lần** cho cả ảnh, phim, nhạc; thêm thư mục nhạc trên NAS
  Home đã có thì không hỏi lại mật khẩu. Nguồn quản lý ở Settings › Sources & Backup ([11](11-settings-sources-backup.md)).
- Đuôi nhận: mp3, m4a, aac, alac (trong m4a), flac, wav, aif/aiff, caf. Phát bằng AVFoundation (intent câu 5).
- File khác (ogg, opus, ape, wma, dsf) **không vào thư viện**; hàng nguồn ghi `14 files can't be played` (chạm → danh sách
  tên file). Bài Apple Music có DRM (m4p) cũng vậy, kèm lý do `Protected by Apple Music`.
  **Chốt 2026-10-16 (D4):** bản đầu bỏ qua OGG/Opus/APE (và wma, dsf), không phát qua VLCKit; số file chưa hỗ trợ ghi rõ ở
  hàng nguồn trong Settings › Sources & Backup (như trên). Làm sau nếu người dùng thật sự có nhiều file loại này.
- Quét giống Movies (FS-23.01 §2): đi sâu tối đa 8 tầng, bỏ thư mục ẩn và thư mục rác của NAS, một thư mục con không trả
  lời thì không ẩn gì. Nguồn thôi liệt kê một bài: bài đã Keep ở lại có nhãn; bài stream ẩn và giữ 30 ngày (như phim).

## 2. Đọc tag

- Đọc: title · artist · album artist · album · số bài/số đĩa · năm · thể loại · compilation · thời lượng · codec · tần số
  mẫu · số bit · ảnh bìa nhúng · lời bài (USLT/©lyr). Plex: lấy từ Plex, không đọc file.
- **Qua mạng chỉ đọc đầu và đuôi file**: ≤ 256 KB đầu (ID3v2, khối metadata FLAC, `moov` đặt trước) + ≤ 128 KB cuối
  (ID3v1, `moov` đặt sau). Không bao giờ tải cả bài để đọc tag. Ảnh bìa **không** nằm trong ngân sách: ghi vị trí, đọc riêng
  một khối khi cần cache. Giữ được với FLAC và MP3 (bộ đọc tự viết); M4A là ngoại lệ đã nhận (A18, dưới).
- **Chốt 2026-10-16 (A9, spike S-M1 — [báo cáo](../../_intents/2026-10-16-fs24-s-m1-flac-tags-spike.md), Đi):** **FLAC: ShotDex tự
  đọc khối metadata** (STREAMINFO, VORBIS_COMMENT, PICTURE) — *vì AVFoundation đọc trọn ảnh bìa trước khi trả tag (đo: TB
  734 KB/file qua mạng so với 8 KB), một độ dài khối hỏng làm mất hết tag hoặc cả file, FLAC có ID3 dán trước thì mất hết
  Vorbis comment.*
  - Lần đọc đầu 8 KB, đọc thêm chỉ khi khối cần nằm ngoài phần đã có; ID3v2 dán trước `fLaC` (có cờ footer) được bỏ qua; duyệt
    khối tới cờ `last`, trần 128 khối; khối khai độ dài vượt file → dừng, **giữ** những gì đã đọc.
  - **STREAMINFO**: tần số, số kênh, số bit, tổng mẫu → thời lượng **chính xác** (không dùng `AVAsset.duration` cho FLAC, nó
    làm tròn lên khối).
  - **VORBIS_COMMENT**: kiểm từng độ dài với cuối khối (số comment khai sai không treo, không cấp phát lớn); UTF-8 khoan dung
    (byte hỏng → U+FFFD). Khoá: `TITLE`, `ARTIST` (nhiều giá trị → nối `, `), `ALBUM`, `ALBUMARTIST`/`ALBUM ARTIST`,
    `TRACKNUMBER` (`3`, `03`, `3/12`) + `TRACKTOTAL`/`TOTALTRACKS`, `DISCNUMBER` + `DISCTOTAL`/`TOTALDISCS`, `DATE` (4 số đầu
    làm năm), `GENRE`, `COMPILATION`, `LYRICS`, rồi `UNSYNCEDLYRICS`.
  - **PICTURE**: chỉ đọc phần cố định (type, MIME, mô tả, rộng, cao), ghi `offset + length` của dữ liệu ảnh; chọn type 3
    (Front), không có thì ảnh đầu. Ảnh tải **lười**, một lần **mỗi album** khi cần cache (không mỗi bài).
  - SEEKTABLE, PADDING, APPLICATION, CUESHEET: nhảy qua. Chưa làm ở v1: `METADATA_BLOCK_PICTURE` base64 (kiểu Ogg), CUESHEET.
- **Chốt 2026-10-16 (A18, Claude quyết sau S-M1):** **MP3: ShotDex cũng tự đọc ID3v2** (v2.3/v2.4, định dạng mở, cùng kiểu bộ
  đọc FLAC) để lần quét tag nằm trong ngân sách 256 KB đầu + 128 KB cuối: frame `APIC` chỉ ghi vị trí, ảnh tải lười như FLAC
  (đo S-M1: AVFoundation đọc 2,1 MB cho MP3 có bìa 2 MB). Frame text v2.4 nhiều giá trị (ngăn bằng NUL) → nối `, `; lời bài
  từ `USLT`; ID3v1 ở đuôi chỉ dùng khi không có ID3v2.
  - **M4A/ALAC, AIFF, WAV có chunk `ID3`: AVFoundation** (`load(.metadata)`, lọc theo `identifier`; **không dùng
    `.commonMetadata`** — thiếu album artist/năm/số bài). Tự giải `trkn`/`disk` (8 byte: số ở byte 2–3, tổng ở 4–5).
    **M4A có bìa nhúng lớn vượt ngân sách** (AVFoundation đọc cả `covr`, đo 2,2 MB với bìa 2 MB) — **chấp nhận**: quét một
    lần, cache theo `modificationDate` + cỡ, chỉ quét lại khi file đổi.
  - **WAV chỉ có RIFF INFO**: iOS 26.5 không trả gì → tên bài từ tên file như "Thiếu tag" bên dưới.
  - Thời lượng: STREAMINFO cho FLAC; `AVAsset.duration` cho phần còn lại (sai ≤ 50 ms, không đáng kể cho UI).
- **Hỏng**: một PICTURE / comment / frame khai sai độ dài không làm mất các tag còn lại, không dừng lần quét và không chặn
  hàng đợi (bài đó phát được nếu AVFoundation mở được; không thì bị bỏ qua như bài không tới được). File AVFoundation
  không mở được để phát (đo: FLAC có PICTURE khai sai độ dài — tag đọc được, phát thì không) vào danh sách `N files can't be
  played` với lý do `Damaged file`.
- **Fixture test** có chữ ngoài ASCII phải tạo bằng `metaflac --no-utf8-convert` (hoặc `LC_ALL=en_US.UTF-8`) và so với
  chuỗi gốc — không thì `metaflac` thay ký tự bằng `#` và test xanh trên dữ liệu đã hỏng (S-M1 §6).
- Thiếu tag: tên bài từ tên file (`03 - Holocene.flac` → `Holocene`, số bài 3), album từ tên thư mục, nghệ sĩ
  `Unknown Artist`. Không gọi dịch vụ tra tag nào trên mạng (riêng tư, giấy phép).
- Gom nhóm: album = (album artist, hoặc artist khi trống) + tên album; compilation → `Various Artists`. So khớp bỏ
  hoa-thường, dấu, khoảng trắng thừa. Album và nghệ sĩ tính bằng truy vấn trên bảng bài, không lưu bảng riêng.
- Ảnh bìa: nhúng → `cover.jpg`/`folder.jpg` cạnh bài → ô chữ màu theo tên (như poster phim). Cache 600 px trong
  `Caches/MusicArt`, có trần chung với cache ảnh nguồn (NF-02 §2).
- `.lrc` cùng tên cạnh bài: ghi đường dẫn, tải khi mở Lyrics ([06 §5](06-music-player.md)).

## 3. Màn Music

- Đầu: ô **Search Music** (tên bài, nghệ sĩ, album; chạy offline) · chip **Albums · Artists · Songs · Playlists · On This
  iPhone** (một chip một lúc; chạm chip đang chọn = về trang chủ).
- Trang chủ, thứ tự cố định: **Playlists** (See All) · **Recently Added** (album, See All) · **Utilities** · **Sources**.
- Utilities (lưới 2 cột icon + tên, như Photos): **Statistics** ([07](07-music-statistics.md)) · **On This iPhone** ·
  **Recently Played** · **Most Played** · **Lyrics** (bài có lời) · **Duplicates** (cùng title + artist + thời lượng ± 2 s).
- Sources: ô 2 cột cho nguồn **có nhạc** (NAS Home, Plex — Living Room, Files) + **Add Source…**; nguồn không tới được
  mờ với nhãn `Offline`.
- ⋯: Grid/List · Sort By (**Recently Added** mặc định · Title · Artist · Year) · Select. **+**: Add a Source… · Add Music Files….
- Album: lưới bìa vuông (iPhone 3 cột ở Recently Added kéo ngang; See All 2 cột), dưới là tên + nghệ sĩ. Trang album:
  bìa, tên, nghệ sĩ, năm · số bài · tổng thời lượng, **Play** · **Shuffle**, danh sách bài theo đĩa/số bài.
- Hàng bài: số/bìa nhỏ · tên · nghệ sĩ · thời lượng · ✓ nếu đã Keep · menu (Play Next · Add to Queue · Add to Playlist… ·
  Keep on iPhone / Remove from iPhone · Go to Album · Go to Artist · Show Lyrics). Bài stream của nguồn offline: mờ, chạm báo
  `Not available offline. Connect to NAS Home to play.` (cùng câu với phim).
- Rỗng: `No Music` · "Add a music folder on your NAS or a Plex server, or copy music files to this iPhone." · **Add a Source**.

## 4. Playlist

- Playlist của người dùng: **New Playlist** (+ trong Playlists, hoặc Add to Playlist… › New Playlist…), đặt tên, thêm bài
  từ mọi nguồn, kéo để sắp lại, vuốt để bỏ một bài, Rename, Delete (alert 2 nút; bài không bị xoá khỏi nguồn).
- Dòng phụ dưới tên: `48 songs · on iPhone, 412 MB` khi đã Keep cả playlist, `31 songs · NAS Home` khi một nguồn,
  `31 songs · 2 sources` khi nhiều nguồn.
- **From Movies**: playlist hệ thống, tự có khi Extract Audio ra bài đầu tiên ([10](10-convert-extract-audio.md));
  dòng phụ `6 tracks · extracted from your videos`; đổi tên, xoá bài được, không xoá được chính playlist khi còn bài.
- **Road Trip** trên board là playlist người dùng; không có playlist mẫu nào được tạo sẵn.
- Playlist từ Plex: không đồng bộ ở v1 — *vì Plex lưu playlist theo tài khoản, sửa hai chiều cần luật xung đột riêng.*

## 5. Gộp My Music của Video Studio

- Một kho nhạc (intent câu 7). Lần chạy đầu sau migration: mọi file trong thư mục nhạc đã import của Video Studio được
  **chuyển** vào kho Files của Music, thành bài đã Keep; manifest tên cũ thành title khi file không có tag.
- Panel Music của Video Studio (FS-12.08 §3) giữ dòng Video sound và nút **Add Music from Files…**; section **My Music**
  đổi thành danh sách **từ thư viện Music**: Playlists (có From Movies) · Recently Added · Search. Bài thêm từ Files ở
  đây vào thư viện Music như Add Music Files….
- Chỉ bài **trên máy** (Keep hoặc Files) dùng được làm nhạc nền; bài stream có nút **Keep on iPhone** ngay trong hàng —
  *vì export video đọc file nhiều lần, không chịu được mạng đứt giữa chừng.*
- Xoá một bài trong panel Video Studio không còn nữa (trước đây xoá file import); xoá ở thư viện Music.

## 6. Cố ý không có

- Nhạc của app Music hệ thống (`MPMediaLibrary`) — intent câu 4, để sau.
- Tải nhạc từ YouTube hay dịch vụ streaming; bẻ DRM — *ToS, bản quyền, App Store.*
- Tra tag/ảnh bìa trên mạng (MusicBrainz, Last.fm) — *riêng tư; giấy phép ảnh bìa.*
- Chấm sao, Love — *không có trên board; thêm thì vẽ trước.* EQ, CarPlay — intent câu 6.
- Backup nhạc lên NAS — intent câu 8.
