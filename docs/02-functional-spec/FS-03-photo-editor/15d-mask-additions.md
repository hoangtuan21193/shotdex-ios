# FS-03.15d — Mask: phép giao, thông số riêng, Object và People

`FS-03.15d` · `ShotDexKit/Models/PhotoEditingModels.swift` · mask trong `ShotDexKit/Render/` · cập nhật 2026-09-28

**Một câu:** mask của Lightroom giao được hai vùng, có Hue, phủ màu, curve và point color riêng, và chọn
được từng người, từng vật — ShotDex thêm đủ phần dựng được bằng API của iOS.

Tổng quan: [FS-03.15](15-lightroom-parameter-parity.md). Mask đang có: [FS-03.05](05-local-masks.md).
Danh sách mask, lưới chọn loại, hàng cọ: [FS-03.13](13-iphone-editor-layout.md).

## 1. Phép giao (Intersect)

- Mỗi vùng của mask là **Add · Subtract · Intersect**. Danh sách mask (FS-03.13) thêm **Intersect area**
  cạnh Add area / Subtract area; hàng vùng mang ký hiệu ⊕ / ⊖ / ⊗.
- Các vùng tính **theo thứ tự trong danh sách**, dồn vào một kết quả: Add lấy lớn hơn, Subtract nhân phần bù,
  Intersect nhân với vùng mới. Opacity của vùng làm mềm tác dụng của chính phép đó.
- Subtract = hiện tại × (1 − vùng trừ): mép mềm 0,8 trừ 0,5 còn 0,4, không phải 0,3. *Vì trừ thẳng làm mép
  bị khuyết sâu hơn Lightroom và Photoshop.*
- Vùng đầu tiên luôn là Add. Đổi phép của một vùng là một bước Undo.
- Hôm nay (2026-09-28), trước danh sách mask của FS-03.13: hàng dưới dải mask trên iPhone có nút ⧉ (menu **Add Area ·
  Subtract Area · Intersect Area** → Brush · Linear · Radial · Color Range · Luminance Range · Subject · Sky) rồi ba
  chip Add · Subtract · Intersect cho nét cọ/hình kế tiếp. Intersect = hiện tại × mix(1, vùng, Opacity) — kernel
  `intersectMask`.

## 2. Thông số riêng của từng mask

Danh sách slider của mask (một danh sách dài như Edit) thêm:

| Nhóm | Control mới | Làm gì |
|---|---|---|
| Color | **Hue** ±100 | xoay hue trong mask, cả vòng màu, không đổi độ sáng |
| Color | **Color** (ô màu) | phủ một màu trung tính về độ sáng; chọn bằng bánh xe màu của overlay (đang có) — không component mới |
| Color | **Point Color** | cùng panel Point Color toàn cục, tối đa 8 điểm cho mỗi mask |
| sau Light | **Curve** | hàng "Edit Curve" mở cùng trình sửa curve điểm 4 kênh, chỉ cho mask này |
| Detail | **Moiré** 0…100 | làm mờ sắc độ tần số cao dạng vân, không đụng độ sáng |
| Detail | **Defringe** ±100 | dương khử viền màu mọi hue trong mask; âm che mask khỏi Defringe toàn cục |

- Thứ tự trong một mask: bộ chỉnh chuẩn → Hue → Color → Point Color → Curve → Moiré → Defringe → trộn theo
  matte. Kernel màu áp trong vùng con phải để yên pixel xa (FS-16 §5).
- **Bỏ khỏi mask**: B&W, Vignette, Grain — Lightroom cũng không có (FS-03.15 §3). Bộ chỉnh chuẩn còn Light ·
  WB · Presence · Detail · Dehaze; xám trong mask là Saturation −100.
- Mask mới không mang curve/point color nào: recipe chỉ thêm khoá khi khác mặc định.

## 3. Object và People

Hai loại mới, cả hai dùng Vision (iOS 17), chạy trên máy trên preview, **một lần mỗi ảnh**; matte lưu vào
kho matte (§5).

- **Subject** đổi nghĩa: luôn là **mọi** đối tượng foreground, tạo ngay khi chọn ô, không cần chạm.
- **Object**: chọn ô Object → pill "Tap an object in the photo"; chạm một vật → mask phủ đúng **một** đối
  tượng foreground tại điểm chạm. Add area + chạm vật khác = thêm vật đó.
