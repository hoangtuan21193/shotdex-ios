# FS-03.05 — Mask cục bộ

`FS-03.05` · `Features/Editing/EditorMaskPanels.swift` · `EditorMaskGuides.swift`
· `ShotDexKit` (matte và overlay) · cập nhật 2026-09-24

**Một câu:** một ảnh có nhiều mask, mỗi mask có đủ bộ chỉnh riêng — và hình dạng của nó luôn nhìn thấy
được, sờ được.

Vẽ, tranh chấp chạm và zoom: [FS-03.05b](05b-mask-painting-and-zoom.md).

## 1. Quy tắc

- **UI mask có hai trạng thái, cùng trong panel**: chọn loại (chưa có mask, hoặc vừa chạm `+`) và chỉnh mask
  đang chọn. Không sheet, không tầng thứ ba. Khung panel và lưới 40pt: [FS-03.12](12-phone-panel-grid.md).
- Mask có **đủ bộ chỉnh chuẩn** (Light/Color/Detail/Effects). Các control decode RAW là **mức nguồn** nên
  chỉ có ở Adjust toàn cục.
- **Overlay đỏ bật theo việc người dùng đang làm**, không theo timer.
- **Không có nút zoom riêng** — pinch đã zoom xuyên qua lớp vẽ; một mode toggle là thêm một thứ phải học
  cho cử chỉ ai cũng thử.
- Nét vẽ lưu theo toạ độ chuẩn hoá của ảnh **sau crop**, nên preview và bản full-res dùng chung một recipe.

## 2. Chọn loại mask

- Tiêu đề **"Choose an area to adjust"** (có `‹` quay lại khi đã có mask), rồi ba hàng chip 40pt, mỗi hàng
  cuộn ngang, không nhãn hàng:

| Hàng | Chip |
|---|---|
| nhận diện | Subject · Sky · Background · Face Skin · Eyes · Lips |
| vẽ | Brush · Linear · Radial |
| dải | Color · Luminance · Depth |

- **Một chạm là tạo mask**, chọn luôn nó và chuyển sang chỉnh.
- Loại không dùng được (ảnh không có depth, không có mặt) **mờ 35%**; chạm vào thì tiêu đề đổi thành **lý do**
  trong 3s, không tạo mask.
- Đang nhận diện: thumbnail mới có vòng quay, pill "Detecting subject…" trên ảnh, các hàng chỉnh mờ và không
  nhận chạm. (Không có viền "vùng dự đoán": trước khi Vision trả lời thì chưa có vùng nào để vẽ.)
- Nhận diện lỗi hoặc không thấy gì: vòng quay dừng, pill 3s **"Couldn't find a subject"** (sky, face tương tự),
  **mask rỗng vẫn giữ** trong dải để Undo, Delete hoặc vẽ thêm.
  Lỗi Vision **không** làm hỏng cả lượt render, và kết quả rỗng được nhớ theo khung nên Vision không chạy lại ở
  mỗi lượt render.

## 3. Chỉnh mask đang chọn

- **Dải đầu 40pt**: thumbnail 40×30 của mọi mask (matte đỏ trên nền xám phẳng — đỏ đè lên ảnh ở cỡ này không
  đọc nổi hình mask; chạm để chọn, đó là lối nhảy nhanh) · `+` · tên mask (không hẹp dưới 72pt — nhiều mask thì dải cuộn) · `⋯`. Mask đổi mà không qua chạm thumbnail (vừa tạo, Duplicate, Undo) thì dải **tự cuộn
  tới thumbnail đó**.
- Mask đang **tắt hiệu ứng** thì thumbnail mờ 35%.
- **Hàng đầu dưới dải**: chip chọn hình (chỉ khi mask có ≥2 hình) · công tắc **Add / Subtract** (chế độ cho
  hình kế tiếp) · Undo.
- Rồi LIGHT / COLOR / DETAIL / EFFECTS và nhóm **MASK · SHAPE**, toàn dòng slider 40pt:

| Loại | Dòng |
|---|---|
| Brush | Size · Feather · Flow · Opacity · Clear Strokes |
| Radial | Feather · Opacity |
| Luminance | Min · Max · Feather · Opacity |
| Color | Range · Feather · Opacity |

- **Số đọc của mọi control brush là số trần 0–100, không có dấu `%`** (đúng cách Lightroom viết): mỗi control
  là phần trăm của một thứ khác nhau, nên số hiển thị là **vị trí núm trên chính thanh của nó**.
- Menu `⋯`: **Hide / Show** (tắt/bật hiệu ứng — thay con mắt trên hàng nav cũ) · Rename · Invert · Duplicate ·
  Delete This Shape (khi ≥2 hình) · Delete.
- Không còn viền accent trên panel: dải thumbnail đã nói "đang ở trong một mask".
- Dùng chữ **Shape** thay cho Region — "Region" đứng cạnh "Mask" đọc như hai tên cho cùng một thứ.

