# BD-03.04 — Tiến độ và chạy nền

`BD-03.04` · `Features/Library/LibraryModel.swift` · `App/BackgroundIndexService.swift`
· cập nhật 2026-09-22

**Một câu:** người dùng thấy gì trong lúc index, và index chạy tiếp thế nào khi app không ở trước mặt.

## 1. Quy tắc

- **Chỉ báo chỉ bật khi có việc thật**, trừ lượt do người dùng bấm.
- **Huỷ đổi giao diện ngay khung hình bấm**, không chờ pipeline cạn.
- **Tiến độ là số cộng dồn**, không đặt lại ở mỗi lượt chạy.
- **Mọi nhánh bị một điều kiện chặn đều phải ghi log** — im lặng chính là thứ khiến lỗi chốt không phân biệt
  được với lỗi mạng.
- **"Xong" nghĩa là không còn dòng nào chưa đọc**, không phải "một suất chạy đã hết".

## 2. Chỉ báo và huỷ

- Tách **cờ chống chạy trùng** (đúng bằng vòng đời một lượt chạy) khỏi **cờ giao diện**. Lượt **tự động**
  chỉ bật cờ giao diện khi pipeline báo "có việc thật" — có dòng để ghi, có ảnh để đọc, có dòng để xoá.
  Lượt **do người dùng bấm** bật ngay lúc bắt đầu: cú chạm không có phản hồi nào khác, mà đọc-lại-toàn-bộ
  mất vài giây quét trước lô đầu tiên.
- Trước đây mở app trên một thư viện đã index xong vẫn giữ "Indexing…" 7 giây trong khi bỏ qua cả 55.000
  ảnh — đúng triệu chứng "index xong rồi vẫn thấy đang index".
- **Huỷ**: xoá sạch mọi trạng thái hiển thị **trước**, rồi mới bảo pipeline dừng. Pipeline cần vài giây để
  cạn (tới 12 lượt đọc đang bay, mỗi lượt có cửa sổ đứng im riêng), nên chờ nó khiến vòng quay còn nguyên
  sau khi chạm — người dùng đọc là "bấm Cancel không ăn". Phần đuôi vẫn chạy ở nền: dòng đã đọc vẫn được
  lưu, lưới vẫn được nạp lại khi xong. Một cờ riêng **chặn mọi thông báo muộn** khỏi bật lại chỉ báo vừa tắt.
- **Yêu cầu của người dùng giành quyền trước lượt đang chạy**: huỷ lượt hiện tại, **bật cờ giao diện lạc
  quan ngay tại chỗ** (huỷ chỉ ngừng mở lượt đọc mới, còn lượt đang bay có thể ngồi trên cửa sổ 8 giây —
  chờ nó nhả rồi mới đổi giao diện là bắt người dùng chờ vài giây trước mắt), rồi chạy đúng lượt vừa bấm
  khi lượt cũ kết thúc. **Chỉ báo giữ nguyên xuyên qua lần bàn giao** — tắt một khung hình đọc thành "bấm
  không ăn".
- **Chốt chống chạy trùng phải nhả được kể cả khi lượt chạy không bao giờ kết thúc** (đồng hồ 45 giây): lệnh
  huỷ là **hợp tác**, nó không hứa lượt chạy sẽ dừng. Quan sát trên máy: một lượt đọc bị treo vĩnh viễn giữ
  chốt **suốt đời tiến trình**, nên mọi lần bấm sau đó dừng ở điều kiện chặn **trước khi** làm gì và **không
  ghi log gì**; hai nút trong Settings lại bị làm mờ theo cờ giao diện nên xám vĩnh viễn. Nhìn từ ngoài
  giống hệt lỗi mạng, và **chỉ tắt hẳn app mới thoát**. Nay quá 45 giây thì nhả chốt bằng tay, huỷ luôn tác
  vụ đó, rồi chạy tiếp đúng cái người dùng đã bấm. 45 giây để chắc chắn dài hơn thời gian một lô đang bay
  cạn hết.
- Mỗi lượt chạy mang một **số thứ tự**: một lượt đã bị bỏ rơi mà sau này mới kết thúc thì chỉ ghi một dòng
  log rồi thôi, **không đặt lại trạng thái của lượt đã thay nó**; các thông báo muộn cũng bị chặn bằng cùng
  số đó.

## 3. Tiến độ

- **Số cộng dồn**: đã xong = **số đã đọc xong trước lượt này** + số vừa đọc xong trong lượt; tổng = số ảnh
  trong thư viện. Mốc đầu được công bố **ngay đầu lượt** nên bảng tiến độ hiện đúng điểm bắt đầu, **không
  nhảy từ 0 và không tụt lùi** khi mở lại app.
