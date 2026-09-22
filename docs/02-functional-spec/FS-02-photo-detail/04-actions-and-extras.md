# FS-02.04 — Hành động và phụ trợ

`FS-02.04` · `Features/Library/SlideshowScreen.swift` · `LivePhotoPlayerView` · `PanoramaScreen`
· `VideoTrimScreen` · cập nhật 2026-09-22

**Một câu:** mọi thứ làm được với tấm ảnh đang xem — menu ⋯, và bốn màn phụ.

## 1. Quy tắc

- **App không tự dựng hộp thoại xác nhận xoá** — hệ thống hiện hộp thoại đó, và app bên thứ ba không ẩn hay
  dời được nó.
- Cùng một hành động phải **đọc giống nhau ở mọi nơi** (Resize ở viewer = Resize ở chế độ chọn).
- Gesture nào tranh nhau thì **tách màn**, đừng chồng chế độ.

## 2. Menu ⋯

| Nhóm | Mục |
|---|---|
| 1 | Add to Album · Duplicate · Copy · **Select Text or Subject** |
| 2 | Adjust Date & Time · Adjust Location · **Show on Map** (chỉ khi có toạ độ) |
| 3 | Hide |

- Video ẩn Copy và Select Text; ảnh Live có thêm **Save as Video**; ảnh panorama có **View Panorama**; video
  có **Trim**.
- **Show in All Photos** hiện khi ảnh **không** mở từ Library (album, chuyến đi, memory, kết quả tìm): đóng
  viewer, về tab Library, mở lại đúng ảnh đó giữa toàn thư viện — đi chung đường với Handoff.
- **Resize** (trước gọi là Compress) đã rời thanh đáy vào menu này; màn đích không đổi.
- **Hide hỏi trước** — từ iOS 16 hệ thống lấy album ảnh ẩn khỏi mọi app trừ Photos, nên app ghi được cờ mà
  không bao giờ thấy lại ảnh để bỏ ẩn ([BD-04](../../01-basic-design/BD-04-design-language.md)).

## 3. Xoá, chia sẻ, favorite

- **Delete** gọi đường xoá của hệ thống → hộp thoại xác nhận. Huỷ thì không đổi gì. Xoá xong danh sách bị
  cắt nên pager **dựng lại trang hiện tại** ở cùng vị trí đã kẹp — hiện ảnh kế tiếp kiểu Photos; hết ảnh thì
  đóng viewer.
- **Share**: ảnh chia sẻ dữ liệu ảnh, video chia sẻ file. File chưa tải về máy → cảnh báo "Unable to Share".
  Luật gỡ vị trí: [NF-03](../../04-non-functional-design/NF-03-privacy-and-security.md).
- **Favorite** ghi thẳng lên thư viện ảnh — hệ thống là nguồn thật.

## 4. Giữ tay để xem bản gốc

Ảnh **đã chỉnh**: giữ tay lên ảnh hiện lại **bản gốc** + nhãn "Original" ở **đáy giữa**; nhả tay là về bản
đã chỉnh.

- Cử chỉ giữ phải là **của UIKit, không phải của SwiftUI** — nội dung nằm trong một scroll view nên cử chỉ
  SwiftUI phủ lên **không bao giờ bắn**. Nó chạy **song song** với pinch và kéo, nếu không thì ảnh đã chỉnh
  mất khả năng phóng.
- Nhãn đặt ở đáy giữa chứ không trên đỉnh: trang ảnh vẽ tràn viền còn đỉnh màn là của nút đóng và bảng thông
  tin — đặt trên đó là nằm **sau lưng** chúng.
- Ảnh gốc phải lấy bằng đường **đọc dữ liệu file gốc**; đường "xin ảnh bản gốc" của hệ thống trả về **đúng
  bản đã chỉnh**. Giải mã thẳng xuống cỡ màn hình — giải mã cả một file 48MP cho một phép so sánh giữ một
  giây là phí bộ nhớ.
- Phát hiện ảnh đã chỉnh bằng cách xem nó có phần dữ liệu chỉnh sửa hay không (hệ thống không có cờ nào).
  Chỉ chạy cho **một** ảnh đang xem, ngoài luồng chính — cũng là lý do lưới **không** có nhãn "đã chỉnh".
- **Live Text bật thì tắt cử chỉ này** — giữ tay lúc đó là thao tác nhấc chủ thể ra khỏi nền.

## 5. Live Text và tách chủ thể

Một lần phân tích cho **cả hai**: chọn/copy/dịch chữ, và giữ tay lên chủ thể để nhấc ra khỏi nền.

- **Mặc định tắt**, bật từ menu ⋯, tự tắt khi lật trang. Hai lý do không bật sẵn: phân tích phải giải mã và
  quét ảnh; và khi bật thì nó tranh cử chỉ với việc lật trang lẫn việc phóng.
