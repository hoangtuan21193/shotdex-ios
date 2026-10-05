# FS-03.17 — Editor iPad + Duo theo design canvas 30/9 — các quyết định

> Chốt 2026-10-01 sau 1 vòng planboard + 1 câu hỏi trong chat (D5).

| ID | Quyết định | Kết quả | Lựa chọn |
|---|---|---|---|
| D1 | Bố cục màn rộng: ảnh + một cột phải cố định | OK | Theo design |
| D2 | Điều khiển nổi trên ảnh | OK | Cho nổi, sửa DESIGN.md |
| D3 | Cỡ nút trên băng: 34 (iPad, Duo dọc, Duo ngoài) / 40 (Duo trong ngang) | OK | Vẽ 34/40, chạm 44 |
| D4 | Bỏ nút ⋯: các mục trong ⋯ đi đâu | OK | Rải về chỗ hợp lý, bỏ 2 mục |
| D5 | Duo trong dọc 669×951 (12 bảng DIP) | OK | Mở xoay cho iPhone target |
| D6 | Sheet Save: công tắc Include Metadata | OK | Bố cục design, hành vi code |
| D7 | Heal: Remove hay Red Eye | OK | — |
| D8 | Reset All trên băng vẫn hỏi lại | OK | — |
| D9 | Chấm 'đã sửa' trên filmstrip màu cam | OK | — |
| D10 | Ô công cụ khác trong lúc đang ở trong công cụ (Duo ngoài) | OK | — |
| D11 | Transform trên ảnh: khung chữ L, thước góc xoay, Rotate/Flip trên ảnh | OK | Mọi thiết bị |
| D12 | Lớp chữ đang chọn: khung trắng, 4 chấm, núm xoay | OK | — |
| D13 | Hàng chữ B · I · U | căn lề | Size − 200 px + | OK | — |
| D14 | Băng iPhone: bỏ ⋯, histogram 66×34, Save icon export | OK | Để sau |
| D15 | Lưới loại Mask và loại lớp | OK | — |
| D16 | Tỉ lệ crop 5:4 | OK | — |
| D17 | Số slider và Curve rút gọn ở IP1/DI1 | OK | — |
| D18 | Lỗi hình trong bảng | OK | — |
| D19 | Màu, bo góc, khoảng cách ngoài token | OK | — |
| D20 | Tài liệu spec | OK | — |
| D21 | Sửa canvas cùng lượt | OK | — |
| D22 | Chứng minh: design-parity PASS từng bảng | OK | — |

## D1 — Bố cục màn rộng: ảnh + một cột phải cố định
- **Chốt:** Theo design: ảnh + cột phải cố định 280 / 260, danh sách phẳng của iPhone, dải công cụ ở chân cột. Bỏ rail, resize, collapse, chọn bên. FS-03.09 §3–6 chuyển thành 'thay bởi FS-03.17'.
- **Vì sao:** Code hiện (FS-03.09): rail 48 + panel 280–420 kéo đổi rộng, thu gọn được, chọn trái/phải, 7 card gập. Design (IP1, IPP1, DI1): ảnh chiếm hết phần trái, cột phải cố định 280 (iPad) / 260 (Duo trong), danh sách phẳng như iPhone có nhãn LIGHT ▼, dải 6 công cụ ở chân cột thay rail. Theo design là bỏ resize, collapse, chọn bên, và viết lại AC-1, 9, 10, 18, 26, 32–34 của FS-03.09.
- **Đã cân nhắc:** Giữ rail + panel, chỉ áp chi tiết design — Không giống design: design-parity sẽ FAIL mọi bảng ở cấu trúc, Trái yêu cầu
- **Lịch sử:** vòng 1 — OK.

