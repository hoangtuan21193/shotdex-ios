# FS-01.08 — Compare

`FS-01.08` · `Features/Library/CompareScreen.swift` · `Domain/Grid/CompareLayout.swift`
· test `CompareLayoutTests` · cập nhật 2026-09-22

**Một câu:** xem nhiều ảnh cạnh nhau ở **cùng một mức phóng**, và chạm để đánh dấu tấm sẽ xoá.

## 1. Quy tắc

- **Chạm ảnh = đánh dấu xoá, và đó là việc duy nhất một cú chạm ở đây làm.** Không có "chọn" trung tính —
  đứng trước 8 khung với một hàng vòng tròn rỗng thì câu hỏi đầu tiên là *"tôi đang tick cái được giữ hay
  cái bị xoá"*, và không cách xếp nút nào trả lời câu đó tốt bằng việc **không có câu đó**.
- Cùng cử chỉ, cùng màu đỏ, cùng biểu tượng thùng rác với lưới Duplicates — màn này thường mở ra từ đó.
- **Phóng và kéo luôn đồng bộ giữa mọi khung**, không có công tắc: nó là cách nhìn của cả phép so sánh.
- Khung **cao theo đúng tỉ lệ ảnh** — cắt theo một chiều cao chung tức là so sánh hai bản crop khác nhau.
- Chỉ cần ảnh tồn tại trong thư viện, **không cần có row metadata** — đòi metadata thì chọn video sẽ ra danh
  sách rỗng và màn hình đen.

## 2. Lối vào

- Chế độ chọn khi có **≥ 2 mục** (ảnh hoặc video), **không giới hạn trên**; thứ tự khung = thứ tự chọn.
- Từ Duplicates: dấu ghi thẳng về màn đó và nút đỏ gọi ngược lại nó
  ([FS-06.06](../FS-06-collections/06-duplicates.md)).
- Từ chế độ chọn thường: màn tự giữ dấu và tự xoá.

## 3. Bố cục

- **Một cách nhìn duy nhất**, tự co theo màn. Ba chế độ cũ (Survey, và Compare hai khung) **đã gỡ** — một
  cách nhìn tự co còn hơn ba cách người dùng phải chọn trước khi bắt đầu được; việc chúng làm nay do **nhiều
  cột + chạm-để-đánh-dấu** làm.
- **Số cột theo bề ngang** (toán thuần, có test): khung hẹp nhất **330pt**, tối đa **3 cột**, và **không
  bao giờ nhiều cột hơn số ảnh**. Thực tế: iPhone và Duo cover = 1 cột; iPad dọc = 2; iPad ngang = 3.
- **Mỗi cột là một chồng riêng, không phải một lưới**: lưới căn mọi hàng theo khung cao nhất nên dưới mỗi
  khung thấp là một khoảng trống. Khung được chia vào **cột đang ngắn nhất** nên mép dưới các cột xấp xỉ
  bằng nhau, và thứ tự chọn vẫn đọc xuôi.
- **Khung không có nút nào** — dưới ảnh chỉ một dòng `camera · tiêu cự · khẩu · tốc độ · ISO · dung lượng`.
  Nút trên từng khung tốn một dòng chiều cao mỗi khung, trên phone là gần một phần ba khung ảnh người ta mở
  màn này ra để nhìn.

## 4. Đánh dấu và xoá

- **Chưa đánh dấu**: một vòng tròn rỗng ở góc trên-phải — **chính nó là thứ nói khung bấm được**, vì màn
  không còn nút nào khác. **Đã đánh dấu**: biểu tượng thùng rác trắng trên đỏ + viền đỏ 3pt + ảnh mờ.
- Chạm khung ảnh đi qua cử chỉ của UIKit (nhường cho chạm-đôi để phóng) chứ không phải cử chỉ của SwiftUI —
  nội dung nằm trong một scroll view nên cử chỉ SwiftUI không bao giờ bắn. Dòng thông số là vùng chạm thứ
  hai (cho tấm đang phóng mà người dùng đang kéo).
- **Góc trên-phải là một chỗ trả lời "giờ làm gì"**: chưa đánh dấu gì thì là dòng chữ *"Tap a photo to mark
  it for deletion"*; có dấu thì là **một nút đỏ `Delete N Photos`** ngay chỗ đó. Hai thứ không bao giờ cùng lúc.
- **`Keep Only This`** nằm trong menu giữ-lâu của khung, đúng chỗ lưới Duplicates để lệnh cùng tên: đánh dấu
  mọi tấm *khác*, bỏ dấu chính nó.
- **Xác nhận**: đường chọn thường **không tự dựng hộp thoại** — một lệnh xoá cho cả mẻ và hộp thoại của hệ
  thống ("Delete 7 Photos?") *là* bước xác nhận. Đường Duplicates trả về **đúng id của nhóm đang mở**,
  không phải mọi dấu trên màn đó.

## 5. Đồng bộ phóng và kéo

- Bộ đồng bộ giữ các khung bằng **tham chiếu yếu** — khung cuộn khuất bị huỷ thì rụng khỏi nhóm thay vì bị
  đồng bộ mãi — và nhớ **trạng thái cuối của cử chỉ** (mức phóng + độ lệch **dạng tỉ lệ** của nội dung).
- Khung dựng sau phát lại trạng thái đó **sau một nhịp**, vì lúc mới dựng nó chưa có kích thước để nhân tỉ
  lệ. Nhờ vậy khung cuộn vào giữa lúc đang phóng hiện ra đã khớp sẵn.
- **Tách theo số ngón**: kéo **một ngón luôn cuộn cột khung**, **hai ngón mới phóng và kéo ảnh** (chỉ bật ở
  màn này; viewer vẫn một ngón). Bản cũ chỉ tắt kéo ở mức 1× rồi bật lại khi phóng — nghĩa là phóng vào để
  soi chi tiết cũng chính là lúc **danh sách hết cuộn được**.

## 6. Video và tải ảnh

- **Khung video** phát bằng player của hệ thống trong cùng khuôn cuộn như ảnh, nên video **phóng, kéo và
  tham gia đồng bộ** như ảnh. **Không tự phát, tắt tiếng mặc định** (hai video cạnh nhau không chọi tiếng);
  nút play/pause kính nhỏ ở góc dưới-phải; hết clip tự tua về đầu; dừng khi đóng màn.
- **Ảnh kéo ngay lúc mở**: mỗi khung xin song song một bản local nhanh và một bản chất lượng cao cỡ màn
  hình, cho phép mạng — iCloud giao bản cỡ màn hình chứ không phải file gốc. Khung chỉ chiếm 1/2–1/4 màn
  nên bản đó đã thừa nét.

## 7. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
