# FS-03.17 — Editor iPad + Duo theo design canvas 30/9 — plan thực thi

> Chốt ngày 2026-10-01, sau 1 vòng · nguồn: .planboard/fs0317-wide-design/plan.json · lý do: DECISIONS.md

## Nguyên tắc
- Làm theo thứ tự; mỗi task xong thì tick và chạy phần "Kiểm tra".
- Cần đi chệch một quyết định đã chốt: dừng lại, hỏi người dùng.
- Quy trình repo (docs/PROCESS.md): spec → người dùng duyệt + commit riêng → `/plan` → code một AC một commit → `/verify`.
  Plan này dừng ở bước 2 chờ duyệt; phần 3–5 chỉ là khung, chi tiết file:line do `/plan FS-03.17` viết.

## Việc cần làm

### 1. Sửa canvas cho khớp quyết định (D21)
- [ ] **1.1 Sửa bảng trên canvas** — https://claude.ai/artifact/T4tEUQrJtxBbi48HokiL9F
  - Theo: D6 (sheet Save: dòng metadata chỉ cho Save Copy, bộ chọn 3 mức; thêm hàng nhiều ảnh), D7 (Heal · Clone · Red Eye ở IP5/IPP6/DI5/DIP5/DC5), D9 (chấm trắng ở IP7/IPP3/DI7/DIP7/DC7), D15 (IP4/IPP2 14 loại; IP6/IPP7 "Speech Bubble", ô 58), D16 (tỉ lệ của code, có 4:3, bỏ 5:4), D18 (DI9 LUTs, DC7 tiêu đề, DC8 đồ thị, IP7 menu Sync, Visualize Spots trùng, DI10 tiêu đề), D5 (note hàng DIP: chỉ editor xoay)
  - Xong khi: một lượt publish, mọi bảng trên không còn chỗ trái quyết định
  - Kiểm tra: `Tools/design-board render build/design/editor/project/<bảng>.dc.html -o build/design/editor/render` sau khi export lại

### 2. Spec FS-03.17 (D20)
- [ ] **2.1 Viết 17 · 17a · 17b · 17c** — `docs/02-functional-spec/FS-03-photo-editor/17*.md`
  - Theo: D1–D22
  - Xong khi: mỗi bảng (IP×12, IPP×12, DI×12, DIP×12, DC×12) là ≥1 AC, chứng minh bằng "design-parity PASS"; có AC đường hỏng (ảnh dọc 2:3 dưới băng nổi, xoay giữa chừng trên Duo, Reset/Revert huỷ ở xác nhận, Save Changes giữ metadata); mọi chỗ vướng ghi `⚠️ CẦN QUYẾT`
- [ ] **2.2 Đánh dấu tài liệu cũ** — `09-wide-screen-and-batch-editing.md` §3–7, `13d-presets-batch-devices.md` §3 + AC-44/45, `README.md` FS-03, `DESIGN.md` §10.3/§13 (ghi chờ sửa)
- [ ] **2.3 Intent** — `docs/_intents/2026-09-22-editor-panel-lightroom-layout.md`, `2026-09-27-editor-iphone-layout.md`: link spec, dòng Tiến độ
- [ ] **2.4 Dừng**: người dùng duyệt, commit tài liệu riêng

### 3. Nền chung (sau `/plan`)
- D1 cột cố định + danh sách/dải công cụ iPhone cho màn rộng · D2 băng nổi + DESIGN.md §10.3 · D3 đĩa 34/40 chạm 44 · D4 bỏ ⋯, rải mục · D19 token mới
- D5 xoay chỉ editor trên Duo trong (plist + AppDelegate)

### 4. Dùng chung với iPhone
- D11 Transform trên ảnh · D12 khung chọn lớp chữ · D13 B·I·U + Size px (Underline trong ShotDexKit, có test render)
- Kiểm tra lại hàng PH* bằng design-parity vì iPhone đổi theo

### 5. Theo thiết bị, vòng design-parity tới PASS (D22)
- iPad 13" ngang (IP) + dọc (IPP): iOS 26.5 và 18.6
- Duo trong ngang (DI) + dọc (DIP): người dùng mở gập simulator bằng tay
- Duo ngoài (DC): AC-44/45 viết lại — dải 84 dùng được khi ẩn status bar
- Mỗi bảng: build → ui-drive/sim-shot → `design-parity` → sửa → lặp; `Tools/gate` trước khi báo xong

## Ngoài phạm vi
- D14: băng iPhone (bỏ ⋯, histogram 66×34, Save icon export) — intent riêng sau.
- D5: xoay cho iPhone thường và mọi màn không phải editor trên Duo.
- Remove (xoá vật thể) trong Heal — giữ D66.