## D2 — Điều khiển nổi trên ảnh
- **Chốt:** Theo design và sửa DESIGN.md §10.3 thành ngoại lệ có tên: 'tier D editor được đặt băng nút, thanh cọ, thước xoay lên vùng ảnh; mỗi thứ là đĩa/thanh kính tối, chạm trong vùng của nó không tới ảnh'. Ảnh luôn fit vào vùng ảnh như hiện nay, nên ảnh dọc sẽ nằm dưới băng: chấp nhận, như Photos.
- **Vì sao:** DESIGN.md §10.3 và FS-03.09 §1 cấm control nổi trên ảnh (ảnh nuốt chạm, che ảnh). Design đặt lên ảnh: băng nút trên cùng (nổi, không còn dải đặc 52pt), thanh cọ dọc của Mask (IP4) và Heal (IP5) ở mép trái, thước góc xoay + nút Rotate/Flip của Transform (IP3). Không cho thì không giống design; cho thì phải sửa luật trong DESIGN.md và xử lý ảnh dọc 2:3 trên Duo trong (ảnh cao hết 669, băng và thanh cọ đè lên ảnh).
- **Đã cân nhắc:** Đưa hết vào cột — IP3/IP4/IP5/DI4/DI5/DC3 sẽ FAIL so design
- **Lịch sử:** vòng 1 — OK.

## D3 — Cỡ nút trên băng: 34 (iPad, Duo dọc, Duo ngoài) / 40 (Duo trong ngang)
- **Chốt:** Vẽ đúng 34 / 40 như design, nhưng vùng chạm mỗi nút 44×44 (khoảng cách 5 giữa nút trong nhóm thì vùng chạm chồng lên nhau, chia đôi ở giữa). Sửa DESIGN.md §13: 'cỡ vẽ theo bảng, vùng chạm luôn 44'. Mỗi nút có nhãn VoiceOver + .help (tooltip con trỏ trên iPad).
- **Vì sao:** DESIGN.md §13 nói tier D lên 44 ở regular width; design giữ 34 trên iPad 13" và 40 trên Duo ngang, chỉ icon (tên ở VoiceOver + tooltip con trỏ). Vẽ 44 thì design-parity FAIL mọi bảng; vẽ 34 mà vùng chạm cũng 34 thì dưới chuẩn 44 của HIG.
- **Đã cân nhắc:** Vẽ 44 theo DESIGN.md — Khác design 10pt mỗi nút, băng dài thêm ~100pt
- **Lịch sử:** vòng 1 — OK.

## D4 — Bỏ nút ⋯: các mục trong ⋯ đi đâu
- **Chốt:** Copy / Paste Edits ra thư viện như note 30/9 (Paste Edits ở thanh chọn, Copy/Paste ở ⋯ màn xem ảnh — đã có ở đó thì chỉ bỏ khỏi editor). Auto Sync vào menu Sync (như PH17). Rotate/Flip thành nút trên ảnh ở Transform (D2). Fit/Fill = chạm đúp ảnh. Use as Reference = giữ lâu một ô filmstrip. Source = hàng đầu danh sách Edit khi ảnh là cặp RAW+JPEG. Tools Panel trái/phải và Show/Hide Tools bỏ (cột cố định bên phải).
- **Vì sao:** Không bảng nào có ⋯. History · Reset All · Revert · Recall lên băng (đã có chỗ). Còn lại ~16 mục chỉ có trên màn rộng không có chỗ: Copy / Paste Edits, Use as Reference, Tools Panel trái/phải, Show/Hide Tools, Fit/Fill, Source (RAW/JPEG), Auto Sync, Rotate/Flip. Bỏ âm thầm là mất chức năng (luật 'điện thoại có mọi chức năng iPad' cũng chạy chiều ngược).
- **Đã cân nhắc:** Giữ một ⋯ nhỏ cuối băng cho phần còn lại — Khác design: nút thừa, design-parity báo EXTRA ở mọi bảng
- **Lịch sử:** vòng 1 — OK.

