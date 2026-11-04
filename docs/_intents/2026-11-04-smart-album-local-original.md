# Intent: Smart album "bản gốc đã có trên máy" — biết ảnh nào đã tải đủ, ảnh nào chỉ là bản xem trước

| Trường | Giá trị |
|---|---|
| Tác giả | Hoang Tuan (người dùng) · Claude soạn |
| Ngày | 2026-11-04 |
| Trạng thái | accepted (2026-11-04, người dùng chốt các câu hỏi qua lựa chọn trong phiên) |
| Tiến độ | **đang làm** (2026-11-04) — task 12/13, 8/14 AC xanh; loop [FS0610_LOOP](../_plans/FS0610_LOOP.md) |
| Nguồn | phản hồi người dùng (2026-11-04, trong phiên kiểm luồng xoá của smart album "có trên NAS") |
| Spec sinh ra từ đây | [FS-06.10](../02-functional-spec/FS-06-collections/10-original-on-device.md) |

Intent anh em: [2026-11-04-smart-album-shared-library](2026-11-04-smart-album-shared-library.md) (Shared Library hay
Personal). Hai việc tách ra vì dữ liệu khác nhau, và việc kia có thể không làm được.

## Problem — vấn đề

Máy bật Optimize Storage thì phần lớn bản gốc nằm trên iCloud, trên máy chỉ có bản xem trước. Hôm nay người chụp
**không gom được những ảnh đã có bản gốc đầy đủ trên máy** (hoặc ngược lại, những ảnh chưa có), ở bất kỳ thiết bị nào
(iPhone, iPad, Mac).

- Smart album không có điều kiện nào về chuyện này. Các trường có ở `ShotDex/Core/Models/SmartAlbumQuery.swift:33-70`.
  Điều kiện gần nhất là **Source** (có hoặc không có trên NAS, `SmartAlbumSQLBuilder.swift:204-226`).
- Bộ lọc Library cũng không có (`ShotDex/Core/Models/FilterCriteria.swift:112-160`; intent
  [keep-offline](2026-10-19-keep-offline.md) dòng 33-36 đã ghi là còn thiếu).
- App chỉ kiểm tra bản gốc lúc mở từng ảnh, rồi không lưu lại kết quả (`ShotDex/Data/Sources/OriginalFetcher.swift:73-95`,
  `isNetworkAccessAllowed = false`). Database không có cột nào cho việc này (`photo_metadata`, `photo_copies`).
- **Keep on This iPhone** (`kept_items`, `AppDatabase+Kept.swift:14-25`) là danh sách ảnh người dùng *xin* giữ trên máy.
  Nó không cho biết ảnh nào *đang* có bản gốc trên máy. Photos tự tải bản gốc về khi xem hoặc sửa, và tự xoá đi khi máy
  hết chỗ.
- SDK iOS 27.1 không có thuộc tính công khai nào cho biết bản gốc đang ở trên máy (đã tìm trong `Photos.framework/Headers`
  ngày 2026-11-04). Cách duy nhất biết chắc là thử đọc bản gốc mà không cho dùng mạng, từng ảnh một, như `OriginalFetcher`
  đang làm.

Người dùng gặp việc này khi làm kế hoạch giải phóng iCloud ([smart-album-on-nas](2026-10-24-smart-album-on-nas.md)):
họ cần biết ảnh nào đã có đủ trên máy, chẳng hạn trước khi đi đến chỗ không có mạng, hoặc trước khi chạy một việc cần
bản gốc. Mức độ: thấp đến vừa. Không mất dữ liệu, nhưng hôm nay muốn biết thì phải mở từng ảnh.

## Proposed outcome — kết quả mong muốn

1. Smart album editor có điều kiện mới, tạm gọi **Original on This Device**, với toán tử *is / is not*. Có trên iPhone,
   iPad và Mac.
2. Kết hợp được với các điều kiện khác, nhất là Source "có trên NAS". Ví dụ: "có trên NAS **và** bản gốc chưa có trên
   máy", hay "bản gốc có trên máy **và** chưa có trên NAS".
3. Kết quả đủ mới để tin được. Người dùng vừa tải về hay Photos vừa xoá bản gốc thì album đổi theo trong thời gian hợp lý,
   và màn hình nói rõ trạng thái kiểm tra đang tới đâu, như dòng tiến độ của On Server (FS-19.07 §7).
