# FS-03.17c — Editor iPhone Duo màn ngoài 466×678

`FS-03.17c` · tier D · `Features/Editing/` · cập nhật 2026-10-01

**Một câu:** gập Duo lại, editor dùng hết màn 466×678: ảnh và panel ở 382pt bên trái, sáu công cụ và Save nằm
**trong** dải 84pt bên phải. Luật chung: [17](17-wide-design.md) §3. Thay [FS-03.13d](13d-presets-batch-devices.md)
§3 và AC-44/45.

## 1. Vì sao dải 84 dùng được

FS-03.13d giữ mọi thứ ở x < 382 vì đo 19/9 thấy hệ thống vẽ status bar và rail ở đó. Đo lại 30/9: khi status bar
ẩn — editor luôn ẩn — hệ thống không vẽ gì trong x382–466 và chạm tới app. Chỉ ba vùng không dùng: lỗ camera
(x400–437, y29–66, phủ bằng mũ 72pt), góc bo dưới từ y≈612, dải 0–19pt sát mép trên. Còn status bar (màn khác
dưới TabView) thì dải vẫn bị nuốt — nên luật này **chỉ cho màn toàn màn hình ẩn status bar**. DESIGN.md §10.1b
ghi ngoại lệ có tên.

## 2. Khung (mọi bảng `DC*`)

| Vùng | Số |
|---|---|
| Băng | y9, đĩa 34, không dải nền: Back 16 · Undo 62 · Redo 101 · History 147 · Reset All 186 · Revert 225 · Recall 264 · histogram 46×28 ở 310 |
| Tên công cụ trên băng | không có, kể cả trong công cụ (ô sáng trên dải và VoiceOver nói tên) |
| Vùng ảnh | x0 y52, 382×356 |
| Panel | x0 y408, 382×270 tới đáy, bo trên 22 |
| Dải 84 | x382–466, nền tối hơn panel, viền trái 1pt; mũ 72 trống |
| Ô công cụ | x393, 64×56, từ y80 bước 60 (tới y436); ô đang dùng nền trắng 8% chữ trắng; còn lại 38% |
| Save | đĩa accent 44 ở y560–604, icon export |
| Trong công cụ | 6 ô vẫn hiện, ô đang dùng sáng, ô khác mờ và không chạm được (D10); ✕ đĩa kính 44 ở y508–552; ✓ đĩa trắng 44 ở y560–604 thay Save; Save ẩn tới khi ra |
| Không Compare | giữ lâu trên ảnh |

## 3. Theo màn

- **Nhiều ảnh** (DC7): filmstrip 56 ở y352–408, ảnh còn 300 cao, panel giữ 270.
- **Curve** (DC8): nhóm trong Edit; đồ thị + cột 4 kênh 158×34 bên phải; Save vẫn hiện, ô Edit sáng.
- **Presets, My Looks** (DC2/DC9): lưới **3 cột**. **Mask mới, lớp mới** (DC10/DC11): lưới **4 cột** ô 85×58.
- **Transform** (DC3): thước rộng 350 vừa khung ảnh 382.
- **Mask** (DC4): hàng cọ trong panel (không thanh nổi — ảnh chỉ cao 356).
- **Save** (DC12): sheet từ đáy rộng cả 466, bắt đầu y150, bo trên.

⚠️ CẦN QUYẾT: **băng trong dải chết 0–19pt**. Băng ở y9–43 nên 10pt trên của mỗi đĩa nằm trong dải không nhận chạm (đo
trên simulator). Phương án: (a) giữ y9 như bảng, vùng chạm 44 mở xuống dưới (y9–53) nên vẫn đủ 34pt chạm được; (b) hạ
băng xuống y19, ảnh mất 10pt, sửa bảng. Đề xuất (a).

⚠️ CẦN QUYẾT: **lỗ camera** — simulator vẫn nhận chạm trong lỗ, nên số đo lỗ và góc bo là hình mask, chưa phải máy thật.
Đề xuất: giữ mũ 72 như bảng, ghi rủi ro, đo lại khi có máy.

## 4. Tiêu chí nghiệm thu

Thiết bị: iPhone Duo iOS 27, gập. Chụp `Tools/sim-shot <udid> out.png cover`. Script:
`ShotDexUITests/scripts/fs0317-duo-cover.json` (⚠️ chưa có; thay `duo-cover-editor.json`).

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-43 | Duo gập | mở ảnh, đi qua các màn như AC-18…AC-28 | `design-parity` PASS `DC1`…`DC12` (12 bảng) | ⚠️ chưa có |
| AC-44 | Duo gập, Edit | dump | Save và 6 ô nằm trong x382–466 × y72–612; không phần tử nào trong mũ y0–72 của dải | ⚠️ chưa có — thay AC-44 của 13d |
| AC-45 | Duo gập, trong Transform | dump; chạm ô Mask | ✕ ở y508–552, ✓ ở y560–604, không có Save; chạm Mask không đổi công cụ | ⚠️ chưa có — thay AC-45 của 13d |
| AC-46 | Duo gập, trong Transform | chạm ✓ | ra Edit; Save hiện lại ở y560–604; crop đã áp | ⚠️ chưa có |
| AC-47 | Duo gập, Edit | chạm Back ở điểm (33, 46) — trong vùng chạm 44, dưới phần vẽ 34 | editor đóng | ⚠️ chưa có |
| AC-48 | Duo gập, màn thư viện (status bar hiện) | dump | không phần tử nào của app ở x ≥ 382 — ngoại lệ chỉ cho editor | ⚠️ chưa có |
| AC-49 | Duo mở, trong editor dọc | gập máy | editor ở màn ngoài theo bảng `DC*` tương ứng, chỉnh sửa còn nguyên | ⚠️ chưa có — cần người gập bằng tay |

**Chưa chứng minh được:** AC-43…AC-49 — chưa có code.
