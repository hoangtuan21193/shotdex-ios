# FS-01.09 — Ghép nhiều ảnh: menu Combine Photos

`FS-01.09` · `ShotDexKit/Render/PhotoStackRenderer.swift` · `PhotoStackScreen` · `SelectionBarViews`
· cập nhật 2026-09-23 · nguồn [intent](../../_intents/2026-09-23-combine-photos-purpose-menu.md)

**Một câu:** chọn ≥ 2 ảnh → ⋯ → **Combine Photos ▸** → chọn **việc muốn làm** (lấy nét toàn cảnh, panorama,
xoá người qua đường, vệt sáng, giảm nhiễu) → một màn làm đúng việc đó.

> Trạng thái: **spec đã duyệt intent, chưa build.** Code hiện tại vẫn là một dòng Combine Photos và bộ chọn
> bốn mode `Average · Lighten · Darken · Focus Stack` trong màn.

## 1. Quy tắc

- Tên dòng là **việc người chụp muốn làm**, không phải tên phép toán. Không chữ `Average`, `Lighten`,
  `Darken` nào hiện trên màn hình.
- Menu con **một cấp**, năm dòng, thứ tự cố định. Mỗi dòng mở **một màn làm một việc**; trong màn không có
  bộ chọn mode.
- Đổi tên không đổi ảnh: cùng khung vào thì ra **đúng từng pixel** như mode tương ứng trước đây.
- Renderer là **actor trong ShotDexKit** vì nó là render thuần. **Ghép lũy tiến** ở mọi việc → bộ nhớ phẳng
  theo số frame. Preview dựng ở 1600pt và dùng lại; chỉ khi Save mới nạp full-res.

## 2. Menu con

| # | Dòng | Làm gì | Bên dưới | Câu giải thích trong màn |
|---|---|---|---|---|
| 1 | **Focus Stack** | lấy nét toàn cảnh — macro, phong cảnh gần-xa | điểm nét nhất (§4) | Keeps the sharpest part of every frame, for depth of field no single shot can reach. |
| 2 | **Panorama** | nối khung cạnh nhau | [FS-14](../FS-14-panorama/README.md) | (màn riêng của FS-14) |
| 3 | **Remove Moving People** | xoá người, xe đi qua trong chuỗi chụp tripod | điểm tối nhất | Clears people and cars that moved between frames. Shoot from a tripod. |
| 4 | **Light Trails** | vệt sao, đèn xe, pháo hoa | điểm sáng nhất | Keeps the brightest light from every frame — star trails, traffic, fireworks. |
| 5 | **Reduce Noise** | giảm nhiễu; giả phơi sáng dài | trung bình đều | Averages the frames to clean up noise, or to smooth water and clouds like a long exposure. |

- Dòng mở menu con giữ tên **Combine Photos**, icon như hiện nay.
- **Panorama** chỉ xuất hiện khi FS-14 đã build; trước đó menu con có bốn dòng.
- Dòng 1–5 **mờ** khi lựa chọn có < 2 ảnh; dòng Combine Photos vẫn mở được để thấy có những việc gì.
- Video trong lựa chọn bị bỏ qua, không làm mờ dòng nào.
- Mỗi dòng một icon SF Symbols có từ iOS 17 — chọn ở `/plan`, theo DESIGN §8.
- Menu có ở **cả bốn lưới** dùng lớp chọn chung: Library, Album Detail, Smart Album Detail, On This Day.
  Hiện chỉ Library cấp hành động này. *Vì* một chuỗi macro hay panorama thường nằm sẵn trong một album.

## 3. Màn

Tầng D (DESIGN §10.3, §10.3b): `Cancel` · tiêu đề · `Save`; stage đen; panel chỉ còn **câu giải thích**
của việc đó và, riêng Focus Stack, dòng nhắc căn khung ("Frames are lined up before stacking…").

- **Tiêu đề** là tên việc, không kèm số ảnh: `Focus Stack`, `Remove Moving People`… Tên việc là danh từ
  hoặc động từ + tân ngữ, đúng DESIGN §12; số ảnh đã hiện ở pill đếm của lưới vừa rời.
- **Cảnh báo lỗi** dùng một tiêu đề chung: `Couldn't Save` khi lưu hỏng, `Couldn't Load Photos` khi hỏng lúc
  dựng preview. Thân cảnh báo nói lý do cụ thể.
- **Cancel giữ lựa chọn**: về lưới vẫn còn nguyên các ảnh đã chọn, để thử việc khác ngay trên cùng chuỗi —
  màn không còn bộ chọn mode nên đây là đường đổi việc. **Save** thì thoát chế độ chọn.
- **Save xong mở ảnh vừa lưu trong viewer**, như FS-14 — một hành vi cho cả menu con. Ảnh mới nằm ở thư
  viện chung, không tự nằm trong album đang mở, nên theo màn đang đứng:
  - **Library**: mở viewer tại chỗ.
  - **Album do người dùng tạo** (thêm ảnh được): **thêm ảnh mới vào album đó**, rồi mở viewer tại chỗ — ảnh
    ghép nằm cạnh các khung gốc của nó.
  - **Smart Album, On This Day** (và album không cho thêm ảnh): chuyển sang tab Library và mở ảnh ở đó.