- Đọc-lại-toàn-bộ thì bắt đầu từ 0. Ảnh đã xong nhưng bị sửa thì trừ khỏi mốc đầu để số vừa xong không vượt
  tổng.
- Báo tiến độ **cả khi bắt đầu đọc một ảnh lẫn khi đọc xong**, gộp lại tối đa 5 lần mỗi giây, kèm **danh
  sách tên file đang đọc song song** — một lô iCloud chậm mà chỉ báo theo số lượng thì bộ đếm đứng im hàng
  phút và người dùng tưởng treo.
- **Pha ghi nhanh và phần quét-bỏ-qua không báo tiến độ** — nếu báo thì thanh tiến độ nhảy lên 100% rồi tụt
  về 0 khi pha đọc EXIF bắt đầu. Lúc đó bảng chỉ ghi "Indexing…" không số.
- **Tốc độ và thời gian còn lại**: trung bình ảnh mỗi phút tính từ mẫu đầu của lượt (có mốc riêng nên lượt
  chạy tiếp chỉ đo phần việc thật). Dòng tóm tắt đặt **thời gian còn lại trước, tốc độ sau** — cái người
  dùng đang đợi là thời gian. Chữ "About" là **trung thực**: ước lượng tính từ trung bình cả lượt nên nó
  nhảy. Đơn vị viết đủ chữ **"photos and videos per minute"** vì cả hai đều được index.
- **Dòng trạng thái mạng**: loại kết nối · tốc độ hiện tại · **tổng đã tải từ iCloud trong lượt này**, và
  mọi con số **luôn có nhãn** — "45 MB" trần đứng cạnh một tốc độ sẽ bị đọc thành dung lượng file hay dung
  lượng máy đã chiếm. Tốc độ **ẩn khi bằng 0**; chưa tải gì thì nói bằng chữ thay vì in "0 KB".
- **Lời khuyên chỉ hiện khi có vấn đề**: "iCloud isn't responding — trying again in 42s" · "Your iPhone is
  warm — indexing slowed down to cool it" · "Indexing paused until your iPhone cools down" · "Low Power Mode
  is slowing indexing down". Lượt chạy bình thường **không có dòng nào**.
- Số liệu thô (mức nhiệt, số lượt đang bay, số lần đứng im) **chỉ đi vào log**, không màn nào hiện — chúng
  vô nghĩa với người dùng.
- **Chữ trên màn nói việc đang làm**: "Reading photo and video info · 13%", không phải "Indexing
  7625/54971". Từ "Indexing" chỉ còn ở nhãn nhỏ trên thanh công cụ và ở tên thiết lập. Bảng chi tiết:
  [FS-01.02](../../02-functional-spec/FS-01-library/02-navigation-and-condition-bar.md).

## 4. Tự thử lại khi iCloud không phục vụ

- Lượt chạy kết thúc mà **còn dòng chưa đọc** và mạng được phép → đặt lịch thử lại sau **30 giây cố định,
  không giãn dần** (một lần thử hỏng rất rẻ: cầu dao mở trong khoảng 12 lượt đọc; còn bắt kịp iCloud ngay
  khi nó hồi lại thì quan trọng hơn). Người dùng tự huỷ thì **không** đặt lịch.
- Đồng hồ đó dựng một thẻ **"iCloud not responding"** với **đếm ngược sống**, số ảnh đang chờ, nút **Retry
  Now** và **Use Cellular**.
- **Thẻ chỉ dựng khi iCloud đúng là thứ đang chờ**; lịch thử lại cho những dòng *chưa đọc* chạy **âm thầm**
  — không được dựng một thẻ nói iCloud hỏng khi iCloud không liên quan gì.
- Khi đồng hồ bắn: đang index thì thôi; mạng vừa thành không-được-phép (rời Wi-Fi mà chưa bật mạng di động)
  thì **hẹn lại cùng khoảng** thay vì chết — và **không** gọi đường chạy tiếp, vì đường đó luôn tải và sẽ
  đốt data trái thiết lập. Lượt mới bắt đầu thì huỷ đồng hồ đang treo.
- **Đổi đường mạng chính là tín hiệu iCloud có thể phục vụ lại**, nên nó huỷ chờ và thử ngay.
- Việc làm mới các con số trong Settings chạy **ngoài luồng giao diện** — ba câu đếm trên bảng 55.000 dòng
  đúng lúc mở màn là đúng lúc giao diện phải mượt.

## 5. Chạy nền

- Mỗi lượt chạy trước mặt giữ một **quyền chạy tiếp khi app rời màn** — thoát app giữa chừng thì lượt vẫn
  chạy thêm khoảng 30 giây. **Hết hạn thì phải xoá cờ giao diện ngay**: tác vụ bị treo cùng app nên phần
  dọn dẹp của nó có thể không chạy tới khi người dùng quay lại, khiến mở app lại thấy "Indexing…" của một
  lượt đã chết từ nhiều phút trước, rồi nó "tự dừng" ngay trước mắt.
