# FS-06.10 — Điều kiện "bản gốc trên máy"

`FS-06.10` · tier A · `Core/Models/SmartAlbumQuery.swift` · `Data/Database/SmartAlbumSQLBuilder.swift` ·
`Core/Models/FilterCriteria.swift` · `Data/Sources/OriginalFetcher.swift` · cập nhật 2026-11-04

**Một câu:** smart album và bộ lọc Library lọc được ảnh **đã có bản gốc đầy đủ trên chính máy này**, tách khỏi ảnh
chỉ có bản xem trước của Optimize Storage. Chạy trên iPhone, iPad, Duo và Mac.

Nguồn: [intent 2026-11-04-smart-album-local-original](../../_intents/2026-11-04-smart-album-local-original.md).
Liền kề: [08 Smart Album](08-smart-albums.md) · [FS-01.05](../FS-01-library/05-filtering-and-sorting.md) ·
On Server [FS-19.07](../FS-19-photo-sources/07-on-server-check.md) · bản gốc iCloud [FS-02.06](../FS-02-photo-detail/06-icloud-originals.md).

## 1. Người dùng cần gì

Máy bật Optimize Storage thì chỉ một phần bản gốc nằm trên máy. Người dùng cần biết hai điều. Trước khi đi tới chỗ
không có mạng: ảnh nào xem và xuất được ở chất lượng đầy đủ. Khi máy đầy: ảnh nào đang thật sự chiếm chỗ trên máy.

## 2. Phạm vi

**Có:**
- Trường mới trong bộ dựng điều kiện (smart album, Advanced Search, điều kiện thẻ Statistics, vì ba nơi dùng chung).
- Một mục trong menu Filter nhanh của Library và của album ([FS-06.09](09-album-filter-menu.md)), dùng cùng dữ liệu.
- Một lượt kiểm tra nền, ghi trạng thái từng ảnh, có dòng tiến độ.

**Cố ý không có:**
- Nút "xoá bản gốc khỏi máy, giữ trên iCloud". PhotoKit không cho app gỡ bản gốc. Chỉ hệ thống làm việc đó.
  Muốn lấy chỗ thì phải xoá ảnh. Xoá ảnh là xoá trên mọi thiết bị (§8).
- Tự tải bản gốc về. Lọc ra ảnh *không* có trên máy rồi dùng **Keep on This iPhone** ([intent keep-offline](../../_intents/2026-10-19-keep-offline.md)) để tải.
- Chia sẻ trạng thái này qua shared index CloudKit. "Trên máy" là chuyện riêng của từng máy.
- Ảnh từ thư mục và server (FS-19). File của chúng đã có cờ "chỉ trên cloud" riêng. Trường này chỉ xét bản Photos.

## 3. Trạng thái

| Trạng thái của một ảnh | Nghĩa | Vào *is* | Vào *is not* |
|---|---|---|---|
| có trên máy | mọi resource gốc đều đọc được khi tắt mạng (§4) | ✅ | — |
| không có | ít nhất một resource gốc phải tải từ iCloud | — | ✅ |
| chưa kiểm | chưa kiểm lần nào, hoặc đã đánh dấu kiểm lại (§4) | — | — |

Ảnh chưa kiểm không vào cả hai, cùng luật với On Server ([FS-19.07 §8](../FS-19-photo-sources/07-on-server-check.md)).
Không đoán thay cho ảnh chưa kiểm.

| Trạng thái màn | Hiển thị |
|---|---|
| đang kiểm | dòng tiến độ dưới thanh điều kiện: *Checking originals · 12,400 of 55,000* |
| đã kiểm xong | *Originals checked 3 min ago* |
| quyền `.limited` | chỉ kiểm ảnh được chia sẻ cho app; dòng tiến độ ghi đúng tổng số đó |
| Mac bật Download Originals | vẫn có trường này. Sau lượt kiểm, mọi ảnh thường ra *có trên máy* (không ẩn trường) |

## 4. Hành vi

- **Có trên máy** nghĩa là có **mọi** resource gốc: ảnh, phần video của Live Photo, video. Nếu ảnh đã sửa thì cả bản
  render đầy đủ. Vì: xem hay xuất khi không có mạng cần đủ những phần đó.
