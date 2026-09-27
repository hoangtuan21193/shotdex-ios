# Kế hoạch — FS-03.15 Đủ thông số Lightroom (15a–15e)

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-03.15`](../02-functional-spec/FS-03-photo-editor/15-lightroom-parameter-parity.md) + [15a](../02-functional-spec/FS-03-photo-editor/15a-tone-color-calibration.md) · [15b](../02-functional-spec/FS-03-photo-editor/15b-detail-optics-transform.md) · [15c](../02-functional-spec/FS-03-photo-editor/15c-retouch-and-red-eye.md) · [15d](../02-functional-spec/FS-03-photo-editor/15d-mask-additions.md) · [15e](../02-functional-spec/FS-03-photo-editor/15e-lens-blur.md) — AC-1…AC-60 (Remove và R-1…R-4 ở 15c §6: **không lập kế hoạch**) |
| Intent | [2026-09-27-lightroom-parameter-parity](../_intents/2026-09-27-lightroom-parameter-parity.md) |
| Quyết định | `.planboard/editor-specs-decisions/DECISIONS.md` D51–D70 (+ D71 cho ranh giới FS-03.16) |
| Quyết định lệch | `.planboard/plans-deviations/DECISIONS.md` — E10–E15 (5 câu §0 + gộp pipeline) |
| Liên quan | [13b](../02-functional-spec/FS-03-photo-editor/13b-edit-and-transform.md) / [13c](../02-functional-spec/FS-03-photo-editor/13c-mask-heal-markup.md) (chỗ đặt control) · [16*](../02-functional-spec/FS-03-photo-editor/16-lens-correction-sources.md) (ba slider độ mạnh của profile — ngoài phạm vi) · [FS-16](../02-functional-spec/FS-16-metal-kernels.md) (kernel Metal, golden) |
| Ngày | 2026-09-28 |
| Trạng thái | **nháp — chờ duyệt**, 61 task; 5 câu ở §0 đã chốt (E10–E14), thêm E15 |

## 0. Đã chốt — chỗ spec và code lệch

Quyết định lệch: `.planboard/plans-deviations/DECISIONS.md`. Mọi dòng ⚠️ cũ đã có câu trả lời; bảng §2 ghi
"chốt E#" ở dòng tương ứng, task nằm ở §5.

| # | AC | Chốt | Hệ quả cho kế hoạch |
|---|---|---|---|
| E10 | AC-41 | Subtract = hiện tại × (1 − vùng trừ), theo spec 15d §1 | task 37 đổi kernel `subtractMask` (`MaskKernels.ci.metal:13-16`) sang nhân phần bù, golden mới. Hôm nay UI chưa tạo vùng Subtract nào ngoài tẩy cọ (`PEC:1793`) nên không ảnh nào đổi |
| E11 | AC-24 | dòng chú "Up to 4 guides" — 13b AC-24 đã sửa cho khớp 15b | task 28 dùng đúng câu này |
| E12 | AC-31 | "0,4 ± 2/255" đo trong không gian làm việc tuyến tính — AC-31 (15c) đã sửa chữ | kernel `healBlend` (`HealingKernels.ci.metal:31-40`) đã đúng → AC-31 ✅ phía render; task 2 chỉ thêm test + viên Opacity |
| E13 | AC-6 | mask bỏ B&W, Vignette, Grain (Lightroom không có); Video Studio giữ thứ tự cũ tới khi FS-12 quyết | task 4: bỏ ba control khỏi phạm vi mask trong `EditorAdjustmentCatalog.swift:128-155`; video (`VideoFrameCompositor.swift:116`, `VideoMaskRenderer.swift:39`) gọi một hàm bọc giữ thứ tự cũ |
| E14 | AC-20/21 | giữ tên "Distortion · Vignetting" cho cả hai cặp, tách bằng nhãn nhóm **LENS PROFILE** (0–200) / **MANUAL** (±100); VoiceOver đọc kèm tên nhóm | task 19–20: hàng tay nằm dưới nhãn MANUAL, nhãn VoiceOver "Distortion, Manual" |
| E15 | AC-6 | gộp ba chuỗi pass chép tay (ảnh tĩnh, Live Photo, mask tự động) thành một danh sách chung **trước** mọi lần đổi thứ tự pass | task 3 mới, đầu pha render; mọi task sau +1 |

## 1. Hiểu đúng chưa

Mỗi thông số Lightroom còn thiếu phải có ba thứ: một trường trong recipe (khoan dung khi decode, mặc định nằm trong trạng thái "chưa sửa"), một pass render đúng vị trí trong bảng §3 của FS-03.15, và một control ở chỗ FS-03.13 đã chừa. Mục tiêu là preset Lightroom nhập vào không mất phần nào. Các thứ mới gồm: curve vùng, B&W mixer, Calibration, NR 3 slider, Defringe tím/lục, méo và tối góc chỉnh tay, Aspect, Upright Auto/Guided lưu riêng, Vignette Style, heal nét cọ + Opacity/New Source/Visualize/Pins/Clear All, Red Eye, mask Intersect + thông số riêng của mask + Object/People, và Lens Blur thay Depth Blur (kèm Depth Anything V2 cho ảnh không có bản đồ độ sâu). Thứ tự render đổi ba chỗ: B&W vào chặng Color, Calibration và tối góc tay ngay sau Lens Blur, Vignette và Grain sau mask. App chưa phát hành nên không cần migration; golden toàn pipeline chụp lại một lần.

Tóm tắt này khớp đặc tả. Chỗ lệch nằm ở §0, đã chốt E10–E15.

## 2. Đối chiếu AC ↔ code

Viết tắt: **PRS** = `ShotDexKit/Render/PhotoRenderService.swift` · **PEC** = `ShotDex/Features/Editing/PhotoEditorController.swift` · **PEM** = `ShotDexKit/Models/PhotoEditingModels.swift`. Mọi file dưới đây đều đã được mở để kiểm.

Tổng: **✅ 2 · ⚠️ 0 · ❌ 56 · ❓ 2** (60 AC). Bốn dòng ⚠️ cũ đã chốt ở §0: AC-31 thành ✅, AC-6/24/41 thành ❌.

### Chung (AC-1…6)

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 | ❌ | Cơ chế lossy đã có: `PEM:1290-1318` (masks, components, healing decode từng phần tử), `PhotoMask.init(from:)` `PEM:1146-1164`, test `RecipeLossyDecodingTests:33,48`. Các trường mới chưa có trong `PhotoAdjustments` (`PEM:569-722`), `MaskBlendOperation` (`PEM:976-978`), `PhotoMaskComponentKind` (`PEM:984-999`) | thêm mọi trường mới theo §3 bảng file; test `newParityFieldsSurviveOneBadElement` |
| AC-2 | ❌ | Lát cắt look chép `adjustments/color/curve/filter/lut` ở **ba chỗ**: `EditClipboard.swift:49-59` (paste), `:68-77` (look), `EditorSyncScope.apply` `:95-108`. Healing không đi theo (`PhotoHealingTests:331`). Chưa có Calibration, curve vùng, Red Eye, guide | gom lại thành **một** hàm lát cắt; guide/Red Eye/phép nắn đã giải thuộc khung; test `parityLookSlice` |
| AC-3 | ❓ | Không có dòng code ánh xạ `crs:` nào (grep ShotDex/ShotDexKit/Tests: 0 kết quả). Bảng thẻ chỉ có trong `14b-lightroom-mapping.md`. FS-03.14 chưa code, và danh sách thẻ chưa kiểm (FS-03.15 §7 câu 3) | chưa kết luận được vì AC đọc "bảng ánh xạ của FS-03.14", thứ chưa tồn tại. Đề xuất: dựng `LightroomTagTable` (Domain, chỉ dữ liệu) từ 14b + 15a–e, sau khi agent `lightroom-parity` kiểm tên thẻ; nếu FS-03.14 có kế hoạch riêng thì chuyển task sang đó |
| AC-4 | ❌ | Chưa có test 100MP hay test trần bộ nhớ editor nào. Khung đo có sẵn: `FocusStackExportTests.swift:16-23` (`task_vm_info` phys_footprint), `:187`. Lưu ảnh chạy `PhotoEditingService.swift:257,265,389` | test `hundredMegapixelSaveStaysUnderCeiling` + lỗi có tên khi vượt trần, không tạo asset rỗng |
| AC-5 | ✅ | Kit hôm nay không import SwiftUI/GRDB (grep: chỉ `PhotoRenderService+Drawing.swift:4-5` import PencilKit/UIKit — được phép). `KernelLibraryTests.everyKernelLoads` `:13` giữ 40 kernel (`:56`) | viết test grep ranh giới kit (hôm nay **chưa có**); mỗi task thêm kernel thì nới danh sách `everyKernelLoads` + `KernelGoldenTests.everyKernelHasACase` `:49` |
| AC-6 | ❌ (chốt E13, E15) | Thứ tự pass **viết cứng** ở `PRS:358-424`. Chỉ Detail là dữ liệu (`PRS:1406-1413`, test `EditorParityTests.swift:34-47`). B&W chạy đầu `applyAdjustments` (`PRS:1216`), Vignette/Grain chạy trong đó (`PRS:1337-1344`), hàm này chạy cả trong mask (`PRS:402`). Có **ba bản chép tay** của chuỗi pass: `automaticMaskImages` `PRS:733-745`, `LivePhotoFrameRenderer` `PhotoEditingService.swift:779-800`, mask Live Photo `:835-870` | **E15** trước: gộp ba bản chép tay vào một danh sách pass chung, chưa đổi thứ tự (task 3). Rồi `RenderPass` + `renderPassOrder` đúng §3; **E13**: mask bỏ B&W/Vignette/Grain (cả danh sách slider của mask), video giữ thứ tự cũ qua hàm bọc (task 4); test `parityPassOrderMatchesTheSpec` |

### 15a — curve vùng, B&W Mixer, Calibration (AC-7…15)

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-7 | ❌ | `ToneCurveAdjustments` chỉ có 4 kênh điểm (`PhotoCurveModels.swift:60-141`), không có trường parametric | `ParametricCurve` (4 slider + 3 điểm chia) + math thuần; test `shadowsLiftTheDarkQuarterOnly` |
| AC-8 | ❌ | — (math đơn điệu có sẵn cho curve điểm: `ToneCurveMath.swift:13`, test `ToneCurveMathTests:30`) | bướu vùng đơn điệu; test 16 tổ hợp dấu × điểm chia 10/50/90 |
| AC-9 | ❌ | Curve đã nướng thành một lượt `CIColorCurves` 256 mức, master rồi kênh (`PhotoRenderService+Curve.swift:13-47`) | ghép "vùng → điểm master → kênh" vào chính bảng đó (D51); test `regionThenPointIsOneTable` + đếm một pass curve |
| AC-10 | ❌ | B&W = `CIColorControls` saturation 0 (`PRS:1216-1222`). `PhotoColorRecipe` không có mixer xám (`PhotoColorModels.swift:327-360`) | `GrayMixerAdjustments` + kernel `grayMixer` dùng lại trọng số dải của `ColorRenderMath.bandWeights` (`ColorRenderMath.swift:87`); golden |
| AC-11 | ❌ | `applyColor` luôn áp HSL (`PhotoRenderService+Color.swift:121-127`). Không có chữ "Off while Black & White is on" (grep 0). B&W là hàng công tắc ở nhóm Color (`EditorAdjustmentCatalog.swift:131`) | B&W bật: bỏ Mixer và Point Color, hàng mờ kèm dòng chú; hàng Mixer thành **B&W Mix** (control) |
| AC-12 | ❌ | Không có Calibration trong model hay render | `PhotoCalibration` (7 trường) + ma trận 3×3 giữ trắng (Domain/kit thuần) + `CIColorMatrix` tuyến tính; test `redHueMovesRedTowardOrange` |
| AC-13 | ❌ | — | test `saturationKeepsGreysGrey` (chuẩn hoá hàng ma trận) |
| AC-14 | ❌ | Cơ chế "một cú kéo = một bước" đã có: `beginContinuousChange` `PEC:550-555`, `setAdjustment` `PEC:579-583`. Encode bỏ khoá mặc định: `PEM:864-870` | nhóm Calibration cuối danh sách Edit; test `calibrationDragIsOneStep` |
| AC-15 | ❌ | Temp/Tint chạy **sau** B&W (`PRS:1306-1322` so với `:1216`) nên hôm nay Temp không đổi tông xám | có sẵn khi làm AC-6 (B&W vào chặng Color, task 4); test `temperatureShiftsTheGreyMix` |

### 15b — NR, Defringe, ống kính chỉnh tay, Aspect, Upright, Vignette Style (AC-16…29)

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-16 | ❌ | Lum NR + Detail ở `PRS:1364-1394`, lượt NR ở `PRS:1422-1441`. Kernel bản đồ rìa `edgeMask` có sẵn (`MaskKernels.ci.metal:40-44`, dùng cho Sharpen Masking `PRS:1815`) | NR Contrast = trộn trả ảnh gốc theo bản đồ rìa; test `contrastKeepsEdges` |
| AC-17 | ❌ | Color NR = `CINoiseReduction` chung (`PRS:1430-1441`) | kernel Metal giữ rìa sắc độ; test + golden |
| AC-18 | ❌ | — | làm mờ sắc độ bán kính lớn (YCbCr), không đụng độ sáng; test `smoothnessClearsMottling` |
| AC-19 | ❌ | Defringe = `CIVibrance` âm **cả khung** (`PhotoRenderService+Optics.swift:88-94`) | bốn trường tím/lục + kernel theo rìa (dùng lại `edgeMask`); bỏ `defringe` cũ; hàng Min/Max như mask Luminance; test `purpleOnlyAtEdges` |
| AC-20 | ❌ | Warp profile là `CIWarpKernel lensWarp` (`LensProfileLibrary.swift:193-233`, kernel `OpticsKernels.ci.metal:23-36`), `fillZoom` trần 1,5 (`:239-249`). Không có số hạng chỉnh tay | cộng hệ số méo tay vào **cùng lượt warp** (tham số kernel mới, golden `lensWarp*` chụp lại có ghi chú); test `distortionPullsTheEdgesIn`. Tên hàng: **chốt E14** — giữ "Distortion", dưới nhãn nhóm MANUAL, VoiceOver "Distortion, Manual" |
| AC-21 | ❌ | Không có tối góc ống kính. `LensDistortionTerm` không có số hạng vignetting (`LensProfileLibrary.swift:7-20`) | pass `lensManualVignetting` tuyến tính ngay sau Lens Blur, tâm theo khung trước crop; hàng "Vignetting" dưới nhãn MANUAL (E14); test `vignettingBrightensCorners` + vị trí trong `renderPassOrder` |
| AC-22 | ❌ | `applyGeo` chỉ có affine + keystone (`PhotoRenderService+Optics.swift:101-130`) | `geoAspect` nhân 1,5^(v/100), dùng cùng chế độ kẹp mép; test `aspectStretchesAroundTheCentre` |
| AC-23 | ❌ | Chỉ có Level/Vertical/Full (`UprightAnalyzer.swift:6-14`), không có Auto. Level dùng Hough tự viết (`:95-110`), không dùng `VNDetectHorizonRequest` (grep 0) — D64 đã chốt dùng Vision cho Level | thêm `.auto` (Level + 60% Vertical), Level lấy chân trời từ Vision, bộ dò dọc giữ nguyên; test (phần Vision: máy thật hoặc Vision của Mac) |
| AC-24 | ❌ (chốt E11) | Không có Guided (`UprightAnalyzer.swift:6-14`, hàng chip `EditorToolPanels.swift:797-853`). 13b và 15b từng ghi hai câu chú khác nhau — nay cùng "Up to 4 guides" | guide (tối đa 4, núm 18/44pt, kính lúp của Point Color), giải 1 đường = xoay, ≥ 2 = phối cảnh; test `twoGuidesMakeBothVertical` + `iphone-upright-guided.json` (**chưa có**) |
| AC-25 | ❌ | Kernel vignette đã có tham số giữ vùng sáng (`PhotoRenderService+Optics.swift:16-59`, `OpticsKernels.ci.metal:11`). Không có Style | `VignetteStyle` (3 kiểu) + chip ở đầu nhóm (`EditorPanelChipStrip` `EditorToolPanels.swift:937`); test `highlightPriorityKeepsLights` |
| AC-26 | ❌ | Vignette chạy **trước** crop, trong `applyAdjustments` (`PRS:1337`) | có sẵn khi làm AC-6 (pass `postCropVignette` sau mask); test `vignetteFollowsTheCrop` |
| AC-27 | ❌ | `applyUpright` ghi thẳng vào `geoRotate/Vertical/Horizontal` (`PEC:721-738` → `UprightSuggestion.apply` `UprightAnalyzer.swift:77-83`). D57 đã chốt lưu riêng | `PhotoUprightRecipe` (chế độ + phép nắn đã giải + guides), render phép nắn trước slider tay; test `solvedTransformAndSlidersAreSeparate` (giải 0 lần thêm sau 20 lần render) |
| AC-28 | ❌ | Look chép cả `adjustments` (gồm slider geo) nhưng không có chế độ Upright (`EditClipboard.swift:55`) | chép chế độ, bỏ phép nắn đã giải; editor/batch giải lại trên ảnh đích khi `mode ≠ off && solved == nil`; test `uprightModeIsResolvedOnTheTarget` |
| AC-29 | ❌ | Kẹp mép khi nắn đã là "tắt" (`clampedToExtent` `PhotoRenderService+Optics.swift:122,145`) — D65. Chưa có Constrain Crop (grep 0) | hình chữ nhật lớn nhất bên trong phần ảnh sau nắn, giữ tỉ lệ đang khoá (math thuần `CropFrameGeometry`); test `constrainCropKeepsTheLockedRatio` |

### 15c — Retouch, Red Eye (AC-30…39)

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-30 | ❌ | Vết tạo **chỉ bằng chạm** (`EditorHealPanel.swift:112-124`). Vết chỉ có hình tròn (`PhotoHealing.swift:28-56`). Phép vá normalized convolution nằm ở `PhotoHealingRenderer.swift:29-128` | `PhotoHealingSpot.shape` (tròn / nét: điểm + bề ngang). Vòng đo màu theo **hình nét** (raster qua `BrushStrokeRasterizer`). Dùng trọng tài chạm/kéo `PaintTouchArbiter`. Test `brushHealRemovesAWire` |
| AC-31 | ✅ phía render (chốt E12) | Opacity đã có trong model (`PhotoHealing.swift:39`) và kernel (`HealingKernels.ci.metal:31-40`, `amount = coverage × opacity`). **Không có slider Opacity** trong panel (`EditorHealPanel.swift:33-56`) | trộn tuyến tính cho đúng 0,4 — đạt theo câu chữ mới của AC-31; viết test `opacityBlendsHalfway` (đo trong không gian làm việc, như `PhotoHealingTests`) + viên Opacity |
| AC-32 | ❌ | Nguồn cố định sang ngang (`PhotoHealing.swift:63-74`) | chấm điểm ứng viên theo vành (màu + vân), bỏ chỗ chồng vết; mỗi lần bấm một bước Undo; test `newSourcePicksAnotherPlace` |
| AC-33 | ❌ | Không có Visualize Spots (grep 0) | lớp hiển thị bản đồ rìa (edgeMask + Threshold) chỉ ở preview, không vào `render(source:)`; test `visualizeIsDisplayOnly` |
| AC-34 | ❌ | `removeAllHealingSpots` có (`PEC:1257-1263`) nhưng chỉ gọi từ nút ↺ của thanh commit rộng (`PhotoEditorScreen.swift:1470-1471`), **không hỏi xác nhận**. Không có Show Spot Pins | Clear All (gồm Red Eye) một bước Undo, hỏi xác nhận khi có từ 2 vết; ẩn ghim; test + `iphone-heal-panel.json` (**chưa có**) |
| AC-35 | ❌ | Mốc khuôn mặt chỉ lấy mắt/lông mày/môi/cằm (`PRS:2413-2441`), **không lấy con ngươi** (grep `pupil` 0) | `PhotoRedEyeSpot` + kernel "đỏ trội → lục/lam rồi tối"; Vision `leftPupil/rightPupil` để căn tâm; test tổng hợp (không dùng ảnh mặt thật) |
| AC-36 | ❌ | — | lỗi Vision hoặc không có mặt → đặt vết tại chỗ chạm, bán kính 1%; test `noFaceFallsBackToTheTap` |
| AC-37 | ❌ | — | Fix Red Eye: mọi con ngươi, qua phép thử đỏ trội, cả lượt là một bước Undo; test cần máy thật/Mac |
| AC-38 | ❌ | Pill 3s có sẵn nhiều bản (`showMaskDetectionNotice` `PEC:2380-2388`, `EditorPillLabel` `EditorTheme.swift:239`) | "No red eyes found", 0 bước Undo |
| AC-39 | ❌ | Hàng chế độ dựng từ `PhotoHealingMode.allCases` = heal, clone (`EditorHealPanel.swift:19-31`, `PhotoHealing.swift:4-19`) | ô Red Eye thứ 3 (Remove không hiện); ở chế độ Red Eye: Pupil Size · Darken · Fix Red Eye; ui-drive + element dump |

### 15d — Mask (AC-40…52)

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-40 | ❌ | `MaskBlendOperation` chỉ có add/subtract (`PEM:976-978`), kernel `addMask/subtractMask` (`MaskKernels.ci.metal:8-16`). UI chỉ tạo **một** thành phần mỗi mask (`PEC:1793-1807`); chip Add/Subtract chỉ bật tẩy cọ (`PEC:217-223`) | `.intersect` + kernel nhân; luồng **Add/Subtract/Intersect area** ở danh sách mask; test `intersectKeepsOnlyTheOverlap` |
| AC-41 | ❌ (chốt E10) | Đã cộng dồn **theo thứ tự danh sách** (`PRS:2044-2085`), Opacity áp trước phép (`:2054-2079`) — khớp spec. Subtract **trừ thẳng** (`MaskKernels.ci.metal:13-16`), spec nhân phần bù | đổi kernel `subtractMask` = `hiện tại × (1 − vùng trừ)` + golden mới; test `areasApplyInListOrder` + `subtractMultipliesTheComplement` (0,8 và 0,5 → 0,4) + Undo một bước |
| AC-42 | ❌ | Mask chỉ nhận `applyAdjustments` (`PRS:402-407`). `applyColor` chỉ chạy toàn cục (`PhotoRenderService+Color.swift:118-120`) | `maskHue` + pass màu cục bộ; test vùng xa ± 1/255 (luật region-kernel FS-16 §5) |
| AC-43 | ❌ | — | phủ màu giữ độ sáng Rec.709 (kernel Metal); test `colorTintIsLuminanceNeutral` |
| AC-44 | ❌ | — | `PhotoMask.curve` nướng bằng `applyCurve` sẵn có, trộn theo matte; test `maskCurveOnlyInside` |
| AC-45 | ❌ | — | Moiré = làm mờ sắc độ tần số cao (chung kernel với Color Smoothness, AC-18); test `moireFlattensColourStripes` |
| AC-46 | ❌ | Subject hôm nay: chạm một điểm → **một** instance, chạm nền → mọi instance (`PRS:2365-2396`, `instanceIndex` `:2480-2500`) — chính là nghĩa mới của Object | kind `.object(point)` dùng lại `instanceIndex`; test (Vision máy thật/Mac) |
| AC-47 | ❌ | Không có `VNGeneratePersonInstanceMaskRequest` / `PersonSegmentation` (grep 0) | People: instance theo người (tối đa 4, iOS 17), xếp theo diện tích, thumbnail; test máy thật + ảnh New Mask |
| AC-48 | ❌ | `DepthImageReader` chỉ đọc disparity/depth/portrait matte (`DepthImageReader.swift:16-65`). Không đọc `AVSemanticSegmentationMatte` | đọc matte tóc/da/răng/kính; hàng mờ 35% + lý do 3s khi thiếu; test + `iphone-people-mask.json` (**chưa có**) |
| AC-49 | ❌ | Lỗi Vision đã thành "matte rỗng, không lỗi render" (`PRS:2225-2233`) | pill "Couldn't find a person", giữ mask rỗng; ui-drive trên simulator |
| AC-50 | ❌ | Như AC-46: Subject đang phụ thuộc điểm chạm (`PEC:2029-2042`, hint "Tap a person or object on the photo" `EditorMaskPanels.swift:548-550`). D67 đã chốt đổi | Subject = `allInstances`, không chạm, bỏ hint; test |
| AC-51 | ❌ | Bộ đệm matte **chỉ trong RAM**: 8 mục FIFO (`PRS:94-99`), không cache ảnh > 3000px (`:2239-2242`). Không có kho file (grep 0) | `GeneratedMatteStore` (file 8-bit ¼ độ phân giải trong Application Support, khoá theo ảnh + vùng + nguồn), đọc trước Vision; test với Vision giả |
| AC-52 | ❌ | 12 ô trên **3 hàng cuộn ngang** detect/draw/range (`EditorNewMaskOption.swift:10-22,69-83`, `EditorMaskPhonePanel.swift:59-71`); sheet rộng là một cột (`EditorMaskPanels.swift:839-847`) | lưới 4 cột, 14 ô đúng thứ tự 15d §3; ui-drive + dump trên 26.5 và 18.6 |

### 15e — Lens Blur (AC-53…60)

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-53 | ❌ | Depth Blur = 2 Gaussian + 2 lần trộn, không có dải lấy nét (`PRS:1604-1643`); `depthBlur` là một slider (`PEM:697`). Ảnh RAW không bao giờ có disparity (`PRS:1165-1169`) | `LensBlurRecipe` (Amount, Bokeh, Near/Far) + 8 lớp độ sâu, chồng xa → gần (kernel Metal); bỏ `depthBlur`; test `focusRangeKeepsTheNearHalfSharp` (fixture `DepthBlurTests` dùng lại) |
| AC-54 | ❌ | — | 5 hình bokeh (kernel tổng quát + golden `lensBlurRing`); test vành/lõi |
| AC-55 | ❌ | Chế độ chạm lấy mẫu có sẵn: `isSamplingColor` / `imageGestureMask` (`EditorImageStage.swift:61-64, 93-98`) tắt cử chỉ mức ảnh | chạm lấy nét (±10 quanh độ sâu tại điểm chạm) + "Tap to focus" + Visualize Depth; test + `iphone-lens-blur.json` (**chưa có**) |
| AC-56 | ❌ | Không có model độ sâu nào (repo chỉ có `DETRResnet50SemanticSegmentationF16P8.mlpackage` 41 MB, `ShotDex/Resources/Models/`) | `DepthEstimating` (protocol, bản thật Depth Anything V2) + kho file (dùng chung AC-51); nhãn "Estimated depth"; test với model giả (1 lần, lần mở lại 0 lần) |
| AC-57 | ❌ | Nền tương tác cache ảnh gốc ở cỡ hiển thị (`InteractiveBaseCache` `PRS:84-89`, `installInteractiveBase` `:200-214`), nhưng Depth Blur chạy lại **mỗi khung** (`PRS:369`) | cache kết quả Lens Blur đã trộn, khoá theo nền + (Amount, Bokeh, Near/Far); test đếm lượt chạy + thời gian khung ≤ 1,1× |
| AC-58 | ❌ | — | dựng sẵn 8 mức mờ (D62); kéo Amount chỉ trộn lại; bản lưu chạy thẳng 8 lớp; test lệch preview/lưu ≤ 2/255 |
| AC-59 | ❌ | Luật hôm nay khi không có bản đồ là "trả ảnh gốc" (`PRS:1595-1603`) | ước lượng lỗi → trả ảnh gốc, nhóm mờ + "Couldn't estimate depth for this photo."; test với bộ ước lượng giả trả lỗi |
| AC-60 | ❓ | Không có model trong repo. Phép đo cần bản Release trên iPhone 12/15 + Instruments; không đo được trong phiên này | task đo sau khi AC-56 land; ghi số vào 15e §3 |

## 3. Tái dùng — không dựng khái niệm thứ hai

| Có sẵn | Ở đâu | Dùng cho |
|---|---|---|
| Decode khoan dung từng phần tử | `LossyDecoding.swift`, `PEM:1290-1318`, `PhotoAdjustmentKind` làm CodingKey `PEM:841-870` | mọi trường mới (AC-1) |
| Nướng curve 256 mức (master → kênh) | `PhotoRenderService+Curve.swift:13-47`, `ToneCurveMath.lut` | curve vùng (AC-7…9), curve của mask (AC-44) |
| Trọng số dải HSL | `ColorRenderMath.bandWeights` `:87`, `mixerBandCentres` `PhotoRenderService+Color.swift:17-24` | B&W Mixer (AC-10) |
| Kernel bản đồ rìa | `edgeMask` `MaskKernels.ci.metal:40`, Sharpen Masking `PRS:1815` | NR Contrast (AC-16), Defringe theo rìa (AC-19), Visualize Spots (AC-33) |
| Warp một lượt `lensWarp` + `fillZoom` trần 1,5 | `LensProfileLibrary.swift:193-251` | méo chỉnh tay (AC-20) |
| Kernel vignette có giữ vùng sáng | `PhotoRenderService+Optics.swift:16-59` | Vignette Style (AC-25) |
| Pipeline mask (tích luỹ theo thứ tự, opacity, invert, cache tự động) | `PRS:2036-2290` | Intersect, Object, People (AC-40…51) |
| `instanceIndex` + `VNGenerateForegroundInstanceMaskRequest` | `PRS:2365-2396, 2480-2500` | Object (AC-46), Subject mới (AC-50) |
| Mốc khuôn mặt + `FaceLandmarkMaskBuilder` | `PRS:2413-2441`, `FaceLandmarkMaskBuilder.swift:61-149` | Red Eye (AC-35), bộ phận People (AC-47) |
| Phép vá normalized convolution | `PhotoHealingRenderer.swift:29-128` | heal nét cọ (AC-30) |
| Raster nét cọ + trọng tài chạm | `BrushStrokeRasterizer.swift`, `PaintTouchArbiter.swift` | heal nét, guide Upright |
| Chế độ chạm lấy mẫu + kính lúp | `EditorImageStage.swift:61-98, 369-389, 866-887` | chạm lấy nét, Red Eye, Object, núm guide |
| Chip / pill | `EditorPanelChipStrip` `EditorToolPanels.swift:937`, `EditorChipButtonStyle` `:859`, `EditorPillLabel` `EditorTheme.swift:239` | Bokeh, Vignette Style, Upright, mọi thông báo 3s |
| Nền tương tác đã cache | `InteractiveBaseCache` `PRS:84-89` | 8 mức mờ Lens Blur (AC-57/58) |
| Golden harness | `KernelGoldenSupport.swift` (marker `build/record-kernel-golden` `:16`, dung sai `:50-52`, PNG pipeline theo iOS `:264-308`) | mọi kernel mới, chụp lại golden pipeline một lần (AC-6) |
| Đo phys_footprint | `FocusStackExportTests.swift:16-23` | AC-4 |
| Vision giả qua protocol | `SubjectVisionReading` (`ShotDex/Data/Sources/SubjectVisionReader.swift:22`) — mẫu | `DepthEstimating`, Vision giả cho AC-51/56/59 |

Hai chỗ đang trùng lặp mà kế hoạch này **gom lại**, không làm thêm bản thứ tư:
- Chuỗi pass chép tay ba lần: `PRS:733-745`, `PhotoEditingService.swift:779-800`, `:835-870`.
- Lát cắt look chép tay ba lần: `EditClipboard.swift:49-59, 68-77, 95-108`.

## 4. File đổi

| Tầng | File | Đụng gì | Mới / sửa |
|---|---|---|---|
| Kit · Models | `PEM` | `PhotoAdjustmentKind` + ~20 kind (Calibration 7, NR 3, Defringe 6, lens tay 3, `geoAspect`, `maskHue/Moire/Defringe`); bỏ `depthBlur`, `defringe`. `MaskBlendOperation.intersect`. Kind `.object`, `.people(person, part)`. `PhotoMask.color/curve/points`. Recipe: `upright`, `lensBlur`, `vignetteStyle`, `redEyes` | sửa |
| Kit · Models | `PhotoCurveModels.swift` · `PhotoColorModels.swift` · `PhotoHealing.swift` | `ParametricCurve` · `GrayMixerAdjustments`, `PhotoCalibration` · `PhotoHealingSpot.shape`, `PhotoRedEyeSpot` | sửa |
| Kit · Models | mới `PhotoUprightRecipe.swift`, `LensBlurRecipe.swift` | chế độ + phép nắn đã giải + guides · Amount/Bokeh/Near/Far | mới |
| Kit · Editing (thuần) | mới `ParametricCurveMath`, `CalibrationMatrix`, `UprightGuideSolver`, `ConstrainedCropMath`, `HealSourceScorer`, `LensBlurLayers` | math test được, không Core Image | mới |
| Kit · Render | `PRS` | một danh sách pass chung thay ba bản chép tay (E15); `RenderPass` + `renderPassOrder`; tách `applyAdjustments` (Light/WB/Presence/Detail/Dehaze) khỏi B&W/Vignette/Grain; hàm bọc giữ thứ tự cũ cho video (E13) | sửa |
| Kit · Render | `PhotoRenderService+Color/Curve/Optics.swift`, `LensProfileLibrary.swift`, `PhotoHealingRenderer.swift` | gray mixer, calibration, vùng, defringe, méo/tối góc tay, aspect, style, heal nét, red eye | sửa |
| Kit · Render | mới `PhotoRenderService+LensBlur.swift`, `+LocalColor.swift`, `+RedEye.swift`; `DepthImageReader.swift` (+ semantic matte) | Lens Blur, màu của mask, Red Eye | mới / sửa |
| Kit · Render | `UprightAnalyzer.swift` | `.auto`, Level qua `VNDetectHorizonRequest` | sửa |
| Kit · Kernels | `ColorKernels`, `OpticsKernels`, `MaskKernels`, `HealingKernels.ci.metal`; mới `LensBlurKernels.ci.metal` | ~10 kernel mới (grayMixer, colorDetailNR, chromaSmooth, defringeEdge, intersectMask, localTint, redEye, lensBlurLayer, bokeh…), mỗi kernel một golden | sửa / mới |
| Data | mới `ShotDex/Data/Sources/GeneratedMatteStore.swift`, `DepthEstimator.swift` (Core ML) | kho file matte/độ sâu, model Depth Anything | mới |
| Data | `PhotoEditingService.swift` | Live Photo (khung + mask) dùng danh sách pass chung (E15); lưu báo lỗi trần bộ nhớ | sửa |
| Video | `VideoFrameCompositor.swift`, `VideoMaskRenderer.swift` | gọi hàm bọc giữ thứ tự cũ (E13), không đổi ảnh video | sửa |
| Resources | `ShotDex/Resources/Models/` (`DepthAnythingV2SmallF16.mlpackage`, gitignore như DETR), `README.md`, `THIRD_PARTY_NOTICES.md` | model + giấy phép | mới / sửa |
| Domain | `EditorAdjustmentCatalog.swift` | nhóm Calibration, Lens Blur; NR/Defringe/lens tay/Aspect vào nhóm; lens tay dưới nhãn nhóm MANUAL (E14); bỏ B&W, Vignette, Grain khỏi phạm vi mask (E13) | sửa |
| Domain | `EditClipboard.swift`, `LookPresetStore.swift` | một hàm lát cắt look (cả `EditorSyncScope`) | sửa |
| Domain | `EditorNewMaskOption.swift` | 14 ô, lưới 4 cột, Object/People | sửa |
| Features | `EditorCurveOverlay.swift` (Point · Region), `EditorColorPanel.swift` (B&W Mix), `EditorToolPanels.swift` (Upright 6 chip, Guided, Aspect, Constrain Crop, Style), `EditorHealPanel.swift`, `EditorMaskPanels.swift` / `EditorMaskPhonePanel.swift`, `EditorImageStage.swift` (chạm lấy nét/Red Eye/Object, guide, Visualize), `PEC` (setter, solve Upright, ước lượng độ sâu async) | control | sửa |
| Test | mới `ParametricCurveTests`, `GrayMixerTests`, `CalibrationTests`, `NoiseReductionSplitTests`, `DefringeTests`, `LensManualTests`, `GeoTransformTests`, `VignetteStyleTests`, `UprightStorageTests`, `UprightGuidedTests`, `RedEyeTests`, `SpotVisualizerTests`, `MaskIntersectTests`, `MaskLocalColorTests`, `MaskLocalCurveTests`, `MaskLocalDetailTests`, `ObjectMaskTests`, `PeopleMaskTests`, `GeneratedMatteStoreTests`, `LensBlurTests` (thay `DepthBlurTests`), `RenderOrderTests`, `LargeImageRenderTests`, `LightroomTagCoverageTests`; sửa `RecipeLossyDecodingTests`, `EditClipboardTests`, `EditorHistoryAndSummaryTests`, `PhotoHealingTests`, `UprightAnalyzerTests`, `KernelLibraryTests`, `KernelGoldenTests`, `EditorAdjustmentCatalogTests` | | mới / sửa |
| UI script | mới `iphone-heal-panel.json`, `iphone-people-mask.json`, `iphone-lens-blur.json`, `iphone-upright-guided.json` | | mới |

Logic nằm ở Kit/Editing (math thuần) và Domain. View chỉ gọi setter của `PEC`. Không dữ liệu nào vào `photo_metadata`; matte và độ sâu là file, không phải bảng GRDB.

### Các đường render bị ảnh hưởng khi đổi thứ tự pass

- **Đi qua `render(baseResult:)`** (`PRS:358`): preview editor (`PEC:2318`), preview tương tác (`PEC:2307`), nền tương tác (`PEC:2535-2541`), ảnh nhỏ mask/filter/LUT (`PEC:2417, 2459, 2493`), Save Copy / Save Changes (`PhotoEditingService.swift:257, 265, 389`, gồm cả batch `EditorBatchSaver.swift:134,144`), Compress (`:423`, recipe identity).
- **Bản chép tay, gộp vào danh sách chung ở task 3 (E15)**: `automaticMaskImages` (`PRS:733-745`), khung chuyển động Live Photo (`PhotoEditingService.swift:779-800`) và mask Live Photo (`:835-870`).
- **Đi qua `applyAdjustments`**: mọi mask (`PRS:402`) — chốt E13: mask mất B&W/Vignette/Grain; node video (`VideoFrameCompositor.swift:116`), mask video (`VideoMaskRenderer.swift:39`) — gọi hàm bọc giữ thứ tự cũ.
- **Widget / Share / Edit Action**: không link kit (Frameworks phase rỗng, `project.pbxproj:220-246`; 0 `import ShotDexKit`), nên không có đường render nào ở đó. D60: trần bộ nhớ extension chưa áp.

## 5. Thứ tự task

Mỗi task = một AC = một commit (`feat(FS-03.15): AC-n …`; riêng AC-6 hai commit: task 3 gộp, task 4 đổi thứ tự), có test đi kèm, `/build` sau mỗi commit, thêm `/screens` nếu đụng UI. Mỗi commit sửa cột "Chứng minh bằng" của AC trong FS-03.15x và dòng `Tiến độ` của intent. Task 0 là commit docs của kế hoạch này.

Thứ tự: ✅ → ❌, chia pha **khung render → dữ liệu → pass render → control**. Pha khung mở đầu bằng task gộp pipeline (E15), rồi mới đổi thứ tự pass. AC-24 cần AC-27, AC-41 cần AC-40 nên xếp ngay sau task nó phụ thuộc.

| # | Pha | AC | Task | Test kèm |
|---|---|---|---|---|
| 1 | Khoá | AC-5 | test grep ranh giới kit; ghi baseline 40 kernel | `KernelLibraryTests.kitHasNoSwiftUIOrGRDB`, `everyKernelLoads` |
| 2 | Khoá | AC-31 | viên Opacity trong Heal; khoá công thức trộn tuyến tính (E12) | `PhotoHealingTests.opacityBlendsHalfway` |
| 3 | Khung render | AC-6 (phần E15) | gộp ba chuỗi chép tay (`PRS:733-745`, `PhotoEditingService.swift:779-800`, `:835-870`) vào **một** danh sách pass chung; **giữ nguyên thứ tự hôm nay** — golden pipeline phải xanh không chụp lại | `RenderOrderTests.stillLiveAndAutoMaskShareOnePassList`, `…livePhotoFrameMatchesStill` (± 1/255), golden pipeline hiện có xanh |
| 4 | Khung render | AC-6 | `RenderPass`/`renderPassOrder` đủ 17 bước §3 (pass chưa có thì là no-op); B&W vào Color; Vignette/Grain sau mask; mask bỏ B&W/Vignette/Grain khỏi chuỗi và khỏi danh sách slider của mask (E13); video qua hàm bọc giữ thứ tự cũ (E13); **chụp lại golden pipeline một lần**, có ghi chú | `RenderOrderTests.parityPassOrderMatchesTheSpec`, `EditorAdjustmentCatalogTests.maskHasNoBlackWhiteVignetteGrain`, `VideoEffectMathTests` + golden `video-frame-*` xanh, `KernelPipelineGoldenTests` (chụp lại) |
| 5 | Dữ liệu | AC-1 | mọi trường mới (model ở §4), mặc định trong "chưa sửa", bỏ `depthBlur`/`defringe` | `RecipeLossyDecodingTests.newParityFieldsSurviveOneBadElement` |
| 6 | Dữ liệu | AC-2 | một hàm lát cắt look; guide/phép nắn/Red Eye/retouch thuộc khung | `EditClipboardTests.parityLookSlice` |
| 7 | Dữ liệu | AC-3 | `LightroomTagTable` (sau khi `lightroom-parity` kiểm thẻ) — ❓ có thể chuyển sang FS-03.14 | `LightroomTagCoverageTests.everyParityControlHasATag` |
| 8 | 15a | AC-7 | `ParametricCurveMath` + trường + slider Region | `ParametricCurveTests.shadowsLiftTheDarkQuarterOnly` |
| 9 | 15a | AC-8 | đơn điệu ở mọi cực trị | `…everyExtremeStaysMonotone` |
| 10 | 15a | AC-9 | nướng vùng → điểm vào một bảng; chế độ **Point · Region** của trình sửa curve (control không có AC riêng, chứng minh bằng ảnh) | `…regionThenPointIsOneTable` + ảnh Curve Region |
| 11 | 15a | AC-10 | kernel `grayMixer` + golden | `GrayMixerTests.blueDarkensOnlyBlue` |
| 12 | 15a | AC-15 | khoá hệ quả của task 4: Temp đổi tông xám | `GrayMixerTests.temperatureShiftsTheGreyMix` |
| 13 | 15a | AC-12 | `CalibrationMatrix` + pass tuyến tính sau Lens Blur | `CalibrationTests.redHueMovesRedTowardOrange` |
| 14 | 15a | AC-13 | chuẩn hoá giữ trắng, Shadow Tint | `CalibrationTests.saturationKeepsGreysGrey` |
| 15 | 15b | AC-16 | NR Contrast | `NoiseReductionSplitTests.contrastKeepsEdges` |
| 16 | 15b | AC-17 | Color Detail (kernel + golden) | `…colorDetailKeepsFineColour` |
| 17 | 15b | AC-18 | Color Smoothness (kernel dùng chung với Moiré) | `…smoothnessClearsMottling` |
| 18 | 15b | AC-19 | Defringe tím/lục theo rìa + hàng Min/Max | `DefringeTests.purpleOnlyAtEdges` |
| 19 | 15b | AC-20 | méo tay trong `lensWarp` (golden `lensWarp*` chụp lại); hàng "Distortion" dưới nhãn MANUAL, VoiceOver kèm tên nhóm (E14) | `LensManualTests.distortionPullsTheEdgesIn` |
| 20 | 15b | AC-21 | tối góc tay + Midpoint, dưới nhãn MANUAL (E14) | `LensManualTests.vignettingBrightensCorners` |
| 21 | 15b | AC-22 | Aspect | `GeoTransformTests.aspectStretchesAroundTheCentre` |
| 22 | 15b | AC-25 | Vignette Style + chip | `VignetteStyleTests.highlightPriorityKeepsLights` |
| 23 | 15b | AC-26 | khoá vignette theo khung sau crop, grain sau vignette | `VignetteStyleTests.vignetteFollowsTheCrop` |
| 24 | 15b | AC-27 | `PhotoUprightRecipe`, giải một lần, slider tay cộng lên trên | `UprightStorageTests.solvedTransformAndSlidersAreSeparate` |
| 25 | 15b | AC-23 | `.auto` + Level qua Vision | `UprightAnalyzerTests.autoLevelsAndPartlyStraightens` |
| 26 | 15b | AC-28 | dán chế độ → giải lại trên ảnh đích (editor + batch) | `EditClipboardTests.uprightModeIsResolvedOnTheTarget` |
| 27 | 15b | AC-29 | Constrain Crop | `GeoTransformTests.constrainCropKeepsTheLockedRatio` |
| 28 | 15b | AC-24 | Guided: guides, bộ giải, 6 chip 3 + 3, dòng chú "Up to 4 guides" (E11) | `UprightGuidedTests.twoGuidesMakeBothVertical` + `iphone-upright-guided.json` |
| 29 | 15c | AC-30 | heal/clone nét cọ | `PhotoHealingTests.brushHealRemovesAWire` |
| 30 | 15c | AC-32 | New Source | `…newSourcePicksAnotherPlace` |
| 31 | 15c | AC-33 | Visualize Spots + Threshold | `SpotVisualizerTests.visualizeIsDisplayOnly` |
| 32 | 15c | AC-35 | Red Eye chạm (kernel + căn con ngươi) | `RedEyeTests.tapCentresOnThePupil` |
| 33 | 15c | AC-36 | dự phòng khi không có mặt | `RedEyeTests.noFaceFallsBackToTheTap` |
| 34 | 15c | AC-37 | Fix Red Eye | `RedEyeTests.fixRedEyeSkipsDarkPupils` (Mac/máy thật) |
| 35 | 15c | AC-38 | không có mắt đỏ → pill | `RedEyeTests.fixRedEyeWithNothingToFix` |
| 36 | 15d | AC-40 | Intersect + luồng thêm vùng | `MaskIntersectTests.intersectKeepsOnlyTheOverlap` |
| 37 | 15d | AC-41 | thứ tự vùng + đổi kernel `subtractMask` sang nhân phần bù (E10), golden mới | `MaskIntersectTests.areasApplyInListOrder`, `…subtractMultipliesTheComplement` |
| 38 | 15d | AC-42 | Hue của mask | `MaskLocalColorTests.hueStaysInsideTheMask` |
| 39 | 15d | AC-43 | phủ màu của mask | `…colorTintIsLuminanceNeutral` |
| 40 | 15d | AC-44 | curve của mask (+ Point Color của mask, dùng lại kernel toàn cục) | `MaskLocalCurveTests.maskCurveOnlyInside` |
| 41 | 15d | AC-45 | Moiré (+ Defringe của mask) | `MaskLocalDetailTests.moireFlattensColourStripes` |
| 42 | 15d | AC-51 | `GeneratedMatteStore` | `GeneratedMatteStoreTests.reopenReadsTheSavedMatte` |
| 43 | 15d | AC-50 | Subject = mọi đối tượng | `ObjectMaskTests.subjectTakesEveryObjectWithoutATap` |
| 44 | 15d | AC-46 | Object chạm chọn | `ObjectMaskTests.tapPicksOneObject` |
| 45 | 15d | AC-47 | People + Person 1…4 + bộ phận | `PeopleMaskTests.onePersonRowPerPerson` |
| 46 | 15d | AC-48 | matte ngữ nghĩa + cổng "Needs a Portrait photo…" | `PeopleMaskTests.hairIsGatedOnTheMatte` |
| 47 | 15d | AC-49 | không thấy người → pill | `iphone-people-mask.json` |
| 48 | 15e | AC-53 | Lens Blur 8 lớp + dải lấy nét; bỏ Depth Blur | `LensBlurTests.focusRangeKeepsTheNearHalfSharp` |
| 49 | 15e | AC-54 | 5 hình bokeh + golden | `LensBlurTests.ringBokehHasABrightRim` |
| 50 | 15e | AC-58 | 8 mức dựng sẵn, kéo Amount chỉ trộn | `LensBlurTests.amountDragOnlyReblends` |
| 51 | 15e | AC-57 | slider khác dùng lại kết quả đã trộn | `LensBlurTests.otherSlidersReuseTheBlendedResult` |
| 52 | 15e | AC-56 | Depth Anything kèm app + `DepthEstimating` + lưu vào kho | `LensBlurTests.noDepthPhotoIsEstimatedOnce` |
| 53 | 15e | AC-59 | ước lượng lỗi → ảnh gốc + dòng chú | `LensBlurTests.estimationFailureRendersTheOriginal` |
| 54 | Control | AC-11 | B&W Mix thay Mixer; HSL/Point mờ + dòng chú | `GrayMixerTests.hslIsOffInBlackAndWhite` + ảnh Color |
| 55 | Control | AC-14 | nhóm Calibration | `EditorHistoryAndSummaryTests.calibrationDragIsOneStep` |
| 56 | Control | AC-34 | Clear All (xác nhận) + Show Spot Pins | `PhotoHealingTests.clearAllIsOneStep` + `iphone-heal-panel.json` |
| 57 | Control | AC-39 | hàng Heal · Clone · Red Eye, control Red Eye | `iphone-heal-panel.json` + dump |
| 58 | Control | AC-52 | lưới mask 4×4, 14 ô | `iphone-people-mask.json` + dump |
| 59 | Control | AC-55 | nhóm Lens Blur, chạm lấy nét, Visualize Depth | `LensBlurTests.tapToFocusCentresTheRange` + `iphone-lens-blur.json` |
| 60 | Toàn cục | AC-4 | lưu 100MP ≤ 1,5 GB; vượt trần thì báo lỗi, giữ phiên | `LargeImageRenderTests.hundredMegapixelSaveStaysUnderCeiling` |
| 61 | Đo | AC-60 | Depth Anything trên iPhone 12/15, ghi vào 15e §3 | Instruments, bản Release |

**61 task** (task 3 là phần gộp pipeline của AC-6, E15). Control dạng slider vào cùng commit với pass của nó (một dòng trong `EditorAdjustmentCatalog`, khoá bằng `EditorAdjustmentCatalogTests`). Control riêng (Region, B&W Mix, Style, Upright chip/Guided, Heal, lưới mask, nhóm Lens Blur) nằm ở task có AC giao diện tương ứng.

**Việc lấy model Depth Anything (trong task 52):**
1. Tải bản Core ML **Depth Anything V2 Small F16** từ trang Core ML Models của Apple (~50 MB; kiểm lại tên và cỡ đúng trên trang).
2. Kiểm giấy phép. Bản **Small** là Apache-2.0. Bản Base/Large là **CC-BY-NC-4.0, cấm dùng thương mại** — tuyệt đối không dùng.
3. Để `.mlpackage` ngoài git như DETR (`.gitignore:15`), cập nhật `Models/README.md` (bảng "thiếu model thì sao") và `THIRD_PARTY_NOTICES.md`.
4. Clone mới không có model phải đi đúng đường AC-59.
5. Đo dung lượng `.mlmodelc` trong bản build và ghi vào AC-60.
6. Model nạp từ `Bundle.main` giống `loadSkyModel` (`PRS:2621-2634`), nhưng qua protocol `DepthEstimating` để test tiêm bản giả.

## 6. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| Golden chạy mãi vì đổi thứ tự pass | cao | Chụp lại golden pipeline (`pipeline-*-ios26/27`) **một lần** ở task 4, bằng marker `build/record-kernel-golden`; task 3 (gộp, E15) không được đổi golden nào. Kernel mới đều có golden. Golden `lensWarp*` chụp lại ở task 19, golden `subtractMask` ở task 37, commit ghi rõ lý do. Không nới dung sai |
| Bản chép tay của chuỗi pass lệch nhau (Live Photo ra khác ảnh tĩnh) | cao nếu không gom | Chốt E15: task 3 gom về một danh sách pass chung **trước** task 4 đổi thứ tự. Test so khung Live Photo với ảnh tĩnh ± 1/255 |
| Đổi `applyAdjustments` làm video ra khác | trung bình | Chốt E13: hàm bọc riêng giữ nguyên thứ tự cho video tới khi FS-12 quyết. `VideoEffectMathTests` / golden `video-frame-*` phải giữ xanh |
| Kéo slider chậm đi (không được hạ độ phân giải — FS-03.04) | cao với Lens Blur | Mỗi pass bỏ qua hẳn khi ở mặc định. Lens Blur dùng cache trộn + 8 mức dựng sẵn (D62). Đo thời gian khung trước/sau ở AC-57. `perf-profiler` chạy sau task 4, 48–51 |
| Lưu 100MP vượt 1,5 GB | cao | Một lớp RGBA half 11648×8736 ≈ 814 MB; mask cọ 8-bit ≈ 102 MB mỗi cái. Lens Blur lúc lưu chạy **tuần tự** 8 lớp, không giữ cả 8. `CIContext` render theo ô. Đo bằng khung `FocusStackExportTests:16-23`. Vượt trần thì ném lỗi có tên trước khi tạo asset |
| App to thêm ~50 MB | chắc chắn | Đã chấp nhận (D59). Ghi số thật ở AC-60 |
| Vision trên iOS 17 / simulator | trung bình | `VNGenerateForegroundInstanceMaskRequest` và `VNGeneratePersonInstanceMaskRequest` (tối đa 4 người) đều từ iOS 17 = mức triển khai tối thiểu, nên không cần `#available`. Simulator cho mốc khuôn mặt sai chỗ (`PRS:2419-2423`) và không tách được người: AC-23/28/37/46/47/50 chạy trên Mac/máy thật, và kế hoạch ghi rõ "chưa chứng minh trên sim". Không dùng ảnh mặt người thật (memory `no-face-photos-in-tests`) |
| Upright dán hàng loạt phải giải trên từng ảnh | trung bình | Giải trong `EditorBatchSaver` trước khi render, trên ảnh preview 256px (`UprightAnalyzer.analysisSide`). Không giải được thì bỏ phần đó, như luật hôm nay |
| Kernel màu trên vùng con làm đổi pixel xa (Hue/Tint/Curve của mask, Red Eye) | trung bình | Luật FS-16 §5: phủ bằng alpha, lấy mẫu ảnh chưa sửa, thử pixel xa với ≥ 2 edit (memory `coreimage-color-kernel-region-trap`) |
| Kho matte phình to | thấp | 100–400 KB mỗi mask. Xoá theo ảnh khi recipe bỏ mask. Trần tổng ghi ở NF-02 (việc của `memory-leak`) |
| Trần bộ nhớ extension | hoãn (D60) | Không extension nào link kit (`project.pbxproj:220-246`). Ghi ở EX-01; ngày có extension render thì đo lại |
| Concurrency: ước lượng độ sâu / Vision / giải Upright chạy async trong `PEC` (`@MainActor`) | trung bình | Task gắn vào phiên, huỷ khi đổi ảnh. Kết quả đi qua actor `PhotoRenderService`. `swift-concurrency` chạy sau task 42, 52 |
| Thiết bị: lưới mask 4×4 và hàng Heal 3 ô trên Duo cao 669pt / iPhone SE | trung bình | Chụp đủ iPhone 17 (26.5 + 18.6), iPad, Duo trong/ngoài ở task 57–59 (`/screens`) |
| Thẻ `crs:` sai tên hoặc giá trị | trung bình | Task 7 chờ `lightroom-parity` kiểm (câu treo 3). Không chặn control |
| PhotoKit (lưu Live Photo) | thấp | Đường lưu không đổi, chỉ đổi chuỗi pass. `photokit-guard` xem task 3 (Live Photo vào danh sách chung) |

