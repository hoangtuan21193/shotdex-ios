# FS-01.09 — Ghép nhiều ảnh: menu Combine Photos

`FS-01.09` · `ShotDexKit/Render/PhotoStackRenderer.swift` · `PhotoStackScreen` · `SelectionBarViews`
· cập nhật 2026-09-23 · nguồn [intent](../../_intents/2026-09-23-combine-photos-purpose-menu.md)

**Một câu:** chọn ≥ 2 ảnh → ⋯ → **Combine Photos ▸** → **Focus Stack**, **Panorama** hoặc **Stack Exposures**
→ một màn cho việc đó.

> Trạng thái: **đã build** (2026-09-23, plan [fs-01-09-combine-menu](../../_plans/2026-09-23-fs-01-09-combine-menu.md));
> bằng chứng từng AC ở §5.

## 1. Quy tắc

- Menu con **một cấp, ba dòng**, thứ tự cố định: **Focus Stack · Panorama · Stack Exposures**. Tên dòng là việc
  người chụp làm; không tên phép toán nào (`Average`, `Lighten`, `Darken`) nằm trong menu.
- **Stack Exposures** gom ba cách ghép cùng một kiểu chụp — nhiều lần bấm một khung cảnh, máy đứng yên — vào
  **một màn có bộ chọn** `Average · Lighten · Darken`, để thử cả ba trên cùng chuỗi mà không phải chọn lại ảnh.
- **Focus Stack** và **Panorama** là màn một việc, không có bộ chọn.
- Đổi chỗ không đổi ảnh: cùng khung vào thì ra **đúng từng pixel** như mode tương ứng trước đây.
- Renderer là **actor trong ShotDexKit** vì nó là render thuần. **Ghép lũy tiến** ở mọi việc → bộ nhớ phẳng
  theo số frame. Preview dựng ở 1600pt và dùng lại cho mọi lần đổi mode; chỉ khi Save mới nạp full-res.

## 2. Menu con và bộ chọn

| # | Dòng | Làm gì | Bên dưới | Câu giải thích trong màn |
|---|---|---|---|---|
| 1 | **Focus Stack** | lấy nét toàn cảnh — macro, phong cảnh gần-xa | điểm nét nhất (§4) | Keeps the sharpest part of every frame, for depth of field no single shot can reach. |
| 2 | **Panorama** | nối khung cạnh nhau | [FS-14](../FS-14-panorama/README.md) | (màn riêng của FS-14) |
| 3 | **Stack Exposures** | ghép nhiều lần bấm một khung cảnh | bộ chọn bên dưới | theo mode đang chọn |

Bộ chọn trong màn Stack Exposures, **mặc định `Average`**:

| Mode | Bên dưới | Câu giải thích (một dòng dưới bộ chọn) |
|---|---|---|
| **Average** | trung bình đều | Reduces noise, or smooths water and clouds like a long exposure. |
| **Lighten** | điểm sáng nhất | Keeps the brightest light from every frame — star trails, traffic, fireworks. |
| **Darken** | điểm tối nhất | Clears people and cars that moved between frames. Shoot from a tripod. |

- Tên mode giữ tên phép toán quen trong Photoshop và app chụp đêm; **câu giải thích nói dùng để làm gì** — tên
  và câu cùng hiện, không cái nào thiếu.
- Dòng mở menu con giữ tên **Combine Photos**, icon như hiện nay.
- **Panorama** mở màn của [FS-14](../FS-14-panorama/README.md); một dòng chỉ nằm trong menu khi màn phía sau nó đã có.
- Cả ba dòng **mờ** khi lựa chọn có < 2 ảnh; dòng Combine Photos vẫn mở được để thấy có những việc gì.
- Video trong lựa chọn bị bỏ qua, không làm mờ dòng nào.
- Mỗi dòng một icon SF Symbols có từ iOS 17 — chọn ở `/plan`, theo DESIGN §8.
- Menu có ở **cả bốn lưới** dùng lớp chọn chung: Library, Album Detail, Smart Album Detail, On This Day.
  Hiện chỉ Library cấp hành động này. *Vì* một chuỗi macro hay panorama thường nằm sẵn trong một album.

## 3. Màn

Tầng D (DESIGN §10.3, §10.3b): `Cancel` · tiêu đề · `Save`; stage đen; một panel.