- Lượt kiểm tra **không bao giờ dùng mạng** và không tải gì về. Nó chạy ngoài main thread, kiểm theo lô, nhường khi
  người dùng đang thao tác, dừng theo nhiệt độ máy, và chạy tiếp được từ chỗ dừng ([NF-01 §1.5](../../04-non-functional-design/NF-01-performance.md)).
- **Lúc chạy:** khi app vào trước mặt, và khi mở một album hay bộ lọc có dùng trường này. Ảnh nào PhotoKit báo
  đổi thì về lại *chưa kiểm*.
- Photos tự gỡ bản gốc khi máy hết chỗ, mà **không** báo thay đổi. Kết quả vì vậy có thể cũ, nên màn luôn ghi
  *checked … ago*.
  - **Quét lại toàn bộ** chỉ khi có album hoặc bộ lọc dùng trường này đang mở, và lần quét trước đã quá 24 giờ
    (người dùng chốt 2026-11-04). Vì: [NF-01 §1.3](../../04-non-functional-design/NF-01-performance.md) cấm quét lại
    cả thư viện mỗi lần mở app.
- **Cách đo:** chọn sau spike AC-1. Có hai cách:
  - (a) Thử đọc từng resource gốc với mạng bị tắt.
  - (b) Đọc cờ chưa công khai "locally available" của resource.
  - Mặc định là (a). Chỉ dùng (b) khi spike đo được (a) chậm quá 2 giờ cho 55k ảnh. Vì: (b) có rủi ro App Review
    (người dùng chốt 2026-11-04).
- **Tên:** trường **Original**, giá trị *On This iPhone* / *iCloud Only*. iPad và Mac đổi theo tên máy. Chip trên
  thanh điều kiện ghi *Original on This iPhone*. Vì: màn **On This iPhone** đã là danh sách Keep, nên tên trường phải
  khác.
- Trong menu Filter nhanh: một mục bật/tắt **Original on This iPhone**, nằm cạnh Favorites. Nó là bộ lọc đơn giản
  nên loại trừ với truy vấn nâng cao ([FS-01.05 §1](../FS-01-library/05-filtering-and-sorting.md)).

## 5. Dữ liệu

| | |
|---|---|
| Đọc từ | PhotoKit (resource của asset, mạng tắt) |
| Ghi vào | **bảng riêng**: mỗi ảnh một dòng gồm trạng thái và thời điểm kiểm; cộng một con trỏ lượt kiểm để chạy tiếp |
| Vì sao không ở `photo_metadata` | lượt index ghi đè cả dòng, và đây là kết quả của một lượt quét đắt tiền ([BD-02](../../01-basic-design/BD-02-database-design.md)) |
| Người dùng tự nhập? | không. Xoá bảng thì chỉ mất công kiểm lại |

## 6. Ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Hiệu năng | không query theo từng cell; lọc bằng SQL trên bảng trạng thái; lượt kiểm không làm lưới tụt dưới 60 fps khi đang cuộn |
| Bộ nhớ | không giải mã ảnh. Chỉ hỏi PhotoKit resource có trên máy hay không. Mỗi lô ≤ 200 ảnh, như batch index |
| Thiết bị | iPhone 402×874 · iPad 1376×1032 · Duo trong 951×669 · Duo ngoài 466×678 · Mac |
| iOS 26 vs trước | rule editor và menu Filter làm được cùng một việc trên 26.5 và 18.6 |
| Truy cập | dòng tiến độ có trait updates-frequently; chip đọc *Original on This iPhone* |
| Design | trước khi code: thêm trường vào `PH_/IP_/DI_/DC_SmartAlbumEditor` và `MAC_SmartAlbumEditor`, thêm mục vào menu Filter (`PH_LibraryMore`, `MAC_FilterPopover`), thêm dòng tiến độ vào `PH_SmartAlbum` và `MAC_SmartAlbum` |

