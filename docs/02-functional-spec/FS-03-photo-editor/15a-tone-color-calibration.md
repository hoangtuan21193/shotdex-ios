# FS-03.15a — Curve vùng, B&W Mixer, Calibration

`FS-03.15a` · `ShotDexKit/Models/PhotoCurveModels.swift` · `PhotoColorModels.swift` · render trong
`ShotDexKit/Render/` · cập nhật 2026-09-28

**Một câu:** ba nhóm màu/tone của Lightroom mà ShotDex chưa có chỗ đặt — preset nào dùng B&W hay
Calibration hôm nay đều mất nửa look.

Tổng quan và thứ tự render: [FS-03.15](15-lightroom-parameter-parity.md). Curve điểm và Mixer đang có:
[FS-04.02](../FS-04-color-mixer-point-grading/02-grading-and-curve.md),
[FS-04.01](../FS-04-color-mixer-point-grading/01-mixer-and-point-color.md).

## 1. Curve dạng vùng (Parametric)

- Bốn slider ±100: **Shadows · Darks · Lights · Highlights**, và ba điểm chia 0…100 (mặc định 25 / 50 / 75)
  quyết định mỗi vùng rộng bao nhiêu. Chỉ có ở kênh RGB, như Lightroom.
- Mỗi vùng là một bướu mềm trên trục vào; bướu kề nhau chồng lên nhau để đường không gãy. Hai đầu 0 và 1
  **không đổi**, đường luôn đơn điệu kể cả khi cả bốn slider ở ±100.
- **Control**: trong trình sửa Curve (✕ · Curve · ✓, FS-03.13) có hai chế độ **Point · Region** ở đầu cột
  chọn kênh. Region: đồ thị vẫn hiện, tô bốn vùng; bốn slider là hàng 40pt dưới đồ thị, panel tự cuộn.
- Ba điểm chia là ba núm trên cạnh đáy đồ thị, vùng chạm 44pt; kéo một núm không vượt núm kề. *Hôm nay (2026-09-28)
  là ba slider dưới bốn slider vùng; núm trên đồ thị làm cùng trình sửa Curve trong panel của FS-03.13.*
- Đồ thị ở Region vẽ **đường tổng** (vùng rồi điểm), nên người dùng thấy đúng cái được áp.
- Curve vùng nướng **vào cùng** bảng tra 256 mức của curve RGB đang có: vùng trước, điểm sau — một lượt curve,
  đúng thứ tự Lightroom, không thêm pass nào.

| Control | Thẻ `crs:` | Thang Lightroom |
|---|---|---|
| Shadows · Darks · Lights · Highlights | ParametricShadows · ParametricDarks · ParametricLights · ParametricHighlights | ±100 |
| ba điểm chia | ParametricShadowSplit · ParametricMidtoneSplit · ParametricHighlightSplit | 0…100 (25/50/75) |

## 2. B&W Mixer 8 màu

- Bật B&W (công tắc đang có ở Color) thì hàng **Mixer** đổi thành **B&W Mix**: 8 slider ±100 cùng tám dải
  màu của HSL (Red … Magenta), rãnh tô từ tối sang sáng theo màu của dải.
- Mỗi slider làm **sáng hoặc tối** những pixel có màu thuộc dải đó trước khi thành xám; trọng số dải dùng
  lại đúng tam giác mềm của HSL Mixer (FS-04.01 §2), nên không có vùng chết.
- Pixel gần trung tính không bị đổi (ngưỡng độ tinh khiết mềm như HSL). Kết quả luôn xám: R = G = B.
- Khi B&W bật, HSL Mixer và Point Color **không áp** và hàng của chúng mờ kèm dòng "Off while Black & White
  is on" — Lightroom cũng tắt HSL ở chế độ B&W. Grading vẫn nhuộm được ảnh xám.
- Không có nút Auto mix ở bản này.
- Chuyển xám chạy **trong chặng Color, sau WB và Light** (thay chỗ đầu chuỗi hôm nay): Temp/Tint đổi tông xám
  như Lightroom. *Vì ở đầu chuỗi, preset B&W dùng Temp để đổi tông ra sai.*
- **Temp/Tint là hệ số từng kênh** trong ánh sáng tuyến tính (màu vật đen ở nhiệt độ đích chia cho ở 6500K, chuẩn
  hoá theo kênh lục), không giữ độ sáng như bộ lọc nhiệt màu của Core Image — nên màu vàng sáng lên khi ấm. Màu
  lam gần như không tối đi vì độ sáng của nó nằm chủ yếu ở kênh lục (chốt 2026-09-28).
- Mask không có công tắc B&W (Lightroom cũng không); xám trong mask là Saturation −100 (FS-03.15 §3).

| Control | Thẻ `crs:` | Thang |
|---|---|---|
| công tắc B&W | ConvertToGrayscale | true/false |
| 8 slider | GrayMixerRed · Orange · Yellow · Green · Aqua · Blue · Purple · Magenta | ±100 |

## 3. Calibration

