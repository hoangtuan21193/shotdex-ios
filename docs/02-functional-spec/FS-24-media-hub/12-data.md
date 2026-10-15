# FS-24.12 — Dữ liệu

`FS-24.12` · migration kế tiếp sau `v38-movies-art`, tên đề xuất `v39-mediaHub` · cập nhật 2026-10-16

**Một câu:** nhạc, playlist, lịch sử nghe, thứ đã Keep và việc Convert/Extract nằm trong bảng mới riêng; không cột nào
trong `photo_metadata`, không khoá ngoại nào trỏ tới nó ([BD-02](../../01-basic-design/BD-02-database-design.md) §1).

## 1. File

| Thư mục (vùng dữ liệu app) | Chứa | Sao lưu iCloud |
|---|---|---|
| `Music/<id>/` (Application Support) | bài đã Keep và bài chép thẳng, giữ tên gốc · `.lrc` · bìa | không |
| `Music/.incoming/` | file đang chép (`.part`) | không |
| `Kept/Photos/` (Application Support) | ảnh đã Keep: bản gốc nguồn FS-19; ảnh Photos là bản gốc **hoặc** bản xem 2732 px HEIC theo lựa chọn mỗi lần ([09 §2a](09-keep-on-device.md), D7) | không |
| `Caches/MusicArt/` | bìa 600 px của bài stream | không (Caches) |
| `Movies/<id>/` | không đổi (FS-23.05) | không |

- Không đặt thứ đã Keep trong Caches: hệ thống được xoá Caches khi đầy, còn Keep là việc người dùng chủ động (như FS-23.05).
- Khởi động: dọn `.part` mồ côi và thư mục không có dòng (NF-02 §2); dòng không có file → `Missing` + Remove, không tự xoá dòng.
- **Gộp My Music** (một lần, trong migration): mọi file ở thư mục nhạc import của Video Studio chuyển sang `Music/<id>/`, thành
  bài nguồn Files đã Keep; tên trong manifest cũ thành title khi không có tag; xong thì xoá thư mục và manifest cũ. Lỗi một
  file không chặn file khác (lossy, như luật decode). App chưa release: không giữ đường đọc cũ (CLAUDE.md, back-compat).

## 2. Bảng mới

| Bảng | Giữ gì | Loại |
|---|---|---|
| Nguồn nhạc | id · loại (thư mục / Plex) · connection FS-15 + đường dẫn, hoặc máy chủ Plex + thư viện Music · lần quét cuối · tới được | người dùng khai |
| Bài | id · id nguồn (rỗng = chép thẳng hoặc nguồn đã gỡ) · đường dẫn hoặc id Plex · tên file · cỡ · ngày sửa · thời lượng · codec · tần số · số bit · title · artist · album artist · album · số bài · số đĩa · năm · thể loại · compilation · khoá gom (đã chuẩn hoá) · có bìa · đường dẫn `.lrc` · có lời nhúng · trạng thái (stream / không phát được + lý do / mất file) · lúc nguồn thôi liệt kê | kết quả quét |
| Playlist | id · tên · loại (người dùng / From Movies) · ngày tạo · ngày sửa | người dùng |
| Bài trong playlist | id playlist · vị trí · id bài · title + artist chụp lúc thêm (hiện khi bài mất) | người dùng |
| Lượt nghe | id bài (rỗng khi bài đã xoá) · title · artist · album · codec · tên nguồn · lúc bắt đầu · giây đã phát · đã đủ ngưỡng | người dùng |
| Hàng đợi | vị trí · id bài · người dùng tự thêm · thuộc phần History hay Up Next; một dòng trạng thái: bài, vị trí ms, Shuffle, Repeat, `Playing from` | người dùng |
| Thứ đã Keep | id · loại (ảnh / album / bài / album nhạc / playlist) · khoá tham chiếu (id ảnh bền v30, id album PhotoKit, id bài, khoá album nhạc, id playlist) · **bản** (gốc / bản xem — chỉ ảnh Photos, D7) · lúc Keep · trạng thái · byte đã chép · lỗi | người dùng |
| File đã Keep | id file (ảnh hoặc bài) · **bản** (gốc / bản xem) · đường dẫn trên máy · cỡ · đếm số "thứ đã Keep" đang giữ nó | kết quả |
| Việc Convert/Extract | id · loại · id phim · lựa chọn (JSON) · trạng thái · % · file ra · lỗi | người dùng |

- **Bài là kết quả quét**: lần quét upsert hàng bài nhưng **không** đụng bảng Keep, playlist, lượt nghe, hàng đợi — vì thế mấy
  thứ đó không là cột của bảng bài (cùng lý do BD-02 §1 với `photo_metadata`).
- Phim giữ trạng thái tải trong bảng phim của FS-23.05 (không chuyển sang bảng Keep) — *vì add-only: đường tải phim đã có test
  xanh; Kept on iPhone cộng cả hai nguồn.* Thêm vào bảng phim: **loại** (Movie / TV Show / Clip) suy ra lúc quét và **loại do
  người dùng đặt** bằng Show As ([04 §3](04-movies-tab.md), A8) — lần quét không ghi đè cột sau.
- **Chốt 2026-10-16 (A15):** bảng nguồn giữ **ba bảng riêng** — ảnh (FS-19, `v30`), phim (FS-23), nhạc (mới); trang Sources &
  Backup **gom theo connection FS-15 / máy chủ Plex** khi hiển thị (một hàng mỗi connection, AC-30). Không gộp bảng — chỉ thêm,
  không đụng migration và test của FS-19, FS-23.
- Album, nghệ sĩ, thống kê nghe: truy vấn SQL (GROUP BY trên bảng bài và bảng lượt nghe), không bảng tổng hợp — NF-01 §1.
- Đăng ký các bảng trên vào bảng vệ tinh BD-02 §3 trong commit làm migration.

## 3. Cài đặt (kho mặc định)

Lựa chọn Grid/List và Sort của Music; đoạn Library | Collections đang chọn; tab cuối; thẻ Review đã bỏ qua tới số video nào;
công tắc **Movie Audio in Background** (mặc định `true`, D2). Sleep Timer không lưu. Chấm NEW đã xem. Không có cài đặt "bản
mặc định khi Keep ảnh Photos" — D7 hỏi mỗi lần. Clear Listening History (D11) xoá bảng lượt nghe + phần History của hàng đợi,
không phải một cài đặt.

## 4. Riêng tư

- Không gì mới rời máy: đọc tag, ảnh bìa, lời bài chỉ từ file và Plex của người dùng; không tra dịch vụ nào.
- Plex nhạc đi cùng ngoại lệ NF-03 §2c đã có — câu "phim không phải từ Plex" ở cột Không gửi sửa thành "phim, nhạc không
  phải từ Plex". **Chốt 2026-10-16 (A16):** đã sửa [NF-03 §2c](../../04-non-functional-design/NF-03-privacy-and-security.md) trong
  commit spec này (hàng Plex: thư viện Movies và Music).
- Lượt nghe chỉ trên máy; không đồng bộ Plex ở v1.
