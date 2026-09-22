# FS-01.09 — Ghép nhiều ảnh (multiple exposure và focus stack)

`FS-01.09` · `ShotDexKit/PhotoStackRenderer.swift` · `PhotoStackScreen` · cập nhật 2026-09-22

**Một câu:** gộp nhiều ảnh thành một — phơi sáng kép, vệt sáng, dọn người qua đường, hoặc ghép độ nét.

## 1. Quy tắc

- Renderer là **actor trong ShotDexKit** vì nó là render thuần.
- **Ghép lũy tiến** ở mọi mode → bộ nhớ phẳng theo số frame.
- Preview dựng ở 1600pt và **dùng lại** cho mọi lần đổi mode; chỉ khi Save mới nạp full-res.

## 2. Bốn mode

| Mode | Dùng để |
|---|---|
| **average** | phơi sáng kép — chạy trung bình lũy tiến nên stack 40 tấm không clip ở tấm thứ hai |
| **lighten** | vệt sáng, pháo hoa, star trail |
| **darken** | dọn người qua đường khỏi chuỗi chụp tripod |
| **focusStack** | ghép độ nét (macro) |

## 3. Focus stack

1. Align mỗi frame bằng bộ căn ảnh theo tịnh tiến của hệ thống — **chỉ tịnh tiến**: stack macro chụp
   trên ray/tripod, fit homography vào vài pixel trôi là fit nhiễu.
2. Dựng **bản đồ độ nét**: mono → Laplacian 3×3 → độ lớn phản hồi → box blur.
3. Ghép lũy tiến qua phép trộn theo mặt nạ — giữ pixel nét nhất.

Frame sau align phải kéo giãn mép ra vô hạn **trước khi** crop, nếu không mép hở thành viền trắng quanh ảnh.

## 4. Màn hình

`PhotoStackScreen`, tier D: Cancel · tiêu đề · Save; stage đen; panel có picker mode + **một dòng giải
thích mode đó dùng để làm gì**. Save nạp full-res, ghép lại, lưu asset mới qua
đường lưu ảnh mới của app.

Lối vào: chọn ≥ 2 ảnh → ⋯ → **Combine Photos**.

## 5. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
