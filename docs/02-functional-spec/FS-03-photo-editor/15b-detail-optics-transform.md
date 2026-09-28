# FS-03.15b — Khử nhiễu, Defringe, ống kính chỉnh tay, Aspect, Upright, Vignette Style

`FS-03.15b` · `ShotDexKit/Render/PhotoRenderService+Optics.swift` · `UprightAnalyzer.swift` · cập nhật 2026-09-28

**Một câu:** phần Detail, Optics, Transform và Effects mà Lightroom chia nhỏ hơn ShotDex — mỗi slider
thiếu thêm vào đúng nhóm người dùng đã quen.

Tổng quan: [FS-03.15](15-lightroom-parameter-parity.md). Slider đang có: [FS-03.01b](01b-adjustments-and-crop.md).
Hồ sơ ống kính và ba slider độ mạnh: [FS-03.16](16-lens-correction-sources.md).

## 1. Khử nhiễu: ba slider còn thiếu

Hàng Detail thành: Lum NR · NR Detail · **NR Contrast** · Color NR · **Color Detail** · **Color Smoothness**.

- **NR Contrast** (0…100, mặc định 0): giữ lại tương phản cục bộ ở rìa sau khi khử nhiễu độ sáng — trộn trả
  ảnh gốc theo bản đồ rìa mềm (cùng kernel `edgeMask` của Sharpen Masking, tìm trên ảnh **đã** khử nhiễu để
  hạt không bị coi là rìa, nở 2px rồi làm mềm 1px). Mờ khi Lum NR = 0.
- **Color Detail** (0…100, mặc định 50): giữ rìa màu mảnh (chữ đỏ nhỏ, viền lá) — khử nhiễu màu yếu đi ở
  chỗ sắc độ đổi gắt. Mờ khi Color NR = 0.
- Color NR giờ **chỉ đụng sắc độ**: ảnh được làm mờ (bán kính 1 + 4 × Color NR px) rồi lấy sắc độ (màu trừ độ sáng)
  của bản mờ thay cho bản gốc; độ sáng giữ nguyên. Color Detail giữ lại sắc độ gốc ở chỗ nó đổi hơn mức nhiễu
  (kernel `chromaDenoise`). *Thay `CINoiseReduction`, vốn làm mềm cả độ sáng.*
- **Color Smoothness** (0…100, mặc định 50): xoá vết loang màu tần số thấp (cỡ 8–32px) bằng làm mờ sắc độ
  bán kính lớn, không đụng độ sáng. Mờ khi Color NR = 0.
  Trên hàng ghi **Smoothness** (ngay dưới Color Detail): "Color Smoothness" không vừa cột nhãn 78pt. Làm mờ
  sắc độ bán kính 16px, trộn bằng kernel `chromaBlend` — kernel Moiré sẽ dùng lại.
- Cả ba chạy trong lượt NR, trước mọi làm nét (thứ tự FS-03.11 §6 giữ nguyên). Kernel mới viết Metal (FS-16).

## 2. Defringe tím / lục

Thay slider Defringe chung (hôm nay giảm độ bão hoà cả khung — xấp xỉ) bằng bốn control ở Optics:
**Purple Amount · Purple Hue · Green Amount · Green Hue**.

- Chỉ tác động **gần rìa tương phản cao**: bản đồ rìa độ sáng, nở vài pixel; ngoài vùng đó ảnh không đổi —
  bông hoa tím giữa khung không bị bạc màu.
- Trong vùng rìa, pixel có hue thuộc dải được kéo sắc độ về phía trung tính theo Amount (0…20 như Lightroom).
- Dải hue là **hai hàng Min · Max** như mask Luminance — không thêm slider hai núm. Mặc định tím 30/70, lục
  40/60 (thang 0…100 của Lightroom), khoảng cách tối thiểu 10.
