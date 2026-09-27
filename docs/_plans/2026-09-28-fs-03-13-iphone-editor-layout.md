# Kế hoạch — Editor trên iPhone: thanh 6 công cụ, panel theo ảnh

| Trường | Giá trị |
|---|---|
| Đặc tả | [FS-03.13](../02-functional-spec/FS-03-photo-editor/13-iphone-editor-layout.md) · [13a](../02-functional-spec/FS-03-photo-editor/13a-chrome-and-toolbar.md) · [13b](../02-functional-spec/FS-03-photo-editor/13b-edit-and-transform.md) · [13c](../02-functional-spec/FS-03-photo-editor/13c-mask-heal-markup.md) · [13d](../02-functional-spec/FS-03-photo-editor/13d-presets-batch-devices.md) — 45 AC |
| Intent | [2026-09-27-editor-iphone-layout](../_intents/2026-09-27-editor-iphone-layout.md) |
| Quyết định | `.planboard/editor-specs-decisions/DECISIONS.md` (D1–D33, D39, D45, D66, D68) |
| Quyết định lệch | `.planboard/plans-deviations/DECISIONS.md` (E1–E5) |
| Ngày | 2026-09-28 |
| Trạng thái | **nháp — chờ duyệt**; 5 dòng ⚠️ đã chốt 2026-09-28 (E1–E5, §2.1) |

## 1. Hiểu đúng chưa

Editor ở layout không sidebar (iPhone dọc, Duo màn ngoài) bỏ bánh xe 15 chip, thay bằng **thanh 6 công cụ cố định**
Presets · Edit · Transform · Mask · Heal · Markup. Băng trên gọn hai bên Dynamic Island, **Save luôn hiện**, bỏ nút
compare (giữ lâu trên ảnh ở Edit/Presets là xem gốc). Panel **344 / 264 / 315** theo phần đen của ảnh sau crop đã
lưu, cố định trong phiên. Bốn công cụ dựng hình vào bằng **✕ · tên · ✓**: ✕ trả recipe và độ sâu lịch sử về lúc vào
(hỏi khi có thay đổi), Undo dừng ở lúc vào. Edit là **một danh sách dài** có nhãn dính + mục lục; Curve vào panel ở
**mọi layout**; Transform gộp Crop · Straighten (có Straighten Tool) · Upright 3+3 · Geometry. Mask/Markup chọn loại bằng
lưới 4 cột, có hàng "[đang chọn] ▼ · + · ⋯" mở danh sách dọc; cọ là hàng viên ghim; phủ đỏ tự mờ 1,5s ở **mọi layout**.
Presets thành lưới 4 cột + menu giữ lâu; filmstrip 56 viền trắng, Sync chỉ ở cuối filmstrip; Duo ngoài có cột công cụ
dọc. **Không đổi recipe. Không mất chức năng.** iPhone đã khoá dọc sẵn (`project.pbxproj:810,843`) — D24 không cần sửa.

Không lệch với intent, trừ ba chỗ intent đã được DECISIONS thay (bỏ iPhone ngang, bỏ Manage Looks, giữ-xem-gốc cả
Presets) — kế hoạch theo DECISIONS.

## 2. Đối chiếu AC ↔ code (2026-09-28, đọc code thật)

Ký hiệu: ✅ code đã đạt (chỉ viết test khoá) · ⚠️ lệch, **cần người dùng quyết** · ❌ chưa có · ❓ chưa kết luận.
"⚠️ → … chốt E#" = dòng từng lệch, người dùng đã chọn hướng ở `.planboard/plans-deviations/DECISIONS.md`.
Đường dẫn gốc `ShotDex/Features/Editing/` trừ khi ghi khác; `LM` = `ShotDex/Domain/Editing/EditorLayoutMetrics.swift`,
`PES` = `PhotoEditorScreen.swift`, `PEC` = `PhotoEditorController.swift`, `EIS` = `EditorImageStage.swift`.

### 13a — khung, băng trên, thanh công cụ

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 | ❌ | panel cố định `LM:32` (264), vùng 185 `LM:38`; `PES:593` dùng thẳng hằng; test khoá 264 `ShotDexTests/EditorPanelLayoutTests.swift:14-49` | hàm thuần `phonePanelHeight(screen:topBand:filmstrip:aspect:)` trong `LM`; 6 hàng slider ở vùng 265; viết lại test 264 |
| AC-2 | ❌ | như AC-1 | ca 4:5 → 264, stage vừa khung 503 |
| AC-3 | ❌ | như AC-1 | ca biên 1:1 trên 402 và 375 (T = 48 trên SE) |
| AC-4 | ❌ | `PES:593` không có khái niệm phiên; `previewAspectRatio` đổi theo crop `PEC:2188-2198` | chốt `a` lúc mở ảnh (và lúc đổi ảnh filmstrip), không đọc lại khi crop |
| AC-5 | ❌ | Curve phone là lớp đè stage `EIS:82-86,538-546`; panel không đổi cao | 315 khi mở Curve với panel 264 — sau AC-19 |
| AC-6 | ❌ | tỉ lệ chỉ biết sau khi preview về `PEC:2188`; `PHAsset.pixelWidth/Height` chưa dùng cho layout | `a` từ pixel asset + `recipe.crop` (rect, quarterTurns) — hàm thuần mới cạnh `CropFrameGeometry` |
| AC-7 | ❌ | Save commit crop rồi mở sheet `PES:2503-2506`, nhưng huỷ sheet thì vẫn ở tab Crop, không về Edit | Save trong công cụ = ✓ rồi mở sheet |
| AC-8 | ❌ | **tái dùng được**: `beginStageSession/restoreStageEntry` lưu recipe + độ sâu, `rewind` lịch sử `PEC:1089-1113`, `PhotoEditHistory.swift:40-50`; nhưng phone không có ✕, không hộp xác nhận (sidebar có Cancel không hỏi `PES:1540-1552`) | ✕ trên thanh + "Discard changes to ‹tool›?" / "Discard Changes" (chữ đã có `PES:168-169`) khi phiên có ≥1 bước |
| AC-9 | ❌ | mỗi nét một bước đã đúng; `undo()` không đổi `selectedGroup` `PEC:536-541` — nhưng ✓ chưa có | ✓ = `clearStageEntry` + về Edit; test undo sau ✓ |
| AC-10 | ❌ | `canUndo` = `history.canUndo` `PEC:310`, không có sàn | sàn undo = `stageEntry.undoDepth` trong Domain (`PhotoEditHistory`); áp cả cho ⌘Z, chạm hai ngón `PES:1037-1043`, History sheet |
| AC-11 | ✅ | giữ ≥0,3s = gốc `EIS:636-649`, gắn cho mọi nhóm không vẽ `EIS:433-438`; Mask Brush: cử chỉ chỉ ở subviews, lớp vẽ nhận cú giữ và nhả tay thành đúng 1 dấu `Domain/Editing/PaintTouchArbiter.swift:123-127` | chỉ khoá bằng script + chụp liên tục |
| AC-12 | ⚠️ → ✅ chốt E1 | spec đổi theo code: histogram "RGB histogram" `EditorHistogramCard.swift:277`, ⋯ "More editor actions" `PES:2351`; Back `PES:2497`, Undo/Redo `:1844,1850`, Save `:2532` đã khớp. Cancel/Apply sinh ra cùng ✕/✓ (task 14, 16), "Show Original" sinh ra cùng việc bỏ nút compare (task 8, hôm nay ở `PES:1962-1968`) | **chỉ viết test khoá** nhãn (dump), đặt sau ✕/✓ |
| AC-13 | ⚠️ → ❌ chốt E2 | ⋯ phone hôm nay `PES:2094-2352`: **Undo · Redo** (`:2106-2118`) · Fill Screen · mục theo tab · Copy/Paste · Auto Sync/Apply Previous/Sync `:2257-2290` · Reset All · Revert · History · Recall · Source. Chốt theo spec: đúng 5 mục History · Copy Edits · Fill Screen · Revert · Reset All | **sửa code**: bỏ Undo/Redo khỏi ⋯ (còn ở băng trên + chạm hai ngón), xếp lại thứ tự, bỏ Sync (sau AC-40), Rotate/Flip → Transform, mục mask → hàng Mask, Recall/Source cuối |
| AC-14 | ❌ | bánh xe `PES:2755-2766`, `EditorGroupWheel` `PES:3073+`; accent còn ở vòng vết Heal đang chọn `EditorHealPanel.swift:143`, filmstrip `EditorSession.swift:199,213`; `Tools/accent-check` đã có | thanh 6 ô (dựng từ `EditorRailMode.allCases` theo thứ tự spec), bỏ bánh xe; chạy accent-check 6 màn × 2 iOS |

