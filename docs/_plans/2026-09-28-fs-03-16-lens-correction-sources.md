# Kế hoạch — Nguồn sửa ống kính: ba mức độ mạnh, dữ liệu nhúng trước

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-03.16`](../02-functional-spec/FS-03-photo-editor/16-lens-correction-sources.md) + [16a](../02-functional-spec/FS-03-photo-editor/16a-correction-sources-and-render.md) + [16b](../02-functional-spec/FS-03-photo-editor/16b-optics-panel-and-data-refresh.md) — 36 AC |
| Intent | [2026-09-27-lens-correction-sources](../_intents/2026-09-27-lens-correction-sources.md) |
| Quyết định | D71–D77, [DECISIONS.md](../../.planboard/editor-specs-decisions/DECISIONS.md) |
| Quyết định lệch | `.planboard/plans-deviations/DECISIONS.md` — E14, E16–E19 |
| Ngày | 2026-09-28 |
| Trạng thái | **nháp — chờ duyệt**, 38 task (36 AC + 2 lệch ngoài AC: E18, E19); mọi câu §1d đã chốt |

## 1. Hiểu đúng chưa

Hôm nay JPEG/HEIC sửa **chỉ méo** theo Lensfun khi người dùng bật tay, RAW chỉ bật/tắt phần sửa có sẵn của
`CIRAWFilter` qua một thang 0–1 ở nhóm RAW. Việc cần làm: một luật chọn nguồn **theo từng mặt** (méo · tối góc ·
CA) cho cả RAW lẫn JPEG — dữ liệu hãng nhúng trong RAW (DNG, Sony, Fuji, Panasonic, OM) → Lensfun bù mặt thiếu →
phần của Apple chỉ khi **không mặt nào** có nguồn 1/2 → không sửa; không bao giờ sửa hai lần. Ba slider 0–200 +
**một** công tắc nằm trong bộ thông số chỉnh (đi theo Copy/Sync/Look); nguồn đã giải nằm trong lựa chọn hồ sơ
(không đi theo). Lensfun thêm tối góc (`pa`) + CA (`linear`/`poly3`), bảng ≤ 4MB, làm mới mỗi bản phát hành qua
`/release-check`. Panel Optics đổi chữ, không còn chữ "Lensfun" ngoài Acknowledgements.

Tóm tắt khớp đặc tả. Không trôi sang FS-03.15 (hai slider chỉnh tay) hay FS-03.14 (bộ nhập preset — ở đây chỉ làm
hàm đổi thẻ `crs:` → trường ống kính, xem T27–T28).

**Quy ước xếp loại trong bảng dưới:** ⚠️ chỉ dùng khi code và tài liệu nói hai điều khác nhau **mà tài liệu chưa
chốt bên nào đúng**. Chỗ code lệch nhưng spec đã ghi rõ phải thay (ví dụ chữ "Found from EXIF", panel:58) xếp ❌ —
đã quyết rồi, không hỏi lại. AC đạt một phần ghi "❌ (một phần ✅)" và tính là ❌.

### 1a. Đối chiếu AC ↔ code — FS-03.16 (chung)

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 mã hoá/giải mã ba mức + nguồn; nguồn lạ → chỉ nguồn rơi về "không sửa" | ❌ | `PhotoAdjustments` không có trường độ mạnh (`ShotDexKit/Models/PhotoEditingModels.swift:569-722`); `PhotoLensProfileChoice` chỉ `lensID/cameraCropFactor/isAutomatic` (`ShotDexKit/Models/PhotoLensProfileChoice.swift:7-19`); giải mã `try?` cả khối (`PhotoEditingModels.swift:1304`) — nguồn lạ làm mất cả lựa chọn | 3 kind mới `lensDistortionScale/lensVignettingScale/lensChromaticAberrationScale` (0…2, mặc định 1) + `lensCorrection` thành công tắc chung; `PhotoLensProfileChoice` thêm nguồn từng mặt + dự phòng; decode từng trường khoan dung (nguồn lạ → `.none`) |
| AC-2 kéo Distortion = một bước history | ❌ (cơ chế có sẵn) | `setAdjustment` chỉ `recordHistory()` khi không phải kéo liên tục (`ShotDex/Features/Editing/PhotoEditorController.swift:579-583`) — tự đạt khi Distortion là một `PhotoAdjustmentKind` | thêm kind (T2), test mức controller (chưa có test controller nào cho history — `EditorHistoryAndSummaryTests` chỉ test `PhotoEditHistory`) |
| AC-3 Paste giữ nguồn của B | ❌ (cơ chế có sẵn) | `EditClipboard.paste` chép `adjustments`, không đụng `lensProfile` (`ShotDex/Domain/Editing/EditClipboard.swift:49-58`); My Looks cắt qua `EditorSyncScope.look` (`LookPresetStore.swift:20,66`) | tự đạt khi ba mức nằm trong `adjustments` → chỉ viết test. **Lệch ngoài AC** (Sync "everything" chép cả `lensProfile`): chốt E18, task T9 |
| AC-4 `.xmp` Custom + tên khớp | ❌ | chưa có bộ nhập preset Lightroom nào (`grep crs:` = 0 kết quả; intent FS-03.14 "chưa làm") | hàm thuần `LightroomLensProfileMapping` trong Domain (bỏ tiền tố "Adobe (…)", qua `LensProfileMatcher`), test độc lập; FS-03.14 gọi nó |
| AC-5 `.xmp` tên không khớp | ❌ | như AC-4 | cùng hàm, trả dòng báo cáo ≈ |
| AC-6 id ống không còn trong bảng | ❌ (một phần ✅) | render: `guard … let lens = LensProfileLibrary.shared.lens(id:)` trả ảnh gốc, không crash (`ShotDexKit/Render/PhotoRenderService.swift:1854-1857`) ✅. Panel: khi còn `lensProfileMatch` thì hiện tên ống khớp, không phải "No profile…" (`EditorLensProfileSection.swift:57-64`) | test khoá phần render; panel dùng trạng thái của resolver |
| AC-7 một công tắc tắt cả nguồn 2 và 3; không còn thang RAW | ❌ | thang RAW `lensCorrection >= 0.5` (`PhotoRenderService.swift:1151-1153`), hàng "Lens" trong nhóm RAW (`ShotDex/Domain/Editing/EditorAdjustmentCatalog.swift:191,245`), `isRAWOnly`/`affectsRAWDemosaic` (`PhotoEditingModels.swift:554-566`); JPEG bật/tắt bằng có/không `lensProfile` (`PhotoEditorController.swift:1149-1161`) | công tắc chung điều khiển bảng §6 16a; bỏ hàng RAW (D71) |

### 1b. Đối chiếu — 16a (nguồn và render)

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-a1 Sony ARW nhúng → nguồn 1, dịch góc ±0,5px | ❌ | không có bộ đọc hiệu chỉnh nào; `MakerNoteParser` chỉ đọc bộ đếm màn trập (`ShotDex/Domain/Metadata/MakerNoteParser.swift:23-50`), có sẵn bảng giải mã Sony (`:161`) và `TIFFReader` (`:256`) | chuyển `TIFFReader`/`IFDEntry` xuống kit, bộ đọc Sony |
| AC-a2 DNG `WarpRectilinear` đỏ ≠ lam | ❌ | không đọc OpcodeList; kernel hôm nay là `CIWarpKernel` một toạ độ cho cả ba kênh (`ShotDexKit/Render/Kernels/OpticsKernels.ci.metal:23-36`) | bộ đọc DNG opcode + kernel mới (T12) |
| AC-a3 CR3 + Lensfun → nguồn 2, Apple tắt, gain `pa` ±1/255 | ❌ | Lensfun bị bỏ qua khi RAW (`PhotoRenderService.swift:1854` `!source.isRAW`; `PhotoEditorController.swift:1130` `guard !info.isRAW`); JSON không có tối góc (`Tools/lensfun-to-json.py:22-36` chỉ `<distortion>`); không dùng `linearSpaceFilter` ở đâu cả | khớp cho RAW, tắt Apple khi nguồn 1/2, gain qua `linearSpaceFilter` |
| AC-a4 ARW cắt cụt → không crash, rơi 2 hoặc 3 | ❌ | — (có tiền lệ kiểm biên trong `TIFFReader.ifd` `MakerNoteParser.swift:292-310`) | kiểm độ dài + ngưỡng tin được 16a §1 |
| AC-a5 PEF, không Lensfun, bộ giải hỗ trợ → nguồn 3; slider không đổi ảnh | ❌ | `raw.isLensCorrectionSupported` đọc thẳng từ `CIRAWFilter` (`PhotoRenderService.swift:1151`) — không có seam để giả lập trong test, repo không có PEF | resolver nhận `decoderSupportsLensCorrection: Bool` làm đầu vào (seam), render theo nguồn đã lưu |
| AC-a6 bộ giải không hỗ trợ → nguồn 4 | ❌ | như trên | cùng resolver |
| AC-a7 ba mức = 0 → như tắt, zoom 1,0 | ❌ | `fillZoom` không có độ mạnh (`LensProfileLibrary.swift:239-249`) | công thức độ mạnh 16a §5 |
| AC-a8 ba mức = 200 → 2× dịch, gain², 2× CA | ❌ | như trên | cùng |
| AC-a9 tỉ số góc/tâm tuyến tính 1,00 ± 0,01 ở Exposure 0 và +1 | ❌ (chốt E17) | spec đòi gain ở khe tuyến tính của `CIRAWFilter` **và** "không hạ độ phân giải khi kéo" (FS-03.16 §6). Code: mọi tham số RAW-demosaic khi kéo rơi xuống `rawDemosaicEdge` và bỏ cache nền (`PhotoEditorController.swift:2163-2168, 2216, 2311-2313`; chữ ký cache `PhotoRenderService.swift:75-83, 942-945`) — nên kéo Vignetting trên RAW sẽ giải mã lại RAW mỗi khung ở độ phân giải nháp. Cache nền lại là RGBA8 **sau** đường cong tone của bộ giải (`:966-972`), nên đặt gain sau cache thì AC-a9 hỏng | chốt E17: giữ sẵn bản giải mã tuyến tính half-float (trước tone) trong cache nền RAW; kéo Vignetting chỉ nhân gain lên bản đó — không giải mã lại, không hạ độ phân giải; bộ nhớ cache ~2× (T18) |
| AC-a10 crop 1,0 trên thân 1,53 ✓; ống crop 1,53 trên FF không tự khớp | ❌ (một phần ✅) | chuẩn hoá bán kính đúng, có test (`LensProfileLibrary.swift:177-186`; `ShotDexTests/LensProfileTests.swift:106-129`) ✅; bộ khớp **không xét crop** (`ShotDex/Domain/Editing/LensProfileMatcher.swift:119-154`) | lọc `lens.cropFactor > cameraCrop + 0.05` khi tự khớp; mở rộng test cho tối góc/CA |
| AC-a11 HEIC iPhone → nguồn 4 | ❌ (hành vi hiển thị đã đúng) | JPEG/HEIC mặc định không có `lensProfile` → render không bước ống kính (`PhotoRenderService.swift:1854`); nhưng chưa có khái niệm "nguồn" để khẳng định | resolver trả `.none` |
| AC-a12 Fuji RAF | ❌ | `fujiCount` chỉ đọc tag `0x1438` (`MakerNoteParser.swift:122-139`) | bộ đọc Fuji |
| AC-a13 Panasonic RW2 méo nhúng + tối góc Lensfun | ❌ | — | bộ đọc Panasonic + chọn nguồn từng mặt |
| AC-a14 OM ORF | ❌ | — | bộ đọc OM |
| AC-a15 JPEG Sony "đã sửa trong máy" → không tự khớp | ❌ | JPEG không tự khớp lúc mở nhưng bật công tắc thì dùng ngay ống khớp (`PhotoEditorController.swift:1149-1156`); không đọc thẻ trạng thái; có sẵn `jpegTIFFBase` (`MakerNoteParser.swift:214`) | đọc thẻ, resolver chặn tự khớp |
| AC-a16 JPEG thẻ "chưa sửa" → tự khớp | ❌ | — | cùng bộ đọc thẻ |
| AC-a17 chip Remove CA còn và đổi ảnh ở CA 0 lẫn 200 | ❌ (một phần ✅) | chip có, luôn hiện trong Optics (`EditorAdjustmentCatalog.swift:162-164`), render `CINoiseReduction` khi ≥ 0,5 (`PhotoRenderService+Optics.swift:70-81`) ✅; slider CA theo hồ sơ chưa có | test đi cùng T12 |
| AC-a18 méo + CA **một** pass, ≤ 8ms/khung | ❌ + ❓ | kernel gộp chưa có; 8ms không đo được trước khi có kernel | test đếm pass trong đồ thị CI; ms đo ở `/verify` |

### 1c. Đối chiếu — 16b (panel và làm mới dữ liệu)

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-b1 ARW Sony nhúng: "FE 24-70mm F2.8 GM II · Found from photo info", hàng 40pt | ❌ | RAW chỉ có dòng ghi chú (`ShotDex/Features/Editing/EditorLensProfileSection.swift:16-17`) | panel mới; cần RAW không mặt người trong thư viện sim |
| AC-b2 JPEG D800E "… · Found from photo info" | ❌ (tự khớp ✅) | tự khớp có test (`LensProfileTests.swift:29-47`); chữ hôm nay "Found from EXIF" (`EditorLensProfileSection.swift:58`) — spec đã ghi phải thay | đổi chữ + ba slider |
| AC-b3 Change → "Chosen by you", một Undo về tự tìm | ❌ (một phần ✅) | `chooseLensProfile` ghi một bước (`PhotoEditorController.swift:1164-1172`) ✅, chữ "Chosen by you" đã có (`:58`) | nguồn = `.lensfun` + `isAutomatic=false`; test controller |
| AC-b4 nguồn 3: hai dòng chữ, slider mờ, VoiceOver | ❌ | — | trạng thái mới |
| AC-b5 D90 "No profile for this lens yet" + Choose Lens | ❌ (một phần ✅) | nút mở picker có (`EditorLensProfileSection.swift:37-39`) ✅; chữ còn đuôi "Choose yours from the list." (`:64`) — spec ghi thay | đổi chữ |
| AC-b6 không chuỗi "Lensfun"; nhóm RAW hết hàng ống kính; một công tắc; Acknowledgements còn | ❌ (một phần ✅) | chân picker "Lens profiles from the Lensfun database" (`EditorLensProfileSection.swift:116`); toggle "Lens Profile" (`:20`); "Lens" ở nhóm RAW (`EditorAdjustmentCatalog.swift:191`). Acknowledgements đúng (`ShotDex/Features/Settings/SettingsScreen.swift:819-839`) ✅ | bỏ chân picker, một toggle "Lens Correction" |
| AC-b7 bước làm mới in trước → sau, ghi commit; thư mục rỗng → fail | ❌ | script không in so sánh, không ghi commit/ngày (`Tools/lensfun-to-json.py:78-85`), thư mục rỗng vẫn ghi JSON rỗng; JSON hiện chỉ có `source`/`license` (1527 ống, 1054 thân) | script `--previous` + fail có điều kiện |
| AC-b8 JSON > 4MB → fail, repo không đổi | ❌ | không có trần; `/release-check` không có bước ống kính (`.claude/skills/release-check/SKILL.md` §1–6) | trần trong script + bước mới trong skill |
| AC-b9 "Use Lens Data Found in Photo" quay về nguồn 1 | ❌ | — | dòng đầu picker khi có nguồn 1 |
| AC-b10 "Already corrected in camera" | ❌ | — | trạng thái mới |
| AC-b11 không có dòng quay về khi không có dữ liệu nhúng | ❌ | — | cùng T37 |

**Tổng: ✅ 0 · ⚠️ 0 · ❌ 35 · ❓ 1 (AC-a18, phần 8ms) — 36 AC.** AC-6 cũ (bộ nhớ extension) bỏ theo E16; AC-7/AC-8 cũ
đổi số thành AC-6/AC-7 trong spec. AC-a9 hết ⚠️ theo E17. Sáu AC đạt một phần (AC-6, a10, a17, b3, b5,
b6) và ba AC có sẵn cơ chế, chỉ thiếu trường (AC-2, AC-3, a11).

### 1d. Đã chốt — quyết định lệch

Quyết định lệch: `.planboard/plans-deviations/DECISIONS.md`.

| # | Chỗ lệch | Chốt | Task |
|---|---|---|---|
| E16 | AC-6 đo bộ nhớ "trong tiến trình extension chia sẻ", nhưng không extension nào link kit (`project.pbxproj:222-233`), và bảng giải mã cả khối đã ~12–24MB | **bỏ AC-6** khỏi spec; không task, không test bộ nhớ extension. D60 vẫn đúng: ngày có extension render thì đo lại | — (T15 cũ bỏ) |
| E17 | AC-a9: gain ở `linearSpaceFilter` làm kéo Vignetting RAW giải mã lại mỗi khung ở `rawDemosaicEdge` | giữ sẵn bản giải mã tuyến tính half-float; kéo chỉ nhân gain; cache nền RAW ~2× bộ nhớ | T18 |
| E18 | Sync "everything" trả nguyên recipe nguồn (`EditClipboard.swift:95-98`), ảnh B nhận `lensProfile` của A | theo spec: mỗi ảnh giữ hồ sơ ống của nó, chỉ chép ba mức độ mạnh (và công tắc) | T9 |
| E19 | RAW mặc định bật; ghi `lensProfile` lúc mở làm `isIdentity` false (`PhotoEditingModels.swift:1234`) → mọi RAW vừa mở bị coi là "đã sửa" | giải nguồn lúc mở, giữ trong controller (như `lensProfileMatch` hôm nay); ghi vào recipe ở lần chỉnh đầu tiên | T16 |
| E14 | hai cặp "Distortion · Vignetting" (profile 0–200 và chỉnh tay ±100 của FS-03.15) cùng panel | giữ tên, tách bằng nhãn nhóm LENS PROFILE / MANUAL; VoiceOver đọc kèm tên nhóm (16b §1) | T29, T36 |

## 2. Tái dùng — không viết cái thứ hai

| Có sẵn | Ở đâu | Dùng cho |
|---|---|---|
| `LensProfileMatcher` (dải tiêu cự + khẩu độ → ngàm → hãng → token) | `ShotDex/Domain/Editing/LensProfileMatcher.swift:112-178` | tự khớp RAW (T17), lọc crop (T11), tên `LensProfileName` preset (T27). **Ở lại app** — renderer chỉ tra id (extension-boundary) |
| `lensNormalizationRadius` (khung hiệu chuẩn, đường chéo mm) | `LensProfileLibrary.swift:177-186` | cả ba mặt của nguồn 2; nguồn 1 dùng khung cảm biến của file (16a §5) |
| `fillZoom` (lặp tới khi góc không lấy mẫu ngoài ảnh, trần 1,5×) | `LensProfileLibrary.swift:239-249` | nhận thêm độ mạnh s; giữ trần |
| nội suy theo tiêu cự | `LensfunLens.distortion(atFocal:)` `LensProfileLibrary.swift:83-109` | mẫu cho TCA; tối góc nội suy 2 chiều (tiêu cự × khẩu độ) |
| công thức poly3/poly5/ptlens | `LensDistortionTerm.scale(at:)` `:34-45` + kernel `OpticsKernels.ci.metal:23-36` | lấy mẫu vào bảng dạng chung |
| `TIFFReader`, `IFDEntry`, `tiffBase`, `jpegTIFFBase`, bảng giải mã Sony `(b³ % 249)` | `MakerNoteParser.swift:161-356` | **chuyển xuống kit** (16a §1); `MakerNoteParser` (bộ đếm màn trập) import lại từ kit |
| mẫu fixture byte tự dựng | `ShotDexTests/MakerNoteParserTests.swift` (`le16/le32/be16/be32/entry`) | fixture khối maker notes / opcode DNG — không cần RAW thật |
| harness golden + bộ đánh dấu `build/record-kernel-golden` | `ShotDexTests/KernelGoldenSupport.swift:16-64`, `KernelGoldenTests.swift:139-170` | kernel mới; ghi lại golden `lensWarp*` một commit riêng |
| `EditClipboard` / `EditorSyncScope.look` | `EditClipboard.swift:41-109` | AC-3 tự đạt; nhánh `.everything` sửa ở T9 (E18) |
| picker ống (tìm, "Fits ‹ngàm›") | `EditorLensProfileSection.swift:79-174` | giữ; thêm dòng "Use Lens Data Found in Photo", bỏ chân ghi công |
| `EditorToggleRow`, `EditorTextButtonStyle`, `EditorTheme.dimText/secondaryText` | `EditorLensProfileSection.swift:19-41` | hàng công tắc + trạng thái — không token mới (16b §1) |
| script ui-drive Optics | `ShotDexUITests/scripts/ipad-optics-lens-{0,3,186}.json` | mẫu cho AC-b* |

## 3. Chỗ nào trong code

| Tầng | File | Đụng gì | Mới / sửa |
|---|---|---|---|
| Tool | `Tools/lensfun-to-json.py` | giữ `<vignetting model="pa">`, `<tca model="linear"/"poly3">`, ống chỉ có tối góc/CA; ghi `lensfunCommit`/`lensfunDate`; `--previous` in dòng so sánh + id biến mất; fail khi rỗng / giảm > 1% / > 4MB | sửa |
| Kit · dữ liệu | `ShotDexKit/Resources/lensfun-distortion.json` → đổi tên `lensfun-profiles.json` | tái tạo; một commit riêng | sửa |
| Kit · model | `ShotDexKit/Models/PhotoEditingModels.swift` | 3 kind độ mạnh; `lensCorrection` hết `isRAWOnly`/`affectsRAWDemosaic`; `isIdentity` bỏ qua mặc định 1 | sửa |
| Kit · model | `ShotDexKit/Models/PhotoLensProfileChoice.swift` | `LensCorrectionSource` (`embedded/lensfun/appleBuiltIn/none`) cho từng mặt, `lensID` tuỳ chọn, decode khoan dung | sửa |
| Kit · render | `ShotDexKit/Render/LensProfileLibrary.swift` | `LensVignettingTerm`, `LensTCATerm`, nội suy | sửa |
| Kit · render | `ShotDexKit/Render/LensCorrection/LensCorrectionProfile.swift` | dạng chung: bảng theo bán kính (méo, gain, tỉ lệ đỏ/lam); `strength(s)`; lấy mẫu từ Lensfun / DNG / hãng; ngưỡng tin được | mới |
| Kit · render | `ShotDexKit/Render/LensCorrection/TIFFReader.swift` | chuyển từ app, `public` | mới (chuyển) |
| Kit · render | `ShotDexKit/Render/LensCorrection/EmbeddedLensData{DNG,Sony,Fujifilm,Panasonic,OM}.swift` | đọc khối → `LensCorrectionProfile` từng mặt; thẻ trạng thái JPEG | mới |
| Kit · render | `ShotDexKit/Render/LensCorrection/EmbeddedLensDataCache.swift` | đọc byte gốc một lần mỗi URL, giới hạn số mục | mới |
| Kit · render | `ShotDexKit/Render/Kernels/OpticsKernels.ci.metal` | `lensCorrect` (CIKernel lấy mẫu R/G/B ở ba bán kính từ bảng 1D) + `lensVignette` (color kernel) | sửa |
| Kit · render | `ShotDexKit/Render/PhotoRenderService.swift` | `applyLensProfile(of:)` theo nguồn đã lưu (bỏ `!source.isRAW`); `makeBaseImage`: `isLensCorrectionEnabled = switch && fallback == .appleBuiltIn`, `linearSpaceFilter` gain; JPEG gain đầu pipeline; chữ ký cache | sửa |
| Domain | `ShotDex/Domain/Editing/LensCorrectionResolver.swift` | luật §3 thuần: đầu vào (isRAW, dữ liệu nhúng từng mặt, khớp Lensfun từng mặt, bộ giải hỗ trợ?, thẻ JPEG, lựa chọn tay) → nguồn từng mặt + trạng thái panel | mới |
| Domain | `ShotDex/Domain/Editing/LensProfileMatcher.swift` | lọc crop khi tự khớp | sửa |
| Domain | `ShotDex/Domain/Editing/LightroomLensProfileMapping.swift` | `crs:LensProfile*` → công tắc, ba mức, lựa chọn ống, dòng báo cáo | mới |
| Domain | `ShotDex/Domain/Metadata/MakerNoteParser.swift` | dùng `TIFFReader` từ kit | sửa |
| Domain | `ShotDex/Domain/Editing/EditorAdjustmentCatalog.swift` | Optics = công tắc + 3 slider + Remove CA/Defringe; bỏ `.lensCorrection` khỏi nhóm RAW; nhãn | sửa |
| Features | `ShotDex/Features/Editing/PhotoEditorController.swift` | chạy resolver cho RAW lẫn JPEG, đọc dữ liệu nhúng off-main, `setLensCorrectionEnabled`, `chooseLensProfile`, `useEmbeddedLensData` | sửa |
| Features | `ShotDex/Features/Editing/EditorLensProfileSection.swift` | 5 hàng 16b §1, chữ 16b §2, cắt giữa tên ống, VoiceOver slider mờ; picker bỏ chân, thêm dòng đầu | sửa |
| Features | `ShotDex/Resources/Localizable.xcstrings` | chữ mới | sửa |
| Skill | `.claude/skills/release-check/SKILL.md` | bước "Lens data refresh" (16b §4) → chạy `Tools/evals` | sửa |
| Test | `ShotDexTests/LensProfileTests.swift`, `LensCorrectionResolverTests.swift`, `LensEmbeddedDataTests.swift`, `LensCorrectionRenderTests.swift`, `LightroomLensProfileMappingTests.swift`, `PhotoEditorControllerLensTests.swift`, `EditorAdjustmentCatalogTests.swift`, `KernelGoldenTests.swift`, `Tools/tests/test_lensfun_to_json.py` | theo từng task | mới / sửa |
| UI test | `ShotDexUITests/scripts/optics-lens-*.json` | route từng trạng thái panel | mới |
| Tài liệu | `FS-03.16*` cột "Chứng minh bằng", `FS-03.11 §7`, `DESIGN.md` nếu đụng, `EX-01` (bảng Kit có gì) | mỗi task | sửa |

Logic nằm ở Domain (resolver, mapping, matcher) và Kit (dạng chung, bộ đọc, render) — View chỉ đọc trạng thái
resolver. Không có dữ liệu người dùng tự nhập mới: recipe đi đường lưu recipe hiện có, không đụng `photo_metadata`.

## 4. Thứ tự task

Mỗi task một commit (`feat(FS-03.16): AC-x …`), test đi kèm, `/build` sau mỗi commit, `/screens` khi đụng UI. Không
có ✅ trọn vẹn nên không có pha "chỉ viết test". Hai dòng ⚠️ cũ đã chốt: AC-6 bỏ (E16), AC-a9 theo E17
(T18). Hai lệch ngoài AC thành task riêng: E18 (T9), E19 (T16, mở đầu pha D).

**Cổng trước pha E — spike dữ liệu nhúng** (không commit code): với RAW thật CC0 từng hãng (để ngoài repo, không mặt
người — kiểm bằng Vision trước), xác nhận tag/offset ở 16a §1, tách khối maker notes / opcode vài KB làm fixture. Kết
quả ghi vào 16a §1 (cột "Nơi ghi") trước khi làm T19.

| # | Pha | Task | AC | Test kèm theo |
|---|---|---|---|---|
| 1 | A dữ liệu | Script: pa + TCA, ống không có méo, commit/ngày Lensfun, `--previous` in "Lens profiles a → b · vignetting … · TCA … · cameras … · KB", id biến mất, fail khi thư mục rỗng; tái tạo JSON (commit riêng), **đo dung lượng thật** so trần 4MB | AC-b7 | `Tools/tests/test_lensfun_to_json.py` (thư mục XML giả nhỏ; rỗng → mã lỗi ≠ 0, file đích không đổi); `LensProfileTests.tableCarriesVignettingAndTCA` |
| 2 | B recipe | 3 kind độ mạnh + công tắc chung; `PhotoLensProfileChoice` nguồn từng mặt; decode khoan dung | AC-1 | `LensProfileTests.strengthsSourceAndSwitchRoundTrip`, `unknownSourceFallsToNoneOnly` |
| 3 | B | `LensCorrectionResolver` khung + ca JPEG/HEIC không khớp | AC-a11 | `LensCorrectionResolverTests.iPhoneHEICResolvesToNone` + render so bản tắt ≤ 1/255 |
| 4 | B | nguồn 3: không 1/2, bộ giải hỗ trợ → Apple theo công tắc, pass ShotDex không chạy | AC-a5 | `…Resolver….unsupportedMakerWithDecoderSupportIsBuiltIn`; render ba slider 0 vs 200 lệch ≤ 1/255 (seam `decoderSupportsLensCorrection`) |
| 5 | B | nguồn 4 RAW: bộ giải không hỗ trợ | AC-a6 | `…noDecoderSupportIsNone` |
| 6 | B | một công tắc; bỏ hàng RAW; bảng §6 16a trong render | AC-7 | `EditorAdjustmentCatalogTests.rawGroupHasNoLensRow`, `LensCorrectionRenderTests.switchOffDisablesBuiltInAndProfile` (sửa `opticsAndGeoAreGlobalOnlyGroups`, `everyGroupedKindAppearsExactlyOnce`) |
| 7 | B | kéo Distortion = một bước history | AC-2 | `PhotoEditorControllerLensTests.distortionDragRecordsOneStep` (đi qua cùng begin/commit của slider) |
| 8 | B | Paste giữ nguồn của B | AC-3 | `EditClipboardTests.pasteCarriesStrengthsKeepsTargetLensSource` |
| 9 | B | chốt E18: Sync "Everything" giữ `lensProfile` của từng ảnh đích, chỉ chép ba mức độ mạnh (và công tắc) — sửa nhánh `.everything` của `EditorSyncScope.apply` (`EditClipboard.swift:95-98`) | lệch ngoài AC (FS-03.16 §4) | `EditClipboardTests.syncEverythingKeepsTargetLensProfile` |
| 10 | B | id ống biến mất → không bước sửa, panel "No profile…" | AC-6 | `LensCorrectionRenderTests.missingLensIDRendersUncorrected`, `…Resolver….staleLensIDIsNoProfile` |
| 11 | C Lensfun | lọc crop khi tự khớp; chuẩn hoá cho tối góc/CA | AC-a10 | mở rộng `normalizationFollowsTheCalibrationFrame`; `LensProfileTests.smallerSensorCalibrationIsNotAutoMatched` |
| 12 | C | kernel `lensCorrect` (méo + CA một pass, bảng 1D) + `lensVignette` JPEG đầu pipeline + công thức độ mạnh; golden `lensWarp*` ghi lại **commit riêng** (FS-16) | AC-a8 | `LensCorrectionRenderTests.twoHundredDoublesDisplacementSquaresGainDoublesCA` (ảnh tổng hợp, ±0,5px / ±1%); `KernelLibraryTests` thêm kernel |
| 13 | C | ba mức = 0 → như tắt, zoom 1,0 | AC-a7 | `…zeroStrengthsMatchSwitchOff` |
| 14 | C | một pass cho méo + CA | AC-a18 | `…distortionAndCAShareOnePass` (đếm kernel trong đồ thị); ≤ 8ms đo ở `/verify` trên iPhone 17 |
| 15 | C | chip Remove CA sống cùng slider CA | AC-a17 | `…removeCAChipChangesImageAtBothCAStrengths` + ảnh chụp Optics |
| 16 | D RAW | chốt E19: nguồn giải lúc mở RAW giữ trong controller (như `lensProfileMatch` hôm nay), render theo nó; ghi vào recipe ở lần chỉnh đầu tiên; RAW mở rồi đóng không chỉnh vẫn `isIdentity` (`PhotoEditingModels.swift:1234`), không hiện dấu, không hỏi lưu | lệch ngoài AC (FS-03.16 §3) | `PhotoEditorControllerLensTests.rawOpenedWithoutEditsStaysIdentity`, `…firstEditWritesResolvedSource` |
| 17 | D RAW | khớp Lensfun cho RAW; Apple tắt khi nguồn 1/2; gain qua `linearSpaceFilter`; resolver chạy lúc mở RAW, nguồn giữ trong phiên (T16, E19) | AC-a3 | `…Resolver….canonCR3WithLensfunIsProfileAppleOff` (mọi tổ hợp bảng §6); `LensCorrectionRenderTests.vignetteGainMatchesPAModel` (xám phẳng, 1/255) |
| 18 | D | chốt E17: cache nền RAW thêm bản giải mã tuyến tính half-float (trước tone); kéo Vignetting chỉ nhân gain lên bản đó, không giải mã lại, không hạ độ phân giải; chữ ký cache tách khỏi tham số demosaic | AC-a9 | `…vignetteRatioHoldsAcrossExposure` (0 và +1 EV, 1,00 ± 0,01); `…vignetteDragDoesNotRedecodeRAW` (đếm lần giải mã khi kéo = 0); đo footprint cache trước/sau (~2×) ghi vào NF-02 |
| 19 | E nhúng | chuyển `TIFFReader` xuống kit; bộ đọc DNG `WarpRectilinear` + `FixVignetteRadial` | AC-a2 | `LensEmbeddedDataTests.dngRedBlueCoefficientsGiveSeparateRadii` (opcode tự dựng); `MakerNoteParserTests` vẫn xanh |
| 20 | E | Sony ARW ba bộ thông số | AC-a1 | `…sonyThreeParamsDecodeWithinHalfPixel` (khối tách từ spike) |
| 21 | E | khối cắt cụt / ngoài ngưỡng tin được → coi như không có | AC-a4 | `…truncatedSonyBlockFallsBack` (có/không Lensfun) |
| 22 | E | Fujifilm RAF | AC-a12 | `…fujiThreeParams…` |
| 23 | E | Panasonic RW2 méo + bù tối góc từ Lensfun, mặt thiếu cả hai → mờ | AC-a13 | `…panasonicDistortionFillsRestFromLensfun` |
| 24 | E | OM ORF | AC-a14 | `…omDistortionFillsRestFromLensfun` |
| 25 | E | thẻ trạng thái JPEG Sony "đã sửa" → không tự khớp; chọn tay thì chạy | AC-a15 | `…sonyJPEGCorrectedInCameraSkipsAutoMatch` |
| 26 | E | thẻ "chưa sửa" → tự khớp | AC-a16 | `…uncorrectedTagMatchesAsUsual` |
| 27 | F preset | `LightroomLensProfileMapping`: Custom + tên khớp | AC-4 | `LightroomLensProfileMappingTests.customNameMatchesLensfunRow` |
| 28 | F | tên không khớp → giữ ba mức, dòng ≈ | AC-5 | `…unknownNameKeepsStrengthsAndReports` |
| 29 | G UI | panel 5 hàng + nhãn nhóm LENS PROFILE (16b §1, E14), toggle "Lens Correction" (cả `shortTitle` cho nhãn history), bỏ chân picker, bỏ hàng RAW | AC-b6 | `EditorStringsTests.noLensfunInEditorStrings` (quét catalog + nguồn Features/Editing); `EditorAdjustmentCatalogTests.profileSlidersSayTheirGroup` (nhãn VoiceOver "Distortion, Lens Profile"); ảnh Optics iPhone + iPad sidebar |
| 30 | G | "No profile for this lens yet" + Choose Lens | AC-b5 | ui-drive `optics-lens-none.json` (D90) |
| 31 | G | "… · Found from photo info" | AC-b2 | ui-drive `optics-lens-found.json` (D800E) |
| 32 | G | Change → "Chosen by you", một Undo | AC-b3 | `PhotoEditorControllerLensTests.chooseLensIsOneStep` + ui-drive |
| 33 | G | không dòng quay về khi không có nguồn 1 | AC-b11 | ui-drive dump picker |
| 34 | G | "Already corrected in camera" | AC-b10 | ui-drive (JPEG Sony có thẻ, không mặt người) |
| 35 | G | nguồn 3: hai dòng, slider mờ, VoiceOver không dùng được | AC-b4 | ui-drive dump (trait) + RAW nguồn 3 trong sim |
| 36 | G | ARW nhúng: trạng thái không cắt, hàng 40pt, slider dưới nhãn LENS PROFILE (E14) | AC-b1 | ui-drive dump khung trên iPhone 17 402×874 |
| 37 | G | "Use Lens Data Found in Photo" quay về nguồn 1, mỗi bước một history | AC-b9 | `PhotoEditorControllerLensTests.useEmbeddedDataRestoresSource` + ui-drive |
| 38 | H release | trần 4MB trong script + bước "Lens data refresh" trong `/release-check`; chạy `Tools/evals` | AC-b8 | `test_lensfun_to_json.py` (JSON giả > 4MB → fail, file đích không đổi) |

Ngoài bảng AC chỉ có hai task của quyết định lệch: T9 (E18) và T16 (E19). Việc đáng làm khác ngoài AC →
`REVIEW_QUEUE.md`.

## 5. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| **Không có RAW mẫu trong repo** (0 ARW/RAF/RW2/ORF/DNG/CR3/PEF) | chắc chắn | fixture = khối maker notes / opcode đã tách (vài KB) hoặc tự dựng theo đặc tả DNG công khai, theo mẫu `MakerNoteParserTests`; RAW đầy đủ CC0 để ngoài repo cho spike; **không ảnh có mặt người** (kiểm Vision trước khi nạp sim) |
| Định dạng nhúng một hãng không quy về dạng chung | trung bình | spike là cổng trước pha E; nguồn 2–4 làm trước; hãng nào hỏng thì dừng lại hỏi, không tự cắt khỏi v1 (D72) |
| **Sửa hai lần** (Apple + ShotDex, hoặc JPEG đã sửa trong máy) | trung bình | bảng §6 16a là một hàm thuần trong resolver, test mọi tổ hợp (T17); thẻ JPEG (T25); render đọc nguồn **đã lưu**, không tự chọn lại |
| JSON vượt 4MB khi thêm pa + TCA | thấp–trung bình (ước 1–2MB, chưa đo) | đo ở T1; vượt → nén trong bundle (D74), không cắt ống |
| **Bộ nhớ bảng**: giải mã cả bảng vào struct ≈ 3–6× byte JSON | trung bình | AC-6 bỏ (E16), nên không có task. Nếu `memory-leak` đo thấy app tăng đáng kể: nạp theo phần — chỉ mục (tên, ngàm, crop, id) một lần, hệ số giải theo id → `REVIEW_QUEUE.md` |
| **Churn golden**: `lensWarp*` đổi khi gộp CA | chắc chắn | ghi lại theo luật FS-16 (`build/record-kernel-golden`), một commit riêng trong T12; golden tổng ≤ 2MB |
| Hiệu năng: kéo Vignetting RAW giải mã lại mỗi khung | thấp (chốt E17) | T18 kéo chỉ nhân gain lên bản tuyến tính đã cache; test đếm lần giải mã khi kéo = 0; đo thời gian khung ở `/verify` |
| **Bộ nhớ cache nền RAW gấp ~2×** (half-float thay 8-bit, E17) | chắc chắn | chấp nhận. Chỉ giữ bản half-float khi ảnh là RAW có tối góc nguồn 1/2; đo footprint trước/sau ở T18, ghi NF-02; `memory-leak` rà sau T18 |
| Hiệu năng: kernel lấy mẫu đọc 3 toạ độ + ROI cả ảnh (`LensProfileLibrary.swift:217-221`) | trung bình | ROI theo dịch chuyển tối đa × zoom thay vì union cả extent; đích ≤ 8ms (AC-a18) |
| Đọc byte gốc mỗi lần render | trung bình | `EmbeddedLensDataCache` theo URL, đọc off-main lúc mở ảnh |
| Concurrency: resolver + đọc maker notes off-main ghi state `@Observable` | trung bình | giữ kiểu `Task.detached` + gán trên main như `resolveLensProfile` hôm nay (`PhotoEditorController.swift:1137-1145`); `swift-concurrency` rà |
| PhotoKit: ảnh đã sửa/xuất mất maker notes; Optimize Storage trả proxy | trung bình | chỉ đọc nguồn 1 khi nguồn là **file gốc**; proxy/không có byte → coi như không có nguồn 1 |
| Kit phình public: `TIFFReader` thành API công khai vĩnh viễn | chắc chắn | chấp nhận (16a §1 đã chốt dùng chung); `MakerNoteParser` app import từ kit |
| Thiết bị: Duo inner 669pt, panel 5 hàng = 200pt | thấp | Edit là danh sách cuộn (16b §1); chụp Duo inner ở T29 |
| ROI kernel mới: đệm cố định `insetBy(-8)` (`LensProfileLibrary.swift:220`) chỉ đủ cho méo; CA ở 200 lệch kênh xa hơn 8px ở góc | trung bình | đệm tính từ dịch chuyển tối đa của cả ba kênh × độ mạnh (perf-profiler) |
| 8ms đo sai chỗ: `CIContext` có `.cacheIntermediates: false` (`PhotoRenderService.swift:70-73`), cả đồ thị `render()` chạy lại mỗi khung | trung bình | AC-a18 đo **cả** `render()` ở cạnh tương tác, với ít nhất một mask, không đo kernel riêng |
| Giải mã bảng trên main: `lensProfileLens` tra `.shared` đồng bộ (`PhotoEditorController.swift:1124-1126`), và hôm nay RAW không chạm `.shared` off-main (`:1130`) | trung bình | resolver chạm bảng off-main cho **mọi** nguồn lúc mở ảnh, trước khi view đọc |
| Chữ: hai cặp "Distortion · Vignetting" (hồ sơ và chỉnh tay FS-03.15) — chốt E14: nhãn nhóm LENS PROFILE / MANUAL, VoiceOver kèm tên nhóm (T29, T36). Slider "Chromatic Aberration" nằm cạnh chip "Remove CA" trong cùng Optics; "Vignetting" (Optics) gần "Vignette" (Effects); nhãn history "Lens On/Off" từ `shortTitle` (`EditorAdjustmentCatalog.swift:245`) | trung bình | spec đã chốt tên (D76, 16b §2) nên không đổi ở đây; T29 đổi `shortTitle` thành "Lens Correction"; `copy-consistency` rà lại khi FS-03.15 thêm slider "Distortion" chỉnh tay |
| Test sẽ vỡ | chắc chắn | `EditorAdjustmentCatalogTests.opticsAndGeoAreGlobalOnlyGroups` (:113-125, Optics == [CA, defringe]), `everyGroupedKindAppearsExactlyOnce`, `displayText(1, of: .lensCorrection) == "On"` (:158), `PhotoEditingModelsTests` :63-71, golden `lensWarp*` — sửa trong task gây ra, không nới ngưỡng |
| Thứ tự bộ đọc nhúng | — | giữ DNG → Sony → Fuji → Panasonic → OM (theo yêu cầu); `lightroom-parity` đề xuất Fuji trước Sony (ảnh X chưa sửa lệch rõ nhất) — đổi hai task T20/T22 nếu người duyệt muốn, không ảnh hưởng phạm vi |
| Pháp lý: không chép mã GPL (darktable, RawTherapee, ExifTool Perl) | — | bộ đọc viết từ mô tả định dạng; ghi nguồn mô tả trong comment |
| AC-4/5 phụ thuộc FS-03.14 chưa làm | chắc chắn | T27–28 chỉ làm hàm đổi thuần; nối vào bộ nhập ở FS-03.14 |

## 6. Phản biện (điền sau khi chạy `challenger`)

| Phản đối | Trả lời / thay đổi |
|---|---|
| — | chưa chạy; chạy trước khi duyệt nếu người dùng muốn |

## 7. Cách chứng minh là xong

- **Test**: mọi tên test ở §4 xanh trong `/test`; `KernelGoldenTests` xanh sau commit ghi lại golden;
  `test_lensfun_to_json.py` xanh; `Tools/gate` xanh.
- **Màn hình phải chụp** (`/screens`, cả iOS 26.5 và 18.6 nơi code rẽ `#available`): Optics ở từng trạng thái 16b §2
  (tự tìm · tự chọn · máy đã sửa · có sẵn trong máy · không có · tắt) trên iPhone 17 (402×874), iPad (sidebar), Duo
  inner (951×669) và cover; picker có/không dòng "Use Lens Data Found in Photo"; nhóm RAW không còn hàng Lens. RAW
  mẫu nạp sim phải qua kiểm mặt người.