- Trên hàng: **Purple · Purple Min · Purple Max · Green · Green Min · Green Max** (Min/Max mờ khi Amount = 0).
  Amount đọc theo thang 0…20 của Lightroom; Min/Max theo 0…100, trải trên hue 230°…350° (tím) và 60°…180° (lục).
  Min vượt Max hay sát nhau dưới 10 thì dải tự nới quanh điểm giữa, không bao giờ rỗng.
- Amount 10 lấy đi 80% sắc độ trong dải; bản đồ rìa = `edgeMask` trên `CIEdges`, nở 3px, làm mềm 1px (kernel
  `defringe`).
- Remove CA giữ nguyên là công tắc.

## 3. Méo và tối góc ống kính chỉnh tay

Ở Optics › Lens Correction, dưới nhãn nhóm **MANUAL**, sau nhóm **LENS PROFILE** của FS-03.16:
**Distortion** (±100) · **Vignetting** (±100) · **Midpoint** (0…100, chỉ hiện khi Vignetting ≠ 0).

- Hai cặp **Distortion · Vignetting** (LENS PROFILE 0–200, MANUAL ±100) **giữ cùng tên**, tách bằng nhãn
  nhóm như Lightroom. Nhãn nhóm là tiêu đề nhỏ chữ hoa kiểu section có sẵn — không token mới.
- VoiceOver đọc cả tên nhóm: "Distortion, Manual" / "Distortion, Lens Profile". *Vì chỉ đọc tên thì hai
  hàng nghe trùng nhau.* Hôm nay (2026-09-28) nhóm MANUAL là một nhóm catalog riêng (`lensManual`) nằm giữa khối
  Lens Profile cũ và nhóm **Defringe**; nhãn LENS PROFILE đến cùng FS-03.16.

- **Distortion** dương nắn méo thùng (kéo vùng rìa ra, tâm như co lại), âm nắn méo gối. Hệ số trong warp:
  1 − 0,04 × giá trị × ρ², ρ là bán kính đầu ra chia nửa đường chéo. Áp cho cả ảnh RAW (bộ giải mã RAW chỉ tự sửa
  theo profile, không biết giá trị người dùng kéo). Cộng vào **cùng một lượt warp** với profile
  — ảnh chỉ nội suy một lần — và tự phóng vừa đủ để không lộ góc trống (trần 1,5× chung với profile).
- **Vignetting** dương làm sáng góc, âm làm tối — theo stop, ±100 là ±1 EV ở góc; Midpoint dời chỗ bắt đầu sụt.
  Tròn quanh tâm, bán kính chuẩn là nửa đường chéo; dùng lại kernel `vignette`. Midpoint **mờ** (không ẩn) khi
  Vignetting = 0, như Midpoint của Vignette ở Effects — ẩn thì nhóm đổi dáng dưới tay. Tâm là tâm ảnh **trước** crop:
  đây là tính chất của ống kính, khác Vignette ở Effects (tính theo khung sau crop).
- Vignetting chạy trong không gian tuyến tính, **ngay sau Lens Blur** — như Lightroom, cùng chỗ với bù tối
  góc theo profile (FS-03.16). *Vì sau curve thì độ sáng đã uốn cong, bù tối góc ra loang.*

## 4. Transform: Aspect, Upright, Constrain Crop

Chỗ đặt theo danh sách Transform của FS-03.13: Upright (Off · Auto · Level · Vertical · Full · Guided)
rồi Geometry (Vertical · Horizontal · Rotate · **Aspect** · Scale · Offset X/Y · Constrain Crop).

- **Aspect** ±100: tỉ lệ ngang/dọc nhân 1,5^(giá trị/100) quanh tâm — +100 kéo ngang ×1,5; góc không lộ.
  Trục nở ra là trục được kéo (âm thì kéo dọc), không trục nào bị co — nên không cạnh nào lùi vào trong khung.
  Chạy trong cùng phép affine với Rotate/Scale/Offset.
- **Auto** = Level + một phần Vertical: nắn dọc tối đa 60% độ hội tụ đo được, để toà nhà không bị kéo cao
  giả. **Full** giữ nghĩa hôm nay (cả hai, 100%).
