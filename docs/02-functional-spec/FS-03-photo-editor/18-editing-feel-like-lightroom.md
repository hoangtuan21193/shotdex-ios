# FS-03.18 — Cảm giác sửa ảnh như Lightroom

`FS-03.18` · `ShotDexKit/Render/PhotoRenderService.swift` · `Features/Editing/PhotoEditorController.swift` ·
`EditorToolPanels.swift` · `EditorHistogramCard.swift` · `EditorHistorySheet.swift` · `EditorImageStage.swift` ·
cập nhật 2026-11-14

Intent [2026-11-14-editor-feel-like-lightroom](../../_intents/2026-11-14-editor-feel-like-lightroom.md) · bằng chứng
[Lightroom Develop RE](../../_research/2026-11-14-lightroom-develop-re.md) · quyết định
`.planboard/editor-lightroom/DECISIONS.md`.

## 1. Nháp khi kéo, nét khi thả (D1)
- Trong một cử chỉ liên tục (thanh trượt, núm, bánh xe, đường cong, kéo mask), preview vẽ ở **chất lượng tương tác**:
  cạnh dài = ½ cạnh hiển thị (tối thiểu 640 px), **bỏ** khử nhiễu, làm nét, lens blur, hạt film. Mọi thứ khác
  (màu, tông, đường cong, mask, film look, LUT, crop, hình học) vẫn vẽ.
- Thả tay: một lần vẽ **chất lượng cuối** như hiện nay (debounce 90 ms giữ nguyên). Ảnh lưu ra không đổi.
- Lần vẽ cũ đang chạy bị huỷ giữa các tầng (A3); chỉ khung mới nhất được hiện.
- Ảnh gốc đã giải mã cho lần vẽ nét được giữ lại (A2); đổi ảnh hoặc đổi kích thước mới giải mã lại.

## 2. Histogram (A1)
- Khi kéo: tối đa 5 lần/giây; khi thả: một lần sau khung nét. Mỗi lúc chỉ một lần tính; đang tính thì bỏ qua.

## 3. Xem thử look (D2)
- Đổi 14/11 (user chọn "Menu kèm ảnh xem thử"): nhấn giữ một ô Film, My Looks hay LUT vẫn mở menu như cũ (Rename,
  Share…, Export As, Delete), nhưng menu có thêm **ảnh xem thử** — ảnh đang sửa với look đó, cạnh dài 720, tên look ở
  dưới — và dòng đầu **Apply**. Lý do: nhấn giữ đã là menu của ô; giữ-để-xem sẽ lấy mất đổi tên/xoá.
- Đóng menu (chạm ra ngoài): recipe không đổi, History không thêm bước. Apply: áp look, một bước History. Chạm nhanh
  vào ô: áp ngay như cũ.
- Board: không vẽ menu đang mở (quy tắc canvas: không thêm board biến thể/menu mở).

## 4. Vùng cháy trên ảnh (D3)
- Card histogram có hai tam giác ở hai góc trên: trái = tắt đen, phải = cháy sáng. Chạm bật/tắt lớp phủ trên ảnh:
  **đỏ** nơi có kênh ≥ 254, **xanh** nơi mọi kênh ≤ 1 (cùng ngưỡng với histogram). Tam giác tô màu khi bật.
- Tính trên khung đã vẽ, ngoài luồng chính; tắt thì không tính.

## 5. Snapshot (D4)
- Sheet History có mục **Snapshots** trên danh sách bước: `+ Snapshot` hỏi tên (mặc định ngày giờ), lưu recipe
  hiện tại theo ảnh. Chạm một snapshot = quay về recipe đó (một bước History "Snapshot: tên"). Vuốt xoá.
- Lưu ở bảng `editor_snapshot` (dữ liệu người dùng), còn sau khi đóng trình sửa và mở lại.

## 6. So sánh chia đôi (D5)
- Nút ◧ trên thanh lệnh cạnh Undo/Redo (iPad, Duo, iPhone không có Dynamic Island): bật/tắt chế độ chia đôi; vạch giữa
  kéo được, trái = gốc, phải = đang sửa. Giữ ngón trên ảnh vẫn xem bản gốc như cũ. Phím `B` trên bàn phím iPad.
- iPhone có Dynamic Island: nút đó rơi vào x 137–171, ngay dưới island — hệ thống nuốt cú chạm (đo 14/11). Ở đó Compare
  là dòng bật/tắt "Compare Before and After" trong menu ⋯ (sau Copy/Paste Edits).

## 7. Lịch sử (D6)
Theo phiên như nay.

## 8. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | recipe có khử nhiễu + làm nét + lens blur | render chất lượng tương tác | không chạy ba tầng đó; cạnh dài = ½ hiển thị (≥ 640) | ✅ `EditorRenderQualityTests` (e1f627ac) |
| AC-2 | như AC-1 | render chất lượng cuối | ảnh giống hệt render hiện nay (cùng pixel) | ⚠️ `EditorRenderQualityTests.finalUnchanged` |
| AC-3 | kéo liên tục | mỗi nhịp | preview dùng chất lượng tương tác; thả tay một render cuối | ⚠️ `PhotoEditorControllerRenderTests` |
| AC-4 | 10 nhịp trong 1 s | histogram | tính ≤ 5 lần + 1 lần sau thả | 🟡 code (throttle 200 ms, một task một lúc, e1f627ac); chưa có test đếm |
| AC-5 | thả tay 2 lần cùng ảnh | render cuối | ảnh gốc giải mã một lần | ⛔ chưa làm (A2 hoãn: rủi ro khác pixel/bộ nhớ) |
| AC-6 | nhấn giữ ô film look | menu mở | ảnh xem thử look đó trên ảnh đang sửa; recipe không đổi, Undo vẫn tắt | ✅ iPhone `build/sa-shots/look-menu/l2-menu.png` |
| AC-7 | như AC-6 | chạm Apply | look áp, một bước History (Undo bật) | ✅ iPhone `l3-applied.png` + dump |
| AC-8 | bật tam giác phải, ảnh có vùng 255 | — | lớp đỏ đúng vùng đó | ✅ `ClippingOverlayTests` + iPhone screenshot (4829c507) |
| AC-9 | tạo snapshot "Ấm", sửa tiếp, đóng, mở lại | chạm "Ấm" | recipe về như lúc tạo | ✅ `EditorSnapshotStoreTests` + iPhone screenshot History sheet (57f8e849); reopen-after-close chưa chụp |
| AC-10 | nút ◧ | chạm | chia đôi hiện, kéo vạch được | 🟡 iPhone ✅ qua ⋯ (`build/sa-shots/compare-menu/c2-split.png`, 5dcb2172); iPad/Duo chưa chụp |
| AC-11 | mọi công cụ cũ | dùng | như trước | ⚠️ test hiện có xanh |
| AC-12 | iPad Pro thật, NR+sharpen bật | kéo Exposure | thời gian mỗi khung giảm so với trước (đo) | ⚠️ đo trên iPad |
