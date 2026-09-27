# Intent: Editor trên iPhone — đủ chức năng như iPad, ảnh to, thao tác một tay

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan |
| Ngày | 2026-09-27 |
| Trạng thái | accepted |
| Tiến độ | **chưa làm** (2026-09-27) — chưa có spec |
| Nguồn | phản hồi người dùng (chủ sở hữu sản phẩm) — phiên thiết kế 2026-09-27, mọi quyết định chốt trên canvas |
| Spec sinh ra từ đây | (điền khi sang Design) |

Canvas thiết kế (mọi màn đã chốt, đánh dấu "ĐÃ CHỌN" / hàng "Bản chốt"):
<https://claude.ai/artifact/T4tEUQrJtxBbi48HokiL9F> — private, chủ sở hữu mở được.

Thay cho bản nháp [2026-09-25-mask-phone-panel](2026-09-25-mask-phone-panel.md) (mọi điểm của nó nằm trong
intent này). Anh em cùng phiên:
[lightroom-preset-exchange](2026-09-27-lightroom-preset-exchange.md) ·
[lightroom-parameter-parity](2026-09-27-lightroom-parameter-parity.md) ·
[lens-correction-sources](2026-09-27-lens-correction-sources.md).

## Problem — vấn đề

Người chụp muốn một app **thay được Lightroom trên iPhone**. Hôm nay editor trên iPhone có đủ phần lớn chức
năng của iPad nhưng dùng khó tới mức nhiều thứ coi như không có:

- **Mask gần như không chỉnh được.** Vùng thông số chỉ thấy ~1 slider trọn (đo trên iPhone 17 ở
  [intent cũ](2026-09-25-mask-phone-panel.md)); Size / Feather / Flow của cọ nằm sau 32 slider và 5 header
  ([EditorMaskPanels.swift:523](../../ShotDex/Features/Editing/EditorMaskPanels.swift)); hàng Add/Subtract
  luôn hiện nhưng không làm gì với 10/11 loại mask; dải mask có hai nút `+` / `+−` cạnh nhau, người dùng
  không hiểu danh sách mask ở đâu và thêm vùng ở đâu.
- **Tới công cụ phải vuốt bánh xe 15 chip**
  ([PhotoEditorScreen.swift:3114](../../ShotDex/Features/Editing/PhotoEditorScreen.swift)) — Crop, Heal, Mask,
  Markup, Presets nằm ở chip 11–15. Vuốt ngang sát đáy màn trùng cảm giác với cử chỉ chuyển app của iOS.
  Các dải chọn khác cũng cuộn ngang: loại mask
  ([EditorMaskPhonePanel.swift:58](../../ShotDex/Features/Editing/EditorMaskPhonePanel.swift)), loại lớp
  Markup ([EditorMarkupPhonePanel.swift:122](../../ShotDex/Features/Editing/EditorMarkupPhonePanel.swift)),
  tỉ lệ Crop, thumbnail Presets.
- **Không huỷ được một công cụ**: rời tab Crop là crop được áp
  ([PhotoEditorScreen.swift:2805](../../ShotDex/Features/Editing/PhotoEditorScreen.swift)); Heal / Mask /
  Markup không có Cancel.
- **Chrome tốn chỗ ảnh**: nút compare trùng với giữ-lâu-trên-ảnh; nút Save chữ dài, cụm nút hai bên có thể
  chạm Dynamic Island; filmstrip khi sửa nhiều ảnh cao 124pt
  ([FS-03.09b §2](../02-functional-spec/FS-03-photo-editor/09b-batch-editing-and-reference.md)).
- **Thiếu so với iPad / Lightroom**: không xoay ngang được (iPhone khoá dọc); Curve vẽ đè lên ảnh; Heal chỉ
  có Heal/Clone · Size · Feather · Delete nên panel trống; Presets không có đường quản lý look.

Ai bị ảnh hưởng: mọi người sửa ảnh trên iPhone (và Duo màn ngoài, cùng panel compact). Mức độ: không crash,
không mất dữ liệu, nhưng Mask — công cụ dùng lâu nhất sau Light — hôm nay phải cuộn từng hàng.

## Proposed outcome — kết quả mong muốn

Chi tiết từng màn ở canvas; đây là kết quả người dùng thấy.

**Khung chung**
- Panel cao **344pt khi ảnh ngang, 264pt khi ảnh dọc**, cố định trong một phiên sửa; ngoại lệ duy nhất:
  Curve với ảnh dọc tạm cao 315pt.
