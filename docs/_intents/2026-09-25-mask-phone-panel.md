# Intent: Panel Mask trên phone — trả chỗ cho slider

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan |
| Ngày | 2026-09-25 |
| Trạng thái | draft |
| Tiến độ | **chưa làm** (2026-09-25) — chưa có spec |
| Nguồn | phản hồi người dùng (chủ sở hữu sản phẩm), đóng vai người dùng Lightroom |
| Spec sinh ra từ đây | (điền khi sang Design) |

Liên quan: [2026-09-24-editor-phone-panel](2026-09-24-editor-phone-panel.md) (panel 264 / lưới 40 — intent này
**không** đổi khung đó, chỉ đổi cái nằm trong 185pt khi đang ở tab Mask).

## Problem — vấn đề

Chỉnh một mask trên iPhone gần như không làm được: panel chỉ còn chỗ cho **một** slider, và thứ người vẽ cọ cần
nhất nằm cuối một danh sách dài.

Đo trên iPhone 17 (402×874, iOS 26.5), ảnh Skógafoss, `Tools/ui-drive` với
[`iphone-mask-panel.json`](../../ShotDexUITests/scripts/iphone-mask-panel.json)
([ảnh 1](assets/2026-09-25-mask-phone-panel/2-brush-top.jpg) ·
[ảnh 2](assets/2026-09-25-mask-phone-panel/3-brush-scrolled.jpg) ·
[ảnh 3](assets/2026-09-25-mask-phone-panel/4-linear-top.jpg)). Vùng thông số chạy từ y=616 tới bánh xe nhóm ở
y≈796, tức ~180pt:

| y | Hàng | Cao |
|---|---|---|
| 616 | dải mask: thumbnail · `+` · tên · `⋯` | 40 |
| 658 | **Add · Subtract · Undo** | 40 |
| 698 | header dính **LIGHT** | 40 |
| 738 | Exposure — slider duy nhất thấy trọn | 40 |
| 778 | Contrast — lộ 18pt, phần còn lại nằm dưới bánh xe | 18 |

- **Chỉ ~58pt cho slider.** Cuộn xuống thì header LIGHT → COLOR vẫn dính, vẫn ăn 40pt; mỗi lần nhìn được một
  hàng ([ảnh 2](assets/2026-09-25-mask-phone-panel/3-brush-scrolled.jpg): Brightness một mình dưới LIGHT). Header
  vẽ ở [EditorAdjustmentPanel.swift:58](ShotDex/Features/Editing/EditorAdjustmentPanel.swift:58) vì mask scope có
  hơn một nhóm; trên panel phone mỗi header là một hàng lưới 40pt
  ([EditorAdjustmentPanel.swift:191](ShotDex/Features/Editing/EditorAdjustmentPanel.swift:191)).
- **Size / Feather / Flow của cọ nằm ở hàng thứ 38.** Chúng ở footer "MASK · SHAPE"
  ([EditorMaskPanels.swift:523](ShotDex/Features/Editing/EditorMaskPanels.swift:523)), sau 32 slider của Light (8) ·
  Color (5) · Detail (8) · Effects (11) và 5 header — ~1.480pt cuộn qua một khe 58pt. Vừa tạo Brush xong, người
  dùng thấy Exposure chứ không thấy cọ to bao nhiêu.
- **Add / Subtract luôn hiện, và với 10/11 loại mask nó không làm gì.** Hàng
  ([EditorMaskPanels.swift:355](ShotDex/Features/Editing/EditorMaskPanels.swift:355)) hiện cho cả Linear
  ([ảnh 3](assets/2026-09-25-mask-phone-panel/4-linear-top.jpg)), Sky, Subject… `maskOperation` chỉ bật/tắt tẩy
  cho cọ ([PhotoEditorController.swift:217](ShotDex/Features/Editing/PhotoEditorController.swift:217)); "hình kế
  tiếp" mà spec nói tới ([05-local-masks.md:49](../02-functional-spec/FS-03-photo-editor/05-local-masks.md)) không
  có đường tạo — FS-03.12 AC-16 đã ghi "photo editor không có đường nào tạo shape thứ hai trong một mask". Tức là
  một công tắc bấm được, đổi trạng thái được, và không đổi gì trên ảnh.
