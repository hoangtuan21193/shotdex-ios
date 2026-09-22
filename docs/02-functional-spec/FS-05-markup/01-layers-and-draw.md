# FS-05.01 — Bốn loại lớp và Draw

`FS-05.01` · `Domain/Editing/ShapeOverlayGeometry.swift` · `Features/Editing/EditorDrawingCanvas.swift`
· cập nhật 2026-09-22

**Một câu:** hình và kính lúp hoạt động thế nào, và vì sao vẽ tay là một chế độ chiếm trọn khung.

## 1. Quy tắc

- Hình học của hình vẽ là **một bộ toán thuần**, dùng chung cho renderer và cho bản vẽ sống trên ảnh.
- **Kính lúp ghép trước, vành vẽ sau** — nó là lớp duy nhất mà hình dạng phụ thuộc ảnh bên dưới.
- Vào Draw là **chiếm trọn màn**: lối ra duy nhất là Clear hoặc Done (giống chế độ cắt ảnh, không có Cancel).

## 2. Hình

Năm kiểu: **chữ nhật · elip · bong bóng thoại · mũi tên · đường thẳng**.

- **Mũi tên và đường thẳng không tô được**: tô một mũi tên là tô cái tam giác tạo ra nó, không phải làm mũi
  tên dày hơn.
- **Đổi kiểu được sau khi tạo** — lỡ đặt hình vuông mà muốn hình tròn thì không phải xoá lớp rồi đặt lại.

## 3. Kính lúp

- Phần phóng được **ghép vào ảnh trước** bộ lớp còn lại: phóng ảnh quanh tâm vòng tròn rồi trộn theo một
  mặt nạ đĩa. Nếu cắt thẳng, mép vòng sẽ răng cưa ở độ phân giải xuất.
- **Vành** thì vẽ cùng chỗ với mọi lớp khác.
- **Luôn tròn, không bóp méo được** — kính lúp méo thì làm mờ đúng thứ nó phải làm rõ.
- Phóng 1× thì coi như không có tác dụng.
- **Kính lúp không được chọn vẫn phải nướng vào ảnh** khi đang sửa lớp khác: bản vẽ sống nằm trên một lớp
  trong suốt, không có pixel nào để phóng — bỏ chúng ra là mất trắng kính lúp suốt thời gian có lớp đang chọn.
- Riêng kính lúp **đang chọn** thì nhường chỗ như mọi lớp khác, nếu không vành sẽ hiện **hai vòng** lúc kéo:
  một chỗ đã nướng, một dưới ngón tay. Đối xứng lại, bản vẽ sống chỉ vẽ vành của kính lúp đang chọn.

## 4. Draw

Chip **Draw** mở một chế độ chiếm trọn khung.

| Mục | Chi tiết |
|---|---|
| Canvas | khung vẽ của hệ thống + bảng công cụ của nó (bút, bút dạ, tẩy, màu), nhận **cả ngón tay lẫn Apple Pencil** |
| Chrome | **Clear · Done ở hàng trên** — bảng công cụ của hệ thống nổi ở **đáy**, nên đáy đã bị chiếm; panel và tab bar ẩn hẳn |
| Khung | canvas vừa khít ảnh, **không cuộn, không phóng trong chế độ vẽ** (v1) nên điểm trên canvas ánh xạ thẳng vào ảnh; vào Draw là đặt lại mức phóng |
| Chốt | Done ghi cả phiên vẽ thành **một** bước hoàn tác; nét rỗng thì coi như không có |

- Trạng thái vẽ có một **mã thay đổi** để canvas dựng lại khi Clear hoặc khi nạp — cơ chế quan sát tinh vi
  của SwiftUI không tự bắn cho một khối dữ liệu thô.
- Nét vẽ là **một dòng trong danh sách lớp** (dưới cùng vì nó ghép dưới mọi lớp khác): chạm để mở lại canvas
  vẽ tiếp, con mắt để ẩn/hiện (ẩn vẫn **giữ nét**), vuốt để xoá.
- Chỉ canvas và renderer biết tới thư viện vẽ; phần dữ liệu trong công thức chỉ là một khối byte.

## 5. Render nét vẽ

Nét vẽ ghép **ngay trước** các lớp còn lại — nét ở dưới, chữ ở trên để chữ vẫn đọc được.

- Có trong đường render chính và trong **bản chỉ để hiển thị** của bản xem trước; bản sạch dùng cho ống hút
  màu và histogram thì **bỏ qua nét** (như với mọi lớp khác); thumbnail và mặt nạ mask cũng sạch.
- Live Photo raster **một lần** rồi ghép cho mọi khung.
- Raster theo đúng tỉ lệ giữa khung xuất và khung lúc vẽ, vẽ theo chiều bottom-up đúng quy ước của lớp ảnh,
  và **cache** theo nội dung + kích thước — nét chỉ đổi lúc bấm Done nên không raster mỗi khung.
- Bản xem trước khi đang cắt ảnh **bỏ cả lớp markup lẫn nét vẽ**.

## 6. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