- **Guided**: kéo trên ảnh tạo một đường guide có hai núm đầu (18pt, chạm 44pt như khung crop); kéo núm hiện
  kính lúp của Point Color (FS-04.01 §5). Tối đa **4** đường; đường thứ 5 không tạo, dòng chú "Up to 4 guides".
- Guided: đường gần dọc thành dọc, gần ngang thành ngang; 1 đường chỉ xoay, ≥ 2 đường giải phối cảnh.
  Mỗi đường thêm/kéo/xoá là một bước Undo.
- **Dò đường**: Level dùng phép tìm đường chân trời của Vision; phần dọc dùng bộ dò đường dọc tự viết (bỏ
  phiếu đường thẳng trên ảnh xám 256px). Guided không cần dò.
- Auto/Full: phần nào không dò được thì bỏ phần đó. Không dò được gì: không đổi gì, dòng "No straight
  lines to work from" trong 3s (luật hôm nay).
- **Lưu**: recipe mang **chế độ Upright + phép nắn đã giải** riêng; ba slider Geo tay cộng lên trên, không
  bị ghi đè. Phép nắn giải **một lần** lúc chạm chế độ, không giải lại mỗi lượt render.
- Chế độ Auto/Level/Vertical/Full đi theo look; dán sang ảnh khác thì giải lại trên ảnh đích. Guided và
  phép nắn đã giải ở lại ảnh gốc (§4 tổng quan).
- **Constrain Crop** bật: tự cắt về hình chữ nhật lớn nhất nằm trong phần ảnh sau nắn, giữ tỉ lệ đang khoá.
  Tắt: kéo giãn mép như hôm nay. *Vì JPEG/HEIC không có trong suốt — góc trống sẽ thành viền đen.*

## 5. Vignette Style

Nhóm Effects › Vignette thêm **Style** — một hàng chip ba ô ở đầu nhóm (kiểu chip chung FS-03.12):
**Highlight Priority** (mặc định) · **Color Priority** · **Paint Overlay**.

- **Highlight Priority**: làm tối như hạ phơi sáng trong không gian tuyến tính; slider Highlights (đang có)
  giữ vùng sáng lại.
- **Color Priority**: chỉ hạ độ sáng, giữ hue và độ bão hoà — góc tối mà không xỉn màu.
- **Paint Overlay**: trộn tuyến tính về đen (âm) hoặc trắng (dương); slider Highlights mờ, như Lightroom.
- **Dấu theo Lightroom** (chốt 2026-09-28): Vignette âm làm tối, dương làm sáng. *Trước đây ShotDex ngược lại
  (dương tối) — preset Lightroom nhập vào sẽ ra vignette sáng.* ±100 là ±2 EV ở góc với hai kiểu Priority.
- Highlight Priority tự giữ vùng sáng (độ sáng 0,55→0,95 giữ dần tới trọn), Highlights hạ ngưỡng dưới xuống;
  Color Priority chỉ giữ theo Highlights. Cả ba kiểu dùng một kernel `vignette` — bỏ nhánh `CIVignetteEffect`
  cũ để đổi Style không đổi dáng sụt.
- Vignette rồi Grain chạy **sau crop và mask**, trước hạ cỡ preview — tâm vignette là tâm khung sau crop.
  *Vì trước crop thì cắt lệch một bên là vignette lệch tâm, sai nghĩa "post-crop".*
- Vignette và Grain **không có trong mask** (Lightroom cũng không); Video Studio giữ chỗ cũ (FS-03.15 §3).

## 6. Thẻ `crs:`

