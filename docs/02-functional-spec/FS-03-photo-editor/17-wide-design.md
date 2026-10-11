# FS-03.17 — Editor iPad và iPhone Duo theo design canvas 30/9

`FS-03.17` · tier D · `Features/Editing/` · `ShotDexTests/EditorPanelLayoutTests.swift` · cập nhật 2026-10-01

**Một câu:** trên iPad và iPhone Duo, editor là ảnh cộng một cột (hoặc panel dưới) dựng từ chính các mảnh của
editor iPhone, với băng nút tròn nổi trên ảnh, đúng như 60 artboard trên
[design canvas](../../design/README.md) (hàng editor `IP*`/`IPP*` trên canvas iPad, `DI*`/`DIP*`/`DC*` trên canvas Duo).

Thay thế: [FS-03.09](09-wide-screen-and-batch-editing.md) §3–§7 (rail, panel đổi rộng, card gập, thanh cam kết
`[↺] Cancel Apply`) và [FS-03.13d](13d-presets-batch-devices.md) §3 + AC-44/45 (Duo màn ngoài). Quyết định:
planboard `fs0317-wide-design` (D1–D22, chốt 2026-10-01). Intent:
[editor-panel-lightroom-layout](../../_intents/2026-09-22-editor-panel-lightroom-layout.md) (màn rộng),
[editor-iphone-layout](../../_intents/2026-09-27-editor-iphone-layout.md) (Duo màn ngoài).

| Phần | Thiết bị | Bảng |
|---|---|---|
| [17a](17a-ipad.md) | iPad 13" ngang 1376×1032 · dọc 1032×1376 | `IP1…IP12`, `IPP1…IPP12` |
| [17b](17b-duo-inner.md) | Duo mở · ngang 951×669 · dọc 669×951 | `DI1…DI12`, `DIP1…DIP12` |
| [17c](17c-duo-cover.md) | Duo gập · màn ngoài 466×678 | `DC1…DC12` |

## 1. Người dùng cần gì

Người chụp mở một ảnh trên iPad hay trên Duo và thấy cùng một editor đã quen trên iPhone — cùng sáu công cụ,
cùng danh sách Edit, cùng cách vào/ra công cụ — chỉ là ảnh to hơn và mọi thứ nằm gần tay. Không có hai bộ
editor để học, và không mất chức năng nào khi đổi máy.

## 2. Phạm vi

**Có:** mọi trạng thái 60 bảng vẽ: Edit, Presets, My Looks, Transform, Mask (có và chưa có mask), Heal, Markup
(có và chưa có lớp), Curve, nhiều ảnh, Save.

**Cố ý không có:**
- Băng nút iPhone (bỏ ⋯, histogram 66×34, icon Save export) — để intent sau (D14). Hàng `PH*` chỉ đổi ở ba chỗ
  dùng chung ở §5.
- Remove (xoá vật thể) trong Heal — giữ D66 của FS-03.15c (D7).
- Xoay ngang cho iPhone thường, và cho mọi màn khác ngoài editor trên Duo (D5).

## 3. Luật chung — mọi bảng iPad và Duo

- **Bố cục** (D1): ảnh chiếm phần còn lại; một cột cố định bên phải (iPad 280, Duo trong ngang 260) hoặc một
  panel dưới cố định (Duo trong dọc 400). Không rail, không kéo đổi rộng, không thu gọn, không chọn trái/phải.
  Trong cột: histogram → danh sách Edit phẳng của iPhone (nhãn nhóm `LIGHT ▼`, chạm là mở mục lục nhóm) → dải
  6 công cụ ở chân: Presets · Edit · Transform · Mask · Heal · Markup.
- **Băng nút nổi trên vùng ảnh** (D2): không dải nền. Thứ tự Back | Undo · Redo | … | History · Reset All ·
  Revert to Original · Recall Last ShotDex Edit | Compare | Save — 12 giữa nhóm, 5 trong nhóm. Duo ngoài và
  Duo trong dọc không có Compare (giữ lâu trên ảnh để so).
- **Nút băng** (D3): đĩa kính tối chỉ icon, vẽ 34 (iPad, Duo dọc, Duo ngoài) hoặc 40 (Duo trong ngang), vùng
  chạm luôn 44×44. Tên ở nhãn VoiceOver và tooltip con trỏ trên iPad.
- **Save**: đĩa accent, icon export, luôn ở cuối băng — kể cả trong công cụ trên iPad và Duo trong ngang. Trên
  Duo ngoài và Duo trong dọc theo §17b/§17c.
