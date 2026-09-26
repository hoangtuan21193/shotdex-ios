# Intent: Duyệt ảnh trên server và tải về thư viện để sửa trên điện thoại

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan@karabiner.tech |
| Ngày | 2026-09-26 |
| Trạng thái | accepted — người dùng duyệt 2026-09-26 |
| Tiến độ | **đang làm** (2026-09-26) — task 6 của plan (3/7 khối B), 7/17 AC xanh |
| Nguồn | phản hồi người dùng (2026-09-26) |
| Spec sinh ra từ đây | [FS-17](../02-functional-spec/FS-17-import-from-server/README.md) — 16 AC |

## Problem — vấn đề

Chiều ngược của FS-15. Kho ảnh — RAW nặng, và cả JPEG, HEIC, TIFF, PNG… — nằm trên NAS/Mac; người chụp muốn lấy
**vài tấm** về iPhone/iPad để sửa trong ShotDex. RAW là trường hợp nặng nhất, không phải trường hợp duy nhất. Hôm nay phải: mở Files (chỉ SMB), mò theo tên file vì không thấy ảnh (Files hiện icon RAW, không
thu nhỏ được nhiều định dạng), tải từng file, lưu vào Photos bằng tay — RAW và JPEG cùng tên thành **hai ảnh
riêng**, ngày trong thư viện thành ngày tải về, và không biết tấm nào mình đã có sẵn.

Quyết định cũ phải xem lại: [FS-10](../02-functional-spec/FS-10-import.md) (2026-09-24) gỡ màn Import vì
"ShotDex đọc thư viện, không quản lý file", và bác cả lối ở menu ⋯ Library lẫn nút ở Collections. Tải từ server
là một lối import mới — người dùng chốt 2026-09-26 đặt nó ở **Collections → Utilities**, qua thẻ **On Server**
đã có, không thêm nút hay tab mới. FS-10 phải được sửa cho khớp.

## Proposed outcome — kết quả mong muốn

- Collections → Utilities → **On Server** mở ra danh sách connection (cùng hàng "ảnh đã upload" hiện nay). Chọn
  một connection → duyệt folder.
- Mỗi folder hiện như **lưới Library**: **mọi file ảnh** iOS đọc được và Photos nhận — RAW mọi hãng và DNG, JPEG,
  HEIC/HEIF, PNG, TIFF, GIF, WebP, AVIF… (không video, không file khác); thu nhỏ thật, nhãn định dạng trên ô như
  Library; folder con ở trên. RAW + JPEG hoặc RAW + HEIC cùng tên hiện **một ô** có nhãn RAW+JPEG / RAW+HEIC.
- Chọn nhiều (giống chế độ chọn của Library) → **Download** → chọn **Library** hoặc **một album** (có sẵn hoặc tạo
  mới).
- Ảnh vào Photos: mỗi file ảnh thành một ảnh; RAW + JPEG/HEIC cùng tên gộp thành **một ảnh**; **giữ ngày chụp gốc** trong EXIF; file được **kiểm SHA-256** sau
  khi tải, lệch thì không ghi vào Photos.
- Ảnh **đã có** (đã upload từ máy này và còn trong thư viện — lịch sử FS-15 khớp đường dẫn và checksum) có dấu
  **In Library**, mặc định không tải lại.
- Tải lớn: tiến độ theo byte, giữ màn hình sáng, huỷ được, giống upload.

## Affected users and systems — phạm vi ảnh hưởng

- Collections → Utilities (thẻ On Server đổi vai), màn mới: danh sách connection, lưới ảnh server, sheet tải về.
- iPhone · iPad · Duo trong · Duo ngoài (lưới phải theo luật màn rộng: nhiều ảnh hơn, không ảnh to hơn).
- Data: `RemoteFileClient` thêm đọc một đoạn file (range read) — SMBClient có `FileReader.read(offset:length:)`,
  Citadel có `SFTPFile.read(from:length:)`; ghi asset qua `PHAssetCreationRequest` (đã dùng ở
  [PhotoLibraryService.swift:980](../../ShotDex/Data/Sources/PhotoLibraryService.swift:980)), RAW làm resource
  `.photo` + JPEG làm `.alternatePhoto`. Domain: ghép cặp RAW+JPEG theo tên, lọc đuôi ảnh, đối chiếu lịch sử.
- Cache thumbnail trên đĩa (giới hạn dung lượng, xoá được).
- Database: có thể cần bảng lịch sử tải về (asset mới ↔ file trên server) để lần sau biết "đã có" — dữ liệu người
  dùng tạo ra → bảng riêng (BD-02).
- Tài liệu: sửa FS-10, FS-06 (Utilities), FS-15 §8.

## Constraints — ràng buộc

- Thumbnail: **đọc preview nhúng** bằng range read vài trăm KB đầu file (RAW, và JPEG/HEIC/TIFF có thumbnail
  EXIF); chỉ tải trọn khi không lấy được (người dùng chốt 2026-09-26). Không tải trọn 200 file RAW chỉ để xem lưới;
  ảnh nhỏ (PNG, GIF, JPEG không thumbnail) tải trọn là chấp nhận được, có giới hạn dung lượng mỗi file.
- "File ảnh" = đuôi mà ImageIO đọc được (`CGImageSourceCopyTypeIdentifiers`) và thuộc `UTType.image` — lấy từ
  hệ thống, không tự liệt kê tay; định dạng Photos từ chối khi ghi thì báo lỗi theo từng file, không hỏng cả lô.
- Bộ nhớ: không giải mã RAW full-res để làm thumbnail; không giữ cả file trong RAM (NF-02).
- Chỉ ghi vào Photos bằng PhotoKit (không kho riêng) — đúng tinh thần FS-10: ShotDex không có thư viện riêng.
- Quyền `.limited`: ảnh vừa tạo vẫn thấy được; ghi vào album cần quyền đọc-ghi đầy đủ → nói rõ khi thiếu.
- Không tải nền (như upload): giữ app mở, màn hình không tự khoá.

## Open questions — câu hỏi còn treo

- ~~Lối vào~~ → Collections → Utilities (người dùng chốt 2026-09-26).
- ~~Thumbnail~~ → preview nhúng (chốt).
- ~~Cặp RAW+JPEG, ảnh đã có, checksum, ngày chụp~~ → gộp, bỏ qua, có kiểm, giữ ngày gốc (chốt).
- Tỉ lệ RAW lấy được preview trong 512 KB đầu, theo hãng (CR3, NEF, ARW, RAF, DNG, ORF)? — spike đo với file mẫu;
  quyết định kích thước đoạn đọc.
- "Đã có" với ảnh **không** đi qua upload của ShotDex (chụp bằng máy này, rồi tự chép lên NAS) — có đối chiếu theo
  tên + ngày chụp + kích thước không? (đề xuất: v1 chỉ dựa lịch sử ShotDex; `/spec` chốt).
- ~~Định dạng~~ → **mọi file ảnh**, không riêng RAW (người dùng chốt 2026-09-26).
- Video trên server có hiện/tải không? (đề xuất: v1 chỉ ảnh, đúng yêu cầu "chỉ show file ảnh").
- WebP, AVIF, GIF động: Photos có nhận qua `PHAssetCreationRequest` trên iOS 17 không? — đo khi spike.
