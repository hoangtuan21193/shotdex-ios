# FS-03.13a — Khung, băng trên, thanh 6 công cụ

`FS-03.13a` · tier D · `Features/Editing/EditorChromeModel.swift` · cập nhật 2026-09-28

**Một câu:** từ trên xuống — băng lệnh gọn hai bên Dynamic Island với Save luôn hiện, ảnh, panel cao theo phần
đen thật của ảnh, và thanh 6 công cụ cố định; vào công cụ nào cũng huỷ được bằng ✕.

Tổng quan và các quyết định đã chốt: [FS-03.13](13-iphone-editor-layout.md). Lưới hàng, chip, slider giữ
[FS-03.12](12-phone-panel-grid.md) §4–5.

## 1. Ba tầng dọc

| Tầng | Cao | Nội dung |
|---|---|---|
| Băng trên | T = lớn hơn của 48 và vùng an toàn trên (như [FS-03.01 §2](01-scope-and-panel.md#2-ba-tầng-theo-chiều-dọc)) | cụm trái · cụm phải |
| Filmstrip | 56, chỉ khi sửa nhiều ảnh và không ở trong công cụ | [13d §2](13d-presets-batch-devices.md#2-sửa-nhiều-ảnh) |
| Ảnh | phần còn lại, vừa khung | stage |
| Panel | 344 · 264 · 315 (§2) = vùng thông số + **54** thanh công cụ + **25** vùng home | tấm đặc, bo 22 hai góc trên |

Vùng thông số vì thế cao **265** (panel 344), **185** (264) hoặc **236** (315): 6 hàng slider, 4 hàng, hoặc đồ thị Curve.

## 2. Chiều cao panel

Ký hiệu: H cao màn · T băng trên · F filmstrip (56 hoặc 0) · W rộng stage · a = rộng ÷ cao của ảnh **sau crop đã lưu**.

- **Panel = 344 khi W ÷ a ≤ H − T − F − 344, ngược lại 264.** Nghĩa là 80pt thêm cho panel lấy **toàn bộ từ phần
  đen**: ảnh không nhỏ đi pt nào so với panel 264.
- iPhone 17 (402×874, T ≈ 62): stage với 344 cao 468 → 3:2 (268), 16:9 (226), 1:1 (402) được 344; 4:5 (503),
  3:4 (536), 9:16 được 264. SE (375×667, T 48): stage 275 → 3:2 được 344, 1:1 được 264.
- a đọc từ **kích thước pixel của asset + crop đã lưu**, không chờ tải ảnh: ảnh chỉ có trên iCloud vẫn ra đúng
  panel ngay khi mở.
- **Cố định trong phiên sửa một ảnh**: crop trong Transform không đổi panel; mở lại ảnh thì tính lại.
- **Ngoại lệ duy nhất — Curve**: panel 264 tạm cao **315** khi mở Curve, ảnh vừa khung lại; ✕ hoặc ✓ trả về 264.
  Panel 344 đã đủ cho đồ thị, không đổi.
- **Sửa nhiều ảnh**: panel tính theo **ảnh đang mở**; lướt filmstrip giữa ảnh ngang và ảnh dọc thì panel đổi 80pt.
- **Vào công cụ khi đang sửa nhiều ảnh**: filmstrip ẩn, panel nhận 56 (344 → 400, 264 → 320), ảnh đứng yên.
- Duo màn ngoài không dùng luật này: danh sách cố định 300 ([13d §3](13d-presets-batch-devices.md#3-duo-màn-ngoài)).

## 3. Băng trên

- **Cụm trái 120**: Back · Undo · Redo — nút tròn 36, cách nhau 4, đĩa trắng 10%.
- **Cụm phải 120**: histogram thu nhỏ 40×28 · ⋯ 36 · **Save 36** (đĩa accent, glyph đen, icon Lưu của `DESIGN.md` §8).
- Hàng nút cách mép trên 11. Khoảng cách tới mép trái / phải: xem ⚠️ dưới đây.
- **Save luôn hiện**, kể cả trong công cụ: chạm = áp công cụ (như ✓) rồi mở sheet lưu. Huỷ sheet thì ở lại Edit.
- **Không còn nút compare.** Giữ lâu trên ảnh ≥0,3s = xem ảnh gốc, **ở Edit và Presets**; nhả tay là về bản đang sửa.
  Trong Mask / Heal / Markup ngón đặt yên là đầu một nét ([FS-03.05b §7](05b-mask-painting-and-zoom.md)).
- Stage có hành động VoiceOver **"Show Original"** — lối so sánh duy nhất cho người không giữ được.
- **⋯ gọn**, theo thứ tự: History · Copy Edits · Paste Edits (khi clipboard có) · Fill Screen / Fit Photo · Revert to
  Original · Reset All · gọi lại bản đã lưu / đổi nguồn (cuối cùng, chỉ khi ảnh có). Revert, Reset All giữ FS-03.01 §3.
- **Undo / Redo không lặp trong ⋯**: đã có ở cụm trái băng trên và chạm hai ngón (chốt E2).
- Sync **không** ở ⋯: chỉ ở cuối filmstrip ([13d §2](13d-presets-batch-devices.md#2-sửa-nhiều-ảnh)).
- Rotate / Flip rời ⋯ vào Transform; phủ đỏ / đảo vùng rời ⋯ vào hàng Mask và ⋯ của mask.

> ⚠️ **CẦN QUYẾT D3 — chờ số đo:** hai cụm cách mép màn **10** (canvas, kiểm trên khung có mask của `Tools/sim-shot`)
> hay **20** (FS-03.01 §3, nút 34 cách 4, cụm 110). Quyết khi có số đo đảo thật (câu đo 1 ở tổng quan).

## 4. Thanh 6 công cụ

- 54pt, **6 ô chia đều**, không cuộn: **Presets · Edit · Transform · Mask · Heal · Markup**. Ô: icon 22 · nhãn
  10,5pt (token nhãn tab) · vạch 16×2. Không khung bo từng ô.
- Chưa chọn = trắng 38%, chữ thường; đang chọn = trắng, chữ đậm, vạch trắng. Không accent.
- Thanh này **thay hẳn bánh xe nhóm** ở mọi layout không sidebar, kể cả Duo màn ngoài; không còn bánh xe nào.
- Mở editor là **Edit**. Chạm Presets / Edit đổi ngay, không ✕ / ✓.
- Chạm Transform / Mask / Heal / Markup = **vào công cụ**: thanh đổi thành **✕ · tên · ✓** (§5).
- Chạm đôi ảnh = tràn viền như hôm nay: ẩn băng, panel và thanh.
- Toast đậu **trên** panel, không đè thanh ([`DESIGN.md` §10.3](../../../DESIGN.md)).

## 5. Vào và ra một công cụ

- Thanh công cụ thành: **✕** tròn 38 (đĩa trắng 10%) · **tên công cụ** 14pt đậm ở giữa · **✓** 42×38 bo 12, nền
  trắng, glyph đen.
- Đang trong công cụ thì năm công cụ kia không chạm được: muốn sang Mask phải ✓ hoặc ✕ trước (thêm 1 chạm, đã chốt).
- **✓** = áp, về Edit (như Apply ở [FS-03.09 §5b2](09-wide-screen-and-batch-editing.md)). Không thêm, không gộp bước lịch sử.
- **✕** = trả recipe và độ sâu lịch sử về lúc vào công cụ, về Edit. Thay luật "rời Crop là áp" của FS-03.01b §6.
- ✕ **hỏi xác nhận khi phiên công cụ có ≥1 thay đổi**: hộp thoại hệ thống "Discard changes to ‹tên công cụ›?" với nút
  phá huỷ **"Discard Changes"** (cùng chữ với hộp thoại bỏ phiên sửa hiện có); 0 thay đổi thì ✕ chạy ngay.
  ✕ đã xác nhận không Redo lại được.
- Mọi thao tác trong công cụ vào lịch sử **từng bước như hôm nay** (một nét, một vết, một cú kéo = một bước).
- **Undo trong công cụ dừng ở lúc vào**: về tới đó thì nút Undo mờ. Muốn lùi bước trước đó phải ✓ hoặc ✕ trước —
  vì ✕ và Undo phải cùng một mốc.
- **Undo sau ✓** lùi bước cuối của công cụ vừa áp; panel ở lại Edit, không mở lại công cụ.

## 6. Trạng thái

| Trạng thái | Điều kiện | Hiển thị |
|---|---|---|
| đang tải | ảnh iCloud chưa về | băng, thanh, panel đúng cao ngay (§2); vùng ảnh là trạng thái tải của FS-03 |
| lỗi tải | iCloud không phản hồi | thông báo + lối ra như hôm nay; thanh công cụ vẫn bấm được Back |
| Edit / Presets | mặc định | thanh 6 công cụ |
| trong công cụ | Transform / Mask / Heal / Markup | ✕ · tên · ✓; Save vẫn hiện |
| tràn viền | chạm đôi | chỉ ảnh (+ thẻ histogram nếu mở) |
| thiếu bộ nhớ | hệ thống báo | nhả cache theo NF-02; phiên công cụ, nét, lịch sử còn nguyên |

## 7. Tiêu chí nghiệm thu

Máy: iPhone 17 (402×874) iOS 26.5 và 18.6; SE 375×667 khi ghi rõ. Script `Tools/ui-drive` dưới đây chưa tồn tại.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | ảnh 6000×4000 (3:2), iPhone 17 | mở editor | panel 344, ảnh 402×268, vùng thông số hiện 6 hàng slider | ⚠️ chưa có — `EditorPanelLayoutTests.phonePanelIs344OnlyWhenTheExtraIsLetterbox` + `iphone-editor-frame.json` |
| AC-2 | ảnh 4000×5000 (4:5), iPhone 17 | mở editor | panel 264, ảnh cao 503, 4 hàng slider | ⚠️ chưa có — cùng test (ca 4:5) |
| AC-3 | ảnh 1:1 | tính panel trên 402×874 và 375×667 | 344 trên iPhone 17 (402 ≤ 468), 264 trên SE (375 > 275) | ⚠️ chưa có — cùng test (ca biên) |
| AC-4 | ảnh 3:2, panel 344, trong Transform | chọn 4:5 rồi ✓ | panel vẫn 344 | ⚠️ chưa có — `EditorPanelLayoutTests.phonePanelStaysFixedForTheSession` |
| AC-5 | ảnh 3:4, panel 264 | Edit → chạm "Edit Curve" | panel 315, ảnh vừa khung lại; ✓ trả panel về 264 | ⚠️ chưa có — `iphone-edit-list.json` + dump |
| AC-6 | ảnh chỉ có trên iCloud, máy offline, ảnh 3:2 | mở editor | panel 344 trước khi ảnh tải; lỗi tải có lối ra; Back đóng editor | ⚠️ chưa có — `EditorPanelLayoutTests.panelHeightNeedsOnlyAssetPixelSize` + ảnh chụp tay |
| AC-7 | Transform mở, đã chọn 1:1 | chạm Save | sheet lưu mở; recipe có crop 1:1; huỷ sheet → ở Edit, crop 1:1 còn | ⚠️ chưa có — `iphone-tool-sessions.json` |
| AC-8 | Heal, vào lúc có 0 vết, thêm 3 vết | chạm ✕ rồi xác nhận | hộp xác nhận hiện; sau xác nhận 0 vết, độ sâu lịch sử bằng lúc vào, thanh về 6 công cụ, Edit sáng. Vào Heal rồi ✕ ngay: không hỏi | ⚠️ chưa có — `EditorHistoryAndSummaryTests.cancelRestoresTheEntryRecipeAndDepth` + `iphone-tool-sessions.json` |
| AC-9 | Mask Brush, 3 nét, rồi ✓ | Undo một lần | còn 2 nét; panel vẫn là Edit | ⚠️ chưa có — `EditorHistoryAndSummaryTests.undoAfterApplyStepsBackOneStroke` |
| AC-10 | Exposure +1,00, rồi vào Mask Brush, vẽ 2 nét | Undo 3 lần | sau lần 2: 0 nét, nút Undo mờ; lần 3 không đổi gì; Exposure vẫn +1,00 | ⚠️ chưa có — `EditorHistoryAndSummaryTests.undoInsideAToolStopsAtEntry` |
| AC-11 | Edit, Exposure +1,00 | giữ ảnh 1,0s rồi nhả; lặp lại ở Presets với Velvia | lúc giữ ảnh là bản gốc (histogram khớp gốc), nhả là bản sửa, ở cả Edit và Presets; ở Mask Brush cùng cú giữ vẽ 1 dấu, không hiện gốc | `ShotDexUITests/scripts/iphone-tool-sessions.json` + chụp lúc giữ (`hold-1` Edit: ảnh gốc, nút so sánh sáng; `hold-2` Presets; `hold-3` Mask Brush: con trỏ cọ, ảnh vẫn là bản sửa; iPhone 17 26.5; slider đổi là Contrast +0,74 thay Exposure +1) |
| AC-12 | VoiceOver bật | dump băng trên, thanh, stage | nhãn Back · Undo · Redo · RGB histogram · More editor actions · Save · Cancel · Apply (nhãn histogram và ⋯ theo code — chốt E1); stage có hành động "Show Original" | ⚠️ chưa có — dump `iphone-editor-frame.json` |
| AC-13 | một ảnh, clipboard rỗng, không có bản đã lưu | mở ⋯ | đúng 5 mục: History · Copy Edits · Fill Screen · Revert to Original · Reset All. Phiên 7 ảnh: ⋯ vẫn không có mục Sync | ⚠️ chưa có — dump `iphone-editor-frame.json` + `iphone-batch-filmstrip.json` |
| AC-14 | lần lượt Presets, Edit, Transform, Mask, Heal, Markup, iOS 26.5 và 18.6 | chụp từng màn | 0 px accent ngoài Save; tập hành động hai nhánh như nhau; nhãn "Transform" không bị cắt trên SE 375 | ⚠️ chưa có — `Tools/accent-check` + `se-editor-fit.json` + agent `ios26-parity` |

Thiếu bộ nhớ: AC-43 · Duo màn ngoài: AC-44, AC-45 — ở [13d](13d-presets-batch-devices.md#4-tiêu-chí-nghiệm-thu).

**Chưa chứng minh được:** AC-1…AC-14 — chưa có code.