- Chạm nền (không đối tượng nào): không tạo mask, pill "Nothing to select there" 3s.
- **People**: ô People mở danh sách con — **All People** · **Person 1…4** (thumbnail người đó, xếp theo
  diện tích) → chọn người → **Entire Person · Face Skin · Body Skin · Eyes · Lips · Hair · Teeth · Glasses**.
- Tách từng người dùng phân tách theo từng người của Vision (tối đa 4); >4 người thì All People dùng phân
  tách người gộp, và chỉ 4 người lớn nhất có hàng riêng.
- Face Skin / Eyes / Lips dựng từ điểm mốc khuôn mặt như hôm nay, **giao** với người đã chọn.
- **Hair · Body Skin · Teeth · Glasses** đọc từ **matte ngữ nghĩa** mà camera iPhone ghi vào ảnh Portrait,
  giao với người đã chọn; Body Skin = matte da trừ Face Skin. Không đọc từ model nào.
- Ảnh không có matte đó: hàng mờ 35%, chạm thì hiện lý do 3s "Needs a Portrait photo taken on iPhone", không
  tạo mask (luật chung FS-03.05 §2).
- Vision lỗi hoặc không thấy người (simulator không chạy được): pill 3s "Couldn't find a person", mask rỗng
  vẫn giữ để Undo/Delete — như Subject.
- **Lưới chọn loại** của FS-03.13 thành **4×4**, 14 ô: Subject · Sky · Background · Object · People · Face
  Skin · Eyes · Lips · Brush · Radial · Linear · Color · Luminance · Depth.
- Ba ô khuôn mặt **giữ ở ngoài** People và vẫn phủ mọi khuôn mặt như hôm nay; trong People chúng giao với
  người đã chọn. *Vì chỉnh da, mắt, môi không nên sâu thêm một chạm.*

## 4. Ngoài phạm vi

Lông mày, quần áo, tròng trắng, mống mắt: không có model Apple công bố, nên preset có thì bỏ vùng đó và báo
trong báo cáo import (FS-03.14). Mask còn lại của correction vẫn nhập.

## 5. Lưu matte sinh ra

- Matte sinh ra (Subject, Object, People, Sky, Background…) lưu thành **file 8-bit ¼ độ phân giải** (ước
  100–400KB/mask) trong **kho riêng** của app, khoá theo ảnh + vùng + nguồn — kết quả quét đắt tiền (BD-02).
- Mở lại ảnh thì đọc file, không chạy lại Vision. File mất hoặc hỏng thì tính lại, không báo lỗi. *Vì Vision
  có thể trả matte khác giữa hai bản iOS — tính lại thì mask đổi sau khi cập nhật hệ điều hành.*
- Matte ngữ nghĩa đọc từ file ảnh thì luôn như nhau, không cần lưu.
- Không nhúng vào recipe (luật "không phình recipe" của LUT). Độ sâu ước lượng của Lens Blur dùng chung kho
  này (15e §3).

## 6. Thẻ `crs:`

| Control | Thẻ | Ghi chú |
|---|---|---|
| nhóm mask | MaskGroupBasedCorrections → CorrectionMasks | cấu trúc cần kiểm |
| Add / Subtract / Intersect | MaskBlendMode (mỗi vùng) | giá trị cần kiểm |
| Hue · Color | LocalHue · LocalToningHue · LocalToningSaturation | ±100 |
| Curve của mask | MainCurve · RedCurve · GreenCurve · BlueCurve (trong correction) | cần kiểm |
| Point Color của mask | LocalPointColors | cần kiểm |
| Moiré · Defringe | LocalMoire · LocalDefringe | ±100 |
| Object · People · bộ phận | What + MaskSubType + MaskSubCategoryID | giá trị cần kiểm |

