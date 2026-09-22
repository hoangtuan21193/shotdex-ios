# FS-06.03 — Memories, `PhotoListScreen` và dựng phim

`FS-06.03` · `Domain/Places/MemoryBuilder.swift` · `Features/Shared/PhotoListScreen.swift`
· cập nhật 2026-09-22

**Một câu:** một lưới dùng chung cho mọi danh sách assetId tự tính, cộng những bộ sưu tập app dám tự dựng.

## 1. Quy tắc

- **Cố ý không bắt chước Memories của Apple.** Apple dựng nó từ nhận diện mặt, phân loại cảnh và một model
  curation — app không có thứ nào trong đó, mà làm bản nhái yếu sẽ ra những bộ sưu tập người dùng không
  đoán được và không tin được.
- Mỗi memory ở đây luôn là thứ người dùng **tự tìm được**: một chuyến đi, một năm, một nơi. Tiêu đề nói rõ
  nó là cái nào.
- màn danh sách ảnh **chỉ để duyệt** — không có chế độ chọn nhiều ảnh, vì đây là danh sách dẫn xuất và một
  selection ở đây không có chỗ về rõ ràng.

## 2. màn danh sách ảnh + model của nó

Hình dạng lưới **thứ ba**, bên cạnh album PhotoKit và truy vấn đã lưu
: một **danh sách assetId tự tính**.

- Giữ **đúng thứ tự caller truyền vào** — một chuyến đi chạy xuôi thời gian, một memory đã được chọn lọc.
- model của nó conform giao thức nguồn ảnh của viewer nên mở thẳng được viewer.
- Dùng cho Places, Trips, Memories, People and Pets.

## 3. Bộ dựng memory

Hàng thẻ **Memories** trên tab Collections, ngay dưới On This Day. Tối đa `limit` **8** thẻ.

| Nguồn | Luật |
|---|---|
| Chuyến đi | 3 cái mới nhất |
| Từng năm đã trọn | 3 năm gần nhất, ≥ tối thiểu **12** ảnh — **bỏ năm hiện tại** vì nó chưa xong (cùng một tiêu đề mà nội dung cứ đổi) |
| Nơi hay quay lại | 2 nơi nhiều ảnh nhất |

Ảnh đã thuộc một chuyến thì **không tính lại** cho năm hoặc nơi. Chạm thẻ → màn danh sách ảnh.

## 4. Nút dựng phim

màn danh sách ảnh có nút **film** ở toolbar, mở thẳng Video Studio với **đúng thứ tự
đang hiện**.

- Một memory hay một chuyến đi vốn đã là một chuỗi ảnh được chọn và xếp sẵn — phần khó nhất của việc dựng
  phim. Phần còn lại thuộc về timeline, nên nút này **giao ảnh qua** chứ không tự dựng sẵn một cuốn phim
  không ai đặt.
- Giới hạn **60 clip** (~2 phút ở thời lượng ảnh mặc định): project giữ mọi clip trong bộ nhớ, và một
  memory 400 ảnh sẽ ra một timeline không ai thao tác nổi.

## 5. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
