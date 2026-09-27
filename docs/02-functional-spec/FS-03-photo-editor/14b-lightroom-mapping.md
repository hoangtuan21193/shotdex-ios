# FS-03.14b — Quy đổi Lightroom → ShotDex

`FS-03.14b` · `ShotDexKit/Models/PhotoEditingModels.swift` (đích) · `ShotDexTests/LightroomMappingTests.swift`
· cập nhật 2026-09-28

**Một câu:** mỗi thẻ `crs:` đi về đâu trong look của ShotDex, gần đúng tới mức nào, và vì sao những thẻ còn
lại bị bỏ. Tổng quan: [FS-03.14](14-lightroom-preset-exchange.md).

> Bảng là **bản nháp** theo danh sách thẻ XMP crs của ExifTool; agent `lightroom-parity` kiểm với Lightroom
> 13–15 trước `/plan` (câu treo 3 ở tổng quan).

## 1. Cách quy đổi

- Mỗi thẻ về **đúng một** slider. Thang khác nhau thì **quy tuyến tính theo biên hai thang** cho tới khi
  thử nghiệm ΔE (câu treo 1) thay bằng hệ số đo được — bảng hệ số là dữ liệu, không nằm rải trong mã.
- Giá trị vượt dải của ShotDex → **kẹp** về biên, dòng ≈ nói giá trị gốc và giá trị đã đặt.
- Preset chỉ ghi những thẻ nó mang; thẻ vắng mặt **không** đặt slider về 0 — look chỉ chứa phần preset nói.
- Look nhập **mang tập thông số preset có ghi**; áp nó chỉ đổi đúng các thông số đó, phần còn lại giữ nguyên (chốt E6).
  Look tự lưu (Save Current) vẫn thay đủ lát cắt — [DECISIONS](../../../.planboard/plans-deviations/DECISIONS.md).
- Thẻ Process Version cũ (Lightroom 3 trở về trước: `Exposure`, `FillLight`, `Recovery`, `Brightness`
  không hậu tố 2012) → ✕ "Settings from Lightroom 3 or older".

## 2. Bảng thẻ

| Nhóm | Thẻ `crs:` | Slider ShotDex | Trạng thái |
|---|---|---|---|
| Cân bằng trắng | `WhiteBalance`="As Shot" | — | ✓ (không đổi gì) |
| | `Temperature` · `Tint` (K tuyệt đối, preset từ RAW) | **WB Kelvin · WB Tint tuyệt đối** (trường mới của recipe, chỉ RAW — chốt E7) | ✓ đúng số; áp lên JPEG thì không đổi gì |
| | `IncrementalTemperature` · `IncrementalTint` | Temp · Tint | ✓ |
| Basic | `Exposure2012` (±5 EV) | Exposure (±2 EV) | ✓; ngoài ±2 → ≈ kẹp |
| | `Contrast2012` · `Highlights2012` · `Shadows2012` · `Whites2012` · `Blacks2012` | Contrast · Highlights · Shadows · Whites · Blacks | ✓ |
| | `Texture` · `Clarity2012` · `Dehaze` · `Vibrance` · `Saturation` | cùng tên | ✓ |
| Tone curve | `ToneCurvePV2012` · `…Red` · `…Green` · `…Blue` (danh sách điểm) | curve điểm 4 kênh | ✓ |
| | `ParametricShadows/Darks/Lights/Highlights` + 3 điểm chia | — | ✕ tới khi có FS-03.15 |
| HSL | `Hue/Saturation/LuminanceAdjustment` × 8 dải | Color Mixer 8 dải | ✓ |
| Color Grading | `ColorGrade{Shadow,Midtone,Highlight,Global}{Hue,Sat,Lum}` · `ColorGradeBlending` · `SplitToningBalance` | 4 bánh + Blending + Balance | ✓ |
| | `SplitToning{Shadow,Highlight}{Hue,Saturation}` (preset cũ) | bánh Shadows · Highlights | ✓ |
| B&W | `ConvertToGrayscale`=True | B&W 100 | ✓ |
| | `GrayMixer*` × 8 | — | ✕ tới FS-03.15 |
| Detail | `Sharpness` · `SharpenRadius` · `SharpenDetail` · `SharpenEdgeMasking` | Sharpen · Radius · Detail · Masking | ✓ |
| | `LuminanceSmoothing` · `LuminanceNoiseReductionDetail` · `ColorNoiseReduction` | Lum NR · NR Detail · Color NR | ✓ |
| | `LuminanceNoiseReductionContrast` · `ColorNoiseReductionDetail/Smoothness` | — | ✕ tới FS-03.15 |
| Effects | `PostCropVignette{Amount,Midpoint,Feather,Roundness,Highlights}` | Vignette 5 slider | ✓ |
| | `PostCropVignetteStyle` ≠ Highlight Priority | — | ≈ tới FS-03.15 |
| | `GrainAmount` · `GrainSize` · `GrainFrequency` | Grain · Size · Roughness | ✓ |
| Optics | `LensProfileEnable`=1 | Lens Correction bật, ống do ShotDex tự khớp | ≈ "lens chosen by ShotDex" |
| | `LensProfileName` · `LensProfile{Distortion,Vignetting,ChromaticAberration}Scale` | — | ✕ tới FS-03.16 |
| | `AutoLateralCA` | Remove CA | ✓ |
| | `DefringePurpleAmount` · `DefringeGreenAmount` | Defringe (một mức = mức lớn hơn) | ≈ tới FS-03.15 |
| Transform | `Perspective{Vertical,Horizontal,Rotate,Scale,X,Y}` | Vertical · Horizontal · Rotate · Scale · Offset | ✓ |
| | `PerspectiveAspect` · `PerspectiveUpright` | — | ✕ tới FS-03.15 |
| Calibration | `ShadowTint` · `{Red,Green,Blue}{Hue,Saturation}` | — | ✕ tới FS-03.15 |
| Profile | `CameraProfile` · `Look` (tên, Amount, bảng) | film look / LUT | §3, §4 |

