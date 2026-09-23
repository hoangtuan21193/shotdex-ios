# FS-03.05 — Mask cục bộ

`FS-03.05` · `Features/Editing/EditorMaskPanels.swift` · `EditorMaskGuides.swift`
· `ShotDexKit` (matte và overlay) · cập nhật 2026-09-22

**Một câu:** một ảnh có nhiều mask, mỗi mask có đủ bộ chỉnh riêng — và hình dạng của nó luôn nhìn thấy
được, sờ được.

Vẽ, tranh chấp chạm và zoom: [FS-03.05b](05b-mask-painting-and-zoom.md).

## 1. Quy tắc

- **UI mask có đúng hai tầng**: danh sách, và chỉnh một mask. Không có tầng thứ ba.
- Mask có **đủ bộ chỉnh chuẩn** (Light/Color/Detail/Effects). Các control decode RAW là **mức nguồn** nên
  chỉ có ở Adjust toàn cục.
- **Overlay đỏ bật theo việc người dùng đang làm**, không theo timer.
- **Không có nút zoom riêng** — pinch đã zoom xuyên qua lớp vẽ; một mode toggle là thêm một thứ phải học
  cho cử chỉ ai cũng thử.
- Nét vẽ lưu theo toạ độ chuẩn hoá của ảnh **sau crop**, nên preview và bản full-res dùng chung một recipe.

## 2. Tầng danh sách

- Tiêu đề + một hành động chính **＋ New Mask**.
- Mỗi hàng: thumbnail 42pt vẽ **matte kiểu Lightroom — hình mask màu đỏ trên nền xám phẳng, KHÔNG có ảnh
  thật phía dưới** (đỏ đè lên ảnh ở 42pt thì không đọc nổi hình mask), tên, phụ đề tóm tắt chỉnh sửa, nút
  ẩn/hiện, chevron, vuốt để xoá, context menu Duplicate/Rename/Invert/Delete.
- Matte chỉ render lại **khi hình dạng mask đổi**, không phải mỗi frame slider.
- Sheet **＋ New Mask** là **một cột hàng gọn cao 54pt**: icon trái trong slot cố định 30pt (cột chữ thẳng
  hàng giữa các hàng), tên + mô tả một dòng. Lưới tile hai cột cũ để mô tả wrap số dòng khác nhau nên card
  to nhỏ lệch nhau và sheet chiếm cả màn hình.

## 3. Tầng chỉnh một mask

- Panel có **viền trên 2pt accent** và **hàng nav riêng 44pt** — `‹ Masks` bên trái; thumbnail + tên mask
  + `n/m ⌄` (mở picker nhảy nhanh) ở giữa; toggle hiệu ứng + ⋯ bên phải. Nhìn là biết không phải toàn cục.
- Vùng cuộn có đủ LIGHT / COLOR / DETAIL / EFFECTS, cộng nhóm cuối **MASK · SHAPE** — **toàn dòng slider**:

| Loại | Dòng |
|---|---|
| Brush | Size · Feather · Flow · Opacity · Clear Strokes |
| Radial | Feather · Opacity |
| Luminance | Min · Max · Feather · Opacity |
| Color | Range · Feather · Opacity |

Cộng chip chọn vùng khi mask có nhiều hình.

- **Số đọc của mọi control brush là số trần 0–100, không có dấu `%`** (đúng cách Lightroom viết): thứ mà
  mỗi control là phần trăm *của* lại khác nhau và không cái nào là bức ảnh — Size là phần cạnh ngắn,
  Feather là phần của dấu cọ, Flow là phần của độ đục đầy đủ. Số hiển thị đơn giản là **vị trí núm trên
  chính thanh của nó**, nên đỉnh của mọi control đều là 100 và liếc là so sánh được.
- Menu ⋯ cạnh tên mask chỉ còn housekeeping: **Rename · Duplicate · Delete This Shape** (chỉ khi mask
  nhiều hình). "Delete Mask" đã là nút thùng rác trên hàng lệnh nên không lặp lại.
- **"Add Shape to Mask" bỏ hẳn**: mask tạo mới luôn một hình; mask nhiều hình chỉ còn đến từ Duplicate
  hoặc recipe cũ.
