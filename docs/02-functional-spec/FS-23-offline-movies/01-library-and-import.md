# FS-23.01 — Thư viện phim: nguồn, stream, tải về

`FS-23.01` · tier B (Grid) / A (List) · board `PH_Movies` (1/5), `PH_MoviesAdd` (2/5) · cập nhật 2026-10-14

**Một câu:** Movies là thư viện chung của mọi nguồn phim — thư mục trên NAS/Files, máy chủ Plex trong nhà, file chép
thẳng vào máy; ở nhà chạm là xem (stream), phim cần mang đi thì Download, nhìn poster là biết phim nào xem được
khi không có mạng.

Quyết định: [planboard movies-library](../../../.planboard/movies-library/DECISIONS.md) D1–D3, D6, D7, D9.

## 1. Lối vào

- Collections › Utilities: ô **Movies** (`play.rectangle`, khác `film` của Video Studio) sau Video Projects. Như mọi ô
  Utilities, số đếm không vẽ mà VoiceOver đọc: `128 movies, 3 on this iPhone`. Ghim được (ô ghim có dòng phụ đó);
  không ẩn được (FS-06.01 §6). iPad dùng cùng băng Utilities (không có sidebar Collections); Mac theo FS-18.
  Movies không cần quyền ảnh: Collections lúc chưa cho đọc ảnh vẫn có nút **Open Movies** dưới thông báo `No Access to Photos`.

## 2. Nguồn

| Nguồn | Thêm ở | Phim vào thư viện |
|---|---|---|
| Thư mục trên connection FS-15 (SMB, SFTP, WebDAV) hoặc thư mục Files | + › Add a Source… › Folder | mọi file phim trong thư mục và thư mục con, quét lại khi mở Movies |
| Máy chủ Plex | + › Add a Source… › Plex | mọi phim/tập trong thư viện Movies và TV của máy chủ ([07](07-plex.md)) |
| File chép thẳng | + › Add Movie Files… (Files), Share sheet / AirDrop | chép ngay vào máy, coi như đã Download |

- Nguồn liệt kê và gỡ ở **Settings › Sources** (cùng chỗ nguồn ảnh FS-19), nhóm "Movie Sources". Gỡ nguồn: phim
  stream của nó biến khỏi Movies; phim đã Download ở lại trên máy.
- Loại file nhận: mp4, m4v, mov, mkv, webm, flv, avi, wmv, ts, m2ts. Phụ đề cùng tên cạnh phim đi theo (03 §5).
- Add Movie Files… / Share / AirDrop **chép** file (bản gốc giữ nguyên); phim đã có (cùng mã băm) không chép lần hai;
  Share/AirDrop xong mở Movies (phim mới nhất đứng đầu theo Recently Added).
- Quét chỉ đọc tên + cỡ, không đọc nội dung; 1.000 file ≤ 10 s trên NAS gigabit. Đi sâu tối đa 8 tầng; bỏ thư mục
  ẩn và thư mục rác của NAS (`@eaDir`, `#recycle`, `$RECYCLE.BIN`, `#snapshot`). Phụ đề cạnh phim chỉ ghi đường dẫn,
  tải khi cần; một thư mục con không trả lời thì lượt quét không ẩn gì; thư mục gốc không trả lời thì nguồn là
  "không tới được" (§3).

## 3. Ba trạng thái của một phim

| Trạng thái | Trên poster | Chạm |
|---|---|---|
| **Trên máy** | dấu ✓ tròn tối góc trên phải | phát từ máy, cả khi chế độ máy bay |
| **Đang tải** | thanh cam dưới poster theo tiến độ | phát (stream nếu tới được nguồn, không thì phần đã tải) |
| **Stream** | không dấu | phát qua mạng nhà; nguồn không tới được → poster mờ, chạm báo `Not available offline. Connect to NAS Home to play.` |

- Lỗi tải: dòng đỏ dưới tên (`Download paused — NAS Home unreachable`); Retry trong menu phim.

## 4. Màn Movies

- **Grid** mặc định: poster dọc 2:3, dưới là tên (1 dòng) + năm; iPhone 3 cột, iPad/Mac/Duo trong theo bề rộng
  (thêm cột, không phóng to). **List** trong ⋯: poster nhỏ 2:3 · tên (năm) · nguồn hoặc `On iPhone` · thời lượng (khi đã biết) · cỡ
  (board `PH_Movies`, tweak List); ngôn ngữ phụ đề chưa có ở hàng (chỉ trong bảng Audio & Subtitles). Lựa chọn Grid/List nhớ lại.
