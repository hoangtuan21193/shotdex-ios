# FS-06.07 — On This Day

`FS-06.07` · `Features/Albums/OnThisDayScreen.swift` · `Domain/OnThisDay/`
· `App/OnThisDayNotificationScheduler.swift` · cập nhật 2026-10-02

**Một câu:** ảnh chụp đúng ngày này ở những năm trước, cộng một lời nhắc hằng ngày nói chúng chiếm bao nhiêu
dung lượng.

## 1. Quy tắc

- Cửa sổ ngày của từng năm dựng **trong mã thuần** (có test) rồi quy ra mốc thời gian để dùng chỉ mục —
  **không** hỏi database bằng cách trích tháng/ngày từ mốc thời gian: cách đó gom theo giờ quốc tế nên ảnh
  chụp 23:30 rơi sai ngày, không dùng được chỉ mục, và mất luôn phần xử lý 29/2 và giờ mùa hè.
- Số liệu của lời nhắc đọc từ **database**, không quét thư viện ảnh.
- Lời nhắc **không chạy code lúc bắn** → mọi con số phải tính **trước** lúc đặt lịch.
- Màn chi tiết **cùng chiều với Library**: năm cũ ở trên, năm mới nhất ở đáy.

## 2. Ảnh bìa

- Xin đúng kích thước vật lý (bề rộng **cửa sổ** × độ phân giải thật của màn, cắt theo tỉ lệ), và giữ trong
  một bộ nhớ đệm riêng nên không bị đẩy ra bởi thumbnail của lưới hay của viewer.
- Màn gốc hâm nóng ảnh bìa **sau khung hình đầu tiên**, dù tab Collections còn chưa dựng.
- **Cùng chỗ đó nạp trước cả danh sách album**: model của tab do màn gốc sở hữu và chạy ngầm sau khung hình
  đầu — việc dựng danh sách phải hỏi số ảnh của **từng** album nên tốn 300–670ms (đo trên 31 album).
- **Hâm nóng thumbnail cho màn chi tiết**: mỗi tile khi hiện ra xin trước khoảng bốn hàng ảnh đầu ở **đúng
  kích thước mà lưới chi tiết sẽ xin** — bộ nhớ đệm khoá theo bề rộng nên lệch 1px là một mục khác và ô vẫn
  mờ. Mở album chỉ tốn 16ms dữ liệu, nhưng 120 thumbnail vẽ từ đầu mới là cái phải chờ.

## 3. Khi nào tab nạp lại

Nghe **hai** tín hiệu: "có ảnh thêm/bớt/đổi chỗ" và **"có album thêm/bớt/đổi"** — không nghe tín hiệu "có
thay đổi bất kỳ", vì tín hiệu đó bắn mỗi giây trong lúc tải ảnh từ iCloud.

- Tín hiệu album **sửa một bug thật**: chỉ nghe tín hiệu ảnh thì **tạo album xong không thấy album** — tạo
  một album (kể cả rỗng) không dịch chuyển ảnh nào nên tín hiệu kia không bắn, phải mở lại app mới hiện.
- Tín hiệu album bắn cả khi một album **đổi nội dung**, vì thêm tấm ảnh đầu tiên vào một album không đổi
  *danh sách* album nhưng quyết định album đó có được vẽ hay không (album rỗng bị loại).
- Mốc so sánh phải được gieo **ngay lúc bắt đầu quan sát**, cùng chỗ với mốc của ảnh — thiếu mốc thì mọi
  thay đổi đều bị coi là thay đổi album.
- Dùng chung mức gộp một lần mỗi giây, và bỏ qua nếu danh sách hiện tại đã dựng từ đúng **cặp** tín hiệu đó.

## 4. Màn chi tiết

- Dùng **lưới dùng chung**, nhưng **màn tự cấp nhóm**: nhóm theo năm, tiêu đề dính dạng viên nang
  "2023 · N years ago".
- Neo đáy, và danh sách được đảo (truy vấn vẫn lấy mới nhất trước vì thẻ ở tab dùng ảnh mới nhất làm bìa) →
  mở ra là ở đáy. Trước đây năm mới nhất nằm trên cùng, **lật ngược dòng thời gian so với Library**.
