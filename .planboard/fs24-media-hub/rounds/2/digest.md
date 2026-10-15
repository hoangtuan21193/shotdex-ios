# Vòng 2 — FS-24 Media hub — các điểm cần chốt

Cần xử lý: 1 sửa, 0 hỏi thêm.

## Sửa (1)

- **D7** Giữ ảnh của thư viện Photos (iCloud) trên máy thì giữ bản nào? — trang keep (đã sửa ở vòng 2)
  - Lựa chọn: Mặc định bản gốc, có thể đổi sang bản xem (orig)
  - Ghi chú: luôn hỏi lúc người dùng chọn keep offlibe

## Đồng ý mặc định (không bấm gì) (27)

- **D1** Đang nghe nhạc mà mở Video Studio thì nhạc có tự dừng không? — trang play
  - Lựa chọn: Tự tạm dừng (pause)
- **D2** Đang xem phim mà khoá máy hoặc chuyển app thì tiếng phim có chạy tiếp không? — trang play (đã sửa ở vòng 2)
  - Lựa chọn: Mặc định chạy tiếp chỉ tiếng, có công tắc tắt (audio)
- **D3** Có xin Apple quyền CarPlay ngay bây giờ không (để sau này nghe nhạc ShotDex trên xe)? — trang play
  - Lựa chọn: Xin ngay, làm sau (now)
- **D4** Nhạc định dạng OGG, Opus, APE có phát được ở bản đầu không? — trang library
  - Lựa chọn: Bỏ qua, ghi số file (skip)
- **D5** Chuyển video tải về từ Photos sang Movies xong, có xoá bản trong Photos không? — trang library
  - Lựa chọn: Hỏi mỗi lần (ask)
- **D6** Lệnh bỏ bản đã giữ trên máy gọi là gì? — trang library
  - Lựa chọn: Remove from iPhone (remove)
- **D8** Có cho dùng "nguồn" và "đã giữ trên máy" làm luật của Smart Album không? — trang keep
  - Lựa chọn: Cả Smart Album (smart)
- **D9** Ô Statistics trong Utilities có hiện một con số tóm tắt không? — trang stats
  - Lựa chọn: Như mọi ô (plain)
- **D10** Màn Music Statistics trên iPhone có đủ 8 thẻ như iPad không? — trang stats
  - Lựa chọn: Đủ 8 thẻ (eight)
- **D11** Có nút xoá lịch sử nghe nhạc không, đặt ở đâu? — trang stats
- **A1** Khoảng trống đáy màn trên iOS cũ khi có mini player — Claude tự quyết
  - Claude đã chọn: Thêm một khoảng mới 164pt cạnh khoảng 100pt hiện có.
- **A2** Mini player trên iOS 26 ở màn con — Claude tự quyết
  - Claude đã chọn: Ẩn khi vào màn con, đúng luật "chỉ ở màn gốc".
- **A3** Mini player là component mới — Claude tự quyết
  - Claude đã chọn: Thêm vào bộ quy tắc thiết kế: cao 56 (iPhone, iPad), 52 (Duo).
- **A4** Sidebar iPad trong FS-21 cũ — Claude tự quyết
  - Claude đã chọn: Sửa FS-21.01 §2 theo sidebar mới trong cùng commit spec.
- **A5** Chiều cao màn trong Duo (669pt) có mini player — Claude tự quyết
  - Claude đã chọn: Chấp nhận, còn dư ≥74pt theo board.
- **A6** Menu phát nhạc trên Mac — Claude tự quyết
  - Claude đã chọn: Thêm menu Controls (Play/Pause, Next, Previous, Shuffle, Repeat) và vẽ lại board menu bar.
- **A7** Lưới Utilities khác luật DESIGN §13 — Claude tự quyết
  - Claude đã chọn: Sửa DESIGN theo board: lưới 2 cột icon + tên.
- **A8** Sửa loại phim sai (clip có năm trong tên) — Claude tự quyết
  - Claude đã chọn: Thêm Show As › Movie · TV Show · Clip vào menu của phim.
- **A9** Đọc tag và ảnh bìa FLAC — Claude tự quyết
  - Claude đã chọn: Tự đọc khối metadata FLAC, chứng minh bằng spike S-M1.
- **A10** Phát nhạc từ NAS — Claude tự quyết
  - Claude đã chọn: Spike S-M2 trước; dự phòng là chép tạm hoặc chỉ phát bản đã giữ.
- **A11** Board còn thiếu (Now Playing, Up Next, Lyrics, Sleep Timer, trang album/nghệ sĩ/playlist, Convert, Extract Audio, Review videos…) — Claude tự quyết
  - Claude đã chọn: Vẽ trên cả 4 canvas trước khi /plan.
- **A12** Icon Keep on iPhone — Claude tự quyết
  - Claude đã chọn: arrow.down.to.line, đã giữ = checkmark.circle.fill (không trùng icon Lưu về Photos).
- **A13** Convert / Extract Audio từ MKV, AVI — Claude tự quyết
  - Claude đã chọn: Giải mã bằng bộ giải mã phim đang có, mã hoá bằng AVFoundation; spike S-M3 trước.
- **A14** Nhóm Metadata, Drives, Cache trên trang Sources & Backup của iPhone/Duo — Claude tự quyết
  - Claude đã chọn: Vẽ thêm.
- **A15** Bảng nguồn ảnh, phim, nhạc — Claude tự quyết
  - Claude đã chọn: Ba bảng riêng, trang Sources gộp theo kết nối.
- **A16** Câu chữ NF-03 về Plex music — Claude tự quyết
  - Claude đã chọn: Sửa NF-03 §2c trong commit spec.
- **A17** Mini player khi sidebar iPad phủ lên nội dung (700–1099pt) — Claude tự quyết
  - Claude đã chọn: Đặt ở đáy vùng nội dung.
