# FS-06.03 — `PhotoListScreen` và dựng phim

`FS-06.03` · `Features/Shared/PhotoListScreen.swift`
· cập nhật 2026-09-27

**Một câu:** một lưới dùng chung cho mọi danh sách assetId tự tính.

## 1. Quy tắc

- màn danh sách ảnh **chỉ để duyệt** — không có chế độ chọn nhiều ảnh, vì đây là danh sách dẫn xuất và một
  selection ở đây không có chỗ về rõ ràng.

## 2. màn danh sách ảnh + model của nó

Hình dạng lưới **thứ ba**, bên cạnh album PhotoKit và truy vấn đã lưu
: một **danh sách assetId tự tính**.

- Giữ **đúng thứ tự caller truyền vào** — một chuyến đi chạy xuôi thời gian.
- model của nó conform giao thức nguồn ảnh của viewer nên mở thẳng được viewer.
- Dùng cho Places, Trips, People and Pets.

## 3. Memories — đã bỏ (2026-09-27)

Tab Collections từng có hàng thẻ **Memories** (3 chuyến đi mới nhất, 3 năm đã trọn, 2 nơi hay quay lại,
dựng bằng `MemoryBuilder`). Bỏ vì:

- **Trùng lặp**: chuyến đi và nơi đã có token Trips / Places trong Utilities; thẻ năm chỉ là một bộ lọc ngày.
- **Sai với app cho photographer**: nguồn là ảnh có GPS, nên thẻ năm gần như chỉ gồm ảnh iPhone — ảnh máy
  ảnh rời không GPS bị bỏ, số "N photos" thấp hơn thật.
- **Tên hứa điều app không làm được**: người dùng iOS thấy "Memories" chờ một cuốn phim tự chạy. Memories của
  Apple dựng từ nhận diện mặt, phân loại cảnh, model curation và nhạc có bản quyền; PhotoKit không có API public
  đọc chúng hay phim của chúng. Một bản nhái yếu sẽ ra những bộ sưu tập người dùng không đoán được.

Đừng thêm lại dưới tên khác nếu nó vẫn chỉ là Trips + Places + một năm.

## 4. Nút dựng phim

màn danh sách ảnh có nút **film** ở toolbar, mở thẳng Video Studio với **đúng thứ tự
đang hiện**.

- Một chuyến đi vốn đã là một chuỗi ảnh được chọn và xếp sẵn — phần khó nhất của việc dựng
  phim. Phần còn lại thuộc về timeline, nên nút này **giao ảnh qua** chứ không tự dựng sẵn một cuốn phim
  không ai đặt.
- Giới hạn **60 clip** (~2 phút ở thời lượng ảnh mặc định): project giữ mọi clip trong bộ nhớ, và một
  chuyến đi 400 ảnh sẽ ra một timeline không ai thao tác nổi.

## 5. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
