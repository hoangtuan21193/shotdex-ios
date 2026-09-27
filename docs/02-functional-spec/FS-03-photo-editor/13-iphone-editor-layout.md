# FS-03.13 — Editor trên iPhone: thanh 6 công cụ, panel theo ảnh

`FS-03.13` · tier D · `Features/Editing/PhotoEditorScreen.swift` · `Domain/Editing/EditorLayoutMetrics.swift`
· intent [2026-09-27-editor-iphone-layout](../../_intents/2026-09-27-editor-iphone-layout.md) · cập nhật 2026-09-28

**Một câu:** editor ở layout compact (iPhone dọc, Duo màn ngoài) có đủ mọi chức năng của iPad, sáu công cụ nằm
cố định dưới ngón cái, không vuốt ngang ở đáy màn, ảnh to nhất phần đen cho phép.

Canvas đã chốt (private, chủ sở hữu mở được): <https://claude.ai/artifact/T4tEUQrJtxBbi48HokiL9F> — số đo
trong spec này đọc từ các bảng "Chốt" / "ĐÃ CHỌN" của canvas. Quyết định đã chốt 2026-09-28 (§5); còn D3 chờ số đo.

## Các phần

| # | Phần | Trả lời | AC |
|---|---|---|---|
| 13a | [Khung, băng trên, thanh công cụ](13a-chrome-and-toolbar.md) | panel 344 / 264 / 315, Save luôn hiện, ⋯, ✕ · tên · ✓, giữ-xem-gốc, lịch sử | AC-1…14 |
| 13b | [Edit và Transform](13b-edit-and-transform.md) | danh sách dài, nhãn dính, mục lục, Curve trong panel, Crop · Straighten · Upright · Geometry | AC-15…24 |
| 13c | [Mask, Heal, Markup](13c-mask-heal-markup.md) | ô chọn 4×4, hàng "Mask 1 ▼", danh sách vùng, hàng cọ ghim, phủ đỏ tự động, Heal, danh sách lớp | AC-25…36 |
| 13d | [Presets, sửa nhiều ảnh, Duo màn ngoài](13d-presets-batch-devices.md) | lưới 4 cột, menu giữ lâu, filmstrip 56, Duo màn ngoài | AC-37…45 |

## 1. Người dùng cần gì

Người chụp muốn bỏ Lightroom trên iPhone: tới mọi công cụ bằng một chạm (không vuốt bánh xe 15 chip sát cạnh
vuốt-chuyển-app), huỷ được một công cụ, chỉnh Mask mà không cuộn từng hàng, và thấy ảnh to.

## 2. Phạm vi

**Có:** mọi màn của photo editor ở layout không sidebar — iPhone dọc, Duo màn ngoài.

