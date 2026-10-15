# FS-24.01 — Khung app: tab Photos · Movies · Music · Search, mini player

`FS-24.01` · tier C (tab bar, mini player) · mã hiện có: `ShotDex/App/RootTabView.swift`, `App/Glass/LiquidGlassTabBar.swift`,
`App/AppNavigation.swift` · board iPhone `Main` · iPad `Main` · Duo `Main` / `DC_Library` · Mac `Main`, `MAC_MenuBar` ·
cập nhật 2026-10-16

**Một câu:** gốc app có ba tab loại media và một Search chung; mỗi tab có ⚙ Settings ở góc trái; một mini player nổi
cho biết đang phát gì và dừng/chuyển bài được từ màn gốc của mọi tab.

## 1. Tab

| Tab | Glyph | Màn gốc | Thay cho (code hiện tại) |
|---|---|---|---|
| **Photos** | `photo.on.rectangle` | segmented **Library \| Collections** ([03](03-photos-tab.md)) | tab Library + tab Collections |
| **Movies** | `play.rectangle` (cùng glyph ô Movies FS-23.01 §1) | trang chủ Movies ([04](04-movies-tab.md)) | ô Movies trong Utilities |
| **Music** | `music.note` | trang chủ Music ([05](05-music-library.md)) | — (mới) |
| **Search** | `magnifyingglass` | Search chung ([08](08-search.md)) | tab Search (chỉ ảnh) |

- Tab **Statistics** không còn là tab: nó là ô đầu của Photos › Collections › Utilities ([02](02-what-moves.md)).
- Tiêu đề lớn của màn gốc là tên tab (`Photos` thì tên đoạn đang chọn: Library hay Collections, như board), **không** dòng
  đếm dưới tiêu đề. Leading: **⚙** mở Settings toàn màn (như hôm nay). Trailing theo tab ([03](03-photos-tab.md)–[05](05-music-library.md)).
- Mở app: tab cuối cùng người dùng ở (khôi phục trạng thái FS-01.07); lần đầu là Photos › Library.
- Đổi tab giữ nguyên chồng màn và chỗ cuộn của từng tab; chạm lại tab đang chọn = về màn gốc, chạm lần nữa = cuộn lên đầu.
- Deep link và Share/AirDrop: phim → tab Movies; nhạc → tab Music; ảnh → Photos (thay đường đi qua Collections hiện tại).

## 2. Hai nhánh iPhone

| | iOS 26+ | iOS 17–25 |
|---|---|---|
| Tab bar | tab bar hệ thống, Search là tab vai trò tìm kiếm (vòng tròn tách riêng) | thanh kính tự vẽ: viên 3 tab + vòng Search 62pt (board `Main`) |
| Mini player | phụ kiện đáy của tab bar hệ thống | viên kính 362×56 bo 28, cách mép 20, nằm **trên** tab bar (board `Main`, y 710) |
| Khoảng trống đáy cho nội dung cuộn | hệ thống tự chừa (token 8 như hôm nay) | **100** khi không có mini player, **164** khi mini player hiện (A1) |

- Số tab không đổi (3 + Search như hôm nay), nên thanh tự vẽ giữ hình học; nhãn bỏ ở cỡ chữ accessibility như luật
  DESIGN §13. Không có xung đột số tab ở nhánh trước 26.
- **Chốt 2026-10-16 (A1):** khoảng đáy trước 26 có **hai** token cạnh nhau trong DESIGN §6 — `bottomChromeClearance` (100,
  không đổi) và token mới `bottomChromeClearanceWithMiniPlayer` = **164** (100 + mini player 56 + khe 8), dùng khi mini player
  hiện. Màn cuộn đọc token qua một chỗ (không tự viết nhánh); mini player ẩn/hiện thì khoảng đáy đổi theo, không giữ 164 khi
  không phát gì. iOS 26: cả hai token là 8 (hệ thống tự chừa phụ kiện).
- **Chốt 2026-10-16 (A2):** iOS 26 bỏ phụ kiện đáy khi đẩy màn con và gắn lại khi về màn gốc — đúng luật "mini player chỉ ở
  màn gốc của tab" (intent mục 12), cùng hành vi với nhánh trước 26. Phụ kiện nhảy ra/vào mỗi lần push là cái giá đã nhận.
- Trong phụ kiện iOS 26 **không** dùng `Menu` và không đặt bề rộng cứng cho hàng (memory `ios26-accessory-menu-limits`):
  mini player chỉ có nút chạm, menu bài nằm ở Now Playing.

## 3. Mini player

- Nội dung: bìa 44 bo 8 · tên bài (1 dòng, cắt cuối) · `nghệ sĩ · nguồn` (`Bon Iver · NAS Home`) · **Pause/Play** · **Next**.
  VoiceOver: nhóm `Now Playing: Holocene, Bon Iver`, hai nút `Pause`, `Next Song`.
