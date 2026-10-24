# FS-01.08 — Compare

`FS-01.08` · tầng D (tối, như Duplicates) · `Features/Shared/PhotoCompareScreen.swift` ·
`Features/Library/Compare/CompareModel.swift` · test `SelectionCompareModelTests`, `CompareScrollSynchronizerTests`
· viết lại 2026-10-24 · intent [bỏ chế độ so sánh của viewer](../../_intents/2026-10-24-drop-viewer-compare-modes.md)
· board `PH_Compare`, `IP_Compare`, `DI_Compare`, `DC_Compare` (cùng màn với `*_DuplicatesCompare`)

> **2026-10-24:** chế độ Single · 2-Up · Survey của Viewer ([08c](08c-compare-viewer-mode.md)) **đã bỏ** trên mọi
> thiết bị — người dùng thấy khó hiểu, quá phức tạp. Compare từ chế độ chọn giờ mở **cùng màn so sánh của
> Duplicates** ([FS-06.06 §7.6](../FS-06-collections/06-duplicates.md)).

**Một câu:** chọn 2 ảnh trở lên → **Compare** → hai ô A/B cùng mức phóng, mỗi ảnh một Keep | Delete, rồi
**Delete N** ngay trên thanh trên cùng.

## 1. Một màn cho hai nơi

- Library, Album, Smart Album, On This Day (chọn ảnh → Compare) và Duplicates (chạm ảnh trong nhóm) dùng
  **cùng một màn** `PhotoCompareScreen`. Khác nhau ở nguồn:
  - **Duplicates** (`DuplicateCompareSource`): tiêu đề `Similar · 4 photos`, A mở trên ảnh nhóm giữ, chip khác
    biệt trên B, dấu ghi vào phiên Duplicates; **không có Delete** ở đây — danh sách Duplicates xoá (06b).
  - **Chọn ảnh** (`SelectionCompareModel`): tiêu đề `Compare · N photos`, A = ảnh chọn đầu, không chip, dấu
    **chỉ sống trong màn này** — đóng mà chưa bấm Delete thì không đổi gì trong thư viện.
- Không còn chế độ nào để chọn, không có nút chọn chế độ trong Viewer ở bất kỳ kích thước nào.

## 2. Lối vào

- Nút **Compare** ở thanh chọn khi có **≥ 2 ảnh** (`CompareSession.minimumCount`), **không giới hạn trên**; thứ
  tự trong dải ảnh = thứ tự chọn. Dưới 2 ảnh nút mờ.
- Đóng (✕, hoặc vuốt xuống trên một ô) → về lưới, chế độ chọn kết thúc.

## 3. Bố cục

- Hai ô **A** và **B** bằng nhau: chồng dọc trên màn hẹp, cạnh nhau khi rộng ≥ 700pt. Ảnh vẽ đúng tỉ lệ, chữ
  và nút nằm trên ảnh chứ không trên khoảng đen.
- **Phóng và kéo luôn đồng bộ** giữa hai ô (`CompareScrollSynchronizer`), không công tắc. Giữ một ô = xem ảnh
  của ô kia ở cùng chỗ phóng.
- Vuốt ngang một ô = bước sang ảnh kế/trước (bỏ qua ảnh ô kia đang hiện). Chạm ảnh trong dải = đưa vào B,
  kéo ảnh lên A = đưa vào A.
- Thanh trên: ✕ · tiêu đề + `Keeping N · deleting M` · **Delete N** (chỉ với nguồn chọn ảnh). Trên màn trong
  Duo thanh lùi xuống `CompareLayout.duoInnerTopInset` cho khỏi góc bo.
- Video trong lựa chọn hiện khung ảnh đại diện, không phát.

## 4. Xoá

- Mỗi ô một **Keep | Delete**; ảnh Delete có viền đỏ, mờ trong dải, chấm đỏ.
- **Delete N** (đỏ, ⌘⌫) xoá các ảnh đánh dấu, theo thứ tự trong màn:
  - chỉ có bản trong Photos → hộp thoại của hệ thống, vào **Recently Deleted**, banner báo;
  - có bản ở thư mục hoặc server → xác nhận của ShotDex trước ([FS-19.04 §2](../FS-19-photo-sources/04-deleting-and-duplicates.md)).
- Huỷ ở hộp thoại → không đổi gì, dấu còn nguyên. Xoá xong ảnh rời màn; còn dưới 2 ảnh thì màn tự đóng.
- Không có dấu nào → nút là `Delete`, mờ.

## 5. Tiêu chí nghiệm thu

- **AC-1** Viewer không có Single · 2-Up · Survey ở iPhone, iPad, Duo (trong + ngoài). — ảnh chụp sim
- **AC-2** Chọn 2–N ảnh → Compare → màn A/B tối với `Compare · N photos`. — ảnh chụp sim
- **AC-3** Đánh dấu Delete một ảnh → `Keeping N-1 · deleting 1`, nút `Delete 1` sáng. — `SelectionCompareModelTests`, ảnh chụp
- **AC-4** Delete N gửi đúng các ảnh đánh dấu, theo thứ tự; Huỷ không đổi gì. — `SelectionCompareModelTests`
- **AC-5** Xoá còn dưới 2 ảnh → màn đóng. — `SelectionCompareModelTests` (dưới 2 = đóng)
- **AC-6** Có bản ngoài Photos → xác nhận ShotDex trước, không xoá thẳng. — `SelectionCompareModelTests`
- **AC-7** Duplicates mở cùng màn, không có Delete N, giữ nguyên hành vi cũ. — ảnh chụp sim
