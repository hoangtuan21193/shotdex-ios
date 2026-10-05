# spec-pending — slug `export` (D4, H1, Z1, Q8, Z2 phần Collage, H2, Z4)

Các chỗ sau cần sửa nhưng nằm trong file không được phép chạm ở lượt /spec này.

1. `docs/02-functional-spec/FS-03-photo-editor/07c-export-acceptance-criteria.md` · §1 bảng "Chỗ đã chốt", hàng 2 (Bố cục sheet) · thay
   "iPad form canh giữa rộng tối đa 700pt như Resize;" bằng
   "iPad form canh giữa rộng tối đa 700pt (Resize ở iPad ngang đã là hai pane, [FS-03.07 §4](07-resize-and-compression.md));" · Z1

2. `docs/02-functional-spec/FS-03-photo-editor/README.md` · bảng các phần, hàng 07 · thay
   "| 07 | [Resize](07-resize-and-compression.md) | preset, preview, chạy cả mẻ |" bằng
   "| 07 | [Resize](07-resize-and-compression.md) | preset, preview, hai pane ở cửa sổ rộng, chạy cả mẻ, toast + Share sau khi lưu, 16 AC |" · D4, H1, Z1

3. `docs/README.md` · dòng cây tài liệu có "FS-11 Collage" · thay "FS-11 Collage" bằng "FS-11 Collage (+ FS-11b màn xuất)" · Z1, H1

4. `DESIGN.md` · §10.1d (cuối section, hoặc một mục §10.1d-ter mới) · thêm:
   "- **Màn công cụ có preview + tuỳ chọn + một nút chính** (Resize, Collage Export): cửa sổ rộng ≥ 700pt, cao ≥ 600pt
   và rộng hơn cao thì hai pane — preview trái lấy phần còn lại, cột phải 400pt, nút chính ghim đáy cột; còn lại một cột
   với nút chính ghim trên home indicator. Preview là nội dung nên được to ra (điều kiện của §10.1d)." · Z1

5. `docs/02-functional-spec/FS-08-settings/README.md` · bảng các phần, hàng 05 và 06 · đổi "19 AC của bố cục + search" thành
   "19 AC của bố cục + search, 5 AC widget trên cửa sổ thấp"; đổi "21 AC" thành "26 AC" · Z4, H2
   (README chỉ được sửa để đăng ký part; lượt này không tạo part mới ở FS-08.)