- Nhờ dùng lưới chung: pinch đổi mật độ (1…8, nhớ chung với Library), nạp trước thumbnail, xoá tại chỗ (mục
  của một năm rỗng thì bay theo), giữ-rồi-kéo và quét chọn.
- Model phát **hai** loại tín hiệu: "danh sách đổi" (đổi ngày, ảnh thêm/bớt, sau khi xoá — đổi ngày có thể
  ra danh sách **cùng số lượng** nên lưới không thể chỉ dựa vào số lượng) và "nội dung ô đổi" (bật favorite,
  ảnh vừa được index sau khi tải từ iCloud).
- Đổi ngày: nút lịch mở một bảng chọn ngày dạng lịch + nút "Today"; **chỉ tháng và ngày** được dùng để so khớp.
  - Bảng có **hai nấc: cao 440pt và toàn màn** (Q8). 440pt chứa trọn lịch tháng 6 hàng + thanh Today/Done.
    *Vì nấc nửa màn ở 678pt (Duo cover) cắt lịch mà không cuộn được.*
  - Duo inner (cao 669, compact height) và iPad: hệ thống bỏ nấc, bảng toàn màn / form sheet, vẫn có Done.
  - Board: chưa có board cho bảng này (`*_OnThisDay` chỉ vẽ màn chi tiết).
- **Đóng viewer thì lưới đưa tới ảnh vừa xem** (Q7), cùng luật với Library: ô của ảnh cuối cùng đang hiện trong
  viewer không thấy trọn thì lưới cuộn, không hoạt ảnh, để ô đó thấy trọn giữa thanh trên và đáy; ô đã thấy trọn
  thì lưới đứng yên.
- Chọn nhiều: thanh đáy **giống các album khác**. Lựa chọn lưu **theo thứ tự chạm** nên thumbnail xem trước
  và các khung Compare theo đúng thứ tự người dùng chọn.

## 5. Lời nhắc hằng ngày

Tuỳ chọn, bật trong Settings ([FS-08.03](../FS-08-settings/03-other-sections.md)). Mỗi ngày một thông báo
nói ngày đó những năm trước có bao nhiêu ảnh và video, chiếm bao nhiêu dung lượng — mục đích là để người
dùng chủ động vào xoá, giải phóng máy.

- **Số liệu từ database**: hỏi thư viện ảnh tương đương là một truy vấn quét cả thư viện, làm 7 lần mỗi lần
  làm mới là không chấp nhận được — và đi qua database còn nghĩa là lượt chạy nền không cần quyền ảnh trong
  tay. Số đếm vẫn chính xác vì lượt index nhanh ghi một dòng cho **mọi** ảnh trong vài giây; chỉ **dung
  lượng** là tập con.
- **Dung lượng là mức tối thiểu khi index chưa xong**: nếu số ảnh đã biết dung lượng ít hơn tổng số ảnh thì
  câu chữ đổi thành **"ít nhất X GB"**. Không đo được byte nào thì chỉ hiện số ảnh.
- **Nhìn trước 7 ngày, mỗi ngày một thông báo không lặp**: mỗi lần làm mới thì đo 7 ngày tới rồi **thay
  sạch** tập đang chờ.
  - Ngày 0 ảnh bị bỏ hẳn.
  - Hôm nay bị bỏ khi giờ nhắc đã qua — một mốc không ở tương lai thì không bao giờ được giao.
  - Một ngày bị bỏ khi **giờ nhắc không tồn tại** trên ngày đó (giờ mùa hè nhảy lên), nếu không sẽ tạo một
    lịch im lặng không bao giờ bắn.
  - Định danh khoá theo **ngày**, không theo giờ, nên đổi giờ nhắc là thay chứ không dồn. Khi dọn thì **chỉ
    dọn đúng tiền tố của mình**, tuyệt đối không xoá sạch mọi thông báo đang chờ của app.
  - Mốc giờ **cố ý không kèm múi giờ**, để nó bắn đúng giờ đồng hồ nơi người dùng đang đứng thay vì 3 giờ
    sáng sau một chuyến bay.
  - **Chấp nhận**: app không mở và không có lượt chạy nền quá 7 ngày thì lời nhắc tạm ngừng.
