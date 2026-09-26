# REVIEW.md — chính sách review

Mọi thay đổi đều đi qua **cùng một bộ** ba lớp dưới đây, không phụ thuộc ai viết hay gấp cỡ nào.
Giai đoạn Deploy của [`docs/PROCESS.md`](docs/PROCESS.md).

Cách gọi: *"review thay đổi này theo REVIEW.md"*, hoặc chạy `/review-sweep` cho một vùng.

## Xếp hạng

| Hạng | Nghĩa | Xử lý |
|---|---|---|
| **Important** | sai kết quả, mất dữ liệu, rò riêng tư, crash, lệch spec, chặn người dùng | sửa trước khi merge |
| **Nit** | phong cách, đặt tên, gọn hơn được | sửa nếu rẻ, không thì bỏ qua |

Mỗi phát hiện phải có `file:line`, một câu mô tả lỗi, và **một kịch bản hỏng cụ thể**
(đầu vào nào → kết quả sai nào). Không có kịch bản hỏng thì không phải Important.

## Lớp 1 — Bugs

- Lỗi logic, điều kiện biên, off-by-one, chia cho 0, optional ép mở.
- Hồi quy: thay đổi này làm hỏng đường nào đang chạy đúng?
- Concurrency: actor isolation, `@MainActor` rò ra background, `Sendable`, task không huỷ được,
  `Task {}` sống lâu hơn chủ của nó. Agent: `swift-concurrency`.
- Vòng giữ và bộ nhớ: closure giữ `self` mạnh, observer không gỡ, cache không trần,
  decode full-res chỗ chỉ cần thumbnail. Agent: `memory-leak`.
- PhotoKit: proxy của Optimize Storage, change token, ảnh ẩn / đã xoá, quyền `.limited`.
  Agent: `photokit-guard`.
- Dữ liệu: indexer ghi đè nguyên row `photo_metadata` → **dữ liệu người dùng tự nhập phải ở bảng
  riêng**. Migration có đường lùi không? Agent: `data-migration`.

## Lớp 2 — Security và privacy

- Cam kết local-only ([NF-03](docs/04-non-functional-design/NF-03-privacy-and-security.md)):
  thay đổi này có làm dữ liệu rời máy không? Ngoại lệ duy nhất được phép là tin nhắn Support do
  người dùng chủ động gửi.
- Vị trí ảnh: có lọt vào file chia sẻ khi người dùng đã tắt không?
- Không log nội dung ảnh, không log đường dẫn chứa tên người, không log toạ độ.
- Không credential, token, key trong diff.
- Required-reason API dùng đúng mã lý do; usage string đủ. Agent: `privacy-manifest`.

## Lớp 3 — Compliance

- Khớp `intent.md`: thay đổi này có giải đúng vấn đề đã nêu không, hay đã trôi sang chuyện khác?
- Khớp `FS-*`: mọi AC đụng tới đều còn đúng; AC mới đã ghi vào tài liệu.
- Khớp `plan.md`: diff có đi đúng kế hoạch đã duyệt không? Lệch thì nói ra, đừng im.
- Khớp `DESIGN.md`: token, bo góc, tier, lối vào glass — không bịa hằng số mới.
  Agent: `design-reviewer`.
- Khớp thiết bị: iPhone · iPad · Duo trong 951×669 · Duo ngoài 466×678, và **cả hai nhánh**
  `#available(iOS 26.0, *)` làm được cùng một việc. Agent: `device-layout`, `ios26-parity`.
- Tài liệu đã cập nhật trong **cùng lượt** với code.

## Sau review

- Phát hiện nào xuất hiện **lần thứ hai** → viết vào `CLAUDE.md`, đừng sửa lại lần nữa bằng tay.
- Phát hiện nào là lỗi của **cấu hình agent** (skill sai, CLAUDE.md thiếu, hook không chặn)
  → thêm một eval vào `evals/`.
- Việc đáng làm nhưng ngoài phạm vi → `REVIEW_QUEUE.md`, không làm luôn.
