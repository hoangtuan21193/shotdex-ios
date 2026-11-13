# Vòng 1 — Search giống Photos

Không còn gì cần sửa: có thể chốt plan.

## Đồng ý mặc định (không bấm gì) (16)

- **D1** Gõ chữ thì gợi ý trông thế nào? — trang typing
  - Lựa chọn: Dòng có hình, loại, số ảnh (rows)
- **D2** Ảnh kết quả hiện ở đâu, lúc nào? — trang typing
  - Lựa chọn: Kết quả ngay trong Search, có nút Mở trong Library (live)
- **D3** Chọn một gợi ý thì sao? — trang typing
  - Lựa chọn: Thành viên lọc, gõ tiếp để thu hẹp (tokens)
- **D4** Ô tìm còn trống thì hiện gì? — trang empty
  - Lựa chọn: Gần đây + gợi ý từ thư viện (library)
- **D5** Gõ ngày tháng thì hiểu tới đâu? — trang empty
  - Lựa chọn: Năm, tháng, mùa, thứ, hôm nay/hôm qua (full)
- **D6** Gõ sai chính tả thì sao? — trang empty
  - Lựa chọn: Chỉ hỏi lại khi 0 kết quả (ask)
- **D7** Làm luôn cho Mac? — trang mac
  - Lựa chọn: Làm cùng đợt (now)
- **A1** Chỉ mục tìm kiếm kiểu Photos — Claude tự quyết
  - Claude đã chọn: Tính sẵn mỗi giá trị tìm được (máy, ống kính, tiêu cự, ISO, khẩu, nơi, năm, tháng, album, từ khoá, loại file, kiểu ảnh) thành một dòng có số ảnh và ảnh đại diện; gõ chữ khớp bằng chỉ mục tiền tố trên các dòng này (vài nghìn dòng) thay vì quét 55.000 ảnh.
- **A2** Mỗi phím gõ chạy ngoài luồng chính, huỷ lần trước — Claude tự quyết
  - Claude đã chọn: Gợi ý và kết quả tính ở nền, chờ 0,15 s sau phím cuối; gõ tiếp thì huỷ lần cũ.
- **A3** Bộ từ vựng dựng một lần — Claude tự quyết
  - Claude đã chọn: Bảng tra tên máy/ống kính/nơi dựng một lần khi thư viện đổi, không dựng lại mỗi phím.
- **A4** Gần đây mở nhanh — Claude tự quyết
  - Claude đã chọn: Số ảnh và ảnh bìa của Gần đây lấy một lần, ngoài luồng chính; ảnh bìa tải không chặn.
- **A5** Kết quả hiện theo lô — Claude tự quyết
  - Claude đã chọn: Lưới kết quả vẽ 300 ảnh đầu ngay, phần còn lại nạp sau.
- **A6** Tìm chữ tự do dùng chỉ mục — Claude tự quyết
  - Claude đã chọn: Chữ không thành gợi ý (tên file, chú thích) vẫn tìm được như cũ, nhưng qua chỉ mục chữ thay vì quét LIKE từng ảnh.
- **A7** Báo khi chưa index xong — Claude tự quyết
  - Claude đã chọn: Đang đọc thư viện thì Search hiện dòng "Đang đọc 1.234 ảnh — kết quả có thể thiếu".
- **A8** Giữ mọi chức năng — Claude tự quyết
  - Claude đã chọn: Cú pháp ISO/f/mm, Advanced Search, Save as Smart Album, AI search (chỉ chạy khi bấm Search và bộ đọc không chắc), keyword:, chú thích, nơi, khung giờ, chip mời, Spotlight, Recents giữ nguyên.
- **A9** Quy trình — Claude tự quyết
  - Claude đã chọn: Intent → spec FS-01.03 §10 có tiêu chí → board PH/IP/DI/DC/MAC_Search sáng + tối → code mỗi tiêu chí một commit → kiểm trên iPhone, iPad, Duo, Mac.
