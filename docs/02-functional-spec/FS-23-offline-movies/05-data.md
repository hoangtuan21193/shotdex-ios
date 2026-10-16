# FS-23.05 — Dữ liệu

`FS-23.05` · cập nhật 2026-10-14

**Một câu:** phim và phụ đề là file trong một thư mục của app không sao lưu; GRDB giữ danh mục, chỗ đang xem và
lựa chọn phụ đề trong bảng riêng; API key ở Keychain.

## 1. File

| Thư mục (trong vùng dữ liệu app) | Chứa | Sao lưu iCloud |
|---|---|---|
| `Movies/<id>/` (trong Application Support — không Documents vì không hiện trong Files, không Caches vì hệ thống được xoá) | phim **đã tải** giữ tên gốc · phụ đề (`<id-phụ-đề>.srt/.ass/.vtt`) · `poster.jpg` | không (đánh dấu cả thư mục `Movies/`) |
| `Caches/MovieArt/` | poster + khung hình của phim **Stream** (cache, xoá được, tải lại khi cần) | không |
| `Movies/.incoming/` | file đang chép (`.part`) | không |

- Không đặt trong Caches: hệ thống được phép xoá Caches khi máy đầy, mà phim là thứ người dùng tự chép vào.
- Khởi động: thư mục `<id>` không có dòng trong bảng → xoá; dòng không có file → hàng `Missing` + Delete
  (không tự xoá dòng — người dùng thấy được chuyện gì đã xảy ra).
- File `.part` của phim không còn trong hàng đợi → xoá lúc khởi động (NF-02: dọn thư mục tạm).
- Nguồn thôi liệt kê một phim (sau một lượt quét **chạy xong** và không rỗng): phim đã tải ở lại, có nhãn; phim stream
  **ẩn khỏi Grid và giữ 30 ngày** cùng chỗ xem, phụ đề, tên đã đặt — file quay lại (cả khi đổi tên/chuyển thư mục, nhận
  bằng tên + cỡ) thì hiện lại nguyên vẹn; quá 30 ngày thì xoá lúc khởi động. Lượt quét lỗi giữa chừng hay trả rỗng không
  ẩn gì.

## 2. Bảng

Migration `v36-movies` (`AppDatabase+Movies.swift`). Năm bảng mới + bảng nhà cung cấp AI, đăng ký vào bảng vệ tinh của
[BD-02](../../01-basic-design/BD-02-database-design.md) §3. Không cột nào trong `photo_metadata`, không khoá ngoại nào
trỏ tới nó (luật BD-02). Khoá ngoại chỉ nối các bảng mới với nhau và với connection FS-15: phụ đề, lựa chọn, việc dịch
dở đi theo phim; xoá connection thì xoá nguồn thư mục trên nó; **phim sống lâu hơn nguồn** (id nguồn về rỗng) — gỡ
nguồn thì `MovieStore` tự xoá phim stream, giữ phim đã tải.

| Bảng | Giữ gì |
|---|---|
| Nguồn phim (`movie_sources`) | id · loại (thư mục / Plex) · connection FS-15 + đường dẫn, hoặc máy chủ Plex (id máy, địa chỉ, thư viện chọn) · lần quét cuối · trạng thái tới được. Token Plex ở Keychain theo id nguồn |
| Phim (`movies`) | id · id nguồn (rỗng = chép thẳng, hoặc nguồn đã gỡ) · đường dẫn hoặc id phim Plex + bản (part) đang/đã tải · tên từ nguồn · **tên người dùng đặt** (Rename, lần quét không ghi đè) · năm · mùa/tập · tên file gốc · cỡ byte (hai thứ này lần quét không ghi đè khi phim đã/đang tải) · tên file trên máy · tên nguồn (còn lại sau khi gỡ nguồn) · id máy chủ Plex (phim đã tải nhận lại nguồn khi thêm lại đúng máy chủ) · mã băm 64 bit · thời lượng · thông tin Plex (mô tả, thể loại) · đường dẫn poster (ảnh cạnh phim trên nguồn, hoặc thumb Plex) · trạng thái (stream / chờ tải / đang tải / trên máy / không phát được / mất file) · byte đã tải · lỗi tải · lúc nguồn không còn file (phim đã tải ở lại, có nhãn) · ngày thêm · lần xem cuối · vị trí xem · đã xem xong · tốc độ · track âm thanh chọn · lệch tiếng (Audio Sync) · **còn nợ Plex** (chỗ xem/đã xem đổi lúc không tới được máy chủ — thay cho bảng hàng đợi: luật "lần xem mới nhất thắng" chỉ cần trạng thái cuối) |
| Phụ đề phim (`movie_subtitles`) | id · id phim · đường dẫn trên nguồn (phụ đề cạnh phim/Plex, tải khi cần) · ngôn ngữ · nguồn (trong file / cạnh phim / nhập / chia sẻ / dịch + nhà cung cấp + id phụ đề gốc) · định dạng · mã chữ · tên file · lệch giờ |
| Lựa chọn phụ đề (`movie_subtitle_choices`) | id phim · phụ đề chính · phụ đề phụ · vị trí · cỡ, màu mỗi dòng |
| Việc dịch dở (`movie_translation_jobs`) | id phim · phụ đề From · ngôn ngữ To · nhà cung cấp · số cue đã xong · file kết quả dở |

- Cài đặt chung (Subtitle Languages, Audio Languages, cỡ/màu/vị trí mặc định) ở kho cài đặt mặc định, như các mục Playback khác.
- Nhà cung cấp AI (tên, loại, địa chỉ, model) ở bảng của [FS-08.07](../FS-08-settings/07-ai-providers.md) §4; key ở Keychain.

## 3. Mã băm

- Cách tính quen dùng của các trình phát phim: cỡ file cộng tổng các số 64 bit little-endian của 64 KB đầu và 64 KB cuối, tràn
  theo 2^64; file < 128 KB thì hai vùng chồng nhau. Kết quả 16 ký tự hex.
- Dùng để nhận ra "phim này đã có" (01 §3). Đọc 128 KB, không đọc cả phim.

## 4. Riêng tư và bản khai

Dữ liệu rời máy chỉ theo thao tác của người dùng, tới dịch vụ người dùng tự cài:

| Thao tác | Gửi tới | Gửi gì |
|---|---|---|
| Add a Source › Plex, stream, Download, đồng bộ chỗ xem | plex.tv (đăng nhập, danh sách máy chủ) và máy chủ Plex của người dùng | token, yêu cầu đọc thư viện/file, chỗ đang xem |
| Translate bằng cloud hoặc máy chủ nhà | nhà cung cấp người dùng đã cài | chữ phụ đề, tên phim, hai ngôn ngữ |
| AI Search bằng máy chủ nhà | máy trong mạng nhà của người dùng | câu tìm + vốn từ thư viện (AI Search không dùng cloud — FS-08.07 §5) |

- Người dùng chốt 2026-10-14: thêm **NF-03 §2c — ngoại lệ thứ ba: AI do người dùng chọn** (đã ghi vào NF-03); bản
  khai giữ "không thu thập" vì yêu cầu đi thẳng tới dịch vụ của người dùng, không qua máy chủ ShotDex; agent
  `privacy-manifest` kiểm lại ở `/plan`.
- Câu onboarding (NF-03 §1) thêm một vế: "…or when you send subtitles to an AI service you choose."
- Máy chủ nhà qua `http://` trong mạng nội bộ đã được phép (Info.plist cho phép mạng cục bộ); cloud luôn `https://`.