- **Focus Stack**: panel là câu giải thích + dòng nhắc căn khung ("Frames are lined up before stacking…").
- **Stack Exposures**: panel là bộ chọn ba mode + câu giải thích của mode đang chọn. Đổi mode dựng lại preview
  từ khung đã nạp, không nạp lại.
- **Tiêu đề** là tên dòng, không kèm số ảnh: `Focus Stack`, `Stack Exposures`. Danh từ, đúng DESIGN §12; số
  ảnh đã hiện ở pill đếm của lưới vừa rời.
- **Cảnh báo lỗi** dùng một tiêu đề chung: `Couldn't Save` khi lưu hỏng, `Couldn't Load Photos` khi hỏng lúc
  dựng preview. Thân cảnh báo nói lý do cụ thể.
- **Cancel giữ lựa chọn**: về lưới vẫn còn nguyên các ảnh đã chọn, để thử việc khác ngay trên cùng chuỗi.
  **Save** thì thoát chế độ chọn.
- **Save xong mở ảnh vừa lưu trong viewer**, như FS-14 — một hành vi cho cả menu con. Ảnh mới nằm ở thư
  viện chung, không tự nằm trong album đang mở, nên theo màn đang đứng:
  - **Library**: mở viewer tại chỗ.
  - **Album do người dùng tạo** (thêm ảnh được): **thêm ảnh mới vào album đó**, rồi mở viewer tại chỗ — ảnh
    ghép nằm cạnh các khung gốc của nó.
  - **Smart Album, On This Day** (và album không cho thêm ảnh): chuyển sang tab Library và mở ảnh ở đó.
- Ảnh lưu là JPEG 0,95 mang EXIF của khung đầu (máy, ống kính, ngày, vị trí) — chung cho cả ba dòng, luật ở FS-01.10 §6.

## 4. Focus stack (thuật toán hiện tại — sẽ thay theo [FS-01.10](10-focus-stack.md))

1. Align mỗi frame bằng bộ căn ảnh theo tịnh tiến của hệ thống — **chỉ tịnh tiến**. Sẽ đổi theo
   [intent Helicon](../../_intents/2026-09-23-focus-stack-helicon-parity.md) (co giãn + xoay).
2. Dựng **bản đồ độ nét**: mono → Laplacian 3×3 → độ lớn phản hồi → box blur.
3. Ghép lũy tiến qua phép trộn theo mặt nạ — giữ pixel nét nhất.

Frame sau align phải kéo giãn mép ra vô hạn **trước khi** crop, nếu không mép hở thành viền trắng quanh ảnh.

