# FS-02.01 — Pager và tải ảnh

`FS-02.01` · `Features/Library/PhotoDetailScreen.swift` · `ZoomableImageView` · cập nhật 2026-09-22

**Một câu:** lật trang dựng lười, và thang chất lượng ảnh đi từ bản local rẻ nhất lên bản gốc — chỉ khi
người dùng chủ động phóng.

## 1. Quy tắc

- Pager là của UIKit, không phải pager của SwiftUI.
- **Local trước, mạng sau.** Không trang nào tải iCloud nếu người dùng chưa chủ động phóng.
- **Bản tốt hơn được thay âm thầm; bản kém không bao giờ ghi đè ảnh đã nét.**
- Rời trang là **huỷ** mọi yêu cầu của trang đó.

## 2. Pager

- Trang được **dựng lười**, hỏi tới đâu dựng tới đó. Pager của SwiftUI dựng mọi trang ngay nên trước đây
  phải giới hạn cửa sổ ±2 và dựng lại giữa lúc vuốt.
- Nguồn ảnh cho viewer là một giao thức theo **vị trí**: số ảnh, id theo vị trí, vị trí theo id, metadata và
  ảnh theo id. Nhờ vậy pager **không ôm cả mảng metadata**: Library lấy metadata đầy đủ theo id khi cần,
  còn album và On This Day trả từ mảng có sẵn.
- Lật xong thì ghi vị trí mới về và nạp thêm nếu sắp hết trang.
- **Trang phải tự tràn qua vùng an toàn**: nó nằm trong một vỏ host lồng bên trong pager, và lệnh tràn ở lớp
  ngoài **không truyền qua ranh giới đó** — triệu chứng là phóng ảnh xong vẫn còn hai dải đen cố định.

## 3. Phóng

- Mở ở **vừa khung, mức nhỏ nhất là 1×**; không tự phóng, không tự cắt.
- Ở 1× thì kéo ngang thuộc về pager; vượt 1,01 lần mới bật kéo bên trong ảnh.
- Phóng thì tắt vuốt-xuống-để-đóng và ẩn tạm chrome; đổi trang thì đặt lại mức phóng.
- **Phóng là lúc nâng lên bản gốc** (cho phép mạng): tín hiệu bắt đầu pinch được bắt ngay đầu cử chỉ, còn
  ngưỡng 1,01 lần là đường dự phòng cho chạm đôi; một cờ chống xin lặp. Yêu cầu bản cỡ màn **bị huỷ trước**
  để không tranh băng thông và để không có kết quả nhỏ tới muộn ghi đè bản gốc.

## 4. Thang chất lượng

thumbnail → bản local → bản local gốc → bản cỡ màn → **bản gốc**

| Bước | Làm gì |
|---|---|
| Mọi trang dựng trước | một thumbnail nhanh + một bản local tốt nhất, **không mạng** |
| Trang đang hiện | thêm bản hiện tại đọc từ file local rồi thu nhỏ; ảnh gốc chỉ ở iCloud thì đường này rỗng và **không tải** |
| Người dùng phóng | bản gốc qua mạng, có vòng tiến độ |

- **Offline vẫn giống Photos**: bản local đầu tiên được vẽ ngay dù chỉ là thumbnail mờ, thay vì giữ màn đen.
  Bản cuối vẫn phải đạt ≥ 90% kích thước mục tiêu; bản thiếu pixel thì xin lại ở mức gấp đôi.
- Vòng quay chỉ xuất hiện **sau 350ms** và chỉ khi hệ thống không trả được bất kỳ bản local nào.
- **Lưới chỉ hâm nóng đúng một ô — ô đang bị chạm**: xin bản cỡ màn cho ảnh dưới ngón tay, giữ qua lúc nhả,
  ô khác bị chạm thì thay. Bản cũ hâm 18 ô đang hiện: 18 lần giải mã ảnh full-screen (~12MB mỗi ảnh) xếp
  cùng hàng đợi với thumbnail nên **lưới mờ vài giây sau mỗi lần cuộn**.
- Rời trang thì huỷ cả bản xem trước, bản local và bản gốc.

## 5. iCloud

- Trạng thái tải được đưa lên màn kèm **vị trí trang**, và lưu theo vị trí rồi dọn quanh trang hiện tại để
  tiến độ không nhảy sang trang khác.
- **Phát hiện đứng im**: tải báo 0% trọn **15 giây** — mọi nhịp tiến độ, mọi lần hoàn tất, và mọi lần đổi
  trang đều tháo đồng hồ này → vòng tiến độ đổi thành biểu tượng iCloud cam + dòng *"iCloud isn't responding
  — check iCloud Photos in Settings or the Photos app."*
- **Không tự huỷ, không xin lại**: yêu cầu đang treo sẽ tự chạy tiếp khi dịch vụ sống lại. Ảnh giữ chỗ vẫn
  hiển thị bình thường.
- Lý do tồn tại: iCloud của máy có thể **ngừng phục vụ toàn cục**
  ([BD-03.03](../../01-basic-design/BD-03-metadata-indexing-flow/03-network-thermal-and-gate.md)) — một vòng
  quay vô hạn làm người dùng tưởng app treo trong khi lỗi nằm ở tầng thiết bị.
- **Viewer tạm dừng index**: mở viewer là giữ một cổng, đóng là nhả, và mỗi lần đổi trang hay mỗi nhịp tải
  đều gia hạn.

## 6. Metadata điền dần

Mở một trang là xin index **đúng một ảnh đó**:

- Đọc EXIF bằng cách stream vài KB phần đầu file — **đường riêng, không phụ thuộc việc tải ảnh đầy đủ**.
- Ghi **một** row, không đụng con trỏ chạy tiếp của lượt index theo mẻ; bỏ qua ảnh đã đọc xong; đọc không
  được thì vẫn giữ trạng thái chờ iCloud.
- Bảng thông tin cập nhật ngay.

## 7. Đóng viewer không được làm Library nạp lại

- Tác vụ khởi tạo của màn Library có thể chạy lại khi lớp phủ đóng → lần nạp đầu đi qua một hàm **có chốt**
  sống theo model.
- Bộ quan sát thay đổi phát **hai** tín hiệu (chung một lần gộp mỗi giây): "có thay đổi bất kỳ" và "có ảnh
  thêm/bớt/đổi chỗ". Lưới và index chỉ nghe tín hiệu thứ hai, nên thông báo do hệ thống cache lại một bản
  ảnh **không** kéo theo một lượt nạp lại và một lượt index.
- Mốc so sánh để phân loại phải được gieo **ngay lúc bắt đầu quan sát**, không chỉ sau khi xin quyền: từ lần
  mở app thứ hai, bộ quan sát bật lên khi chưa có mốc nào — thiếu mốc thì **mọi** thay đổi bị coi là thay
  đổi cấu trúc và bộ lọc thành vô dụng.

## 8. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
