# FS-03.16 — Nguồn sửa ống kính: ba mức độ mạnh, dữ liệu nhúng trước

`FS-03.16` · tier D · render `ShotDexKit/Render/PhotoRenderService.swift` · bảng
`ShotDexKit/Render/LensProfileLibrary.swift` · khớp `ShotDex/Domain/Editing/LensProfileMatcher.swift` · panel
`ShotDex/Features/Editing/EditorLensProfileSection.swift` · script `Tools/lensfun-to-json.py` · cập nhật 2026-09-28

Nguồn intent: [2026-09-27-lens-correction-sources](../../_intents/2026-09-27-lens-correction-sources.md) ·
nối tiếp [FS-03.11 §7](11-parity-with-lightroom.md) (Lensfun cho JPEG, chốt 2026-09-23).

**Một câu:** RAW và JPEG sửa méo, tối góc và quang sai màu theo cùng một luật chọn nguồn, mỗi mặt có một
slider độ mạnh 0–200, và dữ liệu ống kính mới lại ở mỗi bản phát hành.

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 16 | tài liệu này | vì sao, phạm vi, thứ tự nguồn, dữ liệu recipe, preset, tiêu chí chung |
| 16a | [Nguồn và render](16a-correction-sources-and-render.md) | đọc dữ liệu nhúng từng hãng, Lensfun thêm tối góc + CA, công thức độ mạnh, không sửa hai lần |
| 16b | [Panel Optics và làm mới dữ liệu](16b-optics-panel-and-data-refresh.md) | chữ trên màn từng trạng thái, Choose Lens, ghi công, bước làm mới trong `/release-check` |

## 1. Người dùng cần gì

Người chụp RAW bằng ống góc rộng muốn kéo méo về 60% để giữ chút cong tự nhiên, bỏ hết tối góc, và biết
ảnh đang được sửa theo cái gì. Hôm nay RAW chỉ có một công tắc bật/tắt phần sửa của Apple, JPEG chỉ được
nắn méo, và preset Lightroom mang ba mức độ mạnh không có chỗ đặt.

## 2. Phạm vi

**Có:**
- Ba slider **Distortion · Vignetting · Chromatic Aberration**, 0–200, mặc định 100, cho RAW lẫn JPEG/HEIC.
- Thứ tự nguồn cho RAW: dữ liệu nhúng trong file → Lensfun → phần sửa có sẵn của Apple → không sửa (§3).
- Lensfun thêm dữ liệu **tối góc** và **CA** (hôm nay bảng chỉ có méo).
- Nhập ba mức độ mạnh và tên ống từ preset Lightroom ([FS-03.14](14-lightroom-preset-exchange.md)).
- Bước làm mới dữ liệu Lensfun ở mỗi bản phát hành, báo số ống tăng/giảm (16b §4).

**Cố ý không có:**
- Hai slider chỉnh tay (méo, tối góc ống kính) — thuộc [FS-03.15](15-lightroom-parameter-parity.md).
- Cập nhật dữ liệu trong app qua mạng — đã cân nhắc, không chọn; app không cần internet.
- File `.lcp` của Adobe, và sửa tại chỗ dữ liệu Lensfun — luật CC-BY-SA chốt 2026-09-23.
- Nắn tâm quang học lệch (`<center>` của Lensfun) — FS-03.11 coi tâm ảnh là tâm quang học; giữ nguyên.

## 3. Thứ tự nguồn — luật chung

| Thứ tự | Nguồn | RAW | JPEG/HEIC | Ba slider |
|---|---|---|---|---|
| 1 | Dữ liệu hiệu chỉnh hãng ghi trong file, ShotDex tự đọc | có (DNG, Sony, Fujifilm, Panasonic, OM — 16a §1) | không | chạy (mặt nào file thiếu thì lấy bù từ nguồn 2) |
| 2 | Lensfun, khớp từ EXIF hoặc người dùng chọn | có | có | chạy (mặt nào Lensfun có dữ liệu) |
| 3 | Phần sửa có sẵn của bộ giải RAW Apple (Core Image) | có, chỉ bật/tắt | không | mờ |
| 4 | Không sửa | — | — | mờ |

- **Chọn nguồn theo từng mặt** (méo · tối góc · CA): mỗi mặt lấy nguồn 1 nếu có, không thì nguồn 2; cả hai
  thiếu thì slider mặt đó mờ. Nguồn 3 chỉ dùng khi không mặt nào có nguồn 1 hoặc 2.
- **Không bao giờ sửa hai lần**: dùng nguồn 1 hoặc 2 thì phần sửa của Apple **tắt**. Vì Apple không nói nó
  đã sửa gì, bật chồng là không kiểm được.
- Nguồn đã giải **lưu trong recipe**, renderer không tự chọn lại: một bản làm mới dữ liệu không được đổi âm
  thầm ảnh đã sửa.
- RAW vừa mở: nguồn giải lúc mở nhưng **chỉ giữ trong phiên**; ghi vào recipe ở lần chỉnh đầu tiên. *Vì ghi
  lúc mở thì mọi RAW vừa mở bị coi là "đã sửa" — hiện dấu, hỏi lưu khi thoát.*
