# FS-24.13 — Theo thiết bị: iPhone, iPad, Duo, Mac

`FS-24.13` · board: mọi board "Media hub · …" trên 4 canvas (`docs/design/<iphone|ipad|duo|mac>/project/`) · cập nhật 2026-10-16

**Một câu:** cùng một hub trên năm màn hình; điện thoại có đủ mọi chức năng của iPad (NF-05 §1.1), màn rộng thêm nội
dung chứ không phóng to, màn thấp giữ ngân sách chiều cao.

## 1. iPhone 402×874

- Tab bar §01.2, mini player trên tab bar, lưới 2 cột cho Utilities và Sources, kệ kéo ngang ở Movies/Music.
- Now Playing toàn màn, kéo xuống để đóng. Hai nhánh iOS 26 / 17–25 làm cùng việc (NF-05 §1.6), kiểm bằng dump.

## 2. iPad (FS-21: sidebar 320 · nội dung · inspector 360)

- Đầu sidebar: segmented **Photos · Movies · Music** (cao 36, FS-21.01 §1), dưới là nhóm của tab đó; Search là ô toolbar.
- Sidebar Photos (board `Main`): **Library** · **Collections** · nhóm **Pinned** (mặc định On This Day · All Photos ·
  Favorites · Videos · RAW · Recently Added — người dùng 15/10) · **Albums** › · **Utilities** (13 hàng như [03 §3](03-photos-tab.md)) · **Sources**.
- Sidebar Movies (board `IP_Movies`): Home · Movies · TV Shows · Clips · Utilities (6) · Sources. Nội dung Home có chip và kệ như iPhone.
- Sidebar Music (board `IP_Music`): Home · Albums · Artists · Songs · Playlists (từng playlist) · Utilities (6) · Sources.
- Đổi đoạn Photos/Movies/Music = đổi tab: giữ hàng đang chọn và chỗ cuộn của từng tab.
- Mini player ở chân sidebar (§01.4). **Chốt 2026-10-16 (A17):** khi sidebar **phủ** lên nội dung (cửa sổ 700–1099pt) mini
  player nằm ở **đáy vùng nội dung**, viên 360×56 bo 28, giữa bề rộng nội dung, đáy cách mép 20 — không theo sidebar khi sidebar
  trượt ra/vào, không có bản thứ hai trên toolbar. Board iPad mới vẽ sidebar ghim; trạng thái phủ vẽ thêm (README §5).
- Collections iPad: Utilities 4 cột, Sources 6 ô một hàng (board `IP_Collections`). Music Statistics 3 cột (`IP_MusicStats`).
- Split View < 700pt: bố cục iPhone (FS-21.01).

## 3. Duo

| | Màn trong 951×669 (regular, thấp) | Màn ngoài 466×678 (scene 382×644, rail hệ thống 84pt phải) |
|---|---|---|
| Điều hướng | rail dọc 68pt bên phải: Photos · Movies · Music, Search 52 ở đáy rail (board `Main`) | tab bar hệ thống trong dải 84pt |
| Library | ⚙ + ngày, segmented Library \| Collections (300×36) | segmented dưới mũ (350×36) |
| Collections | Utilities 4 cột, hero theo luật cửa sổ thấp (187pt) | Utilities 2 cột, Media Types cuộn ngang |
| Movies | Home chip một hàng; See All 7 cột | chip hai hàng; poster 3; **không +** |
| Music | Playlists 3 cột, Recently Added 6 album | Playlists dạng danh sách; ⋯ không + |
| Settings › Sources & Backup | hai cột trong pane | một cột 382 |
| Mini player | 360×52 | 350×52 |

- Gập/mở máy: giữ tab, chỗ cuộn, hàng đợi, giờ đang phát; nhạc **không** dừng khi gập (khác phim: phim giữ vị trí FS-23.02 §4).
- Không lái Duo bằng tool MCP simulator (CLAUDE.md); chứng minh bằng `Tools/ui-drive` + `Tools/sim-shot inner|cover`.

## 4. Mac (FS-18, chưa có target)

- Sidebar kính 228 (DESIGN §10b): bốn nhóm thu gọn được **Photos · Movies · Music · Sources**, mỗi nhóm có nút + riêng
  (New Album · Add Movie Files · Add Music Files · Add Source). Photos: Library · Collections · On This Day · Favorites ·
  Albums › · Media Types › · Utilities › (13 hàng, có On Server, On This Mac). Movies: Home · Movies · TV Shows · Clips ·
  Utilities ›. Music: Albums · Artists · Songs · Playlists › · Utilities ›. Sources: từng nguồn, Offline, Eject.
- Now Playing ở chân sidebar (trên dòng trạng thái index); nhấp đúp mở cửa sổ Now Playing.
- Thanh menu, phím: [01 §5](01-navigation-and-shell.md). Lệnh **Keep on Mac** trong menu Image và menu chuột phải (`MAC_ContextMenu`).
- Filter and Sort popover thêm Source và Kept on Mac (`MAC_FilterPopover`).
- Mac có nhạc cùng lúc với iPhone, iPad (intent câu 9) — nhưng chưa có target Mac; AC Mac để `⚠️ chưa có` tới khi FS-18 có code.

## 5. Truy cập (mọi thiết bị)

- Mini player, rail, segmented sidebar là control tự vẽ: nhãn và trait theo trạng thái (`Pause` / `Play`, `Photos, selected`).
- Thanh tua Now Playing là control điều chỉnh, mỗi bước 10 s; lời bài có giờ đọc từng dòng.
- Ở cỡ chữ accessibility: nhãn tab pre-26 bỏ (DESIGN §13); mini player cao theo chữ, không cắt tên bài; ô Utilities xuống 1 cột.