- **WB tuyệt đối (chốt E7):** recipe RAW có cặp Kelvin / Tint **tuyệt đối**, cạnh độ lệch so với As Shot (±4000 K / ±150).
  - Có giá trị thì decoder đặt thẳng nhiệt độ trung tính, bỏ qua độ lệch; slider WB của RAW hiện Kelvin thật ([FS-03.04 §2](04-raw-and-render-graph.md)).
  - Trường nằm trong model recipe của `ShotDexKit`, cùng vùng thông số với [FS-03.15](15-lightroom-parameter-parity.md).

## 3. Camera profile → film look

Khớp **theo tên**, không phân biệt hoa thường, bỏ tiền tố "Camera " và hậu tố phiên bản ("v2"). Không đọc
DCP nào. Amount của profile (nếu có) → Amount của look.

| Tên profile trong preset | Film look ShotDex | Trạng thái |
|---|---|---|
| PROVIA/Standard · Velvia/Vivid · ASTIA/Soft · CLASSIC CHROME | cùng tên | ✓ |
| PRO Neg. Hi · PRO Neg. Std · CLASSIC Neg. · NOSTALGIC Neg. | cùng tên | ✓ |
| ETERNA/Cinema · ETERNA BLEACH BYPASS · ACROS (+Ye/+R/+G Filter) | cùng tên | ✓ |
| MONOCHROME (+Ye/+R/+G Filter) · SEPIA của Fujifilm | look Fujifilm cùng tên (có sẵn trong strip B&W) | ✓ |
| Monochrome của hãng khác · Adobe Monochrome | Mono | ≈ |
| Vivid (Camera Vivid, Adobe Vivid) | Vivid | ≈ |
| còn lại (Adobe Color/Standard/Portrait/Landscape, REALA ACE…) | Original | ≈ "No ShotDex look for profile 'Adobe Color' — Original used" |

## 4. Creative profile và nhóm bị bỏ qua

- **Creative profile có RGBTable trong file** → giải mã thành LUT 3D, thêm vào My LUTs mang tên profile,
  look trỏ tới LUT đó với Amount của profile. Giải mã được hay không: câu treo 2.
- Giải mã thất bại, hoặc profile **dựng sẵn trong Lightroom** (chỉ có tên/UUID, không có bảng trong file) →
  ✕ "The profile's colour table isn't in the file"; phần còn lại của preset vẫn áp.

