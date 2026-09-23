# Intent: Đủ chức năng để người dùng bỏ được Lightroom

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan |
| Ngày | 2026-09-22 |
| Trạng thái | accepted |
| Tiến độ | **xong phần FS-03.11** (2026-09-23) — 16/16 AC có test; câu treo 2 (`.xmp`/`.dng`) và 4 (HDR) chưa chốt |
| Nguồn | phản hồi người dùng (chủ sở hữu sản phẩm) · bảng đối chiếu từ agent `lightroom-parity` (2026-09-22) |
| Spec sinh ra từ đây | [`FS-03.11`](../02-functional-spec/FS-03-photo-editor/11-parity-with-lightroom.md) — 16 AC, viết 2026-09-23 |

## Problem — vấn đề

Người chụp ảnh **vẫn phải mở Lightroom** sau khi đã chỉnh trong ShotDex. Nhưng khoảng cách **hẹp hơn nhiều
so với cảm giác ban đầu** — agent `lightroom-parity` đã quét toàn bộ catalog và bác bỏ ba giả định sai của
bản nháp trước intent này:

| Tưởng là thiếu | Thực tế |
|---|---|
| Mask chỉ có brush/linear/radial/subject/sky | **Đã có 7 loại** — thêm `luminanceRange` và `colorRange`, có kernel render và panel riêng ([PhotoEditingModels.swift:970](ShotDexKit/Models/PhotoEditingModels.swift:970), [EditorMaskPanels.swift:458](ShotDex/Features/Editing/EditorMaskPanels.swift:458)) |
| Geo không có Upright tự động | **Đã có** — Hough-line detector đủ ba chế độ Level/Vertical/Full ([UprightAnalyzer.swift](ShotDexKit/Render/UprightAnalyzer.swift), [EditorToolPanels.swift:396](ShotDex/Features/Editing/EditorToolPanels.swift:396)) |
| Màu/curve còn sơ sài | **Đã sát Lightroom** — mixer 8 dải, tới 8 point color, 4 bánh xe grade, curve 4 kênh + 6 preset |

Cái **thật sự thiếu**, đã xác minh bằng grep:

- **Không có gì để xoá vết.** Heal, clone, spot removal: `grep -ril "healing|cloneStamp|spotRemoval"` trên cả
  `ShotDexKit/` lẫn `ShotDex/` trả về **rỗng**. Bụi cảm biến, mụn, dây điện — việc gần như bức nào cũng cần,
  và là lý do phổ biến nhất để mở app khác.
- **Không chọn được vùng theo bộ phận khuôn mặt** (da / mắt / môi). Lightroom có People mask; ShotDex có
  subject nguyên khối. Đây đúng là câu "da cần chỉnh riêng".
- **Khử nhiễu vẫn là loại cổ điển** (`CINoiseReduction`), không có mô hình học — lý do chính người ta còn mở
  Lightroom cho ảnh ISO cao.
- **Sửa ống kính chỉ chạy trên RAW**: `lensCorrection` đi thẳng qua `CIRAWFilter` nên ảnh JPEG không có hồ sơ
  ống kính nào cả ([EditorAdjustmentCatalog.swift:148](ShotDex/Domain/Editing/EditorAdjustmentCatalog.swift:148)).
- **Preset mua sẵn không nhập được vào ảnh** — dù bộ đọc `.cube` **đã viết xong và đang chạy trong Video
  Studio** ([CubeLUT.swift](ShotDex/Domain/Video/CubeLUT.swift), [ImportedLUTStore.swift](ShotDex/Data/Sources/ImportedLUTStore.swift)),
  chỉ là chưa nối vào editor ảnh.
- **Mask thiếu ba loại rẻ tiền**: Background (chỉ là subject đảo ngược, `PhotoMask.isInverted` đã có),
  Depth Range (`DepthImageReader` đã đọc bản đồ độ sâu cho `depthBlur`), và Object nhiều vật thể.