- Dùng chữ **Shape** thay cho Region — "Region" đứng cạnh "Mask" đọc như hai tên cho cùng một thứ.

## 4. Mười một loại vùng

Brush · Linear Gradient · Radial Gradient · Subject · Sky · Luminance Range · Color Range · **Depth Range** ·
**Face Skin · Eyes · Lips** (FS-03.11). Mỗi vùng là **Add hoặc Subtract** và có opacity riêng, nên cộng/trừ
nhiều vùng vào cùng một mask được.

- Sheet New Mask liệt kê **hàng**, không phải loại (`EditorNewMaskOption`): thêm hàng **Background** — là
  Subject với `isInverted`, đặt tên "Background N", không phải loại mới.
- **Depth Range**: phép dải của Luminance Range chạy trên bản đồ disparity, chuẩn hoá theo từng ảnh về
  0 (xa) … 1 (gần) — min/max đọc từ **một** pixel của `CIAreaMinMaxRed` (R = min, G = max) — cắt/scale
  theo khung render, rồi làm mờ khoảng một pixel bản đồ (bản đồ chỉ ~¼ độ phân giải ảnh, phóng lên bị
  bậc thang). Slider Near/Far. Ảnh không có depth thì hàng **mờ** kèm lý
  do.
- **Face Skin / Eyes / Lips**: đa giác từ `VNDetectFaceLandmarksRequest`, dựng bằng
  `FaceLandmarkMaskBuilder` (hình học thuần, test được): Skin = **đường hàm** (`faceContour`) khép lại + nửa elip
  cho trán, **trừ** mắt, chân mày, môi (bản đầu dùng elip cả hộp mặt thì tràn ra nền hai bên má); không có
  đường hàm thì lùi về elip; Eyes = hai mắt nở ×1.6; Lips = môi ngoài nở ×1.12. Mọi khuôn mặt trong khung. Feather theo
  khung. Kiểm tra có mặt chạy **một lần mỗi ảnh** trên preview (`VNDetectFaceRectanglesRequest`); không có
  mặt thì ba hàng mờ "No face found in this photo", đang kiểm **hoặc Vision lỗi** thì vẫn sáng — lỗi là
  "chưa biết", không được nói với người dùng là "không có mặt".
- **Simulator**: không có Neural Engine, Vision mặc định báo "Could not create inference context". Request
  nào liệt kê CPU cho stage của nó thì bị ghim CPU (chỉ trên simulator); tách chủ thể không hỗ trợ CPU nên
  Subject/Background **không chạy được trên simulator** — kiểm trên máy thật hoặc Vision của Mac. Landmark
  khuôn mặt chạy trên CPU của simulator nhưng lệch vị trí; trên Mac/máy thật thì đúng.

- **Subject** dùng phân tách foreground của hệ thống (iOS 17+). Thấy nhiều đối tượng thì cú chạm của người
  dùng đọc đúng đối tượng tại điểm đó; chạm nền thì lấy tất cả.
- **Sky** ưu tiên matte bầu trời mà bản decode RAW cung cấp. Ảnh thường dùng model phân đoạn ngữ nghĩa
  chạy **trên máy** (Apache-2.0, bundle trong app; lớp "sky" đọc từ metadata của model chứ không hardcode
  chỉ số).
- Live Photo chỉ chạy suy luận **một lần** trên ảnh tĩnh rồi scale mask qua các frame — không chạy model
  cho từng frame.
- Render áp **crop trước** rồi mới tới mask. Lúc đang kéo crop, canvas tạm hiện ảnh chưa crop và **ẩn
  render mask** để handle luôn ở đúng hệ toạ độ.

## 5. Guide trên ảnh

Sau khi đặt mask, hình dạng **phải nhìn thấy được và có tay nắm**.

- Guide nằm **trong lớp đã phóng to, trên lớp vẽ**: tay nắm thắng hit-test, còn kéo vào vùng trống vẫn rơi
  xuống lớp vẽ bên dưới.
- Tay nắm 18pt / vùng chạm 44pt, **dùng chung ngôn ngữ với khung crop**.
- **Mọi số đo của guide chia cho mức zoom** — nằm trong lớp đã phóng mà không chia thì ở 800% một tay nắm
  phủ **một phần ba khung ảnh** và vùng chạm của nó nuốt luôn hình đang chỉnh.

