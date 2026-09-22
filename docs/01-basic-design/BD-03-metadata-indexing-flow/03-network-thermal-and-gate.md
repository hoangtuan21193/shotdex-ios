# BD-03.03 — Mạng, iCloud, nhiệt và quyền ưu tiên

`BD-03.03` · `Data/Sources/ExifReader.swift` · `IndexTrafficMonitor` · `Domain/Indexing/IndexInteractionGate.swift`
· test `IndexNetworkStatusTests` · `IndexThermalPolicyTests` · `IndexInteractionGateTests` · cập nhật 2026-09-22

**Một câu:** index sống chung với iCloud chập chờn, máy nóng, pin yếu và **một người đang xem ảnh**.

## 1. Quy tắc

- **Tối đa 4 lượt tải iCloud cùng lúc trên toàn app** (kể cả lượt đọc một ảnh của viewer). Đọc trên máy
  không giới hạn.
- **Đồng hồ canh đo tiến độ TẢI, không đo tiến độ nhận khối dữ liệu.**
- Thời hạn là **cửa sổ không-có-tiến-triển**, không phải một hạn chót cứng.
- **Cầu dao mở thì dừng cả lượt và chờ**, không đi tiếp để dán nhãn "chờ iCloud" cho cả thư viện.
- Quyết định "có được dùng mạng không" được **hỏi lại ở mỗi lô**, không chốt một lần đầu lượt.
- **Mọi chỗ chờ đều phải huỷ được** — chờ suất tải, chờ nghỉ, chờ cầu dao.

## 2. Chính sách mạng

| Đường mạng | Được tải từ iCloud |
|---|---|
| Wi-Fi (hệ thống không coi là tốn tiền) | luôn |
| Mạng di động | chỉ khi bật "Use Cellular Data for Indexing" (mặc định tắt) |
| Lượt do người dùng bấm chạy tiếp hoặc thử lại | luôn |

- Ở mạng di động chưa bật: **chỉ tạm dừng phần tải iCloud**, việc đọc dữ liệu trên máy vẫn chạy (không tốn
  data). Dòng trạng thái đổi thành "Paused — waiting for Wi-Fi", cập nhật sống mỗi giây.
- Lượt chạy chỉ-trên-máy kết thúc mà còn ảnh chờ iCloud → giữ một thẻ cố định **"Indexing paused — waiting
  for Wi-Fi"**.
- **Số ảnh "đang chờ iCloud" chỉ đếm đúng loại đó, không gộp ảnh lỗi**: mọi giao diện nói về mạng đều đọc
  con số này. Ảnh lỗi là lỗi **không phải mạng** và có kết cục xác định, nên nó **không bao giờ** được bật
  hộp thoại "iCloud không phản hồi". Bản cũ đếm gộp nên một file hỏng trên máy làm hộp thoại đó bật lại mỗi
  30 giây.
- **Tự chạy tiếp khi mạng đổi**: khi chuyển từ "đang tạm dừng" sang "được phép" và còn việc dở thì tự chạy
  tiếp — và **chỉ ở đúng lần chuyển đó**, để không cướp lượt chạy đầu tiên lúc mở app.
- Trước khi hiện trạng thái, app **chờ hệ thống báo đường mạng lần đầu**, nên chỉ báo nói đúng Wi-Fi hay
  mạng di động ngay từ khung hình đầu thay vì mặc định coi là tốn tiền.

## 3. Đồng hồ canh và giới hạn tải

| Tham số | Giá trị |
|---|---|
| Cửa sổ đứng im — đọc trên máy | 10 giây |
| Cửa sổ đứng im — tải mạng | 8 giây |
| Trần tuyệt đối cho một lượt tải | 120 giây |
| Số lượt tải iCloud cùng lúc | **4**, xếp hàng vào trước ra trước |

