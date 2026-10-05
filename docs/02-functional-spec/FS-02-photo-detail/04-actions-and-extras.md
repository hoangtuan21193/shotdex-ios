# FS-02.04 — Hành động và phụ trợ

`FS-02.04` · `Features/Library/SlideshowScreen.swift` · `LivePhotoPlayerView` · `PanoramaScreen`
· `VideoTrimScreen` · cập nhật 2026-10-02

**Một câu:** mọi thứ làm được với tấm ảnh đang xem — menu ⋯, và bốn màn phụ.

## 1. Quy tắc

- **App không tự dựng hộp thoại xác nhận xoá** — hệ thống hiện hộp thoại đó, và app bên thứ ba không ẩn hay
  dời được nó.
- Cùng một hành động phải **đọc giống nhau ở mọi nơi** (Resize ở viewer = Resize ở chế độ chọn).
- Gesture nào tranh nhau thì **tách màn**, đừng chồng chế độ.
- **Mọi sheet mở từ viewer có nút đóng nhìn thấy** (Q1): Photo Info, danh sách khung Burst, các sheet sửa ngày /
  vị trí / thêm vào album. Sheet chỉ-đọc dùng **Done** bên phải thanh tiêu đề; sheet nhập liệu giữ Cancel trái.
- **Không lỗi nào im lặng** (Q2): thao tác ghi lên thư viện mà hỏng thì có cảnh báo; người dùng tự huỷ thì
  không có gì.

## 2. Menu ⋯

| Nhóm | Mục |
|---|---|
| 1 | Add to Album · Duplicate · Copy · **Select Text or Subject** |
| 2 | Adjust Date & Time · Adjust Location · **Show on Map** (chỉ khi có toạ độ) |
| 3 | Hide |

- Video ẩn Copy và Select Text; ảnh Live có thêm **Save as Video**; ảnh panorama có **View Panorama**; video
  có **Trim**; ảnh burst mà app thấy ≥ 2 khung có **Select Frames…** ([05](05-burst-selection.md)) — mục duy
  nhất cho burst, không có mục chỉ-xem-khung riêng.
- **Show in All Photos** hiện khi ảnh **không** mở từ Library (album, chuyến đi, memory, kết quả tìm): đóng
  viewer, về tab Library, mở lại đúng ảnh đó giữa toàn thư viện — đi chung đường với Handoff.
- **Resize** (trước gọi là Compress) đã rời thanh đáy vào menu này; màn đích không đổi.
- **Hide hỏi trước** — từ iOS 16 hệ thống lấy album ảnh ẩn khỏi mọi app trừ Photos, nên app ghi được cờ mà
  không bao giờ thấy lại ảnh để bỏ ẩn ([BD-04](../../01-basic-design/BD-04-design-language.md)). Ẩn xong thì
  toast 4 giây chỉ chỗ tìm lại, cùng chữ với lưới ([FS-01.06](../FS-01-library/06-multi-select.md) §6, D5).

## 3. Xoá, chia sẻ, favorite

- **Delete** gọi đường xoá của hệ thống → hộp thoại xác nhận. Huỷ thì không đổi gì: **không cảnh báo, không
  toast**, viewer đứng ở cùng ảnh. Xoá xong danh sách bị
  cắt nên pager **dựng lại trang hiện tại** ở cùng vị trí đã kẹp — hiện ảnh kế tiếp kiểu Photos; hết ảnh thì
  đóng viewer.
- **Share**: như Photos ([06](06-icloud-originals.md) §9) — share sheet mở ngay, mỗi mục là nguồn dữ liệu lười;
  chọn đích rồi mới tải bản gốc (nếu chỉ có trên iCloud) và ghi lại metadata trong modal giữa màn có tiến độ +
  Cancel. Video chia sẻ file. Không còn cảnh báo "Unable to Share" (2026-10-02).
  Luật gỡ vị trí: [NF-03](../../04-non-functional-design/NF-03-privacy-and-security.md).
- **Favorite** ghi thẳng lên thư viện ảnh — hệ thống là nguồn thật. Tim chỉ đổi khi hệ thống báo ghi xong.
- **Hỏng** (Q2) — favorite hay xoá bị hệ thống từ chối (quyền, iCloud, lỗi ghi): cảnh báo **"Couldn't Update
  Photos"** kèm lý do của hệ thống, hai nút **OK** và **Try Again**, cùng cảnh báo với lưới ([FS-01.06](../FS-01-library/06-multi-select.md)
  §6). Tim giữ trạng thái cũ, ảnh vẫn ở trang đó. Cảnh báo do bộ điều phối của viewer trình bày, nên hiện
  được trên lớp phủ toàn màn.