- **Khi nào làm mới**: màn gốc (sau khung hình đầu và mỗi lần app trở lại) và lượt chạy nền
  ([BD-03.04](../../01-basic-design/BD-03-metadata-indexing-flow/04-progress-and-background.md)).
- Bộ đặt lịch là **một actor, không gắn với luồng giao diện**: nó đọc database đồng bộ, phải gọi được từ
  lượt chạy nền, và việc xếp hàng chính là thứ giữ cho cửa sổ "xoá rồi đặt lại" không bị xen kẽ giữa hai
  lượt làm mới. **Mọi điều kiện không thoả đều dẫn tới huỷ lịch, không phải bỏ qua** — nên một lịch đặt dưới
  cấu hình cũ không thể sống sót.

## 6. Chạm thông báo mở thẳng đúng ngày

- Thông báo mang theo ngày dạng `yyyy-MM-dd` — chuỗi thuần, an toàn khi lưu, dựng từ thành phần lịch nên
  không phụ thuộc ngôn ngữ và sống qua việc đổi múi giờ.
- Chạm thì app **thay** đường điều hướng của tab bằng đúng một màn On This Day của ngày đó — thay chứ không
  nối, vì chạm khi đang ở màn này với ngày khác không được xếp chồng hai bản.
- Chạm có thể tới **trước khi màn gốc tồn tại** (mở app từ trạng thái tắt hẳn), nên ngày được **giữ tạm** và
  được lấy ra cả khi giá trị đổi lẫn một lần lúc màn gốc khởi tạo.

## 7. Tiêu chí nghiệm thu

Phần cũ (§1–§6: cửa sổ ngày, ảnh bìa, nạp lại, lời nhắc) **chưa gắn AC** dù có `OnThisDayWindowsTests`,
`OnThisDayQueriesTests`, `OnThisDayNotificationScheduleTests`, `OnThisDayNotificationCopyTests` — xem
[README — Việc còn nợ](../../README.md#6-việc-còn-nợ).

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | (Q8) màn chi tiết ngày 14/9, iPhone 402×874 | chạm nút lịch | bảng cao 440pt; lịch tháng hiện trọn 6 hàng, Today và Done thấy được; kéo bảng lên thì thành toàn màn | ⚠️ chưa có — đề xuất script `onthisday-date-picker.json` |
| AC-2 | (Q8) như AC-1, tháng hiển thị cần 6 hàng (ví dụ 3/2024) | mở bảng trên Duo cover 466×678 | 6 hàng ngày và thanh Today/Done thấy trọn, không cần cuộn; chạm ngày 31 chọn được | ⚠️ chưa có — chụp bằng `Tools/sim-shot … cover` |
| AC-3 | (Q8) như AC-1 | mở bảng trên Duo inner 951×669 và iPad 1376×1032 | bảng toàn màn / form sheet; lịch không bị cắt; Done đóng bảng và ngày mới áp lên màn | ⚠️ chưa có |
| AC-4 | (Q7) ngày có 120 ảnh trong 3 năm, lưới density 3 | mở ảnh thứ 10, vuốt sang 40 ảnh (tới ảnh thứ 50, năm khác), đóng viewer | ô ảnh thứ 50 thấy trọn trên lưới, không nằm dưới thanh trên hay đáy | ⚠️ chưa có |
| AC-5 | (Q7) như AC-4 | mở ảnh thứ 10, vuốt 1 ảnh (ô ảnh 11 đang thấy trọn), đóng viewer | độ lệch cuộn của lưới không đổi (0pt) | ⚠️ chưa có |
| AC-6 | (Q7) như AC-4 | mở ảnh thứ 50, xoá nó trong viewer (viewer sang ảnh 51), đóng viewer | ô ảnh 51 thấy trọn; ảnh 50 không còn trong lưới | ⚠️ chưa có |