- **Không ghép HDR, không ghép panorama** — `PhotoStackRenderer` mới có average/lighten/darken/focusStack.

Người dùng nói thẳng mục tiêu: **"để người dùng tự tin dùng mà không cần Lightroom nữa"**, và chức năng nào
*chỉ Lightroom có* thì **phải làm chỉn chu**, không làm cho có.

> Ghi chú độ tin cậy: agent **không tải được** trang tài liệu của Adobe (`helpx.adobe.com` trả 403 cả 7 lần).
> Cột "Lightroom làm gì" dựa trên trang sản phẩm `adobe.com` tải được + kiến thức mô hình, **không phải tài
> liệu đã đọc**. Cột "ShotDex có gì" thì có `file:line` xác minh được. Trước khi chốt spec, phần Lightroom
> cần kiểm lại bằng app thật hoặc nguồn tải được.

## Proposed outcome — kết quả mong muốn

- Một người chụp ảnh làm xong **một bức ảnh hoàn chỉnh** trong ShotDex — kể cả ảnh ISO cao, ảnh có bụi cảm
  biến, ảnh cần chỉnh riêng tông da — mà **không phải mở app khác**.
- Có một **bảng đối chiếu ShotDex ↔ Lightroom** được viết ra và bảo trì: cái gì đã có, cái gì cố ý không
  làm, cái gì đang nợ. Bản quét 2026-09-22 là mốc đầu tiên; nó đã chứng minh giá trị bằng cách bác ba giả
  định sai.
- Chức năng nhận làm thì **làm tới nơi**: đúng kết quả, đúng tốc độ, có undo, có preview thật.
- Mỗi chức năng mới trả lời được một câu bằng lời người chụp ảnh: *"cái này cứu tôi khỏi mở Lightroom trong
  tình huống nào"*. Không qua được câu đó thì không làm.

## Affected users and systems — phạm vi ảnh hưởng

- **Màn hình**: Photo Editor (tier D) và mọi thứ ăn theo recipe — extension ShotDexEdit, batch edit,
  Copy/Paste edits, My Looks.
- **Tầng code**: chủ yếu **ShotDexKit** (lõi render, model recipe, toán chỉnh sửa) — mỗi thứ thêm vào đều tốn
  `public` và tốn ngân sách bộ nhớ extension. Thêm `ShotDex/Domain/Editing/` và `Features/Editing/` cho UI.
- **Dữ liệu người dùng — có đụng**: thêm tầng healing = đổi cấu trúc recipe; thêm loại mask = thêm case vào
  `PhotoMaskComponentKind` (cộng thêm case thì recipe cũ vẫn đọc được, nhưng tầng healing thì không). Recipe
  cũ không được vỡ; recipe mới mở bằng bản app cũ phải suy biến chứ không hỏng ảnh.
- **Thiết bị**: cả bốn; chuẩn dựng UI là iPad trước (theo intent bố cục cùng ngày).
- Có thể đụng **Core Image · Vision · Core ML · Metal** — tức là đụng cả pin và bộ nhớ.

## Constraints — ràng buộc

- **Không thêm dependency** ngoài framework của Apple. GRDB vẫn là thư viện ngoài duy nhất.
- **Chạy trên máy, không gửi ảnh đi đâu.**
- **Không sao chép giao diện, biểu tượng hay tài sản của Adobe.** Lấy mô hình thao tác và khả năng, không
  lấy hình.
- **Trần bộ nhớ extension ~120MB**: mô hình khử nhiễu chắc chắn **không vừa** — extension phải suy biến về
  đường cổ điển, có kiểm soát, không chết. Tiền lệ: mô hình tách bầu trời 41MB đã theo kiểu "không nằm trong
  git, thiếu thì im lặng bỏ qua" (`ShotDex/Resources/Models/README.md`) — kiểu đó phải được xem lại chứ
  không nhân bản.
