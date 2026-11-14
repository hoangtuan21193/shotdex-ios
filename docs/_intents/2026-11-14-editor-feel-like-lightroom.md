# Intent: Sửa ảnh mượt như Lightroom

| Trường | Giá trị |
|---|---|
| Tác giả | Hoang Tuan (người dùng) · Claude soạn |
| Ngày | 2026-11-14 |
| Trạng thái | accepted (planboard `.planboard/editor-lightroom`, 1 vòng, đồng ý mọi đề xuất) |
| Nguồn | "Understand how edit image works in the Lightroom app, show me the evidence, and build for shotdex. Không được bỏ chức năng nào của shotdex, chỉ update giao diện và logic bên trong để shotdex hoạt động mượt hơn giống lightroom." |
| Bằng chứng | [docs/_research/2026-11-14-lightroom-develop-re.md](../_research/2026-11-14-lightroom-develop-re.md) (Lightroom Classic 15.6) |
| Spec | [FS-03.18](../02-functional-spec/FS-03-photo-editor/18-editing-feel-like-lightroom.md) |

## Problem
- Kéo thanh trượt khi đã bật khử nhiễu, làm nét, lens blur: ảnh trễ tay — mỗi nhịp vẽ đủ chất lượng ở tới 2400 px và
  tính histogram trên cùng hàng đợi.
- Mỗi lần thả tay giải mã lại file gốc; render cũ không dừng giữa chừng.
- Muốn so vài look phải áp rồi Undo; không có Snapshot; không có so sánh chia đôi dù code đã có; không thấy vùng
  cháy trên ảnh.

## Proposed outcome
Như Lightroom: kéo thì ảnh nháp theo tay, thả thì nét; histogram không làm chậm; giữ ô look để xem thử; Snapshot;
nút chia đôi; lớp cháy sáng/tắt đen bật từ histogram.

## Constraints
- Không bỏ chức năng nào: mọi công cụ, mask, heal, markup, preset, LUT, film, batch, Save/Save Copy, HDR, lens blur.
- Ảnh sau khi thả tay và ảnh lưu ra giống hệt hiện nay (cùng pipeline, cùng chất lượng).
- Snapshot là dữ liệu người dùng: bảng riêng, không vào `photo_metadata`.
- iPhone, iPad, Duo (Mac chưa có trình sửa ảnh).
