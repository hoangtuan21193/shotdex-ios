# FS-23.08 — Trang chi tiết phim

Chạm một phim trong Movies không phát ngay mà mở trang chi tiết, kiểu Infuse (người dùng yêu cầu 15/10; planboard
`.planboard/movie-detail`, 5 câu chốt cùng ngày). Board: iPhone `PH_MovieDetail` (tweak `fresh`, `downloading`,
`onDevice`, `dark`) · iPad `IP_MovieDetail` · Duo trong `DI_MovieDetail`, ngoài `DC_MovieDetail` · Mac `MAC_MovieDetail`.

## 1. Mở và đóng

- Chạm poster (Grid) hoặc hàng (List) → trang chi tiết đẩy vào cùng ngăn điều hướng của Movies; Back về lưới, giữ
  vị trí cuộn; thanh tab vẫn hiện. Phim mờ vì nguồn không tới được vẫn mở được trang (xem thông tin, Audio,
  Subtitles); nút xem báo `Not available offline. Connect to NAS Home to play.` như hôm nay.
- **Giữ lâu** poster vẫn mở menu nhanh (01 §5), thêm **Play** ở đầu menu (D4).
- Select (⋯ › Select) chạm là chọn, không mở trang.

## 2. Bố cục iPhone (D1)

- Ảnh nền ngang trên cùng (340 pt), mờ dần xuống nền trang. Plex: ảnh nền (`art`) của phim; không có thì poster
  phóng to làm mờ; không poster thì ô màu theo tên (01 §4).
- Poster nhỏ 112×168 bên trái chồng lên ảnh nền; bên phải: tên (24 pt đậm, tối đa 2 dòng), `năm · thời lượng ·
  độ phân giải` (thứ nào biết), thể loại (Plex), `nguồn · cỡ file`.
- Tóm tắt (Plex) 3 dòng, chạm để xem hết.
- Nút ⋯ góc phải: Mark as Watched/Unwatched · Rename · Retry Download (khi lỗi) · Remove Download (hoặc
  Remove from Movies với phim chép thẳng). Duo ngoài không có ⋯.

## 3. Nút xem và Download (D2)

- Đang xem dở (chỗ xem hợp lệ theo 02 §5): nút cam to **Resume · 47:12**, dưới là thanh đã xem + `1:58:48 left`;
  hàng dưới hai nút nửa bề rộng **From Beginning** và Download. Chưa xem hoặc đã xem hết: một nút **Play**,
  Download chiếm cả hàng.
- From Beginning phát từ 0:00; chỗ xem mới ghi đè chỗ cũ khi xem.
- Download theo trạng thái (01 §3, §6): `Download` → `Downloading 45%` (thanh tiến độ trong nút) → `✓ On iPhone`.
  Chạm khi đang tải hoặc đã tải: alert Remove Download (01 §6). Lỗi: nút ghi `Retry Download`, dòng đỏ dưới nút.
  Phim chép thẳng: không có nút Download. Phim Plex nhiều bản: Download hỏi bản như hôm nay (AC-56).

## 4. Audio · Subtitles · Version (D3)

- Ba hàng trong một thẻ: **Audio** `English · TrueHD 7.1` · **Subtitles** `Tiếng Việt + English` (Primary +
  Secondary; `Off`) · **Version** `4K · 54.3 GB` (chỉ phim Plex có hơn một bản).
- Audio / Subtitles mở đúng bảng **Audio & Subtitles** của player (02 §3b, 03) — cùng Primary/Secondary, vị trí,
  kiểu chữ, Translate…, Import File…; lựa chọn lưu theo phim như trong player, vào phim là đúng ngay.
- Track âm thanh trước khi phát: Plex từ thông tin phim; MKV/WebM đọc đầu file (vài KB, cả khi stream); MP4/MOV
  trên máy qua AVFoundation; còn lại hàng Audio ghi `Chosen when playing`. Chọn được lưu theo **vị trí trong file**
  (track âm thanh thứ n), player khớp lại đúng track khi mở.
- Version: chọn bản sẽ Play và Download; mặc định bản nét nhất (07 §3).

## 5. Thiết bị (A5, D5)

- iPad, Duo trong, Mac: ảnh nền ngang cả màn; cột trái poster + thông tin + nút; cột phải tóm tắt + thẻ Audio/
  Subtitles/Version. Không phóng to chữ hay nút.
- Duo ngoài (466×678, thanh 84 pt): trang rút gọn — poster, tên, Resume/Play + From Beginning, hàng Audio · Subtitles;
  không Download, Remove, Rename, ⋯.
