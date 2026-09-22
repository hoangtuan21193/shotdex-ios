# Intent: <tiêu đề ngắn>

| Trường | Giá trị |
|---|---|
| Tác giả | |
| Ngày | YYYY-MM-DD |
| Trạng thái | draft / accepted / dismissed |
| Nguồn | tự nghĩ ra / phản hồi người dùng / crash log / vượt control band / kết quả quét bảo mật |
| Spec sinh ra từ đây | (điền khi sang Design) |

## Problem — vấn đề

Hôm nay người dùng **không làm được gì**? Ai bị ảnh hưởng? Mức độ ra sao?
Viết bằng lời của người chụp ảnh, kèm bằng chứng nếu có (log, ảnh, câu phàn nàn, con số).

## Proposed outcome — kết quả mong muốn

Tốt hơn thì trông như thế nào. Vẫn là **kết quả**, chưa phải giải pháp kỹ thuật.

## Affected users and systems — phạm vi ảnh hưởng

- Màn hình / tính năng nào
- Thiết bị nào (iPhone · iPad · Duo trong · Duo ngoài)
- Tầng nào của code (Domain / Data / Features / ShotDexKit / extension)
- Có đụng dữ liệu người dùng đã lưu không (→ cần migration?)

## Constraints — ràng buộc

Cái gì **không được** làm. Ví dụ: không rời máy dữ liệu người dùng; không thêm dependency;
không phá trần bộ nhớ extension; không làm hỏng nhánh iOS 26; không đổi schema đang có dữ liệu.

## Open questions — câu hỏi còn treo

Cái gì chưa biết, và **ai/cái gì trả lời được**. Câu hỏi còn treo thì chưa được sang Design.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
