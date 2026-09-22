# FS-03.01b — Các thông số chỉnh và Crop

`FS-03.01b` · `ShotDexKit` (render) · `Domain/Editing/EditorAdjustmentCatalog.swift`
· `Domain/Editing/UprightAnalyzer.swift` · test `UprightAnalyzerTests` · cập nhật 2026-09-22

**Một câu:** từng nhóm slider thật sự làm gì với bức ảnh, và khung cắt được chốt lúc nào.

Bố cục panel: [FS-03.01](01-scope-and-panel.md).

## 1. Quy tắc

- **Detail và Effects là slider hai chiều**, không phải 0…100: kéo phải làm việc hiển nhiên, kéo trái làm
  điều ngược lại.
- Thông số mới thêm vào công thức theo kiểu **"có thì đọc, không thì lấy mặc định"**, nên công thức cũ vẫn
  đọc được; và mặc định phải nằm trong trạng thái "chưa sửa gì" để nhãn Reset không sai.
- Phép vẽ tự viết mà **không chạy được thì trả về ảnh nguyên bản**, không làm app chết.
- Cái gì là **xấp xỉ thì ghi rõ là xấp xỉ** — không gọi nó là thứ nó không phải.

## 2. Các nhóm

| Nhóm | Thông số |
|---|---|
| LIGHT | Exposure · Contrast · Highlights · Shadows · Whites · Blacks · Brilliance · Brightness |
| COLOR | Temp · Tint · Vibrance · Saturation · **công tắc đen trắng** |
| DETAIL | Sharpen · Sharpen Radius · Sharpen Detail · Sharpen Masking · Definition · Lum NR · NR Detail · Color NR |
| EFFECTS | Texture · Clarity · Dehaze · Vignette (mức, tâm, độ mềm, độ tròn, giữ vùng sáng) · Grain (mức, cỡ hạt, độ thô) |
| OPTICS | khử viền tím · giảm quầng màu |
| GEO | xoay · phóng · dịch ngang/dọc · nắn phối cảnh dọc/ngang · **Upright** |

## 3. Hướng của Temp và Tint — hai chỗ đều phải đảo dấu

- **Ảnh thường**: bộ lọc của hệ thống nhận nhiệt độ theo **vật lý** (số càng cao càng **xanh**), ngược với
  slider nhiếp ảnh (kéo phải là **ấm**). Nên kéo phải phải **hạ** con số đưa vào, và trục còn lại phải lấy
  **dấu âm**.
- **Ảnh RAW**: giá trị đưa vào là "nhiệt độ mà bộ giải mã coi là trắng", nên **nâng nó lên = ảnh lạnh đi**.
  Lại phải **trừ** đi, và chặn trong khoảng hợp lệ.
- Các preset film giữ nguyên **giá trị cứng cũ** để **không đổi ảnh của những công thức đã lưu**.

## 4. Từng phép làm gì

- **Đen trắng** khử màu **ngay đầu chuỗi**, nên phần chỉnh tone chạy trên ảnh xám và phần Grade sau đó vẫn
  nhuộm hai đầu sáng-tối được.
- **Sharpen gom bốn nút kiểu Lightroom**: **Amount** làm nét theo độ sáng · **Radius** chồng thêm một lượt
  bán kính rộng · **Detail** thêm một lượt bán kính rất nhỏ để nhấn kết cấu mịn, **cường độ nhân với Amount**
  (không có Amount thì Detail vô hiệu) · **Masking** giới hạn toàn bộ việc làm nét **vào vùng rìa** bằng một
  bản đồ rìa mềm, nên kéo cao thì chỉ còn rìa mạnh nhất được làm nét. Đây là **xấp xỉ** cách Lightroom chống
  quầng sáng, **không phải** giải chập thật.
- **Khử nhiễu là ba slider một chiều** (FS-03.11 §6): **Lum NR** (0…1) khử nhiễu độ sáng · **NR Detail**
  (0…1, mặc định 0,5 như Detail 50 của Lightroom, mờ khi Lum NR = 0) giữ lại vân nằm trên ngưỡng nhiễu —
  phần bị lọc mất được làm mờ 1px (hạt nhiễu cỡ một pixel triệt tiêu, vân vài pixel còn lại) rồi cộng trả
  theo mức Detail; đầu vào sharpness của `CINoiseReduction` bỏ vì nó làm nét cả hạt · **Color NR** khử nhiễu màu mà ít làm mềm chi tiết.
  Nửa "kéo dương là thêm hạt" cũ đã bỏ: hạt ở Grain.
- **Khử nhiễu chạy trước mọi thứ làm nét** — Sharpen, Definition, Texture, Clarity đều là unsharp mask, chạy
  chúng trên ảnh còn nhiễu là khuếch đại nhiễu rồi mới xoá. Thứ tự là dữ liệu
  (`PhotoRenderService.detailPassOrder`) để test đọc được.
- **Texture** là làm nét bán kính nhỏ (1–2,5px); **Clarity** là bán kính lớn (8–28px), tức tương phản vùng
  trung gian. **Dehaze** kéo dương thì tăng tương phản và màu, hạ điểm đen, thêm một lượt bán kính lớn; kéo
  âm thì phủ mờ về xám sáng. **Xấp xỉ bằng các phép có sẵn, không phải thuật toán khử mù thật.**
- **Vignette**: khi độ tròn và phần giữ vùng sáng đều ở mặc định thì dùng phép có sẵn của hệ thống; khác đi
  thì chuyển sang một phép tự viết — khoảng cách tính theo một hình siêu-elip (độ tròn quyết định), chuyển
  tiếp mềm giữa tâm và mép, và **vùng sáng được giữ lại** theo mức người dùng chọn. Kéo âm thì **làm sáng
  góc** thay vì tối góc.
