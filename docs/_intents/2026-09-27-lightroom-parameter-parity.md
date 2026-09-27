# Intent: Đủ mọi thông số chỉnh của Lightroom (trừ mask AI cần model mới và HDR)

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan |
| Ngày | 2026-09-27 |
| Trạng thái | accepted |
| Tiến độ | **chưa làm** (2026-09-27) — chưa có spec |
| Nguồn | phản hồi người dùng (chủ sở hữu sản phẩm) — "tôi muốn phản ánh được all thông số từ xmp của lightroom" |
| Spec sinh ra từ đây | (điền khi sang Design) |

Liên quan: [lightroom-preset-exchange](2026-09-27-lightroom-preset-exchange.md) (lý do trực tiếp: preset nhập
vào phải có chỗ đặt từng thông số) · [editor-iphone-layout](2026-09-27-editor-iphone-layout.md) (Transform,
Heal, Mask đã vẽ chỗ cho các control mới) · [lens-correction-sources](2026-09-27-lens-correction-sources.md)
(phần Lens profile tách riêng) · nối tiếp FS-03.11
([11-parity-with-lightroom.md](../02-functional-spec/FS-03-photo-editor/11-parity-with-lightroom.md)).

## Problem — vấn đề

Preset Lightroom mang những thông số ShotDex không có chỗ đặt, nên nhập vào sẽ mất một phần look, và người
chụp quen Lightroom tìm không thấy control. So `crs:` (danh sách thẻ theo
[ExifTool XMP crs](https://exiftool.org/TagNames/XMP.html), bổ sung từ hiểu biết — cần kiểm lại) với model
`PhotoAdjustments` ([PhotoEditingModels.swift:569](../../ShotDexKit/Models/PhotoEditingModels.swift)),
`PhotoColorRecipe`, `ToneCurveAdjustments`, `PhotoMask` (2026-09-27):

**Đã có đủ** (không thuộc intent này): Basic (WB, Exposure…Blacks, Texture, Clarity, Dehaze, Vibrance,
Saturation) · Tone curve điểm 4 kênh · HSL 8 dải · Color Grading 4 bánh + Blending + Balance · Point Color ·
Sharpening 4 slider · Transform V/H/Rotate/Scale/Offset · Crop · Vignette hậu crop 5 slider · Grain 3 slider ·
B&W bật/tắt · mask Subject/Sky/Brush/Linear/Radial/Color/Luminance/Depth/Face Skin/Eyes/Lips, cộng/trừ.

**Thiếu hoặc thiếu chi tiết** (phạm vi intent này):

| Nhóm | Thiếu |
|---|---|
| Tone | tone curve **dạng vùng** (Parametric Shadows/Darks/Lights/Highlights + 3 điểm chia) |
| B&W | **mixer 8 màu** (GrayMixer) |
| Calibration | Shadow Tint, Red/Green/Blue Hue & Saturation |
| Noise Reduction | Luminance Contrast, Color Detail, Color Smoothness |
| Defringe | tách Purple / Green Amount + dải Hue (hôm nay một mức chung) |
| Transform | **Aspect**; **Upright** Auto/Level/Vertical/Full/Guided + đường guide |
| Vignette | Style: Highlight Priority / Color Priority / Paint Overlay |
| Retouch | vết Heal/Clone **dạng nét cọ**; **Remove** (content-aware); Opacity; New Source; Visualize Spots + Threshold; Show Spot Pins; Clear All |
| Red Eye | chưa có |
| Mask — ghép | phép **giao** (Intersect) |
| Mask — thông số riêng | Hue, Color (phủ màu), Tone Curve, Point Color, Moiré, Defringe cho từng mask |
| Mask — loại vùng dùng API iOS | **Object** (chạm chọn chủ thể, Vision `VNGenerateForegroundInstanceMaskRequest`), **People** (Vision person segmentation), **tóc / da / răng / kính** khi ảnh có sẵn `AVSemanticSegmentationMatte` |
| Lens Blur | đầy đủ (dải lấy nét, hình bokeh, độ mạnh) — hôm nay chỉ một slider `depthBlur` |

## Proposed outcome — kết quả mong muốn

- Mỗi thông số ở bảng trên có **control trong editor** (chỗ đặt theo canvas của
  [editor-iphone-layout](2026-09-27-editor-iphone-layout.md)) **và** có trường tương ứng trong recipe để
  preset Lightroom đổ vào.
- **Lens Blur**: ảnh có độ sâu (Portrait / iPhone lưu depth) — đầy đủ, bokeh bằng kernel Metal CI (đường
  FS-16). Ảnh không có độ sâu — thử model ước lượng độ sâu (Depth Anything V2 từ trang Core ML models của
  Apple) rồi mới quyết có kèm vào app không; chưa quyết thì Lens Blur mờ đi kèm một dòng giải thích.
- **Remove** content-aware chạy trên máy.
- Kết quả gần Lightroom nhất có thể — **không hứa giống hệt** (mỗi engine tính "Exposure +0.5" một kiểu).

## Affected users and systems — phạm vi ảnh hưởng

- **Code**: `ShotDexKit/Models` (trường mới trong `PhotoAdjustments`, `PhotoColorRecipe`, `PhotoMask`,
  `PhotoHealingSpot`, `MaskBlendOperation.intersect`); `ShotDexKit/Render` (`PhotoRenderService` + extensions:
  calibration, parametric curve, gray mixer, NR thêm, defringe, upright/aspect, vignette style, red eye, local
  curve/point color/hue, lens blur, remove); kernel Metal CI (FS-16); `Features/Editing` (control);
  `Domain/Editing` (catalog thông số, Upright tính đường thẳng); Vision/AVFoundation cho mask.
- **Extension**: widget/share render qua kit — pass mới phải vừa trần bộ nhớ extension.
- **Dữ liệu đã lưu**: recipe thêm trường. App chưa phát hành → không migration (luật 2026-09-23); decode vẫn
  lossy.

## Constraints — ràng buộc

- **Không mask AI cần model tự kiếm** (lông mày, quần áo, tách tròng trắng/mống mắt) — để sau; gặp trong
  preset thì bỏ qua và ghi vào báo cáo import.
- **HDR** (HDREditMode, xuất gain map) **không thuộc intent này** — intent riêng sau.
- Không huấn luyện model; model bên thứ ba chỉ dùng loại Apple công bố cho Core ML (như DETR đang kèm), và
  chỉ sau thử nghiệm có số đo dung lượng / chất lượng.
- Mọi thứ trên máy; không gửi ảnh đi đâu.
- Không hạ độ phân giải preview khi kéo (FS-03.04) — pass nặng (Remove, Lens Blur) phải có chiến lược riêng.
- Kit không import SwiftUI/GRDB; type mới trong kit là `public`.

## Open questions — câu hỏi còn treo

Chặn Design cho phần tương ứng (các phần khác đi trước được):

1. **Remove content-aware**: thuật toán vá ảnh tự viết hay model Core ML? Chất lượng, tốc độ trên iPhone 12
   trở lên? → thử nghiệm riêng.
2. **Depth Anything V2**: dung lượng, thời gian chạy, mép tóc; có đáng kèm vào app không? → thử nghiệm.
3. **Hệ số quy đổi** từng slider Lightroom → ShotDex (Exposure, Contrast, Clarity, Texture, Dehaze, Grain
  size…): cần bộ ảnh xử lý ở cả hai app để đo. → thử nghiệm dùng chung với
  [lightroom-preset-exchange](2026-09-27-lightroom-preset-exchange.md).
4. Danh sách thẻ `crs:` đầy đủ của Lightroom hiện tại (13–15), gồm cấu trúc `MaskGroupBasedCorrections` và
  `RetouchAreas`. → agent `lightroom-parity` trong `/spec`.
5. Red Eye: tự phát hiện mắt (Vision face landmarks) hay chỉ chạm tay? → người dùng, trong `/spec`
  (đề xuất: chạm vào mắt, Vision căn tâm).

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
