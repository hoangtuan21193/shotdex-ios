# FS-03.03 — Cử chỉ slider, so sánh và undo

`FS-03.03` · `EditorSliderRow` · `EditorImageStage` · `PhotoEditHistory` · cập nhật 2026-09-22

**Một câu:** một cú vuốt chéo không được cướp mất cuộn panel, và mọi bước chỉnh đều quay lại được.

## 1. Quy tắc

- **Chủ sở hữu một cú vuốt quyết định trong 8pt đầu**, và quyết **trước** khi hệ thống kịp bắt đầu cuộn.
- Tiêu chí là **góc, không phải trục nào lớn hơn**.
- Khi slider nhận thì **cuộn tắt hẳn** tới lúc nhả tay — không có trạng thái cả hai cùng nhận.
- **Panel giữ nguyên chiều cao** lúc đang kéo, và **không vẽ số lớn lên ảnh**.
- Undo giữ **toàn bộ phiên**.

## 2. Tranh chấp cử chỉ

- Ngưỡng **8pt** thấp hơn ngưỡng ~10pt mặc định của hệ thống, và phán quyết chạy từ toạ độ chạm thô. Quyết
  muộn hơn thì cú vuốt dọc vẫn kịp bật slider và tắt cuộn trong cùng một frame — đúng cái làm giữa panel
  khó cuộn.
- Slider chỉ nhận khi hướng nằm trong **±25° của trục ngang**. So "dọc lớn hơn ngang" là quá dễ cho slider
  (vuốt chéo 40° vẫn thắng), làm giữa panel gần như không cuộn được.
- Chỉ đổi giá trị sau **6pt** di chuyển; mapping **tương đối** (theo độ dịch) chứ không nhảy tới điểm chạm.

## 3. Mốc và phản hồi

- **Mốc identity**: đang kéo mà đi qua giá trị identity thì trỏ **snap vào đúng identity** trong bán kính
  **6pt trên rãnh** — hẹp có chủ ý, mốc rộng làm các giá trị nhỏ quanh 0 không bấm tới được. Tính theo
  điểm màn hình nên mọi dải giá trị đều cùng cảm giác, kèm một haptic gọn khi vừa vào mốc.
- Straighten có mốc 0°, Intensity có mốc 100%.
- Chạm đôi lên nhãn = reset về identity (kèm haptic); chạm lên cột số = mở bàn phím số (parse và clamp).
- Khi slider nhận: haptic nhẹ, dòng sáng lên, rãnh và trỏ to ra. Giá trị đọc ngay ở cột số của dòng đang
  chỉnh, ảnh không bị chữ che.
- Nhả tay sau cú kéo **< 250ms** thì hiện toast `Contrast +0.35 → +0.12 · Undo` trong 3s.

## 4. Chip tỉ lệ giữ nguyên diện tích khung

Đổi tỉ lệ thì khung được tính lại **quanh chính tâm nó với diện tích không đổi**, chỉ clamp khi tỉ lệ đó
không vừa ảnh ở diện tích ấy.

Bản cũ nội tiếp tỉ lệ mới vào khung cũ nên mỗi lần chạm mất một dải — bấm 1:1 · 4:3 · 1:1 vài lượt là
khung teo dần về gần bằng không.

**Original** trả khung về **full frame**, đúng nghĩa "ảnh nguyên bản", chứ không nội tiếp tỉ lệ ảnh vào
khung đang có. **Free** không đụng vào khung.

## 5. So sánh và xem toàn màn

- **Chạm đôi vào ảnh** vào/ra chế độ tràn viền (ẩn băng lệnh + panel, chỉ còn card histogram nếu đang mở
  và một pill hướng dẫn). Pinch zoom tới **6×**.
- **Xem ảnh gốc** = giữ nút before/after trên băng, hoặc giữ tay lên ảnh.
- Thanh chia BEFORE/AFTER vẫn còn trong mã nhưng **không có lối vào** — before/after hiện là giữ-xem-gốc.

## 6. History và Reset

- **History** là sheet liệt kê mọi bước của phiên, nhãn suy ra bằng cách so hai recipe liền nhau, kèm
  khoảng cách `now / −2 / +1`; chạm để nhảy tới bước đó.
- **Reset All** (menu ⋯) đưa mọi chỉnh sửa trong **phiên đang mở** về identity — và **vẫn Undo được**.
- Không dùng chữ "Revert" cho việc này, để khỏi nhầm với thao tác phục hồi bản gốc của Photos
  ([FS-03.01](01-scope-and-panel.md)).

## 7. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