- **Reset All và Revert** vẫn hỏi lại bằng hộp xác nhận như hôm nay (D8). Revert và Recall mờ khi không có gì để
  làm, không biến mất (băng không nhảy chỗ).
- **Trong công cụ** (Transform, Mask, Heal, Markup, Mask mới, lớp mới): dải công cụ ở chân cột thành
  `✕ · tên · ✓`, ✓ là đĩa trắng, ✕ kính. Không có thanh `[↺] Cancel Apply` nữa.
- **Không còn ⋯** (D4). Các mục cũ đi về: Copy / Paste Edits → thư viện (thanh chọn và ⋯ của màn xem ảnh);
  Auto Sync → menu Sync; Rotate 90° · Flip → hai đĩa kính 34 góc trên-trái vùng ảnh, chỉ trong Transform;
  Fit/Fill → chạm đúp ảnh; Use as Reference → giữ lâu một ô filmstrip; Source (RAW/JPEG) → hàng đầu danh
  sách Edit khi ảnh là cặp. Tools Panel trái/phải và Show/Hide Tools bỏ.
- **Thanh nổi trên ảnh** (D2): thanh cọ dọc của Mask và thanh Heal ở mép trái vùng ảnh (iPad 56 rộng; Duo trong
  bản gọn, Size là nút kéo ngang). Chạm trong thanh không tới ảnh; một ngón ngoài thanh vẫn là vẽ.
- **Sheet Save** (D6): bố cục của bảng (JPEG | HEIC, Save Copy, Save Changes) nhưng dòng **Metadata** là bộ chọn
  ba mức như hôm nay, **chỉ áp cho Save Copy**; Save Changes giữ hết. Giữ hai hàng nhiều ảnh và cảnh báo HEIC.
- **Chấm "đã sửa"** trên filmstrip trắng, không accent (D9).
- **Số**: kích thước cấu trúc là token tier D có tên (cột 280/260, panel 400, histogram 256×120 / 236×80, filmstrip
  96/72/64/56, đĩa băng 34/40, thước 44, thanh cọ 56). Bo, khoảng, cỡ chữ lẻ của bảng dùng token gần nhất có sẵn,
  lệch ≤2pt (D19).

## 4. Nhãn và tiếng

Nhãn VoiceOver đúng `aria-label` của bảng: `Back`, `Undo`, `Redo`, `History`, `Reset All`, `Revert to Original`,
`Recall Last ShotDex Edit`, `Compare with original`, `Save`, `Histogram`, `Tools`, `Jump to group, now <NHÓM>`.
`design-parity` khớp phần tử theo nhãn, nên đổi nhãn là đổi spec.

## 5. Dùng chung với iPhone (đổi luôn hàng `PH*`)

- **Transform trên ảnh** (D11): khung cắt trắng 1,5pt có bóng, góc chữ L 20×3, vạch giữa cạnh; lưới 1/3 khi kéo,
  lưới mịn 8×8 khi xoay; thước 44pt ở đáy vùng ảnh vuốt ngang ±45°, hít 0 kèm rung, chạm số về 0; xoay hai ngón
  cùng giá trị; ảnh tự phóng không lộ góc. Panel bỏ slider Angle; giữ Aspect, Upright, Geometry.
- **Lớp đang chọn** (D12): khung trắng 1,5pt cách chữ 6pt, 4 chấm trắng 10pt ở góc, núm xoay 24pt trên cần 16pt,
  chip độ khi xoay, hít 0/90/180/270 kèm rung. Kéo góc phóng đều quanh tâm, kể cả khi lớp nghiêng. Không accent.
- **Hàng chữ** (D13): B · I · U | căn lề | Size − N px +. Gạch chân là thuộc tính mới của lớp chữ, render ra ảnh.
  Size hiện bằng px của ảnh đang sửa, lưu vẫn là tỉ lệ cạnh ngắn; −/+ bước 1% cạnh ngắn; chạm số để gõ px.

## 6. Ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Thiết bị | iPad Pro 13" M5 iOS 26.5 + 18.6 · iPhone Duo iOS 27 (màn trong ngang/dọc, màn ngoài) · iPhone 17 cho §5 |
| iOS 26 vs trước | iPad chạy cả hai nhánh; băng nổi giống nhau ở hai nhánh (không dùng chrome hệ thống) |
| Hiệu năng | thước xoay và tay nắm lớp cập nhật preview ở tần số khung như slider ([NF-01](../../04-non-functional-design/NF-01-performance.md)) |
| Truy cập | mọi đĩa icon-only có nhãn; thước có `adjustable` ±0.1° |
| Dữ liệu | gạch chân và ẩn điểm Heal là trường mới trong recipe — app chưa release, không migration; decode vẫn khoan dung |