- **Preview không hạ độ phân giải để chạy mượt** (FS-03.04). Chức năng nặng quá luật này thì phải có đường
  khác (render nền, chỉ áp lúc lưu) và phải nói rõ trong spec.
- **Luật recipe**: cái gì thuộc về một khung hình cụ thể — crop, mask, markup, **và healing** — không được
  chép sang ảnh khác. `FS-03.10` đã có sẵn danh sách loại trừ; healing chỉ là thêm một dòng vào đó.
- **Luật dữ liệu người dùng**: indexer ghi đè cả dòng `photo_metadata`, nên thứ gì người dùng gõ vào phải nằm
  ở bảng riêng.
- Đây là **nhiều lượt ship**, không phải một.

## Sửa theo ảnh Lightroom thật — 2026-09-22

Người dùng chụp Lightroom trên iPad thật (`assets/lightroom-ref/lr-01…17.png`, 1194×834pt). Ba điều chỉnh
so với bảng của agent:

- **Danh sách "Create new Mask" của Lightroom iPad** (`lr-12`) có đúng chín mục: Select subject · Select sky
  · **Select background** · Brush · Linear gradient · Radial gradient · **Color range** · **Luminance range**
  · **Depth range** (mờ khi ảnh không có bản đồ độ sâu). **Không có People, không có Object** trên bản iPad.
  → ShotDex thiếu **Background** và **Depth range** là đúng, nhưng mask bộ phận khuôn mặt **không phải là
  đuổi kịp Lightroom** — đó là đi trước nó. Vẫn đáng làm, nhưng phải xếp hạng bằng lý do khác.
- **Versions có trên bản iPad** (`lr-15`: tab Auto / Named, có "Current edits" và "Original"). Vậy mục
  "bảng Versions là chuyện của Classic" trong phần *Không đuổi theo* là **sai** — đây là khoảng trống thật,
  cần xếp hạng lại ở `/spec`.
- **Mỗi loại mask có thẻ giải thích kèm ảnh ví dụ** trước khi tạo (`lr-13`: Brush → ảnh minh hoạ + một câu
  hướng dẫn + nút Create). Đây là chi tiết "chỉn chu" đáng học.

Ghi chú bố cục cho `/spec` (không thuộc phạm vi chức năng): Lightroom gom **Curve vào trong Light** (một nút
biểu tượng ở hàng tiêu đề), **Mixer/Grading vào trong Color**, **Geometry vào công cụ Crop** — nên panel của
họ chỉ có năm nhóm: Light · Color · Effects · Detail · Optics.

## Thứ tự ưu tiên đề xuất

Chấm theo "mỗi tuần cứu được bao nhiêu lần mở Lightroom", sau khi đã trừ những thứ hoá ra đã có:

1. **Xoá vết — heal + clone.** Khoảng trống lớn nhất còn lại, và **không cần mô hình học**: Lightroom làm
   việc này bằng lấy mẫu vùng lân cận + hoà biên theo gradient, đúng hình dạng của bộ rasterize nét vẽ và
   tầng `PhotoDrawing` đã có trong kit. Cần model mới (`PhotoHealingLayer` mang theo *độ lệch nguồn* — thứ
   mask không có) và một pass render mới.
2. **Mask theo bộ phận khuôn mặt (da / mắt / môi) bằng Vision landmarks.** `VNDetectFaceLandmarksRequest` trả
   sẵn đa giác mắt, môi, chân mày, viền mặt — **không cần huấn luyện gì**, đúng khuôn mẫu đã làm được với
   color-range và luminance-range. Tóc và quần áo thì **không có API, để ngoài**.
3. **Nối bộ nhập `.cube` LUT vào editor ảnh.** Hạ tầng đã viết xong và đang chạy ở Video Studio — phần còn
   lại chủ yếu là đường ống: một bước render và một lối vào import.
4. **Mask Depth Range + Background.** Gần như miễn phí: `DepthImageReader` đã đọc bản đồ độ sâu,
   `PhotoMask.isInverted` đã có. Gộp chung lượt với mục 2 vì cùng một chỗ dispatch render.
