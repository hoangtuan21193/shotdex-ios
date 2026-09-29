# FS-03.13b — Edit và Transform trên iPhone

`FS-03.13b` · tier D · `Features/Editing/EditorToolPanels.swift` · cập nhật 2026-09-28

**Một câu:** Edit là **một** danh sách slider cuộn dọc có nhãn nhóm dính và mục lục để nhảy; Transform thay Crop,
gộp Crop · Straighten · Upright · Geometry vào một danh sách, có Straighten Tool kéo theo chân trời.

Khung và ✕ / ✓: [13a](13a-chrome-and-toolbar.md). Thông số từng nhóm làm gì: [FS-03.01b](01b-adjustments-and-crop.md).

## 1. Edit: một danh sách dài

- Mọi nhóm nối nhau trong **một** danh sách cuộn dọc, thứ tự của danh mục thông số: **Light · Curve · Color ·
  Color Mix · Point Color · Grading · Effects · Detail · Optics** (9 nhóm hôm nay). Geometry rời Edit vào Transform.
- **Hai mô hình nhóm**: phone giữ 9 nhóm phẳng — danh sách đằng nào cũng dài, mục lục 9 dòng ngắn hơn 5 thẻ lồng;
  sidebar giữ 5 nhóm của [FS-03.09 §10](09-wide-screen-and-batch-editing.md).
- Nhóm màu theo vùng tối / trung / sáng tên **Grading** ở nhãn nhóm, mục lục và chip (chip "Grade" hôm nay đổi theo).
- Mỗi nhóm mở bằng nhãn IN HOA 26pt (11pt đậm, trắng 45%); **nhãn của nhóm đang ở đầu vùng cuộn dính trên cùng**
  dạng "LIGHT ▼" (trắng 70%) + đường kẻ 1pt, nền panel che hàng cuộn bên dưới.
- **Chạm nhãn dính → mục lục** trong panel: mỗi nhóm một mục, chạm một mục là cuộn tới nhãn nhóm đó ở đầu vùng
  cuộn và đóng mục lục. Mục lục dựng từ danh sách nhóm, không viết tay 9 tên — FS-03.15 thêm nhóm thì mục lục tự có.
- **Nhớ chỗ cuộn**: rời Edit (sang Presets, vào một công cụ) rồi quay lại thì danh sách ở đúng vị trí cũ. Chỗ cuộn là
  trạng thái của phiên, không vào recipe, không vào lịch sử.