- Băng trên: Back · Undo · Redo … histogram · ⋯ · **Save** (nút tròn icon lưu, màu accent) — hai cụm nằm
  gọn hai bên Dynamic Island. Save **luôn hiện**, kể cả khi đang ở trong công cụ (bấm = áp dụng công cụ rồi
  mở sheet lưu). Không còn nút compare: giữ lâu trên ảnh = xem ảnh gốc (chỉ ở Edit).
- ⋯ gọn: History · Copy/Paste Edits · Sync · Fill Screen · Revert · Reset All.
- **Thanh 6 công cụ cố định** ở đáy, không cuộn: Presets · Edit · Transform · Mask · Heal · Markup. Chưa
  chọn = xám mờ, đang chọn = trắng + vạch 16×2; không khung bo từng ô.
- Vào Transform / Mask / Heal / Markup: thanh đổi thành **✕ · tên · ✓** (✓ nền trắng — accent chỉ còn trên
  Save). Presets và Edit không có ✕/✓.
- **Không còn cuộn ngang ở đáy / trong panel** trừ filmstrip và slider.
- Chữ giải thích viết thường như câu; chữ in hoa chỉ dành cho nhãn nhóm.

**Edit** — một danh sách dài cuộn dọc, nhãn nhóm dính trên cùng ("LIGHT ▼"); chạm nhãn → mục lục 9 nhóm để
nhảy; rời Edit rồi quay lại giữ đúng chỗ cũ. Curve là một hàng sau Light, chạm "Edit Curve" → đồ thị vuông
trong panel, chọn kênh bên phải, ✕ · Curve · ✓.

**Transform** (thay Crop, gộp Geometry) — một danh sách: Crop (Original · Free · 1:1 · 4:5 · More…, Rotate ·
Flip · Reset) → Straighten (Angle, **Straighten Tool**: kéo một đường theo chân trời, nhấc tay ảnh tự xoay;
Auto) → Upright (Off · Auto · Level · Vertical · Full · Guided, tối đa 4 đường guide) → Geometry (Vertical ·
Horizontal · Rotate · Aspect · Scale · Offset X/Y · Constrain Crop).

**Mask**
- Chưa có mask: vào là thấy **ô lớn 4×3** chọn loại vùng (ảnh dọc cuộn dọc tới hàng 3).
- Có mask: hàng trên = "[thumbnail] Mask 1 ▼ · **Mask Overlay** · **+** · ⋯". `+` duy nhất = mask mới. Chạm
  ▼ → danh sách dọc: mask → các vùng (⊕/⊖) → Add area / Subtract area ngay dưới mask đang chọn → New Mask
  cuối; 👁 mỗi hàng = ẩn hiệu ứng của mask đó.
- Tạo Brush → **vẽ ngay**. Hàng cọ ghim 1 hàng: [Vẽ][Tẩy] | Size | Feather | Flow; chạm một viên → hàng đó
  thành slider (✓ quay lại); giữ viên và kéo ngang cũng đổi được; vòng xem trước cỡ cọ hiện trên ảnh; Size
  tính theo điểm trên màn (zoom vào = nét nhỏ trên ảnh).
- Slider của mask: một danh sách dài như Edit.
- Phủ đỏ tự động: đang vẽ thì hiện, nhấc tay mờ dần, kéo slider thì tắt; chip **Mask Overlay** ghim bật.

**Heal** — cùng kiểu hàng với cọ; panel dùng hết chỗ: Remove · Heal · Clone · Size · Feather · Opacity ·
điểm đang chọn (New Source · Delete Spot) · tất cả điểm (Visualize Spots + Threshold · Show Spot Pins ·
Clear All). Tính năng mới của Heal thuộc
[lightroom-parameter-parity](2026-09-27-lightroom-parameter-parity.md); intent này chỉ lo bố cục.

**Markup** — chưa có lớp: ô lớn chọn loại lớp; có lớp: "Text 1 ▼ · + · ⋯", danh sách lớp kéo ≡ dọc để đổi
thứ tự; Pen cùng kiểu hàng với cọ; căn lề chữ là **nhóm 3 nút liền** (trái · giữa · phải).