| Nhóm luôn bỏ | Dòng lý do |
|---|---|
| Crop (`HasCrop`, `Crop*`) | "Crop stays with each photo" |
| Vết sửa (`RetouchAreas`, `RedEyeInfo`) | "Spot fixes belong to one photo" |
| HDR (`HDREditMode` và nhóm HDR) | "HDR editing isn't in ShotDex" |
| Mọi mask (`MaskGroupBasedCorrections`, gradient, radial, brush, mask tự sinh Sky/Subject/People) | "Masks stay with each photo" |

- Preset "adaptive" của Lightroom cũng bỏ mask: chỉ phần chỉnh toàn ảnh của nó vào look.
  *Vì* look không mang mask là luật chung của FS-03 README và Copy/Sync ([FS-03.10](10-copy-paste-edits.md)).

## 5. Thẻ chưa có chỗ đặt

Mọi dòng "✕ tới FS-03.15/16" ở §2 là thông số ShotDex **chưa có**, không phải thứ cố ý bỏ.

- FS-03.14 **ship trước** FS-03.15: thẻ chưa có chỗ đặt thành dòng ✕ "…isn't in ShotDex yet"; phần còn lại vẫn áp.
- Mỗi look nhập từ preset Lightroom **giữ file gốc** cạnh nó (vài KB mỗi preset) — bản sau quy đổi lại từ
  file đó khi FS-03.15/16 có thông số, không bắt người dùng tìm lại preset. Nút quy đổi lại không thuộc v1.

## 6. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-b1 | preset chỉ có `CameraProfile`="Camera CLASSIC CHROME"; ảnh đang có Exposure +0.50 | nhập, rồi áp look lên ảnh | look có film look Classic Chrome, Amount 100%, tập thông số đã đặt chỉ gồm film look; hàng ✓; sau khi áp ảnh vẫn Exposure +0.50, mọi slider khác giữ giá trị trước khi áp (chốt E6) | `CameraProfileMapTests.fujiNamesMapToTheSameLook` |
| AC-b2 | preset có `CameraProfile`="Adobe Color" và `Vibrance`=+10 | nhập | film look Original, Vibrance +10; dòng ≈ nêu tên profile | `CameraProfileMapTests.unknownProfileFallsBackToOriginal` |
| AC-b3 | `Exposure2012`=+3.00 | nhập | Exposure +2.00 EV; dòng ≈ "beyond ±2 EV — set to +2.00" | `LightroomMappingTests.exposureBeyondRangeIsClampedAndReported` |
| AC-b4 | preset có `HasCrop`=True, crop 4:5 và `Exposure2012`=+0.30 | nhập | look không có crop, Exposure +0.30; dòng ✕ "Crop stays with each photo"; hàng ≈ | `LightroomMappingTests.cropIsNeverImported` |
| AC-b5 | `WhiteBalance`="Custom", `Temperature`=5500, `Tint`=+10 | nhập rồi áp lên một RAW và một JPEG | look mang WB tuyệt đối 5500 K / Tint +10 (không phải độ lệch so với As Shot); RAW: nhiệt độ trung tính của decoder = 5500 K, tint +10, slider WB đọc 5500 K; JPEG không đổi màu (sai lệch 0/255); hàng ✓ (chốt E7) | `LightroomMappingTests.absoluteWhiteBalanceIsRAWOnly` |
| AC-b6 | preset có creative profile kèm RGBTable 32³ và Amount 60 | nhập | My LUTs +1 mang tên profile; look trỏ tới LUT đó ở 60% | `CreativeProfileTests.rgbTableBecomesALUT` — ⚠️ chưa có, chờ câu treo 2 |
| AC-b7 | FS-03.15 chưa ship; preset có `ParametricShadows`=-20 và `Clarity2012`=+15 | nhập | Clarity +15; dòng ✕ "Tone curve regions aren't in ShotDex yet" | `LightroomMappingTests.missingTargetsAreSkippedWithAReason` |
| AC-b8 | preset "adaptive" có mask Sky (Exposure −0.70 trong mask) và `Vibrance`=+20 toàn ảnh | nhập | look có Vibrance +20, không mask, không có Exposure trong tập thông số đã đặt; dòng ✕ "Masks stay with each photo"; hàng ≈ | `LightroomMappingTests.masksAreNeverImported` |

**Chưa chứng minh được:** AC-b1…b8 (chưa có code); AC-b6 còn chờ thử nghiệm RGBTable.
