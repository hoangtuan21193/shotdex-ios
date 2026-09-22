# EX-02 — Widget

`EX-02` · `ShotDexWidget/` · `WidgetShared/` · `ShotDex/App/Widgets/`
· test `WidgetSharedTests` · `PhotoWidgetDataTests` (49 ca) · cập nhật 2026-09-22

**Một câu:** hai widget đọc dữ liệu app đã ghi sẵn vào vùng chia sẻ — widget **không bao giờ tự đi lấy** ảnh,
lịch, thời tiết hay vị trí.

## 1. Quy tắc

- **Không widget nào đọc thư viện ảnh, lịch, mạng hay vị trí.** App ghi sẵn dữ liệu; widget chỉ đọc file.
  Một extension tự đi lấy là đẩy việc đó sang một tiến trình thứ hai chạy theo lịch của hệ thống thay vì
  theo ý người dùng.
- **App không bao giờ tự hiện hộp xin quyền lịch hay vị trí** — chỉ hai nút trong màn cài đặt widget mới hỏi.
- **Một mặt widget duy nhất** vẽ mọi hàng **và cũng là bản xem trước trong Settings** — một bản xem trước
  thứ hai là cách bản xem trước bắt đầu nói dối.
- App chỉ làm việc khi **thực sự có widget đang đặt trên màn hình**.
- Ảnh phủ kín ô **phải có khung và bị cắt** — nếu không, khối chứa nó đo theo ảnh và đẩy chữ ra ngoài mép.

## 2. Hai widget

| Widget | Cỡ | Nội dung |
|---|---|---|
| **On This Day** | nhỏ / vừa / lớn / dải Lock Screen | ảnh nền + "N years ago" + số ảnh; cỡ lớn là lưới tối đa 4 ô, mỗi ô một năm |
| **Photo Widget** | mọi cỡ hệ thống + cả ba dạng Lock Screen | vẽ chữ **trên ảnh hoặc album người dùng chọn**; định dạng, font, màu, cỡ, vị trí và độ tối đều lấy từ **design** nó đang mặc ([FS-08.04](../02-functional-spec/FS-08-settings/04-photo-widget-designs.md)) |

- **Một widget, nhiều design** — không phải bốn loại cứng. Bốn loại cũ khác nhau **đúng ở giá trị mặc
  định**, mà lại lấy mất năng lực: một widget "đồng hồ" không thể thêm thời tiết dù mặt widget vẽ được.
  Gộp lúc app còn ở bản 1.0 nên không widget nào của ai bị mồ côi; sau bản thử nghiệm đầu tiên thì xoá một
  loại widget là mất widget người dùng đã đặt.
- **Lock Screen**: mọi design đều có ba dạng. Mặt nào được vẽ là do design quyết — thời tiết nếu bật thời
  tiết, không thì sự kiện nếu bật lịch, không thì ngày. **Không bao giờ vẽ giờ** — Lock Screen đã có đồng
  hồ của nó, và đó chính là lý do widget đồng hồ cũ không được đưa lên đây.
- Dạng Lock Screen dùng **view riêng**, không dùng mặt widget chính: ở đó hệ thống vẽ một màu, không có nền
  ảnh, nên font, màu, vị trí và ảnh người dùng chọn **không có gì để tác động**; chỉ dữ liệu đi qua.
- Việc chọn nền theo cỡ widget phải nằm **trong view**, không nằm ở khai báo widget: dạng Lock Screen cần
  nền trong suốt, còn đặt một tấm ảnh sau nó sẽ ra một khối xám.

## 3. Cấu hình ngay trên màn hình chính

Chạm-giữ widget có mục **Edit Widget**, với bốn tham số:

| Tham số | Ghi chú |
|---|---|
| **Design** (đầu tiên) | **đây là chỗ hai widget cạnh nhau trông khác nhau được** — hệ thống lưu câu trả lời này **theo từng widget đã đặt**, còn design nó trỏ tới nằm trong một file dùng chung. Để trống thì rơi về design đầu tiên, nên widget vừa thả xuống đã vẽ được |
| **Photo** | 100 ảnh mới nhất, mỗi mục có ngày giờ và **một thumbnail 180px** để menu vẽ thành hàng có ảnh. **Thắng Album** khi cả hai cùng được đặt |
| **Album** | danh mục album do app ghi ra (id, tên, số ảnh) — phần hỏi đáp này chạy trong tiến trình widget nên **không được đụng thư viện ảnh**, chỉ đọc file |
| **Change Photo**, **Dim Photo** | có lựa chọn "As Set in ShotDex" để **không** ghi đè cấu hình trong app |

- Menu chỉ là **một danh sách**, không phải lưới, nên phần ảnh lẻ đúng nghĩa là "ảnh chụp gần đây" chứ
  không phải cả thư viện.
