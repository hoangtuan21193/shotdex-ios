# BD-03.02 — Đọc EXIF

`BD-03.02` · `Data/Sources/ExifReader.swift` · `Domain/Indexing/IndexPipeline.swift`
· `Data/Database/MetadataStore.swift` · cập nhật 2026-09-23

**Một câu:** hai pha của một lượt chạy, thang cách lấy dữ liệu, và ba kết cục có thể xảy ra khi đọc một ảnh.

## 1. Quy tắc

- **Không giải mã ảnh**, và không tải ảnh đầy đủ chỉ để đọc metadata.
- Hỏi hệ thống "ảnh này gồm những file nào" **đúng một lần cho mỗi ảnh** — không lặp lại lời gọi liên tiến trình.
- Luôn đọc **file gốc**, kể cả với ảnh đã chỉnh sửa.
- **Đọc hỏng không được đè lên EXIF đã có.**
- Cùng một lần mở file đó còn trả lời **"đây có phải panorama ShotDex ghép không"**: thẻ XMP trong file,
  đọc qua đối tượng metadata của ImageIO chứ không phải từ dict thuộc tính (XMP không nằm trong đó).
  Kết quả gộp với cờ panorama của hệ thống thành cột `isPanorama`
  ([FS-14 §7](../../02-functional-spec/FS-14-panorama/01-screen-and-flow.md)). Hai điều đi kèm:
  thẻ **không** làm một file không EXIF thành "đã đọc EXIF" — nó nói ảnh là gì, không nói phơi sáng bao
  nhiêu; và đường ghi của lần **đọc hỏng** chỉ được bật cờ lên, không bao giờ tắt, vì đường đó không mở
  file nên không thể biết thẻ còn hay mất.

## 2. Hai pha mỗi lượt chạy

**Pha 1 — ghi nhanh.** Duyệt thư viện, ảnh nào chưa có dòng thì ghi ngay một dòng từ **dữ kiện hệ thống
biết sẵn** (ngày, kích thước, toạ độ, favorite; dung lượng để trống, **không hỏi thêm gì cho từng ảnh**),
đánh dấu **chưa đọc**, ghi theo lô 1.000 dòng mỗi lần. Cả thư viện có dòng trong vài giây → lưới, sắp xếp
và nhóm theo ngày dùng được ngay, còn EXIF điền dần ở pha 2. Pha này **không đè dòng đã có**, kể cả khi
người dùng chọn đọc lại toàn bộ.

**Pha 2 — đọc EXIF.** Duyệt theo **ngày chụp giảm dần** (ảnh mới index trước), theo lô 200, và trong mỗi lô
đọc song song tối đa 12 ảnh. Kết quả gom lại **đúng thứ tự lô**.

Bỏ hẳn bước mở file khi chắc chắn không có EXIF máy ảnh: **ảnh chụp màn hình** và **video** ghi thẳng kết
luận "không có EXIF" (phép kiểm này là hàm thuần, có test). Video vẫn lấy dung lượng và tên file.

**Dung lượng đọc ở pha 2**, và đọc **ngoài luồng giao diện**, rồi ghi vào database để nhãn trên lưới không
phải hỏi hệ thống ở từng ô lúc cuộn.

## 3. Thang lấy dữ liệu

| # | Bước | Dừng khi |
|---|---|---|
| 1 | đọc file gốc **không dùng mạng**, trần 8 MB | file có sẵn trên máy |
| 2 | **đọc bản thu nhỏ đang có trên máy** | máy còn giữ một bản nào đó |
| 3 | tải lại **có mạng** (nếu chính sách cho phép) | dữ liệu về |
| 4 | file trên máy lớn hơn 8 MB: **thử đọc phần đã gom một lần** | phần đầu file có khối EXIF |
| 5 | mượn đường chỉnh sửa của hệ thống để lấy đường dẫn file gốc (chờ tối đa 10 giây) | — |

- **Bước 2 là bước quan trọng nhất khi máy bật tối ưu dung lượng**: ảnh gốc nằm trên iCloud nhưng hệ thống
  vẫn giữ **một bản thu nhỏ trên máy**, và bản đó **giữ nguyên khối EXIF** (chỉ pixel bị thu nhỏ). Phải xin
  ở **chế độ nhanh**, không phải chế độ chất lượng cao — chế độ kia đòi bản chất lượng cao vốn chỉ có trên
  iCloud nên trả về rỗng và ép đi đường mạng vô ích. Nhờ bước này mà **đa số ảnh đã đẩy lên mây vẫn đọc
  được ngay trên máy**, và tránh luôn lỗi xác thực tài khoản mà việc kéo file gốc hay gây ra.