- **Đo**: ≤ 8ms/khung kéo Distortion trên iPhone 17 (AC-a18) ở `/verify`.
- **Tài liệu phải cập nhật**: cột "Chứng minh bằng" của 16/16a/16b theo từng AC; 16a §1 cột "Nơi ghi" sau spike;
  16b §4 dung lượng thật; FS-03.11 §7 (RAW giờ cũng qua Lensfun); EX-01 §2 (kit thêm bộ đọc + dạng chung);
  NF-02 (bộ nhớ cache nền RAW ~2×, E17); dòng `Tiến độ` của intent (**chưa sửa trong lượt này** — lượt plan bị giới hạn chỉ ghi file
  kế hoạch; người duyệt ghi `**chưa làm** (2026-09-28) — plan … chờ duyệt, 38 task` khi commit).

## 8. Agent ở giai đoạn Deploy

| Agent | Vì sao | Đã chạy lúc plan |
|---|---|---|
| `extension-boundary` | bộ đọc + dạng chung + kernel vào kit; `TIFFReader` public; bảng nạp theo phần | ✅ — xác nhận AC-6 cũ không có đường code (đã bỏ, E16), matcher ở lại app, ước bộ nhớ bảng |
| `perf-profiler` | kernel lấy mẫu, ROI, giải mã lại RAW khi kéo | ✅ — gain trong `linearSpaceFilter` làm mỗi khung kéo tạo lại `CIRAWFilter` (nguồn của E17); đệm ROI theo CA; đo cả `render()`; chạm bảng off-main |
| `test-coverage` | 36 AC, fixture byte, seam `CIRAWFilter` | ✅ — fixture tự dựng theo mẫu `MakerNoteParserTests`; seam "bộ giải hỗ trợ?" cho AC-a5/a6; chưa có test controller nào → `PhotoEditorControllerLensTests` mới; danh sách test sẽ vỡ (§5) |
| `copy-consistency` | chữ 16b §2, va chạm tên | ✅ — mọi chữ phải thay khớp bảng §1c; va chạm CA/Remove CA, Vignetting/Vignette, "Lens On/Off" (§5) |
| `lightroom-parity` | thứ tự ưu tiên, hành vi LR với dữ liệu nhúng | ✅ (helpx.adobe.com chặn truy cập; nguồn thứ cấp) — LR tự áp hồ sơ nhúng với mirrorless, thang 0–200 vẫn chạy trên hồ sơ nhúng, Remove CA tách khỏi hồ sơ: khớp §3, D76, D77. Ưu tiên: Lensfun tối góc + CA trước, rồi luật không sửa hai lần, rồi bộ đọc (DNG đầu tiên) — khớp thứ tự pha của kế hoạch |
| `swift-concurrency` | resolver/đọc byte off-main | ở Deploy |
| `photokit-guard` | byte gốc vs proxy / bản đã sửa | ở Deploy |
| `memory-leak` | cache dữ liệu nhúng, bảng, cache nền RAW half-float (E17) | ở Deploy |
| `device-layout`, `ios26-parity`, `a11y-voiceover`, `localization` | panel Optics 5 hàng, slider mờ, chữ mới | ở Deploy |
