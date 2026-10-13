# FS-23.01 — Kho phim và đưa phim vào

`FS-23.01` · tier A · board `PH_Movies` (1/5), `PH_MoviesAdd` (2/5) — chưa vẽ · cập nhật 2026-10-14

**Một câu:** một danh sách phim nằm trong máy, thêm từ server/Files/Share sheet, mỗi phim thấy cỡ, tiến độ chép,
chỗ đã xem, phụ đề có sẵn; xoá là trả lại dung lượng.

## 1. Lối vào

- Collections › Utilities thêm ô **Movies**, đứng sau Video Projects; dòng giá trị `4 · 12.3 GB`. Ghim được
  (`utility:` như các tiện ích khác); không ẩn được (luật Utilities, FS-06.01 §6).
- iPad và Mac: hàng **Movies** trong nhóm Utilities của sidebar (FS-21.01, FS-18.01). Duo ngoài: ô giống iPhone.
- Biểu tượng: một SF Symbol **khác `film`** (`film` đã là Video Studio, DESIGN.md) — chọn ở board.
- Intent ghi "chip Movies trong Albums"; Collections không có hàng chip, nên người dùng chốt (2026-10-14) **ô
  Utilities**, không thêm thành phần mới.

## 2. Danh sách

| Trạng thái | Điều kiện | Hiển thị |
|---|---|---|
| rỗng | chưa có phim | `No Movies` · "Copy movies from a server or Files to watch them without a connection." · nút **Add Movies** |
| đang chép | ≥ 1 phim đang vào | hàng đó có thanh tiến độ, `Copying 2.1 of 4.7 GB · 3 min left`, nút ✕ |
| bình thường | | hàng phim (dưới) |
| lỗi chép | server mất, file hỏng | hàng giữ phần đã chép, dòng `Can't Reach NAS Home` + **Retry**; không xoá gì tự động |

- Hàng phim: khung hình 16:9 lấy ở 10% thời lượng (r-sm) · tên · `1:58:20 · 4.7 GB` · ngôn ngữ phụ đề đã có
  (`EN · VI`) · thanh đã xem dưới khung hình. Xem ≥ 95% → `Watched`, thanh ẩn.
- Tên hiện ra đọc từ tên file: bỏ phần đuôi kỹ thuật (độ phân giải, codec, nhóm phát hành), giữ tên + năm, hoặc
  tên + `S01E04`. Người dùng sửa được (Rename); tên file trên đĩa không đổi.
- Đầu danh sách: `4 Movies · 12.3 GB · 48 GB Free on This Device`.
- Sắp xếp (menu ⋯): Recently Added (mặc định) · Title · Recently Watched. Select → Delete hàng loạt.
- Giữ lâu một hàng: Play · Subtitles… · Rename · Delete (cuối, đỏ). Chạm hàng → phát (02).

## 3. Đưa phim vào

Nút **+** (hoặc Add Movies) mở menu **From a Server…** · **From Files…**. Share sheet/AirDrop đi đường riêng.

| Nguồn | Cách |
|---|---|
| Server FS-15 | mở trình duyệt FS-17.01 ở chế độ **chọn phim**: chỉ thư mục và file phim hiện, chọn nhiều, nút `Add N Movies` |
| Server, đang duyệt bình thường | giữ lâu một file phim → **Add to Movies**; Select → thanh dưới có **Add to Movies** |
| Files | bảng chọn tài liệu của hệ thống, chỉ loại phim, chọn nhiều, luôn **sao chép** vào kho |
| Share sheet / AirDrop | app khai các loại file phim nên hiện trong hàng app của Share sheet và trong "Open with" của AirDrop; hệ thống đưa bản sao, ShotDex chuyển vào kho rồi mở Movies tại phim đó |

- FS-17.01 hôm nay **ẩn video** (chỉ liệt kê ảnh). Đổi: ở chế độ chọn phim và trong menu giữ lâu, file phim được
  hiện và chọn được; duyệt ảnh bình thường vẫn như cũ.
- Extension chia sẻ hiện có **không** đổi (chỉ ảnh, không vùng chia sẻ với app — NF-03 §1).
- **Phụ đề cạnh phim**: file `.srt/.ass/.ssa/.vtt` cùng tên gốc trong cùng thư mục (`Movie.srt`, `Movie.en.srt`,
  `Movie.vi.forced.srt`) được chép theo; ngôn ngữ đọc từ đuôi tên, không có thì đoán từ nội dung.
- Loại file nhận: mp4, m4v, mov, mkv, webm, flv, avi, wmv, ts, m2ts. Loại khác → `ShotDex can't play this file type.`
- Cùng file (cỡ + mã băm 64 bit trùng) đã trong kho → `Already in Movies` và không chép lần hai.

## 4. Chép

- Một phim một lúc, theo hàng đợi; chép theo khối 1 MB vào file tạm cạnh kho, đổi tên thật khi đủ byte.
- Trước mỗi phim: cỡ file + 1 GB phải còn trống. Thiếu → `Not enough space on this device — about 3.2 GB needed.`,
  phim đó không bắt đầu, hàng đợi dừng.
- Mất server giữa chừng → giữ phần đã chép; Retry hoặc mở lại app **chép tiếp từ byte đã có**, không chép lại.
- Rời app: iOS 26 xin tác vụ xử lý tiếp tục như Backup (FS-22.02 §3), tiến độ hiện ở giao diện của hệ thống;
  trước iOS 26 chép tới khi hệ thống dừng app, mở lại thì chạy tiếp.
- Xong một phim: kiểm cỡ đúng bằng nguồn, tính mã băm, lấy khung hình, đọc thời lượng + danh sách track. Phim
  không đọc được → hàng `Can't Play This File` + Delete; không tự xoá.
- Kho nằm trong vùng dữ liệu của app, **đánh dấu không sao lưu**; không hiện trong app Files; không qua Photos.

## 5. Xoá và dung lượng

- Delete hỏi bằng alert 2 nút: `Delete “Dune Part Two”?` · "This removes the movie and its subtitles from this
  device and frees 4.7 GB." · **Delete** / Cancel. Không có Undo — file đã xoá.
- Xoá phim xoá luôn phụ đề tải về và bản dịch của nó; không đụng file gốc trên server/Files.
- Hết bộ nhớ hệ thống không bao giờ làm ShotDex tự xoá phim (NF-02: chỉ xoá cache của ShotDex).
