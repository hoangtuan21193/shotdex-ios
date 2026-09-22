# FS-02.02 — Video

`FS-02.02` · `Features/Library/VideoPlaybackModel.swift` · `ZoomableVideoView`
· `Domain/Presentation/VideoTransportMath.swift` · cập nhật 2026-09-22

**Một câu:** phát clip ngay trong viewer — trạng thái nói thật, transport hai hàng, và không bao giờ để lại
một khung đen im lặng.

## 1. Quy tắc

- **Giữ khung phát của hệ thống, không thêm thư viện player.** Các engine ngoài nhắm streaming và codec lạ,
  thêm 20–70 MB vào app, và mất đường lấy video của thư viện ảnh.
- **"Sẵn sàng" nghĩa là item đã sẵn sàng *và* lớp hình đã có gì để vẽ** — không phải "player khác rỗng".
- **Chỉ trang đang hiện mới tải video.**
- **Cụm nút giữa khung và panel dưới là MỘT bộ control** — cùng ẩn, cùng hiện.
- Mọi lần tua đi qua **một** yêu cầu duy nhất; trong lúc tua thì đồng hồ định kỳ **không được ghi** vị trí.

## 2. Trạng thái phát

Năm trạng thái: **rỗi · đang tải · đang đệm · sẵn sàng · lỗi**.

| Trạng thái | Lớp phủ |
|---|---|
| Đang tải | vòng tiến độ iCloud + dòng "Downloading from iCloud" |
| Đang đệm | vòng quay, **sau 350ms** (bản đã cache thì không nháy) |
| Lỗi | thẻ cảnh báo + nút **Retry** (huỷ yêu cầu, tháo player, nạp lại) |

- Theo dõi cả: item đã sẵn sàng chưa · lớp hình đã có gì để vẽ chưa (clip chỉ có tiếng thì bỏ qua điều kiện
  này) · buffer đủ để chạy tiếp không · và tình trạng phát. Clip báo lỗi khi chạy dở cũng vào trạng thái lỗi.
- **Đồng hồ canh 15 giây**, gia hạn mỗi nhịp tiến độ: chưa sẵn sàng thì chuyển sang lỗi và mời thử lại, thay
  vì để vòng quay chạy mãi.
- Đường xin video trả về **một kết quả có lỗi rõ ràng**, không phải một giá trị rỗng — hệ thống trả rỗng cho
  cả ba trường hợp huỷ, lỗi thật và iCloud không phục vụ được, còn chỗ gọi cũ nuốt cả ba.
- Nhờ đường đó mà **vòng tiến độ iCloud và cảnh báo đứng im cũng chạy cho video**, không chỉ cho ảnh.
- Lớp phủ **độc lập với việc chrome đang ẩn hay hiện** — clip không phát được vẫn phải nói lý do sau khi
  transport mờ đi.
- Bấm play khi player chưa có thì **được ghi nhớ** và thực hiện lúc sẵn sàng, nên tự phát không bị mất.

## 3. Transport

**Cụm giữa khung hình**: lùi 10 giây · play/pause · tiến 10 giây — đường kính 56/68/56pt, glyph trắng trên
đĩa đen mờ.

**Panel dưới** — hai hàng trong một viên kính (một hàng 8 control không đủ 44pt trên máy 393pt):

| Hàng | Nội dung |
|---|---|
| Trên (44pt) | play/pause · thời gian đã trôi · thanh tua · thời gian còn lại |
| Dưới (6 × 44pt, chia đều) | tốc độ (0,5/1/1,5/2×) · tắt tiếng · AirPlay · **loop** · **lưu khung** · toàn màn |

- Hai nhãn thời gian dùng chữ số đều bề rộng và **rộng cố định** để thanh tua không giật khi đổi số chữ số;
  thời lượng iCloud chưa biết thì in `--:--` — **số sai còn tệ hơn trống**.
- **Có hai nút play/pause là cố ý**: cụm giữa ẩn khi phóng, panel dưới thì không — nút ở đầu hàng tiến độ là
  nút **luôn có mặt**.
- Chỉ nút play **ở cụm giữa** mới ẩn chrome tức thì; nút ở hàng tiến độ đi theo đồng hồ 3 giây, vì ẩn ngay sẽ
  rút chính thanh tua vừa bấm ra khỏi dưới ngón tay.
- **Không có menu ⋯ ở transport**: loop là công tắc dùng thường xuyên, chôn trong menu hai tầng thì không
  thấy được trạng thái.
- Cụm giữa còn ẩn khi: chưa sẵn sàng · đang hiện nhãn vừa lưu khung · **đang phóng** · và trong **cửa sổ tự
  phát đầu tiên** (mở clip là để xem, không phải để nhìn nút).
- Hiện/ẩn bằng độ mờ + tắt nhận chạm, **không phải chèn/gỡ view**: trạng thái đổi từ ngoài mọi hoạt ảnh nên
  chèn/gỡ sẽ nhảy khựng.
- **Một đồng hồ chung 3 giây**: transport, cụm giữa, nút đóng, bảng thông tin, thanh đáy và status bar mờ đi
  **đồng bộ**. Dừng hoặc hết clip thì huỷ đồng hồ và giữ control hiện.

## 4. Cử chỉ

| Cử chỉ | Kết quả |
|---|---|
| Chạm bất cứ đâu khi đang phát | **dừng + hiện toàn bộ control** |
| Chạm khi đang dừng | bật/tắt chrome như thường |
| Chạm đôi nửa trái/phải | **luôn** tua ∓10 giây, dù đang phát hay dừng |
| Chạm đôi khi đang phóng | về lại 1× |
| Pinch | phóng 1–5× |

