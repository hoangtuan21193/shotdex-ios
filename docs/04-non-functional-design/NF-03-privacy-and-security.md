# NF-03 — Quyền riêng tư và bảo mật

`NF-03` · `ShotDex/Features/Support/` · `PrivacyInfo.xcprivacy` · cập nhật 2026-10-03

**Một câu:** cam kết xử lý cục bộ, hai ngoại lệ, và luật metadata khi chia sẻ hay xuất.

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
| file gốc của ảnh được chọn, tới **đúng** server người dùng khai (SMB/SFTP/WebDAV) | bất cứ thứ gì tới máy chủ của ShotDex — không có máy chủ nào |
| tên file, thư mục theo ngày chụp | database index, lịch sử upload |

- Mật khẩu server ở **Keychain**, chỉ trên máy này, không vào bản sao lưu; không bao giờ vào database hay log.
- WebDAV qua HTTP gửi mật khẩu và ảnh **không mã hoá** — chỉ khi người dùng tự chọn, form cảnh báo
  ([FS-15.05 §3](../02-functional-spec/FS-15-server-upload/05-more-protocols.md)).
- Tải ảnh **về** từ server ([FS-17](../02-functional-spec/FS-17-import-from-server/README.md)) chỉ nhận dữ liệu; không
  gửi gì ngoài lệnh đăng nhập và đọc file.
- SFTP xác minh host key lần đầu và **chặn** khi nó đổi; WebDAV HTTPS làm y hệt với chứng chỉ tự ký. SMB không có cơ chế tương đương — ghi rõ ở FS-15.
- **Sidecar `.xmp`** ([FS-19.02 §5](../02-functional-spec/FS-19-photo-sources/02-identity-and-sidecars.md)): ShotDex ghi
  sao, cờ, keyword, title, caption, recipe vào file `.xmp` cạnh bản sao ở thư mục, ổ hay server **của người dùng** — không
  đi đâu khác, không bao giờ ghi vào file ảnh, mọi thẻ của app khác giữ nguyên. Tắt bằng Read and Write .xmp Sidecars.
- Upload **không** gỡ vị trí (lựa chọn metadata của FS-08.06 là luật của chia sẻ và xuất): đây là bản lưu trữ của chính người
  dùng, gỡ toạ độ là làm hỏng bản gốc.

## 3. Metadata khi chia sẻ và xuất

Đặc tả đầy đủ, kèm tiêu chí nghiệm thu: [FS-08.06](../02-functional-spec/FS-08-settings/06-share-metadata-privacy.md).

- **Ba mức cho mỗi lần chia sẻ hay xuất**: All Metadata · No Location · No Metadata. Mặc định nằm ở
  Settings → Sharing và là **All Metadata** (như Photos: toạ độ là một phần hồ sơ của tấm ảnh, và thợ ảnh gửi cho
  khách thường muốn có nó).
- **Một mặc định cho mọi lối ra**: Share, Save Copy, Paste Edits, Resize và kéo sang app khác.
- **No Metadata giữ Copyright và Artist** — quyền tác giả của người chụp, không phải dấu vết về họ.
- **Save Changes không bao giờ đổi ngày hay vị trí của asset** — ảnh không rời máy, nên nó bỏ qua lựa chọn
  metadata (lựa chọn chỉ nằm ở phần Save Copy của sheet Save).
- **Vị trí người dùng đã xoá không rời máy**: asset không còn vị trí mà file vẫn mang GPS thì mọi mức, kể cả All
  Metadata, đều bỏ GPS của file.
- Ghi lại file bằng cách **chép ảnh sang file mới kèm bộ thuộc tính đã sửa**, **không** giải mã rồi mã hoá
  lại: bỏ toạ độ mà **không đụng một pixel hay một trường EXIF nào khác**. Hai ngoại lệ, người dùng chốt
  2026-10-01 ([FS-08.06 §3](../02-functional-spec/FS-08-settings/06-share-metadata-privacy.md)): PNG và TIFF
  được ghi lại không mất dữ liệu (pixel vẫn trùng từng byte), và HEIC ở No Metadata đi dưới dạng JPEG chất
  lượng tối đa — share sheet nói rõ *"HEIC sent as JPEG"*.
- **Muốn xoá một trường thì phải ghi một giá trị rỗng tường minh** — bỏ trống trường đó nghĩa là "giữ nguyên
  của ảnh gốc". Xoá cả nhóm GPS, trường vị trí chủ thể, và mấy trường địa danh của chuẩn báo chí.
- **Không ghi lại được thì không âm thầm giao đi nguyên bản.** ImageIO không ghi được RAW, nên mẻ có RAW hỏi
  một lần: Share as JPEG · Share RAW with Location · Skip (RAW iOS không đọc được: Share as JPEG mờ). Ảnh khác ghi
  lại lỗi thì bị bỏ khỏi mẻ và nêu tên. Kéo thả không hỏi được, nên RAW kéo ra đi dưới dạng JPEG render ở mức mặc
  định; ảnh đã chỉnh kéo ra bản đã chỉnh, như Share.
- **Gom sau khi chọn đích**: share sheet mở ngay, tải iCloud và ghi lại metadata chạy sau khi người dùng chọn
  đích, trong một modal có Cancel ([FS-02.06 §9](../02-functional-spec/FS-02-photo-detail/06-icloud-originals.md)).
- Đổi mức cho một lần share bằng hai dòng hành động của app trong share sheet; chạm Share thường dùng mặc định.
- **Video đi nguyên bản ở mọi mức**: vị trí nằm trong phần mô tả của container, gỡ nó là chép cả clip ra đĩa.
  Mẻ có video mà mức không phải All Metadata thì app nói *"Videos keep their metadata"* trước khi share.
- Share extension "Save to ShotDex" lưu nguyên byte: nó nhận ảnh **vào** thư viện, không gì rời máy.

## 4. Bản khai quyền riêng tư — cả 5 target

| Target | Khai gì |
|---|---|
| App | dùng **kho cài đặt** (chỉ kho mặc định, không dùng kho theo nhóm — dữ liệu chia sẻ với widget đi qua **file trong thư mục chung**, không qua kho cài đặt) và **đọc ngày của file** ở hai chỗ: nhạc người dùng nhập, và thư mục người dùng chọn khi nhập ảnh. Mỗi mục khai kèm **mã lý do** tương ứng |
| Bốn target còn lại | không dùng API nào thuộc diện phải khai lý do — bản khai rỗng |

- Mọi target đều khai **không theo dõi người dùng** và **không thu thập dữ liệu**: trong mã không có lời gọi
  mạng nào, không có thư viện phân tích hay báo lỗi nào, và việc nhận diện người/thú chạy **hoàn toàn trên máy**.
- **Nhận dạng giọng nói chỉ chạy trên máy** (phụ đề Video Studio, [FS-12.14](../02-functional-spec/FS-12-video-studio/14-captions.md)):
  không có model trên máy thì không chạy, không bao giờ rơi sang máy chủ.
- Trình build tự đưa bản khai vào phần tài nguyên — đã kiểm bản build ra: **cả 5 bản khai nằm đúng chỗ**
  trong app, các extension và framework.

## 5. Câu xin quyền phải nói đúng việc app làm

Mức quyền đang xin đã đủ và **không thiếu khoá khai nào** — nhưng câu chữ thì từng thiếu sự thật: bản cũ chỉ
nói app "phân tích metadata", trong khi app **ghi rất nhiều** (sửa ảnh, đánh dấu yêu thích, tạo album, nhân
bản, xoá, xuất video). Câu đó phải nói cả phần ghi.
