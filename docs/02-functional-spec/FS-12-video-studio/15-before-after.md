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
  COMPARE. *Vì* trên điện thoại mọi chỉnh màu đều nằm trong panel Look, nên so sánh nằm cùng chỗ.
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
| AC-1 | iPhone, panel Look mở, playhead 8,4 s | chạm Before and After | đường chia ở x 201 ±1 (50%); pill Before tại (10, 70), After tại (336, 70); mục COMPARE hiện, Split được chọn; số bước undo không đổi | ⚠️ chưa có |
| AC-2 | như AC-1 | đọc khung ở 8,4 s | nửa trái khớp khung render không look/Adjust/Color/overlay (≤ 1/255), **có** zoomIn; nửa phải khớp After; không sticker, không chữ ở nửa trái | ⚠️ chưa có — test compositor |
| AC-3 | Split đang bật | kéo tay nắm tới x 100 | đường chia ở x 100 ±1; VoiceOver đọc "Before, 25 percent" | ⚠️ chưa có |
| AC-4 | COMPARE = Hold to Compare | giữ khung 1 s rồi nhả | lúc giữ: cả khung là Before; sau nhả: After; recipe và số bước undo không đổi | ⚠️ chưa có |
| AC-5 | so sánh đang bật trên iPhone | bấm ✓ của panel Look | so sánh tắt; mở lại Look thì nút ở trạng thái tắt | ⚠️ chưa có |
| AC-6 | iPad ngang, pool đang mở | chạm Before and After | pool gập; hai khung 448×252 tại y 160, x 33 và 497; Side by Side được chọn; Show original vắng khỏi capsule Undo · Redo; chạm lần nữa: pool mở lại | ⚠️ chưa có |
| AC-7 | iPad ngang, Side by Side | phát 10 s trên máy thật | mọi lần lấy mẫu hai bên cùng số khung (dừng: lệch 0; phát: ≤ 1); ≤ 3 khung rơi trong 10 s | ⚠️ chưa có — máy thật |
| AC-8 | Side by Side, Amount 80 | kéo Amount về 40 trong một lần kéo | After đổi, Before giữ nguyên từng pixel; undo +1 (chỉ cho Amount) | ⚠️ chưa có |
| AC-9 | iPad dọc, Side by Side | chạm Swap sides | After ở x 28, Before ở x 502; nhãn đổi theo | ⚠️ chưa có |
| AC-10 | project không look, Adjust, Color hay overlay | bật so sánh | hai bên giống từng pixel; dòng dưới khung "No edits to compare yet." | ⚠️ chưa có |
| AC-11 | so sánh đang bật (Split 30%) | Export | file xuất không có đường chia, không pill; khung 8,4 s khớp After | ⚠️ chưa có — smoke test export |
| AC-12 | Duo trong, panel Look mở | chạm nút tại (148, 12); rồi giữ nó 1 s | chạm: hai khung 330×186 tại y 96; giữ: cả hai khung hiện Before tới khi nhả | ⚠️ chưa có — `Tools/ui-drive` + `Tools/sim-shot` |
| AC-13 | footage log, de-log S-Log3 bật | bật so sánh | nửa Before phẳng như nguồn chưa de-log (≤ 1/255 so với khung nguồn) | ⚠️ chưa có |
| AC-14 | iPhone 402×874 · iPad 1376×1032 · 1032×1376 · Duo trong 951×669 · Duo ngoài 466×678 | dựng đúng trạng thái từng board | khớp `F7_P_BeforeAfter`, `F7_IL_BeforeAfter`, `F7_IP_BeforeAfter`, `F7_DI_BeforeAfter`, `F7_DC_BeforeAfter` lệch ≤ 2pt (sau khi sửa pill F7_P); không control dưới góc bo | ⚠️ chưa có — agent `design-parity` |
| AC-15 | iPhone và Duo trong, rồi iPad ngang | bật rồi tắt so sánh, đọc màu nút | iPhone/Duo bật: nền trắng, glyph đen; tắt: nền trắng 10%, glyph trắng; iPad bật: nền trắng 14%; nút không bao giờ mang #EB9526 | ⚠️ chưa có — agent `design-reviewer` |

**Chưa chứng minh được:** AC-1 tới AC-15. AC-7 cần máy thật.

## 10. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Hai lượt grade mỗi khung (cộng chuyển cảnh, cộng Clarity…Dehaze của 06c) vượt 33,3 ms | đo AC-7 trước `/plan`; không đạt thì Before render ở nửa độ phân giải khi đang phát, đủ khi dừng |
| Bỏ de-log khỏi Before là đổi hành vi hôm nay | ghi ở đây; giữ-để-xem-bản-gốc dùng cùng định nghĩa nên hai lối vào không lệch nhau |