## 7. Phản biện (điền sau khi chạy `challenger`)

| Phản đối | Trả lời / thay đổi |
|---|---|
| … | … |

## 8. Cách chứng minh là xong

- **Test**: mọi tên dự kiến ở cột "Chứng minh bằng" của 15/15a–e (bảng §5), cộng `KernelGoldenTests` / `KernelLibraryTests` mở rộng, `RenderOrderTests`, `LargeImageRenderTests`. Chạy `/test` sau mỗi task, `Tools/gate` ở cuối.
- **Màn hình phải chụp** (iPhone 17 iOS 26.5 và 18.6; iPad; Duo trong và ngoài cho lưới mask và Heal):
  - Edit › Color (B&W Mix, dòng "Off while…")
  - Curve Region
  - Calibration
  - Detail (NR 6 hàng)
  - Optics (nhãn nhóm LENS PROFILE / MANUAL, lens tay, Defringe Min/Max)
  - Transform (6 chip Upright, Guided với 4 guide, Aspect, Constrain Crop)
  - Effects (Vignette Style)
  - Lens Blur (Estimated depth, Visualize Depth, Tap to focus, lỗi ước lượng)
  - Heal (3 chế độ, Red Eye, Visualize Spots, hộp Clear All)
  - Mask (lưới 4×4, People › Person, Intersect area, hàng Hair mờ, danh sách slider không còn B&W/Vignette/Grain)