- **Grain** sinh nhiễu rồi khử màu và trộn vào ảnh, **tất định theo toạ độ pixel** nên nó **không "sôi"**
  khi kéo slider. Grain là một chiều — không có "grain âm".
- **Optics là xấp xỉ**: không có thư viện hồ sơ ống kính, không nhận biết rìa. Phần sửa méo ống kính thật sự
  vẫn nằm ở nhóm RAW.
- **Geo** chạy sau phần curve và trước film look, cắt và mask; ảnh được **kéo giãn mép ra** nên không lộ góc
  trong suốt. **Không quy đổi lại toạ độ của mask** — một phép nắn mạnh đi kèm mask có thể làm mask lệch;
  trường hợp thường (nắn mà không có mask) thì đúng.
- **Chưa làm**: Contrast của khử nhiễu độ sáng và Smoothness của khử nhiễu màu — chúng cần một bản đồ rìa riêng.

## 5. Upright

Một hàng chip **Level / Vertical / Full / Off** đặt **trên** các slider Geo — Upright là thứ *đặt* mấy
slider đó, nên đọc sau chúng là đọc đáp án trước câu hỏi.

Hai nửa tách hẳn: **phần hình học thuần** (tính góc nghiêng và độ nắn, có test, không cần ảnh) và **phần
tìm đường thẳng** từ pixel.

- Bộ tìm đường thẳng **tự viết**, chạy trên ảnh xám 256px. **Không dùng bộ thị giác của hệ thống**: nó không
  có phép tìm đoạn thẳng, còn phép tìm đường chân trời chỉ là một nửa của Level và không nói gì về phương
  dọc. Mỗi điểm ảnh chỉ bỏ phiếu trong khoảng ±4° quanh hướng của chính nó nên bảng phiếu sạch và cả lượt
  chạy mất vài mili-giây.
- **Level** = **trung vị có trọng số** của độ lệch, tính trên **cả** đường gần ngang **lẫn** đường gần dọc —
  một khung cửa nói về độ nghiêng đúng như một đường chân trời. Lệch quá 20° thì đó là đường chéo có thật
  trong ảnh, bỏ. Dùng **trung vị chứ không phải trung bình**, và **trọng số lấy căn bậc hai**: phiếu tỉ lệ
  với độ dài nên một cầu thang dài có thể nặng gấp sáu một bệ cửa sổ, nhưng nó **không phải sáu lần bằng
  chứng** — ba cạnh đồng thuận phải thắng một đường chéo đơn độc.
- **Vertical** = **chênh lệch** độ nghiêng giữa các đường gần dọc ở **nửa trái** và **nửa phải**; một phần
  ba ở giữa không bỏ phiếu (đường đi qua tâm nghiêng như nhau dù máy đứng bên nào). Nghiêng đều cả hai bên
  là việc của Level. Bằng chứng chỉ có một bên (một cái cây nghiêng) bị từ chối.
- **Phân tích trên ảnh gốc**, không phải bản đang xem: đo trên bản đã nắn là đo luôn phần vừa nắn rồi nắn
  tiếp — bấm lần hai là ảnh nghiêng thêm.
- Không tìm được đường thẳng nào thì **không đổi gì**, và hàng Upright tự ghi *"No straight lines to work
  from"* trong 3 giây. Không dùng thông báo hoàn tác của editor, vì thông báo đó có nút Undo mà ở đây không
  có gì để hoàn tác.

## 6. Crop

Tự do · nắn nghiêng −45…45° · xoay 90° · lật · và các tỉ lệ Free / Original / 1:1 / 4:3 / 3:2 / 16:9 / 4:5 / 9:16.

- Khung có viền mảnh, lưới chia ba, và **bốn núm tròn 18pt** (vùng chạm 44pt).
- **Cả ba cách chỉnh khung của Photos**: kéo góc · **kéo cạnh** (bốn thanh ở giữa mỗi cạnh, vùng chạm vươn
  ra ngoài khung nên bắt được đúng trên đường viền) · **kéo trong khung để dời**.
- Trong một cú kéo góc, **góc đối diện bị khoá làm điểm neo** và tỉ lệ tính từ neo đó, **không tính lại
  quanh tâm ở mỗi khung hình** — đó là nguyên nhân cũ làm cả khung trôi khỏi ảnh. Kéo cạnh khi đang khoá tỉ
  lệ thì trục còn lại co giãn quanh tâm rồi kẹp lại trong ảnh.
- Khi tab Crop mở, ảnh **thu nhỏ 30pt mỗi bên** để núm không nằm sát mép màn, và **mọi cử chỉ mức ảnh bị
  tắt** — để nguyên thì cử chỉ của khung dựng nuốt mất cú kéo núm, đúng cái làm khung cắt nhảy loạn.
- **Không còn nút Done.** Khung là bản nháp sống, nhưng **được chốt khi rời nhóm** hoặc khi bấm Save. Vào
  tab thì mở một phiên cắt (ghi lại khung cũ và độ sâu lịch sử), và mỗi cú kéo ghi thẳng vào công thức để
  bản xem trước sống. Phần huỷ phiên chỉ còn dùng cho các lối thoát khác. Dòng chú trong panel: *"The crop
  applies when you leave this tab or save."*
- **Reset Crop** đưa khung, độ nghiêng, xoay và lật về nguyên bản trong **một** bước.

## 7. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