| Loại | Guide |
|---|---|
| Linear | line liền qua điểm đầu, line đứt qua điểm cuối (vuông góc trục), trục nối giữa; tay nắm hai đầu để xoay/đổi cỡ dải + tay nắm rỗng giữa để dời cả dải |
| Radial | outline ellipse + **ellipse đứt bên trong tại `1 − feather`** (lần đầu slider Feather có hình để nhìn) + 4 tay nắm cardinal + tay nắm feather nhỏ lệch 45° + tay nắm rỗng ở tâm |
| Subject | một chấm ghim tại điểm đã chọn, không tương tác |
| Brush | không có guide cố định — chỉ con trỏ cọ bám ngón tay |

- **Đặt một lần, sau đó kéo là di chuyển** (kiểu control point của Snapseed): gradient vừa thêm thì kéo
  trên ảnh là **đặt**; từ đó về sau kéo **bất kỳ đâu là dời nguyên hình**, còn đổi cỡ là việc của tay nắm.
  Trước đây kéo luôn đặt lại từ đầu — chạm hụt ellipse một chút là gradient đang chỉnh bị phá.
- Với radial, **kéo trong lẫn ngoài ellipse đều là di chuyển**; chỉ tay nắm mới đổi cỡ.
- **Giới hạn đã biết**: vùng trong ellipse là một lớp trong suốt nằm trên, nên **pan hai ngón bắt đầu từ
  trong lòng ellipse không ăn**; bắt đầu từ ngoài thì bình thường.
- Hint trong nhóm MASK · SHAPE nói theo guide: linear *"Drag the photo to move the gradient, the dots to
  reshape it"*, radial *"Drag the photo to move, the dots to resize"*, luminance *"Pick the range with the
  Min and Max sliders"*. Guide ẩn khi xem tràn viền.

## 6. Overlay đỏ

- Màu: **screen một lớp đỏ trầm để kéo shadow vào hue trước, rồi phủ đỏ rực alpha 0,52 lên**. Wash phẳng
  45% của bản cũ bị xỉn trên vùng tối — đúng chỗ hay vẽ mask nhất.
- **Chỉ vẽ bên trong editor một-mask.** Màn danh sách là chỗ *chọn* mask, không tô đỏ.
- **Bật và giữ** ở mọi thao tác liên quan **hình dạng**: tạo mask, mở mask, chọn/xoá hình, đổi Add/Sub,
  đảo vùng, kéo gradient, chạm subject/màu, chỉnh Feather/Opacity/Min/Max, và mọi nét cọ.
- **Chỉ tự ẩn khi người dùng bắt đầu chỉnh thông số** của mask — lúc đó tint đỏ che đúng thứ duy nhất cần
  xem là hiệu ứng. Quy tắc **không có ngoại lệ**: kể cả overlay vừa bật tay cũng nhường slider.
- **Chạm vào ảnh khi đang ở mask detail = "mask đâu?"** → bật lại lớp đỏ và guide. Gradient chỉ đặt lại sau
  khi ngón kéo ≥ 8pt, nên một cú chạm không làm radial sập về ellipse tối thiểu.

## 7. Hai công tắc, hai icon theo chuẩn ngành

| Công tắc | Icon | Nghĩa |
|---|---|---|
| Hiệu ứng của mask | con mắt / mắt gạch | bật/tắt **tác dụng** — Lightroom và Photoshop đều dạy bản năng này |
| Lớp phủ đỏ | chấm tròn đỏ / chấm gạch | hiện/ẩn **hình mask** |

- Pill lớp phủ mang glyph **là chính cái nó bật**; nền pill giữ kính, không accent — chấm đỏ tự mang trạng
  thái.
- Overlay **tô đỏ bất kể hiệu ứng đang bật hay tắt**: nó trả lời "mask ở đâu". Bản có guard theo hiệu ứng
  làm nút overlay thỉnh thoảng bấm không ra gì.
- Quan hệ giữa hai công tắc xử lý **tại lúc gạt con mắt**: tắt hiệu ứng → tắt luôn overlay (không còn đỏ
  lởn vởn, và trả lời được "gạt ăn chưa"); bật lại → hiện lại hình mask.

## 8. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
