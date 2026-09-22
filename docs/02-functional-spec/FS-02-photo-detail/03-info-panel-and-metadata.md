# FS-02.03 — Bảng thông tin và Photo Info

`FS-02.03` · `Features/Library/MetadataPanel.swift` · `Domain/Presentation/PhotoInfoPanelSummary.swift`
· `MakerNoteParser` · cập nhật 2026-09-22

**Một câu:** hai dòng tóm tắt trên chrome, và một bảng đầy đủ viết cho người chụp ảnh chứ không phải cho máy.

## 1. Quy tắc

- Bảng tóm tắt **cao đúng 52pt bằng nút đóng**, tối đa **2 dòng**.
- **Không cắt giữa từ** — hết chỗ thì **bỏ cả cụm**.
- **Thông số phơi sáng và dung lượng không bao giờ bị bỏ.** Tên máy là thứ bỏ trước.
- Bảng đầy đủ dựng **ngay từ khung hình đầu bằng dữ liệu đã index**, không chờ đọc file hay chờ iCloud.
- Không hiển thị giá trị không tồn tại; dòng rỗng bị bỏ.

## 2. Hai dòng tóm tắt

| Dòng | Nội dung |
|---|---|
| 1 | **chỉ ngày giờ** — `Today 16:32` / `Yesterday 16:32` cho hai ngày gần nhất, còn lại `10 Jul 16:32`, **thêm năm chỉ khi khác năm hiện tại**. Cộng nhãn định dạng file và trạng thái iCloud |
| 2 | **tên máy** · cụm phơi sáng ghép bằng khoảng trắng (`400mm f/7.1 1/1000 ISO 3200`) · dung lượng |

- Ngày và giờ định dạng riêng nên **không có chữ ` at `** ở giữa.
- Tốc độ dùng dạng rút gọn (bỏ chữ `s` khi dưới 1 giây).
- **Tên ống kính không hiện ở đây** — chỉ trong bảng đầy đủ và trong nhãn trợ năng.
- Một dòng chỉ có ~277pt (393 trừ lề và nút đóng 52) ≈ 49 ký tự. Bản cũ gộp thành **một** dòng và đặt tên
  máy/ống kính (dài nhất) lên đầu, nên phần bị cắt đuôi chính là phần phơi sáng.
- Bề rộng được **đo một lần bằng một lớp nền**, không đo lại mỗi khung — cử chỉ vuốt-đóng vẽ lại giao diện
  mỗi khung. So bằng font hệ thống theo kiểu chữ nên tự theo cỡ chữ người dùng chọn, và ngân sách được chia
  thêm cho mức co chữ mà giao diện cho phép, thay vì bỏ tên máy chỉ vì thiếu vài point.
- Ở cỡ chữ trợ năng thì **ẩn dòng hai** (vẫn giữ 52pt; chi tiết nằm trong bảng đầy đủ).
- Cả bảng là **một phần tử trợ năng có vai trò nút**: nhãn đọc **đủ mọi trường kể cả trường đã bỏ**, cộng
  định dạng và trạng thái iCloud, kèm gợi ý "Shows all photo info".
- Cảnh báo iCloud đứng im chỉ dùng **icon** để bảng không nở chiều cao.

## 3. Bảng Photo Info

Mở bằng nút Info hoặc vuốt lên.

**Thứ tự**: Location → Camera & Lens → Exposure → Capture Settings → Date → File → (Rights/Description) →
Shutter Count → nút xem dữ liệu thô.

| Nhóm | Gồm |
|---|---|
| File | tên file · định dạng · kích thước · megapixel · dung lượng · không gian màu |
| Exposure | tốc độ · khẩu · ISO · EV · tiêu cự · tiêu cự 35mm · khoảng cách chủ thể |
| Capture Settings | chương trình · chế độ · đo sáng · cân bằng trắng · nguồn sáng · flash · cảnh · dải · zoom số |

- Nguồn: dựng ngay từ database, rồi **đọc bổ sung từ file — ưu tiên bản local**, chỉ tìm bản chất lượng cao
  hoặc bản trên iCloud khi máy không có bản nào. Giá trị đọc thêm bổ sung trường sâu, nhưng luôn quay về
  database cho những trường đã index.
- Mã số của chuẩn EXIF được đổi thành nhãn đọc được. Bỏ khỏi bảng mặc định: id nội bộ, DPI, mã hướng ảnh,
  máy chủ, phiên bản EXIF, số sê-ri.
- Mỗi nhóm có **một mặt nền duy nhất** — không có thẻ lồng trong thẻ. Các nhóm chính luôn mở để đọc lướt.
- Bố cục mặc định **hai trường một hàng** (nhãn nhỏ, giá trị đầy đủ, copy được), tự về **một cột** ở cỡ chữ
  trợ năng.

## 4. Location

- Có toạ độ → bản đồ cao **128pt** có ghim, toạ độ và độ cao chung một khối; tên và địa chỉ tra **bất đồng
  bộ**, **không chặn** phần tóm tắt.
- Không có toạ độ → mục Location **vẫn đứng đầu** và ghi rõ **"No location data"**, để phân biệt với lỗi đọc.
- Kết quả tra được cache theo toạ độ đã làm tròn (~10m) và theo ngôn ngữ, nên một loạt ảnh chụp liên tiếp
  không gọi dịch vụ lặp lại.
- iOS 26 dùng API tra địa chỉ mới của bản đồ; bản trước dùng bộ tra của Core Location. Offline thì vẫn hiện
  bản đồ và toạ độ, kèm câu nói rõ tên địa điểm cần mạng.

## 5. Shutter Count

Tải **độc lập sau phần tóm tắt**, nên một ảnh gốc nằm trên iCloud không giữ vòng quay cả bảng. Mục này luôn
cho biết **đang đọc**, **giá trị**, hoặc **lý do không có**.

Bộ đọc maker note đọc tối đa **16 MB** đầu file rồi dừng:

| Hãng | Nguồn |
|---|---|
| Nikon | một thẻ riêng trong maker note |
| Sony | một thẻ đã mã hoá, bố cục khác nhau theo đời máy |
| Fujifilm | ghi đúng là **số ảnh**, không phải số lần đóng màn — có thể bị reset khi cập nhật firmware |
| File RAW của Fujifilm | phải đọc mốc ảnh JPEG nhúng bên trong rồi mới tìm khối EXIF; bản cũ chỉ nhận hai dạng đầu file nên luôn trả rỗng dù tài liệu nói là hỗ trợ |
| Canon, OM, Panasonic, Leica, Pentax-Ricoh, khác | hiện **giải thích giới hạn theo file và đời máy**, không đoán số và không ẩn mục |

## 6. Dữ liệu thô

Nút **"Show All Raw Metadata"** chỉ bật khi lượt đọc nền xong, rồi mở một màn liệt kê mọi thứ đọc được,
nhóm theo nguồn. Từ điển lồng nhau được trải phẳng thành đường dẫn có dấu chấm; maker note dạng nhị phân
hiện **số byte** thay vì đổ cả khối. Mọi khoá và giá trị đều copy được.

## 7. Video

Phần tóm tắt giữ **File / Date / Location + thông tin track hình và tiếng** (thời lượng, kích thước, tốc độ
khung, bitrate, codec). Màn dữ liệu thô vẫn đầy đủ. Giá trị **bôi đen copy được**.

## 8. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