## 7. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | (spike) máy thật, 55k ảnh, Optimize Storage bật | chạy lượt kiểm theo cách (a) rồi (b) | có số: thời gian, CPU, bộ nhớ đỉnh của mỗi cách; hai cách khớp nhau trên ≥ 99,9% ảnh; ghi vào `docs/_intents` | ⚠️ chưa có — spike |
| AC-2 | 100 ảnh: 60 có đủ bản gốc, 30 chỉ bản xem trước, 10 chưa kiểm | album *Original is On This iPhone* | *Matches 60 photos*; *is not* ra 30; 10 ảnh chưa kiểm không vào bên nào | ⚠️ chưa có — `OriginalPresenceRuleTests` |
| AC-3 | Live Photo có ảnh trên máy, phần video chỉ trên iCloud | kiểm ảnh đó | trạng thái *không có* | ⚠️ chưa có — test với resource giả |
| AC-4 | ảnh đã sửa, bản gốc có trên máy, bản render chỉ trên iCloud | kiểm ảnh đó | trạng thái *không có* | ⚠️ chưa có |
| AC-5 | máy tắt mạng, 1.000 ảnh chưa kiểm | lượt kiểm chạy hết | không có request mạng nào; 1.000 dòng trạng thái được ghi | ⚠️ chưa có — test có đếm request |
| AC-6 | lượt kiểm tới 30.000 / 55.000 | app bị đóng hẳn, rồi mở lại | lượt kiểm chạy tiếp từ 30.000, không kiểm lại từ 0 | ⚠️ chưa có |
| AC-7 | 55k ảnh đã kiểm | index lại toàn bộ thư viện | trạng thái của mọi ảnh vẫn còn (không về *chưa kiểm*) | ⚠️ chưa có — test có upsert metadata |
| AC-8 | ảnh A *có trên máy*; PhotoKit báo A đổi | lần mở album kế | A thành *chưa kiểm* rồi được kiểm lại; dòng tiến độ đếm A | ⚠️ chưa có |
| AC-9 | quyền `.limited`, cho app 40 ảnh | mở album có trường này | dòng tiến độ ghi *of 40*; không có ảnh ngoài 40 ảnh đó | ⚠️ chưa có |
| AC-10 | album *Source is NAS Home* VÀ *Original is iCloud Only* | mở album | chỉ ra ảnh có trên NAS mà bản gốc không có trên máy; chip ghi đủ hai điều kiện | ⚠️ chưa có — `SmartAlbumSQLBuilder` test |
| AC-11 | Library 100 ảnh, 60 có trên máy, iOS 26.5 và 18.6 | menu Filter › bật *Original on This iPhone* | lưới còn 60; thanh chip có chip tương ứng; đang có truy vấn nâng cao thì truy vấn đó bị xoá | ⚠️ chưa có — `Tools/ui-drive` + ảnh cả hai nhánh |
| AC-12 | Mac bật Download Originals, 200 ảnh | lượt kiểm xong | *is On This Mac* ra 200; trường vẫn có trong menu trường | ⚠️ chưa có — Mac |
| AC-13 | mọi trường của bộ dựng | mở menu phép của *Original* | chỉ có *is* và *is not*; không có *is missing* | ⚠️ chưa có — test lặp qua mọi trường (FS-06.08 AC-6) |
| AC-14 | iPhone, Duo trong, iPad, Mac | mở sheet editor và màn album có dòng tiến độ | khớp board từng máy, lệch ≤ 2pt | ⚠️ chưa có — `design-parity` |

**Chưa chứng minh được:** AC-1…AC-14 (spec mới, chưa có code).

## 8. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Người dùng lọc *On This iPhone* để lấy chỗ, rồi xoá, tưởng chỉ xoá trên máy | hộp xoá giữ như hôm nay: hộp hệ thống, cộng câu *Recently Deleted* / iCloud khi ảnh có trên NAS ([FS-19.07 §9](../FS-19-photo-sources/07-on-server-check.md)). Không thêm hộp (người dùng chốt 2026-11-04) |
| Photos gỡ bản gốc mà không báo thay đổi, nên kết quả cũ | luôn ghi *checked … ago*; quét lại theo luật §4 |
| Cờ chưa công khai bị đổi hoặc bị App Review từ chối | chỉ dùng sau khi người dùng chốt ở §4; (a) luôn là đường dự phòng |
