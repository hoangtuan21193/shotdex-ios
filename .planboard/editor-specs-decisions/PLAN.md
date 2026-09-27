# Các điểm cần quyết — FS-03.13…16 — plan thực thi

> Chốt ngày 2026-09-28, sau 1 vòng · nguồn: .planboard/editor-specs-decisions/plan.json · lý do từng điểm: DECISIONS.md

## Nguyên tắc
- Chỉ sửa tài liệu (`docs/02-functional-spec/FS-03-photo-editor/13*…16*`); không `.swift`.
- Mỗi `⚠️ CẦN QUYẾT` đã chốt → thay bằng luật đã chọn (thì hiện tại), bỏ dấu ⚠️.
- AC nào đổi nghĩa thì sửa AC; AC của phần bị bỏ thì xoá.
- Cần đi chệch một quyết định đã chốt: dừng lại, hỏi người dùng.

## Đổi hướng từ các thẻ "Không OK" (áp cho mọi spec liên quan)

| Thẻ | Hướng mới |
|---|---|
| D24–D28 | **iPhone khoá dọc, editor không xoay.** Bỏ toàn bộ bố cục iPhone ngang (13d, 13 tổng quan). |
| D20 | **Không có màn Manage Looks.** Giữ lâu bất kỳ ô nào ở Presets / My Looks / LUTs → Rename · Share · Export As · Delete; **Delete không hiện với preset có sẵn trong app**. Không có sắp xếp kéo thả. |
| D45, D48 | **Chia sẻ mỗi lần một look**; chỉ một loại file `.shotdexlook` (một look/file); **không nhận zip**. |
| D66 | **Remove (xoá vật) tạm bỏ** khỏi đợt này cho tới khi Apple có API/model hỗ trợ; bỏ chip Remove ở Heal. |
| D32 | Duo màn ngoài, đang trong công cụ: **✕ và ✓ nằm trong cột công cụ dọc** (thay các ô công cụ), không có ô chết. |
| D38 | Nhãn **"Import XMP Preset" / "Export XMP Preset"**, kèm một câu giải thích ngắn kiểu "Export presets in XMP format for use with Adobe Lightroom." Không đặt cổng pháp lý chặn bản phát hành. |
| D22 | Ô filmstrip **bo góc 6**. |

## Việc cần làm

### 1. FS-03.13 — bố cục iPhone
- [ ] **1.1** Áp D1–D19, D21, D23, D29–D33 (lựa chọn trong DECISIONS.md; khác đề xuất: D3 chờ số đo, D12 Upright 2 hàng 3+3, D23 Sync chỉ ở filmstrip) — `13*.md`
- [ ] **1.2** Bỏ bố cục ngang (D24–D28), bỏ Manage Looks (D20), bo góc 6 (D22), Duo ✕/✓ trong cột (D32), bỏ chip Remove ở Heal (D66), mask grid 4×4 (D68) — `13*.md`
  - Xong khi: không còn `⚠️ CẦN QUYẾT` nào ngoài D3 (chờ đo); AC đếm lại; §6 "chỗ phải viết lại" khớp

### 2. FS-03.14 — trao đổi preset
- [ ] **2.1** Áp D34–D37, D39–D44, D46, D47, D49, D50 (khác đề xuất: D39 nhãn "Imported", D40 thêm dòng không liên quan Adobe, D41 bỏ ảnh xem trước nhúng) — `14*.md`
- [ ] **2.2** Bỏ gói nhiều look và zip (D45, D48), bỏ Manage Looks → menu giữ lâu (D20), nhãn Import/Export XMP Preset (D38), bỏ cổng pháp lý — `14*.md`

### 3. FS-03.15 — thông số Lightroom
- [ ] **3.1** Áp D51–D65, D67–D70 (khác đề xuất: D59 kèm Depth Anything, D62 dựng sẵn 8 mức mờ, D64 Vision chân trời + bộ dò dọc tự viết, D68 lưới 4×4, D69 Red Eye chạm + tự dò) — `15*.md`
- [ ] **3.2** Tạm bỏ Remove (D66): chuyển AC Remove sang "Ngoài phạm vi", bỏ D63 khỏi luật chạy — `15c*.md`, `15*.md`

### 4. FS-03.16 — nguồn sửa ống kính
- [ ] **4.1** Áp D71–D77 (khác đề xuất: D72 đọc cả 5 định dạng nhúng) — `16*.md`

### 5. Đồng bộ
- [ ] **5.1** Ghi "Cập nhật 2026-09-28" vào intent editor-iphone-layout (bỏ xoay ngang, bỏ Manage Looks) và parameter-parity (Remove tạm bỏ), preset-exchange (một look/lượt, không zip) — `docs/_intents/2026-09-27-*.md`
- [ ] **5.2** Cập nhật dòng Tiến độ với số AC mới — intents
- Kiểm tra: `grep -c "CẦN QUYẾT" docs/02-functional-spec/FS-03-photo-editor/1[3-6]*.md`

## Ngoài phạm vi
- Bố cục iPhone xoay ngang (D24–D28), màn Manage Looks (D20), gói nhiều look và zip (D45, D48), Remove (D66), cổng pháp lý chặn phát hành (D38).