- **Undo có hai chỗ.** Nút Undo cuối hàng Add/Subtract lặp nút Undo của băng lệnh trên cùng (góc trên-trái, cả ba
  ảnh) — 40pt của hàng đó phần lớn là nút trùng.

Người dùng Lightroom sẽ thấy lạ ở cả ba điểm. Lightroom iPad (ảnh thật trong repo,
[`lr-14`](assets/lightroom-ref/lr-14.png), 2026-09-22):

- Cọ là một **công cụ**, không phải một nhóm slider: cột dọc riêng **Brush · Eraser · Size · Feather · Flow** ·
  Invert · Delete. Tẩy là một nút của cọ, không phải chế độ Add/Subtract của cả mask.
- Nhóm chỉnh của mask là **Light · Color · Effects · Detail · Optics gập lại, mở một nhóm**, không phải một danh
  sách dài có header dính.
- Cộng / trừ một vùng là **một nút tạo vùng mới** dưới danh sách thành phần của mask (⊕⊖ trong cột thumbnail),
  không phải công tắc thường trực.

App khác (tra 2026-09-25):

| App | Cọ / tẩy | Cộng / trừ vùng | Slider | Nguồn |
|---|---|---|---|---|
| **Lightroom iPhone** | Eraser "on the left side of the screen"; Size · Feather · Flow là cài đặt của cọ | Add → chọn công cụ trong "Create new Mask" | — | trích đoạn tìm kiếm từ [helpx iOS](https://helpx.adobe.com/lightroom-cc/using/masking-mobile-ios.html) (trang trả 403, chưa đọc trọn) |
| **Snapseed Brush** | chọn hiệu ứng (Dodge & Burn · Exposure · Temperature · Saturation) + mức mạnh; nút tẩy riêng; **cỡ cọ = zoom ảnh**, không có slider Size | — | không có | [Brush](https://support.google.com/snapseed/answer/6157715?hl=en) |
| **Snapseed Selective** | chạm đặt điểm; pinch đổi cỡ vùng | mỗi điểm là một vùng | **không có slider thường trực**: vuốt dọc chọn thông số, vuốt ngang đổi giá trị | [Selective](https://support.google.com/snapseed/answer/6157827?hl=en) |
| **Photomator** | cọ có size · softness · opacity; cọ vừa cộng vừa trừ | chọn mask hay cả ảnh bằng **một menu thả** (không phải dải) | — | [PetaPixel](https://petapixel.com/2023/04/12/pixelmator-photo-rebrands-to-photomator-adds-ai-masking-tools/), [iDB](https://www.idownloadblog.com/2023/04/12/pixelmator-photo-2-3-update-photomator-iphone-ipad-image-editor/) |
| **Darkroom** | chưa xác minh | invert / kết hợp mask qua nút `•••` | chưa xác minh | [Darkroom blog](https://darkroom.co/blog/2022-04-masks) |

Điểm chung: **không app nào có hàng Add/Subtract thường trực.** Tẩy là một nút của cọ. Cộng/trừ vùng là việc
làm một lần, qua `+` hoặc qua menu.

Cách của Snapseed (vuốt trên ảnh để đổi giá trị, pinch để đổi cỡ) không lấy được cho mask của ShotDex: trên ảnh,
một ngón đang vẽ cọ hoặc kéo gradient, hai ngón đang zoom
([05b-mask-painting-and-zoom.md](../02-functional-spec/FS-03-photo-editor/05b-mask-painting-and-zoom.md)).

Mức độ: không crash, không mất dữ liệu; nhưng Mask là công cụ người chụp dùng lâu nhất sau Light, và trên phone
hôm nay phải cuộn từng hàng một để chỉnh.

## Proposed outcome — kết quả mong muốn

- Chỉnh mask trên phone thấy **ít nhất 2 slider trọn** một lúc (hôm nay: 1), không hàng nào nằm dưới bánh xe.
- **Không header nhóm nào ăn một hàng** của khe slider.
- Vừa tạo Brush xong là **thấy ngay Size / Feather / Flow và nút tẩy**, không cuộn.
- **Không còn control nào bấm được mà không làm gì**: loại mask không có gì để cộng/trừ thì không hiện Add/Subtract.
- Không còn nút trùng với băng lệnh trên.
- Người đã quen Lightroom nhận ra ngay: cọ là công cụ, chỉnh theo từng nhóm.
- Không mất chức năng nào: mọi slider mask, mọi hàng Shape (Feather · Opacity · Min · Max · Range · Near · Far ·
  Clear Strokes), chip chọn hình khi mask có ≥2 hình, Undo (ở băng lệnh) vẫn tới được.

### Đã chốt với người dùng (2026-09-25)

| # | Chủ đề | Chốt |
|---|---|---|
| 1 | Undo trên hàng mask | **bỏ** — băng lệnh trên đã có Undo |
| 2 | iPad / Duo trong (sidebar) | **để sau** — intent này chỉ panel compact (iPhone, Duo màn ngoài) |

## Affected users and systems — phạm vi ảnh hưởng

- **Màn**: editor → tab Mask, trạng thái "đã có mask" (`EditorMaskDetailPanel`). Màn chọn loại mask
  (`EditorMaskChooser`) và dải mask 40pt không thuộc phạm vi.
- **Thiết bị**: iPhone 402pt và 375pt; Duo màn ngoài (cùng panel compact). iPad và Duo trong (sidebar) **ngoài
  phạm vi** (chốt #2) — kể cả hàng Add/Subtract vô nghĩa trên sidebar
  ([EditorMaskPanels.swift:531](ShotDex/Features/Editing/EditorMaskPanels.swift:531)), để intent iPad sau.
- **Code** (Features/Editing): `EditorMaskPanels.swift` (`phoneShapeRow`, `maskShapeSection`, `addSubtractRow`),
  `EditorMaskPhonePanel.swift`, `EditorAdjustmentPanel.swift` (`EditorAdjustmentGroupsView` + `EditorGroupHeader`
  khi scope mask), có thể `PhotoEditorController.swift` (`maskOperation` / `brushIsEraser`). Domain:
  `EditorLayoutMetrics.swift` nếu có hằng mới. Test: `EditorPanelLayoutTests.swift`.
- **Docs**: FS-03.05 §3 (bố cục chỉnh mask), FS-03.12 (lưới phone), `DESIGN.md` §7 nếu thêm kiểu hàng.
- **Dữ liệu đã lưu**: không đụng. `maskOperation`, cỡ cọ nằm trên controller, không nằm trong recipe.

## Constraints — ràng buộc

- **Khung FS-03.12 giữ nguyên**: panel 264, vùng thông số 185, lưới 40, panel không đổi cao theo trạng thái. Chỗ
  thêm phải lấy từ bên trong 185pt, không lấy từ ảnh.
- **Không đặt control nổi đè lên stage** (`DESIGN.md` §7, dòng 298: stage nuốt mọi chạm). Cột công cụ cọ kiểu
  Lightroom không chép nguyên được lên ảnh.
- Một kiểu chip, một kiểu slider, accent chỉ trên Save (FS-03.12).
- **Phone có đủ mọi thứ iPad có**; danh sách dựng từ catalog / `allCases`, không liệt kê tay.
- Pinch khi vẽ mask là zoom (FS-03.05b) — không dùng pinch để đổi cỡ cọ.
- Nhánh iOS 26 và pre-26 cùng chạy. Không thêm dependency.

## Open questions — câu hỏi còn treo

### 1. Bố cục nào cho 185pt? — người dùng chọn

Số tính trên lưới 40 ở 402pt; mọi phương án giữ dải mask 40pt trên cùng (thumbnail · `+` · tên · `⋯`) và bánh
xe nhóm ở đáy. Ví dụ dưới là mask Brush vừa tạo.

**A — hàng chip nhóm, mở một nhóm một lúc** *(đề xuất)*

| Hàng | Nội dung |
|---|---|
| 1 (40) | dải mask |
| 2 (40) | chip `Brush · Light · Color · Detail · Effects` — chip đầu mang tên loại mask (Brush, Radial, Luminance…) và chứa các hàng Shape của loại đó |
| 3–5 (105) | slider của **đúng một** chip đang chọn, cuộn dọc, không header. Thấy **2,6 hàng** |

- Chip Brush: `Paint · Erase` · Size · Feather · Flow · Opacity · Clear Strokes. Chip Radial: Feather · Opacity.
  Chip Luminance: Min · Max · Feather · Opacity… Subject/Sky/Linear chỉ có Opacity.
- Chip Light: 8 slider; Color: 5; Detail: 8; Effects: 11 — nhóm dài nhất cuộn 11 hàng, không phải 32.
- **Lý do**: (1) editor chính đã dạy người dùng cách này — bánh xe mở từng nhóm Light / Color / Effects / Detail,
  không header; mask đi cùng một mô hình thì không phải học lại. (2) Lightroom cũng mở từng nhóm của mask
  (`lr-14`: Light · Color · Effects · Detail · Optics gập, mở một cái) và tách cọ ra thành công cụ riêng — chip
  đầu là chỗ của công cụ đó. (3) Cỡ cọ nằm ngay dưới mắt khi vừa tạo Brush, thay vì hàng 38. (4) Header nhóm
  biến thành chip — cùng thông tin "đang ở nhóm nào", nhưng một hàng cho cả 5 nhóm thay vì mỗi nhóm một hàng.
- **Giá**: đổi nhóm tốn 1 chạm thay vì cuộn; hàng chip giữ 40pt cố định; 5 chip ở 375pt phải đo (câu 4).

**B — một danh sách phẳng, bỏ header**

| Hàng | Nội dung |
|---|---|
| 1 (40) | dải mask |
| 2–5 (145) | toàn bộ slider trong một cột: hàng Shape của loại mask lên đầu, rồi Light · Color · Detail · Effects liền nhau, không header. Thấy **3,6 hàng** |

- **Lý do có thể chọn**: nhiều slider thấy nhất; không thêm hàng chip nào; mask Sky/Subject chỉ cần Exposure và
  vài hàng Light là thấy ngay.
- **Vì sao không đề xuất**: Color bắt đầu ở hàng ~14, Effects ở ~27 — vẫn là "cuộn qua cả chục hàng để tới thứ
  cần", chỉ đổi chỗ đau từ Size cọ sang Temp/Clarity. Bỏ header thì cũng mất luôn mốc "đang ở nhóm nào" khi
  cuộn nhanh. Không giống editor chính, không giống Lightroom.

**C — như A, cộng cột công cụ cọ cạnh ảnh** (bản chép Lightroom iPad)

| Chỗ | Nội dung |
|---|---|
| cạnh trái ảnh | cột dọc ~44pt: Paint · Erase · Size · Feather · Flow — anh em với stage, không đè lên |
| panel | như A nhưng không có chip Brush |

- **Lý do có thể chọn**: giống Lightroom nhất; Size/Feather/Flow luôn thấy trong lúc vẽ mà không chiếm hàng panel.
- **Vì sao không đề xuất**: ảnh hẹp ~44pt (11% bề ngang 402pt) suốt lúc chỉnh mask — trên phone ảnh là thứ thiếu
  nhất; cần một component mới (cột công cụ dọc) mà editor chưa có; DESIGN.md cấm đè stage nên không thể làm như
  Lightroom (cột của họ nổi trên vùng đen của ảnh); và chỉ Brush dùng được cột này, 10 loại còn lại có một cột
  trống hoặc một bố cục thứ hai.

### 2. Add / Subtract — Lightroom làm thế nào, và ShotDex theo tới đâu

Lightroom (iPad, `lr-14` — cắt phóng to: [cột cọ](assets/2026-09-25-mask-phone-panel/lr14-brush-rail.png) · [cột mask](assets/2026-09-25-mask-phone-panel/lr14-mask-column.png)) tách hai thứ ShotDex đang gộp vào một công tắc:

- **Tẩy là một nút của cọ.** Cột công cụ Brush: `Brush` (đang chọn) · `Eraser` · Size (`13`) · Feather · Flow ·
  Invert · Delete. Chọn Eraser thì nét kế tiếp trừ khỏi vùng cọ. Không có "chế độ Subtract" nào cho cả mask.
- **Cộng / trừ một vùng là nút tạo vùng mới.** Cột mask ở góc phải-dưới: `+` (mask mới) · thumbnail mask ·
  `↳` thành phần (icon cọ) · nút **⊕⊖** dưới cùng. Nút ⊕⊖ mở danh sách loại vùng để thêm vào *chính mask này* —
  Add hoặc Subtract (desktop còn có Intersect). Nội dung menu đó chụp chưa có; theo trí nhớ, cần ảnh iPhone xác
  nhận (câu 5).
- Mask chỉ có một vùng không hiện gì về cộng/trừ ngoài nút ⊕⊖ đó.

Đề xuất cho ShotDex:

- **Brush**: `Paint · Erase` là hàng đầu trong chip Brush (tên Lightroom dùng: Brush / Eraser), điều khiển đúng
  `brushIsEraser` như hôm nay. Mở mask Brush luôn về `Paint`.
- **Loại khác**: không hiện gì. Công tắc hôm nay chỉ đổi cọ sang tẩy, nên bỏ nó không mất hành vi nào.
- **Nút ⊕⊖ (thêm vùng Add/Subtract vào mask đang chọn)**: là tính năng chưa có — FS-03.05 §4 hứa, FS-03.12 AC-16
  ghi chưa có đường làm. **Không gộp vào intent này**; mở intent riêng khi muốn. Khi làm, chỗ của nó là trong
  `⋯` của mask hoặc cạnh `+` trên dải mask, không phải một hàng thường trực.

Người dùng xác nhận hướng này hoặc chọn gộp ⊕⊖ vào luôn.

### 3. Mở mask thì chip nào đang chọn? (nếu chọn A)

Đề xuất: Brush, Luminance, Color, Depth → **chip Shape** (chưa vẽ / chưa chọn dải thì chưa có gì để chỉnh);
Subject, Sky, Background, Face/Eyes/Lips, Linear, Radial → **Light** (vùng đã có sẵn, người ta vào để chỉnh sáng).
Nhớ chip cuối trong phiên khi chuyển qua lại giữa các mask. → `/spec`.

### 4. 375pt

5 chip `Brush · Light · Color · Detail · Effects` có vừa không cuộn trên iPhone SE 375? Tên loại dài nhất
("Luminance", "Face Skin") có đẩy chip Effects ra ngoài? → `/spec` + `device-layout`.

### 5. Cỡ cọ theo zoom, kiểu Snapseed?

Snapseed không có slider Size: cọ giữ nguyên cỡ trên màn, muốn nét nhỏ thì zoom ảnh vào. ShotDex hôm nay tính
`brushSize` theo cạnh ngắn của ảnh (`PhotoEditorController.brushSize = 0.25`), và đã có pinch-zoom lúc vẽ. Theo
cách Snapseed thì chip Brush bớt được một hàng, nhưng đổi hành vi cọ và bỏ một control Lightroom có. Đề xuất:
**giữ slider Size** (người dùng Lightroom tìm nó), ghi lại ý này cho sau. → người dùng.

### 6. Cho panel cao hơn?

Mỗi +40pt là thêm một hàng slider, trả bằng stage (hôm nay 402×548 trên iPhone 17). Cỡ ảnh khi fit:

| Tỉ lệ | 264 (hôm nay) | 304 (+40) | 344 (+80) |
|---|---|---|---|
| 3:2 · 4:3 ngang · 1:1 | không đổi | không đổi | không đổi |
| 4:5 dọc | 402×502 | không đổi | 374×468 (−13% diện tích) |
| 3:4 dọc (ảnh iPhone) | 402×536 | 381×508 (−10%) | 351×468 (−24%) |
| 2:3 dọc (máy ảnh) | 365×548 | 339×508 (−14%) | 312×468 (−27%) |

Ảnh ngang còn ~280pt đen trên stage, nên cao thêm không mất gì; ảnh dọc thì mất. Cách làm có thể: (a) +40 cố định
cho mọi tab — đổi khung FS-03.12 vừa chốt 2026-09-24; (b) chỉ tab Mask cao hơn — ảnh nhảy 40pt khi vào/ra Mask,
phá luật "panel không đổi cao"; (c) panel lấn vào phần đen mà ảnh để lại — ảnh ngang được thêm 1–2 hàng miễn phí,
ảnh dọc giữ 264, chiều cao cố định trong một phiên sửa. Chiều cao không sửa được ba lỗi kia (Add/Subtract vô nghĩa,
cọ ở hàng 38, Undo trùng) — nó cộng thêm vào A/B, không thay chúng. Đụng mọi tab → nếu làm thì là **intent riêng**
sửa khung FS-03.12. → người dùng.

### 7. Lightroom iPhone thật

Người dùng chụp giúp vài màn Masking trên iPhone (Brush đang vẽ, một mask có nhiều nhóm, menu của ⊕⊖) như bộ
`lr-*` của iPad, để `/spec` đối chiếu? Không chặn việc duyệt.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