- Nhóm mới **Calibration**, cuối danh sách Edit (sau Optics và RAW), 7 slider ±100: **Shadow Tint** ·
  **Red Hue · Red Saturation · Green Hue · Green Saturation · Blue Hue · Blue Saturation**.
- Ba cặp Hue/Saturation **dời ba màu cơ bản** của ảnh: Hue xoay màu cơ bản đó quanh vòng màu, Saturation đẩy
  nó ra xa hay lại gần trục xám. Tính bằng một ma trận 3×3 dựng từ ba màu cơ bản đã dời.
- Ma trận **giữ trắng**: mỗi hàng chuẩn hoá để xám vẫn là xám — Calibration đổi màu, không đổi WB.
- **Shadow Tint** đẩy lục ↔ tím hồng, trọng số giảm dần từ đen (1) tới trung tính (0 ở độ sáng 0,5).
- Chạy trong không gian tuyến tính, **ngay sau Lens Blur, trước Light** — Calibration trong Lightroom là một
  phần hồ sơ màu máy ảnh, nên B&W Mixer và HSL đọc màu **đã** calibrate.
- *Vì sau Light thì Exposure đã đẩy màu sang vùng khác trước khi calibrate* — preset giả phim ra lệch.
- Không có trong mask (Lightroom cũng không). Ảnh RAW và ảnh thường dùng cùng một phép.

| Control | Thẻ `crs:` | Thang |
|---|---|---|
| Shadow Tint | ShadowTint | ±100 |
| Red/Green/Blue Hue | RedHue · GreenHue · BlueHue | ±100 |
| Red/Green/Blue Saturation | RedSaturation · GreenSaturation · BlueSaturation | ±100 |

## 4. Tiêu chí nghiệm thu

Ảnh thử dựng trong code: dải xám 256 mức, và bảng màu 24 ô theo giá trị sRGB công bố của ColorChecker
(ô "Red" 175,54,60; ô "Yellow" 231,199,31; ô "Blue" 56,61,150; ô "Neutral 5" 122,122,121).

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-7 | dải xám, curve điểm thẳng | đặt Shadows +50 (điểm chia mặc định) | đầu ra ở mức vào 0,15 tăng 0,02…0,08; mức 0 và 1 lệch ≤ 1/255; mức ≥ 0,85 lệch ≤ 2/255 | `ParametricCurveTests.shadowsLiftTheDarkQuarterOnly` |
| AC-8 | dải xám | đặt cả bốn vùng lần lượt ±100 (16 tổ hợp dấu) và điểm chia 10/50/90 | mọi bảng tra đơn điệu không giảm, hai đầu giữ nguyên | `ParametricCurveTests.everyExtremeStaysMonotone` |
| AC-9 | curve vùng Lights +30, curve điểm RGB Soft S | render dải xám | bằng bảng tra "vùng rồi điểm" tính tay ± 1/255, và chỉ một lượt curve trong chuỗi | `ParametricCurveTests.regionThenPointIsOneTable` · chế độ Region: `ShotDexUITests/scripts/iphone-curve-region.json` |
| AC-10 | bảng 24 ô, B&W bật, mixer 0 | đặt Blue −60 | ô Blue tối đi ≥ 15% độ sáng; ô Yellow và Neutral 5 lệch ≤ 2/255; mọi ô R = G = B ± 1/255 | `GrayMixerTests.blueDarkensOnlyBlue` · golden `grayMixer-patches/photo` |
| AC-11 | bảng 24 ô, B&W bật, HSL Blue Luminance +50 | render | HSL không áp (bằng bản HSL 0 ± 1/255); hàng Mixer ghi "Off while Black & White is on" | ⚠️ chưa có (dự kiến `GrayMixerTests.hslIsOffInBlackAndWhite`) + ảnh Edit › Color, iPhone 17 26.5 |
| AC-12 | bảng 24 ô | đặt Calibration Red Hue +30 | hue ô Red dịch về phía cam +4°…+12°; ô Neutral 5 lệch ≤ 1/255; ô Blue dịch ≤ 2° | ⚠️ chưa có (dự kiến `CalibrationTests.redHueMovesRedTowardOrange`) |
| AC-13 | bảng 24 ô | đặt Blue Saturation +50 | độ bão hoà ô Blue tăng ≥ 10% tương đối; mọi ô trung tính lệch ≤ 1/255 | ⚠️ chưa có (dự kiến `CalibrationTests.saturationKeepsGreysGrey`) |
| AC-14 | Calibration ở mặc định | kéo Red Hue 0 → +40 rồi thả, rồi Undo một lần | một bước lịch sử; recipe về đúng mặc định, không thêm khoá Calibration | ⚠️ chưa có (dự kiến `EditorHistoryAndSummaryTests.calibrationDragIsOneStep`) |
| AC-15 | bảng 24 ô, B&W bật, mixer 0 | đặt Temp +30 (so với 0) | ô Yellow sáng lên ≥ 3/255, ô Blue không sáng lên; mọi ô vẫn R = G = B ± 1/255 | `GrayMixerTests.temperatureShiftsTheGreyMix` · `WhiteBalanceMathTests` |

**Chưa chứng minh được:** AC-7…AC-15 (chưa code).
