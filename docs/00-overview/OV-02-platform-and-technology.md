# OV-02 — Nền tảng và công nghệ

`OV-02` · `ShotDex.xcodeproj` · cập nhật 2026-09-24

**Một câu:** framework nào dùng cho việc gì, và ba quyết định nền không được đảo.

## 1. Quy tắc

- **Tối thiểu iOS 17** — cần bộ biểu đồ, cơ chế quan sát trạng thái mới, và bảng trượt nhiều nấc.
- **Ba thư viện bên thứ ba**, qua trình quản lý gói của Swift: **GRDB** (database), **SMBClient** và
  **Citadel** (upload lên file server, [FS-15](../02-functional-spec/FS-15-server-upload/README.md)). Còn lại là
  framework hệ thống. Thêm một thư viện là quyết định có tên, không phải tiện tay.
- Thư viện mới phải có giấy phép **MIT/Apache/BSD** — bọc libsmb2/libssh (LGPL/GPL) bị loại — và chỉ app chính
  link; kit và extension không thấy chúng.
- **swift-collections ghim ở 1.3**: bản 1.7 (SwiftNIO kéo vào) gọi một hàm runtime mà iOS 26.5 chưa có — app
  chết ngay lúc mở. Nâng bản thì chạy thử trên iOS 17/18/26 trước.
- **Kích thước màn và cửa sổ luôn hỏi qua một lớp riêng của app**, không hỏi thẳng "màn hình chính" của hệ
  thống.
- **Không đọc lại metadata cả thư viện mỗi lần mở app** — xem
  [BD-03](../01-basic-design/BD-03-metadata-indexing-flow/README.md).

## 2. Framework theo việc

| Việc | Dùng |
|---|---|
| Giao diện | SwiftUI; dùng UIKit ở chỗ cần hiệu năng và phân trang — lưới ảnh, khung phóng, và bộ lật trang của viewer |
| Thư viện ảnh | PhotoKit: xin quyền, lấy ảnh, cache thumbnail, theo dõi thay đổi |
| Đọc EXIF | ImageIO — đọc thuộc tính, **không giải mã ảnh** |
| Render editor | Core Image; PencilKit cho phần vẽ tay ([FS-05](../02-functional-spec/FS-05-markup/README.md)) |
| Database | GRDB trên SQLite — tổng hợp bằng SQL cho phần lọc và thống kê |
| Biểu đồ | Swift Charts (cột, phân bố, vành khuyên) |
| Trạng thái và tiêm phụ thuộc | cơ chế quan sát của Swift + môi trường của SwiftUI |
| Phóng ảnh | bọc một scroll view của UIKit |
| Chia sẻ | bảng chia sẻ của hệ thống |
| Bảng trượt · menu | bảng trượt nhiều nấc và menu thả xuống của hệ thống |
| Cài đặt | kho cài đặt của app |
| Thông báo | thông báo cục bộ theo lịch, **không push**, không cần quyền máy chủ; đặt bộ nhận ngay lúc app khởi tạo vì app **không có lớp delegate** riêng |
| Ngôn ngữ | bộ chuỗi của hệ thống, có vùng tiếng Việt |
| Đồng thời | cơ chế bất đồng bộ của Swift — async/await, nhóm tác vụ, actor |
| Font · haptic | font hệ thống · phản hồi rung của hệ thống |

## 3. Đánh đổi đã chọn

| Chọn | Thay vì | Vì |
|---|---|---|
| GRDB | SwiftData | thống kê cần gom nhóm, chia dải và phân vị — làm trong truy vấn, không làm trong Swift |
| Lớp đo màn riêng | hỏi thẳng "màn hình chính" | máy hai màn làm câu hỏi đó thành câu hỏi sai; và app cần **bề rộng cửa sổ** (chia đôi màn, gập máy) chứ không phải bề rộng màn — đo theo màn thì mọi lượt xin ảnh "cỡ màn hình" đều lấy dư |
| ImageIO | giải mã ảnh rồi đọc | đọc EXIF không cần một pixel nào |

Lớp đo màn lấy cửa sổ đang hoạt động rồi cấp: độ sáng màn (cho phần giữ màn sáng), tỉ lệ điểm ảnh, kích
thước **cửa sổ**, và kích thước pixel dùng khi xin ảnh. Đường hỏi "màn hình chính" **chỉ còn đúng một chỗ**
bên trong lớp đó, cho trường hợp app chưa có cửa sổ nào.

## 4. Ràng buộc còn treo

- Việc dịch mới phủ chuỗi của lời nhắc và mục Notifications; phần còn lại vẫn là tiếng Anh
  ([NF-06](../04-non-functional-design/NF-06-accessibility-and-localization.md)).
