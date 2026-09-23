---
name: spec
description: Giai đoạn 2 (Design) của AI-native SDLC — từ một intent.md đã duyệt, soạn hoặc cập nhật tài liệu đặc tả FS-* trong docs/ kèm tiêu chí nghiệm thu kiểm được, áp sẵn mọi ràng buộc chính sách và đánh dấu chỗ vướng. Arguments: <FS-xx hoặc slug của intent>. Không viết code.
---

# Spec — giai đoạn Design

| | |
|---|---|
| **Input** | `/spec FS-12` (màn đã có) hoặc `/spec <đường dẫn intent>` (việc mới) |
| **Cần có sẵn** | một `intent.md` đã `accepted` |
| **Mã FS lấy ở đâu** | `docs/README.md` mục 3 và 4. Tính năng mới → skill tự cấp mã kế tiếp và tự đăng ký vào README |
| **Output** | tài liệu `FS-*` được sửa, trọng tâm là **bảng tiêu chí nghiệm thu**, kèm các dòng `⚠️ CẦN QUYẾT:` |
| **Không đụng** | `.swift` |
| **Người dùng làm gì tiếp** | trả lời từng `⚠️ CẦN QUYẾT`, duyệt bảng tiêu chí, commit riêng, rồi `/plan` |


Playbook: yêu cầu và thiết kế **gộp vào một phiên**, ràng buộc lấy từ skills, kết quả version hoá.
Quy trình repo: `docs/PROCESS.md` mục 2 (bảng lệnh) và mục 6 (cách viết tiêu chí nghiệm thu).

Đầu ra là **tài liệu**. Không sửa `.swift` trong lượt này.

## Trình tự

1. **Đính `intent.md`.** Không có intent → hỏi người dùng, hoặc chạy `/intent` trước.
   Intent còn câu hỏi treo → giải quyết trước, đừng soạn spec trên nền mơ hồ.

2. **Nạp ràng buộc trước khi viết** — đây là phần "skills as institutional knowledge":
   - `DESIGN.md` — token, màu, bo góc, 4 tier, lối vào glass. Cấm bịa hằng số mới.
   - `docs/04-non-functional-design/` — hiệu năng, bộ nhớ, riêng tư, thiết bị, truy cập.
   - `docs/01-basic-design/BD-02` — luật dữ liệu người dùng phải ở bảng riêng.
   - `docs/README.md` — tài liệu nào đã nói gì, để không mô tả trùng.
   - `FS-*` của các màn liền kề — tránh đặt tên lệch.

3. **Xác định tài liệu đích**: đã có thì mở; chưa có thì cấp mã `FS-xx` kế tiếp, copy
   `docs/_templates/TEMPLATE-functional-spec.md`, đăng ký vào `docs/README.md` mục 3 và 4.

4. **Soạn spec, đánh dấu mọi chỗ vướng** bằng `⚠️ CẦN QUYẾT:` ngay tại chỗ. Vướng là khi yêu cầu
   đụng một ràng buộc ở bước 2 — ví dụ cần một màu chưa có trong `DESIGN.md`, cần thêm cột vào
   `photo_metadata`, cần thêm 40pt chiều cao trên màn Duo chỉ còn 669pt, cần đọc ảnh full-res
   trong extension. **Không tự quyết**; nêu phương án và để người dùng chốt.

5. **Viết tiêu chí nghiệm thu** (mục 7 của mẫu) — phần quan trọng nhất:
   - dạng **Cho / Khi / Thì**, đầu vào có số cụ thể, đúng một thao tác;
   - kết quả quan sát được từ test hoặc từ ảnh chụp màn hình;
   - cột cuối ghi chứng minh bằng `@Test` nào hoặc script `Tools/ui-drive` nào; chưa có thì ghi
     `⚠️ chưa có`, cấm để trống;
   - phải phủ **đường hỏng**: không mạng, iCloud-only, quyền `.limited`, huỷ giữa chừng, undo,
     hết bộ nhớ;
   - 5–15 AC cho một màn bình thường. Dưới 5 là chưa nghĩ đủ.

   Từ cấm trong AC: mượt, trực quan, hợp lý, đẹp, nhanh (không kèm số).

6. **Cập nhật intent gốc**: điền `Spec sinh ra từ đây` bằng link tới `FS-*`, và dòng `Tiến độ` thành
   `**chưa làm** (<ngày>) — spec FS-xx, N AC` (luật: `docs/PROCESS.md` mục 2, "Dòng Tiến độ").

7. **Báo cáo**: đường dẫn, số AC, danh sách `⚠️ CẦN QUYẾT`, câu hỏi còn treo.

## Kết thúc

Nói rõ: người dùng đọc và duyệt, commit tài liệu **riêng một commit** (đó là mốc để so ở giai
đoạn Build), rồi `/plan`. Không tự chuyển giai đoạn.
