---
name: intent
description: Giai đoạn 1 (Plan) của AI-native SDLC — biến một ý tưởng, một lời phàn nàn, một crash hay một lần vượt control band thành docs/_intents/<ngày>-<slug>.md có version, trước khi bàn tới yêu cầu chi tiết. Arguments: <slug hoặc mô tả ngắn>. Không viết code, không viết spec.
---

# Intent — giai đoạn Plan

| | |
|---|---|
| **Input** | một câu mô tả vấn đề bằng lời thường. Không cần đặt tên chuẩn, không cần biết nó thuộc màn nào |
| **Cần có sẵn** | không cần gì |
| **Output** | `docs/_intents/<YYYY-MM-DD>-<slug>.md` — 5 mục theo mẫu |
| **Không đụng** | `.swift`, tài liệu đặc tả, tiêu chí nghiệm thu |
| **Người dùng làm gì tiếp** | sửa file, trả lời Open questions, đổi `Trạng thái: accepted`, commit riêng, rồi `/spec` |


Playbook: <https://claude.com/blog/the-ai-native-sdlc-playbook> · quy trình repo: `docs/PROCESS.md` mục 2 (bảng lệnh).

Đầu ra là **một file `intent.md`**. Không sửa `.swift`, không viết spec, không đề xuất kiến trúc.

## Trình tự

1. **Nghe trước.** Người dùng mô tả bằng lời thường. Đừng chuẩn hoá vội, đừng nhảy sang giải pháp.

2. **Tìm bằng chứng** trước khi viết: log, crash `.ips`, ảnh chụp, mục trong `REVIEW_QUEUE.md`,
   kết quả `Tools/bands-check`, hoặc chỗ code đang gây ra vấn đề. Một intent không có bằng chứng
   là một ý thích.

3. **Viết nháp** `docs/_intents/<YYYY-MM-DD>-<slug>.md` theo
   `docs/_templates/TEMPLATE-intent.md`, đủ năm mục:

   | Mục | Luật |
   |---|---|
   | Problem | hôm nay người dùng **không làm được gì**; ai bị ảnh hưởng; mức độ. Không mô tả giải pháp |
   | Proposed outcome | trông ra sao khi tốt hơn — vẫn là kết quả, chưa phải cách làm |
   | Affected users and systems | màn hình, thiết bị, tầng code, có đụng dữ liệu đã lưu không |
   | Constraints | cái gì off-limits: local-only, không thêm dependency, trần bộ nhớ extension, nhánh iOS 26, schema đang có dữ liệu |
   | Open questions | cái gì chưa biết và ai trả lời được |

   Dòng `Tiến độ` ghi `**chưa làm** (<ngày>) — chưa có spec` (luật: `docs/PROCESS.md` mục 2, "Dòng Tiến độ").

4. **Hỏi lại** những chỗ mình phải đoán, mỗi câu kèm phương án mặc định đề xuất. Câu hỏi chưa
   trả lời thì để nguyên ở mục Open questions — **còn câu hỏi treo thì chưa được sang Design.**

5. **Báo cáo**: đường dẫn file, các câu hỏi còn treo, và nói rõ bước kế: người dùng sửa + duyệt,
   commit riêng một commit, rồi `/spec`.

## Không làm

- Không gộp nhiều vấn đề vào một intent. Hai vấn đề → hai file.
- Không viết tiêu chí nghiệm thu ở đây (đó là việc của `/spec`).
- Không tự đặt trạng thái `accepted` — chỉ người dùng duyệt.