## 7. Tiêu chí nghiệm thu chung

Mỗi bảng là một AC ở 17a–17c, chứng minh bằng **`design-parity` PASS** trên bảng đó: dump `Tools/ui-drive` so với
`Tools/design-board render` (thiếu / thừa / lệch >2pt vị trí, >1pt cỡ) và nhìn hai ảnh. Phần dưới là hành vi
không vẽ được trên bảng tĩnh.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | iPad, ảnh đã sửa | chạm Reset All trên băng | hộp xác nhận hiện; Cancel thì ảnh không đổi | ⚠️ chưa có — `fs0317-ipad.json` |
| AC-2 | iPad, ảnh chưa từng lưu bằng ShotDex | nhìn băng | Revert và Recall hiện, mờ, chạm không làm gì; vị trí 5 nút còn lại không đổi | ⚠️ chưa có |
| AC-3 | ảnh RAW+JPEG | mở Edit | hàng Source đứng đầu danh sách, đổi được RAW ↔ JPEG | ⚠️ chưa có |
| AC-4 | 5 ảnh, Auto Sync tắt | mở menu Sync, bật Auto Sync, kéo Exposure +1 | 4 ảnh kia nhận Exposure +1 | ⚠️ chưa có |
| AC-5 | 5 ảnh | giữ lâu ô thứ 3 filmstrip → Use as Reference | Reference View mở với ảnh 3 | ⚠️ chưa có |
| AC-6 | ảnh fit | chạm đúp ảnh | chuyển Fill; chạm đúp lần nữa về Fit | ⚠️ chưa có |
| AC-7 | Save Copy, Metadata = No Metadata | Save Copy | bản sao không EXIF; ảnh gốc giữ ngày + vị trí | `MetadataLevelTests`, `MetadataRewriterTests` (có, hành vi không đổi) + ⚠️ ui-drive cho sheet mới |
| AC-8 | Save Changes | lưu | ngày, vị trí, EXIF ảnh gốc giữ nguyên, bất kể Metadata đang chọn gì | ⚠️ chưa có |
| AC-9 | Transform, góc 0 | vuốt thước +3,2° rồi thả gần 0,3° | dừng 0,3°; vuốt về −0,2° thì hít 0 kèm rung | ⚠️ chưa có |
| AC-10 | Transform, góc 7° | chạm số trên thước | góc về 0 | ⚠️ chưa có |
| AC-11 | Transform | xoay hai ngón 5° trên ảnh | thước hiện +5,0°; undo một lần về 0 | ⚠️ chưa có |
| AC-12 | lớp chữ nghiêng −8° | kéo chấm góc ra xa tâm gấp đôi khoảng cách | lớp to gấp đôi, tâm đứng yên, vẫn −8° | `OverlayHandleMathTests` ⚠️ chưa có |
| AC-13 | lớp chữ 0° | kéo núm xoay tới 88° | hít 90°, chip "90°", có rung | ⚠️ chưa có |
| AC-14 | lớp chữ, ảnh cạnh ngắn 4000px | chạm + ở Size | "200 px" → "240 px"; recipe lưu 0,06 cạnh ngắn | `TextOverlayLayoutTests` ⚠️ chưa có |
| AC-15 | lớp chữ bật U | Save Copy | ảnh xuất có gạch chân dưới chữ | `TextOverlayRenderTests` ⚠️ chưa có |
| AC-16 | Mask, đang vẽ | chạm Size trên thanh cọ nổi rồi kéo | cỡ cọ đổi; không nét nào vẽ lên ảnh | ⚠️ chưa có |
| AC-17 | iPhone 17 | mở Transform, chọn lớp chữ, mở hàng chữ | `design-parity` PASS trên `PH07_Transform`, `PH15_MarkupText` | ⚠️ chưa có |

**Chưa chứng minh được:** mọi AC trên — chưa có code.

## 8. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Thanh nổi và ảnh tranh nhau chạm | vùng chạm thanh ăn trước; AC-16 |
| Ảnh dọc 2:3 nằm dưới băng nổi | chấp nhận như Photos; bảng chỉ vẽ ảnh 3:2 nên 17b có AC riêng cho ảnh 2:3 |
| Mất chức năng khi bỏ ⋯ | §3 liệt kê chỗ mới của từng mục; AC-3…AC-6 |
| `design-parity` khớp theo nhãn | đổi nhãn VoiceOver phải đổi bảng và §4 cùng lượt |