- **Không xin bản thu nhỏ qua mạng.** Đã thử: trên một thư viện đã đẩy hết lên mây, **1** ảnh được phục vụ
  bản thu nhỏ so với **11+** rơi xuống file gốc, mà số byte mỗi ảnh không đổi. Hệ thống không phục vụ bản
  thu nhỏ cho ảnh không có bản nào trên máy — kết quả duy nhất là thêm một vòng hỏi thất bại cho mỗi ảnh.
- **Chi phí sàn của đường iCloud ≈ 1 MB mỗi ảnh** (hệ thống giao theo khối 1 MB) dù khối metadata chỉ ~64
  KB. Một thư viện 50.000 ảnh đã đẩy hết lên mây ≈ **50 GB** — nên đường dài phải là **chạy nền**, không
  phải bắt người dùng ngồi mở app.

## 4. Phân tích dữ liệu

- Đọc các nhóm thuộc tính chuẩn để lấy: ISO, khẩu, tốc độ, tiêu cự, tiêu cự quy đổi 35mm, tên và hãng ống
  kính, tên và hãng máy. **Không giữ ảnh trong bộ nhớ đệm** khi đọc.
- **Chỉ đường mạng mới đọc dần và dừng sớm**: vừa tải vừa thử đọc, và **huỷ ngay khi đã có metadata**
  (thường 64–300 KB).
- **Đường trên máy thì gom hết rồi đọc một lần.** Đưa một bộ đệm dở dang vào bộ đọc ảnh khiến nó cố khởi tạo
  bộ giải mã video ở **mỗi khối**, sinh ra một chuỗi lỗi lặp làm ngập log và đốt CPU.
- Bộ đệm **chỉ nằm trong bộ nhớ**, không ghi file gốc xuống máy.

## 5. Ba kết cục không-thành-công

| Kết cục | Nghĩa | Xử lý |
|---|---|---|
| **Chờ iCloud** | **chưa lấy được byte nào** — ảnh gốc còn trên mây, hoặc mạng hỏng trước khi dữ liệu về | thử lại **vô hạn, không đếm** |
| **Đọc không ra** | **dữ liệu đã về** trọn vẹn nhưng không tìm thấy metadata (file hỏng, cụt, định dạng lạ) | ghi lỗi và **đếm**; sau 5 lần thì kết luận "không có EXIF" |
| **Thất bại phi mạng** | không lấy được dữ liệu vì lý do **không phải mạng** (không có file ảnh, lỗi đọc đĩa) | **đếm y như trên** |

- Lỗi truyền dữ liệu của iCloud **luôn** rơi vào nhánh "chờ iCloud", nên nhánh thất bại phi mạng trên đường
  mạng là **không thể xảy ra** — mã ở đó chỉ còn để phòng thủ.
- Nhờ vậy một file hỏng thật trên máy vẫn **tự dừng lại** thay vì thử lại mãi, còn một đường mạng chập chờn
  **không bao giờ** khiến ảnh bị dán nhãn oan là "không có metadata".
- Số lần đếm được **đọc lại từ database trước mỗi lần ghi lỗi** nên nó leo qua nhiều lượt chạy; ghi trạng
  thái khác lỗi thì **đặt lại về 0**.
- Đường đọc-một-ảnh của viewer thì **kết luận ngay** khi đọc không ra: nó đã tải cả ảnh rồi, không cần đếm.

## 6. Luật không đè dữ liệu cũ

Với những ảnh mà lượt chạy **không lấy được byte nào**:

- **Chỉ cập nhật dữ kiện hệ thống** (ngày chụp, loại media, kích thước, dung lượng, tên file, toạ độ,
  favorite) cộng trạng thái và số lần đã thử.
- **Mọi trường EXIF giữ nguyên**, và **ngày sửa cố tình để cũ** — đẩy nó lên sẽ khiến một lần chỉnh sửa bị
  quên trước khi kịp đọc lại metadata.
- Ảnh chưa có dòng thì vẫn ghi đầy đủ để ảnh mới hiện ra ngay.

**Vì sao**: **một** lần đọc lại toàn bộ đúng lúc iCloud trả về 0 byte đã làm trắng **49.828 dòng** đang ở
trạng thái đã đọc xong — tên máy, ISO, tất cả về rỗng.

## 7. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
