# FS-04 — Màu: Mixer, Point Color, Grading, Curve

`FS-04` · tier D · `Features/Editing/EditorColorPanel.swift` · `ShotDexKit` (render màu)
· `Domain/Editing/ColorRenderMath.swift` · test `PhotoColorModelsTests` · `ColorRenderMathTests`
· `ToneCurveMathTests` · cập nhật 2026-09-22

**Một câu:** bốn khối chỉnh màu của editor — đủ ba khối màu của Lightroom cộng tone curve — và Depth Blur.

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 01 | [Mixer và Point Color](01-mixer-and-point-color.md) | 24 slider theo băng màu, ống hút màu, kính lúp soi pixel |
| 02 | [Grading và Tone Curve](02-grading-and-curve.md) | 4 vùng × 3 slider, đồ thị đè lên ảnh, preset |
| 03 | [Depth Blur](03-depth-blur.md) | ảnh Portrait, vì sao hai filter của Apple đều không dùng được |

## Quy tắc

- **Chỉ áp cho cả ảnh.** Không khối màu nào xuất hiện trong phần chỉnh của một mask, và render cũng chỉ áp
  **một lần** ở vị trí toàn ảnh.
- **Không bao giờ nâng phiên bản của công thức sửa ảnh.** Mọi trường đọc theo kiểu "có thì đọc, không thì
  lấy mặc định", và chỉ ghi phần khác mặc định — nên một ảnh không đụng màu thì trong công thức **không có
  khối màu nào**. Nâng phiên bản sẽ làm app từ chối đọc công thức cũ.
- **Toán quyết định nằm ở tầng logic thuần và có test**, còn mã chạy trên GPU **sinh từ cùng những hằng số
  đó** — nên GPU không thể lệch khỏi test.
- Mỗi cú kéo là **một** bước hoàn tác.
- Chỗ nào hỏi "có đang kéo slider không" thì phải xét **cả hai loại** slider của editor, nếu không panel sẽ
  vừa cuộn vừa chỉnh.

## Thứ tự render

```
tone → màu → curve → filter → crop → mask
```

Khối màu chèn giữa phần chỉnh tone toàn ảnh và phần filter, tại **đúng ba chỗ** gọi render: render chính,
ảnh nền cho mask tự động, và bộ dựng khung của Live Photo. Ba phép biến đổi liên tiếp được gộp thành **một
lượt chạy trên GPU**; khối nào ở trạng thái mặc định thì bỏ qua hẳn. Việc này **không đụng** tới phần decode
RAW và không đổi khoá cache của mask.

## Model

Công thức sửa ảnh mọc thêm **đúng một khối màu** gồm mixer, các điểm màu và grading.

| Phần | Nội dung |
|---|---|
| Mixer | 8 băng màu × (hue, saturation, luminance), giá trị −1…1; hue lệch tối đa ±30° |
| Point Color | màu tham chiếu (hue, saturation, độ sáng) + ba mức dịch + **bán kính** (mặc định 0,5), **tối đa 8 điểm** |
| Grading | 4 vùng × (hue, saturation, luminance) + **Blending** (mặc định 0,5) + **Balance** |
| Tone Curve | 4 chuỗi điểm — RGB chung và R/G/B riêng; mặc định là đường thẳng |

"Đã sửa gì chưa" của cả ảnh tính luôn cả khối màu, nên nhãn Reset trong lịch sử vẫn đúng.

## Panel

- **Không còn ô chọn mục trong panel** — mỗi tab vẽ thẳng một khối. Panel chỉ cao ~230–280pt nên mỗi khối
  chiếm trọn phần còn lại, thay vì dồn ba khối vào một danh sách cuộn dài.
- Ba tab **Mixer / Point / Grading** đứng liền nhau ngay bên phải Adjust; tab Color còn lại Temp, Tint,
  Vibrance, Saturation và công tắc đen trắng.
- Mọi slider ở đây có thể thay rãnh bằng **dải màu** (và khi có dải màu thì tắt phần tô accent, giữ vạch
  mốc). Giá trị hiển thị ±100, lưu −1…1.

## Lịch sử

Nhãn bước nói ra **đúng thứ vừa đổi**: "Mixer · Red Hue +20" · "Added/Removed Point Color" ·
"Grading · Shadows" · "Grading · Blending 65".

## Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
