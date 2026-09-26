# FS-17.01 — Duyệt ảnh trên server

`FS-17.01` · `Features/ServerImport/ServerBrowserScreen.swift` · `ServerPhotoGrid` · `Domain/ServerImport/`
· cập nhật 2026-09-26

**Một câu:** folder trên server hiện như Library — folder con ở trên, lưới ảnh bên dưới, thumbnail từ preview
nhúng, chọn nhiều như Library.

## 1. Lối vào

- Collections → Utilities → thẻ **On Server** (hiện khi có ít nhất một connection, FS-17 §6). Mở màn **On Server**:

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
- Sắp xếp: menu toolbar **Name** (mặc định) / **Date Modified**, nhớ theo connection.

| Trạng thái | Hiển thị |
|---|---|
| đang liệt kê | spinner giữa màn |
| folder rỗng / không có ảnh | "No photos in this folder." (+ folder con nếu có) |
| lỗi nối | câu lỗi FS-15.01 §3 + **Try Again** |
| đang tải thumbnail | ô xám cùng màu placeholder của Library + nhãn định dạng hiện ngay |
| không lấy được thumbnail | ô có icon định dạng lớn + tên file |

## 3. Thumbnail

Thứ tự thử, dừng ở bước đầu tiên ra ảnh ≥ 320 px cạnh dài (ảnh nhỏ hơn giữ làm tạm, tiếp tục thử):

1. **Đọc đoạn đầu** file (mặc định 512 KB — con số chốt sau spike) bằng range read.
2. ImageIO incremental trên đoạn đó → thumbnail có sẵn (JPEG/HEIC/TIFF có EXIF thumbnail, DNG/NEF nhiều máy).
3. Tách **JPEG nhúng lớn nhất giải mã được** trong đoạn đó (SOI…EOI) — cách lấy preview `PRVW` của CR3 và
   `JpgFromRaw` của các RAW dạng TIFF.
4. File **không phải RAW** và ≤ 25 MB → tải trọn, ImageIO thumbnail.
5. Không được → icon định dạng.

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