4. Có thể thêm: cùng điều kiện đó trong bộ lọc Library (Open question 2).

## Affected users and systems — phạm vi ảnh hưởng

- Màn hình: Smart Album editor, màn smart album (iOS, iPad, Duo, Mac). Bộ lọc Library nếu chốt có.
- Thiết bị: iPhone · iPad · Duo trong · Duo ngoài · Mac. Trên Mac có thể chọn "Download Originals to this Mac". Khi đó
  điều kiện luôn đúng và có thể ẩn đi (Open question 4).
- Tầng code: Data (một chỗ lưu trạng thái bản gốc cho từng ảnh, và một lượt quét để làm mới nó), Database
  (`SmartAlbumSQLBuilder`, có thể cả `FilterCriteria`), Core/Models (`RuleField`), Features (rule editor).
- Dữ liệu đã lưu: cần một **bảng riêng**. Lượt index ghi đè cả dòng `photo_metadata`, và đây là kết quả của một lượt
  quét đắt tiền ([BD-02](../01-basic-design/BD-02-database-design.md)). Sửa 2026-11-04 khi viết spec (bản đầu ghi nhầm
  là được nằm trong `photo_metadata`).

## Constraints — ràng buộc

- Không bao giờ tải bản gốc chỉ để kiểm tra. Lượt kiểm tra chạy với `isNetworkAccessAllowed = false`.
- Thư viện 55k ảnh: lượt quét không được làm nghẽn lưới hay index. Không mở từng ảnh trên main thread, và quét được
  lại từ giữa chừng khi bị cắt (như IndexPipeline).
- Mỗi thiết bị một trạng thái riêng. Không chia sẻ qua CloudKit shared index
  ([icloud-shared-index](2026-11-02-icloud-shared-index.md)), vì "trên máy" là chuyện riêng của từng máy.
- Không thêm dependency. Không dùng key KVC chưa công khai của `PHAssetResource` (`locallyAvailable`) nếu App Review có
  thể từ chối. Nếu dùng thì phải hỏi người dùng trước (Open question 1).
- Giữ cả hai nhánh iOS 26 và trước 26 ở rule editor.

## Open questions — câu hỏi còn treo

**Đã trả lời (người dùng, 2026-11-04):** Q1 spike đo cả hai cách rồi chọn · Q2 có, bộ lọc Library dùng chung dữ liệu ·
Q3, Q4, Q5 nhận mặc định · Q6 để **dùng khi offline** và **giải phóng máy**.

1. **Đo bằng gì?** Thử đọc bản gốc offline từng ảnh thì chắc chắn, nhưng 55k ảnh tốn bao lâu? Hay dùng key KVC
   `locallyAvailable` của `PHAssetResource`: nhanh, nhưng là API chưa công khai.
   Mặc định đề xuất: một spike đo cả hai trên thư viện thật, rồi người dùng chọn. → spike, rồi người dùng.
2. **Bộ lọc Library cũng có điều kiện này?** Mặc định đề xuất: có, dùng chung một cột. → người dùng.
3. **Làm mới lúc nào?** Chỉ khi mở album hay chạy nền theo PhotoKit change? Photos tự xoá bản gốc mà không gửi
   change notification rõ ràng. Mặc định đề xuất: quét lại khi app về trước mặt và khi mở album có điều kiện này, có
   dòng tiến độ. → spike.
4. **Mac đã bật Download Originals thì sao?** Mặc định đề xuất: vẫn có điều kiện. Khi kiểm tra thấy toàn bộ đã có trên
   máy thì lưới hiện bình thường, không ẩn điều kiện. → người dùng.
5. **Video và Live Photo:** có tính phần video của Live Photo không? Mặc định đề xuất: "có trên máy" nghĩa là mọi
   resource gốc đều có, như luật "mọi file gốc" của On Server. → người dùng.
6. **Người dùng cần điều kiện này để làm gì tiếp?** Đi đến chỗ không có mạng, chạy hash cho On Server mà không phải tải,
   hay giải phóng dung lượng máy? Câu trả lời quyết định tên và chỗ đặt điều kiện. → người dùng.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
