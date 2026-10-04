# ShotDex Mac — plan thực thi

> Chốt ngày 2026-10-04, sau 1 vòng · nguồn: .planboard/macos-app/plan.json · lý do: DECISIONS.md

## Nguyên tắc
- Làm theo thứ tự; mỗi task xong thì tick và chạy phần "Kiểm tra".
- Cần đi chệch một quyết định đã chốt: dừng lại, hỏi người dùng.
- Code chỉ bắt đầu sau `/spec` + `/plan` (docs/PROCESS.md). Plan này đưa canvas và tài liệu tới đó.

## Việc cần làm

### 1. Canvas theo quyết định (build/design/mac/project → publish lên artifact)
- [x] **1.1 Viewer gộp Compare** — `MAC_Viewer`, `MAC_Compare` (vẽ lại thành chế độ 2-Up/Survey của Viewer, P/X, bỏ dải phím)
  - Theo: D15, D12 · Xong khi: không còn cửa sổ Compare riêng; Viewer có segmented Single · 2-Up · Survey
- [x] **1.2 Viewer mở trong cửa sổ** — `MAC_Viewer`, `MAC_Edit` (nút Back về lưới, sidebar ẩn; vùng ảnh theo nền cửa sổ)
  - Theo: D9, D10
- [x] **1.3 Editor hai trạng thái lưu** — `MAC_Edit`, `MAC_Export` (ảnh thư mục: "Edited · saved" + Revert, không Done; thêm board `MAC_EditPhotos` cho ảnh Photos có Done; Export bỏ "Save Edit")
  - Theo: D16
- [x] **1.4 Màn Import thẻ nhớ** — board mới `MAC_Ingest` (chọn thẻ, đích chính + backup, mẫu tên, preset metadata, tiến độ copy/verify)
  - Theo: D8
- [x] **1.5 Sidecar XMP** — `MAC_SettingsSources` (công tắc đọc/ghi .xmp, mặc định bật), sửa chữ `MAC_AddSource`, `MAC_GetInfo`
  - Theo: D3
- [x] **1.6 Server là nguồn index** — `MAC_ServerBrowser` (bỏ Import), `MAC_SettingsServers` (bỏ "Import Downloaded Photos To")
  - Theo: D5
- [x] **1.7 Xoá file** — `MAC_Cull`, `MAC_Duplicates`, `MAC_Compress` (hộp xác nhận nói nơi đến; NAS chỉ "Hide"), chữ "never edits file contents"
  - Theo: D6
- [x] **1.8 Bản sao hai nguồn** — `MAC_Duplicates` (không nhóm khác nguồn), `MAC_Statistics` (chú thích đếm một lần)
  - Theo: D7, D4
- [x] **1.9 Lần mở đầu** — thay `MAC_Onboarding` bằng `MAC_EmptyLibrary` (cửa sổ chính trống, Add Photos Library / thả thư mục)
  - Theo: D13
- [x] **1.10 Còn lại** — `MAC_SettingsGeneral` bỏ Accent Color (D11); `MAC_SettingsEditing` bỏ câu "no colour-space conversion" (D17); `MAC_Statistics` bỏ popup ngày chung (D18); `MAC_Collections`, `MAC_AlbumDetail` bỏ thư mục album + số dưới cover (D19); sửa số ảnh theo máy cho khớp giữa Statistics và Search
- [x] **1.11 Kiểm và publish** — render toàn bộ sáng/tối, xem từng PNG, cập nhật `canvas.json`, publish
  - Kiểm tra: `Tools/design-board render build/design/mac/render-src-all/*.dc.html -o build/design/mac/review/light`

### 2. Tài liệu
- [x] **2.1 Intent** — `docs/_intents/2026-10-04-macos-app.md`: đóng Open questions bằng D1–D19, link DECISIONS.md; người dùng đổi `accepted`, commit riêng
- [ ] **2.2 DESIGN.md mục Mac** — hình học Mac (từ `build/design/mac/MAC_STYLE.md` v2), amber luôn (D11), tier D giữ nguyên (D10)
- [x] **2.3 Chạy `Tools/evals`** — vì `CLAUDE.md` đã sửa (link canvas Mac)

### 3. Sang Design → Build
- [ ] **3.1 Spike** — build ShotDexKit + Domain + Data cho macOS, đếm lỗi (đưa số vào /plan)
- [ ] **3.2 `/spec`** — bộ FS Mac: nguồn ảnh (id hash D4, XMP D3, server D5, xoá D6, đếm D7), Import thẻ (D8), cửa sổ/Viewer/Compare (D9, D15), Editor lưu (D16), xuất màu (D17), Statistics (D18); sửa FS-01.08, FS-01.12, FS-03.04, FS-07.01 cho Mac; `data-migration` duyệt schema

## Ngoài phạm vi
- Màn hình thứ hai (Secondary Viewer) — không ở bản đầu (D14).
- Widget, Share extension, Edit action trên Mac — để sau (intent).
- Sync recipe giữa Mac và iPhone ngoài đường Photos/iCloud — chưa làm.
