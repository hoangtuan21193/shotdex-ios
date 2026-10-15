# FS-24 Media hub — các quyết định

Chốt 2026-10-16 sau 3 vòng. Nguồn: `plan.json`.

| ID | Quyết định | Kết quả | Lựa chọn |
|---|---|---|---|
| D1 | Đang nghe nhạc mà mở Video Studio thì nhạc có tự dừng không? | OK | Tự tạm dừng |
| D2 | Đang xem phim mà khoá máy hoặc chuyển app thì tiếng phim có chạy tiếp không? | OK | Mặc định chạy tiếp chỉ tiếng, có công tắc tắt |
| D3 | Có xin Apple quyền CarPlay ngay bây giờ không (để sau này nghe nhạc ShotDex trên xe)? | OK | Xin ngay, làm sau |
| D4 | Nhạc định dạng OGG, Opus, APE có phát được ở bản đầu không? | OK | Bỏ qua, ghi số file |
| D5 | Chuyển video tải về từ Photos sang Movies xong, có xoá bản trong Photos không? | OK | Hỏi mỗi lần |
| D6 | Lệnh bỏ bản đã giữ trên máy gọi là gì? | OK | Remove from iPhone |
| D7 | Giữ ảnh của thư viện Photos (iCloud) trên máy thì giữ bản nào? | OK | Hỏi mỗi lần, Originals đứng đầu |
| D8 | Có cho dùng "nguồn" và "đã giữ trên máy" làm luật của Smart Album không? | OK | Cả Smart Album |
| D9 | Ô Statistics trong Utilities có hiện một con số tóm tắt không? | OK | Như mọi ô |
| D10 | Màn Music Statistics trên iPhone có đủ 8 thẻ như iPad không? | OK | Đủ 8 thẻ |
| D11 | Có nút xoá lịch sử nghe nhạc không, đặt ở đâu? | OK | Có: Settings › Playback › "Clear Listening History…", hỏi lại trước khi xoá. |
| A1 | Khoảng trống đáy màn trên iOS cũ khi có mini player | OK (Claude tự quyết) | Thêm một khoảng mới 164pt cạnh khoảng 100pt hiện có. |
| A2 | Mini player trên iOS 26 ở màn con | OK (Claude tự quyết) | Ẩn khi vào màn con, đúng luật "chỉ ở màn gốc". |
| A3 | Mini player là component mới | OK (Claude tự quyết) | Thêm vào bộ quy tắc thiết kế: cao 56 (iPhone, iPad), 52 (Duo). |
| A4 | Sidebar iPad trong FS-21 cũ | OK (Claude tự quyết) | Sửa FS-21.01 §2 theo sidebar mới trong cùng commit spec. |
| A5 | Chiều cao màn trong Duo (669pt) có mini player | OK (Claude tự quyết) | Chấp nhận, còn dư ≥74pt theo board. |
| A6 | Menu phát nhạc trên Mac | OK (Claude tự quyết) | Thêm menu Controls (Play/Pause, Next, Previous, Shuffle, Repeat) và vẽ lại board menu bar. |
| A7 | Lưới Utilities khác luật DESIGN §13 | OK (Claude tự quyết) | Sửa DESIGN theo board: lưới 2 cột icon + tên. |
| A8 | Sửa loại phim sai (clip có năm trong tên) | OK (Claude tự quyết) | Thêm Show As › Movie · TV Show · Clip vào menu của phim. |
| A9 | Đọc tag và ảnh bìa FLAC | OK (Claude tự quyết) | Tự đọc khối metadata FLAC, chứng minh bằng spike S-M1. |
| A10 | Phát nhạc từ NAS | OK (Claude tự quyết) | Spike S-M2 trước; dự phòng là chép tạm hoặc chỉ phát bản đã giữ. |
| A11 | Board còn thiếu (Now Playing, Up Next, Lyrics, Sleep Timer, trang album/nghệ sĩ/playlist, Convert, Extract Audio, Review videos…) | OK (Claude tự quyết) | Vẽ trên cả 4 canvas trước khi /plan. |
| A12 | Icon Keep on iPhone | OK (Claude tự quyết) | arrow.down.to.line, đã giữ = checkmark.circle.fill (không trùng icon Lưu về Photos). |
| A13 | Convert / Extract Audio từ MKV, AVI | OK (Claude tự quyết) | Giải mã bằng bộ giải mã phim đang có, mã hoá bằng AVFoundation; spike S-M3 trước. |
| A14 | Nhóm Metadata, Drives, Cache trên trang Sources & Backup của iPhone/Duo | OK (Claude tự quyết) | Vẽ thêm. |
| A15 | Bảng nguồn ảnh, phim, nhạc | OK (Claude tự quyết) | Ba bảng riêng, trang Sources gộp theo kết nối. |
| A16 | Câu chữ NF-03 về Plex music | OK (Claude tự quyết) | Sửa NF-03 §2c trong commit spec. |
| A17 | Mini player khi sidebar iPad phủ lên nội dung (700–1099pt) | OK (Claude tự quyết) | Đặt ở đáy vùng nội dung. |

## D1 — Đang nghe nhạc mà mở Video Studio thì nhạc có tự dừng không?
- **Chốt:** Tự tạm dừng khi vào Video Studio; ra khỏi Video Studio thì bấm Play lại trên mini player.
- **Vì sao:** Không dừng thì tiếng nhạc lẫn với tiếng clip đang xem trước, khó nghe để dựng video.
- **Đã cân nhắc:** Phát chung
- **Lịch sử:** vòng 1 — OK (mặc định).

