# FS-12.02 — Năng lực biên tập clip

`FS-12.02` · `Domain/Video/` (`VideoSplitMath`, `VideoTimelineMath`) · `VideoStudioModel`
· cập nhật 2026-09-22

**Một câu:** mọi năng lực đều đi qua pipeline sẵn có — không mở đường dựng thứ hai cho bất kỳ tính năng nào.

## 1. Quy tắc

- Thêm năng lực = thêm tham số vào recipe, **không** thêm đường render.
- Thay đổi nào ảnh hưởng thời lượng thì phải để phần đặt clip và fade **tự tính lại**, không sửa tay.

## 2. Bảng năng lực

| Năng lực | Cách làm | Ghi chú |
|---|---|---|
| **Speed** 0,25–4× | co giãn đoạn đã chèn (cả video lẫn âm thanh) về đúng ô thời gian | thời lượng hiệu dụng = trim ÷ speed nên vị trí và fade tự đúng; **âm thanh đổi cao độ** (chấp nhận ở v1) |
| **Freeze** | trích một khung từ video lúc nạp (dung sai bằng 0) rồi giữ như ảnh tĩnh trên xương sống đen | không phải tra lại thư viện ảnh |
| **Split** | cắt clip dưới playhead thành hai (math thuần, có test) | video quy đổi thời gian cục bộ về nguồn qua trim + speed; ảnh và freeze thì chia đôi thời lượng; hai clip con **dùng chung nguồn đã nạp** |
| **Tỉ lệ khung** 16:9 · 9:16 · 1:1 · 4:5 | đổi kích thước khung thật | portrait và vuông là **khung thật**, compositor letterbox lên **màu nền của recipe** |
| **Màu nền** | dùng ở hai chỗ letterbox của compositor | slide và zoom lộ nền cũng dùng màu này; fadeBlack vẫn đen theo đúng tên nó |
| **Master volume** | nhân vào mọi đường âm lượng của clip và nhạc | — |
| **Nhạc nhiều bản** | mỗi bản có **mốc bắt đầu, trim hai đầu, âm lượng, fade in/out riêng** | kéo băng trên timeline để dời, kéo tay nắm để cắt. **Loop đã bỏ hẳn** |
| **Sticker / overlay ảnh** | dùng lại đường rasterize overlay của editor ảnh | picker ghi PNG vào kho overlay dùng chung; **không đụng compositor** |
| **Thay / thêm media** | chọn từ picker rồi nạp nguồn **cho riêng clip đó** rồi ghép vào | không nạp lại cả project |

## 3. Tiêu chí nghiệm thu

Xem [README](README.md).
