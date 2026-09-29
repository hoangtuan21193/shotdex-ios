# FS-03.13d — Presets, sửa nhiều ảnh, Duo màn ngoài

`FS-03.13d` · tier D · `Features/Editing/EditorSession.swift` · cập nhật 2026-09-28

**Một câu:** Presets thành lưới 4 cột cuộn dọc, giữ lâu một ô là quản lý look đó; sửa nhiều ảnh có filmstrip 56pt tự
ẩn khi vào công cụ; Duo màn ngoài đưa công cụ — và ✕ / ✓ khi ở trong công cụ — lên cột dọc cạnh rail.

Khung: [13a](13a-chrome-and-toolbar.md). Look và My Looks: [FS-03.02](02-film-simulation-and-presets.md); nhập / xuất /
chia sẻ look: [FS-03.14](14-lightroom-preset-exchange.md). Phiên nhiều ảnh: [FS-03.09b](09b-batch-editing-and-reference.md).

## 1. Presets

- Không ✕ / ✓: chạm một ô là áp. Từ trên xuống: dải nguồn **Presets · My Looks · LUTs** (3 chip chia đều) · hàng
  **Amount** (chỉ khi có look, 0…100, mốc 100) · đường kẻ · **lưới 4 cột** cuộn dọc.
- Ô lưới: thumbnail cao 62 bo 8 + tên 11pt trắng 60% dưới, hàng cao 90. Đang chọn = vòng trắng của swatch
  ([FS-03.12 §4](12-phone-panel-grid.md#4-chip-và-dải-chọn)), còn lại mờ 80%. Thay dải thumbnail cuộn ngang của FS-03.02 §8.
- **My Looks**: hai ô đầu **Save Current** (mờ khi recipe là identity) và **Import XMP Preset**; sau đó các look.
  Save Current giữ như hôm nay: đặt tên, không chọn nhóm; hint *"Saves tone, color, curve and film look. Crop, masks
  and markup stay with this photo."* Chưa có look nào thì dưới hai ô là *"Save an edit here and it can be put on any photo."*
- **LUTs**: ô đầu là **Import .cube** như FS-03.12 §4.
- **Giữ lâu bất kỳ ô look nào** — ở Presets, My Looks hay LUTs — → menu **Rename · Share · Export As ▸ · Delete**.
  Export As mở ba dòng ShotDex Look (.shotdexlook) · **Export XMP Preset** (.xmp) · LUT (.cube).
- **Delete không hiện với preset có sẵn trong app**; ba mục kia vẫn có. Ô hành động (Save Current, Import XMP
  Preset, Import .cube) không có menu.
- **Không có màn Manage Looks**, không chọn nhiều, không kéo sắp xếp: kéo một ô chỉ cuộn lưới. Share mỗi lần một look.
- Look nhập từ preset ngoài mang nhãn **"Imported"**. Nhãn, câu giải thích XMP và hành vi mọi mục thuộc
  [FS-03.14](14-lightroom-preset-exchange.md).

## 2. Sửa nhiều ảnh

- **Filmstrip 56** giữa ảnh và panel; panel vẫn theo luật 344 / 264 với F = 56 ([13a §2](13a-chrome-and-toolbar.md#2-chiều-cao-panel)).
- Ô **44** bo **6** (`r-track` của `DESIGN.md` §5), cách nhau 8, lề trái 12, fade phải 28. Ảnh đang sửa: **vòng trắng**
  1,5pt cách 2 và độ mờ 100%; ảnh khác 75%.
- Badge: **chấm trắng 8** góc dưới phải = có nháp chưa lưu · **✓** trong đĩa đen 65% cỡ 14 = đã lưu. Không accent.
- Cuối filmstrip: pill **Sync** cao 32 (nền trắng 12%, icon + chữ 12,5pt đậm) và "2 / 7" mono 10pt bên dưới.
  Chạm Sync → menu **Sync Look to N Photos** (dòng phụ "Tone, color, curve and look") · **Sync Everything to N Photos**
  · **Apply Previous** · **Auto Sync** (công tắc). Hành vi giữ FS-03.09b §3.
- Menu Sync **luôn 4 mục**: Apply Previous **mờ** khi chưa có ảnh trước để áp, không ẩn (chốt E5).
- **Sync chỉ ở đây**, không ở ⋯ — một hành động, một chỗ. Tràn viền thì chạm đôi để filmstrip hiện lại.
- **Vào công cụ → filmstrip ẩn**, panel nhận lại 56, khung ảnh **đứng yên**. Vì mask, vết, lớp là của một ảnh: đổi
  ảnh giữa chừng công cụ dễ nhầm. Ra công cụ thì filmstrip hiện lại.
- Filmstrip là vùng cuộn ngang được phép duy nhất cạnh slider. Ẩn khi tràn viền. Thumbnail tải theo thang của FS-03.09b §2.
- Panel theo **ảnh đang mở**: lướt từ ảnh 3:2 sang ảnh 3:4 thì panel 344 → 264 ([13a §2](13a-chrome-and-toolbar.md#2-chiều-cao-panel)).

## 3. Duo màn ngoài

- Vùng app 382×644 (rail iOS 84 bên phải, đáy 34). **Cột công cụ 56** ở x 326–382, trong vùng an toàn, sát rail:
  **Save** 36 accent trên cùng, rồi 6 ô công cụ 52×54 xếp dọc, vạch 16×2 dưới ô đang chọn.
- Nhãn ô cột **10,5pt** (token nhãn tab). "Transform" phải vừa ô 52; đo thấy cắt mới thêm token 9,5 vào `DESIGN.md`.
- Băng trên cao 44, không có đảo: Back · Undo · Redo … **histogram 40×28** · ⋯. Ảnh 326×300 dưới băng.
- **Danh sách cố định 300** (326×300 dưới ảnh, bo 22), không theo luật 344 / 264 của iPhone.
- **Vào công cụ: ✕ và ✓ vào cột**, thay chỗ 6 ô công cụ — Save · ✕ tròn 38 · ✓ 52×38 nền trắng; không ô chết.
  Tên công cụ 14pt đậm ở giữa băng trên. ✓ / ✕ làm đúng như iPhone ([13a §5](13a-chrome-and-toolbar.md#5-vào-và-ra-một-công-cụ)).
- Hàng Mask giữ chữ **"Mask Overlay"**; chỉ rút thành "Overlay" trên màn này nếu đo thấy cắt (AC-32 fail).

## 4. Tiêu chí nghiệm thu

Máy: iPhone 17 iOS 26.5 và 18.6; iPhone Duo 27.1 cho AC-44, AC-45. Tiếp số của 13c.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-37 | 49 look, ảnh 3:2 (panel 344) | chạm Presets | lưới 4 cột, 13 hàng, chỉ cuộn dọc; chạm Velvia → look áp, hàng Amount hiện ở 100 | ✅ `EditorPanelLayoutTests.presetGridIsFourColumnsOfThirteenRows` · `iphone-presets-grid.json` (lưới 4 cột, ô 87×80 + khe 10 = hàng 90, cuộn dọc; chạm Velvia → hàng Amount 100%) |
| AC-38 | recipe identity, 0 look đã lưu | chạm My Looks | ô 1 Save Current mờ, ô 2 Import XMP Preset sáng, dòng "Save an edit here…" hiện; chạm nó mở bộ chọn tài liệu hệ thống | ⚠️ một phần — `iphone-my-looks.json`: Save Current mờ khi recipe identity, dòng "Save an edit here…" hiện; ô Import XMP Preset + bộ chọn tài liệu chờ bộ nhập FS-03.14a |
| AC-39 | My Looks có 6 look, 1 LUT đã nhập | giữ lâu 0,6s lần lượt "Forest", Velvia (Presets), LUT đã nhập; rồi kéo Forest sang ô khác | Forest và LUT: đúng 4 mục Rename · Share · Export As · Delete, Export As đúng 3 định dạng; Velvia: 3 mục, không Delete; kéo không đổi thứ tự | ⚠️ chưa có — `iphone-presets-grid.json` |
| AC-40 | phiên 7 ảnh, đang ở ảnh 2, 3 ảnh có nháp, 1 ảnh đã lưu | chụp màn Edit, rồi chạm Sync | filmstrip cao 56 giữa ảnh và panel, ô 44 bo 6, vòng trắng ở ô 2, 3 chấm, 1 ✓, "2 / 7"; 0 px accent ngoài Save; menu Sync đúng 4 mục (Apply Previous mờ nếu phiên chưa có ảnh trước) | ✅ `iphone-batch-filmstrip.json` (phiên 7 ảnh: dải 56 giữa ảnh và panel, ô 44 bo 6, vòng trắng ở ảnh đang sửa, chấm nháp, "2 / 7"; menu Sync đúng 4 mục, Apply Previous mờ khi chưa có ảnh trước) · `Tools/accent-check` = 0 px accent ngoài Save; badge ✓ đã lưu chưa chụp (cần lưu một ảnh trong phiên) |
| AC-41 | như AC-40, ảnh 3:2 | chạm Mask | filmstrip biến mất, panel 400, khung stage không đổi (±0,5pt); ✓ → filmstrip hiện lại, panel 344 | ✅ `EditorPanelLayoutTests.batchPanelCountsTheFilmstrip` · `iphone-batch-filmstrip.json` (dump khung stage 402×412 ở y 62 trước, trong Mask và sau ✓ — panel 400 trong Mask, filmstrip ẩn rồi hiện lại) |
| AC-42 | phiên nhiều ảnh, ảnh đang mở 3:4 | chụp màn Edit, rồi chạm ô một ảnh 3:2 | panel 264, stage cao 874 − 62 − 56 − 264 = 492, ảnh 369×492; sang ảnh 3:2 thì panel 344 | ✅ `EditorPanelLayoutTests.batchPanelCountsTheFilmstrip` (3:4 → 264, stage 492, ảnh 369×492; 3:2 → 344) |
| AC-43 | Mask Brush, 3 nét, trong công cụ | giả lập cảnh báo thiếu bộ nhớ | không crash; vẫn trong công cụ, 3 nét còn; ✕ vẫn trả về lúc vào | `EditorHistoryAndSummaryTests.memoryWarningKeepsTheToolSession` (`handleMemoryWarning` nhả thumbnail, giữ recipe, lịch sử, phiên công cụ) |
| AC-44 | Duo màn ngoài 466×678 | mở Edit | Save + 6 ô trong x 326–382, không phần tử nào ở x ≥ 382; băng có histogram; danh sách 326×300 dưới ảnh; không nhãn nào thành "…" | ⚠️ chưa có — `duo-cover-editor.json` + `Tools/sim-shot … cover` |
| AC-45 | như AC-44 | chạm Mask, vẽ 1 nét, rồi ✓ trong cột | lúc trong Mask cột chỉ có Save · ✕ · ✓, không ô công cụ nào; băng đọc "Mask"; sau ✓ cột về 6 ô, nét còn | ⚠️ chưa có — `duo-cover-editor.json` + dump |

**Chưa chứng minh được:** AC-37…AC-45 — chưa có code.