| Control | Thẻ | Thang Lightroom |
|---|---|---|
| NR Contrast · Color Detail · Color Smoothness | LuminanceNoiseReductionContrast · ColorNoiseReductionDetail · ColorNoiseReductionSmoothness | 0…100 (0 · 50 · 50) |
| Defringe | DefringePurpleAmount · DefringePurpleHueLo/Hi · DefringeGreenAmount · DefringeGreenHueLo/Hi | 0…20 · 0…100 |
| Ống kính chỉnh tay | LensManualDistortionAmount · VignetteAmount · VignetteMidpoint | ±100 · ±100 · 0…100 |
| Aspect · Constrain Crop | PerspectiveAspect · CropConstrainToWarp | ±100 · 0/1 |
| Upright | PerspectiveUpright · UprightFourSegments_0…3 · UprightTransform_0…5 | giá trị chế độ cần kiểm (§7 tổng quan) |
| Vignette Style | PostCropVignetteStyle | 1 · 2 · 3 |

## 7. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-16 | ảnh tổng hợp: bậc độ sáng 0,3→0,7 + nhiễu ±0,08; Lum NR 60 | đặt NR Contrast 100 (so với 0) | chênh độ sáng trên dải 4px quanh bậc tăng ≥ 10%; phương sai nhiễu vùng phẳng tăng ≤ 20% | `NoiseReductionSplitTests.contrastKeepsEdges` · hàng mờ khi Lum NR = 0: `ShotDexUITests/scripts/iphone-nr-contrast.json` |
| AC-17 | ô cờ sắc độ 2px (đỏ/lục cùng độ sáng) + nhiễu màu ±0,05; Color NR 50 | đặt Color Detail 100 (so với 0) | phương sai sắc độ của ô cờ giữ ≥ 60% (Detail 0: ≤ 30%) | `NoiseReductionSplitTests.colorDetailKeepsFineColour` · `…colorNoiseReductionLeavesLuminance` · golden `chromaDenoise-*` · hàng: `ShotDexUITests/scripts/iphone-color-nr.json` |
| AC-18 | nền xám có vết loang sắc độ 16px ±0,04; Color NR 50 | đặt Color Smoothness 100 (so với 0) | phương sai sắc độ còn ≤ 50%; độ sáng lệch ≤ 1/255 | `NoiseReductionSplitTests.smoothnessClearsMottling` · golden `chromaBlend-*` · hàng: `ShotDexUITests/scripts/iphone-color-nr.json` |
| AC-19 | rìa đen/trắng có viền tím hue 290° rộng 2px, viền lục ở rìa khác, và một ô tím phẳng cách rìa ≥ 12px | đặt Purple Amount 10 | sắc độ viền tím giảm ≥ 70%; viền lục và ô tím phẳng lệch ≤ 2/255 | `DefringeTests.purpleOnlyAtEdges` · `…greenOnlyOnItsBand` · `…hueBandKeepsItsMinimumWidth` · golden `defringe-*` · hàng: `ShotDexUITests/scripts/iphone-defringe.json` |
| AC-20 | ảnh có chấm ở tâm và ở bán kính 0,8 trên đường chéo | đặt Distortion +50 | chấm ở 0,8 dời **ra** 0,3%…1,5% nửa đường chéo; tâm đứng yên; không góc nào lấy mẫu ngoài ảnh (cả ±50, ±100) | `LensManualTests.distortionPullsTheEdgesIn` · `…neitherDirectionShowsEmptyCorners` · `…rawSourcesGetTheManualCorrection` · `…distortionRowNamesItsGroup` · golden `lensWarp*` (chụp lại) · hàng: `ShotDexUITests/scripts/iphone-lens-manual.json` |
| AC-21 | ảnh xám phẳng 0,5 | đặt Vignetting +50, Midpoint 50 | độ sáng góc tăng ≥ 8% tương đối; tâm lệch ≤ 1/255; tâm tính trên khung trước crop; vị trí pass ngay sau Lens Blur | `LensManualTests.vignettingBrightensCorners` · `…vignettingDarkensAndMidpointMovesTheFallOff` · hàng: `ShotDexUITests/scripts/iphone-lens-manual.json` |
| AC-22 | hình tròn đen giữa nền trắng | đặt Aspect +50 | tỉ lệ ngang/dọc của hình thành 1,22 ± 0,02; 0 pixel trong suốt | `GeoTransformTests.aspectStretchesAroundTheCentre` · `…negativeAspectGrowsTheHeight` · hàng: `ShotDexUITests/scripts/iphone-geo-aspect.json` |
| AC-23 | ảnh toà nhà tổng hợp: cạnh dọc hội tụ 8°, nghiêng 2° | chạm Auto | độ nghiêng còn ≤ 0,5°; độ hội tụ còn 3°…4° (nắn 60%) | ⚠️ chưa có — phần Level cần máy thật hoặc Vision của Mac (dự kiến `UprightAnalyzerTests.autoLevelsAndPartlyStraightens`) |
| AC-24 | cùng ảnh, Upright Guided, 4 đường đã có | vẽ 2 đường dọc theo hai cạnh nghiêng rồi thử đường thứ 5 | hai cạnh dọc trong 0,5°; đường thứ 5 không tạo, hiện "Up to 4 guides"; 1 Undo gỡ đúng 1 đường | ⚠️ chưa có (dự kiến `UprightGuidedTests.twoGuidesMakeBothVertical`) + `ShotDexUITests/scripts/iphone-upright-guided.json` |
| AC-25 | ảnh có đèn sáng 0,95 ở góc và vùng xám 0,5 cạnh đó | Vignette −50, Style Highlight Priority (so với Paint Overlay) | Highlight Priority: đèn còn ≥ 0,9, vùng xám tối ≥ 20%; Paint Overlay: đèn tối ≥ 20% | `VignetteStyleTests.highlightPriorityKeepsLights` · `…negativeDarkensPositiveBrightens` · `…paintOverlayDimsHighlights` · golden `vignette*` · chip: `ShotDexUITests/scripts/iphone-vignette-style.json` |
| AC-26 | Vignette −50, crop giữ nửa trái ảnh | render | tâm vùng sáng nhất nằm ở tâm khung **sau** crop ± 2% cạnh ngắn; grain chạy sau vignette | ⚠️ chưa có (dự kiến `VignetteStyleTests.vignetteFollowsTheCrop`) |
| AC-27 | ảnh toà nhà của AC-23, Upright Auto đã chạm | kéo slider Vertical tay +10, rồi render 20 lần | recipe mang chế độ Auto + phép nắn đã giải + Vertical 10 riêng; phép nắn giải 0 lần thêm; Off trả đúng Vertical 10 | ⚠️ chưa có (dự kiến `UprightStorageTests.solvedTransformAndSlidersAreSeparate`) |
| AC-28 | ảnh A Upright Auto; ảnh B là toà nhà khác nghiêng 3°, hội tụ 6° | Copy Edits A → Paste sang B | B mang chế độ Auto; phép nắn của B giải trên B (khác A); độ nghiêng của B còn ≤ 0,5° | ⚠️ chưa có — phần Level cần máy thật hoặc Vision của Mac (dự kiến `EditClipboardTests.uprightModeIsResolvedOnTheTarget`) |
| AC-29 | ảnh 3:2, Vertical +40, tỉ lệ khoá 3:2 | bật Constrain Crop (so với tắt) | bật: 0 pixel ngoài ảnh sau nắn, khung vẫn 3:2 ± 0,01; tắt: mép kéo giãn, 0 pixel trong suốt | ⚠️ chưa có (dự kiến `GeoTransformTests.constrainCropKeepsTheLockedRatio`) |

**Chưa chứng minh được:** AC-23, AC-24, AC-26…AC-29 (chưa code).

*AC-20 sửa 2026-09-28:* bản cũ ghi "dời vào" cùng lúc với "không góc trống" — hai điều không cùng đúng. Nắn méo
thùng kéo vùng rìa **ra**; phóng vừa khít (không góc trống) không đảo chiều đó. Lightroom cũng vậy khi bật Constrain
Crop; "dời vào" chỉ đúng khi thu nhỏ để giữ trọn góc và chừa viền trống.
