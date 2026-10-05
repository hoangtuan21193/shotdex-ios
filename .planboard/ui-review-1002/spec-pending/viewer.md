# Pending spec edits — slug `viewer` (Q1, Q2, Q7, V1–V4, Z5, D5)

Áp khi file đích không còn thay đổi chưa commit của phiên khác. Mỗi mục: file · section · thay đổi · ID.

## DESIGN.md

1. **§10.4 Sheet** — thêm bullet cuối (Q1):
   > - **Mọi sheet có nút đóng nhìn thấy trong thanh tiêu đề** (2026-10-02): sheet chỉ-đọc dùng `Done` bên phải, sheet
   >   nhập liệu giữ `Cancel` trái. Không trông vào vuốt xuống: ở cửa sổ regular-width compact-height (Duo trong
   >   951×669) hệ thống bỏ detent và sheet thành toàn màn.
2. **§6 Khoảng cách và kích thước** — chỉ khi ⚠️ CẦN QUYẾT bề rộng cột Photo Info (FS-02.03b §2) chọn phương án a,
   thêm hàng (V3):
   > | bề rộng cột Photo Info (viewer, cửa sổ ngang ≥ 700pt) | **360** | cố định, không kéo đổi |
3. **§10.3, bullet "Thứ gì phải nhìn ảnh mới chọn được thì không đặt trong sheet"** — nối thêm câu (V3):
   > Photo Info của viewer theo cùng luật: cửa sổ rộng ≥ 700, cao ≥ 600 và rộng > cao thì là cột bên phải
   > ([FS-02.03b](docs/02-functional-spec/FS-02-photo-detail/03b-info-inspector.md)), còn lại là sheet có Done.

## docs/02-functional-spec/FS-01-library/01-photo-grid-and-data-source.md

4. **§1 dòng "trừ bốn ca ở §5"** → "trừ năm ca ở §5" (Q7).
5. **§5, cuối danh sách** — thêm bullet (Q7):
   > - **Đóng viewer**: ô của ảnh vừa xem không thấy trọn thì lưới cuộn một lần, không hoạt ảnh, cho ô nằm giữa vùng
   >   nhìn ([FS-02.01b](../FS-02-photo-detail/01b-closing-and-keyboard.md) §1). Ô đã thấy trọn thì đứng yên.

## docs/02-functional-spec/FS-02-photo-detail/README.md (chỉ được sửa để đăng ký part — đã đăng ký 01b, 03b)

6. **Bảng Chrome, hàng "Trên-trái"** → "nút **X** cao 52pt, và **bảng thông tin ngay bên phải, cùng hàng** (regular
   width: rộng tối đa 520pt)" (V3).
7. **Bảng Cử chỉ, hàng "Vuốt lên"** → "mở Photo Info, giống bấm nút Info — sheet, hoặc cột bên phải ở cửa sổ ngang
   ≥ 700pt ([03b](03b-info-inspector.md))" (V3).
8. **Quy tắc, sau bullet "Đóng viewer không được làm Library nạp lại"** — thêm (Q7, Z5):
   > - **Đóng viewer thì lưới tới ảnh vừa xem**; Esc đóng, ← / → lật ảnh — xem [01b](01b-closing-and-keyboard.md).

## docs/02-functional-spec/FS-02-photo-detail/02-video-playback.md

9. **§9 Tua từng khung** — thêm một dòng theo kết quả ⚠️ CẦN QUYẾT ở FS-02.01b §2 (Z5):
   - nếu chọn a: "Bàn phím: → / ← tiến/lùi một khung khi clip đang dừng; lật trang bằng ⌥→ / ⌥←."
   - nếu chọn b: "Bàn phím: `.` / `,` tiến/lùi một khung khi clip đang dừng; → / ← luôn lật trang (FS-02.01b §2)."

## docs/02-functional-spec/FS-02-photo-detail/07-caption-and-keywords.md

10. **§4, câu đầu** "section đầu của Info sheet, **trên Location**" → "section đầu của Photo Info (sheet hoặc cột),
    **trên Camera & Lens**" (V4).

## docs/02-functional-spec/FS-06-collections/06-duplicates.md hoặc 06b

11. **Chỗ nói Compare mở từ Duplicates** — thêm (V2, Q2):
    > Xoá trong Compare mà nhóm còn ≥ 2 ảnh thì Compare ở lại; lỗi xoá do chính Compare báo, vì cảnh báo của
    > Duplicates nằm dưới lớp phủ toàn màn ([FS-01.08](../FS-01-library/08-compare.md) §4).
