# Pending spec edits — slug `search` (S1, S2, S4, S5, C1)

Files these items need but that are not assigned to the `search` agent. Each: file · section · exact text · ID.

1. **docs/01-basic-design/BD-03-metadata-indexing-flow/README.md** · "Bước cuối cho mỗi ảnh" · sau bước 3 thêm (S2):
   > 4. Tính khung giờ chụp — theo mặt trời khi có toạ độ, theo giờ EXIF khi không ([BD-03.02 §4](02-exif-read.md)).

   (đánh lại số các bước sau: ghi theo lô → 5, toạ độ → 6)

2. **docs/02-functional-spec/FS-06-collections/09-album-filter-menu.md** · §2 Phạm vi, dòng `Filter:` — chỉ áp nếu
   ⚠️ CẦN QUYẾT ở FS-01.05b §1 chọn b (S1). Thay dòng bằng:
   > - Phần `Filter:`: All Items · Favorites · Photos Only / Videos Only (loại trừ nhau) · **Capture Kind ▸** ·
   >   **Camera ▸** · **Lens ▸** (tối đa 8 dòng, số ảnh **trong album**, [FS-01.05b §1](../FS-01-library/05b-gear-menu-missing-data-and-sheet.md)) ·
   >   **Advanced Filter…** (chỉ lọc trong album, §4).

   AC thêm: `| AC-S1 | album 40 ảnh: 25 X-T5, 15 α7 IV | Filter → Camera ▸ | 2 dòng, X-T5 · 25 trước; chạm X-T5 → 25 ô | ⚠️ chưa có |`

3. **docs/02-functional-spec/FS-07-statistics/01-dashboard.md** · §4, bullet "Nhóm "Unknown" bị ẩn khỏi biểu đồ" · thay bằng (S5):
   > - Nhóm **"Unknown" bị ẩn khỏi biểu đồ**, và thay bằng một dòng chú "N photos without this info." — **chạm được**:
   >   mở Library với điều kiện "is missing" của trục đó + khoảng ngày và điều kiện của biểu đồ, lưới ra đúng N ô
   >   ([FS-01.05b §2](../FS-01-library/05b-gear-menu-missing-data-and-sheet.md)). N đếm theo cùng định nghĩa "thiếu" ở đó.

   Và AC tương ứng ở `03-acceptance-criteria.md`: `| AC-S5 | biểu đồ Lens, This Year, 250 ảnh không lens | chạm "250 photos without this info." | Library, chip No Lens, 250 ô | ⚠️ chưa có |`

4. **docs/02-functional-spec/FS-06-collections/08-smart-albums.md** · đoạn mô tả sheet soạn (S4):
   > - Loại media và chế độ khớp chung một hàng (bộ dựng dùng chung, [FS-01.05b §3](../FS-01-library/05b-gear-menu-missing-data-and-sheet.md));
   >   `Matches N photos` nằm dưới tiêu đề sheet, cạnh nút Save, không ở chân danh sách điều kiện.

5. **docs/02-functional-spec/FS-07-statistics/01-dashboard.md** · §4, bullet "Ô soạn" · thêm câu (S4):
   > Mục Conditions dùng hàng gộp loại media + chế độ khớp của bộ dựng chung; ô soạn biểu đồ không hiện số ảnh khớp
   > (đã có xem trước sống).