- Tìm album **bỏ dấu, bỏ hoa thường, và đổi `đ` thành `d` bằng bảng riêng** — `Đ` là một chữ riêng trong
  bảng mã, phép bỏ dấu của hệ thống không bỏ được gạch ngang của nó.
- **Widget chọn album thì app mới render được ảnh**: widget ghi một yêu cầu vào **file duy nhất mà widget
  ghi và app đọc** (ngược chiều mọi dữ liệu khác) và hiện một dải "Open ShotDex to copy these photos";
  trong lúc chờ thì lịch làm mới đặt sau **15 phút** thay vì hết giờ. Mở app là yêu cầu được xử lý và widget
  được nạp lại.
- **Đồng bộ hai chiều, ai sửa sau thắng**: menu ngoài màn hình chính và màn Settings sửa **cùng một bộ cấu
  hình**. Widget **ghi ngược** câu trả lời của menu vào file dùng chung.
  - Menu không xoá được từ phía app, nên mỗi câu trả lời **chỉ áp dụng một lần**: app nhớ lại **chữ ký** của
    câu trả lời đã nhận; chữ ký không đổi thì không áp lại, và thay đổi sau đó trong app đứng vững.
  - **Menu để trống không phải là một câu trả lời**: không đặt gì và cả hai lựa chọn ở "As Set in ShotDex"
    thì widget **không ghi gì**, kể cả chữ ký. Nếu không, widget thứ hai với menu trống sẽ liên tục ghi đè
    lựa chọn của widget thứ nhất và hai bên thay nhau viết file vô tận.
  - **Hệ quả cần biết**: hai widget cùng design dùng chung một bộ cấu hình.
- App phải **làm mới khi trở lại foreground**: tác vụ khởi tạo chỉ chạy một lần, nên mở lại một app đang
  chạy nền sẽ không xử lý yêu cầu nào.

## 4. Phía app ghi gì

| Việc | Cách làm |
|---|---|
| On This Day | ghi **hôm nay + 2 ngày kế**, mỗi ngày một file dữ liệu + tối đa 4 ảnh; ảnh đại diện **lấy mỗi năm một tấm trước**; chỉ duyệt 60 ảnh đầu; render **không dùng mạng** |
| Photo Widget | 1 ảnh (nguồn ảnh lẻ) hoặc tối đa **12** ảnh (nguồn album, chỉ ảnh tĩnh), **cho phép mạng** vì đó là ảnh người dùng tự chọn |
| Thời tiết | dùng **dịch vụ mở, không cần khoá** — dịch vụ thời tiết của Apple đòi quyền gắn với App ID nên sẽ tối thui với ai tự build. Toạ độ **làm tròn 2 chữ số (~1km)** trước khi gửi và xin ở độ chính xác thấp; đọc lại khi quá 30 phút; quá **3 giờ** thì widget nói "Weather out of date" thay vì hiện số cũ |
| Lịch | chỉ **hôm nay**, tối đa 8 sự kiện, chỉ chép **tiêu đề + giờ + màu lịch**. **Không bao giờ tự xin quyền** — chưa cấp thì ghi rõ "không có quyền" và widget nói lịch đang tắt |
| Ảnh | cạnh dài **1600px, JPEG 0,85**, kèm việc dọn bớt file cũ |

- **Quyền là thứ người dùng tự bật**: hai điểm duy nhất gọi hệ thống là nút **Allow Calendar Access** và
  **Allow Location Access** trong màn cài đặt widget. Mỗi mục có một hàng trạng thái (Allowed · Denied ·
  Not Requested), nút đổi thành **Open Settings** khi đã bị từ chối, và một dòng nói quyền đó dùng làm gì.
- **Chống ghi thừa**: chỉ ghi lại khi thiếu file, khi **dấu hiệu thư viện đổi** (số ảnh và ảnh mới nhất),
  hoặc khi file của hôm nay đã quá 6 giờ. App làm mới khi thư viện báo có thay đổi cấu trúc, ở **cả hai
  nhánh iOS**.
- **Ảnh của album để trong thư mục theo album**, không theo widget → hai widget cùng album dùng chung một
  bản. Giữ tối đa **6** thư mục, cũ nhất bị dọn.
- Ảnh render ở **1600px** vì 1000px là thiếu và nhìn rõ: widget cỡ lớn là 329×345pt, trên màn 3× cần
  ~1035px **cạnh ngắn** — nên một khung ngang chặn ở 1000px cạnh dài đã bị phóng lên trước khi vẽ. App ghi
  lại cỡ đã render, và **tự render lại** nếu nó nhỏ hơn mức hiện tại.