**Presets** — không ✕/✓; Presets · My Looks · LUTs; Amount; lưới thumbnail 4 cột cuộn dọc. My Looks có ô
**Save Current** (giữ như hôm nay: đặt tên, không chọn nhóm) và ô **Import**; giữ lâu look → Rename · Share ·
Export As · Delete; ⋯ tab → Manage Looks (chọn nhiều, kéo sắp xếp, Share / Delete). Phần nhập/xuất/chia sẻ
thuộc [lightroom-preset-exchange](2026-09-27-lightroom-preset-exchange.md).

**Sửa nhiều ảnh** — filmstrip **56pt** (ô 44) giữa ảnh và panel; panel giữ 344/264 (ảnh dọc nhỏ đi); ảnh
đang sửa viền trắng (không còn accent), chấm = có nháp, ✓ = đã lưu; nút **Sync** + "2 / 7" cuối filmstrip
(Sync Look · Sync Everything · Apply Previous · Auto Sync); vào công cụ thì filmstrip ẩn, panel nhận lại chỗ,
ảnh đứng yên.

**Thiết bị** — iPhone **xoay ngang được**: ảnh trái, cột phải = băng lệnh + danh sách + 6 công cụ. Duo màn
ngoài: 6 công cụ + Save là **cột dọc bên phải** (trong vùng an toàn, cạnh rail 84pt của iOS), danh sách slider
dưới ảnh.

## Affected users and systems — phạm vi ảnh hưởng

- **Màn**: toàn bộ photo editor ở layout compact (iPhone, Duo màn ngoài) và iPhone ngang (layout mới). iPad
  và Duo màn trong (sidebar) **không đổi bố cục** trong intent này.
- **Code**: `Features/Editing/*` (PhotoEditorScreen, EditorChromeModel, EditorMaskPanels/PhonePanel,
  EditorMarkupPhonePanel, EditorToolPanels, EditorHealPanel, EditorCurveOverlay, EditorSliderRow, filmstrip),
  `Domain/Editing/EditorLayoutMetrics.swift` (luật panel theo tỉ lệ ảnh, filmstrip, hướng xoay), project
  setting hướng xoay iPhone, `DESIGN.md` §10.3 (panel phone, thanh công cụ, accent), `docs/FS-03.*` (01, 05,
  09b, 12), FS-05 (Markup).
- **Dữ liệu đã lưu**: không đổi recipe. Thứ tự sắp xếp My Looks là dữ liệu mới của người dùng (nằm trong kho
  look, không trong `photo_metadata`).

## Constraints — ràng buộc

- **Không mất chức năng nào** so với iPad/hôm nay; hàng build từ `allCases`, không liệt kê tay theo thiết bị
  (danh sách viết tay là cách Color và cả hàng transport từng biến mất trên phone).
- **Không control nổi đè stage** (`DESIGN.md` §10.3) — chip, ✕/✓, Overlay đều nằm trong panel/băng; vòng cọ và
  đường Straighten là hiển thị, không phải nút.
- Accent chỉ trên Save; nhánh iOS 26 và trước 26 đều chạy.
- Không vuốt ngang ở đáy màn / trong panel trừ filmstrip và kéo slider.
- Mọi thứ chạy trên máy, không thêm dependency.
- App chưa phát hành: không cần tương thích ngược cho edit đã lưu (luật CLAUDE.md 2026-09-23).

## Open questions — câu hỏi còn treo

Mọi quyết định thiết kế đã chốt với người dùng. Còn lại là **số đo**, trả lời trong `/spec` bằng
`device-layout` / `Tools/ui-drive`, không cần người dùng:

1. Dynamic Island thật rộng bao nhiêu trên iPhone 17 / Pro Max — hai cụm 120pt ở băng trên có hở ≥8pt không.
   → `device-layout`.
2. iPhone SE 375pt: hàng cọ [Vẽ][Tẩy] + 3 viên, thanh 6 công cụ (nhãn "Transform"), hàng Mask ("Mask Overlay"
   + `+` + ⋯) có vừa không. → `device-layout`.
3. Duo màn ngoài (vùng app 382pt, trừ cột 56): hàng Mask có vừa không, hay cần rút "Mask Overlay" thành
   "Overlay" ở màn này. → `duo-ux-review`.
4. Luật "ảnh ngang → 344": ngưỡng theo tỉ lệ nhãn hay theo phần đen còn thừa thật (1:1, 4:5)? Người dùng đã
   duyệt "theo phần đen thật" — `/spec` ghi thành công thức và test.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