- Nguồn 2 có dữ liệu méo nhưng thiếu tối góc/CA thì slider mặt thiếu mờ, không rơi xuống nguồn 3.
- Mặc định: RAW **bật**, JPEG **tắt**; JPEG máy ảnh đã tự sửa trong máy không tự khớp ống (16a §4).

## 4. Dữ liệu recipe

| | |
|---|---|
| Bộ thông số chỉnh | ba mức độ mạnh (0–2, hiển thị 0–200) · **một** công tắc cho mọi nguồn |
| Lựa chọn hồ sơ ống | thêm loại nguồn; giữ id ống Lensfun, crop thân máy, tự khớp hay tự chọn — lưu riêng, ngoài bộ thông số |
| *Tên trong code (2026-09-29)* | kind `lensDistortionScale` · `lensVignettingScale` · `lensChromaticAberrationScale` (mặc định 1, không ghi khoá khi 1) + `lensCorrection` làm công tắc; `PhotoLensProfileChoice.distortionSource/vignettingSource/chromaticAberrationSource` kiểu `LensCorrectionSource` (`embedded · lensfun · appleBuiltIn · none`), `lensID` thành tuỳ chọn; lựa chọn lưu trước khi có nguồn đọc ra Lensfun cho cả ba mặt |
| Bỏ | thang bật/tắt riêng của RAW trong nhóm RAW (0–1 so ngưỡng 0,5) — không còn khái niệm thứ hai |
| Người dùng tự nhập? | không vào `photo_metadata` — recipe là dữ liệu sửa ảnh, đi đường lưu recipe như hôm nay ([FS-03.06](06-saving-recipe-and-live-photo.md)) |
| Tương thích | app chưa phát hành: không migration, không cờ phiên bản; decode vẫn khoan dung (FS-03.11 §9b) |
| Copy / Sync / My Looks | ba mức độ mạnh và công tắc **đi theo** look (tự chép vì nằm trong bộ thông số chỉnh); nguồn đã giải **không** — mỗi ảnh tự giải ống của nó |
| Sync "Everything" | cũng giữ lựa chọn hồ sơ ống của từng ảnh, chỉ chép ba mức độ mạnh (và công tắc). *Vì ảnh B có thể chụp ống khác — chép hồ sơ của A là sửa méo sai* |

## 5. Preset Lightroom (FS-03.14 đổ vào đây)

| Thẻ `crs:` | Vào đâu |
|---|---|
| `LensProfileEnable` | công tắc chung |
| `LensProfileSetup` = Auto | bỏ qua tên, mỗi ảnh tự giải theo §3 |
| `LensProfileSetup` = Custom + `LensProfileName` | bỏ tiền tố "Adobe (…)", tên còn lại qua bộ khớp hiện có (khớp theo dải tiêu cự + khẩu độ rồi token tên) |
| `LensProfileDistortionScale` · `…VignettingScale` · `…ChromaticAberrationScale` | ba slider, 1:1 (0–200) |

- Tên không khớp dòng nào: giữ ba mức, ảnh tự giải theo §3, báo cáo import ghi một dòng ≈ nêu tên ống.
- Xuất `.xmp`: ghi `Enable` + `Setup = Auto` + ba mức; không ghi tên ống (FS-03.14).

## 6. Ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Preview | không hạ độ phân giải khi kéo ([FS-03.04](04-raw-and-render-graph.md)); pass mới chạy GPU, kernel Metal theo [FS-16](../FS-16-metal-kernels.md) |
| Kit | bộ đọc dữ liệu nhúng và bảng nằm trong kit, không SwiftUI/GRDB ([EX-01](../../03-extensions-and-integrations/EX-01-shotdexkit-and-edit-extension.md)) |
| Bộ nhớ | không có trần riêng cho extension: hôm nay không extension nào render recipe (D60, [EX-01](../../03-extensions-and-integrations/EX-01-shotdexkit-and-edit-extension.md)); ngày có extension render thì đo lại cả bảng ống kính |
| Dung lượng | bảng là JSON thô, trần 4MB (16b §4); hôm nay 823KB, thêm tối góc + CA ước 1–2MB, **chưa đo** |
| Pháp lý | bộ đọc tự viết từ mô tả định dạng; không chép mã GPL (darktable, RawTherapee) |