- Cờ đi theo **trang đang hiển thị**, nên trang nạp trước không chạy phân tích. Máy không hỗ trợ thì không
  cài gì.

## 6. Live Photo

- Nhãn **LIVE** ở **góc dưới-trái** vùng ảnh (không phải trên-trái như Photos — viewer đã chiếm góc đó);
  chạm để phát một lượt.
- Lớp phát Live Photo **phủ lên** ảnh tĩnh chứ không thay thế: nó không có cơ chế phóng riêng, và cử chỉ
  giữ-để-phát của nó tranh với việc lật trang. Lớp phủ sống đúng một lượt phát rồi tự gỡ.
- Phần chuyển động **chỉ tải khi bấm**, vì pager nạp trước cả trang bên cạnh.
- **Save as Video** ghi đoạn chuyển động ra file tạm rồi nhập vào thư viện thành video mới; ảnh tĩnh giữ nguyên.

## 7. Slideshow

Mở từ menu ⋯ (mờ khi nguồn < 2 ảnh), toàn màn nền đen.

- Chuyển ảnh bằng mờ chồng 0,6 giây (tắt khi bật giảm chuyển động); điều khiển tự ẩn sau 3 giây.
- Đóng · chọn **2/3/5/8/12 giây mỗi ảnh** (nhớ lại lần sau) · Trước/Tạm dừng/Sau · dòng "N of M".
- **Bỏ qua video** — slideshow dừng lại phát clip là tính năng khác, và Video Studio đã lo phần đó. Cố ý
  không có chủ đề hay nhạc: phần dựng phim thật là Video Studio, đây chỉ là bản "xem lướt".
- Ảnh chỉ nhận **bản cuối cùng**, không nhận bản xem trước — cờ của hệ thống trả lời "bản này còn thô", chứ
  không phải "đây là bản cuối"; đọc nhầm một lần là vòng quay treo vĩnh viễn với ảnh đã cache.

## 8. Panorama

⋯ → **View Panorama** (chỉ với ảnh panorama) mở một màn riêng, nền đen.

- Ảnh **cao bằng màn hình**, bề ngang chạy ra ngoài hai mép, cuộn ngang. Viewer thường fit cả khung nên ảnh
  9000×1200 thành một dải cao vài trăm pixel — vứt đi đúng lý do người ta chụp panorama.
- **Màn riêng chứ không phải một chế độ trong viewer**: đã cao bằng màn thì kéo ngang phải là cuộn ảnh, mà
  trong viewer kéo ngang là lật ảnh. Hai cái phải nhường nhau một, tách màn là cách nói thẳng cái nào nhường.
- Mở ra **đứng giữa** ảnh. Nút **play** quét từ trái sang phải, ~4 giây một màn hình — đủ chậm để đọc là
  *nhìn* chứ không phải cuộn. Chạm tay là dừng ngay, và dừng ở **chỗ hoạt ảnh đang thật sự hiện**, không
  phải ở đích nó đang nhắm tới.
- Ảnh tải ở **độ phân giải tối đa** — xem một dải ở chiều cao thật thì bản vừa màn hình đã vứt chi tiết mất rồi.

## 9. Cắt video

⋯ → **Trim** mở một màn riêng, tier D: nền đen, hàng trên `Cancel` / `Trim` / `Save`.

- Panel đáy: dải 10 khung xem trước (dung sai ±0,5 giây vì dải này chỉ là **bản đồ thô**), hai tay nắm
  amber, vùng bỏ đi tối 60%, playhead trắng, nhãn `bắt đầu – kết thúc · độ dài`, nút Play (phát **đúng dải
  đang chọn**) và Reset.
- **Một cử chỉ kéo cho cả dải**, không phải mỗi tay nắm một cái — một thanh 16pt đặt bằng độ lệch **không
  nhận được chạm nào**. Chạm xuống chọn tay nắm **gần hơn** và giữ lựa chọn đó tới hết cú kéo, nếu không kéo
  điểm đầu vượt điểm cuối là cử chỉ nhảy sang tay kia giữa chừng. Cắt chạy theo **độ dịch của ngón**, không
  theo vị trí tuyệt đối, nếu không dải sẽ nhảy ngay lúc chạm.
- Ghi **đè lên chính video đó**, kèm dữ liệu chỉnh sửa mang định danh của app — nên Photos vẫn **Revert** về
  bản gốc được, và đó là thứ cho phép ghi đè thay vì đẻ ra bản sao. App **nhận lại chính adjustment của
  mình** nên cắt lần hai là cắt tiếp.
- Xuất ở chế độ **giữ nguyên luồng** + khoảng thời gian: giữ nguyên codec, bitrate, HDR. Nén lại một bản
  ProRes hay Dolby Vision xuống H.264 chỉ để bỏ hai giây là phá hoại ngầm.
- Phần toán (kẹp hai tay nắm, tối thiểu **0,3 giây**, mốc khung xem trước) là hàm thuần, có test.

## 10. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
