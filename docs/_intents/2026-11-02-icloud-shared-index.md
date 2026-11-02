# Intent: Dữ liệu index dùng chung giữa các máy cùng iCloud — mỗi ảnh chỉ đọc một lần

| Trường | Giá trị |
|---|---|
| Tác giả | Hoang Tuan (người dùng) · Claude soạn |
| Ngày | 2026-11-02 |
| Trạng thái | accepted (2026-11-02, người dùng trả lời câu hỏi trong phiên và bảo code luôn) |
| Tiến độ | **gần xong** (2026-11-02) — code xong, iOS + Mac build sạch; spec [BD-03.05](../01-basic-design/BD-03-metadata-indexing-flow/05-shared-index.md); 4/10 AC có test (chỉ mới biên dịch, chưa chạy được vì không có simulator), phần cần thiết bị chưa kiểm |
| Nguồn | tự nghĩ ra (người dùng, 2026-11-02) |
| Spec sinh ra từ đây | [BD-03.05](../01-basic-design/BD-03-metadata-indexing-flow/05-shared-index.md) |

## Bối cảnh

Đi cặp với [2026-11-02-mac-local-only-index](2026-11-02-mac-local-only-index.md). Người dùng có Mac đã tải đủ bản
gốc, cùng iPhone/iPad bật Optimize Storage, tất cả chung một thư viện iCloud Photos. Hôm nay mỗi máy tự index cả
thư viện từ đầu.

Đã chốt trong phiên 2026-11-02:

- **Hai chiều**: máy nào index xong ảnh nào thì các máy khác dùng lại.
- Kênh là **CloudKit**, mỗi ảnh một bản ghi.
- Máy nhận **tin luôn** nếu ngày sửa ảnh khớp, lệch thì tự index lại ảnh đó.

## Problem — vấn đề

- **iPhone index chậm và tốn mạng vì phần lớn bản gốc không ở trên máy.** Thiết bị thật của người dùng bật Optimize
  Storage (memory `grid-thumbnail-optimize-storage`). Mỗi ảnh chỉ có trên iCloud tốn ~1,05 MB và một lần stream
  8 s (`ShotDex/Data/Sources/ExifReader.swift` quanh dòng 236–249). Lần index đầu trên iPhone kéo dài hàng giờ, có
  lúc kẹt hẳn vì mạng (memory `wifi-index-stall-is-app-side`). Trong lúc đó lọc theo máy, ống kính và Statistics
  thiếu dữ liệu.
- **Cùng một ảnh bị đọc lại trên từng máy.** Mac đã đọc xong từ bản gốc local, iPhone vẫn kéo lại từ iCloud, iPad
  kéo thêm lần nữa. Có máy mới hay cài lại app thì làm lại từ đầu.
- **Mac bỏ qua ảnh chưa tải** (intent cặp). Không có máy khác bù thì những ảnh đó không bao giờ có thông số nếu người
  dùng không bấm "Index luôn".

Ảnh hưởng: mọi người dùng có từ hai máy trở lên chung iCloud Photos. Nặng nhất là iPhone có thư viện lớn.

## Proposed outcome — kết quả mong muốn

- Mở ShotDex trên iPhone sau khi Mac đã index xong: trong vài phút, lưới lọc được theo máy, ống kính và phơi sáng,
  Statistics đủ số liệu, mà iPhone không tải header ảnh nào từ iCloud.
- Ảnh iPhone index được, kể cả ảnh Mac đã bỏ qua, sẽ xuất hiện trên Mac kèm thông số mà Mac không phải đọc.
- Ảnh đã sửa sau khi được index (ngày sửa lệch) thì máy nhận tự đọc lại. Dữ liệu cũ không bị dùng sai.
- Không cần thiết lập gì ngoài việc dùng chung Apple Account và iCloud Photos. Có một công tắc để tắt.
- Đăng xuất iCloud hoặc tắt iCloud Photos: app vẫn chạy như hôm nay, tự index trên máy.

## Affected users and systems — phạm vi ảnh hưởng

- Thiết bị: **cả bốn** (iPhone, iPad, Duo, Mac). Mọi máy vừa gửi vừa nhận.
- Code: `IndexPipeline` (bỏ qua ảnh đã có dữ liệu khớp, đẩy kết quả lên), tầng Data (một store CloudKit mới, ánh xạ
  `localIdentifier` sang `cloudIdentifier` theo lô; `HandoffActivity.swift` đã dùng `cloudIdentifierMappings`),
  Settings (công tắc, trạng thái sync).
- Hạ tầng: CloudKit container và entitlement `iCloud` cho app iOS lẫn Mac. Hôm nay
  `ShotDexMac/ShotDexMac.entitlements` chưa có. Đụng tới cấu hình Apple Developer.
- Dữ liệu: bảng mới hoặc cột mới để ghi "dòng này đến từ máy khác hay đọc tại chỗ" và trạng thái đã đẩy/chưa đẩy.
  `photo_metadata` do indexer viết lại cả dòng, nên trạng thái sync có thể phải nằm ở bảng riêng.

## Constraints — ràng buộc

- **Chỉ metadata đọc từ file** (EXIF, ống kính, phơi sáng, kích thước, các trường `MetadataComposer` tạo ra) được
  đồng bộ. Dữ liệu người dùng tự nhập (smart album, mapping máy ảnh tự đặt, đánh dấu Keep/Duplicates, chart, sổ
  Backup) **không** nằm trong intent này.
- Chỉ dùng **CloudKit private database** của chính người dùng. Không có server của ShotDex, không ai khác đọc được.
- Không thêm dependency bên thứ ba (CloudKit là framework hệ thống).
- Dữ liệu từ máy khác không được ghi đè kết quả đọc tại chỗ mới hơn. Khoá là `cloudIdentifier` cộng ngày sửa ảnh.
- Sync không được làm chậm index tại chỗ: mất mạng hay CloudKit lỗi thì index vẫn chạy như hôm nay.
- App chưa release: không cần tương thích ngược định dạng bản ghi (`CLAUDE.md`, mục "ShotDex is unreleased").
- Widget và các extension không đụng tới CloudKit.

## Open questions

Đã trả lời (2026-11-02):

4. **Thứ tự lúc mở app:** **kéo dữ liệu về trước** (chờ tối đa ~30 s), rồi mới tự index phần còn thiếu. Dữ liệu tới
   sau vẫn được dùng.
5. **Phạm vi v1:** EXIF và metadata **cộng địa điểm** (kết quả tra tên địa điểm). Nhận diện chủ thể và hash ảnh để
   sau.
6. **CloudKit:** chưa bật. Container `iCloud.com.hoangtuan.shotdex`. Người dùng bật iCloud/CloudKit cho bundle id
   trên developer.apple.com, hoặc để Xcode tự quản lý signing.

7. **Mac index cho mọi máy** (người dùng thêm giữa phiên): công tắc nằm trên Mac và áp cho mọi máy qua iCloud.
   iPhone/iPad khi đó chỉ đọc ảnh có bản gốc trên máy, phần còn lại chờ Mac. Mỗi máy có nút riêng để vẫn tự
   index.

Còn treo, chỉ đo được trên máy thật (simulator không có iCloud Photos):

1. `cloudIdentifier` có ổn định và lấy được theo lô lớn không, gồm cả ảnh Shared Library và ảnh chưa upload xong.
2. `modificationDate` của cùng một ảnh có khớp giữa Mac và iPhone không.
3. Quota và throttle của CloudKit với 50–100 nghìn bản ghi.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