- **Tài liệu phải cập nhật**:
  - cột "Chứng minh bằng" của từng AC trong 15/15a–e
  - FS-04.03 (Depth Blur bị thay)
  - FS-03.01b §5 (Upright lưu riêng)
  - FS-03.05 (Subject đổi nghĩa, Intersect)
  - EX-01 (D60)
  - BD-02 (kho matte)
  - NF-02 (trần 100MP, trần kho matte)
  - `Models/README.md` + `THIRD_PARTY_NOTICES.md`
  - 15e §3 (số đo AC-60)
- **Agent ở Deploy**:
  - `perf-profiler` — frame time, pass ở mặc định, Lens Blur
  - `memory-leak` — 100MP, cache Lens Blur, kho matte
  - `extension-boundary` — type `public` mới, kit không SwiftUI/GRDB, model nạp từ `Bundle.main`
  - `swift-concurrency` — ước lượng độ sâu / Vision / giải Upright async
  - `test-coverage` — math thuần mới
  - `lightroom-parity` — danh sách thẻ `crs:`, hệ số quy đổi
  - `photokit-guard` — Live Photo đi chuỗi chung
  - `a11y-voiceover` — guide, ghim vết, núm điểm chia curve, chạm lấy nét, nhãn "Distortion, Manual" (E14)
  - `copy-consistency` — nhãn nhóm LENS PROFILE / MANUAL (E14), "Up to 4 guides" (E11), câu lỗi
  - `device-layout` + `iphone-ux-review` + `duo-ux-review` — lưới 4×4, hàng Heal
  - `ios26-parity` — mọi panel mới
  - `challenger` — trước khi duyệt kế hoạch

> Dòng `Tiến độ` của intent **chưa sửa** trong lượt này (giới hạn phiên: chỉ viết file kế hoạch). Khi duyệt, người commit ghi:
> `**chưa làm** (2026-09-28) — plan [2026-09-28-fs-03-15-lightroom-parameter-parity](../_plans/2026-09-28-fs-03-15-lightroom-parameter-parity.md) chờ duyệt, 61 task`.