**Cố ý không có:**
- **Bố cục iPhone ngang**: iPhone khoá dọc, editor cũng không xoay.
- Màn Manage Looks, chọn nhiều look, kéo sắp xếp look — thay bằng menu giữ lâu ([13d §1](13d-presets-batch-devices.md#1-presets)).
- Remove (tô lên vật để xoá) — tạm bỏ tới khi Apple có model hỗ trợ.
- Bố cục sidebar (iPad, Duo màn trong) — giữ [FS-03.09](09-wide-screen-and-batch-editing.md), chỉ nhận luật chung ở §3.
- Hành vi nhập / xuất / chia sẻ look — [FS-03.14](14-lightroom-preset-exchange.md); spec này chỉ đặt chỗ các nút.
- Thông số mới (Upright Auto/Guided, Aspect, Red Eye…) — [FS-03.15](15-lightroom-parameter-parity.md); ống kính — [FS-03.16](16-lens-correction-sources.md).
- Đổi recipe — không trường nào thêm hay đổi nghĩa vì bố cục.

## 3. Luật chung

- **Không mất chức năng.** Mọi ô, hàng, mục lục, menu dựng từ **danh sách đầy đủ** của loại đó, không liệt kê
  tay theo thiết bị; test lặp qua danh sách và đếm.
- **Không cuộn ngang ở đáy màn và trong panel**, trừ filmstrip và kéo slider. Dải chip dài hơn một hàng thành
  lưới ô, hai hàng, hoặc mục "More…".
- **Không control nổi đè stage** (`DESIGN.md` §10.3). Vòng cọ, đường Straighten, đường guide Upright là hiển
  thị; tay nắm guide mask / vết Heal giữ như [FS-03.05 §5](05-local-masks.md#5-guide-trên-ảnh).
- **Accent chỉ trên Save.** ✓ nền trắng, glyph đen. Công cụ đang chọn: trắng + vạch 16×2.
- **Chữ giải thích viết như câu** ("Drag a line along…"); chữ IN HOA chỉ cho nhãn nhóm (LIGHT, SELECTED SPOT).
- **Hình học theo token có sẵn**: hàng 40, chip 30 bo 8, slider [FS-03.12 §5](12-phone-panel-grid.md#5-slider),
  thang khoảng cách 4…24. Số mới nào cũng ghi ở đây và đánh dấu nếu chưa có trong `DESIGN.md`.
- **Chưa có thì không hiện**: hàng, ô, chip của thông số chờ FS-03.15 không hiện và không mờ; thứ tự giữ chỗ.
- **Hai luật áp cho mọi layout, kể cả sidebar**: Curve luôn trong panel ([13b §2](13b-edit-and-transform.md#2-curve-trong-panel)),
  phủ đỏ mask tự động ([13c §3](13c-mask-heal-markup.md#3-hàng-cọ-ghim-và-phủ-đỏ)).
- **iOS 26 và trước 26 có cùng tập hành động**; chỉ vật liệu kính khác.

## 4. Ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Hiệu năng | đổi công cụ, mở mục lục, mở danh sách mask **không render lại ảnh**; stage chỉ vừa khung lại khi panel đổi cao (Curve 315) |
| Bộ nhớ | không thêm bản ảnh nào; thumbnail Presets theo lô ≤24 look ([FS-03.02 §8](02-film-simulation-and-presets.md#8-panel-presets)) |
| Thiết bị | iPhone 402×874 · SE 375×667 · Pro Max 440×956, chỉ dọc · Duo ngoài 466×678 (vùng app 382×644) |
| iOS 26 vs trước | cùng hành động; kiểm bằng dump hai phía (agent `ios26-parity`) |
| Truy cập | nhãn VoiceOver cho mọi nút chỉ có icon; stage có hành động "Show Original" thay nút compare đã bỏ; hàng 40 là miễn trừ tầng D ([FS-03.12 §7](12-phone-panel-grid.md#7-đã-chốt-2026-09-24)) |
| Dữ liệu | không đổi recipe; look là dữ liệu người dùng trong kho look, không vào `photo_metadata` ([BD-02](../../01-basic-design/BD-02-database-design.md)) — thuộc FS-03.14 |

## 5. Đã chốt 2026-09-28

Lý do và phương án đã cân nhắc: [DECISIONS.md](../../../.planboard/editor-specs-decisions/DECISIONS.md).

- **D1** Panel 344 / 264 / 315 theo phần đen của ảnh — [13a §2](13a-chrome-and-toolbar.md#2-chiều-cao-panel).
- **D2** Sửa nhiều ảnh: panel tính theo ảnh đang mở — 13a §2, 13d §2.
- **D3** Cụm nút cách mép 10 hay 20pt — **chờ số đo đảo thật** (câu đo 1) — [13a §3](13a-chrome-and-toolbar.md#3-băng-trên).
- **D4** Thanh 6 công cụ thay hẳn bánh xe ở mọi layout không sidebar, kể cả Duo màn ngoài — 13a §4.
- **D5** "Gọi lại bản đã lưu / đổi nguồn" ở cuối ⋯, chỉ khi ảnh có — 13a §3.
- **D6** Giữ-xem-gốc ở Edit và Presets — 13a §3.
- **D7** ✕ hỏi xác nhận chỉ khi phiên công cụ có ≥1 thay đổi — 13a §5.
- **D8** Undo trong công cụ dừng ở lúc vào — 13a §5.
- **D9** Hai mô hình nhóm: phone 9 nhóm phẳng, sidebar 5 nhóm — [13b §1](13b-edit-and-transform.md#1-edit-một-danh-sách-dài).
- **D10** Tên nhóm "Grading" — 13b §1.
- **D11** Curve luôn trong panel, mọi layout — 13b §2.
- **D12** Upright hai hàng 3 + 3 — 13b §3.
- **D13** Straighten Tool dựng đường gần dọc đứng thẳng — 13b §3.
- **D14** Hàng Transform chờ FS-03.15 không hiện, giữ chỗ trong thứ tự — 13b §3.
- **D15** Phủ đỏ theo luật mới ở mọi layout, mờ 1,5s — [13c §3](13c-mask-heal-markup.md#3-hàng-cọ-ghim-và-phủ-đỏ).
- **D16** Add / Subtract area có mọi loại vùng, dựng từ danh sách — 13c §2.
- **D17** Hàng Heal chờ FS-03.15 không hiện, giữ chỗ trong thứ tự — 13c §4.
- **D18** Loại mực Pen ở trang con mở từ chấm màu (lưới mực + bảng màu) — 13c §5.
- **D19** Tên lớp "Speech bubble" — 13c §5.
- **D20** Không có Manage Looks; giữ lâu mọi ô → Rename · Share · Export As · Delete, không Delete với preset có sẵn — [13d §1](13d-presets-batch-devices.md#1-presets).
- **D21** Filmstrip 56, ô 44, viền trắng — 13d §2.
- **D22** Ô filmstrip bo 6 — 13d §2.
- **D23** Sync chỉ ở cuối filmstrip, không ở ⋯ — 13d §2.
- **D24–D28** iPhone khoá dọc, editor không xoay; bỏ toàn bộ bố cục iPhone ngang — §2.
- **D29** Duo ngoài giữ chữ "Mask Overlay", chỉ rút khi đo thấy cắt — [13d §3](13d-presets-batch-devices.md#3-duo-màn-ngoài).
- **D30** Nhãn cột Duo 10,5pt (token nhãn tab) — 13d §3.
- **D31** Danh sách Duo ngoài cố định 300 — 13d §3.
- **D32** Duo ngoài trong công cụ: ✕ và ✓ nằm trong cột dọc thay các ô công cụ — 13d §3.
- **D33** Băng trên Duo ngoài có histogram — 13d §3.
- **D39 · D45** Look nhập mang nhãn "Imported"; share mỗi lần một look — 13d §1, chi tiết ở FS-03.14.
- **D66** Remove tạm bỏ, Heal không có chip Remove — 13c §4.
- **D68** Lưới chọn mask 4×4, ba ô khuôn mặt giữ ngoài, thêm Object và People — 13c §1.

## 6. Đoạn phải viết lại khi spec này land

Không sửa trong lượt này; `/plan` liệt kê lại theo file:line.

| Tài liệu | Đoạn | Thành |
|---|---|---|
| `DESIGN.md` §10.3 | "264pt = 185 + 54 + 25", bánh xe + vạch, "Điện thoại (<700pt) giữ nguyên cấu trúc", filmstrip 96/124 viền accent | 344/264/315, thanh 6 công cụ, filmstrip 44/56 viền trắng, phủ đỏ mờ 1,5s |
| `DESIGN.md` §5 | `r-track` 6 chỉ cho Video Studio | thêm ô filmstrip của editor |
| FS-03.01 | §1, §2, §3 (cụm nút, nút xem gốc, bảng ⋯), §5 dải nhóm, §6 | trỏ về 13a; Sync rời ⋯, gọi lại bản đã lưu cuối ⋯ |
| FS-03.01b | §5 hàng Upright 4 chip, §6 "crop chốt khi rời nhóm" + dòng chú | 6 chip hai hàng 3 + 3; ✕ / ✓ |
| FS-03.02 | §8 dải thumbnail cuộn ngang, §9 "giữ = Delete" | lưới 4 cột; menu giữ lâu, không Delete với preset có sẵn |
| FS-03.03 | §1 "panel giữ nguyên chiều cao", §5 nút before/after | trừ Curve 315; giữ-trên-ảnh ở Edit và Presets |
| FS-03.05 | §2 ba hàng chip cuộn, §3 dải thumbnail + Add/Subtract + Undo, §6 phủ đỏ, §7 pill; AC-17, 18, 21, 22 | 13c; phủ đỏ mới cho mọi layout |
| FS-03.09 / 09b | 09 §10 hàng "Điện thoại — không đụng" + còn treo 3; 09b §2 filmstrip + badge, §3 lối vào Sync | 13d; phone 9 nhóm, sidebar 5 |
| FS-03.11 | §2 "cũng có trên bánh xe điện thoại" | thanh công cụ |
| FS-03.12 | Một câu, §3, §4 (dải >5 cuộn, hàng Crop / Presets), §6; AC-10, 11, 13 | 13a–13d |
| FS-03.14 | chỗ đặt nút "⋯ → Manage Looks", Manage Looks | menu giữ lâu của [13d §1](13d-presets-batch-devices.md#1-presets) |
| FS-04.02 | §1, §4 curve đè ảnh | curve trong panel, mọi layout kể cả sidebar |
| FS-05 README, FS-05.01 | "Panel — dải lớp", §4 dải mực, §6 ba hàng chip + kéo thumbnail; AC-26…37 | 13c §5; mực ở trang con của chấm màu |

## 7. Câu hỏi đo — trả lời bằng `device-layout` / `duo-ux-review`, không cần người dùng

1. **Dynamic Island** trên iPhone 17 / 17 Pro Max rộng bao nhiêu thật; hai cụm 120pt còn hở ≥8pt mỗi bên không
   (canvas: đảo 126 ở x 138, cụm trái kết thúc x 130). Quyết D3. **⚠️ chưa đo.**
2. **SE 375pt**: nhãn "Transform" trong ô 1/6; hàng cọ [Vẽ][Tẩy] + 3 viên; hàng "Mask 1 ▼ · Mask Overlay · + · ⋯";
   Upright 3 + 3. **⚠️ chưa đo.**
3. **Duo ngoài** (382 − cột 56 = 326): hàng Mask vừa không (D29); "Transform" 10,5pt trong ô 52 (D30). **⚠️ chưa đo.**
4. **Luật 344**: đã ghi thành công thức ở [13a §2](13a-chrome-and-toolbar.md#2-chiều-cao-panel) và AC-1…3;
   còn phải đo băng trên T thật trên từng máy (canvas dùng 60, iPhone 17 báo vùng an toàn ~62).

## 8. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Panel 344 làm ảnh 4:5 vừa crop trong phiên nhỏ hơn mức có thể | chấp nhận — panel cố định trong phiên là quyết định của intent; mở lại ảnh thì tính lại |
| Bỏ nút compare: người không biết giữ-lâu mất lối so sánh | hành động VoiceOver "Show Original" (AC-12); có cần gợi ý lần đầu không là câu hỏi cho `ux-reviewer` sau `/plan` |
| Sync chỉ ở filmstrip: lúc tràn viền không thấy Sync | chạm đôi thoát tràn viền là filmstrip hiện lại; VoiceOver tới pill Sync trong filmstrip |
| Lưới mask 4×4 trên panel 264 phải cuộn tới hàng 3 và 4 | chấp nhận — giữ ba ô khuôn mặt ở ngoài rẻ hơn một chạm thêm mỗi lần chỉnh da, mắt, môi |