### 13b — Edit và Transform

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-15 | ❌ | phone chỉ vẽ **một** nhóm mỗi lần `PES:2536-2653` | `EditorEditList`: `LazyVStack(pinnedViews:)` mọi nhóm, nhãn dính "‹GROUP› ▼" |
| AC-16 | ❌ | danh sách nhóm có sẵn = `EditorGroup.allCases` trừ 6 nhóm công cụ + `geo` → đúng 9, đúng thứ tự `PEC:61-81`; tên "Grade" `PEC:91` | mục lục dựng từ danh sách đó (Domain, test lặp); đổi "Grade" → "Grading" (D10, cả sidebar) |
| AC-17 | ❌ | không có mục lục | chạm mục → cuộn tới nhãn, đóng mục lục |
| AC-18 | ❌ | không có trạng thái cuộn nào trong `EditorChromeModel.swift` | chỗ cuộn là trạng thái phiên trên `EditorChromeModel` (không vào recipe/lịch sử) |
| AC-19 | ❌ (½ ✅) | sidebar đã vẽ curve trong panel (`isShapingCurve` tắt khi wide `EIS:82-86`, `EditorCurveOverlay(scrollsWithPanel:)` `EditorCurveOverlay.swift:14-24`); phone vẫn đè stage; ✕ Curve chưa có | hàng Curve + công cụ con ✕ · Curve · ✓ với đồ thị 220×220 tái dùng `EditorCurveOverlay(scrollsWithPanel: true)`; bỏ lớp đè ở mọi layout |
| AC-20 | ❌ | Crop và Geo là hai chip bánh xe; tỉ lệ 8 chip cuộn ngang `EditorToolPanels.swift:721-732`; `CropAspect.allCases` = 8 `ShotDexKit/Models/PhotoEditingModels.swift:916-924` (đúng 4 + More… 4) | `EditorTransformList` 4 nhóm; More… dựng từ `allCases` trừ 4; hàng chờ FS-03.15 không hiện |
| AC-21 | ❌ | model đúng một nửa: `cancelCropSession` trả crop + rewind `PEC:1283-1290`, nhưng phone commit khi rời tab `PES:2805-2815` và footnote "applies when you leave" `EditorToolPanels.swift:587` | ✕ Transform dùng stage session (trả cả recipe) |
| AC-22 | ❌ | không có Straighten Tool; Angle = `recipe.crop.straightenDegrees`, kẹp ±45 `PEC:1053-1057` | Domain `StraightenToolMath` (góc, dựng đứng >45°, <8pt = chạm) + lớp chạm một ngón |
| AC-23 | ⚠️ → ❌ chốt E3 | câu "No straight lines to work from" 3s đã có cho Upright `EditorToolPanels.swift:839-857`; Upright Level ghi `geoRotate` `PEC:721-740`. Chốt theo spec: Auto của Straighten ghi `crop.straightenDegrees` (13b §3 và AC-23 đã ghi rõ) | **sửa code**: chip Auto chạy `UprightAnalyzer` Level, ghi góc vào `crop.straightenDegrees` (kẹp ±45, một bước lịch sử), `geoRotate` không đổi; Upright Level giữ nguyên đường cũ |
| AC-24 | ❌ | Upright một hàng 4 chip Level · Vertical · Full · Off `EditorToolPanels.swift:797-837`; `UprightMode` chỉ 3 ca `ShotDexKit/Render/UprightAnalyzer.swift:6-23`; Guided chưa có | 3 + 3 theo thứ tự Off · Auto · Level / Vertical · Full · Guided, dồn khi thiếu; **phần Guided chờ FS-03.15b** |

