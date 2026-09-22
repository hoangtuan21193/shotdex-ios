# FS-06.01b — Album Detail, quản lý album và Creations

`FS-06.01b` · `Features/Albums/AlbumDetailScreen.swift` · `CreationsScreen` · `Features/Shared/PhotoDragItem.swift`
· bảng `creations` · cập nhật 2026-09-22

**Một câu:** mở một album ra thì làm được gì, và ShotDex **mở lại được thứ chính nó đã làm ra**.

Bố cục tab: [FS-06.01](01-tabs-tokens-and-album-management.md).

## 1. Quy tắc

- Album Detail dùng **chung lưới** với Library (nhưng neo đỉnh).
- **Con trỏ phân trang tách khỏi số ảnh đang hiện** — danh sách của hệ thống là một bản chụp bất biến.
- Thả ảnh lên album chỉ **thêm vào**, không bao giờ di chuyển hay xoá.
- Công thức của Creations lưu thành **một chuỗi JSON phẳng**, không lồng kiểu dữ liệu.

## 2. Album Detail

- Lưới phân trang **120 ảnh mỗi trang**; trang kế nạp khi ô gần cuối hiện ra.
- Pinch đổi mật độ 1…8 (nhớ chung với Library); lưới phẳng, ngày hiện dưới tên album ở thanh trên.
- Chế độ chọn đầy đủ như Library; menu giữ-lâu có thêm **Remove from Album**.
- **Con trỏ phân trang** giữ riêng, nên sau khi xoá ảnh thì trang kế **bỏ qua** những ảnh đã mất thay vì
  nối lại trùng.
- Có biểu ngữ quyền giới hạn + nút Manage khi quyền ảnh bị giới hạn.

## 3. Sắp xếp trong Album Detail

Nút sắp xếp cạnh Select: **Album Order · Newest First · Oldest First**.

- **Album Order = không sắp gì cả** — đó là cách thư viện trả về thứ tự riêng của album (thứ tự thêm vào,
  hoặc thứ tự người dùng tự kéo trong Photos).
- **Smart album không có Album Order**: nó là một truy vấn, không có thứ tự riêng nào để quay về. Mặc định
  của smart album là Newest First, của album người dùng là Album Order.
- **Nhớ theo từng album**, không phải một thiết lập chung: album chuyến đi đọc theo thứ tự nó xảy ra, album
  hình nền đọc theo thứ tự thêm vào — một công tắc chung thì cứ đổi album là phải chọn lại.
- Đổi thứ tự phải **báo cho lưới bằng một số hiệu mới**: sắp lại giữ nguyên số ảnh lẫn tập ảnh nên không
  còn tín hiệu nào khác nói cho lưới biết danh sách đã khác.
- Ở **Album Order thì lưới bỏ tiêu đề ngày** — chia theo ngày sẽ cắt vụn đúng cái trình tự người dùng tự xếp.

## 4. Quản lý album

- Giữ một tile album của người dùng → menu **Rename · Delete Album**. Album hệ thống không có menu vì hệ
  thống từ chối cả hai.
- Đổi tên và tạo mới dùng chung **một** hộp thoại có ô nhập.
- Xoá có hộp xác nhận nói rõ hậu quả: *"The photos stay in your library."*
- **Chưa có**: kéo sắp xếp thứ tự album, và chọn ảnh bìa (hệ thống không cho đọc ảnh bìa của album).

## 5. Creations

Hai hàng riêng trong Utilities: **Collages** và **Video Projects**, kèm số lượng. **Luôn hiện kể cả khi
rỗng** — chúng cũng là chỗ *bắt đầu* một cái mới.

- Gộp thành một hàng "Creations" đã thử và bỏ: cái tên không nói trong đó có gì, mà collage và video xuất
  phát khác chỗ và sửa bằng hai công cụ khác nhau.
- Tên là **"Video Projects" chứ không phải "Videos"**: Media Types đã có album `Videos` nghĩa là *cảnh quay
  người dùng tự quay* — tên đó do hệ thống đặt, không đổi được — còn đây là thứ Video Studio làm ra và mở
  lại sửa được. `Collages` không cần định ngữ vì không có gì khác trong tab trùng tên.