## 7. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-40 | ảnh 256×256: nửa trên và nửa dưới đều có ô lam và ô vàng; mask = Linear phủ nửa trên | thêm Color Range lấy mẫu ô lam, phép Intersect | matte: ô lam nửa trên ≥ 0,95; ô lam nửa dưới ≤ 0,05; ô vàng nửa trên ≤ 0,05 | `MaskIntersectTests.intersectKeepsOnlyTheOverlap` · `…intersectAreaJoinsTheSelectedMask` · golden `intersectMask-*` · `ShotDexUITests/scripts/iphone-mask-intersect.json` |
| AC-41 | mask = Radial A (Add) rồi Linear B (Intersect) | thêm Radial C (Add) không chồng A | vùng C = 1 dù B = 0 ở đó (phép tính theo thứ tự); Undo một lần gỡ C; một vùng Subtract 0,5 trên matte 0,8 cho 0,4 ± 1/255 | ⚠️ chưa có (dự kiến `MaskIntersectTests.areasApplyInListOrder`) |
| AC-42 | ảnh 256×256, mask Radial ở ô 64×64 góc trên trái, thêm Exposure +0,5 toàn cục | đặt Hue +30 cho mask | hue trong mask đổi ≥ 10°; khối 32×32 quanh (0,875; 0,875) bằng bản không Hue ± 1/255 | ⚠️ chưa có (dự kiến `MaskLocalColorTests.hueStaysInsideTheMask`) |
| AC-43 | vùng xám 0,5 trong mask | đặt Color hue 30°, độ bão hoà 50 | pixel trong mask có hue 30° ± 5°; độ sáng Rec.709 lệch ≤ 1/255 | ⚠️ chưa có (dự kiến `MaskLocalColorTests.colorTintIsLuminanceNeutral`) |
| AC-44 | dải xám trong mask nửa trái, curve toàn cục Soft S | đặt curve của mask: điểm (0,5; 0,4) | nửa trái mức 0,5 ra 0,4 ± 2/255 sau Soft S; nửa phải bằng bản chỉ có Soft S ± 1/255 | ⚠️ chưa có (dự kiến `MaskLocalCurveTests.maskCurveOnlyInside`) |
| AC-45 | vân moiré màu tổng hợp (sọc lục/tím 3px cùng độ sáng) trong mask | đặt Moiré 80 | phương sai sắc độ trong mask còn ≤ 50%; độ sáng lệch ≤ 1/255; ngoài mask không đổi | ⚠️ chưa có (dự kiến `MaskLocalDetailTests.moireFlattensColourStripes`) |
| AC-46 | ảnh CC0 không người, hai vật tách rời | chạm Object vào vật 1 | IoU với đối tượng 1 của Vision ≥ 0,9; phủ vật 2 ≤ 5% | ⚠️ chưa có — cần máy thật hoặc Vision của Mac (dự kiến `ObjectMaskTests.tapPicksOneObject`) |
| AC-47 | ảnh có 2 người (hình nộm/manơcanh, không mặt thật) | mở People | có đúng 3 hàng: All People · Person 1 · Person 2, thứ tự theo diện tích | ⚠️ chưa có — cần máy thật (dự kiến `PeopleMaskTests.onePersonRowPerPerson`) + ảnh New Mask |
| AC-48 | ảnh HEIC không có matte ngữ nghĩa | People → Person 1 → chạm Hair | không tạo mask; hàng Hair mờ 35% và hiện "Needs a Portrait photo taken on iPhone" 3s | ⚠️ chưa có (dự kiến `PeopleMaskTests.hairIsGatedOnTheMatte`) + `ShotDexUITests/scripts/iphone-people-mask.json` |
| AC-49 | simulator (Vision không tách được người) | chạm People → All People | pill "Couldn't find a person" 3s; mask rỗng vẫn trong danh sách; không alert | ⚠️ chưa có (`ShotDexUITests/scripts/iphone-people-mask.json`, iPhone 17 26.5) |
| AC-50 | ảnh CC0 không người, hai vật tách rời | chọn ô Subject, không chạm | mask phủ cả hai vật, IoU với phân tách gộp của Vision ≥ 0,9; không có pill "Tap…" | ⚠️ chưa có — cần máy thật hoặc Vision của Mac (dự kiến `ObjectMaskTests.subjectTakesEveryObjectWithoutATap`) |
| AC-51 | ảnh có mask Object đã tạo | đóng rồi mở lại ảnh; rồi xoá file matte và mở lần nữa | lần 2: Vision chạy 0 lần, matte khớp từng pixel lần 1; lần 3: tính lại, không alert | ⚠️ chưa có (dự kiến `GeneratedMatteStoreTests.reopenReadsTheSavedMatte`, Vision giả) |
| AC-52 | editor, chưa có mask, iPhone 17 26.5 và 18.6 | mở Mask | lưới 4 cột đủ 14 ô đúng thứ tự §3; Face Skin, Eyes, Lips nằm ngoài People | ⚠️ chưa có (`ShotDexUITests/scripts/iphone-people-mask.json` + element dump) |

**Chưa chứng minh được:** AC-41…AC-52 (chưa code). Point Color và Defringe của mask không có AC riêng —
dùng lại pass toàn cục, phủ bởi golden kernel FS-16 khi port.