### 13c — Mask, Heal, Markup

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-25 | ❌ | 3 hàng chip cuộn ngang `EditorMaskPhonePanel.swift:58-70`; thứ tự `EditorNewMaskOption.allCases` đã khớp spec (trừ Object/People) `Domain/Editing/EditorNewMaskOption.swift:10-22`; ba ô mặt riêng ✅ | lưới 4 cột ô 60 dựng từ `allCases`; sửa `MaskPhonePanelTests.chooserRowsCoverEveryKindOnce` |
| AC-26 | ⚠️ → ❌ chốt E4 | Brush vẽ ngay đã đúng (chip → `editSelectedMaskAdjustments` → lớp vẽ bật `EIS:40-49`); tên mask hôm nay theo loại `"\(option.shortTitle) \(recipe.masks.count)"` `PEC:1785-1787`. Chốt theo spec: "Mask n" + dòng phụ liệt vùng; FS-03.05 §3, §4 và AC-18 đã sửa theo (2026-09-28) | **sửa code**: tên "Mask \(count)" cho mọi loại (cả Background); dòng phụ dựng từ `components` (Domain, có test); hàng trên 40 + hàng cọ ghim; **sửa `MaskPhonePanelTests.oneTapOnRadialMakesOneShortNamedMask`** (FS-03.05 AC-18) sang "Mask 1" và cập nhật cột chứng minh AC-18 |
| AC-27 | ✅ | `+` → `isChoosingMaskKind`, `‹` không tạo gì `EditorMaskPhonePanel.swift:79-90`; `MaskPhonePanelTests.swift:77-88` | cập nhật test theo lưới + tiêu đề "New Mask" |
| AC-28 | ❌ | dải thumbnail ngang `EditorMaskPhonePanel.swift:142-252`; sheet chọn mask `EditorMaskPanels.swift:896` | `EditorMaskList` dọc: mask → vùng ⊕/⊖ → Add/Subtract area → New Mask |
| AC-29 | ❌ | **không có API thêm vùng** vào mask đã có: `maskOperation` chỉ bật tẩy cho cọ `PEC:217-223`; không chỗ nào append component | `PEC.addArea(_ option:, operation:)` + lưới "Add to / Subtract from ‹mask›" từ `allCases` |
| AC-30 | ❌ | Size/Feather/Flow là 3 hàng slider trong danh sách `EditorMaskPanels.swift:637-646` | hàng viên ghim, chạm → slider + ✓, giữ-kéo; vòng xem trước |
| AC-31 | ❌ | luật hôm nay: hiện khi vẽ `revealMaskShape`, tắt khi kéo slider, không mờ, không ghim `PEC:640-661`; công tắc ở ⋯ `PES:2223-2237` | Domain `MaskOverlayPolicy` (vẽ → hiện, nhấc → mờ 1,5s, slider → tắt, ghim thắng) cho mọi layout |
| AC-32 | ❌ | hàng chưa tồn tại; chưa đo SE/Duo (câu đo 2, 3) | đo sau AC-26/30 |
| AC-33 | ❌ | Heal: hint · Heal/Clone · Size · Feather · Delete Spot chỉ khi có vết chọn `EditorHealPanel.swift:7-86`; không có Remove ✅ | hàng chế độ chia đều, hàng viên ghim, SELECTED SPOT mờ 0,35, SPOTS · n; hàng FS-03.15c không hiện |
| AC-34 | ❌ | **model có sẵn**: `moveOverlays(fromDisplay:toDisplay:)` `PEC:1602`, `moveOverlay(id:ontoOverlay:)` `:1614` (một bước undo, test `MarkupPhonePanelTests.swift:91-105`); UI vẫn dải ngang kéo-thả | danh sách lớp dọc, `≡` + `onMove` → `moveOverlays` |
| AC-35 | ✅ | nhóm căn lề 3 nút, đúng 1 sáng `EditorTextDetailPanel.swift:358-400` | test khoá; thêm nhãn VoiceOver "Text alignment" / "Align left…" (spec §5, hôm nay không có nhãn) |
| AC-36 | ❌ | 7 mực là dải chip cuộn `EditorMarkupPhonePanel.swift:422,503`; chooser 3 hàng cuộn `:122` | trang con từ chấm màu (lưới mực `EditorDrawInk.allCases` + bảng màu có sẵn `chrome.colorPalette`) |

### 13d — Presets, sửa nhiều ảnh, Duo màn ngoài

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-37 | ❌ | thumbnail cuộn ngang `EditorToolPanels.swift:64-92`; 49 look ✅ (`PhotoFilter` 49 ca); Amount chỉ khi có look ✅ | lưới 4 cột, hàng 90 |
| AC-38 | ❌ | Save Current mờ khi identity ✅ `EditorToolPanels.swift:107`; chưa có ô Import XMP Preset, chưa có dòng trống | ô Import XMP Preset + dòng "Save an edit here…" — **bộ nhập thuộc FS-03.14a** |
| AC-39 | ❌ | giữ lâu chỉ có "Delete Look/LUT" `EditorToolPanels.swift:180-186,401-406,427-431`; preset có sẵn không có menu; `LookPresetStore.rename` có sẵn | menu Rename · Share · Export As · Delete — **Share/Export As chờ FS-03.14c** |
| AC-40 | ⚠️ → ❌ chốt E5 | filmstrip 96/124 `LM:247-248`, viền + badge accent `EditorSession.swift:196-216`; ✓ đã lưu không hiện với ảnh không phải ảnh đang mở (draft bị xoá khi lưu `EditorSession.swift:63-66`, badge chỉ khi `hasDraft`); Sync ở ⋯ `PES:2257-2290`; Apply Previous chỉ hiện khi có `previousRecipe` `:2265`. Chốt theo spec: menu luôn 4 mục | **sửa code**: filmstrip 56/44/r-track 6, vòng trắng, chấm trắng / ✓ đĩa đen, pill Sync + "2 / 7"; menu Sync luôn có Apply Previous, `.disabled` khi `previousRecipe == nil` |
| AC-41 | ❌ | filmstrip ẩn chỉ khi vẽ/tràn viền `PES:993` | ẩn khi vào công cụ, panel +56, stage đứng yên |
| AC-42 | ❌ | không có luật panel theo ảnh | ca F = 56 của hàm AC-1, đổi ảnh thì tính lại |
| AC-43 | ❌ | editor không nghe `didReceiveMemoryWarning` (chỉ `LibraryModel.swift:262`); phiên công cụ phone chưa có | test: bắn notification trong công cụ → phiên, nét, sàn undo còn — sau AC-8 |
| AC-44 | ❌ | Duo ngoài đi đường phone (panel 264 + bánh xe, FS-03.12 AC-13); luật `usesSidebar` `LM:100-102` | bố cục cột 56 (Save + 6 ô) khi vùng an toàn phải lớn (hỏi safe area, không hỏi idiom); danh sách 300 |
| AC-45 | ❌ | như AC-44 | ✕ / ✓ thay 6 ô trong cột; tên công cụ trên băng |

**Tổng: ✅ 4 · ❌ 41 · ⚠️ còn mở 0 · ❓ 0** (trước khi chốt: ✅ 3 · ⚠️ 5 · ❌ 37 — AC-12 thành ✅, AC-13/23/26/40 thành việc sửa code). Số AC không đổi: 45.

### 2.1 Các dòng ⚠️ — đã chốt 2026-09-28