## 4. Focus stack (thuật toán hiện tại)

1. Align mỗi frame bằng bộ căn ảnh theo tịnh tiến của hệ thống — **chỉ tịnh tiến**. Sẽ đổi theo
   [intent Helicon](../../_intents/2026-09-23-focus-stack-helicon-parity.md) (co giãn + xoay).
2. Dựng **bản đồ độ nét**: mono → Laplacian 3×3 → độ lớn phản hồi → box blur.
3. Ghép lũy tiến qua phép trộn theo mặt nạ — giữ pixel nét nhất.

Frame sau align phải kéo giãn mép ra vô hạn **trước khi** crop, nếu không mép hở thành viền trắng quanh ảnh.

## 5. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | Library, chọn 4 ảnh | mở ⋯ | có **một** dòng Combine Photos; không dòng Focus Stack/Panorama nào đứng riêng ở cấp ngoài | ⚠️ chưa có — `combine-menu.json` + dump |
| AC-2 | chọn 4 ảnh | ⋯ → Combine Photos | menu con ghi đúng thứ tự Focus Stack · Panorama · Remove Moving People · Light Trails · Reduce Noise (Panorama chỉ khi FS-14 đã build) | ⚠️ chưa có — `combine-menu.json` + dump |
| AC-3 | chọn 1 ảnh + 3 video | ⋯ → Combine Photos | mở được; cả năm dòng mờ | ⚠️ chưa có — `combine-menu.json` |
| AC-4 | 4 khung cố định, cùng một bộ | chạy từng việc 1, 3, 4, 5 | ảnh ra trùng từng pixel với mode Focus Stack, Darken, Lighten, Average cũ | ⚠️ chưa có — `PhotoStackRendererTests` |
| AC-5 | chọn 6 ảnh + 2 video | ⋯ → Combine Photos ▸ Light Trails | màn mở với 6 khung, tiêu đề `Light Trails`, **không** có bộ chọn mode | ⚠️ chưa có — `combine-menu.json` + ảnh |
| AC-6 | từng màn trong năm việc | mở | câu giải thích đúng bảng §2; không chữ Average/Lighten/Darken nào trên màn | ⚠️ chưa có — dump + ảnh |
| AC-7 | iOS 26.5 và iOS 18.6 | mở menu con trên cả hai | cùng năm dòng, cùng thứ tự, cùng trạng thái mờ | ⚠️ chưa có — `combine-menu.json` chạy hai máy |
| AC-8 | iPhone 402×874, iPad 1376×1032, Duo trong 951×669 | mở menu con | cùng số dòng trên cả ba | ⚠️ chưa có — `combine-menu.json` + `Tools/sim-shot` |
| AC-9 | VoiceOver bật | vuốt tới dòng Combine Photos | đọc tên kèm "menu"; mỗi dòng con đọc đúng tên | ⚠️ chưa có — dump nhãn a11y |
| AC-10 | chọn 5 ảnh, màn Reduce Noise đang mở | Cancel | về lưới, vẫn đúng 5 ảnh được chọn; mở tiếp Combine Photos ▸ Light Trails được ngay | ⚠️ chưa có — `combine-menu.json` + dump |
| AC-11 | Save thành công | xong lưu | màn đóng, chế độ chọn tắt, viewer mở đúng ảnh vừa lưu | ⚠️ chưa có — `combine-menu.json` + ảnh |
| AC-12 | Save hỏng giữa chừng | cảnh báo hiện | tiêu đề `Couldn't Save`; không còn `Couldn't Combine` ở đâu | ⚠️ chưa có — ảnh + String Catalog |
| AC-13 | Album Detail, Smart Album Detail, On This Day, mỗi màn chọn 3 ảnh | mở ⋯ | có dòng Combine Photos với cùng menu con như Library | ⚠️ chưa có — `combine-menu.json` |
| AC-14 | album người dùng tạo có 8 ảnh, chọn cả 8 | Focus Stack → Save | album có 9 ảnh; viewer mở ảnh mới ngay trong album | ⚠️ chưa có — `combine-menu.json` + ảnh |
| AC-15 | Smart Album, chọn 3 ảnh | Light Trails → Save | tab Library được chọn, viewer mở ảnh mới; smart album không đổi | ⚠️ chưa có — `combine-menu.json` + ảnh |

**Chưa chứng minh được:** cả 15 — chưa build.

Quyết định 2026-09-23: cả bốn lưới · tiêu đề chỉ tên việc · lỗi chung · Cancel giữ lựa chọn · Save mở viewer; từ album người dùng thì thêm ảnh vào album, từ Smart Album / On This Day thì sang Library.
Không còn `⚠️ CẦN QUYẾT`.

## 6. Tài liệu phải sửa khi Build

- [FS-01.06](06-multi-select.md) — danh sách menu ⋯ (hiện còn thiếu cả Paste Edits lẫn Combine Photos).
- `DESIGN.md` §10.3b (Combine Photos: bỏ "mỗi mode", thành "mỗi việc") và §10.6 (danh sách menu ⋯).
- [FS-14.01](../FS-14-panorama/01-screen-and-flow.md) §1 và §6 — đã trỏ về menu con này và giữ lựa chọn khi Cancel.