- Mỗi hàng mở một màn danh sách: nút `+` trên thanh trên và nút **New Collage / New Video Project** ở màn
  rỗng → ô chọn ảnh → mở thẳng công cụ với ảnh vừa chọn.
- Mỗi dòng: ảnh bìa của bản đã xuất · **ngày sửa gần nhất làm tiêu đề** (không lặp chữ "Collage" ở mọi dòng
  của một danh sách vốn đã chỉ một loại) · số ảnh nguồn ở dòng phụ. Chạm mở lại **đúng công cụ đã làm ra
  nó**; giữ để gỡ khỏi danh sách.

## 6. Bảng riêng cho Creations

Mỗi dòng giữ: id · loại · id ảnh đã xuất (rỗng khi người dùng xoá ảnh đó) · ngày tạo · ngày sửa · **công
thức dạng JSON**; có chỉ mục theo ngày sửa.

Bảng riêng vì hai lý do:

1. Lượt index ghi đè cả dòng metadata của ảnh nên cột lạ bị xoá trắng mỗi lần index
   ([BD-02](../../01-basic-design/BD-02-database-design.md)).
2. Dữ liệu này khoá theo **sản phẩm**, không theo ảnh — một collage lấy 4 ảnh và đẻ ra ảnh thứ 5, không
   dòng nào trong 5 dòng đó là nhà của nó.

- Công thức lưu thành **chuỗi JSON phẳng**: nếu để thư viện database tự lồng, nó sẽ đưa cả **dòng database**
  cho kiểu lồng bên trong, khiến bộ giải mã đi tìm tên cột và cho ra một công thức rỗng — smart album đã
  dính đúng bẫy này.
- **Mở lại**: màn collage và Video Studio nhận một sản phẩm đã lưu và dùng **công thức đó** thay cho công
  thức dựng từ danh sách ảnh. Với video, việc nạp vốn đã đi theo công thức nên cắt, tốc độ, chữ và nhạc về
  đúng như lúc xuất.
- Ảnh nguồn **lấy lại theo id** chứ không lưu (ảnh của hệ thống không lưu được). Thiếu một ảnh thì báo thẳng
  *"Some of the photos this was made from are no longer in your library."* chứ không mở ra một collage
  thiếu ô.
- Xuất lại **cập nhật đúng dòng cũ**, không đẻ dòng thứ hai.

## 7. Kéo thả ảnh

Mỗi ảnh được gói **hai cách** khi kéo:

1. **File gốc** đúng định dạng của nó (cho phép tải bản trên iCloud) để thả sang app khác — ảnh kéo ra phải
   là *ảnh*, EXIF và tất cả, không phải một bản thu nhỏ.
2. **Id nội bộ** dưới một định dạng riêng của app, **chỉ dùng trong tiến trình này**, để thả trong app —
   thả 40 ảnh vào một album không được xuất 40 file trước.

- **Định dạng riêng chứ không phải định dạng công khai**: id nội bộ vô nghĩa ngoài máy này, nên không chào
  nó cho app khác.
- **Kéo chỉ chạy trong chế độ chọn, và chỉ từ ô đã chọn.** Ngoài chế độ chọn, chạm-giữ là cử chỉ *vào* chế
  độ chọn — một cú chạm không mang được hai nghĩa. Trong chế độ chọn hai cử chỉ chia nhau sạch: quét chọn
  cần **di chuyển**, nên ngón nằm yên đủ lâu cho hệ thống nhấc lên là rõ ràng muốn kéo.
- Kéo là **cả lựa chọn**, không phải ô dưới ngón — chọn ảnh rồi kéo đi đâu đó là **một** ý nghĩ.
- **Thả lên tile album** chỉ **thêm vào**. Album không cho thêm (smart album, album chia sẻ) thì **không
  sáng viền** — sáng lên rồi từ chối là nói dối.

## 8. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
