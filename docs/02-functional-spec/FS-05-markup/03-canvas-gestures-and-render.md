# FS-05.03 — Cử chỉ, render và preset

`FS-05.03` · `Features/Editing/EditorOverlayGuides.swift` · `ShotDexKit` (ghép lớp)
· `Domain/Editing/SignaturePresetStore.swift` · cập nhật 2026-09-24

**Một câu:** khi có lớp đang chọn, chính khung dựng vẽ nó live — và đó là điều kiện để kéo một dòng chữ
không phải chạy lại cả chuỗi xử lý ảnh.

## 1. Quy tắc

- Có lớp đang chọn → render **bỏ hẳn phần markup**, khung dựng tự vẽ.
- Bản vẽ sống gọi **đúng bộ raster của renderer**, không dựng lại bằng thành phần chữ của SwiftUI.
- **Không có tay nắm.** Một ngón kéo = di chuyển, hai ngón = đổi cỡ và xoay.
- **Cử chỉ markup không được chạy vòng render.**
- Lớp markup ghép **cuối cùng**, sau khi ảnh đã thu về kích thước xuất.

## 2. Vì sao không có tay nắm

Đã thử rồi bỏ:

- Ở cỡ một dòng chữ bình thường, một nút 22pt ở góc **che kín chính chữ** nó đang chỉnh.
- Hai nút cách nhau ~20pt mà vùng chạm là 44pt → với tay vào "đổi cỡ" rất hay bắt phải "xoay" (đó chính là
  cảm giác "phóng to chữ bị ngược").
- Khi lớp đã xoay, độ dịch của tay nắm được báo **theo hệ toạ độ đã xoay**, nên đổi cỡ hay dời một dòng chữ
  nghiêng đều kéo sai hướng.

Thay bằng cử chỉ kiểu công cụ chữ của Snapseed, cộng slider cỡ và xoay trong panel cho chính xác.

## 3. Cử chỉ trên ảnh

| Cử chỉ | Kết quả |
|---|---|
| Chạm một lớp | **chọn** (hiện khung ngay từ lúc ngón chạm xuống) |
| Kéo quá 4pt trúng lớp | **nắm lớp đó và dời ngay từ mm đầu**, kể cả lớp **chưa** được chọn |
| Hai ngón bất kỳ đâu trên ảnh | đổi cỡ + xoay |
| Chạm chỗ trống (trên ảnh **hoặc** vùng trống của danh sách) | bỏ chọn |

- Vùng chạm để kéo được dựng cho **mọi** lớp — chọn hay chưa. Dựng cho cả lớp đang chọn cốt để **danh tính
  không đổi**: nếu chỉ dựng cho lớp chưa chọn thì lúc kéo nó tự được chọn, vùng chạm bị gỡ khỏi màn và **cử
  chỉ đang chạy bị huỷ**.
- Vùng chạm là hộp bao **theo trục màn hình** của lớp đã xoay (không xoay theo lớp, đúng lý do ở §2), sàn
  44pt để chữ nhỏ vẫn nắm được.
- Dời lớp đặt **tâm tuyệt đối** tính từ điểm bắt đầu cố định, không cộng dồn từng khung.
- **Hút vào mốc**: tâm ±0,012 mỗi trục và mỗi 45° khi xoay, kèm haptic; đường gióng chạy ngang cả ảnh chỉ
  hiện **khi đang hút**.
- **Hai ngón nhận trên cả khung ảnh**, không chỉ trong hộp của lớp: lớp nhận hai ngón phủ hết vùng ảnh và
  nằm **dưới** vùng chạm lẫn khung chọn, nên một ngón vẫn chọn và kéo được. Gắn vào chính hộp là sai — một
  dòng chữ thường **hẹp hơn khoảng cách hai đầu ngón tay**, nên bắt buộc pinch phải rơi vào trong nó thì
  gần như không đổi cỡ được.
- Phóng và xoay chạy **song song**, và mỗi cái kết thúc độc lập, nên nhóm hoàn tác chỉ đóng khi **cả hai**
  đã rảnh — nhả phóng trước xoay một khung mà đóng luôn thì một cử chỉ thành hai bước lịch sử.
- Chọn một lớp thì **tắt cử chỉ mức ảnh** — không thêm một trọng tài thứ ba; đây đúng là việc chế độ cắt ảnh
  đang làm, và bỏ chọn chỉ cách một cú chạm khi cần phóng lại.
- **Khung chọn do chính bản vẽ sống vẽ**, dưới đúng phép đặt chữ — vẽ bằng một lớp riêng thì nó lệch khỏi
  chữ, vì chỉ số đo của thư viện chữ mới đặt đúng.

## 4. Chọn là mở thuộc tính

Lớp đang chọn (trên ảnh hoặc trên dải) **luôn** là lớp mà các hàng trong panel đang chỉnh — không còn trạng thái
"chọn nhưng chưa mở chi tiết", vì panel không còn danh sách để quay về.

