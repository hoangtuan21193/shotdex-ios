# NF-03 — Quyền riêng tư và bảo mật

`NF-03` · `ShotDex/Features/Support/` · `PrivacyInfo.xcprivacy` · cập nhật 2026-09-24

**Một câu:** cam kết xử lý cục bộ, hai ngoại lệ, và luật gỡ vị trí khi chia sẻ.

## 1. Quy tắc

- Không tải ảnh hay EXIF lên máy chủ. Không tài khoản, không đăng nhập. Dữ liệu index nằm trên máy.
- Onboarding ghi: *"Your photos and metadata stay on this device. They leave it only when you upload them
  to a server you set up."* Câu đó **nói kèm ngoại lệ**, không được viết tuyệt đối.
- **Quyền khai mà không dùng là bề mặt thừa** — extension chia sẻ **không** khai vùng chia sẻ với app, vì
  nó chỉ ghi ảnh vào thư viện.

## 2. Ngoại lệ thứ nhất — tin nhắn hỗ trợ

Do người dùng chủ động gõ và bấm gửi ([FS-13](../02-functional-spec/FS-13-support.md)).

| Gửi đi | Không gửi |
|---|---|
| nội dung họ viết | ảnh |
| phiên bản app và iOS, model máy, ngôn ngữ | tên, email |
| số ảnh **đã làm tròn** | vị trí |
| log chẩn đoán **nếu** họ tự bật và đọc trước | — |

Danh tính là **khoá chứng thực của bản cài** — gỡ app là mất.

## 2b. Ngoại lệ thứ hai — upload lên file server của người dùng

[FS-15](../02-functional-spec/FS-15-server-upload/README.md). Chỉ khi người dùng tự chọn ảnh và bấm Upload.

| Gửi đi | Không gửi |
|---|---|
| file gốc của ảnh được chọn, tới **đúng** server người dùng khai (SMB/SFTP) | bất cứ thứ gì tới máy chủ của ShotDex — không có máy chủ nào |
| tên file, thư mục theo ngày chụp | database index, lịch sử upload |

- Mật khẩu server ở **Keychain**, chỉ trên máy này, không vào bản sao lưu; không bao giờ vào database hay log.
- SFTP xác minh host key lần đầu và **chặn** khi nó đổi. SMB không có cơ chế tương đương — ghi rõ ở FS-15.
- Upload **không** gỡ vị trí (Include Location là luật của Share sheet): đây là bản lưu trữ của chính người
  dùng, gỡ toạ độ là làm hỏng bản gốc.

## 3. Chia sẻ không kèm vị trí

- **Settings → Sharing → Include Location**, mặc định **bật** (như Photos: toạ độ là một phần hồ sơ của tấm
  ảnh, và thợ ảnh gửi cho khách thường muốn có nó). Tắt thì toạ độ bị gỡ **trước khi ảnh rời khỏi app**.
- Ghi lại file bằng cách **chép ảnh sang file mới kèm bộ thuộc tính đã sửa**, **không** giải mã rồi mã hoá
  lại: lời hứa của công tắc là bỏ toạ độ mà **không đụng một pixel hay một trường EXIF nào khác**.
- **Muốn xoá một trường thì phải ghi một giá trị rỗng tường minh** — bỏ trống trường đó nghĩa là "giữ nguyên
  của ảnh gốc". Xoá cả nhóm GPS, trường vị trí chủ thể, và mấy trường địa danh của chuẩn báo chí.
- **Video ngoài phạm vi**: vị trí của clip nằm trong phần mô tả của container, gỡ nó nghĩa là **ghi lại cả
  file** — một cú chia sẻ không được phép mã hoá lại một clip 4K. Dòng chú của thiết lập nói thẳng điều đó.

## 4. Bản khai quyền riêng tư — cả 5 target

| Target | Khai gì |
|---|---|
| App | dùng **kho cài đặt** (chỉ kho mặc định, không dùng kho theo nhóm — dữ liệu chia sẻ với widget đi qua **file trong thư mục chung**, không qua kho cài đặt) và **đọc ngày của file** ở hai chỗ: nhạc người dùng nhập, và thư mục người dùng chọn khi nhập ảnh. Mỗi mục khai kèm **mã lý do** tương ứng |
| Bốn target còn lại | không dùng API nào thuộc diện phải khai lý do — bản khai rỗng |

- Mọi target đều khai **không theo dõi người dùng** và **không thu thập dữ liệu**: trong mã không có lời gọi
  mạng nào, không có thư viện phân tích hay báo lỗi nào, và việc nhận diện người/thú chạy **hoàn toàn trên máy**.
- Trình build tự đưa bản khai vào phần tài nguyên — đã kiểm bản build ra: **cả 5 bản khai nằm đúng chỗ**
  trong app, các extension và framework.

## 5. Câu xin quyền phải nói đúng việc app làm

Mức quyền đang xin đã đủ và **không thiếu khoá khai nào** — nhưng câu chữ thì từng thiếu sự thật: bản cũ chỉ
nói app "phân tích metadata", trong khi app **ghi rất nhiều** (sửa ảnh, đánh dấu yêu thích, tạo album, nhân
bản, xoá, xuất video). Câu đó phải nói cả phần ghi.
