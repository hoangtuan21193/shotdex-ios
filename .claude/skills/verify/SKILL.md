---
name: verify
description: Giai đoạn 4 (Test) của AI-native SDLC — phiên tự chứng minh công việc của mình trước khi tới người: chạy test sau từng tiêu chí nghiệm thu, chụp mọi trạng thái màn hình, báo AC nào chưa chứng minh được. Arguments: <FS-xx>. Chạy trước khi báo "xong".
---

# Verify — giai đoạn Test, vòng phản hồi

| | |
|---|---|
| **Input** | `/verify FS-12` |
| **Cần có sẵn** | các AC đã được làm xong ít nhất một phần |
| **Output** | bảng một dòng một tiêu chí (chứng minh bằng gì · xanh/đỏ/chưa có), danh sách ảnh đã chụp, danh sách tiêu chí **chưa** chứng minh được |
| **Không làm** | không sửa code cho test xanh |
| **Người dùng làm gì tiếp** | còn dòng chưa chứng minh được thì chưa xong — quay lại `/plan` cho phần thiếu |


Playbook: *gói kiểm chứng vào một lệnh, ghi rõ output thế nào là khoẻ, nêu đích đo được, phiên
tự kiểm trước khi người review*. Quy trình repo: `docs/PROCESS.md` mục 2 (bảng lệnh) và mục 5 (cổng chặn).

Skill này **đo rồi nói thật**. Không sửa code cho test xanh.

## Trình tự

1. Mở `FS-xx`, lấy bảng tiêu chí nghiệm thu. Không có → dừng, báo tính năng chưa có định nghĩa "xong".

2. Với từng AC, chạy đúng thứ ghi ở cột "Chứng minh bằng":
   - tên test → `/test <Class/method>`
   - script `Tools/ui-drive` → chạy, lấy ảnh và element dump
   - `⚠️ chưa có` → đánh dấu **chưa chứng minh được**, đề xuất test cần viết

3. `Tools/gate` — build + toàn bộ unit test, để chắc không vỡ chỗ khác.

4. Đụng cấu hình agent (`CLAUDE.md`, `.claude/**`) thì chạy thêm `Tools/evals`.

5. Chụp màn hình **mọi trạng thái** ở mục 3 của tài liệu, trên mọi thiết bị mục 6 nói tới, và
   **cả hai nhánh** `#available(iOS 26.0, *)` nếu code rẽ nhánh (`/screens`).
   iPhone Duo và iPad sau khi xoay: dùng `Tools/sim-shot`, không dùng screenshot của driver.

6. **Nhìn từng ảnh**: control bị cắt hoặc chồng, chữ tràn, thứ nấp sau tab bar, màu/khoảng cách
   lệch `DESIGN.md`, nội dung rỗng nửa vời. Thấy lỗi thì sửa và chụp lại trong cùng lượt.

7. Báo cáo dạng bảng, một dòng một AC:

   | AC | Chứng minh bằng | Kết quả |
   |---|---|---|
   | AC-1 | `VideoStudioModelTests.splitAtPlayhead` | ✅ xanh |
   | AC-4 | — | ⚠️ chưa có test |

   Kèm danh sách ảnh đã chụp. **Còn một AC chưa chứng minh được thì tính năng chưa xong** — nói
   đúng như vậy, không làm tròn lên.

8. Cập nhật cột "Chứng minh bằng" trong `FS-*` cho các AC vừa có test.

9. Cập nhật dòng `Tiến độ` của intent gốc theo kết quả vừa đo (luật: `docs/PROCESS.md` mục 2, "Dòng
   Tiến độ"): `xong` chỉ khi **mọi** AC xanh và `Tools/gate` xanh; còn AC chưa chứng minh thì `gần xong`
   (mọi task đã commit) hoặc `đang làm`, kèm `x/N AC xanh` và danh sách AC còn thiếu.

## Sửa bug

Viết test **đỏ** tái hiện lỗi trước. Trong lúc sửa, bật `export SHOTDEX_FREEZE_TESTS=1` — hook
`.claude/hooks/freeze-tests.sh` sẽ chặn mọi sửa đổi vào file test, để không ai làm test xanh bằng
cách sửa test. Xong thì thêm lỗi đó thành một AC, và thành một eval nếu nó là lỗi của cấu hình agent.