## 7. Tiêu chí nghiệm thu chung

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | recipe có Distortion 150 · Vignetting 0 · CA 200, nguồn Lensfun id "Canon\|Canon EF 24-70mm f/2.8L II USM\|1.0" | encode rồi decode | cả ba mức, công tắc và nguồn giống hệt; thêm một loại nguồn lạ vào JSON thì chỉ nguồn rơi về "không sửa", ba mức và mọi phần khác còn nguyên | `LensProfileTests.strengthsSourceAndSwitchRoundTrip` · `…unknownSourceFallsToNoneOnly` |
| AC-2 | ảnh có Distortion 100 | kéo lên 160 rồi thả | đúng **một** bước history; Undo trả 100 và ảnh render lệch ≤ 1/255 so với trước khi kéo | ⚠️ chưa có |
| AC-3 | ảnh A (ARW, nguồn dữ liệu nhúng, 50/100/150) và ảnh B (CR3, nguồn Lensfun ống của B) | Copy Edits ở A, Paste lên B | B nhận 50/100/150, **giữ** nguồn Lensfun ống của B, không nhận nguồn của A | ⚠️ chưa có |
| AC-4 | `.xmp` có Enable 1, Setup Custom, Name "Adobe (Canon EF 24-70mm f/2.8L II USM)", ba mức 80/120/100 | nhập và áp lên CR3 chụp bằng ống đó | công tắc bật, ống là dòng Lensfun cùng tên, ba slider 80/120/100, báo cáo ghi ✓ | ⚠️ chưa có |
| AC-5 | `.xmp` như AC-4 nhưng Name "Adobe (Foo 13mm f/1.1)" | nhập và áp lên cùng CR3 | ba mức 80/120/100 giữ nguyên, nguồn tự giải theo §3, báo cáo có một dòng ≈ nêu "Foo 13mm f/1.1", không crash | ⚠️ chưa có |
| AC-6 | recipe trỏ tới id ống không còn trong bảng (sau một lần làm mới) | mở ảnh trong editor | render không có bước sửa theo hồ sơ, không crash; panel hiện "No profile for this lens yet" + Choose Lens | ⚠️ chưa có |
| AC-7 | RAW nguồn 3 (phần sửa của Apple) và JPEG nguồn 2, cùng recipe | tắt công tắc Lens Correction | cả hai ảnh mất sửa ống kính; danh mục thông số không còn thang RAW riêng nào điều khiển phần của Apple | ⚠️ chưa có |

**Chưa chứng minh được:** AC-1 → AC-7 (chưa có code). AC của từng phần ở 16a §7 và 16b §5.

## 8. Đã chốt 2026-09-28 — lý do ở [DECISIONS.md](../../../.planboard/editor-specs-decisions/DECISIONS.md)

- **D71** Ba mức + công tắc vào bộ thông số chỉnh, hồ sơ thêm loại nguồn, bỏ thang RAW cũ (§4).
- **D72** v1 đọc cả năm định dạng nhúng: DNG, Sony, Fujifilm, Panasonic, OM (16a §1).
- **D73** CA theo hồ sơ dùng kernel mới, gộp với méo trong một pass (16a §5).
- **D74** Bảng Lensfun là JSON thô, trần 4MB; vượt trần thì chuyển sang nén trong bundle (16b §4).
- **D75** JPEG đã sửa trong máy: đọc thẻ trạng thái, không tự khớp, nói rõ lý do (16a §4, 16b §2).
- **D76** Giữ chip Remove CA, là sửa CA không cần hồ sơ (16a §5).
- **D77** Ống người dùng chọn thắng dữ liệu nhúng, có lối quay về dữ liệu trong ảnh (16b §2).

Chốt thêm khi đối chiếu kế hoạch với code — lý do ở
[.planboard/plans-deviations/DECISIONS.md](../../../.planboard/plans-deviations/DECISIONS.md):

- **E14** Hai cặp Distortion · Vignetting giữ tên, tách bằng nhãn nhóm LENS PROFILE / MANUAL (16b §1).
- **E16** Không có tiêu chí bộ nhớ extension (§6).
- **E17** Bù tối góc RAW khi kéo dùng bản giải mã tuyến tính half-float đã cache (16a §5).
- **E18** Sync "Everything" giữ hồ sơ ống của từng ảnh (§4).
- **E19** RAW vừa mở ghi nguồn vào recipe ở lần chỉnh đầu tiên (§3).

## 9. Rủi ro và câu hỏi còn treo

| Rủi ro | Xử lý |
|---|---|
| Không có file RAW mẫu trong repo (0 file ARW/RAF/RW2/ORF/DNG/CR3 trong target test) | fixture là **khối maker notes / opcode đã tách** (vài KB) cho test đơn vị; RAW đầy đủ CC0 để ngoài repo, chỉ cho spike |
| Golden của kernel nắn méo (FS-16) đổi khi gộp CA vào cùng pass | ghi lại golden theo luật FS-16, một commit riêng |

1. **Định dạng nhúng từng hãng** đọc ổn định không, quy về cùng một dạng bảng không → spike với RAW thật
   của từng hãng là bước kiểm, không cắt phạm vi; nguồn 2–4 làm trước được.
2. **Lightroom có ưu tiên dữ liệu nhúng** với máy mirrorless không, và có cho tắt không → agent
   `lightroom-parity`, kiểm trước `/plan`, để AC-4 khớp hành vi Lightroom.
3. **Dung lượng thật** của JSON khi thêm tối góc + CA → đo khi chạy script, so với trần 4MB (16b §4).
4. **Câu chữ** cho JPEG đã sửa trong máy và dòng quay về dữ liệu trong ảnh (16b §2) → chốt ở lượt
   `copy-consistency` trước `/plan`.
