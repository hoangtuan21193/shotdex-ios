# FS-03.09 — chốt các chỗ code lệch spec + ba điểm của luồng server — plan thực thi

> Chốt ngày 2026-09-30, sau 1 vòng · nguồn: .planboard/fs0309-divergences/plan.json

## Nguyên tắc
- Làm theo thứ tự; mỗi task xong thì tick và chạy phần "Kiểm tra".
- Cần đi chệch một quyết định đã chốt: dừng lại, hỏi người dùng.
- Mỗi AC một commit; build sau mỗi thay đổi; UI đổi thì chụp iPad 13" + iPad Pro 11" (và iPhone nếu đường đó chạm phone).

## Việc cần làm

### 1. Sửa AC cho khớp code (không đổi UI)
- [x] **1.1 AC-1 thành 7 thẻ; test đọc danh sách màn hình dùng** — `docs/02-functional-spec/FS-03-photo-editor/09-wide-screen-and-batch-editing.md`, `ShotDexTests/EditorWideScreenTests.swift`, `ShotDex/Features/Editing/EditorAdjustmentCatalog.swift:99`
  - Theo: D1 (Sửa AC thành 7, test đọc danh sách thật)
  - Xong khi: test đỏ nếu `PhotoEditorScreen.sidebarParameterGroups` đổi; `sidebarSections` bỏ nếu không ai dùng
  - Kiểm tra: `/test EditorWideScreenTests`
- [x] **1.2 AC-9: cụm lệnh nằm trong bề rộng panel + 8pt** — FS-03.09
  - Theo: D4
  - Xong khi: dòng AC-9 ghi số đo 361pt là đạt
- [x] **1.3 AC-20: mốc canvas 832pt; test trừ tay nắm 10pt** — FS-03.09, `ShotDexTests/EditorPanelLayoutTests.swift:582-590`
  - Theo: D5 (Hạ mốc AC xuống 832)
  - Xong khi: test đo canvas thật (trừ tay nắm) ≥ 832 và khớp 832 đo trên iPad Pro 11"
  - Kiểm tra: `/test EditorPanelLayoutTests`
- [x] **1.4 AC-13: 7 slider, rời Crop là áp khung; chip tỉ lệ xuống hàng** — FS-03.09, crop panel trong `ShotDex/Features/Editing`
  - Theo: D6 (Rời Crop là áp)
  - Xong khi: 4:5 và 9:16 thấy trọn trong panel iPad, không cuộn ngang
  - Kiểm tra: `ipad-ws-stage-modes.json`

### 2. Panel cuộn
- [x] **2.1 AC-5: đệm dưới động để thẻ cuối lên được đầu** — `ShotDex/Features/Editing/PhotoEditorScreen.swift` (sidebar list)
  - Theo: D2 (Đệm dưới động)
  - Xong khi: chạm Detail / Calibration từ giữa danh sách → header ở y đầu vùng cuộn (212 trên 13")
  - Kiểm tra: `ipad-ws-lists-and-scroll.json`
- [x] **2.2 AC-11: chỉ điểm điều khiển nhận kéo; vuốt trên nền đồ cuộn danh sách** — `ShotDex/Features/Editing/EditorCurveGraph.swift:71, :199`
  - Theo: D3 (Chỉ điểm điều khiển nhận kéo)
  - Xong khi: vuốt bắt đầu trên nền đồ cuộn panel; kéo một điểm vẫn nắn curve; chạm nền vẫn thêm điểm
  - Kiểm tra: `ipad-ws-lists-and-scroll.json` + test curve hiện có

### 3. Markup, lỗi nạp
- [x] **3.1 AC-28/29: một ↺, hỏi xác nhận khi ≥ 2 layer** — `ShotDex/Features/Editing/EditorTextPanel.swift:72-83`, `PhotoEditorScreen.swift:1733-1741`, FS-03.09
  - Theo: D7 (Một ↺, hỏi khi ≥ 2 layer)
  - Xong khi: chỉ còn một ↺ cho Markup; 3 layer → hộp xác nhận → xoá, Undo một bước lấy lại; 1 layer xoá không hỏi
  - Kiểm tra: `EditorWideScreenTests` + `ipad-ws-stage-modes.json`
- [x] **3.2 AC-30: màn rộng ẩn palette PencilKit, EditorDrawRows trong panel** — `PhotoEditorScreen.swift:2229-2269`
  - Theo: D8 (EditorDrawRows trong panel)
  - Xong khi: đang vẽ trên iPad không có thanh nào đè ảnh; cọ/cỡ/màu/opacity trong panel; phone giữ nguyên
  - Kiểm tra: `ipad-ws-stage-modes.json` lúc đang vẽ + iPhone markup route
- [x] **3.3 AC-15: lỗi nạp nói lý do; quyền ảnh → Open Settings** — `PhotoEditorController.swift:655-657`, `PhotoEditorScreen.swift:216-226`
  - Theo: D9 (Làm ngay)
  - Xong khi: unit test phân loại lỗi (quyền / tải iCloud / khác) và nội dung alert; ảnh chờ máy thật
  - Kiểm tra: `/test` lớp test mới

### 4. Luồng server
- [x] **4.1 D10: màn rộng đưa hành động của thanh chọn lên toolbar** — `ShotDex/Features/ServerImport/ServerBrowserScreen.swift`, `ShotDex/Features/ServerUpload/ConnectAsScreen.swift`
  - Theo: D10 (Đưa hành động lên toolbar như Files)
  - Xong khi: iPad: Import N to Library / Delete / Choose "…" / Connect là nút toolbar, không còn nút 1000pt; iPhone giữ thanh dưới
  - Kiểm tra: `server-import-ipad-select.json`, `server-connect-as-ipad.json`; iPhone `server-files-browser.json`
- [x] **4.2 D12: Photo Info không ghi "/" cho folder cloud** — `ShotDex/Features/Library/MetadataPanel.swift:110`
  - Theo: D12
  - Xong khi: dòng CloudTest ghi "On My iPhone › CloudTest"
  - Kiểm tra: ảnh Photo Info trên 18.6

### 5. Chứng minh
- [x] **5.1 `/verify FS-03.09`** trên iPad 13" + iPad Pro 11"; cập nhật Tiến độ intent editor-panel-lightroom-layout

## Ngoài phạm vi
- D11 (đổi chữ "Server" khi đích là folder cloud) — Không OK, giữ nguyên chữ.
- AC-14 (máy thật), nhóm Duo màn trong (sim gập).
