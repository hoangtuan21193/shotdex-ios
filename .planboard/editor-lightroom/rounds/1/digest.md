# Vòng 1 — Sửa ảnh mượt như Lightroom

Không còn gì cần sửa: có thể chốt plan.

## Đồng ý mặc định (không bấm gì) (13)

- **D1** Lúc đang kéo thanh trượt, ảnh hiện thế nào? — trang feel
  - Lựa chọn: Bản nháp khi kéo, nét khi thả (proxy)
- **D2** Xem thử một look/preset trước khi áp? — trang feel
  - Lựa chọn: Giữ để xem thử (hold)
- **D3** Hiện vùng cháy sáng / tắt đen ngay trên ảnh? — trang feel
  - Lựa chọn: Bật bằng tam giác ở histogram (toggle)
- **D4** Thêm Snapshot (lưu một trạng thái có tên)? — trang history
  - Lựa chọn: Có, lưu theo ảnh (snap)
- **D5** So sánh trước/sau kiểu chia đôi? — trang history
  - Lựa chọn: Có nút chia đôi (split)
- **D6** Lịch sử chỉnh sửa có còn sau khi đóng trình sửa? — trang history
  - Lựa chọn: Theo phiên (như nay) (session)
- **A1** Histogram không tính mỗi nhịp kéo — Claude tự quyết
  - Claude đã chọn: Histogram cập nhật khi thả tay (và tối đa ~5 lần/giây khi kéo), từng lần một, không chặn ảnh.
- **A2** Không giải mã lại file gốc mỗi lần thả tay — Claude tự quyết
  - Claude đã chọn: Ảnh gốc đã giải mã được giữ lại cho lần vẽ nét kế tiếp.
- **A3** Huỷ lần vẽ cũ đang chạy — Claude tự quyết
  - Claude đã chọn: Kéo tiếp thì lần vẽ cũ dừng ngay thay vì chạy hết rồi bỏ.
- **A4** Bớt vẽ lại giao diện mỗi nhịp — Claude tự quyết
  - Claude đã chọn: Chỉ phần ảnh đổi mỗi nhịp; thanh, nút, histogram không vẽ lại theo.
- **A5** Heal 'Visualize Spots' ra khỏi luồng chính — Claude tự quyết
  - Claude đã chọn: Lớp hiện vết bụi tính ngoài luồng chính.
- **A6** Giữ mọi chức năng — Claude tự quyết
  - Claude đã chọn: Mọi công cụ, mask, heal, markup, preset, LUT, film, batch, save/copy, HDR, lens blur giữ nguyên; chỉ đổi cách vẽ và thêm D1–D5.
- **A7** Quy trình — Claude tự quyết
  - Claude đã chọn: Intent → spec FS-03.18 có tiêu chí → board PH/IP/DI sáng+tối → code mỗi tiêu chí một commit → đo thời gian vẽ trên sim + iPad thật.