## D5 — Duo trong dọc 669×951 (12 bảng DIP)
- **Chốt:** Mở xoay, chỉ cho editor và chỉ trên màn trong của Duo: plist iPhone cho phép mọi hướng, còn lúc chạy app trả về dọc ở mọi nơi khác (iPhone thường, Duo ngoài, mọi màn không phải editor). Editor trên Duo trong xoay 951×669 ↔ 669×951 và ở 669×951 đi đường iPhone (narrowBody) theo 12 bảng DIP. Chụp: bạn mở gập simulator bằng tay, ui-drive xoay (không mở đầu bằng orientation), sim-shot inner.
- **Vì sao:** App hiện không vào được cửa sổ này: target iPhone khoá dọc nên trên màn trong app luôn nhận cảnh ngang 951×669 (đã chụp, có test EditorPanelLayoutTests:457). Muốn có 669×951 phải mở xoay cho iPhone target — trái D24–D28 (Video Studio iPhone chỉ dọc) và đổi mọi màn khác của app trên Duo. Simulator Duo cũng không có lệnh mở gập/xoay để chụp.
- **Đã cân nhắc:** Bỏ khỏi đợt này, ghi rõ — Không đủ 60 bảng như yêu cầu; Code layout, chứng minh bằng test metrics — Code không ai chạy tới; AC chỉ 'tính', không 'chụp'
- **Lịch sử:** vòng 1 — OK, chọn 'Mở xoay' (khác đề xuất 'Bỏ khỏi đợt này'); chat — phạm vi: chỉ editor, chỉ Duo trong.

## D6 — Sheet Save: công tắc Include Metadata
- **Chốt:** Lấy bố cục sheet của design (giữa màn, 540 iPad / 480 Duo trong / rộng 466 từ đáy trên Duo ngoài; JPEG | HEIC, nút Save Copy / Save Changes). Giữ hành vi code: dòng metadata chỉ áp cho Save Copy, là bộ chọn 3 mức như hiện nay đặt ở chỗ công tắc; Save Changes giữ hết. Sửa chú thích trên canvas cho khớp. Giữ cả hai hàng nhiều ảnh (Save Changes to N Photos / Save N Copies) mà bảng không vẽ.
- **Vì sao:** IP12/DI12/DC12 vẽ công tắc 'Include Metadata' và chú thích nói tắt đi thì Save Changes cũng xoá ngày/vị trí. Code: Save Changes luôn giữ mọi metadata, Save Copy có bộ chọn 3 mức (FS-03.08.06 vừa làm xong AC-12). Theo design là xoá metadata ảnh gốc trong thư viện — không lấy lại được.
- **Đã cân nhắc:** Theo design: switch cho cả hai — Save Changes xoá ngày/vị trí khỏi ảnh gốc, Viết lại FS-03.08.06
- **Lịch sử:** vòng 1 — OK.

## D7 — Heal: Remove hay Red Eye
- **Chốt:** Theo code: Heal · Clone · Red Eye. Sửa bảng IP5, IPP6, DI5, DIP5, DC5 trên canvas cho khớp. Danh sách điểm có nút ẩn từng điểm (mới) thì làm — cần thêm một trường ẩn/hiện cho mỗi điểm sửa.
- **Vì sao:** IP5/DI5 vẽ Remove · Heal · Clone (Remove đang chọn), không có Red Eye. Code và FS-03.15c §6 (D66): Remove ngoài phạm vi, có Red Eye. Hàng iPhone (PH13) đã theo code. Theo bảng là thêm một chức năng lớn (xoá vật thể) không có trong spec.
- **Lịch sử:** vòng 1 — OK.

## D8 — Reset All trên băng vẫn hỏi lại
- **Chốt:** Nút trên băng như design; chạm vẫn mở xác nhận 'Reset All Adjustments?' như hiện nay. Revert to Original cũng vậy.
- **Vì sao:** Design đặt Reset All thành nút ngay trên băng, cạnh History. FS-03.09 §5 cố ý để nó trong ⋯ kèm xác nhận vì chạm nhầm là mất mọi chỉnh sửa (undo có cứu được nhưng người dùng không biết).
- **Lịch sử:** vòng 1 — OK.

## D9 — Chấm 'đã sửa' trên filmstrip màu cam
- **Chốt:** Giữ trắng như code (DESIGN.md: accent chỉ trên Save, AC-40). Sửa bảng IP7/IPP3/DI7/DC7 trên canvas.
- **Lịch sử:** vòng 1 — OK.

