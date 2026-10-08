# FS-12.15 — So sánh trước / sau

`FS-12.15` · tier D · `Features/VideoStudio/VideoStudioModel.swift` (giữ-để-xem-bản-gốc) · `VideoStudioCommandBand.swift` · `VideoViewerChrome.swift`
· nguồn intent [video-studio-canvas-chrome](../../_intents/2026-10-03-video-studio-canvas-chrome.md) (canvas hàng F7) · cập nhật 2026-10-04 (iPad kiểu Mac)

**Một câu:** đặt khung gốc cạnh khung đã grade — hai khung cạnh nhau hoặc một đường chia kéo được — trong lúc
vẫn phát, scrub và chỉnh look.

Look: [FS-12.06c](06c-photo-looks.md). Tầng màu: [FS-12.06](06-color-layer.md). Phím `\`: [FS-12.17b](17b-keyboard-and-pointer.md).
Board hàng F7: `F7_P_BeforeAfter` ([`docs/design/iphone/project/`](../../design/iphone/project/)) · `F7_IL_BeforeAfter`, `F7_IP_BeforeAfter` ([`docs/design/ipad/project/`](../../design/ipad/project/), kiểu Mac 2026-10-04) · `F7_DI_BeforeAfter`, `F7_DC_BeforeAfter` ([`docs/design/duo/project/`](../../design/duo/project/)).

## 1. Người dùng cần gì

Giữ-để-xem-bản-gốc chỉ cho thấy một trong hai, và tay đang giữ thì không kéo Amount được. Người chụp muốn thấy look
đang ăn vào khung **trong lúc** chỉnh, và thấy nó qua cả đoạn phim, không chỉ một khung đứng.

## 2. Phạm vi

**Có:** nút **Before and After**; hai chế độ mỗi máy; Before và After phát, scrub cùng một đồng hồ; After cập nhật
ngay khi chỉnh; **Swap sides** trên iPad dọc.

**Cố ý không có:**
- So với một phiên bản cũ của chính project (snapshot) — Undo đã làm việc đó.
- Xếp chồng trên/dưới trên iPhone — cần cao 452pt, khung chỉ có 226 (board F7_P).
- Ảnh hưởng lên file xuất — so sánh là trạng thái xem, không bao giờ tới export.

## 3. Before là gì

**Before bỏ:** look cả video và look riêng từng clip, Adjust, Color (de-log, node chain, mask, LUT), mọi overlay (chữ,
sticker, phụ đề [FS-12.14](14-captions.md)). **Before giữ:** cắt, trim, tốc độ, thứ tự, chuyển cảnh, hiệu ứng chuyển
động, xoay, tỉ lệ và nền, âm thanh.

- Đúng dòng chú thích của board: "Before drops the look, adjustments, color and overlays." Cùng nghĩa với giữ-để-xem-bản-gốc.
- **De-log cũng bị bỏ** (code hôm nay giữ nó). *Vì* nhãn là "Original clip": footage log phải hiện phẳng như máy quay ghi.
- Chỉ có **một** âm thanh — của After.

## 4. Màn hình (canvas hàng F7)

| Máy · board | Lối vào | Khi đang so sánh |
|---|---|---|
| iPhone 402×874 · `F7_P_BeforeAfter` | header panel Look: nút tròn 32 tại x 280, trái ✕ và ✓ | khung 402×226 giữ nguyên; đường chia trắng 2pt + tay nắm tròn 34 "Drag to compare" giữa chiều cao khung; mục **COMPARE** ngay dưới Amount: **Split · Hold to Compare** 181×30; dòng chú thích |
| iPad ngang 1376×1032 · `F7_IL_BeforeAfter` (kiểu Mac 2026-10-04) | nút tròn **44** cuối hàng phát dưới khung (x 956; khi pool gập x 945) — không còn viewer header | pool tự gập (capsule Media Pool hiện ở x 16); hai khung **448×252** tại y 160, x 33 và 497, cách nhau 16; segmented **Side by Side · Split** 280×36 tại (349, 84) trên hai khung; dòng "Both sides play and scrub together · 0:08.4" dưới khung (y 424); Show original ẩn khỏi capsule Undo · Redo |
| iPad dọc 1032×1376 · `F7_IP_BeforeAfter` | như iPad ngang (nút 44 ở x 960) | hai khung **458×258** đặt ngang tại y 223, x 28 và 502; segmented Side by Side · Split 280×36 tại (354, 84); dock 324 tiêu đề "Before and After · Clip 2", ba cột 312 **Look · Compare · Adjust**; Compare: segmented Side by Side · Split 312×36, **Swap sides ›** 312×44, dòng "Before shows · Original clip", chú thích |
| Duo trong 951×669 · `F7_DI_BeforeAfter` | nút tròn 36 tại (148, 12) **thay** Show original | hai khung **330×186** tại y 96 trong vùng khung 684×385, cách nhau 8; cột Look 264 giữ nguyên, thêm Side by Side · Split 112×28 dưới Amount; dòng "Both sides play together · 0:08.4" |
| Duo ngoài 466×678 · `F7_DC_BeforeAfter` | header panel Look, như iPhone | như iPhone, khung 382×215 |

- **Nhãn:** pill "Before" 64×22 nền đen 60% chữ trắng ở góc trên trái, pill "After" 56×22 nền trắng chữ đen ở góc
  trên phải, cách mép khung 10pt, chữ 11,5 bold. Board F7_P vẽ hai pill ở y 10 **của màn hình**, đè lên Back và
  Export — lấy y 70 (10pt trong khung), như ba board iPad/Duo; sửa board.
- **Màu nút** (chốt 2026-10-03): iPhone, Duo — bật = **nền trắng, glyph đen** (như ✓ Done cạnh nó); tắt = nền trắng
  10%, glyph trắng. iPad: nút tròn 44 trong hàng phát, nền trắng 14% (`pressed`) khi bật, trong suốt khi tắt. Accent chỉ ở Export (luật intent).
  Board F7_P và F7_DI đang vẽ glyph trắng trên nền trắng — sửa glyph sang đen; tiêu đề board DI bỏ chữ "(cam)".
- **iPhone:** không còn nút Show original ở băng trên (canvas). Giữ-để-xem là chế độ **Hold to Compare** trong
  COMPARE. **Hôm nay (2026-10-05):** iPhone và Duo ngoài chưa có lối so sánh nào — nút giữ-để-xem tạm trong tiêu
  đề Look đã bỏ (board F5_P_Looks không vẽ, người dùng chốt); nút 32 ở x 280 của spec này là lối vào duy nhất khi
  làm. *Vì* trên điện thoại mọi chỉnh màu đều nằm trong panel Look, nên so sánh nằm cùng chỗ.
- **Duo trong:** nút thay Show original nhưng **giữ lâu ≥ 0,3 s vẫn là xem bản gốc**. *Vì* Duo không còn chỗ nào
  khác cho cử chỉ đó, và luật "điện thoại đủ mọi chức năng" cấm làm mất nó.

## 5. Hành vi

- **Bật/tắt** không phải một bước undo và không lưu vào project. iPhone, Duo ngoài: đóng panel Look (✓ hay ✕) là
  tắt. iPad: nút ở hàng phát dưới khung bật/tắt bất kỳ lúc nào; tắt thì pool trở lại đúng trạng thái trước khi gập.
- **Một đồng hồ:** hai bên luôn cùng một khung — dừng thì lệch 0 khung, đang phát lệch ≤ 1 khung. Scrub, nhảy
  khung, kéo playhead đi cả hai.
- **After sống:** chạm ô look, kéo Amount, chỉnh Adjust/Color thì After đổi ở khung kế tiếp; Before không đổi.
- **Split:** mặc định 50%; kéo tay nắm 0–100% bề rộng khung, trái là Before. Vị trí giữ tới khi tắt so sánh.
  iPad ở Split dùng khung đơn cỡ thường, pool không gập.
- **Hold to Compare:** giữ ngón trên khung = cả khung là Before, nhả = After; không thêm bước undo.
- **Swap sides** (iPad dọc): After sang trái, Before sang phải, nhãn đi theo; giữ tới khi tắt.
- Chọn clip khác, chọn item khác trên timeline: so sánh vẫn bật. Export trong lúc so sánh: file chỉ có After.
- **Không có gì để so:** project không look, Adjust, Color, overlay → hai bên giống nhau, dòng dưới khung thành
  "No edits to compare yet." (iPhone: thay dòng chú thích COMPARE).
- **VoiceOver:** nút đọc "Before and After", trait selected khi bật; tay nắm là phần tử chỉnh được "Before, 50
  percent", vuốt lên/xuống ±10%; hai khung đọc "Before" và "After".

## 6. Chi phí khung hình

- Side by Side và Split vẽ **hai** phiên bản mỗi khung; Hold to Compare chỉ một. Mỗi bên render ở cỡ nó chiếm trên
  màn × scale, trần cạnh dài 1280 như preview ([FS-12.01 §8](01-render-and-export-pipeline.md)).
- Ngân sách vẫn **33,3 ms/khung** cho cả hai bên. Đổi Before chỉ đi tầng dựng khung hình rẻ, không dựng lại composition.

## 7. Dữ liệu

Không có trường mới trong project: chế độ, vị trí đường chia, swap là trạng thái màn hình, mất khi rời studio.

## 8. Đường hỏng

| Tình huống | Hành vi |
|---|---|
| Clip chỉ có trên iCloud, máy không mạng | cả hai bên hiện cùng trạng thái lỗi có chữ của FS-12 AC-13 |
| Không mạng, `.limited`, hết bộ nhớ | không áp dụng — không đọc thêm asset, không ghi file |
| Undo/Redo khi đang so sánh | After theo recipe mới; Before không đổi; so sánh vẫn bật |
| Máy không giữ 30 khung/giây khi vẽ hai bên | xem §10 |

## 9. Tiêu chí nghiệm thu

Project mẫu như [FS-12.14 §9](14-captions.md); cả video Moody Coast Amount 80 ([FS-12.06c](06c-photo-looks.md)), clip 2
có sticker và một chữ "GOLDEN HOUR", clip 2 hiệu ứng zoomIn.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | iPhone, panel Look mở, playhead 8,4 s | chạm Before and After | đường chia ở x 201 ±1 (50%); pill Before tại (10, 70), After tại (336, 70); mục COMPARE hiện, Split được chọn; số bước undo không đổi | ✅ `VideoBeforeAfterTests.phoneSplitGeometry` (đường chia x 201 ±1 trên khung 402), `exportIgnoresCompareState` (undo không đổi); route `video-compare-phone.json` (iPhone 17 26.5, `build/proofs/fs1215/phone-split.png`): nút tròn 32 trong tiêu đề Look trắng/glyph đen, đường trắng + tay nắm, pill Before trái · After phải trong khung (10pt), COMPARE Split · Hold to Compare, Split chọn |
| AC-2 | như AC-1 | đọc khung ở 8,4 s | nửa trái khớp khung render không look/Adjust/Color/overlay (≤ 1/255), **có** zoomIn; nửa phải khớp After; không sticker, không chữ ở nửa trái | ✅ `VideoBeforeAfterRenderTests.leftIsBeforeRightIsAfter` (compositor thật, một request: khung 640×180 = [Before | After], nửa trái khớp khung không grade ≤ 1/255, nửa phải sáng hơn); hiệu ứng chuyển động đi theo timing chung của hai bên (`beforeKeepsEffectsTransitionsAudio`); overlay không bao giờ nướng vào preview, lớp sống chỉ vẽ trên After |
| AC-3 | Split đang bật | kéo tay nắm tới x 100 | đường chia ở x 100 ±1; VoiceOver đọc "Before, 25 percent" | ✅ `VideoBeforeAfterTests.fractionFromDrag` (x 100 → 25%, kẹp 0–100%), `accessibilityValueReadsPercent` ("Before, 25 percent", vuốt ±10%); tay nắm là phần tử chỉnh được (`compareHandle`) |
| AC-4 | COMPARE = Hold to Compare | giữ khung 1 s rồi nhả | lúc giữ: cả khung là Before; sau nhả: After; recipe và số bước undo không đổi | ✅ `VideoBeforeAfterTests.holdNeverTouchesRecipeOrUndo` (giữ = Before, nhả = After, recipe và undo không đổi); ảnh `phone-hold.png` (Hold to Compare chọn) |
| AC-5 | so sánh đang bật trên iPhone | bấm ✓ của panel Look | so sánh tắt; mở lại Look thì nút ở trạng thái tắt | ✅ `VideoBeforeAfterTests.closingLookPanelTurnsCompareOff` (✓ và ✕ đều tắt; mở lại Look: tắt) |
| AC-6 | iPad ngang, pool đang mở | chạm Before and After | pool gập; hai khung 448×252 tại y 160, x 33 và 497; Side by Side được chọn; Show original vắng khỏi capsule Undo · Redo; chạm lần nữa: pool mở lại | ✅ route `video-compare-ipad.json` (iPad Pro 13" ngang, `build/proofs/fs1215/ipad-landscape-side-by-side.png`): pool gập, Side by Side · Split 280×36 trên sân khấu, hai khung ~446×251 ở x 32/497, Show original vắng khỏi capsule Undo · Redo, dòng "Both sides play and scrub together · 0:00.0"; chạm lần nữa pool mở lại (`ipad-landscape-off.png`, `VideoBeforeAfterTests.iPadLandscapeFrames` — pool trả đúng trạng thái trước). Số y đo lại ở AC-14 |
| AC-7 | iPad ngang, Side by Side | phát 10 s trên máy thật | mọi lần lấy mẫu hai bên cùng số khung (dừng: lệch 0; phát: ≤ 1); ≤ 3 khung rơi trong 10 s | ⚠️ chưa có — máy thật |
| AC-8 | Side by Side, Amount 80 | kéo Amount về 40 trong một lần kéo | After đổi, Before giữ nguyên từng pixel; undo +1 (chỉ cho Amount) | ✅ `VideoBeforeAfterRenderTests.amountDragChangesOnlyAfter` (Amount 80 → 40: nửa Before giống từng pixel, nửa After đổi); Amount vẫn là bước undo của look |
| AC-9 | iPad dọc, Side by Side | chạm Swap sides | After ở x 28, Before ở x 502; nhãn đổi theo | ✅ `VideoBeforeAfterTests.swapPutsAfterLeft` (After x 28, Before x 502, 458 rộng); dock dọc Look · Compare · Adjust với Swap Sides (`VideoCompareDock`) — ảnh chờ AC-14 |
| AC-10 | project không look, Adjust, Color hay overlay | bật so sánh | hai bên giống từng pixel; dòng dưới khung "No edits to compare yet." | ✅ `VideoBeforeAfterTests.nothingToCompareWhenNoLookAdjustColorOverlay` (kể cả de-log là có gì để so); nút luôn dùng được, dòng dưới khung / dòng COMPARE thành "No edits to compare yet." |
| AC-11 | so sánh đang bật (Split 30%) | Export | file xuất không có đường chia, không pill; khung 8,4 s khớp After | ✅ `VideoBeforeAfterTests.exportIgnoresCompareState` (Split 30% bật: recipe xuất giống hệt, không khoá nào của so sánh trong JSON); `compareStateIsNotUndoable` |
| AC-12 | Duo trong, panel Look mở | chạm nút tại (148, 12); rồi giữ nó 1 s | chạm: hai khung 330×186 tại y 96; giữ: cả hai khung hiện Before tới khi nhả | ⚠️ một phần — stand-in Duo trong (`-VideoStudioStandIn duoInner`, route `video-f4f7f8-duo-inner-standin.json`, `build/proofs/fs1215/F7_DI-standin-side-by-side.png`): đĩa ở (148,12) trắng/glyph đen khi bật, hai khung cạnh nhau, "Both sides play together · 0:00.0"; `design-board compare` F7_DI: không lệch ở hai khung; giữ ≥ 0,3 s = Before trên cả hai (`VideoDuoCompareDisc`, `setShowsOriginal` với stage pair) — chưa chụp lúc giữ; Duo thật chỉ mở được bằng tay |
| AC-13 | footage log, de-log S-Log3 bật | bật so sánh | nửa Before phẳng như nguồn chưa de-log (≤ 1/255 so với khung nguồn) | ✅ `VideoBeforeAfterTests.beforeDropsDeLog`, `VideoBeforeAfterRenderTests.beforeDropsDeLogInPixels` (S-Log3 bật: nửa Before = khung nguồn ≤ 1/255, After de-log); giữ-để-xem dùng cùng `beforeRecipe` |
| AC-14 | iPhone 402×874 · iPad 1376×1032 · 1032×1376 · Duo trong 951×669 · Duo ngoài 466×678 | dựng đúng trạng thái từng board | khớp `F7_P_BeforeAfter`, `F7_IL_BeforeAfter`, `F7_IP_BeforeAfter`, `F7_DI_BeforeAfter`, `F7_DC_BeforeAfter` lệch ≤ 2pt (sau khi sửa pill F7_P); không control dưới góc bo | ⚠️ một phần — `design-board compare` 2026-10-06: **F7_IL** hai khung 448×252 ở y 160 (x 30/494, lệch −3 so với board 33/497), Side by Side · Split ở (348, 86), nút ở hàng phát dời theo khung After; **F7_DI** hai khung khớp; **F7_DC** (Duo thật) COMPARE Split · Hold 173 rộng, nút so sánh trái ✕ ✓ (board DC không vẽ ✕ ✓ nên x lệch), board vẽ tay nắm 17 từ 2026-10-08 nhưng app mở panel Look ở y 300 phủ timeline (FS-12.07b §4), board ở 334 dưới dải tổng quan (FS-12.06c §2) — chờ người dùng chọn, REVIEW_QUEUE; **F7_P** nút 32 ở x 280, Split · Hold 181×30 sau khi chỉnh; **F7_IP** chưa đo (driver không xoay iPad). Ảnh `build/proofs/fs1215/*` |
| AC-15 | iPhone và Duo trong, rồi iPad ngang | bật rồi tắt so sánh, đọc màu nút | iPhone/Duo bật: nền trắng, glyph đen; tắt: nền trắng 10%, glyph trắng; iPad bật: nền trắng 14%; nút không bao giờ mang #EB9526 | ✅ code: iPhone/Duo ngoài bật = nền trắng glyph đen, tắt = trắng 10% (`VideoLookCompareButton`), Duo trong cùng luật (`VideoDuoCompareDisc`), iPad nền trắng 14% khi bật (`VideoBeforeAfterButton`, `openCellFill`); không chỗ nào dùng accent; ảnh `phone-split.png`, `ipad-landscape-side-by-side.png` |

**Chưa chứng minh được:** AC-7 (máy thật), AC-12 (Duo trong — ảnh), AC-14 (parity).

## 10. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Hai lượt grade mỗi khung (cộng chuyển cảnh, cộng Clarity…Dehaze của 06c) vượt 33,3 ms | đo AC-7 trước `/plan`; không đạt thì Before render ở nửa độ phân giải khi đang phát, đủ khi dừng |
| Bỏ de-log khỏi Before là đổi hành vi hôm nay | ghi ở đây; giữ-để-xem-bản-gốc dùng cùng định nghĩa nên hai lối vào không lệch nhau |