- **Vì sao đo tiến độ tải**: hệ thống giao dữ liệu iCloud theo **khối 1 MB**, nên trước khi trọn 1 MB về thì
  lượt đọc **không nhận được byte nào** và trông như đứng im. Đo trên máy ở đoạn mạng chậm (~28 KB/s): 1 MB
  cần ~36 giây, nên cửa sổ 8 giây giết lượt đọc ở giây thứ 8 **mọi lần** — dưới ~128 KB/s thì **không ảnh
  nào có thể đọc xong**, và mỗi lần bị giết là phần đã tải bị bỏ. Đo lại cùng đoạn mạng sau khi đổi cách
  đo: **52 ảnh / 174 giây, gấp ~10 lần, không lần nào đứng im, không lần nào mở cầu dao.**
- **Trần 120 giây** tồn tại vì một lượt còn nhích thì đồng hồ canh không bao giờ giết nó — đó là thứ ngăn
  một lượt tải bò chậm giữ mãi một trong bốn suất.
- **Vì sao giữ 4 suất**: đã thử 8 trên máy thật. Số byte mỗi giây **không tăng**, chỉ chia cùng một cái ống
  thành 8 dòng chậm gấp đôi, và tỉ lệ đọc được **tụt** (200/200 → 117/200); số yêu cầu leo lên trong khi
  byte bò — dịch vụ của hệ thống tự giảm tốc khi bị hỏi quá rộng. **Không có lần đứng im nào được ghi**, nên
  đồng hồ canh mù với dạng hỏng này; dấu hiệu duy nhất là lượt đọc về mà chưa đọc được gì, lại còn phải tải
  lại từ đầu ở lượt sau. Chỉ nâng lại khi **đo được** byte mỗi giây thật sự tăng.
- Sau khi lấy được suất, phải **kiểm lại cầu dao** (nó có thể đã mở trong lúc xếp hàng) và **chờ hết kỳ
  nghỉ** — **ngủ trong lúc vẫn giữ suất là chủ đích**: nó bóp cả làn mạng để dịch vụ kia có chỗ thở.
- Cả việc chờ suất lẫn chờ nghỉ đều **phải bị đánh thức khi huỷ**. Bản cũ chờ bằng một cơ chế không nhận
  tín hiệu huỷ, còn vòng chờ nghỉ thì **nuốt lỗi**, nên khi bị huỷ nó **quay nóng vô hạn trong lúc vẫn giữ
  suất**. Hai chỗ đó cùng khiến lượt chạy không bao giờ kết thúc — nguồn thật của lỗi chốt ở [04](04-progress-and-background.md).

## 4. Cầu dao mạng

| Tham số | Giá trị |
|---|---|
| Mở khi | **≥ 10 lần đứng im trong 12 lượt gần nhất** (cửa sổ trượt) |
| Chờ | **30 giây cố định, không giãn dần** |
| Thử lại | đúng **một** lượt thăm dò; quyền thăm dò tự hết hạn sau 15 giây |
| Nghỉ sau mỗi lần đứng im | 2 giây |
| Số lần mở tối đa mỗi lượt chạy | 3 |

- **Cửa sổ trượt chứ không đếm liên tiếp**: iCloud nghẹt vẫn rỉ ra vài byte lẻ, và một lượt may mắn **không
  được phép bảo lãnh cho cả đường ống đã chết**. Bản đếm-liên-tiếp không bao giờ mở, nên lượt chạy treo ở
  0 KB/s vô hạn mà không tạm dừng, không báo gì.
- Mở cầu dao thì lượt đọc iCloud tiếp theo **trả lời ngay là chưa tải được**. Pipeline **chờ hết 30 giây**
  thay vì đi tiếp: đi tiếp thì trong 30 giây đó mỗi ảnh chỉ tốn một lần đọc-trên-máy-thất-bại cộng một lần
  bị từ chối tức thì, tức là **~300 ảnh mỗi giây** — nên **một** kỳ chờ đủ để dán nhãn "chờ iCloud" cho
  ~9.000 dòng **mà chưa hề gửi một yêu cầu nào**.
- Cap 3 lần vì nếu iCloud chết hẳn thì lượt chạy phải kết thúc để nhường cho vòng tự thử lại 30 giây — cái
  đó có thẻ và có đồng hồ đếm ngược, còn giữ chỉ báo sáng vô hạn thì không.