## D10 — Ô công cụ khác trong lúc đang ở trong công cụ (Duo ngoài)
- **Chốt:** DC3/DC4…: dải 84 vẫn hiện 6 ô, ô đang dùng sáng. Chạm ô khác khi đang trong công cụ: không làm gì, các ô khác mờ 38% và disabled — phải ✕ hoặc ✓ trước, giống iPhone (ở iPhone dải công cụ biến mất khi vào công cụ).
- **Lịch sử:** vòng 1 — OK.

## D11 — Transform trên ảnh: khung chữ L, thước góc xoay, Rotate/Flip trên ảnh
- **Chốt:** Làm một bản cho mọi thiết bị, kể cả iPhone theo PH07–PH10. Giữ slider Geometry 'Rotate' (là xoay phối cảnh, khác góc nghiêng) nhưng đổi nhãn hiển thị không trùng số với thước.
- **Vì sao:** Code: khung cắt 18pt núm tròn, lưới 1/3 luôn hiện, slider Angle trong panel, Rotate/Flip trong ⋯. Design (IP3, DI3, DC3, PH07): khung trắng 1,5 góc chữ L 20×3 + vạch giữa cạnh, thước 44pt dưới ảnh vuốt ±45° hít 0, lưới mịn 8×8 khi xoay, ảnh tự phóng không lộ góc, xoay hai ngón, bỏ slider Angle. Chỉ làm màn rộng thì phải giữ hai bản khung cắt.
- **Đã cân nhắc:** Chỉ màn rộng — Hai bản khung cắt, iPhone lệch hàng PH trên canvas
- **Lịch sử:** vòng 1 — OK.

## D12 — Lớp chữ đang chọn: khung trắng, 4 chấm, núm xoay
- **Chốt:** Làm cho mọi thiết bị theo note 30/9 (cùng code overlay). Không dùng accent.
- **Vì sao:** Code đã từng thử tay nắm và bỏ (comment ở EditorOverlayGuides.swift:160-199, núm 22pt che chữ nhỏ). Design (IP6, DIP6) đưa lại kiểu khác: chấm 10pt và núm 24pt nằm NGOÀI chữ, kéo góc tính theo tâm nên đúng cả khi chữ nghiêng, hít 0/90/180/270 có rung, chip độ.
- **Lịch sử:** vòng 1 — OK.

## D13 — Hàng chữ B · I · U | căn lề | Size − 200 px +
- **Chốt:** Làm cho mọi thiết bị (iPhone theo PH15). Thêm underline vào kit, có test render.
- **Vì sao:** Cần trường Underline mới trong PhotoOverlay ở ShotDexKit + renderer vẽ gạch chân (đổi recipe: app chưa release nên không cần migration). Size hiện bằng px của ảnh đang sửa, lưu vẫn là tỉ lệ cạnh ngắn; −/+ bước 1% cạnh ngắn, chạm số để gõ px. Cột 260/280: căn lề thu thành một nút xoay vòng.
- **Lịch sử:** vòng 1 — OK.

## D14 — Băng iPhone: bỏ ⋯, histogram 66×34, Save icon export
- **Chốt:** Không làm đợt này; iPhone giữ băng hiện tại. Mở intent riêng cho băng iPhone sau khi màn rộng xong.
- **Vì sao:** Note hàng iPhone có đề xuất 30/9 cho băng iPhone (Main.dc.html), nhưng bạn chỉ yêu cầu iPad + Duo. Làm D4 (bỏ ⋯ màn rộng) mà giữ ⋯ trên iPhone thì hai bên lệch nhau về chỗ của Copy/Paste, Fit/Fill…
- **Đã cân nhắc:** Làm luôn — Thêm phạm vi, phải verify lại FS-03.13a
- **Lịch sử:** vòng 1 — OK.

## D15 — Lưới loại Mask và loại lớp
- **Chốt:** Theo IP10/IP11 (14 loại vùng, 11 loại lớp, khớp code, ô 58). Sửa IP4/IPP2 (8 loại, có 'Range' không tồn tại, ô 54) và IP6/IPP7 ('Bubble' → 'Speech Bubble', ô 58) trên canvas.
- **Lịch sử:** vòng 1 — OK.