- **Tìm ảnh theo nguồn, không theo widget** (thuần, có test): ưu tiên thư mục riêng của widget khi nó còn
  giữ đúng nguồn, nếu không thì thư mục theo album hoặc ảnh lẻ; thiếu cả hai thì coi như đang chờ. Bản xem
  trước trong Settings **dùng đúng luật đó** nên không thể lệch với màn hình chính.

## 5. Lưu trữ và dòng thời gian

- **Cấu hình là JSON trong vùng chia sẻ, không phải kho cài đặt**: một danh sách **có thứ tự** các design,
  mỗi design gồm id, tên và thiết lập. **Id là thứ widget đã đặt ghi nhớ**, và cũng là tên thư mục ảnh —
  nên đổi tên design **không làm mồ côi** widget đang mặc nó.
- Bộ giải mã cấu hình phải **tự viết và đọc từng khoá một**: bộ giải mã tự sinh làm hỏng **cả file** khi
  thiếu một khoá, nên bản cũ sẽ mất sạch cấu hình.
- **Dòng thời gian**: On This Day có một mốc cho mỗi ngày đã ghi sẵn (các mốc sau rơi đúng nửa đêm địa
  phương). Photo Widget sinh **60 mốc mỗi phút khi có hiện giờ**, còn khi tắt giờ thì **8 mốc cách nhau 15
  phút** — thành phần hiển thị giờ của hệ thống **không nhận định dạng tuỳ chọn**, nên muốn tự chọn định
  dạng thì phải trả giá bằng một mốc mỗi phút, và đó cũng là lý do **giây bị loại khỏi định dạng khi lưu**.
  Ảnh giải mã **một lần cho cả dòng thời gian** rồi dùng lại theo vị trí.
- **Liên kết sâu**: `shotdex://on-this-day?day=YYYY-MM-DD` và `shotdex://photo?id=…` (id có dấu `/` nên
  phải nằm ở phần tham số). App nhận rồi quy về cùng một đường điều hướng như mọi lối vào khác.

## 6. Ràng buộc kỹ thuật

- Thư mục dùng chung là **một nhóm file thuộc CẢ hai target**: mỗi target là một thư mục được đồng bộ, nên
  cùng một file chỉ vào được nhiều target khi thư mục đó được khai trong từng target.
- Quyền cần khai: lịch (hai mức), vị trí khi dùng app. Cả hai target khai **vùng chia sẻ**; build lên máy
  thật cần bật quyền đó trên App ID.
- **Mỗi dòng sự kiện bị đóng khung theo bề rộng widget**, tiêu đề cắt đuôi chứ không nở: một tên sự kiện dài
  từng đẩy cả hàng vượt ra ngoài **hai mép** và mang luôn chấm màu ra khỏi cạnh trái. Danh sách cũng **không
  co chữ** — co chỉ dành cho dòng giờ dài, còn trong một danh sách nó làm tiêu đề khác cỡ với giờ đứng cạnh.
- **Số dòng sự kiện ở widget nhỏ**: chỉ cắt xuống 2 dòng **khi còn vẽ lưới tháng**; nếu chỉ liệt kê sự kiện
  thì dùng đủ số tối đa — cắt sẵn để lại một khoảng trống phía trên dòng "+2 more".
- **Thumbnail của widget phải chờ bản cuối cùng**: chế độ giao hàng nhanh gọi lại **hai lần**, nên lấy ảnh
  khác rỗng đầu tiên là **luôn lấy bản mờ** rồi cache lại hàng giờ. Bản local cuối cùng mà vẫn không đủ nét
  (ảnh chỉ còn bản thu nhỏ trên máy) thì **thử lại có mạng**. App ghi lại phiên bản của bộ render nên file
  do bản cũ ghi tự được render lại.
- **Tải iCloud đi qua một cổng giới hạn 4 lượt**: xin không được thì **trả lời ngay là không**, ô giữ bản
  mềm và hỏi lại ở lần dừng cuộn sau — xếp hàng thì hàng đợi toàn ô đã trôi khỏi màn.

## 7. Ràng buộc còn treo

Nhánh ảnh-thu-nhỏ **không tái hiện được trên máy ảo** (không có iCloud thật, không có tối ưu dung lượng).
Kiểm trên máy thật: bật tối ưu dung lượng → bật chế độ máy bay (ô phải mềm, không treo) → tắt chế độ máy bay
rồi dừng cuộn (ô phải nét lên); đọc log của app ở phân hệ thumbnail.

## 8. Tiêu chí nghiệm thu

49 ca test phủ phần thuần: khoá ngày, liên kết sâu, lưới tháng, cắt danh sách sự kiện, vị trí thành phần,
chuyển đổi dữ liệu bản cũ, thứ tự ưu tiên cấu hình, chọn thư mục theo nguồn, định dạng thời tiết.
Phần giao diện **chưa viết** — xem [README — Việc còn nợ](../README.md#6-việc-còn-nợ).
