# FS-03.05b — Vẽ mask, tranh chấp chạm và zoom

`FS-03.05b` · `Features/Editing/EditorPaintTouchLayer.swift` · `Domain/Editing/PaintTouchArbiter.swift`
· `Domain/Editing/BrushStrokeRasterizer.swift` · test `PaintTouchArbiterTests` · cập nhật 2026-09-22

**Một câu:** một ngón luôn là vẽ, hai ngón luôn là zoom/pan — và cọ giữ nguyên cỡ trên màn hình ở mọi mức
phóng, nên zoom vào chính là cách tô được sợi mi.

## 1. Quy tắc

- **Một ngón = vẽ. Hai ngón = zoom + pan.** Không có chế độ zoom riêng.
- **Cỡ cọ là cỡ trên màn hình, không phải cỡ trên ảnh** — đúng cách Lightroom trên iOS làm.
- **Biên mềm tính theo từng nét**, không phải làm mờ cả mask một lần.
- **Một cú zoom không được tốn undo nào, và không được để lại vệt nào.**
- Ảnh luôn phải phủ **ít nhất một nửa khung** để còn thứ dưới ngón mà kéo lại.

## 2. Cỡ cọ theo màn hình

- Vòng cọ dưới ngón tay **giữ nguyên kích thước ở mọi mức zoom**; nét ghi lại thì chia theo mức phóng.
- **Chia cho zoom là chia _mọi_ số đo của con trỏ**, không riêng đường kính: hai độ dày nét viền, cỡ glyph
  của tẩy, bán kính đổ bóng. Chỉ chia đường kính là bug "brush zoom theo ảnh" — nét viền 1,5pt phẳng ở
  800% dày **12pt**, nuốt trọn vòng 8pt và biến cọ mảnh thành một cục trắng to dần theo mỗi cú pinch.
- Sàn 8pt đặt **trước** phép chia nên nó là sàn *trên màn hình*. Có test bất biến: đường kính × mức zoom
  không đổi ở 1× / 2× / 4× / 8×.
- Cỡ mặc định = **¼ cạnh ngắn**: nét đầu phải đọc là "tôi đang tô một vùng", không phải nét bút.
- Con trỏ có vòng ngoài = dấu chân cọ, vòng đứt trong = lõi cứng, glyph `−` khi đang tẩy.

## 3. Biên mềm theo từng nét

Bản cũ stroke cứng mọi đường rồi làm mờ **cả mask một lần**, bán kính lấy từ nét **to nhất**. Đúng khi mọi
nét cùng cỡ — và sai ngay khi không, mà **zoom chính là thứ làm chúng khác cỡ**.

Triệu chứng: vẽ ở 100%, zoom vào vẽ tiếp thì nét thứ hai **mờ hẳn**, và **biến mất hoàn toàn** ngay khi
thêm một nét to bên cạnh.

Nay mỗi nét tự mang biên của nó:

- Các vòng đồng tâm từ dấu chân đầy đủ thu vào lõi cứng, mỗi vòng cộng thêm một ít alpha; profile mượt để
  chỗ giáp lõi không thành nếp gấp.
- Số vòng theo bề rộng dải chuyển tính bằng pixel, **trần 20 vòng** để một mask 30 nét vẫn chỉ là một nắm
  hình tô.
- **Profile alpha chỉ phụ thuộc feather và flow, không phụ thuộc cỡ** — đó chính là thứ làm nét vẽ ở 800%
  đậm đúng bằng nét vẽ ở 100%. Có test.
- Hệ quả: dấu cọ **kết thúc đúng ở vòng ngoài** của con trỏ (bản làm mờ cũ tràn ra ngoài), và **tẩy cũng
  có biên mềm** — lõi vẫn xoá sạch hoàn toàn.
- Một bản rasterizer dùng chung cho cả preview lẫn lúc lưu; hai bản copy cũ đã trôi khác nhau ở cách tẩy
  hoà trộn và ở chỗ đặt sàn 1px.

## 4. Touch nào là nét, touch nào là zoom

Bản "vẽ ngay ở touch đầu" không dùng được trên máy thật vì bốn chuyện:

1. Hai ngón **không bao giờ** chạm cùng lúc (lệch 20–60 ms) → mỗi cú pinch vẽ một dấu rồi phải rollback.
2. Nhả hai ngón cũng lệch → ngón còn lại trượt vài điểm là vẽ.
3. Ngón chạm thêm giữa cú pan trông giống hệt ngón đầu của một nét mới.
4. Rollback sạch một nét dài chỉ vì cạnh tay chạm nhẹ thì mất công tô.

Bốn luật của trọng tài (thuần, có test):

| # | Luật |
|---|---|
| 1 | Chạm xuống khi đã có ngón khác trên lớp → **bỏ qua**; số ngón đếm từ chính lớp đó, không từ sự kiện |
| 2 | **Chốt**: thấy ≥ 2 ngón một lần thì mọi touch sau đều bỏ qua **cho tới khi nhả hết** |
| 3 | **Cửa sổ xác nhận 0,08 s hoặc 4pt**: nét nằm chờ, buffer điểm, chưa chạm recipe — nên pinch bị loại **không để lại vệt nào và không tốn undo**. Nhả tay luôn xác nhận (ngón đã nhả không thể thành pinch) nên **chạm một cái vẫn ra đúng một dấu** |
| 4 | **Nghỉ 0,25 s** sau khi multi-touch nhả hết |

