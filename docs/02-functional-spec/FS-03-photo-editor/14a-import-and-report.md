# FS-03.14a — Nhập preset và báo cáo

`FS-03.14a` · `ShotDex/Domain/Editing/` (bộ đọc preset — trong app, không vào `ShotDexKit`) ·
`ShotDexTests/LightroomXMPReaderTests.swift` · cập nhật 2026-09-28

**Một câu:** một lối Import nhận mọi định dạng preset người chụp đang có, và sau đó nói thật preset nào
sang được bao nhiêu. Tổng quan và các quyết định đã chốt: [FS-03.14](14-lightroom-preset-exchange.md).

## 1. Nhận định dạng nào

Lối vào: ô **"Import XMP Preset"** trong My Looks (chỗ đặt theo [FS-03.13](13-iphone-editor-layout.md)),
dưới nhãn một dòng "Import presets in XMP format from Adobe Lightroom." Ô mở Files, chọn **nhiều file** một lần.
Các đường nhận từ app khác ([14c §4](14c-export-share-receive.md#4-nhận)) đi cùng bộ nhập, khác chỗ hiện kết quả.

| File | Nhận ra bằng | Đọc gì | Đi đâu |
|---|---|---|---|
| `.xmp` | gói XMP có thẻ trong namespace `crs:` | thẻ chỉnh sửa, tên preset | My Looks, nhãn "Imported" |
| `.lrtemplate` | văn bản bảng Lua, khối `settings` | chỉ **hằng số** (chuỗi, số, true/false, bảng lồng) — **không bao giờ chạy Lua** | My Looks, "Imported" |
| DNG có preset | gói XMP trong file | chỉ metadata — **không giải mã pixel** | My Looks, "Imported" |
| `.shotdexlook` | định danh định dạng + schema version | đúng **một** look, kèm bảng LUT nhúng nếu có | My Looks, giữ nguồn ghi trong file |
| `.cube` | đuôi file | bộ đọc LUT sẵn có ([FS-03.11 §4](11-parity-with-lightroom.md#4-nhập-cube-lut-vào-editor-ảnh)) | tab LUTs |

- XMP sidecar của một ảnh đã sửa trong Lightroom **cũng là một preset**: nó được nhập như look, và phần
  crop/mask của nó rơi vào ✕ theo lát cắt look.
- **Không nhận zip.** Zip không nằm trong loại file Import cho chọn; Files tự giải nén khi chạm, rồi người
  dùng chọn nhiều file trong thư mục vừa giải nén.
- DNG **không** đăng ký làm loại file ShotDex mở từ Files: chạm một tấm DNG trong Files phải mở ảnh, không phải
  nhập preset. DNG preset chỉ vào qua ô Import.
- Mỗi look nhập từ `.xmp` / `.lrtemplate` / DNG giữ **bản chép byte-giống file gốc** cạnh nó (14b §5).

## 2. Giới hạn đọc

Kiểm **trước** khi đọc nội dung, bằng kích thước file hệ thống báo:

| Giới hạn | Trần | Vì |
|---|---|---|
| `.xmp` · `.lrtemplate` | ≤ **5 MB** mỗi file | preset thường vài KB; có RGBTable ~vài trăm KB |
| `.shotdexlook` | ≤ **16 MB** mỗi file | look nhúng LUT 64³ dạng chữ `.cube` ~6,5 MB |
| DNG | ≤ **200 MB**, chỉ đọc gói XMP | preset DNG của bản di động là cả tấm ảnh |
| `.cube` | theo bộ đọc sẵn có: **2…64** điểm mỗi cạnh | không viết bộ đọc thứ hai |
| một lượt nhập | ≤ **500** preset | báo cáo còn đọc được; phần vượt là ✕ "Import the rest separately" |
| XML | không DTD, không entity ngoài, lồng ≤ **64** tầng | chặn XXE và đệ quy |
| Lua | lồng ≤ **32** tầng; biểu thức không phải hằng số → cả preset ✕ | không có chỗ cho mã chạy được |

Bảng đo lại trên một bộ preset thật trước `/verify`; dòng nào lệch thì chỉnh số, không đổi cách kiểm.

## 3. Báo cáo

Nhập từ ô Import xong → sheet **báo cáo** (`[.medium, .large]`, [DESIGN.md §10.4](../../../DESIGN.md)).

- Dòng đầu: "**12 looks added · 2 skipped**".
- Mỗi preset một hàng: tên · trạng thái · chạm để mở danh sách dòng lý do của nó.

| Trạng thái preset | Khi |
|---|---|
| ✓ **Added** | mọi thẻ đọc được đều ✓ |
| ≈ **Added with changes** | có ít nhất một thẻ ≈ hoặc ✕, và ít nhất một thẻ đã áp |
| ✕ **Skipped** | file không đọc được, trùng cả tên lẫn nội dung, hoặc không thẻ nào thuộc về một look |

- Dòng lý do nói **cái gì** và **thay bằng gì**: "Exposure +3.00 is beyond ShotDex's ±2 EV — set to +2.00",
  "Crop stays with each photo". Bảng lý do theo từng thẻ: [14b](14b-lightroom-mapping.md).
- Thẻ quản trị của preset (Process Version, UUID, loại preset) được đọc nhưng **không** thành dòng báo cáo.
- Báo cáo **không lưu** lại sau khi đóng — look đã nhập mang nhãn nguồn, còn lý do chỉ cần lúc nhập.
- Lượt nhập dài: sheet hiện "Reading 120 of 500" + **Cancel**. Huỷ = **không thêm gì**: look chỉ ghi vào kho
  khi cả lượt xong, để Undo và Cancel cùng một nghĩa.

## 4. Tên, nhãn, trùng tên

- Tên look = tên preset trong file; không có (sidecar, khoá bản địa hoá `$$$/…`) → tên file bỏ đuôi.
  Trim, tối đa **60** ký tự.
- Nhãn **"Imported"** vẽ sau tên, màu chữ phụ của editor; là **nguồn** của look chứ không phải một phần tên:
  Rename không xoá nó, `.shotdexlook` mang nó theo. VoiceOver đọc "Imported".
- Nhóm preset của Lightroom **bị bỏ** — My Looks không có nhóm (FS-03.13: Save Current không chọn nhóm).
- Look mới nhập vào **đầu** danh sách, theo thứ tự file.
- **Trùng tên** (không phân biệt hoa thường) → thêm hậu tố như Rename (E8): "Golden (2)", đã có thì "(3)". Nhập **không bao giờ** ghi đè hay xoá
  look của người dùng — khác Save Current, vốn ghi đè ([FS-03.02 §9](02-film-simulation-and-presets.md#9-my-looks)).
- **Trùng cả tên lẫn nội dung** → ✕ "Already in My Looks"; không thêm look.

## 5. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-a1 | `.xmp` có `crs:Name`="Golden", `Exposure2012`=+0.50, `HueAdjustmentRed`=-20 | nhập qua ô Import XMP Preset | My Looks thêm "Golden" nhãn "Imported": Exposure +0.50 EV, Red Hue −20; báo cáo "1 look added", hàng ✓ | ⚠️ nửa Domain ✅ `LightroomXMPReaderTests.exposureAndRedHueMap` (+ `elementFormIsReadToo`, `aDoctypeIsRefusedBeforeParsing`); ô Import + `looks-import-report.json` ở task 23 |
| AC-a2 | `.lrtemplate` title "Matte", `Contrast2012` = -30, `Blacks2012` = 25 | nhập | "Matte" nhãn "Imported": Contrast −30, Blacks +25; ✓ | ✅ `LightroomTemplateReaderTests.readsSettingsAsData` (+ `functionCallsAreRejected`) |
| AC-a3 | DNG 25 MB của bản di động, XMP có `Vibrance`=+15 | nhập | look có Vibrance +15; bộ đếm giải mã ảnh của test = 0 | ✅ `PresetDNGReaderTests.readsXMPWithoutDecodingPixels` (file TIFF dựng trong test mang gói XMP; 0 lần giải mã) |
| AC-a4 | `.xmp` thiếu thẻ đóng ở dòng 14 | nhập | hàng ✕ "The file is not valid XMP. Try exporting the preset from Lightroom again."; số look không đổi | ✅ `LightroomXMPReaderTests.malformedXMLGivesNextStep` |
| AC-a5 | `.xmp` 50 MB | nhập | ✕ "Larger than 5 MB — not a preset" trước khi đọc nội dung; bộ nhớ tăng < 10 MB | ✅ `PresetImportLimitsTests.oversizedFileIsRefusedUnread` (file thưa 50 MB, từ chối từ kích thước hệ thống báo) |
| AC-a6 | 10 `.xmp` chọn cùng lúc, một file XML hỏng | nhập | 9 look thêm, 1 hàng ✕ mang tên file hỏng; dòng đầu "9 looks added · 1 skipped" | `PresetImportReportTests.oneBrokenPresetOnlyLosesItself` |
| AC-a7 | `.xmp` có `Exposure2012`=+1.00 và thẻ lạ `crs:FutureSlider`=40 | nhập | look thêm với Exposure +1.00; hàng ≈, dòng "Unknown setting FutureSlider — ignored" | ✅ `PresetImportReportTests.unknownTagsAreListedNotFatal` |
| AC-a8 | sidecar `.xmp` chỉ có thẻ EXIF/Dublin Core, không thẻ `crs:` | nhập | ✕ "This XMP has no Lightroom edit settings"; không thêm look | ✅ `LightroomXMPReaderTests.sidecarWithoutSettingsIsNotAPreset` |
| AC-a9 | My Looks đã có "Golden" (tự lưu) | nhập preset tên "golden", rồi nhập lại đúng file đó | lần đầu thêm "golden (2)" nhãn "Imported", "Golden" giữ nguyên nội dung; lần hai ✕ "Already in My Looks", số look không đổi | ✅ `LookPresetStoreTests.importNeverOverwritesAUserLook` |
| AC-a10 | chọn cùng lúc 2 `.xmp` và 1 `.cube` 33³ | nhập | My Looks +2, tab LUTs +1; báo cáo có dòng "Added to LUTs" | `PresetImportReportTests.cubeFilesGoToLUTs` |
| AC-a11 | lượt nhập 300 preset | chạm Cancel ở "Reading 120 of 300" | không look nào được thêm; My Looks như trước lượt nhập | `PresetImportTests.cancelAddsNothing` |
| AC-a12 | `Golden.xmp` 3 KB | nhập, rồi Delete look "Golden" | sau nhập: cạnh look có bản chép byte-giống file gốc; sau Delete: bản chép cũng mất | ✅ `LookPresetStoreTests.keepsOriginalPresetBesideLook` (+ `legacyLooksMoveIntoTheFileOnce`) |

**Chưa chứng minh được:** AC-a1…a12 (chưa có code).

## 6. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| `.lrtemplate` chứa lời gọi hàm / nối chuỗi | chỉ đọc hằng số; gặp biểu thức → ✕ cả preset (`LightroomTemplateReaderTests.functionCallsAreRejected`) |
| XMP có DTD / entity ngoài | từ chối trước khi phân tích; không mở URL nào trong file |
| Sidecar làm ShotDex thành app mở mọi `.xmp` trong Files | chấp nhận: sidecar có `crs:` thì nhập được; không có thì ✕ rõ (AC-a8) |