- **Byte về trong lúc đang chờ bị bỏ qua**: có thể còn tới 6 lượt đang bay lúc cầu dao mở, và một lượt nhả
  bộ đệm muộn mà đóng cầu dao thì kỳ nghỉ vô nghĩa. Mọi thứ đặt lại ở đầu mỗi lượt chạy.
- Trạng thái chết quan sát được trên máy là **lỗi xác thực tài khoản ở tầng hệ điều hành**: dịch vụ treo im
  lặng mọi yêu cầu, đứng im đúng bằng cửa sổ, không trả về lỗi nào, và cả lượt chạy 0 byte từ lượt đọc đầu
  tiên. Nó có thể kéo dài nhiều phút; app sống chung bằng vòng thăm dò và thử lại.
- **Log gom về một chỗ**: bắt đầu lượt · mỗi lần đứng im · cầu dao mở/mở lại/đóng · mã lỗi khi mạng trả lỗi
  thật (hiếm — treo mới là chủ đạo, nên một lỗi trả về là tín hiệu quý) · ảnh chụp tình trạng mỗi 10 giây ·
  tổng kết cuối lượt. Nhờ vậy cả diễn biến một lượt suy thoái đọc được **ở một chỗ**.

## 5. Nhiệt và tiết kiệm pin

| Trạng thái nhiệt | Đọc song song | Nghỉ giữa lô |
|---|---|---|
| mát | 12 | 0 giây |
| ấm | 6 | 3 giây |
| nóng | 3 | 10 giây |
| rất nóng | 2 | 10 giây + **ngừng hẳn việc mở lượt đọc mới** cho tới khi nguội |

- Chế độ tiết kiệm pin siết thêm về mức "ấm" và ép nghỉ tối thiểu 3 giây; nếu máy còn nóng hơn thế thì mức
  nóng thắng.
- Số lượt đọc song song được **tính lại ở mỗi lần một lượt đọc xong**, không phải mỗi lô: máy nóng lên giữa
  lô thì lượt xong không được thay (fan-out **tự co**, không giết lượt đang bay), máy nguội thì tăng lại.
  Luôn mở ít nhất một lượt khi không còn lượt nào đang bay, để nhóm việc không bao giờ đói.
- Bỏ qua kỳ nghỉ trước lô đầu tiên (máy mát thì bắt đầu ngay); ngủ theo nhịp 250ms nên **huỷ dính trong một
  nhịp**.
- Trạng thái nhiệt và pin đọc qua một chỗ **thay được khi test**, nên chính sách là hàm thuần, kiểm được, và
  không cần theo dõi thông báo hệ thống — nó đã được hỏi lại ở mọi điểm dừng.
- Ở tầng trên: vào chế độ tiết kiệm pin thì **dừng** lượt đang chạy và chặn mọi lượt tự động; người dùng
  vẫn bấm chạy tay được; **cắm sạc thì tự chạy tiếp** — ngoại lệ tự-chạy duy nhất.

## 6. Nhường băng thông cho người đang xem ảnh

- Lượt tải iCloud của index và lượt tải ảnh của viewer **đi chung một dịch vụ hệ thống**. Không có cổng
  nhường, một ảnh chỉ-có-trên-mây vừa được chạm phải xếp sau hàng chục lượt tải của index — **10–20 phút**.
- Cổng là một bộ đếm tham chiếu cộng một mốc hoạt động (thuần, có test): viewer giữ một lượt khi mở, và
  **chạm vào cổng** mỗi lần đổi trang và mỗi nhịp tải.
- Pipeline hỏi cổng mỗi 250ms ở đầu mỗi lô và trước mỗi lần mở lượt đọc thay thế; đang nhường thì **ngừng
  mở lượt mới**, còn các lượt đang bay tự cạn trong vài giây (dừng sớm khi đã có metadata, hoặc hết cửa sổ
  đứng im).
- **Tự bỏ nhường sau 90 giây không hoạt động** — một bộ đếm bị rò không được treo index vĩnh viễn; nếu đang
  tải thật thì nhịp tiến độ giữ cho việc nhường còn sống. Vòng chờ thoát ngay khi huỷ.
- Lượt chạy nền không bị ảnh hưởng; và **lượt đọc một ảnh của viewer được miễn** — nó chính là nhu cầu của
  người đang xem.

## 7. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
