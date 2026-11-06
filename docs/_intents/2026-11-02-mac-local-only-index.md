# Intent: Mac index nhanh — chỉ ảnh đã có bản gốc trên Mac, không kéo gì từ iCloud

| Trường | Giá trị |
|---|---|
| Tác giả | Hoang Tuan (người dùng) · Claude soạn |
| Ngày | 2026-11-02 |
| Trạng thái | accepted (2026-11-02, người dùng trả lời câu hỏi trong phiên và bảo code luôn) |
| Tiến độ | **gần xong** (2026-11-02) — code xong, Mac build sạch; spec [BD-03.05](../01-basic-design/BD-03-metadata-indexing-flow/05-shared-index.md) §1; AC-1/2 chưa kiểm (Mac chưa ký được với iCloud) |
| Nguồn | tự nghĩ ra (người dùng, 2026-11-02) |
| Spec sinh ra từ đây | [BD-03.05](../01-basic-design/BD-03-metadata-indexing-flow/05-shared-index.md) |

## Bối cảnh

Mac thường còn nhiều chỗ trống, nên nhiều người chọn **Download Originals to this Mac** trong Photos: bản gốc nằm sẵn
trên máy. Ảnh nào cũng index được mà không cần mạng. Intent này đi cặp với
[2026-11-02-icloud-shared-index](2026-11-02-icloud-shared-index.md): ảnh Mac bỏ qua sẽ được máy khác cùng iCloud
index rồi gửi về. Mỗi intent vẫn đứng riêng được: Mac-only không cần sync, chỉ là ảnh bỏ qua chờ lâu hơn.

## Problem — vấn đề

Hôm nay Mac index theo đúng đường của iPhone, chỉnh cho máy có ít bản gốc, mạng yếu và hay nóng máy:

- **Không có cách bảo app "đừng đụng iCloud".** Ảnh chưa có bản gốc trên Mac rơi xuống đường đọc mạng trong
  `ExifReader.readExif` (`ShotDex/Data/Sources/ExifReader.swift:249`, stream 8 s). Đo trên thiết bị: PhotoKit giao
  dữ liệu iCloud theo khối 1 MB, trung bình **~1,05 MB/ảnh** cho mỗi lần đọc header (ghi chú ở `ExifReader.swift`
  quanh dòng 236). Với thư viện vài chục nghìn ảnh, đó là hàng chục GB lưu lượng và hàng giờ chờ cho phần metadata,
  mà ảnh không ở lại trên máy. Người dùng thấy như "tải về rồi xoá, phí".
- **Tốc độ không tận dụng máy.** Số lượt đọc song song cố định ở
  `IndexPipeline.readConcurrency = 12` (`ShotDex/Domain/Indexing/IndexPipeline.swift:57`), kèm giảm tốc theo nhiệt
  và Low Power Mode, vốn viết cho iPhone. Trên Mac có bản gốc local, giới hạn thật là đĩa và CPU, không phải
  round-trip iCloud.
- **Ảnh mạng làm chậm cả lượt.** Ảnh iCloud chen giữa các batch 200 ảnh, nên ảnh local đứng sau phải chờ ảnh mạng
  stall hết cửa sổ 8 s.

Ảnh hưởng: mọi người dùng ShotDex trên Mac có thư viện lớn. Nặng nhất là lần index đầu tiên.

## Proposed outcome — kết quả mong muốn

- Trong Settings của Mac có option **"Chỉ index ảnh đã tải về Mac"**. Khi bật, index **không dùng mạng**: ảnh chưa
  có bản gốc trên Mac thì bỏ qua, không đọc header từ iCloud, không đọc bản thu nhỏ. Option làm đúng như tên.
- Settings hiện **"N ảnh chưa index trên Mac"** kèm nút **"Index luôn"**. Chỉ nút này mới được dùng mạng cho số ảnh
  đó.
- Ảnh bị bỏ qua vẫn có trong lưới (dòng fast-pass đã có từ PHAsset), chỉ chưa có thông số máy, ống kính, phơi sáng.
  Khi máy khác gửi dữ liệu về, hoặc người dùng tải bản gốc về Mac, ảnh tự có thông số mà không cần làm gì.
- Lần index đầu một thư viện đã tải đủ bản gốc chạy nhanh rõ rệt so với hôm nay. Con số mục tiêu chốt ở `/spec`,
  sau khi đo baseline.

## Affected users and systems — phạm vi ảnh hưởng

- Màn hình: Settings của Mac (option, dòng đếm, nút "Index luôn"); dòng tiến độ index nếu cần phân biệt "đã bỏ qua".
- Thiết bị: **Mac**. iPhone, iPad và Duo không đổi hành vi. Có nên đưa option này lên iPad không là câu hỏi mở.
- Code: `ExifReader` (đường đọc không mạng), `IndexPipeline` (option, thứ tự đọc, độ song song trên Mac),
  `MacDependencies`, Settings của Mac.
- Dữ liệu: có thể cần một trạng thái `exifStatus` mới, hoặc dùng lại `pendingICloud`, cho "bỏ qua vì local-only".
  Đây là cột trong `photo_metadata` do indexer tự ghi, không phải dữ liệu người dùng nhập.

## Constraints — ràng buộc

- Option bật thì **không một byte nào** đi qua mạng vì index. Không đọc bản thu nhỏ để giả là đã index.
- Không làm hỏng đường hiện có trên iPhone/iPad. Bộ ngắt mạng, stall window và giảm tốc theo nhiệt giữ nguyên ở đó.
- Không thêm dependency. Không tự đổi cài đặt Photos của người dùng (không bật "Download Originals" thay họ).
- Ảnh bỏ qua không được tính là lỗi, không tăng `maxReadAttempts`, không bị gắn `noExif`.

## Open questions — đã trả lời (2026-11-02)

1. **Mặc định:** **tắt**. Người dùng tự bật trong Settings của Mac.
2. **Dòng đếm:** ảnh còn **thiếu thông số, bất kể nguồn**. Ảnh đã nhận dữ liệu từ máy khác thì không tính.
3. **Độ song song trên Mac:** Claude tự đo và quyết ở bước code.
4. **iPad:** để sau. Lượt này chỉ làm Mac.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