## 4. Mười một loại vùng

Brush · Linear Gradient · Radial Gradient · Subject · Sky · Luminance Range · Color Range · **Depth Range** ·
**Face Skin · Eyes · Lips** (FS-03.11). Mỗi vùng là **Add hoặc Subtract** và có opacity riêng, nên cộng/trừ
nhiều vùng vào cùng một mask được.

- Màn chọn loại liệt kê **mục**, không phải loại: **Background** là Subject đảo, đặt tên "Background N",
  không phải loại mới.
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

## 7. Hai công tắc

| Công tắc | Icon | Nghĩa |
|---|---|---|
| Hiệu ứng của mask | `⋯` Hide / Show, thumbnail mờ khi tắt | bật/tắt **tác dụng** |
| Lớp phủ đỏ | chấm tròn đỏ / chấm gạch | hiện/ẩn **hình mask** |

- Pill lớp phủ mang glyph **là chính cái nó bật**; nền pill giữ kính, không accent — chấm đỏ tự mang trạng
  thái.
- Overlay **tô đỏ bất kể hiệu ứng đang bật hay tắt**: nó trả lời "mask ở đâu". Bản có guard theo hiệu ứng
  làm nút overlay thỉnh thoảng bấm không ra gì.
- Quan hệ giữa hai công tắc xử lý **tại lúc Hide / Show**: tắt hiệu ứng → tắt luôn overlay (không còn đỏ
  lởn vởn, và trả lời được "gạt ăn chưa"); bật lại → hiện lại hình mask.

## 8. Tiêu chí nghiệm thu

Phần còn lại của FS-03.05 **chưa viết**. Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).

## 9. Tiêu chí nghiệm thu panel phone

Tiếp số của [FS-03.12](12-phone-panel-grid.md). Máy: iPhone 17, iOS 26.5 và 18.6.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-17 | ảnh chưa có mask | mở Mask | ba hàng chip hiện trong panel, không sheet; panel vẫn 264 | `MaskPhonePanelTests.chooserRowsCoverEveryKindOnce` + ảnh iPhone 17 26.5, 2026-09-24 |
| AC-18 | như AC-17 | chạm Radial một lần | có đúng 1 mask, dải hiện 1 thumbnail + tên "Radial 1", hàng Feather · Opacity có | `MaskPhonePanelTests.oneTapOnRadialMakesOneShortNamedMask` + ảnh iPhone 17 26.5, 2026-09-24 |
| AC-19 | ảnh không có depth | chạm Depth | không tạo mask; tiêu đề thành "This photo has no depth map. Portrait mode photos do." rồi trở lại sau 3s | `MaskPhonePanelTests.depthWithoutADepthMapGivesItsReason` + ảnh iPhone 17 26.5, 2026-09-24 |
| AC-20 | 1 mask đang bật | `⋯` → Hide | ảnh mất tác dụng mask, thumbnail mờ 35%, lớp đỏ tắt; Show trả lại cả ba | `MaskPhonePanelTests.hideAndShowToggleTheEffect` |
| AC-21 | 6 mask, dải cuộn tới cuối, mask 6 đang chọn, rồi chạm thumbnail mask 1 | `⋯` → Duplicate | bản sao nằm ngay sau mask 1, được chọn, thumbnail của nó nằm trọn trong dải | `MaskPhonePanelTests.duplicateLandsRightAfterItsSource` + ảnh iPhone 17 26.5, 2026-09-25 (6 mask Radial, chạm mask 1, `⋯` → Duplicate: bản sao ở vị trí 2, được chọn, nằm trọn trong dải) |
| AC-22 | 1 mask đang chọn | chạm `+` rồi `‹` | vẫn 1 mask, mask cũ vẫn chọn, không có mask rỗng | `MaskPhonePanelTests.plusThenBackMakesNothing` |
| AC-23 | simulator (Vision không chạy được Subject) | chạm Subject | vòng quay dừng, pill "Couldn't find a subject" 3s, mask rỗng vẫn trong dải, không có alert lỗi | `iphone-image-and-detect.json`, iPhone 17 Pro 26.5, 2026-09-25: chạm Subject → 1s sau pill "COULDN'T FIND A SUBJECT", 5s sau pill mất, "Subject 1" rỗng vẫn trong dải, không alert |
| AC-24 | ảnh chưa có mask | chạm Sky rồi Undo một lần | 0 mask, panel về màn chọn loại | `MaskPhonePanelTests.undoAfterCreatingReturnsToTheChooser` |
| AC-25 | 1 mask | `⋯` → Delete | 0 mask, panel về màn chọn loại, không có `‹` | `MaskPhonePanelTests.deletingTheLastMaskReturnsToTheChooser` |

**Chưa chứng minh được:** không còn.
