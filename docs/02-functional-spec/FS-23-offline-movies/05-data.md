# FS-23.05 — Dữ liệu

`FS-23.05` · cập nhật 2026-10-14

**Một câu:** phim và phụ đề là file trong một thư mục của app không sao lưu; GRDB giữ danh mục, chỗ đang xem và
lựa chọn phụ đề trong bảng riêng; API key ở Keychain.

## 1. File

| Thư mục (trong vùng dữ liệu app) | Chứa | Sao lưu iCloud |
|---|---|---|
| `Movies/<id>/` | file phim giữ tên gốc · phụ đề (`<id-phụ-đề>.srt/.ass/.vtt`) · khung hình 16:9 | không (đánh dấu cả thư mục) |
| `Movies/.incoming/` | file đang chép (`.part`) | không |

- Không đặt trong Caches: hệ thống được phép xoá Caches khi máy đầy, mà phim là thứ người dùng tự chép vào.
- Khởi động: thư mục `<id>` không có dòng trong bảng → xoá; dòng không có file → hàng `Missing` + Delete
  (không tự xoá dòng — người dùng thấy được chuyện gì đã xảy ra).
- File `.part` của phim không còn trong hàng đợi → xoá lúc khởi động (NF-02: dọn thư mục tạm).

## 2. Bảng

Migration kế tiếp `v36-movies`. Bốn bảng mới, đăng ký vào bảng vệ tinh của [BD-02](../../01-basic-design/BD-02-database-design.md) §3.
Không cột nào trong `photo_metadata`; không khoá ngoại (luật BD-02).

| Bảng | Giữ gì |
|---|---|
| Phim | id · tên hiện · tên file gốc · cỡ byte · mã băm 64 bit · thời lượng · nguồn (connection + đường dẫn, hoặc Files, hoặc Share) · trạng thái (đang chép / sẵn sàng / không phát được / mất file) · byte đã chép · ngày thêm · lần xem cuối · vị trí xem · đã xem xong · tốc độ · track âm thanh chọn · lệch tiếng (Audio Sync) |
| Phụ đề phim | id · id phim · ngôn ngữ · nguồn (trong file / cạnh phim / nhập / chia sẻ / dịch + nhà cung cấp + id phụ đề gốc) · định dạng · mã chữ · tên file · lệch giờ |
| Lựa chọn phụ đề | id phim · phụ đề chính · phụ đề phụ · vị trí · cỡ, màu mỗi dòng |
| Việc dịch dở | id phim · phụ đề From · ngôn ngữ To · nhà cung cấp · số cue đã xong · file kết quả dở |

- Cài đặt chung (Subtitle Languages, Audio Languages, cỡ/màu/vị trí mặc định) ở kho cài đặt mặc định, như các mục Playback khác.
- Nhà cung cấp AI (tên, loại, địa chỉ, model) ở bảng của [FS-08.07](../FS-08-settings/07-ai-providers.md) §4; key ở Keychain.

## 3. Mã băm

- Cách tính quen dùng của các trình phát phim: cỡ file cộng tổng các số 64 bit little-endian của 64 KB đầu và 64 KB cuối, tràn
  theo 2^64; file < 128 KB thì hai vùng chồng nhau. Kết quả 16 ký tự hex.
- Dùng để nhận ra "phim này đã có" (01 §3). Đọc 128 KB, không đọc cả phim.

## 4. Riêng tư và bản khai

Chỉ một loại dữ liệu lần đầu rời máy, theo thao tác của người dùng:

| Thao tác | Gửi tới | Gửi gì |
|---|---|---|
| Translate bằng cloud hoặc máy chủ nhà | nhà cung cấp người dùng đã cài | chữ phụ đề, tên phim, hai ngôn ngữ |
| AI Search bằng máy chủ nhà | máy trong mạng nhà của người dùng | câu tìm + vốn từ thư viện (AI Search không dùng cloud — FS-08.07 §5) |

- Người dùng chốt 2026-10-14: thêm **NF-03 §2c — ngoại lệ thứ ba: AI do người dùng chọn** (đã ghi vào NF-03); bản
  khai giữ "không thu thập" vì yêu cầu đi thẳng tới dịch vụ của người dùng, không qua máy chủ ShotDex; agent
  `privacy-manifest` kiểm lại ở `/plan`.
- Câu onboarding (NF-03 §1) thêm một vế: "…or when you send subtitles to an AI service you choose."
- Máy chủ nhà qua `http://` trong mạng nội bộ đã được phép (Info.plist cho phép mạng cục bộ); cloud luôn `https://`.