## D2 — Đang xem phim mà khoá máy hoặc chuyển app thì tiếng phim có chạy tiếp không?
- **Chốt:** Thêm lựa chọn trong Settings › Playback: "Movie Audio in Background" — bật thì khoá máy/chuyển app phim chạy tiếp chỉ tiếng (mặc định bật, theo lựa chọn của bạn), tắt thì phim dừng như hiện nay. Picture in Picture không đổi.
- **Vì sao:** Chạy tiếp thì nghe được như podcast nhưng dễ hao pin và lỡ đoạn phim; dừng thì giống app hiện nay.
- **Đã cân nhắc:** Mặc định dừng, có công tắc bật
- **Lịch sử:** vòng 1 — Sửa: "có option cho người dùng chọn"; vòng 2 — OK.

## D3 — Có xin Apple quyền CarPlay ngay bây giờ không (để sau này nghe nhạc ShotDex trên xe)?
- **Chốt:** Xin ngay, nhưng bản đầu chưa làm CarPlay.
- **Vì sao:** Apple duyệt quyền CarPlay mất vài tuần; xin muộn thì lúc muốn làm phải chờ.
- **Đã cân nhắc:** Chưa xin
- **Lịch sử:** vòng 1 — OK (mặc định).

## D4 — Nhạc định dạng OGG, Opus, APE có phát được ở bản đầu không?
- **Chốt:** Bỏ qua ở bản đầu, Settings ghi rõ bao nhiêu file chưa hỗ trợ. Làm sau nếu bạn thật sự có nhiều file loại này.
- **Vì sao:** Bỏ qua thì vài file trên NAS không hiện; phát được thì mất gapless và tốn thêm thời gian làm.
- **Đã cân nhắc:** Phát qua bộ giải mã phim
- **Lịch sử:** vòng 1 — OK (mặc định).

## D5 — Chuyển video tải về từ Photos sang Movies xong, có xoá bản trong Photos không?
- **Chốt:** Hỏi bằng hộp xoá của hệ thống "Delete 12 videos from Photos?"; bấm Cancel thì giữ cả hai bản.
- **Vì sao:** Không xoá thì video nằm hai chỗ, tốn dung lượng iCloud; tự xoá thì có thể mất video bạn muốn giữ.
- **Đã cân nhắc:** Luôn giữ cả hai; Tự xoá
- **Lịch sử:** vòng 1 — OK (mặc định).

## D6 — Lệnh bỏ bản đã giữ trên máy gọi là gì?
- **Chốt:** "Remove from iPhone" (Remove from iPad / Mac trên thiết bị khác), đối xứng với Keep on iPhone.
- **Vì sao:** Tên lệch nhau giữa ảnh, phim, nhạc làm người dùng không chắc bấm vào có mất file gốc không.
- **Đã cân nhắc:** Remove Download
- **Lịch sử:** vòng 1 — OK (mặc định).

## D7 — Giữ ảnh của thư viện Photos (iCloud) trên máy thì giữ bản nào?
- **Chốt:** Luôn hỏi mỗi lần bấm Keep on iPhone với ảnh của thư viện Photos: hộp "Keep 412 Photos on iPhone" có Originals — full resolution (≈ 8.2 GB) đứng đầu, và Viewing Copies — 2732 px on the long side, HEIC (≈ 0.5 GB); Cancel thì không giữ gì.
- **Vì sao:** Bản gốc tốn gấp 10–30 lần dung lượng; bản xem nhẹ nhưng không sửa hay xuất ảnh gốc được khi mất mạng.
- **Đã cân nhắc:** Mặc định bản xem, có thể đổi sang bản gốc
- **Lịch sử:** vòng 1 — Sửa: "có option cho người dùng chọn"; vòng 2 — Sửa: "luôn hỏi lúc người dùng chọn keep offline"; vòng 3 — Sửa: "ghi rõ độ phân giải các option ngoài origin"; chốt trong chat.

## D8 — Có cho dùng "nguồn" và "đã giữ trên máy" làm luật của Smart Album không?
- **Chốt:** Có: Source và Kept dùng được cả trong bộ lọc tạm lẫn làm luật Smart Album.
- **Vì sao:** Chỉ có bộ lọc tạm thì mỗi lần muốn xem "ảnh đã giữ trên NAS Home" phải lọc lại.
- **Đã cân nhắc:** Chỉ bộ lọc tạm
- **Lịch sử:** vòng 1 — chọn khác đề xuất (Cả Smart Album).

## D9 — Ô Statistics trong Utilities có hiện một con số tóm tắt không?
- **Chốt:** Ô Statistics như mọi ô, không con số; lưới đều.
- **Vì sao:** Có số thì thấy ngay body dùng nhiều nhất, nhưng ô đó cao hơn các ô khác; không số thì lưới đều nhưng Statistics chìm giữa 13 ô.
- **Đã cân nhắc:** Có dòng tóm tắt
- **Lịch sử:** vòng 1 — chọn khác đề xuất (Như mọi ô).

## D10 — Màn Music Statistics trên iPhone có đủ 8 thẻ như iPad không?
- **Chốt:** Đủ 8 thẻ, cuộn dọc; vẽ thêm 3 thẻ còn thiếu.
- **Vì sao:** Thiếu thẻ trên iPhone là trái luật "phone có mọi chức năng của iPad"; đủ thì trang dài hơn.
- **Đã cân nhắc:** Giữ 5 thẻ
- **Lịch sử:** vòng 1 — OK (mặc định).

## D11 — Có nút xoá lịch sử nghe nhạc không, đặt ở đâu?
- **Chốt:** Có: Settings › Playback › "Clear Listening History…", hỏi lại trước khi xoá.
- **Vì sao:** Không có nút thì Recently Played và thống kê giữ mãi những gì bạn đã nghe.
- **Đã cân nhắc:** —
- **Lịch sử:** vòng 1 — OK (mặc định).
