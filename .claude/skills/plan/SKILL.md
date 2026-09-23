---
name: plan
description: Giai đoạn 3 (Build) của AI-native SDLC — chạy plan mode trên một FS-* đã duyệt, đối chiếu từng tiêu chí nghiệm thu với code hiện có (đã đạt / lệch / chưa có, kèm file:line), ra docs/_plans/<ngày>-<slug>.md rồi dừng chờ duyệt. Arguments: <FS-xx>. Không viết code trong lượt này.
---

# Plan — giai đoạn Build, phần trước khi gõ code

| | |
|---|---|
| **Input** | `/plan FS-12` |
| **Cần có sẵn** | `FS-12` đã có bảng tiêu chí nghiệm thu và đã được duyệt |
| **Output** | `docs/_plans/<YYYY-MM-DD>-<slug>.md`: bảng đối chiếu từng tiêu chí ↔ code (✅/⚠️/❌/❓ kèm `file:line`), thứ tự task, rủi ro |
| **Không đụng** | `.swift` |
| **Người dùng làm gì tiếp** | duyệt bảng, quyết từng dòng ⚠️ (tài liệu đúng hay code đúng), commit riêng, rồi gõ `làm AC-1` |


Playbook: *plan mode trước khi implement*. Kế hoạch phải nói **file nào đổi · thứ tự làm ·
test nào chứng minh là xong · rủi ro**. Quy trình repo: `docs/PROCESS.md` mục 2 (bảng lệnh).

Đầu ra là **một file kế hoạch**. Không sửa `.swift`.

## Trình tự

1. Đọc `FS-xx`. **Không có bảng tiêu chí nghiệm thu → dừng**, bảo người dùng chạy `/spec`.
   Kế hoạch không có đích thì không phải kế hoạch.

2. Đọc `intent.md` gốc nếu có: kế hoạch phải giải đúng vấn đề đó, không trôi sang chuyện khác.

3. **Đọc code thật** ở các đường dẫn ghi trong hàng "Mã nguồn" và "Test" của tài liệu, cùng những
   gì chúng gọi tới. **Cấm xếp loại một AC khi chưa mở file liên quan.**

4. **Bảng đối chiếu AC ↔ code** — phần quan trọng nhất của kế hoạch trong một codebase đã có sẵn:

   | AC | Trạng thái | Bằng chứng | Việc |
   |---|---|---|---|
   | AC-1 | ✅ code đã đạt | `VideoStudioModel.swift:412` | không sửa code, chỉ viết test khoá lại |
   | AC-2 | ⚠️ lệch | `…:88` undo gộp 2 bước | **hỏi**: tài liệu đúng hay code đúng? |
   | AC-3 | ❌ chưa có | không tìm thấy đường code | làm mới + test |
   | AC-4 | ❓ chưa kết luận | — | nói vì sao, cấm đoán |

   Với mọi dòng ⚠️: hỏi người dùng một câu cho mỗi chỗ, **không tự quyết**.

5. Ghi lại **cái gì tái dùng được** — component, store, math đã có. Đây là chặn "một khái niệm
   hai cách làm".

6. Tạo `docs/_plans/<YYYY-MM-DD>-<slug>.md` từ `docs/_templates/TEMPLATE-plan.md`, đủ:
   - bảng file đổi, và **tầng** nhận logic: Domain (thuần, test được) / Data / Features.
     Logic không vào View. Dữ liệu người dùng tự nhập → bảng riêng.
   - thứ tự task: **một AC = một task = một commit**, test đi kèm từng task.
     Thứ tự làm: ✅ (viết test) trước → ⚠️ theo quyết định → ❌ sau cùng.
   - rủi ro: dữ liệu (migration có đường lùi?), bộ nhớ (trần extension), thiết bị (Duo 669pt),
     concurrency, PhotoKit.
   - cách chứng minh là xong: test nào, màn hình nào phải chụp, tài liệu nào phải cập nhật.

7. Chọn agent sẽ chạy ở giai đoạn Deploy theo vùng đụng: `data-migration`, `swift-concurrency`,
   `photokit-guard`, `device-layout`, `ios26-parity`, `extension-boundary`, `memory-leak`.

8. Dòng `Tiến độ` của intent gốc: `**chưa làm** (<ngày>) — plan <link> chờ duyệt, N task`.

9. **Dừng, chờ duyệt.** Không tự chạy sang code.

## Khi đã duyệt

Làm từng task một, mỗi task một commit (`feat(FS-12): AC-3 …`), build sau mỗi commit
(`/build`), đụng UI thì thêm `/screens`. Mỗi AC xong thì **sửa ngay** cột "Chứng minh bằng"
trong `FS-*` từ `⚠️ chưa có` thành tên test thật. Đóng lại bằng `/verify` và `Tools/gate`.

Sau **mỗi** commit task, sửa dòng `Tiến độ` của intent gốc trong cùng commit:
`**đang làm** (<ngày>) — task k/n, x/N AC xanh`; commit task cuối thì `**gần xong**` nếu còn AC chưa
chứng minh. Chỉ `/verify` được ghi `xong` (luật: `docs/PROCESS.md` mục 2, "Dòng Tiến độ").

Việc đáng làm nhưng ngoài bảng AC → `REVIEW_QUEUE.md`, không làm luôn.