- Hiện khi hàng đợi nhạc có bài (đang phát hoặc đang dừng); ẩn khi hàng đợi trống hoặc sau **Stop** trong Now Playing.
- Chỉ ở **màn gốc** của tab Photos, Movies, Music, Search (người dùng 15/10): không che màn con, sheet, alert, Viewer,
  editor, player phim, chế độ chọn ảnh (tab bar ẩn thì mini player cũng ẩn).
- Chạm vùng chữ/bìa → Now Playing toàn màn ([06](06-music-player.md)); vuốt lên trên viên cũng mở.
- **Chốt 2026-10-16 (A3):** mini player là component dùng chung mới (`MiniPlayerBar`, DESIGN §9): cao **56** trên iPhone và
  iPad, **52** trên Duo (trong và ngoài), kính qua `.glassBackground(Capsule())`; hai số đo ở DESIGN §6. Board giữ nguyên.
- Phim đang phát toàn màn thì không có mini player (phim có Now Playing riêng trên lock screen, [06 §6](06-music-player.md)).

## 4. Theo thiết bị

| Thiết bị | Điều hướng | Mini player |
|---|---|---|
| iPhone, Split View < 700pt | tab bar §2 | §2 |
| iPad ≥ 700pt (FS-21.01) | đầu sidebar: công tắc **Photos · Movies · Music** (segmented 3 đoạn) đổi nội dung sidebar; Search là ô trên toolbar | chân sidebar, rộng hết sidebar (304), cao 56, bo 16, trên dòng trạng thái index |
| Duo trong 951×669 | rail dọc phải 68pt: Photos · Movies · Music + vòng Search 52 ở đáy rail | viên 360×52 bo 26, giữa vùng nội dung, đáy cách mép 12 (board `Main`, y 605) |
| Duo ngoài 466×678 | tab bar hệ thống trong dải 84pt bên phải (như hôm nay) | viên 350×52 trong cột 382, đáy cách mép 20 (board `DC_Library`) |
| Mac | sidebar bốn nhóm thu gọn được: **Photos · Movies · Music · Sources**; Search trên toolbar | chân sidebar ([13 §4](13-devices.md)) |

- iPad sidebar theo tab ([13 §2](13-devices.md)): Photos = Library · Collections · Pinned · Albums · Utilities · Sources;
  Movies = Home · Movies · TV Shows · Clips · Utilities · Sources; Music = Home · Albums · Artists · Songs · Playlists ·
  Utilities · Sources. Mỗi nhóm Sources chỉ liệt kê nguồn có loại media đó.
- **Chốt 2026-10-16 (A4):** FS-21.01 §2 (sidebar iPad cũ, chưa có code) đã viết lại theo sidebar theo tab ở trên, trong
  cùng commit spec này; [FS-21.01 §2](../FS-21-ipad-mac-style/01-shell.md) trỏ về đây.
- Duo ngoài **chỉ phát**, không thêm nguồn (FS-23.02 §4): không có **+** ở Movies và Music; ⋯ chỉ View/Sort.
- **Chốt 2026-10-16 (A5):** Duo trong cao 669pt, ngân sách khối không cuộn ≤ 334pt (NF-05 §4). Đo trên board: header
  Library (⚙, ngày, Select, segmented 36) ~108pt + mini player 52 + lề 12 = **172pt**; Statistics và Movies Home thêm hàng
  chip ~44pt → 216pt; Search có ô + scope 88pt → **260pt**. Chấp nhận: mini player giữ 52, còn dư ≥ 74pt; không thêm số đo
  thấp. AC-95 đo lại trên dump.

## 5. Mac: thanh menu (board `MAC_MenuBar`)

- **Go**: nhóm Photos (Library ⌥⌘1 · Favorites ⌥⌘2 · Videos ⌥⌘3 · RAW ⌥⌘4 · Recently Added ⌥⌘5 · Collections · On This Day ·
  Albums · Statistics ⌥⌘6 · Photos Utilities ›) · nhóm Movies (Movies ⌥⌘7 · Movie Utilities ›) · nhóm Music (Music ⌥⌘8 ·
  Playlists › · Now Playing).
- **File**: thêm Add Movie Files… · Add Music Files…. **Image** (ảnh) và menu chuột phải: thêm **Keep on Mac**.
- **Chốt 2026-10-16 (A6):** thêm menu **Controls** (sau Image, trước Go): mục đầu đổi tên theo trạng thái — **Pause** khi đang phát, **Play** khi đang dừng (Space khi không có ô nhập hay ảnh
  nào đang dùng Space) · **Next** ⌘→ · **Previous** ⌘← · **Shuffle** (dấu ✓ khi bật) · **Repeat ›** Off · All · One — kiểu
  app Music. Phím media của bàn phím vẫn đi qua Now Playing hệ thống. Board `MAC_MenuBar` đã vẽ lại (menu Controls mở, mục đầu `Pause` vì đang phát).