5. **Khử nhiễu bằng mô hình.** Có thật trong lời phàn nàn, nhưng đắt nhất: không có mô hình sẵn của Apple để
   dựa, phải tự huấn luyện, và không vừa trần bộ nhớ extension. Không phải chỗ để làm ẩu cho nhanh.
6. **Hồ sơ ống kính cho ảnh JPEG.** Hạ bậc mạnh so với bản nháp trước: nửa khó của mục đó (Upright) hoá ra
   **đã có**, và nửa còn lại vướng chuyện không có cơ sở dữ liệu hệ số méo nào để dựa — chỉ khả thi ở dạng
   vài chục ống kính đo tay. Xem lại ở `/plan` nếu phạm vi bó được.

Dưới cả sáu: **tự động dò bụi cảm biến** (phải có mục 1 trước mới có chỗ đứng) và **ghép HDR / panorama**
(chưa thấy trong lời phàn nàn; panorama còn là cả một hệ thống con mới).

## Không đuổi theo — chốt luôn câu hỏi treo

- **Đồng bộ đám mây, thư viện kiểu Lightroom, chia sẻ web.** ShotDex là local-only và thư viện là PhotoKit.
  Đây là quyết định kiến trúc, không phải tính năng thiếu.
- **Mô hình collection/collection-set của Lightroom.** `SmartAlbumStore` đã làm đúng việc đó trên PhotoKit.
- **Nâng trần 8 point color, phá luật look-preset không mang theo crop/mask.** Cả hai là lát cắt cố ý đã có
  lý do; đòi lại là mở lại một quyết định đã chốt, không phải lấp một khoảng trống.
- **Bảng "Versions" lưu mốc có tên.** Lightroom bản iPad/cloud cũng không có; đó là chuyện của Classic.
- **Trình duyệt camera profile (Adobe Standard / Camera Matching).** 48 look phim đã phục vụ đúng nhu cầu
  "cho ra cái nhìn của máy tôi", có cá tính hơn một danh sách profile.

## Open questions — câu hỏi còn treo

1. **Thứ tự sáu mục trên có đúng ý không?** Khác bản nháp trước ở ba chỗ: mask dải màu/dải sáng biến mất
   (đã có sẵn), LUT import chen lên hạng 3, hồ sơ ống kính rớt xuống đáy. → người dùng chốt.
2. **Nhập `.xmp` preset và profile `.dng` của bên thứ ba** có làm không? Khác `.cube` hoàn toàn: schema XMP
   của Adobe và định dạng ma trận/đường tông độc quyền. → người dùng; nếu có thì tách spec riêng.
3. ~~Khử nhiễu bằng mô hình~~ — **chốt 2026-09-23: không tự huấn luyện.** Giữ bộ lọc có sẵn và tiêu chỉnh
   nó (thêm Detail cho đường luminance, khử nhiễu chạy trước sharpening), nói thật là ở ISO rất cao không
   bằng Denoise AI, và không có chữ "AI" nào trong giao diện. Xem `FS-03.11` §6.
4. **HDR có nhận không?** Ghép HDR khả thi (đã có đường nạp nhiều khung của `PhotoStackRenderer`); panorama
   thì đắt hơn hẳn. → người dùng.
5. **Recipe đổi cấu trúc thì di trú thế nào?** Tầng healing là thay đổi lớn nhất. → `data-migration` phải trả
   lời trước khi viết dòng code đầu tiên.
6. **"Chỉn chu" nghiệm thu bằng gì?** Cần định nghĩa kiểm được cho từng chức năng (xoá vết khớp vân nền tới
   mức nào, trong bao nhiêu giây, ở độ phân giải nào). → `/spec`.
7. **Kiểm lại cột Lightroom** bằng app thật, vì tài liệu Adobe chặn tải. → trước khi chốt `/spec`.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
