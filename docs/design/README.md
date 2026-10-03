# Design — một canvas cho mỗi thiết bị

Bản thiết kế (artboard `.dc.html`) **nằm trong repo này** và là nguồn gốc. Artifact trên claude.ai là bản
để xem, comment và chỉnh tay; mọi phiên đọc và sửa ở đây.

| Thiết bị | Thư mục | Canvas | Hàng trên canvas |
|---|---|---|---|
| iPhone 17 · 402×874 | [iphone/](iphone/project/) | <https://claude.ai/artifact/QUTRUQGqpZLLWe4VNg2REY> | Màn hình app `PH_*` (vào: `Main` = Library) · Sửa ảnh `PH01…PH37` · Video Studio `P*`, `*_P_*` |
| iPad 13" · 1376×1032 và dọc | [ipad/](ipad/project/) | <https://claude.ai/artifact/WSuCW14jrZWQFiJKJtwx6j> | Màn hình app `IP_*` (vào: `Main` = Library) · Sửa ảnh ngang `IP1…`, dọc `IPP1…` · Video Studio ngang `IL*`, dọc `IP1_Main…`, `*_IL_*`, `*_IP_*` |
| iPhone Duo · trong 951×669, ngoài 466×678 | [duo/](duo/project/) | <https://claude.ai/artifact/N91F3p5AZWgSQiMWVtZYrL> | Màn hình app `DI_*` (vào: `Main` = Library màn trong), `DC_*` · Sửa ảnh `DI*`, `DIP*`, `DC*` · Video Studio `DI*`, `DC*`, `*_DI_*`, `*_DC_*` |
| Mac · 1440×900 | [mac/](mac/project/) | <https://claude.ai/artifact/HEj8sG21jAEWd7Mgvuyxgj> | `Main` = Library, mọi board khác `MAC_*`; brief và hình học Mac ở [mac/MAC_STYLE.md](mac/MAC_STYLE.md) |

Ba canvas cũ (App Screens `53VivNtn…`, Photo Editor `T4tEUQrJ…`, Video Studio `B8NqQqRH…`) đã gộp vào bốn canvas
trên ngày 2026-10-04. Tên board giữ nguyên, trừ hai board trùng tên `Main`: Main của Editor → `PH01_Edit`, Main
của Video Studio → `P1_Main`; Library iPad `IP_Library` → `Main` (iPad), Library Duo `DI_Library` → `Main` (Duo).
Plan cũ trỏ tới link canvas cũ: tra board theo tên trong bảng trên.

## Luật làm việc

1. **Sửa trong repo, rồi publish.** Sửa `docs/design/<thiết bị>/project/*.dc.html` (và `canvas.json` khi thêm,
   bớt, dời board), publish lên đúng canvas, commit. Không sửa thẳng trên canvas rồi để repo cũ.
2. **Trước khi sửa: kéo chỉnh tay về.** Người dùng có thể đã sửa hoặc comment trên canvas. Đọc lại những file
   sắp sửa từ canvas (Artifact `read` theo `path`); khác repo thì lấy bản canvas vào repo trước. Publish bị từ
   chối vì "đã có bản mới" nghĩa là đúng chuyện này.
3. **Một thiết bị, một canvas.** Màn mới nối vào hàng của khu tương ứng trên canvas của thiết bị đó, không mở
   canvas hay hàng "đề xuất" riêng.
4. **Render để soi:** `Tools/design-board render` cần runtime giả `support.js` đặt cạnh board — chép board vào
   `build/design/<thiết bị>/render-src/` (gitignored) cùng `support.js` từ `build/design/app/render-src/`, xem
   [CLAUDE.md](../../CLAUDE.md).
