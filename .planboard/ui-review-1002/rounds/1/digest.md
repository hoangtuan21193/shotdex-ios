# Vòng 1 — Review UI/UX ShotDex — chọn việc cần làm (2/10)

Không còn gì cần sửa: có thể chốt plan.

## Không OK (bỏ, không cần sửa) (1)

- **S3** M-23 · Capsule '85mm' nói rõ tiêu cự thật hay tương đương — trang search
  - Ghi chú: ko tự đổi , k hiện actual

## OK (46)

- **Q1** M-14 · Photo Info và Burst có nút Done — trang quick
- **Q2** M-10 · Lỗi Favorite/Delete ở Viewer và Compare phải hiện ra — trang quick
- **Q3** M-26 · Dòng gợi ý 'Try:' đang là tiếng Việt cứng trong UI tiếng Anh — trang quick
- **Q4** M-58 · Số trong Statistics có dấu phân cách hàng nghìn — trang quick
- **Q5** M-59 · Thêm chart Top Lens vào bộ mặc định — trang quick
- **Q6** M-07 · Xoá kết nối server dùng .alert thay confirmationDialog — trang quick
- **Q7** M-16 · Đóng Viewer thì lưới cuộn tới ảnh vừa xem — trang quick
- **Q8** Nhóm nhỏ còn lại (M-09, M-56, M-75, M-78, M-87) — trang quick
- **D1** M-01 · Merge All Groups ghi vào thư viện trước khi xác nhận — trang delete
  - Lựa chọn: Merge chỉ ở Exact + alert + bỏ try? (exact)
- **D2** M-03 · Dấu xoá ở Duplicates mất khi đổi tab/Back; đánh dấu được cả nhóm — trang delete
  - Lựa chọn: Giữ trong bộ nhớ của phiên (memory)
- **D3** M-04 · Ô ảnh trùng cho thấy bản nào đáng giữ — trang delete
- **D4** M-02 · Resize với Delete Originals bật sẵn — trang delete
  - Lựa chọn: Giữ bật, nói rõ ở nút + toast (label)
- **D5** M-08 · Hide nói tìm lại ở đâu — trang delete
- **V1** M-13 · Compare zoom 5× không soi được độ nét — trang viewer
  - Lựa chọn: Bản phân giải cao theo vùng, chặn ~3000px (tiled)
- **V2** M-15 · Compare: xoá một tấm không thoát cả màn — trang viewer
- **V3** M-17 · Photo Info trên iPad — trang viewer
  - Lựa chọn: Cột inspector bên phải ở regular width (inspector) — KHÁC với đề xuất
- **V4** M-18, M-19 · Thứ tự Photo Info và chạm-để-ẩn chrome — trang viewer
- **V5** M-20 · Duo cover: thùng rác gần ngón cái nhất — trang viewer
- **S1** M-21 · Lọc theo Camera/Lens từ menu Filter — trang search
  - Lựa chọn: Submenu Camera ▸ / Lens ▸ (submenu)
- **S2** M-22 · Từ không hiểu ('night') bị đổi thành tìm theo tên file — trang search
  - Lựa chọn: Thêm trường timeOfDay (night, golden hour) (timeofday) — KHÁC với đề xuất
- **S4** M-25 · Rule builder gọn hơn trên màn thấp — trang search
- **S5** M-27 · Lọc ảnh thiếu dữ liệu (không vị trí, không lens, không ngày) — trang search
- **F1** M-31 · Onboarding báo trước hộp quyền — trang firstrun
- **F2** M-32 · Trạng thái 'đang index' ở Statistics, Duplicates, Search — trang firstrun
- **F3** Bỏ sót · Board cho Limited Access, bị từ chối, iCloud offline — trang firstrun
- **H1** M-37 · Resize xong thì Share được ngay — trang share
- **H2** M-36 · Tên mức Share đọc ngược trong một ca — trang share
- **H3** M-40 · Upload dừng khi app ra nền — trang share
  - Lựa chọn: Làm BGContinuedProcessingTask luôn (bg-now) — KHÁC với đề xuất
- **H4** M-06, M-41, M-42 · Sửa vặt màn server — trang share
- **H5** M-43 · Uploaded to Server: Free Up Space có con số — trang share
- **Z1** M-45 · Nút chính của Compress và Collage Export — trang sizes
  - Lựa chọn: Hai pane ở regular width (panes) — KHÁC với đề xuất
- **Z2** M-46…49 · Lưới thay cho thẻ full-width trên iPad — trang sizes
- **Z3** M-52 · Màn thấp: 669pt nhận metrics của iPad — trang sizes
  - Lựa chọn: Một environment isShortWindow + 8 điểm gọi (env) — KHÁC với đề xuất
- **Z4** M-53 · Widget editor trên Duo — trang sizes
- **Z5** M-50 · Bàn phím iPad trong Viewer — trang sizes
- **C1** M-72 · Vuốt nhầm làm mất form đang nhập — trang stats
- **C2** M-61 · Chart editor: Save xám dù tên gợi ý đã hiện — trang stats
- **C3** M-62 · Màu chart: indigo hay amber — trang stats
  - Lựa chọn: Giữ indigo, sửa DESIGN (doc) — KHÁC với đề xuất
- **C4** M-60 · Bar chart vẽ hai lần cùng dữ liệu — trang stats
- **C5** M-67 · Collections: 'My Albums ›' mở lưới đầy đủ — trang stats
- **C6** M-68, M-69, M-76 · Từ ngữ và glyph — trang stats
- **P1** Bỏ sót · Review dark mode và accessibility — trang process
- **P2** Bỏ sót · Chấm sao / Pick / Reject chưa có board — trang process
- **P3** Bỏ sót · Chạy vòng lõi trên thư viện thật — trang process
- **P4** 15 mục challenger loại — trang process
- **P5** Cách đi vào code — trang process
  - Lựa chọn: Một /intent 'UI review 2/10' cho tất cả (intent-all) — KHÁC với đề xuất
