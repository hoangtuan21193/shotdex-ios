# Intent: Sửa ống kính cho RAW có điều khiển được, và dữ liệu ống kính luôn mới

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan |
| Ngày | 2026-09-27 |
| Trạng thái | accepted |
| Tiến độ | **chưa làm** (2026-09-27) — chưa có spec |
| Nguồn | phản hồi người dùng (chủ sở hữu sản phẩm) — phiên thiết kế 2026-09-27 |
| Spec sinh ra từ đây | (điền khi sang Design) |

Liên quan: [lightroom-preset-exchange](2026-09-27-lightroom-preset-exchange.md) (preset ghi
`LensProfileDistortionScale/VignettingScale/ChromaticAberrationScale`) ·
[lightroom-parameter-parity](2026-09-27-lightroom-parameter-parity.md) · nối tiếp quyết định Lensfun ở
[FS-03.11](../02-functional-spec/FS-03-photo-editor/11-parity-with-lightroom.md) (2026-09-23).

## Problem — vấn đề

- **RAW và JPEG sửa ống kính theo hai đường khác nhau.** JPEG/HEIC đi Lensfun nhưng **chỉ sửa méo**; RAW chỉ
  bật/tắt phần sửa có sẵn trong `CIRAWFilter` của Apple
  ([PhotoRenderService.swift:1152](../../ShotDexKit/Render/PhotoRenderService.swift),
  [:1855](../../ShotDexKit/Render/PhotoRenderService.swift) bỏ qua Lensfun khi `source.isRAW`). Người dùng
  không chỉnh được độ mạnh sửa méo / tối góc / quang sai màu (CA), và ta không biết Apple đã sửa gì.
- **Chưa sửa tối góc và CA theo profile**: `lensfun-distortion.json` chỉ chứa dữ liệu méo, dù Lensfun có cả
  vignetting và TCA cho nhiều ống.
- **Preset Lightroom** mang ba mức scale riêng → hôm nay không có chỗ đặt.
- **Ống kính mới**: bản phần mềm Lensfun phát hành lần cuối 2023, nhưng cơ sở dữ liệu vẫn cập nhật liên tục
  (commit `data/db` ngày 24/9/2026). ShotDex chỉ có dữ liệu ở thời điểm chạy `Tools/lensfun-to-json.py`.
- **Chữ trên màn**: người dùng không biết "Lensfun" là gì.

## Proposed outcome — kết quả mong muốn

- **Ba slider riêng**: Distortion · Vignetting · Chromatic Aberration (0–200, mặc định 100), cho cả RAW lẫn
  JPEG, cộng hai slider chỉnh tay (méo, tối góc ống kính) thuộc
  [lightroom-parameter-parity](2026-09-27-lightroom-parameter-parity.md).
- **Thứ tự nguồn cho RAW**: (1) dữ liệu hiệu chỉnh **nhúng trong file RAW**, ShotDex tự đọc (Sony, Fuji,
  Panasonic, OM/Olympus, DNG OpcodeList) → (2) Lensfun → (3) phần sửa có sẵn của Apple (chỉ bật/tắt) →
  (4) không sửa. Không bao giờ sửa hai lần (dùng (1) hoặc (2) thì tắt phần của Apple).
- **Chữ hiển thị** (không có chữ "Lensfun"): "Found from photo info" · "Chosen by you" · "Using the camera's
  built-in correction" + dòng mờ "Strength controls need a lens profile" · "No profile for this lens yet" +
  Choose Lens. Ghi công Lensfun (CC-BY-SA) chỉ trong About.
- **Dữ liệu mới mỗi bản phát hành**: `/release-check` chạy lại `lensfun-to-json.py` (thêm vignetting + TCA)
  và báo số ống tăng. Không cần mạng trong app.
- Map tên ống từ `LensProfileName` của preset Lightroom qua bộ khớp hiện có.

## Affected users and systems — phạm vi ảnh hưởng

- **Code**: `ShotDexKit/Render/LensProfileLibrary.swift`, `PhotoRenderService` (đường RAW: bù tối góc trong
  `CIRAWFilter.linearSpaceFilter`, nắn méo/CA sau giải mã), `ShotDexKit/Resources/lensfun-*.json`,
  `Tools/lensfun-to-json.py`, bộ đọc maker notes / DNG opcode (mới, trong kit), `Features/Editing`
  (Optics › Lens Correction), `.claude/skills/release-check`.
- **Thiết bị**: mọi thiết bị.
- **Dữ liệu đã lưu**: recipe thêm ba scale + nguồn đã giải; ảnh RAW sửa trước đây có thể khác chút — app chưa
  phát hành, không migration.
- App to thêm (ước ~1–2MB dữ liệu vignetting/TCA — chưa đo).

## Constraints — ràng buộc

- Không cần internet; không cập nhật dữ liệu trong app (đã cân nhắc, không chọn).
- Không kèm `.lcp` của Adobe; giữ nguyên dữ liệu Lensfun (chỉnh ở lớp khớp tên bên ngoài — luật CC-BY-SA đã
  chốt 2026-09-23).
- Không hạ độ phân giải preview; pass mới chạy GPU.
- Kit thuần: không SwiftUI/GRDB; extension render vẫn dưới trần bộ nhớ.

## Open questions — câu hỏi còn treo

1. **Định dạng dữ liệu nhúng của từng hãng** (Sony `DistortionCorrParams`, Fuji `GeometricDistortionParams`,
   Panasonic, OM, DNG `WarpRectilinear` / `FixVignetteRadial`): đọc được ổn định không, mô hình có đổi về
   cùng dạng polynomial không? → thử nghiệm với file RAW thật của từng hãng (chặn Design phần (1); phần
   (2)–(4) đi trước được).
2. Lightroom có thật ưu tiên dữ liệu nhúng với máy mirrorless không (để khớp hành vi khi nhập preset). →
   agent `lightroom-parity` trong `/spec`.
3. Dung lượng thật của JSON khi thêm vignetting + TCA. → đo lúc chạy script.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