Quyết định lệch: `.planboard/plans-deviations/DECISIONS.md`.

| # | Dòng | Câu đã hỏi | Chốt | Hệ quả trong plan |
|---|---|---|---|---|
| E1 | AC-12 | "Histogram"/"More" (spec) hay "RGB histogram"/"More editor actions" (code)? | theo **code** — spec 13a AC-12 đã sửa | ✅, task 18 chỉ viết test khoá |
| E2 | AC-13 | ⋯ giữ Undo/Redo (code) hay đúng 5 mục (spec)? | theo **spec** — bỏ khỏi ⋯ | task 41 sửa code |
| E3 | AC-23 | Straighten Auto ghi `crop.straightenDegrees` (spec) hay `geoRotate` (code)? | theo **spec** — góc Straighten của crop | task 25 sửa code |
| E4 | AC-26 (và 28, 29) | "Mask 1" + dòng phụ (spec) hay "Brush 1"/"Radial 1" (code, FS-03.05 AC-18)? | theo **spec** — FS-03.05 AC-18 đã sửa | task 28 sửa code + test FS-03.05 |
| E5 | AC-40 | Apply Previous luôn hiện, mờ khi chưa có (spec) hay chỉ khi có (code)? | theo **spec** — menu luôn 4 mục | task 40 sửa code |