## D16 — Tỉ lệ crop 5:4
- **Chốt:** Giữ danh sách tỉ lệ của code (có 4:3, không có 5:4), xếp theo lưới 3 cột của design. Sửa IP3/IPP5/DIP4 trên canvas.
- **Lịch sử:** vòng 1 — OK.

## D17 — Số slider và Curve rút gọn ở IP1/DI1
- **Chốt:** Bảng chỉ vẽ mẫu: Light đủ 8 slider của code, Curve luôn có Point | Region + Reset như IP8/DI8. design-parity chỉ so chrome và thứ tự nhóm, không so số dòng.
- **Lịch sử:** vòng 1 — OK.

## D18 — Lỗi hình trong bảng
- **Chốt:** Sửa trên canvas: chip LUTs DI9 tràn quá 951; tiêu đề DC7 '320' → 270; đồ thị DC8 lố đáy panel; menu Sync IP7 đặt lại dưới nút Sync; Visualize Spots trùng ở DI5/IPP6; tiêu đề DI10 'cuộn' (thật ra không cuộn).
- **Lịch sử:** vòng 1 — OK.

## D19 — Màu, bo góc, khoảng cách ngoài token
- **Chốt:** Kích thước cấu trúc mới thành token tier D có tên (cột 280/260, histogram 256×120 / 236×80, filmstrip 96/72/56, đĩa băng 34/40, thước 44, thanh cọ 56). Số lẻ còn lại (bo, khoảng, cỡ chữ, alpha) dùng token gần nhất có sẵn — lệch ≤2pt, trong dung sai của design-parity — và sửa bảng về token đó khi tiện.
- **Vì sao:** Bảng dùng nhiều số không có trong DESIGN.md: bo 6/10/14/24, khoảng 5/6/9/10, kính 0.72/0.82, nền #0e0e0e, chữ 12.5/9.5. Thêm hết vào DESIGN.md là phình token; ép hết về token gần nhất thì lệch bảng 1–2pt.
- **Lịch sử:** vòng 1 — OK.

## D20 — Tài liệu spec
- **Chốt:** FS-03.17 mới: 17 (luật chung + AC chung), 17a iPad, 17b Duo trong ngang, 17c Duo ngoài. FS-03.09 §3–7 và FS-03.13d §3 ghi 'thay bởi FS-03.17', AC cũ bị thay thì đánh dấu, không xoá. Intent gốc: 2026-09-22-editor-panel-lightroom-layout (màn rộng) + 2026-09-27-editor-iphone-layout (Duo ngoài).
- **Lịch sử:** vòng 1 — OK.

## D21 — Sửa canvas cùng lượt
- **Chốt:** Sau khi chốt planboard, sửa các bảng bị quyết định đổi ngay trên canvas (một lượt publish), rồi mới viết AC và render lại build/design/editor/render.
- **Vì sao:** Luật của bạn: design và code luôn khớp. design-parity so với bảng; bảng sai (D6, D7, D9, D15–D18) thì code đúng vẫn FAIL, hoặc code bị ép theo bảng sai.
- **Lịch sử:** vòng 1 — OK.

## D22 — Chứng minh: design-parity PASS từng bảng
- **Chốt:** Mỗi bảng là một AC, chứng minh bằng 'design-parity PASS' + đường dẫn ảnh. Vòng: code → build → ui-drive/sim-shot → design-parity → sửa → lặp tới PASS. Thiết bị: iPad Pro 13" M5 iOS 26.5 (+18.6 cho nhánh pre-26), iPhone Duo iOS 27. Khi tới bảng DI, tôi nhắn bạn mở gập simulator.
- **Vì sao:** Một AC 'giống bảng X' chỉ kiểm được bằng số: dump ui-drive so khung từng nút với bảng (±2pt vị trí, ±1pt cỡ) + nhìn hai ảnh. Duo: simulator boot ở trạng thái gập, không có lệnh mở; bảng DI cần bạn mở gập bằng tay một lần mỗi lượt chụp.
- **Lịch sử:** vòng 1 — OK.