- **Try Again** (K12) chạy lại **đúng thao tác vừa hỏng**, trên đúng ảnh đó và cùng giá trị (tim bật thì vẫn
  bật). Hỏng nữa thì cảnh báo hiện lại; OK đóng cảnh báo, không đổi gì. Xoá chạy lại thì hệ thống hỏi xác nhận lại.

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

⋯ → **View Panorama** mở một màn riêng, nền đen. "Ảnh panorama" ở đây là **một định nghĩa dùng chung
cho cả app**: ảnh mang cờ panorama của hệ thống (Pano của Camera) **hoặc** ảnh ShotDex ghép ra, nhận
qua thẻ XMP của nó ([FS-14 §7](../FS-14-panorama/01-screen-and-flow.md)). Không theo tỉ lệ khung: ảnh
crop 21:9 không phải panorama.

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

- **Esc = Cancel** (Z5): đóng màn, video giữ nguyên, dải đã kéo bị bỏ không hỏi. Đang lưu (màn khoá, vòng
  *Saving…*) thì Esc và Cancel không làm gì cho tới khi hệ thống trả lời.

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

Board: `PH_Viewer`, `IP_Viewer`, `DI_Viewer`, `DC_Viewer` (cảnh báo, toast Hide); `*_VideoTrim` không đổi.
Các luật khác của file chưa có AC — xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | (Q2) iPhone 402×874, ảnh chưa favorite, lệnh ghi favorite trả lỗi (giả lập) | bấm tim | trong ≤ 1 s có cảnh báo "Couldn't Update Photos" + lý do + OK + Try Again; tim vẫn rỗng; OK đóng cảnh báo, viewer ở cùng ảnh | ⚠️ chưa có |
| AC-2 | (Q2) ảnh 12 của 50 | bấm Delete, rồi Cancel trong hộp thoại hệ thống | 0 cảnh báo, 0 toast; viewer vẫn ở ảnh 12; nguồn vẫn 50 ảnh | ⚠️ chưa có |
| AC-3 | (Q2) ảnh 12 của 50, lệnh xoá trả lỗi (giả lập) | bấm Delete | cảnh báo "Couldn't Update Photos" có OK + Try Again; ảnh 12 vẫn hiện; nguồn vẫn 50 ảnh | ⚠️ chưa có |
| AC-4 | (Q2) quyền `.limited`, ảnh đã chia sẻ, lệnh ghi favorite bị từ chối | bấm tim | cảnh báo như AC-1, không đổi gì trên lưới phía sau | ⚠️ chưa có |
| AC-5 | (Q2) như AC-1 trên iPhone 16 iOS 18.6 và Duo ngoài 466×678 | bấm tim | cảnh báo hiện trên viewer, nút OK và Try Again nằm trọn bên trái rail 84pt | ⚠️ chưa có |
| AC-6 | (D5) viewer ở một ảnh | ⋯ → Hide → xác nhận | toast "1 photo hidden · Find it in Photos > Hidden" hiện 4 s ± 0,2 s, không có nút Undo | ⚠️ chưa có |
| AC-7 | (Q1) ảnh burst, danh sách khung Burst đang mở trên iPhone và Duo ngoài | bấm Done | Done thấy ở phải thanh tiêu đề trước khi bấm, nằm ngoài rail; sheet đóng, viewer ở cùng ảnh | ⚠️ chưa có |
| AC-8 | (Z5) iPad có bàn phím, Trim video 20 s, dải đã kéo về 2,0–8,0 s | bấm Esc | màn đóng; video vẫn dài 20 s | ⚠️ chưa có |
| AC-9 | (Z5) Trim đang lưu (vòng *Saving…*) | bấm Esc | màn không đóng; lưu chạy tới xong rồi màn tự đóng | ⚠️ chưa có |
| AC-10 | (K12) như AC-1, lỗi giả lập chỉ ở lần ghi đầu | bấm Try Again | lệnh favorite chạy lại đúng 1 lần cho đúng ảnh đó; tim đầy; không còn cảnh báo | ⚠️ chưa có |
| AC-11 | (K12) như AC-3, lỗi giả lập ở mọi lần ghi | bấm Try Again | hộp xác nhận xoá của hệ thống hiện lại; xác nhận thì cảnh báo hiện lại; ảnh 12 vẫn hiện | ⚠️ chưa có |
