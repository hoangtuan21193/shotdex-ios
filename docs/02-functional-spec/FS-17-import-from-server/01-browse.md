# FS-17.01 — Duyệt ảnh trên server

`FS-17.01` · `Features/ServerImport/ServerBrowserScreen.swift` · `ServerPhotoGrid` · `Domain/ServerImport/`
· cập nhật 2026-09-26

**Một câu:** folder trên server hiện như Library — folder con ở trên, lưới ảnh bên dưới, thumbnail từ preview
nhúng, chọn nhiều như Library.

## 1. Lối vào

- Collections → Utilities → thẻ **On Server** (luôn hiện, FS-17 §6). Mở màn **On Server** — chưa có connection thì
  màn trống "Add a connection to browse and download photos from your NAS or computer." + **Add Connection**:

| Section | Nội dung |
|---|---|
| Connections | mỗi connection một hàng: tên · `SMB · host/share/folder` (`FileServerRow`) · chạm → duyệt, mở ở folder dùng lần trước của connection (FS-15.02 §2) |
| (không tiêu đề) | **Uploaded from This Device** · số ảnh → màn Uploaded to Server hiện có (FS-15.02 §8); ẩn khi 0 |

- Toolbar màn On Server: **+** → Add Connection (FS-15.04).

## 2. Màn duyệt một folder

- Tiêu đề: tên folder (gốc: tên share / "Home" / host theo giao thức — cùng luật FS-15.02 §2a). Back đi lên cha,
  tới gốc thì về On Server.
- Trên cùng: các **folder con** dạng hàng (icon `folder`, tên, chevron); ẩn folder chấm; sắp kiểu Finder.
- Dưới: **lưới ảnh**, cùng hình học lưới Library (số cột theo độ rộng và mật độ đã lưu, khoảng cách, bo góc, pinch
  đổi cột) — DESIGN.md §lưới, không token mới.
- Chỉ **file ảnh**: đuôi thuộc `UTType.image` và ImageIO đọc được (lấy từ `CGImageSourceCopyTypeIdentifiers`, không
  liệt kê tay). File khác, video, file chấm: ẩn. Dòng cuối lưới: "N photos" (+ "M other files hidden" khi M > 0).
- **Ghép cặp**: file RAW và file JPEG/JPG/HEIC/HEIF cùng tên gốc (không phân biệt hoa thường) trong cùng folder →
  **một ô**, nhãn `RAW+JPG` / `RAW+HEIC`; thumbnail lấy từ file không-RAW (nhỏ, nhanh hơn).
- Nhãn định dạng trên ô: cùng kiểu nhãn Library (`RAW`, `JPG`, `HEIC`, `PNG`, `TIFF`, `DNG`…).
- Dấu **In Library** (glyph `checkmark.circle.fill` nhỏ góc dưới-trái, VoiceOver "In Library") khi ảnh đã có (FS-17
  §4).
- **Sort** (menu toolbar), nhớ theo connection:

  | Lựa chọn | Nguồn | Khi chọn |
  |---|---|---|
  | **Name** (mặc định) | tên file, so kiểu Finder (`IMG_2` trước `IMG_10`) | tức thì |
  | **Date Taken** | EXIF `DateTimeOriginal` đọc từ đoạn đầu file (cùng lượt đọc với thumbnail, §3) | đọc EXIF **cả folder** (không chỉ ô đang hiện), thanh "Reading dates… 120 of 500" trên lưới, **sắp lại một lần** khi đọc xong — không nhảy ô từng cái; file không có EXIF dùng ngày sửa |
  | **Date Modified** | ngày sửa file server trả khi liệt kê | tức thì |

  Phần hai của menu: **Ascending** (mặc định) / **Descending**. Ngày chụp đã đọc được cache cùng thumbnail (khoá
  FS-17 §4), mở lại folder không đọc lại. Ảnh ghép cặp lấy ngày của file không-RAW, thiếu thì của RAW.

| Trạng thái | Hiển thị |
|---|---|
| đang liệt kê | spinner giữa màn |
| folder rỗng / không có ảnh | "No photos in this folder." (+ folder con nếu có) |
| lỗi nối | câu lỗi FS-15.01 §3 + **Try Again** |
| đang tải thumbnail | ô xám cùng màu placeholder của Library + nhãn định dạng hiện ngay |
| không lấy được thumbnail | ô có icon định dạng lớn + tên file |

## 3. Thumbnail

Thứ tự thử, dừng ở bước đầu tiên ra ảnh ≥ 320 px cạnh dài (ảnh nhỏ hơn giữ làm tạm, tiếp tục thử). Cặp RAW+JPEG
thử **file RAW trước** — đoạn đầu RAW rẻ hơn tải trọn JPEG.

1. Đọc **256 KB đầu** file (range read).
2. ImageIO trên đoạn đó (JPEG/HEIC có EXIF thumbnail, NEF, DNG iPhone), rồi tách **JPEG nhúng có đủ byte** — tìm điểm
   kết thúc bằng cách đi qua marker, vì ImageIO gọi một JPEG bị cắt là "complete" khi mới đọc header; chọn JPEG nhỏ
   nhất mà ≥ 320 px.
3. RAF: đọc JPEG preview theo con trỏ ở byte 84–91 của header nếu ≤ 8 MB.
4. RAW khác: đọc tiếp tới **1 MB**.
5. File **không phải RAW** và ≤ 25 MB → tải trọn, ImageIO thumbnail.
6. Không được → icon định dạng.

Đo 2026-09-26 (một file mỗi hãng, raw.pixls.us + CR3 Canon R6 II): NEF 640 px, PEF/DNG Pentax 720 px, DNG iPhone 400
px trong 256 KB; CR3 1620 px, ARW 1616 px, ORF 3200 px, RW2 trong 1 MB; RAF 4416 px qua con trỏ (5.7 MB). Mười file
đều ra thumbnail ≥ 320 px.

- **Ngày chụp** (Date Taken) đọc từ 64 KB đầu: EXIF qua ImageIO; không được (CR3, RAF, PEF, ARW, RW2) thì chuỗi ngày
  EXIF đầu tiên trong đoạn đó — máy ảnh ghi DateTime và DateTimeOriginal bằng nhau; đúng cả 10 file mẫu.
- Kết quả thu về 400 px (cạnh dài), lưu cache đĩa (FS-17 §4). Mở lại folder: thumbnail từ cache, không đọc mạng.
- Chỉ làm cho ô **đang hiện hoặc sắp hiện** (một màn phía trước); cuộn qua thì huỷ; tối đa 4 luồng mỗi connection.
- Một connection dùng chung cho liệt kê + thumbnail của cả lượt duyệt; rời màn On Server thì đóng.

## 4. Chọn nhiều

- **Select** trên toolbar → chế độ chọn giống Library: chạm để chọn/bỏ, vuốt để chọn dải, **Select All** trong
  menu, số đã chọn ở tiêu đề. Ảnh ghép cặp = một lựa chọn.
- Thanh dưới: **Download** (kèm số) — mờ khi 0. Ảnh "In Library" chọn được nhưng sheet tải về mặc định bỏ qua chúng
  (FS-17.02 §1).
- Không ở chế độ chọn: chạm ô → xem lớn (preview nhúng, fit màn hình), tên, dung lượng, ngày sửa, camera/ống kính
  nếu EXIF đọc được từ đoạn đầu; nút **Download** cho riêng tấm đó (FS-17 §6).