- Nhóm có dải chọn (Color Mix, Point Color, Grading) đặt dải chọn **ngay dưới nhãn nhóm**, trong danh sách; dải chọn ≤6
  mục chia đều ([FS-03.12 §4](12-phone-panel-grid.md#4-chip-và-dải-chọn)). Point Color giữ luật có / chưa có điểm.
- Luật cử chỉ slider giữ [FS-03.03 §2](03-gestures-compare-and-undo.md#2-tranh-chấp-cử-chỉ): cuộn dọc và kéo slider
  phân xử trong 8pt đầu.

## 2. Curve trong panel

- Curve là **một hàng sau Light**: nhãn "Curve" · 4 chấm kênh 8pt (trắng, đỏ, xanh lá, xanh dương) · chip **Edit Curve**.
- Chạm Edit Curve = vào công cụ con **✕ · Curve · ✓**: vùng thông số thành đồ thị vuông **220×220** bên trái, cột
  phải là chip kênh RGB · Red · Green · Blue (chia dọc, cao 30, cột rộng tối thiểu 120 và lấy phần bề rộng còn lại — 138 trên 402; tên giữa chip, chấm màu 10pt ghim mép trái), chip Reset và hint
  *"Tap the line to add a point. Drag to move it, double-tap to remove it."*
- Region (parametric) và các preset hình dạng không có chỗ trong vùng này: ở ⋯ → **Curve Type** / **Preset Shapes**.
  Region đổi vùng thành bảy slider, có chip Point · Region ở đầu để quay lại.
- Ảnh dọc (panel 264): panel tạm 315 ([13a §2](13a-chrome-and-toolbar.md#2-chiều-cao-panel)). Ảnh ngang: 344 đủ chỗ.
- **Curve luôn trong panel, ở mọi layout** — kể cả sidebar iPad / Duo màn trong; không còn lớp curve đè stage.
  Ảnh không bị che nên vẫn thấy kết quả lúc kéo.
- ✕ trả curve về lúc mở; ✓ về danh sách Edit, đúng chỗ hàng Curve. Mỗi cú kéo điểm là một bước lịch sử ([FS-04](../FS-04-color-mixer-point-grading/README.md), quy tắc chung).

## 3. Transform

Một danh sách cuộn dọc có nhãn dính và mục lục như Edit, bốn nhóm theo thứ tự:

| Nhóm | Hàng |
|---|---|
| CROP | chip **Original · Free · 1:1 · 4:5 · More…** (chia đều) · chip **Rotate · Flip · Reset** |
| STRAIGHTEN | slider **Angle** (−45°…45°, mốc 0°) · chip **Straighten Tool · Auto** |
| UPRIGHT | chip **Off · Auto · Level** / **Vertical · Full · Guided** (hai hàng 3 + 3) · hint · chip **Clear Guides** (chỉ khi Guided) |
| GEOMETRY | Vertical · Horizontal · Rotate · Aspect · Scale · Offset X · Offset Y · công tắc Constrain Crop |

- **More…** mở menu các tỉ lệ còn lại, dựng từ danh sách tỉ lệ trừ bốn cái đã hiện (hôm nay: 4:3 · 3:2 · 16:9 · 9:16).
- Khung cắt, tay nắm và ảnh thu 30pt mỗi bên giữ [FS-03.01b §6](01b-adjustments-and-crop.md#6-crop); crop **không
  còn chốt khi rời nhóm** — ✓ chốt, ✕ bỏ.
- **Straighten Tool** (bật = chip nền trắng 20%): **một ngón** kéo trên ảnh vẽ một đường thước; nhấc tay thì Angle
  đặt sao cho đường đó nằm ngang, trong kẹp ±45°, **một** bước lịch sử. Hai ngón vẫn zoom / pan. Đường ngắn hơn
  8pt là chạm, không xoay. Hint: *"Drag a line along something that should be level, like the horizon or a table edge."*
- Đường lệch **quá 45° so với ngang** (cột nhà, thân cây) được **dựng đứng thẳng**, như Lightroom và như Guided.
- **Auto** của Straighten chạy phân tích Level của Upright ([FS-03.01b §5](01b-adjustments-and-crop.md#5-upright)),
  **ghi vào Angle của Straighten** (góc khung crop), không ghi Geometry Rotate (chốt E3).
  - *Vì* Straighten thuộc crop, không theo Copy Edits / Sync; Geometry đi theo look. Upright Level vẫn ghi Geometry.
  - Không thấy đường thẳng thì hàng ghi *"No straight lines to work from"* 3s, không đổi gì.
- **Guided**: một ngón vẽ tối đa **4** đường theo cạnh phải thẳng; hint đếm *"2 of 4 drawn."*; đường thứ 5 không vẽ.
  Phép nắn theo guide và Auto / Aspect / Constrain Crop thuộc [FS-03.15](15-lightroom-parameter-parity.md).
- **Upright hai hàng 3 + 3**, mỗi chip ~120pt trên 402, ~111 trên 375: "Vertical" (~66pt) không bị cắt, không cuộn ngang.
- **Chưa có thì không hiện**: Upright Auto, Guided, Aspect, Constrain Crop không hiện tới khi FS-03.15 land, không nút
  mờ. Thứ tự giữ chỗ để chúng hiện đúng vị trí; chip Upright còn lại dồn theo thứ tự, 3 chip mỗi hàng.

## 4. Trạng thái

| Trạng thái | Điều kiện | Hiển thị |
|---|---|---|
| Edit mặc định | mở editor | đầu danh sách, nhãn dính "LIGHT ▼" |
| mục lục mở | chạm nhãn dính | danh sách nhóm trong panel; chạm ngoài mục lục (trong panel) đóng nó |
| Curve | chạm Edit Curve | ✕ · Curve · ✓, đồ thị trong panel |
| Transform | chạm Transform | ✕ · Transform · ✓, khung cắt trên ảnh, nhãn dính "CROP ▼" |
| Straighten Tool bật | chạm chip | một ngón trên ảnh vẽ thước, khung cắt không nhận kéo |
| Guided | chip Guided | một ngón vẽ guide, đếm n of 4 |

## 5. Tiêu chí nghiệm thu

Máy: iPhone 17 iOS 26.5 và 18.6; ảnh 3:2 (panel 344) nếu không ghi khác.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-15 | Edit, danh sách ở đầu | cuộn tới khi nhãn COLOR qua đầu vùng cuộn | nhãn dính đọc "COLOR ▼" | `iphone-edit-list.json` 2-scrolled (nhãn dính "GRADING ▼", bánh xe theo) · nhãn dính đọc từ `scrollPosition(id:)` |
| AC-16 | Edit | chạm "LIGHT ▼" | mục lục có đúng các nhóm của danh mục, mỗi nhóm một lần, đúng thứ tự (9 hôm nay), có "Grading", không có "Grade" | `EditorPanelLayoutTests.phoneIndexListsEveryEditGroupOnce` (11 nhóm hôm nay: 9 + Lens Blur + Calibration của FS-03.15) · `iphone-edit-list.json` 3-index |
| AC-17 | mục lục mở | chạm Detail | nhãn DETAIL ở đầu vùng cuộn (±1pt), nhãn dính "DETAIL ▼", mục lục đóng | `iphone-edit-list.json` 3-index → 4-detail (nhãn dính "DETAIL ▼", mục lục đóng) |
| AC-18 | Edit cuộn tới Detail | chạm Presets rồi Edit | nhãn dính vẫn "DETAIL ▼", cùng offset (±1pt) | `iphone-edit-list.json` 5-back · ⚠️ chỗ cuộn nhớ theo **nhóm** ở đầu (`chrome.editListGroup`), không theo từng điểm offset; kiểm lại sau task 8 khi có nút Edit |
| AC-19 | ảnh 3:2 | Edit Curve, chạm đồ thị thêm 2 điểm, rồi ✕ | curve về đường thẳng, recipe không có khối curve; không phần tử nào của curve nằm trong khung stage lúc mở, trên iPhone 17 và iPad 13" sidebar | ✅ `EditorHistoryAndSummaryTests.curveCancelLeavesNoCurveBlock` (+ `curveCancelInsideAToolKeepsTheToolsWork`, `tappedPointSitsOnTheLine`) · iPhone 17: `iphone-curve-tool.json` (hỏi Discard, về hàng Curve), `iphone-curve-dump.json` (đồ thị trong panel, không lớp nào trên stage) · iPad 13": `ipad-curve-sidebar.json` (đồ thị trong sidebar, stage trống) |
| AC-20 | Transform | dump vùng thông số | 4 nhãn CROP · STRAIGHTEN · UPRIGHT · GEOMETRY đúng thứ tự; More… cộng 4 chip = mọi tỉ lệ trong danh sách tỉ lệ, mỗi cái một lần; trước FS-03.15 không hàng / chip nào mờ vì chưa có | ✅ `EditorPanelLayoutTests.transformReachesEveryCropRatioOnce` · `iphone-transform.json` (4 nhãn đúng thứ tự, More… = 4:3 · 3:2 · 16:9 · 9:16, không hàng mờ) |
| AC-21 | ảnh 3:2 crop gốc, góc 0° | Transform, chọn 1:1, Rotate một lần, rồi ✕ và xác nhận | crop về nguyên khung, không xoay, góc 0° | ✅ `EditorHistoryAndSummaryTests.transformCancelRestoresTheFrame` |
| AC-22 | Straighten Tool bật, góc 0° | kéo một ngón từ (60, 300) tới (340, 318) rồi nhấc; làm lại từ góc 0°, kéo (200, 100) tới (220, 400) | lần 1: Angle 3,7° ±0,1° (atan 18/280), thước nằm ngang, đúng 1 bước lịch sử; lần 2: Angle −3,8° ±0,1° (atan 20/300; đỉnh đường lệch trái nên xoay theo chiều kim đồng hồ — sửa 2026-09-29, bản cũ ghi +3,8°), thước đứng thẳng; kéo 6pt thì Angle không đổi | ✅ `StraightenToolTests.aLineAtThreeDegreesLevelsThePhoto` · `.aNearVerticalLineStandsUp` · `.aShortDragIsATap` · `.aRulerIsOneStep` · `iphone-straighten-tool.json` (thước (60,300)→(340,318) cho 3,7°, kéo 6pt giữ 3,7°) |
| AC-23 | (1) ảnh không có đường thẳng (bầu trời phẳng); (2) ảnh có chân trời nghiêng | chạm Auto của Straighten | (1) Angle không đổi; hàng ghi "No straight lines to work from" 3s. (2) Angle nhận đúng góc Level mà phân tích Upright trả; cả hai ca Geometry Rotate không đổi (chốt E3) | ✅ `EditorHistoryAndSummaryTests.straightenAutoWritesTheCropAngle` (không có đường: không đổi; có: góc Level vào crop, Geometry Rotate và Upright giữ nguyên) · `UprightAnalyzerTests` (ca rỗng) · `iphone-straighten-auto.json` (Auto → Angle 6,7°, Upright vẫn Off) |
| AC-24 | Upright, Guided, 4 guide đã vẽ | vẽ đường thứ 5 | vẫn 4 guide; dòng chú "Up to 4 guides" (như 15b AC-24); chip Upright hai hàng 3 + 3, không cắt chữ trên 402 và 375, không cuộn ngang | ✅ `iphone-upright-guided.json` (vẽ 5 đường: còn 4, "Up to 4 guides"; chip 118pt trên 402) · `se-transform-fit.json` (375, iOS 18.6: chip 109pt, không cắt, không cuộn) |

**Chưa chứng minh được:** AC-15…AC-24 — chưa có code.