Lệch nhỏ ngoài bảng AC (ghi để khỏi quên, không chặn): chữ gợi ý Save Current trong spec ("Saves tone, color, curve and
film look. Crop, masks and markup stay with this photo.") khác câu đang có `PES:710` ("…tone, colour, curve…") dù spec
ghi "giữ như hôm nay" — sửa theo spec trong task AC-38 trừ khi người dùng nói khác.

## 3. Cái gì tái dùng được (chặn "một khái niệm hai cách làm")

| Có sẵn | Ở đâu | Dùng cho |
|---|---|---|
| Phiên công cụ: `beginStageSession` / `restoreStageEntry` / `clearStageEntry` (recipe + độ sâu, rewind lịch sử) | `PEC:1089-1113`, `Domain/Editing/PhotoEditHistory.swift:40-50` | ✕ / ✓ phone (AC-8, 9, 10, 21) — **một** cơ chế cho sidebar và phone |
| `EditorRailMode` (edit, presets, crop, heal, mask, markup) + `containing(_:)` | `EditorSidebar.swift:53-97` | thanh 6 công cụ phone và cột Duo (đổi thứ tự hiển thị thành Presets · Edit · …; đổi tên hiển thị Crop → Transform) |
| `EditorGroup.allCases` (9 nhóm phone sau khi trừ công cụ + geo) | `PEC:61-81` | mục lục Edit (AC-16), không viết tay |
| `EditorCurveOverlay(scrollsWithPanel: true)` + `EditorCurveChannelStrip` | `EditorCurveOverlay.swift:14-24,497` | đồ thị 220×220 trong panel (AC-19) |
| `cancelCropSession`, `CropFrameGeometry`, `CropAspect.allCases` | `PEC:1283`, `Domain/Editing/CropFrameGeometry.swift`, kit | Transform, More…, tỉ lệ sau crop (AC-6) |
| `UprightAnalyzer` + dòng báo 3s | kit, `EditorToolPanels.swift:839-857` | Straighten Auto (AC-23) — cùng phân tích Level, ghi vào `crop.straightenDegrees` (E3) |
| `EditorNewMaskOption.allCases` + `unavailableReason` | `Domain/Editing/EditorNewMaskOption.swift` | lưới chọn mask và lưới Add/Subtract area (AC-25, 29) |
| `EditorMaskActionsMenu` (Hide/Show · Rename · Invert · Duplicate · Delete This Shape · Delete) | `EditorMaskPanels.swift:227-305` | ⋯ của hàng Mask (bỏ Undo/Redo trong đó — chốt E2) |
| `moveOverlays(fromDisplay:toDisplay:)` | `PEC:1602` | danh sách lớp dọc (AC-34) |
| `EditorDrawInk.allCases`, bảng màu `chrome.colorPalette` | `EditorMarkupPhonePanel.swift:367`, `EditorChromeModel.swift` | trang con mực (AC-36) |
| `EditorStripLayout` (chia đều) | `Domain/Editing/EditorStripLayout.swift` | 6 ô thanh công cụ, Upright 3+3, Heal/Clone — **luật ">5 thì cuộn" phải đổi thành "xuống hàng / More…"** |
| `LookPresetStore.rename/delete`, `ImportedLUTStore` | `Domain/Editing/LookPresetStore.swift` | menu giữ lâu (AC-39) |
| `Tools/accent-check`, `Tools/sim-shot` (mask góc bo), `Tools/ui-drive` | `Tools/` | AC-14, 40, 44 |
| hộp "Discard Changes" | `PES:168-169` | chữ nút của ✕ (AC-8) |

## 4. Chỗ nào trong code

| File | Tầng | Đụng gì | Mới / sửa |
|---|---|---|---|
| `Domain/Editing/EditorLayoutMetrics.swift` | Domain | `phonePanelHeight(...)` 344/264/315/+56, thanh 54, filmstrip 56/44, cột Duo 56, danh sách Duo 300; bỏ hằng bánh xe, bỏ `curvePlotRect` đè stage | sửa |
| `Domain/Editing/EditorCroppedAspect.swift` | Domain | tỉ lệ sau crop từ pixel asset + `PhotoCropRecipe` (rect, quarterTurns) | mới |
| `Domain/Editing/PhotoEditHistory.swift` | Domain | sàn undo (`floorDepth`), `canUndo(aboveFloor:)` | sửa |
| `Domain/Editing/EditorEditIndex.swift` | Domain | danh sách nhóm Edit phone (9), nhóm Transform (4, có chỗ giữ cho FS-03.15), mục lục | mới |
| `Domain/Editing/StraightenToolMath.swift` | Domain | góc từ đoạn thẳng, dựng đứng >45°, ngưỡng 8pt | mới |
| `Domain/Editing/MaskOverlayPolicy.swift` | Domain | trạng thái phủ đỏ (vẽ/nhấc/slider/ghim, mờ 1,5s) | mới |
| `Domain/Editing/EditorStripLayout.swift` | Domain | xếp hàng N ô chia đều, không cuộn | sửa |
| `Domain/Editing/EditorNewMaskOption.swift` | Domain | thứ tự lưới 4 cột (giữ chỗ Object/People) thay `Row` 3 hàng | sửa |
| `PhotoEditorController.swift` | Features (model) | sàn undo khi có stage session; `addArea(_:operation:)`; tên mask "Mask n" (E4); Straighten Auto → `crop.straightenDegrees` (E3); "Grading" | sửa |
| `Domain/Editing/MaskAreaSummary.swift` | Domain | dòng phụ "Sky − Brush" dựng từ `components` (cộng/trừ, Background) — E4 | mới |
| `EditorChromeModel.swift` | Features (model) | `activeTool` (công cụ đang mở), chỗ cuộn Edit/Transform, mục lục mở, danh sách mask/lớp mở, `sessionAspect`, trạng thái phủ đỏ | sửa |
| `PhotoEditorScreen.swift` (3239 dòng) | Features (view) | tách bố cục phone ra `PhotoEditorPhoneLayout.swift`; bỏ bánh xe + nút compare; band mới; ⋯ mới | sửa + tách |
| `EditorToolBar.swift` | Features (view) | thanh 6 ô / ✕ · tên · ✓ / cột Duo | mới |
| `EditorEditList.swift`, `EditorTransformList.swift` | Features (view) | danh sách dài, nhãn dính, mục lục | mới |
| `EditorImageStage.swift` | Features (view) | bỏ lớp curve đè; Straighten Tool + Guided (sau 15b) một ngón; vòng xem trước Size; "Show Original" | sửa |
| `EditorCurveOverlay.swift` | Features (view) | panel 220×220 + cột kênh, bỏ nhánh đè stage | sửa |
| `EditorToolPanels.swift` | Features (view) | Crop panel → vào Transform list; Upright 3+3; Presets lưới + menu giữ lâu | sửa |
| `EditorMaskPhonePanel.swift`, `EditorMaskPanels.swift` | Features (view) | lưới 4 cột, hàng trên, danh sách mask, hàng cọ ghim, chip Mask Overlay (cả sidebar) | sửa |
| `EditorHealPanel.swift` | Features (view) | hàng chế độ, hàng viên, SELECTED SPOT, SPOTS · n; bỏ accent vòng vết | sửa |
| `EditorMarkupPhonePanel.swift`, `EditorTextDetailPanel.swift` | Features (view) | lưới lớp, danh sách lớp dọc, trang con mực, nhãn VO căn lề | sửa |
| `EditorSession.swift` (filmstrip) | Features (view) | 56/44/6, vòng trắng, badge, pill Sync + đếm; menu Sync luôn 4 mục, Apply Previous mờ khi chưa có (E5) | sửa |
| `ShotDexTests/*` | Test | xem §6 | sửa + mới |
| `ShotDexUITests/scripts/*.json` | Test | 10 script mới (§6) | mới |
| `DESIGN.md`, `docs/02-functional-spec/**` | Tài liệu | §7 bảng viết lại, mỗi đoạn đi cùng commit của AC làm nó sai | sửa |

Logic không vào View: chiều cao panel, tỉ lệ sau crop, sàn undo, góc Straighten, luật phủ đỏ, mục lục, xếp hàng ô —
tất cả ở Domain và có test. Không dữ liệu người dùng mới (chỗ cuộn, mục lục mở là trạng thái phiên, không lưu).

## 5. Thứ tự task

Một AC = một task = một commit (`feat(FS-03.13): AC-n …`), test đi cùng. Thứ tự theo luật **✅ → ⚠️ → ❌**. Cả 5 câu
⚠️ đã có câu trả lời (E1–E5, §2.1); vì dòng nào cũng dựa vào khung chưa có (✕/✓, danh sách mask, filmstrip mới), *commit*
của chúng vẫn nằm trong pha của nó, ngay sau task tiền đề — kể cả AC-12 (✅ sau E1): test khoá nhãn cần Cancel/Apply
của ✕/✓ nên đứng ở task 18 chứ không ở pha 0. Mỗi commit phải build được và
**không làm mất chức năng giữa chừng** — vì thế Edit list land trước khi bánh xe bị bỏ (bánh xe tạm cuộn danh sách dài
tới nhóm của chip).

| # | Pha | AC | Task | Test kèm theo | Phụ thuộc |
|---|---|---|---|---|---|
| 1 | 0 · khoá cái đã đạt | AC-11 | khoá giữ-xem-gốc ở Edit/Presets, dấu cọ ở Mask | `iphone-tool-sessions.json` (phần giữ) + chụp liên tục `Tools/sim-shot` | — |
| 2 | 0 | AC-27 | khoá `+` → `‹` | `MaskPhonePanelTests.plusThenBackMakesNothing` (giữ, sửa tên AC) | — |
| 3 | 0 | AC-35 | khoá radio căn lề + nhãn VO | `MarkupPhonePanelTests.alignmentGroupIsARadio` | — |
| 4 | 1 · Edit list | AC-15 | danh sách dài + nhãn dính (bánh xe tạm cuộn tới nhóm) | `iphone-edit-list.json` + dump | — |
| 5 | 1 | AC-16 | mục lục từ `EditorEditIndex`, "Grade" → "Grading" | `EditorPanelLayoutTests.phoneIndexListsEveryEditGroupOnce` | 4 |
| 6 | 1 | AC-17 | nhảy tới nhóm | `iphone-edit-list.json` dump trước/sau | 5 |
| 7 | 1 | AC-18 | nhớ chỗ cuộn | `iphone-edit-list.json` | 4 |
| 8 | 2 · khung + thanh | AC-14 | **đo D3 trước** (`device-layout`); thanh 6 công cụ, bỏ bánh xe + nút compare (thêm `accessibilityAction(named: "Show Original")` trên stage), band Back·Undo·Redo \| histogram·⋯·Save 36 | `Tools/accent-check` + `se-editor-fit.json` + `ios26-parity` | 4–7, đo D3 |
| 9 | 2 | AC-1 | `phonePanelHeight` + 6 hàng | `EditorPanelLayoutTests.phonePanelIs344OnlyWhenTheExtraIsLetterbox` + `iphone-editor-frame.json` | 8 |
| 10 | 2 | AC-2 | ca 4:5 | cùng test | 9 |
| 11 | 2 | AC-3 | ca biên 1:1, SE | cùng test | 9 |
| 12 | 2 | AC-6 | tỉ lệ từ pixel asset + crop đã lưu | `EditorPanelLayoutTests.panelHeightNeedsOnlyAssetPixelSize` + ảnh chụp tay offline | 9 |
| 13 | 2 | AC-4 | cố định trong phiên | `EditorPanelLayoutTests.phonePanelStaysFixedForTheSession` | 12 |
| 14 | 3 · phiên công cụ | AC-8 | ✕ (nhãn VO "Cancel") + hỏi khi ≥1 bước | `EditorHistoryAndSummaryTests.cancelRestoresTheEntryRecipeAndDepth` + `iphone-tool-sessions.json` | 8 |
| 15 | 3 | AC-10 | sàn undo tại lúc vào (mọi đường undo) | `EditorHistoryAndSummaryTests.undoInsideAToolStopsAtEntry` | 14 |
| 16 | 3 | AC-9 | ✓ (nhãn VO "Apply") và undo sau ✓ | `EditorHistoryAndSummaryTests.undoAfterApplyStepsBackOneStroke` | 14 |
| 17 | 3 | AC-7 | Save trong công cụ = ✓ + sheet | `iphone-tool-sessions.json` | 16 |
| 18 | 3 | AC-12 ✅ (chốt E1) | **chỉ test khoá**: Back · Undo · Redo · RGB histogram · More editor actions · Save · Cancel · Apply + hành động "Show Original" | dump `iphone-editor-frame.json` | 8, 14, 16 |
| 19 | 3 | AC-43 | cảnh báo bộ nhớ giữ phiên | `EditorHistoryAndSummaryTests.memoryWarningKeepsTheToolSession` | 14 |
| 20 | 4 · Curve + Transform | AC-19 | Curve trong panel mọi layout | `EditorHistoryAndSummaryTests.curveCancelLeavesNoCurveBlock` + dump iPhone 17 và iPad 13" | 14 |
| 21 | 4 | AC-5 | panel 315 khi Curve với ảnh dọc | `iphone-edit-list.json` + dump | 9, 20 |
| 22 | 4 | AC-20 | Transform list, More…, hàng chờ 15 ẩn | `EditorPanelLayoutTests.transformReachesEveryCropRatioOnce` + `iphone-transform.json` | 14 |
| 23 | 4 | AC-21 | ✕ Transform trả khung | `EditorHistoryAndSummaryTests.transformCancelRestoresTheFrame` | 22 |
| 24 | 4 | AC-22 | Straighten Tool | `StraightenToolTests.aLineAtThreeDegreesLevelsThePhoto` · `.aNearVerticalLineStandsUp` | 22 |
| 25 | 4 | AC-23 (chốt E3) | chip Auto của Straighten: phân tích Level → `crop.straightenDegrees`, `geoRotate` không đổi | `UprightAnalyzerTests` (ca rỗng có sẵn `:271`) + `EditorHistoryAndSummaryTests.straightenAutoWritesTheCropAngle` + `iphone-transform.json` | 22 |
| 26 | 4 | AC-24 | Upright 3+3 (Guided ẩn tới 15b) | `iphone-transform.json` + `se-editor-fit.json` | 22; **phần Guided chờ FS-03.15b** |
| 27 | 5 · Mask/Heal/Markup | AC-25 | lưới 4 cột | `MaskPhonePanelTests.chooserTilesCoverEveryKindOnce` + `iphone-mask-list.json` | 14 |
| 28 | 5 | AC-26 (chốt E4) | hàng trên + tên "Mask n" + dòng phụ vùng (`MaskAreaSummary`) + hàng cọ vẽ ngay; sửa test FS-03.05 AC-18 | `MaskPhonePanelTests.brushTileDrawsImmediately` + `MaskPhonePanelTests.oneTapOnRadialMakesOneShortNamedMask` (sửa sang "Mask 1") + `MaskAreaSummaryTests.subtitleListsEveryArea` | 27 |
| 29 | 5 | AC-28 | danh sách mask dọc | `MaskPhonePanelTests.listPutsAreaActionsUnderTheSelectedMask` | 28 |
| 30 | 5 | AC-29 | Add / Subtract area mọi loại | `MaskPhonePanelTests.subtractAreaAddsASubtractingBrush` | 29 |
| 31 | 5 | AC-30 | hàng viên cọ ghim | `iphone-mask-list.json` + chụp liên tục | 28 |
| 32 | 5 | AC-31 | luật phủ đỏ mọi layout | `MaskOverlayPolicyTests.autoOverlayFollowsPaintAndYieldsToSliders` + dump iPhone/iPad | 28 |
| 33 | 5 | AC-32 | vừa SE 375 và Duo 326 (D29) | `se-editor-fit.json` + `duo-cover-editor.json` | 28, 30, 44* |
| 34 | 5 | AC-33 | Heal bố cục mới (hàng 15c ẩn) | `iphone-heal-markup.json` | 14 |
| 35 | 5 | AC-34 | danh sách lớp dọc | `MarkupPhonePanelTests.verticalListRestacksTheLayer` | 14 |
| 36 | 5 | AC-36 | trang con mực + lưới lớp | `MarkupPhonePanelTests.everyInkIsReachable` + `iphone-heal-markup.json` | 35 |
| 37 | 6 · Presets + nhiều ảnh | AC-37 | lưới 4 cột | `iphone-presets-grid.json` + dump | 8 |
| 38 | 6 | AC-38 | My Looks: Import XMP Preset + dòng trống | `iphone-presets-grid.json` | 37; **bộ nhập FS-03.14a** |
| 39 | 6 | AC-39 | menu giữ lâu | `iphone-presets-grid.json` | 37; **Share/Export As chờ FS-03.14c** |
| 40 | 6 | AC-40 (chốt E5) | filmstrip 56 + pill Sync; menu luôn 4 mục, Apply Previous mờ khi chưa có ảnh trước | `iphone-batch-filmstrip.json` (dump menu cả hai trạng thái) + `Tools/accent-check` | 9 |
| 41 | 6 | AC-13 (chốt E2) | ⋯ đúng 5 mục: bỏ Undo/Redo và Sync | dump `iphone-editor-frame.json` + `iphone-batch-filmstrip.json` | 40 |
| 42 | 6 | AC-41 | vào công cụ ẩn filmstrip, panel +56 | `iphone-batch-filmstrip.json` dump trước/sau | 14, 40 |
| 43 | 6 | AC-42 | panel theo ảnh đang mở | `EditorPanelLayoutTests.batchPanelCountsTheFilmstrip` | 9, 40 |
| 44 | 7 · Duo ngoài | AC-44 | cột 56 + danh sách 300 + histogram | `duo-cover-editor.json` + `Tools/sim-shot … cover` | 8, 14 |
| 45 | 7 | AC-45 | ✕ / ✓ trong cột | `duo-cover-editor.json` + dump | 44 |

\* Task 33 đo phần Duo khi task 44 đã land; nếu làm trước thì chỉ đo SE rồi bổ sung Duo sau task 44.

**Hàng chờ spec khác (không hiện, giữ chỗ — luật "chưa có thì không hiện"):**

| Spec | Hiện ra ở | Trong task |
|---|---|---|
| FS-03.14a / 14c | ô Import XMP Preset (bộ nhập), Share · Export As của menu giữ lâu, nhãn "Imported" | 38, 39 — AC-38/39 chỉ chứng minh trọn khi 14 land |
| FS-03.15a | nhóm Edit mới (vd. Calibration) — mục lục tự có | 5 (test lặp, không đếm cứng 9) |
| FS-03.15b | Upright Auto, Guided, Aspect, Constrain Crop | 22, 26 — AC-24 phần "4 of 4 drawn" chờ 15b |
| FS-03.15c | Heal: Red Eye, Opacity, New Source, Visualize Spots + Threshold, Show Spot Pins, Clear All | 34 |
| FS-03.15d | ô Object, People (lưới lên 4×4) | 27 |
| FS-03.16b | nội dung nhóm Optics trong danh sách Edit | 4 (nhóm dựng từ catalog) |

Cách giữ chỗ: mỗi danh sách (hàng Transform, ô mask, hàng Heal) là một enum thứ tự đầy đủ trong Domain có
`isAvailable`; view chỉ vẽ ca có. Test lặp qua enum, không liệt kê tay theo thiết bị (luật "phone có mọi tính năng
iPad").

## 6. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| **D3 chưa đo** — cụm 120 cách mép 10 hay 20, hở Dynamic Island ≥8 không (code hôm nay: 20 `LM:268`, đảo 132 `LM:272`) | chắc chắn phải làm | task 8 mở bằng `device-layout` trên iPhone 17 + 17 Pro Max, khung có mask của `Tools/sim-shot`; ghi số vào 13a §3 trong cùng commit |
| **SE 375×667**: "Transform" trong ô 62,5 ở 10,5pt; Upright 111/chip; hàng cọ; hàng Mask; stage 275 | trung bình | `se-editor-fit.json` ở task 8, 26, 33; co tối đa 0,85 như FS-03.12, không thêm cỡ chữ |
| **Duo ngoài 326**: nhận ra bằng vùng an toàn phải 84 chứ không bằng idiom (Duo báo `.phone`); "Mask Overlay" và "Transform" trong ô 52 | trung bình | hàm Domain chọn bố cục theo `size + safeAreaInsets`; đo trước khi quyết D29/D30; không lái Duo bằng MCP (dùng `Tools/ui-drive`) |
| **iOS 26 vs 18.6**: thanh công cụ tự vẽ (không `TabView`), chỉ vật liệu qua `editorGlass`; mọi hành động hai nhánh như nhau | thấp | `ios26-parity` dump hai phía ở task 8, 18, 44 |
| **Min target iOS 17**: `ScrollPosition`/`onScrollGeometryChange` là iOS 18 | trung bình | nhớ chỗ cuộn bằng `scrollPosition(id:)` (iOS 17) + neo theo id nhóm; nhãn dính bằng `LazyVStack(pinnedViews:)` |
| **Bỏ Undo/Redo khỏi ⋯ (E2)**: người cầm một tay mất lối undo gần ngón cái | trung bình | chạm hai ngón vẫn undo (`PES:1037-1043`); `iphone-ux-review` xem lại ở task 41 |
| **Straighten Auto và Upright Level cùng phân tích, hai chỗ lưu (E3)**: Auto ghi crop, Level ghi `geoRotate` — bấm cả hai là xoay gấp đôi | trung bình | test task 25 khẳng định `geoRotate` không đổi; hint Upright không nhắc Straighten; `challenger` xem ở §8 |
| **Sàn undo ở controller đổi cả sidebar** (sidebar cũng gọi `beginStageSession` `PES:2827-2831`): trong Mask/Markup/Crop của iPad undo sẽ dừng ở lúc vào | cao | đề xuất áp cho mọi layout (một luật, như D15) — xác nhận khi duyệt plan; nếu không thì gate theo `isWideLayout` |
| **Curve rời stage ở mọi layout** (D11) đụng sidebar và FS-04.02 | chắc chắn | task 20 chụp iPad 13" + dump "không phần tử curve trong khung stage" |
| Straighten Tool: dấu góc (kéo xuống bên phải = +3,7°) phải khớp chiều quay của render `crop.straightenDegrees` | trung bình | test Domain cả hai dấu + chụp so trên sim |
| AC-6 offline iCloud khó dựng trên sim | cao | test Domain cho luật; phần "lỗi có lối ra, Back đóng" chụp tay trên máy thật hoặc sim không mạng |
| **Checkout chung với agent khác** (FS-03.14/15/16 cùng đụng `EditorToolPanels`, `EditorHealPanel`, `PhotoEditorController`) | cao | stage đúng đường dẫn, không `git add -A`/`stash`/`reset`; tách bố cục phone ra file mới ở task 8 để giảm vùng va chạm trong `PES` 3239 dòng |
| Hiệu năng danh sách Edit ~60 slider; đổi công cụ không được render lại ảnh | trung bình | `LazyVStack`, đổi công cụ chỉ đổi chrome (không `scheduleRender`); `perf-profiler` sau pha 1 |
| Phủ đỏ mờ 1,5s dùng `Task` hẹn giờ | thấp | policy thuần trả mốc thời gian; view dùng `TimelineView`/animation, huỷ khi rời mask (`swift-concurrency`) |
| Ảnh thử có mặt người | — | không dùng ảnh có mặt (luật repo); ô Face Skin/Eyes/Lips kiểm bằng dữ liệu tổng hợp |
| Quyền ảnh sim 26.5 | thấp | theo memory "sim photo permission on iOS 26" |
| Bỏ nút compare: người không biết giữ lâu | trung bình | "Show Original" cho VoiceOver; hỏi `ux-reviewer` về gợi ý lần đầu (spec §8) |

## 7. Tài liệu viết lại — cùng commit với AC làm nó sai

| Tài liệu | Đoạn (file:line) | Trong task |
|---|---|---|
| `DESIGN.md` §10.3 | `:281` "264pt = 185 + 54 + 25"; `:300`, `:309` "Slab 264pt" | 9 (AC-1) |
| `DESIGN.md` §10.3 | `:283` "Dải ≤5 chip chia đều, >5 cuộn"; `:287` bánh xe + accent; `:315` toast vs bánh xe; `:316` fade bánh xe; `:321-325` "Điện thoại (< 700pt) giữ nguyên cấu trúc" | 8 (AC-14) |
| `DESIGN.md` §10.3 | `:311` filmstrip 96/124 viền accent; §5 `:105` `r-track` chỉ Video Studio | 40 (AC-40) |
| `DESIGN.md` §10.3 | phủ đỏ mờ **1,5s** (token mới); `:319` curve chỉ sidebar → mọi layout | 32 (AC-31), 20 (AC-19) |
| FS-03.01 | §2 `:20`, §3 `:32`, §5 `:62-80`, §6 `:82` | 8, 9; bảng ⋯ ở 41 |
| FS-03.01b | §5 `:73` Upright 4 chip; §6 `:99` "crop chốt khi rời nhóm" | 26; 23 |
| FS-03.02 | §8 `:109`; §9 `:120` "giữ = Delete" | 37; 39 |
| FS-03.03 | §1 `:7` panel giữ cao; §5 `:46` nút before/after | 21; 8 |
| FS-03.05 | §2 `:22`, §3 `:43`, §6 `:129`, §7 `:141`; AC-17/21/22 `:165-170`. Tên "Mask n" (§3, §4, AC-18) **đã sửa** 2026-09-28 theo E4 — task 28 chỉ cập nhật cột chứng minh AC-18 | 27, 28–30, 32 |
| FS-03.09 / 09b | 09 §8 `:310,316`, §10 `:395`; 09b §2 `:20`, §3 `:34` | 8; 40 |
| FS-03.11 | §2 `:36` "cũng có trên bánh xe điện thoại" | 8 |
| FS-03.12 | Một câu `:7`, §3 `:26`, §4 `:40`, §6 `:71`; AC-10/11/13 `:105-108` | 8, 22, 37, 44 |
| FS-04.02 | Một câu `:6`, §1 `:12`, §4 `:47` curve đè ảnh | 20 |
| FS-05 README / FS-05.01 | README `:53` "Panel — dải lớp"; 01 §4 `:35`, §6 `:72`, §7 `:91` | 35, 36 |
| FS-03.13* | cột "Chứng minh bằng" từ ⚠️ chưa có → tên test thật; 13a §3 số D3. AC-12 (E1), 13a §3 (E2), 13b §3 + AC-23 (E3), 13c §2 (E4), 13d §2 + AC-40 (E5) **đã sửa** 2026-09-28 | mỗi task; 8 |
| FS-03.14 | đã sửa sẵn (`14-lightroom-preset-exchange.md:101`) | — |

Dòng `Tiến độ` của intent: kế hoạch này **không** sửa (lượt này chỉ được viết file plan); khi duyệt, commit đầu tiên
ghi `**chưa làm** (2026-09-28) — plan 2026-09-28-fs-03-13-iphone-editor-layout.md chờ duyệt, 45 task`, rồi mỗi task
cập nhật `**đang làm** — task k/45, x/45 AC xanh` theo `docs/PROCESS.md` §2.

## 8. Phản biện (điền sau khi chạy `challenger`)

| Phản đối | Trả lời / thay đổi |
|---|---|
| … | … |

## 9. Cách chứng minh là xong

- **Test đơn vị mới/sửa**: `EditorPanelLayoutTests` (344/264/315/+56, cố định phiên, pixel size, mục lục, More…;
  viết lại `thePhonePanelIsA264SlabOnA40PointGrid` và dòng đếm `EditorGroup.allCases == 15`), `EditorHistoryAndSummaryTests`
  (✕, sàn undo, ✓, curve ✕, transform ✕, cảnh báo bộ nhớ), `StraightenToolTests`, `MaskOverlayPolicyTests`,
  `MaskPhonePanelTests` (lưới, vẽ ngay, danh sách, subtract area), `MarkupPhonePanelTests` (danh sách dọc, radio căn lề,
  mọi mực). Chạy `/test` sau mỗi task, `Tools/gate` cuối pha.
- **Script `Tools/ui-drive` mới**: `iphone-editor-frame.json`, `iphone-edit-list.json`, `iphone-tool-sessions.json`,
  `iphone-transform.json`, `iphone-mask-list.json`, `iphone-heal-markup.json`, `iphone-presets-grid.json`,
  `iphone-batch-filmstrip.json`, `se-editor-fit.json`, `duo-cover-editor.json`. Chuyển tiếp (giữ-lâu, vòng Size, phủ
  đỏ mờ) chụp liên tục bằng `Tools/sim-shot` từ host.
- **Màn phải chụp** (`/screens`): Presets · Edit (đầu + mục lục mở + cuộn tới Detail) · Curve (ảnh dọc 315 và ngang
  344) · Transform (Straighten Tool, Upright) · Mask (lưới, hàng trên, danh sách, hàng cọ) · Heal · Markup (lưới, danh
  sách lớp, trang mực) · phiên nhiều ảnh (filmstrip, menu Sync, trong công cụ) · hộp xác nhận ✕ · tràn viền — trên
  **iPhone 17 iOS 26.5 và 18.6**, **SE 375**, **17 Pro Max 440** (băng + đảo), **Duo 27.1 màn ngoài** (`sim-shot … cover`),
  và **iPad 13" sidebar** cho AC-19, AC-31. Tên file theo `/screens`.
- **Agent ở giai đoạn Deploy**: `device-layout` (D3, SE, Pro Max, Duo — trước task 8 và cuối mỗi pha), `ios26-parity`
  (tập hành động hai nhánh), `iphone-ux-review` (tầm với ngón cái, cạnh vuốt, ✕/✓, giữ-xem-gốc), `duo-ux-review` (cột
  56, 326pt, gập/mở giữa phiên công cụ), `a11y-voiceover` (nhãn thanh công cụ, "Show Original", nhóm căn lề, danh
  sách mask/lớp, Dynamic Type trên hàng 40), `design-reviewer` (344/264/315, token 1,5s, accent chỉ Save, `r-track`),
  `hig-components` (hộp xác nhận, menu giữ lâu, danh sách kéo ≡), `component-consistency` (một kiểu hàng "▼ · + · ⋯"
  cho Mask và Markup, một kiểu hàng viên cho cọ/Heal/Pen), `copy-consistency` + `localization` (chuỗi mới, "Grading"),
  `ux-reviewer` (gợi ý lần đầu cho giữ-xem-gốc, Sync khi tràn viền), `perf-profiler` (danh sách dài, không render lại
  khi đổi công cụ), `swift-concurrency` + `memory-leak` (hẹn giờ phủ đỏ, snapshot phiên công cụ), `test-coverage`
  (mọi Domain mới), `challenger` (trước khi duyệt — điền §8).
- **Xong khi**: `/verify FS-03.13` chỉ được bằng chứng cho cả 45 AC (AC-24 phần Guided, AC-38/39 phần 14 ghi rõ là chờ
  spec kia), `Tools/gate` xanh, Stop hook không còn cảnh báo.