- Không có timer nào: đo bằng dấu thời gian của chính touch, và sự kiện kế tiếp (60–120 Hz) tự tới sau hạn.
- Ngón thứ hai chen vào giữa một nét đã đi ≥ 8pt → **giữ nét**; ngắn hơn → **bỏ nét**.
- Cuộc gọi tới (hệ thống huỷ gesture) theo cùng luật.
- **Nét bị huỷ phải rollback cả entry history** mà nó vừa mở — chỉ pop khi đỉnh stack đúng là nó, nên một
  edit thật không bao giờ bị nuốt. Gradient đang kéo thì chỉ đóng nhóm thay đổi: dời một hình là thứ nhìn
  thấy được và một undo là đủ.

## 5. Vì sao lớp vẽ là UIKit

Dùng cử chỉ kéo của SwiftUI ở đây cho **ba bug thật**:

1. Nó theo *mọi* số ngón nên ngón đầu của cú pinch mở luôn một nét — zoom xong ảnh dính một dấu cọ.
2. Cử chỉ của view con được ưu tiên hơn pinch của view cha nên hai ngón **không zoom được gì**.
3. Gesture bị hệ thống huỷ thì **không báo kết thúc**, nên trạng thái kẹt ở "đang vẽ" và mọi touch sau nối
   vào một nét đã bỏ — đúng hiện tượng "pinch xong brush không ăn nữa".

Lớp quan sát chạm **không nhận diện gì cả**, chỉ báo touch: không tranh nhận diện thì không có trọng tài
nào để thua, và một bộ nhận diện đã thất bại sẽ bị hệ thống ngắt luồng touch — mất đúng phần ghi sổ cần để
biết một ngón vừa chen vào cú pan hai ngón.

## 6. Zoom và pan

- **Zoom tối đa 10×** (6× → 8× như trần của Lightroom → 10× theo yêu cầu). Cọ là cỡ màn hình nên mỗi nấc
  zoom là một cỡ cọ mảnh hơn: ở 10×, nét nhỏ nhất ghi lại chỉ còn **0,2% cạnh ngắn**.
- Ảnh thì hết nét trước mốc đó — khung dừng ở **4800px**, trên điện thoại khoảng 400%. Quá mức đó là
  **phóng to chứ không phải giải thêm chi tiết**, vẫn đáng đổi vì thứ đang ngắm là *mask*, không phải hạt ảnh.
- **Pinch neo vào chính hai ngón, không vào tâm khung** (có test round-trip): phóng quanh tâm thì pinch mở
  ở một góc ảnh làm đúng chỗ đang soi chạy khỏi màn hình — mà tìm lại chính là phần lớn công việc khi lý
  do zoom là tô một chi tiết nhỏ.
- Offset tính **theo bước, từ frame trước**, không dựng lại từ đầu gesture — dựng lại sẽ đè mất phần pan
  hai ngón và **ảnh không pan được nữa khi đang zoom**.
- **Pan bị chặn** để ảnh luôn phủ ít nhất nửa khung trên cả hai trục (có test sweep). Không chặn thì fling
  một cái là ảnh chỉ còn thòi ra một mẩu ở mép. Clamp áp cho pan một ngón, pan hai ngón, **và mỗi lần đổi
  zoom** (pinch nhỏ lại làm ảnh co về tâm nên offset đang hợp lệ có thể thành phạm luật).
- Trục bị letterbox mà ảnh nhỏ hơn nửa khung (một panorama) chỉ trượt tới đúng mép, không bị ghim cứng.
- **Số phần trăm zoom ở góc trên-trái khung**, accent trong lúc pinch. Nó thay pill `1:1` cố định ở góc
  dưới-trái — thứ nói sai ở mọi mức khác 100% và lại nằm ở góc người ta không nhìn.
- Nhả tay mà vẫn còn zoom thì pill **đổi thành nút Fit**: pinch nhả hết về đúng 100% là việc khó làm, và
  trong công cụ vẽ thì chạm đôi là hai dấu cọ nên **không còn đường nào khác về 100%**.
- Rời mask hoặc đổi tab thì reset zoom.

## 7. Hai cử chỉ của view cha bị tắt khi có lớp vẽ

- **Giữ-để-xem-ảnh-gốc**: ngón đặt yên trên ảnh trong công cụ vẽ là đầu một nét, không phải yêu cầu xem
  bản gốc — và bản cũ nháy ảnh gốc rồi nhả ra vẫn để lại một dấu.
- **Chạm đôi**: tắt, **trừ khi đang xem tràn viền** vì lúc đó nó là đường ra duy nhất. Hai dấu cọ từ hai cú
  chạm thì **giữ** — trong một công cụ cọ, chạm hai lần đúng nghĩa là hai dấu.

## 8. Layout ảnh độc lập với kích thước bitmap

- Khung ảnh tính từ **tỉ lệ**, không từ kích thước bitmap: cùng một recipe render lại ở size khác làm ảnh
  — và mọi guide, nét trên nó — dịch một phần nhỏ của point; ở 800% phần nhỏ đó nhân 8 và đọc ra thành
  "ảnh bị nhảy".
- Tỉ lệ chỉ cập nhật khi **hình dạng** đổi (nguồn, khung crop, straighten, xoay, lật), không đổi khi chỉ
  độ phân giải đổi.
- Còn lại một cú "pop" độ nét khi khung cuối cùng tới ở zoom sâu — cách sửa thật là render riêng vùng đang
  xem, **chưa làm**.

## 9. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