## 5. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | Library, chọn 4 ảnh | mở ⋯ | có **một** dòng Combine Photos; không dòng Focus Stack/Panorama nào đứng riêng ở cấp ngoài | ✅ `combine-menu.json`, dump `01-menu-one-photo` (iPhone 17 Pro 26.5) |
| AC-2 | chọn 4 ảnh | ⋯ → Combine Photos | menu con ghi đúng ba dòng Focus Stack · Panorama · Stack Exposures, không dòng Average/Lighten/Darken nào (Panorama chỉ khi FS-14 đã build) | ✅ `combine-menu.json`, dump `03-submenu-three-photos` (26.5 và 18.6) |
| AC-3 | chọn 1 ảnh + 3 video | ⋯ → Combine Photos | mở được; mọi dòng mờ | ✅ dump `02-submenu-one-photo`: ba dòng `enabled: false` (26.5) |
| AC-4 | 4 khung cố định, cùng một bộ | chạy Focus Stack, rồi Stack Exposures ở cả ba mode | ảnh ra trùng từng pixel với mode Average, Lighten, Darken cũ | ✅ `PhotoStackRendererTests` + `CombinePurposeTests.everyStackModeIsReachableFromExactlyOneRow`. Focus Stack nay căn theo FS-01.10 — cố ý khác cũ |
| AC-5 | chọn 6 ảnh + 2 video | ⋯ → Combine Photos ▸ Stack Exposures | màn mở với 6 khung, tiêu đề `Stack Exposures`, bộ chọn `Average · Lighten · Darken` đang ở `Average`; không có Focus Stack trong bộ chọn | ✅ dump `04-stack-exposures-average` (Average `selected`) + ảnh (26.5, 18.6) |
| AC-6 | màn Stack Exposures, rồi màn Focus Stack | chạm lần lượt ba mode; mở màn Focus Stack | mỗi mode hiện đúng câu giải thích ở bảng §2; đổi mode không nạp lại khung; màn Focus Stack không có bộ chọn | ✅ dump `04`/`05`/`06` (câu đổi theo mode) và `08-focus-stack` (không nút mode) |
| AC-7 | iOS 26.5 và iOS 18.6 | mở menu con trên cả hai | cùng các dòng, cùng thứ tự, cùng trạng thái mờ | ✅ `combine-menu.json` trên iPhone 17 Pro 26.5 và iPad Pro 13 18.6 — cùng ba dòng, cùng thứ tự |
| AC-8 | iPhone 402×874, iPad 1376×1032, Duo trong 951×669 | mở menu con | cùng số dòng trên cả ba | ⚠️ hai phần ba: iPhone và iPad ✅; Duo chưa — màn trong không chụp được trên máy này (không có lệnh gập mở) |
| AC-9 | VoiceOver bật | vuốt tới dòng Combine Photos | đọc tên kèm "menu"; mỗi dòng con đọc đúng tên | ⚠️ chưa có — dump nhãn a11y |
| AC-10 | chọn 5 ảnh, màn Stack Exposures đang mở | Cancel | về lưới, vẫn đúng 5 ảnh được chọn; mở tiếp Combine Photos ▸ Focus Stack được ngay | ✅ `combine-menu.json` với 3 ảnh: dump `07-after-cancel` còn `Show Selected (3…)`, rồi mở Focus Stack (`08`) |
| AC-11 | Save thành công | xong lưu | màn đóng, chế độ chọn tắt, viewer mở đúng ảnh vừa lưu | ✅ `focus-stack-save.json` ảnh `02` (iPhone 17 Pro 26.5, lưới Library): màn đóng, dump có `Select photos` chứ không còn `Done selecting`, viewer mở ảnh mới (EXIF khung đầu, 1,9 MB) |
| AC-12 | Save hỏng giữa chừng | cảnh báo hiện | tiêu đề `Couldn't Save`; không còn `Couldn't Combine` ở đâu | ⚠️ một nửa: `PhotoStackModelTests` (4 test, hai tiêu đề theo pha); `Couldn't Combine` đã rời code và String Catalog; còn thiếu ảnh chụp cảnh báo |
| AC-13 | Album Detail, Smart Album Detail, On This Day, mỗi màn chọn 3 ảnh | mở ⋯ | có dòng Combine Photos với cùng menu con như Library | ⚠️ chưa có — `combine-menu.json` |
| AC-14 | album người dùng tạo có 8 ảnh, chọn cả 8 | Focus Stack → Save | album có 9 ảnh; viewer mở ảnh mới ngay trong album | ⚠️ chưa có — `combine-menu.json` + ảnh |
| AC-15 | Smart Album, chọn 3 ảnh | Stack Exposures, `Lighten` → Save | tab Library được chọn, viewer mở ảnh mới; smart album không đổi | ⚠️ chưa có — `combine-menu.json` + ảnh |

**Chưa chứng minh được:** AC-8 (Duo), AC-9 (VoiceOver: dump có nhãn `Combine Photos`, chưa nghe đọc "menu"), AC-11, AC-13 (ba lưới album), AC-14, AC-15 — các đường lưu chưa chạy trên simulator. AC-12 một nửa.

Quyết định 2026-09-23: ba dòng Focus Stack · Panorama · Stack Exposures; Stack Exposures là một màn có bộ chọn `Average · Lighten · Darken` (mặc định Average), kèm câu giải thích từng mode · cả bốn lưới · tiêu đề chỉ tên việc · lỗi chung · Cancel giữ lựa chọn · Save mở viewer; từ album người dùng thì thêm ảnh vào album, từ Smart Album / On This Day thì sang Library.
Không còn `⚠️ CẦN QUYẾT`.

## 6. Tài liệu phải sửa khi Build

- [FS-01.06](06-multi-select.md) — danh sách menu ⋯ (hiện còn thiếu cả Paste Edits lẫn Combine Photos).
- `DESIGN.md` §10.3b (Combine Photos thành ba màn; bộ chọn chỉ còn ở Stack Exposures) và §10.6 (danh sách menu ⋯).
- [FS-14.01](../FS-14-panorama/01-screen-and-flow.md) §1 và §6 — đã trỏ về menu con này và giữ lựa chọn khi Cancel.