- Đầu màn: ô **Search** (tên, năm, tên file; chạy offline) và hàng lọc **All · On This iPhone · Unwatched**.
  Chữ theo thiết bị: `On This iPad`, `On This Mac`, `Download to iPad`… (mọi chỗ ghi "iPhone" trong spec này).
- ⋯: Grid/List · Sort (**Recently Added** mặc định · Title · Year · Recently Watched) · Select. Year: mới trước, không năm
  xuống cuối; Recently Watched: chưa xem bao giờ xuống cuối; Title: đọc số như người (Film 9 trước Film 10), tập theo
  mùa/tập. Search: mọi từ phải khớp, bỏ hoa-thường và dấu (`do thi` tìm ra `Đô Thị`), tìm cả `S02E04`.
- Dòng phụ dưới tiêu đề: `128 movies · 3 on this iPhone`; dung lượng (`21.4 GB · 48 GB free`) ở cuối danh sách khi cuộn hết.
- Poster: Plex → poster của Plex; thư mục → `<tên>-poster.jpg`, rồi `poster.jpg`/`folder.jpg` (chỉ khi thư mục có đúng một phim) cạnh phim, ảnh bìa nhúng
  trong MP4; thiếu thì **ô chữ** (nền màu theo tên, ghi tên + năm). Khung hình thật (10% thời lượng) và ảnh bìa
  nhúng trong MKV chỉ lấy khi phim đã được mở hoặc đã tải — quét không mở từng phim qua mạng (người dùng chốt 14/10). Tên + năm: Plex, không thì đọc từ tên file
  (`Dune.Part.Two.2024.2160p…` → `Dune Part Two` · `2024`); `S01E04` cho tập phim. Rename sửa được tên hiện.
- Rỗng: `No Movies` · "Add a folder on your NAS or a Plex server, or copy movie files to this iPhone." · **Add a Source**.

## 5. Nút + và menu phim

- **+**: `Add a Source…` (Folder on a Server or Files · Plex Server) · `Add Movie Files…`. Không còn gì khác.
- Menu phim (giữ lâu, hoặc ⋯ trên poster khi rê chuột ở Mac/iPad): **Play** · **Download to iPhone** /
  **Remove Download** · **Mark as Watched/Unwatched** · **Audio & Subtitles…** · **Rename** · **Retry Download**
  (chỉ khi lỗi) · **Remove from Movies** (chỉ phim chép thẳng; xoá file khỏi máy, alert 2 nút).
- Select (⋯): chọn nhiều → Download · Remove Download · Mark as Watched.

## 6. Tải về (Download)

- Một phim một lúc theo hàng đợi; khối 1 MB vào `.part`, đổi tên khi đủ byte; trước mỗi phim cần cỡ + 1 GB trống,
  thiếu → `Not enough space on this device — about 3.2 GB needed.`, không bắt đầu.
- Mất nguồn giữa chừng → giữ phần đã tải, chạy tiếp từ byte đã có khi tới lại được. Không kiểm SHA-256 (phim quá
  lớn); kiểm cỡ khớp nguồn.
- Rời app / khoá máy (người dùng chốt 14/10): **Plex và WebDAV tải nền** bằng kiểu tải nền của iOS, khoá máy vẫn chạy.
  **SMB, SFTP, Files chỉ chạy khi ShotDex mở** (iOS 26: thêm tác vụ xử lý tiếp tục như FS-22.02 §3); hàng đang tải
  ghi `Keep ShotDex open to finish`; mở lại app thì chạy tiếp từ byte đã có.
- Tải kèm: phụ đề cạnh phim, poster/thông tin (Plex: poster, ảnh nền, năm, mô tả, thể loại).
- Kho trong vùng dữ liệu của app, **không sao lưu**, không qua Photos, không hiện trong Files.
- **Remove Download**: alert 2 nút `Remove Download?` · "The movie stays on NAS Home. This frees 6.1 GB." · Remove /
  Cancel; phim quay về Stream, giữ chỗ đang xem; phụ đề đã dịch giữ lại (nhỏ, khó làm lại).
- Hết bộ nhớ hệ thống không bao giờ làm ShotDex tự xoá phim đã tải (NF-02).