- Chạm do cử chỉ của UIKit xử lý (nhường cho chạm đôi), **không** thêm một lớp SwiftUI trong suốt để hứng
  chạm — lớp đó sẽ được hỏi trước và ăn luôn touch, làm mất kéo khi đang phóng.
- Nút transport nằm **trên** lớp video nên bấm nút không bật/tắt chrome.
- Phản hồi khi tua là **nút nảy nhẹ** (nhấn liên tục thì nảy từng lần), tôn trọng thiết lập giảm chuyển
  động. **Không dùng vệt sáng loang**: nó phủ gần nửa khung hình, đè lên đúng nội dung đang xem.
- Ở chế độ xem toàn màn, khung đã xoay 90° nên cú chạm tới theo hệ toạ độ **trước khi xoay**: nửa trái/phải
  vật lý ứng với trục **dọc** của khung.

## 5. Tua và kéo thanh tua

- **Gộp yêu cầu**: vị trí mới được ghi **lạc quan** rồi giao cho một yêu cầu duy nhất đang bay; mục tiêu mới
  thay mục tiêu cũ. Suốt lúc đó đồng hồ định kỳ không ghi vị trí — nếu ghi, nhịp 0,25 giây kế tiếp sẽ đè
  bằng vị trí **trước** khi tua, và thanh nhảy tới rồi giật lùi.
- Buffer cạn trong lúc tua **không** bị coi là sự cố (tua làm cạn buffer là chuyện thường).
- Nhờ vị trí lạc quan, chạm đôi liên tiếp **tự cộng dồn** (3 lần = 30 giây) mà thanh chỉ đi một chiều.
- **Kéo thanh tua hiện đúng khung đang kéo**: bắt đầu kéo thì **dừng phát** (phát và xem trước tranh nhau
  cùng một đồng hồ; Photos cũng dừng), trong lúc kéo thì tua với **dung sai 0,5 giây** — đủ lỏng để rơi vào
  khung khoá gần đó nên xem trước theo kịp ngón tay trên clip 4K — và khi nhả thì tua **chính xác** rồi phát
  tiếp nếu trước đó đang phát.

## 6. Cài đặt phát

- **Tốc độ, loop, tắt tiếng được nhớ** giữa các clip. Đổi tốc độ phải đặt **cả** giá trị mặc định **lẫn**
  giá trị đang chạy, và dùng thuật toán giữ cao độ để 2× không thành giọng chuột.
- **Loop mặc định BẬT**, và phải đọc theo kiểu phân biệt được "chưa chọn" với "đã tắt" — đọc kiểu thường trả
  về "tắt" cho khoá chưa ghi, và clip dừng chết ở khung cuối bị hiểu là viewer hỏng.
- Trạng thái loop báo bằng **hai glyph khác nhau, cùng màu trắng đặc**: vòng lặp, và vòng lặp có gạch chéo.
  Gạch chéo phải **tự vẽ** — bộ biểu tượng hệ thống không có biến thể gạch chéo cho glyph này; hai viên nang
  xoay 45°, kèm một viên tối nằm dưới làm rãnh khoét đúng cách hệ thống vẽ các biến thể gạch chéo.
- **Âm thanh chỉ giành quyền khi người dùng bật tiếng lần đầu**, và nhả lại khi tắt tiếng hoặc rời viewer —
  duyệt ảnh trong im lặng không được cướp nhạc đang phát của app khác. Đếm tham chiếu vì nhiều trang có thể
  cùng giữ.

## 7. Lưu khung ra thư viện

Nút riêng ở hàng dưới, icon khung ngắm — icon mũi tên tải xuống đọc như "tải cả clip xuống".

Trích khung ở **độ phân giải đầy đủ, dung sai bằng 0**, mã hoá HEIC chất lượng 0,95 (không được thì JPEG)
rồi lưu thành ảnh mới. Việc giải mã và mã hoá chạy **ngoài luồng chính** nên khung 4K không làm nghẽn giao
diện. Tên file gồm tên clip + phút, giây và số khung. Nhãn xác nhận hoặc lỗi tự tắt sau 1,4 / 2,6 giây.

## 8. Xem toàn màn

Nếu cửa sổ đang dọc thì **xoay riêng phần video và transport 90°** và hoán đổi bề rộng/chiều cao ngay trong
giao diện — máy vẫn dọc, **không gọi API xoay**, nên khoá xoay đang bật vẫn dùng được.

- Ẩn nút đóng, bảng thông tin, thanh đáy và status bar; dùng cạnh an toàn lớn nhất để né tai thỏ và vạch
  home; khoá lật trang, vuốt-mở-thông-tin và vuốt-đóng.
- Lớp video **chỉ gán lại player khi thực sự đổi** — gán lặp mỗi lần chrome hay lề đổi làm **rơi khung đang
  hiện**, tự nó là một nguồn nháy đen.
- Bật/tắt toàn màn thì mức phóng về vừa khung.

## 9. Tua từng khung

Hàng `Frame` (◀| `Frame` |▶) nằm **dưới** cụm transport, **chỉ hiện khi clip đang dừng** — tua khung là việc
người ta làm khi đã dừng để soi một khung, và lúc đang phát thì hai nút này không có trên màn.

Cắt video: [FS-02.04](04-actions-and-extras.md).

## 10. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