- **Dải lớp** là nơi chọn, đổi thứ tự, ẩn/hiện, xoá (qua `⋯`). **Ảnh** là nơi chọn và thao tác. Chọn trên
  ảnh thì dải tự cuộn tới thumbnail của lớp đó.
- Chạm vùng trống trên ảnh: **khung chọn trên ảnh mất, panel vẫn giữ lớp vừa chọn** — panel không nhảy.
- Thêm ảnh hoặc dán preset thì đặt trên ảnh luôn; thêm chữ thì mở thẳng ô gõ trên ảnh.

## 5. Không chạy vòng render

Nhóm thay đổi của markup cố ý **không** dùng chung cơ chế với slider:

- Cơ chế đó kích một lượt render tương tác 768px, và nếu mỗi khung kéo đều xin render thì bản xem trước nhảy
  qua lại giữa 768 và 2400 suốt cú kéo — đó chính là **nháy và giật** khi di chuyển chữ.
- Vì khi có lớp đang chọn thì bản xem trước đã render **không có** markup, ảnh nướng sẵn vẫn đúng — ảnh
  không đổi khi chữ dịch. Nên phần cập nhật chỉ ghi lịch sử **một lần cho cả cử chỉ** rồi **dừng trước khi
  xin render**. Render chỉ chạy lại lúc chọn hoặc bỏ chọn (tức lúc nướng vào hoặc lấy ra).

## 6. Cache

Mỗi khung kéo, panel + khung chọn + bản vẽ sống đều hỏi font và đo chữ — mà giải một kiểu chữ theo tên tốn
hàng chục mili-giây, còn hỏi "file ảnh này còn không" là một lần chạm đĩa **trên luồng chính**.

- Cache font giữ một kiểu chữ ở cỡ tham chiếu rồi sao ra cỡ cần dùng.
- Cache đo chữ khoá theo mọi thứ đổi **kích thước**, và cố ý **không** gồm vị trí, góc xoay hay độ mờ — nhờ
  vậy một cú kéo di chuyển là **trúng cache ở mọi khung**.
- Kho ảnh overlay cache luôn cả việc file còn tồn tại hay không.

## 7. Thứ tự render

Markup ghép **cuối cùng, sau khi ảnh đã thu về kích thước xuất và dời về gốc toạ độ**:

- không thứ gì trong chuỗi tone/màu/film được nhuộm lên chữ;
- cắt và nắn ảnh không được làm méo nó;
- và một lượt thu nhỏ *sau* đó sẽ làm mềm đúng những cạnh khiến chữ nhỏ đọc được.

Vì thế nó **không** nằm trong nhánh render dùng lại, mà ở đường render chính (mọi đường ghi file) và ở bản
xem trước **chỉ cho ảnh hiển thị** — bản sạch là thứ ống hút màu lấy mẫu và histogram dựng từ đó, một dòng
credit trắng không phải mức phơi sáng của khung ảnh.

Mọi lớp được vẽ vào **một** ảnh trung gian rồi ghép một lần. Live Photo có đường riêng: mọi khung cùng kích
thước nên raster **một lần** rồi ghép lại, cache có khoá vì bộ dựng khung chạy song song.

## 8. Preset (watermark)

Nhãn giao diện là "Presets" / "Save Preset"; lưu dạng JSON trong cài đặt của app.

- Lưu **cả cụm lớp** — watermark thật thường là logo + một dòng credit, hai thứ chỉ có nghĩa khi đi cùng.
- Dán thì **thêm vào** và cấp id mới: dán preset không được âm thầm xoá chữ đang có, và dán hai lần thì
  hoàn tác phải phân biệt được.
- Ảnh của lớp nằm trong thư mục riêng của app, **không nhúng byte vào công thức** — công thức phải vừa trong
  phần dữ liệu chỉnh sửa gắn theo ảnh.
- Chọn ảnh qua ô chọn của hệ thống với ba yêu cầu: **một ảnh**, **bản hiện tại**, và **xin dữ liệu PNG theo
  đúng định dạng** rồi mới mã hoá lại. Xin "bản tương thích" sẽ chuyển sang JPEG, còn xin theo kích thước
  mục tiêu sẽ trả về một ảnh đã làm bẹt nền — **cả hai biến logo thành một ô trắng**.
- Chọn xong thì ô chọn **đóng ngay** và editor bật vòng quay **"Adding image…"** suốt lúc giải mã, mã hoá
  lại và lưu — một ảnh PNG full-res mất một nhịp, không có vòng quay sẽ đọc như **đơ**.
- **Không tự dọn ảnh thừa**: một công thức đã gắn vào ảnh sống lâu hơn preset tạo ra nó, nên "không preset
  nào nhắc tới ảnh này" **không** chứng minh nó vô dụng. Chỉ khi xoá một preset mới xoá những ảnh không
  preset nào khác dùng. Giữ thừa tốn vài kilobyte; xoá oan tốn watermark của một ảnh đã lưu.

## 9. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