- Một yêu cầu chạy bị chặn vì lượt cũ chưa kết thúc được **ghi nhớ** và chạy khi lượt đó xong — không thì
  index dừng hẳn tới lần mở app sau nữa.
- Tác vụ nền được đăng ký lúc app khởi động (cần khai trong cấu hình app) và chạy tiếp khi app bị treo hoặc
  bị tắt, vào lúc hệ thống thấy phù hợp.
- **Lượt nền dùng cùng chính sách mạng với lượt trước mặt.** Trước đây nó bị ghim ở "không dùng mạng", và
  trên một thư viện bật tối ưu dung lượng (~91% ảnh không còn bản gốc trên máy) thì nó **không đọc được gì
  cả** — trong khi đó chính là chỗ duy nhất hợp lý để trả hàng chục giờ tải iCloud.
- **Đặt lịch chạy tiếp khi còn dòng chưa đọc**, hoặc khi lượt vừa rồi **không chạy được**; và khai **cần
  mạng** khi việc còn lại là đọc từ iCloud (không khai thì hệ thống có thể cấp suất lúc không có mạng, và
  lượt đó chỉ để xác nhận lại là không đọc được gì).
- **Lượt trước mặt thắng lượt nền**: mọi lần từ chối vì "đang chạy" đều trả về **một tín hiệu nói rõ là
  chưa chạy**, để nơi gọi phải thử lại chứ không kết luận đã xong. Trước khi chạy, lượt trước mặt **huỷ**
  lượt nền rồi **chờ nó nhả** (hỏi lại mỗi 200ms, tối đa 30 giây); hết hạn hoặc thua tranh chấp thì hẹn lại
  sau 15 giây. Không mất gì vì dòng được ghi theo từng lô.
  - Vì sao cần: lượt nền buộc phải gọi thẳng pipeline (app có thể được hệ thống mở ở nền, chưa có màn nào),
    nên pipeline có thể đang bận với một lượt mà phần giao diện không hề biết. Khi đó nó từ chối và trả về
    một kết quả rỗng **nhìn y hệt "thư viện đã index đủ"**: không chỉ báo, không tiến độ, không thử lại.
    Đo trên máy: app ngồi im dù còn 42.544 dòng chưa đọc, tới khi người dùng tự bấm đọc lại.
- Suất nền **cũng dùng để nạp lại lời nhắc "Ngày này năm xưa"**, và điều kiện xin suất gồm cả việc lời nhắc
  có đang bật hay không — nếu không, một thư viện đã index xong hẳn sẽ **không bao giờ có suất nền nữa**,
  và lời nhắc chỉ còn được nạp khi người dùng mở app.
- Việc "còn dòng chưa đọc" mới là điều kiện đặt lịch, **không phải** việc còn điểm chạy tiếp: một lượt kết
  thúc-nhưng-chưa-đủ sẽ **xoá điểm đó**, nên bám vào điểm chạy tiếp thì cái đuôi dài không bao giờ có lượt nền.
- Hệ thống **không chạy tác vụ nền trên máy ảo**, và tự quyết thời điểm — không có gì đảm bảo ngay lập tức.

## 6. Tự chạy khi app trở lại

- Đặt ở **màn gốc** (luôn sống), không đặt ở màn Library: iOS 26 dựng nội dung từng tab một cách lười, nên
  mở app vào tab khác thì màn Library chưa tồn tại.
- Lần dựng đầu chờ **500ms** để Library kịp vẽ một khung hình tương tác được, trước khi việc đối chiếu thư
  viện tranh đĩa.
- Lệnh chạy là **an toàn khi gọi lặp**, nên gọi nhiều lần không sao.

## 7. Đo đạc

- Có dấu mốc đo hiệu năng cho ba giai đoạn: ghi nhanh, đọc EXIF, ghi database.
- Log sức khoẻ ghi **một dòng mỗi lô xong** (số ảnh, thời gian, tốc độ, và thời gian trung bình từng giai
  đoạn) — trung bình cả lượt che mất giai đoạn suy thoái giữa đường (máy nóng dần, iCloud bắt đầu đứng im).
- Ba dòng riêng tách **chi phí quét** khỏi **chi phí đọc thật**, và dòng kết thúc ghi rõ **lượt đó có bật
  chỉ báo hay không** cùng **nguyên nhân chạy** (mở app, người dùng bấm, đọc lại toàn bộ, tự thử lại, cắm
  sạc) — để truy được nguồn gốc của một chỉ báo lạ.

## 8. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
