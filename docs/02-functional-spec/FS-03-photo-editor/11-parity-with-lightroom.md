# FS-03.11 — Đuổi kịp Lightroom: sáu việc còn thiếu

`FS-03.11` · `ShotDexKit/Render/` · `ShotDexKit/Models/PhotoEditingModels.swift` ·
`ShotDex/Features/Editing/` · cập nhật 2026-09-23

**Một câu:** sáu thứ Lightroom làm được mà ShotDex chưa, xếp theo "mỗi tuần cứu được bao nhiêu lần mở
Lightroom", với ranh giới rõ ở chỗ nào ta **cố ý không** đuổi theo.

Nguồn: intent `docs/_intents/2026-09-22-editor-lightroom-feature-parity.md` và bảng đối chiếu đo trên máy
thật (`docs/_intents/assets/lightroom-ref/`, iPad 11" 1194×834).

## 1. Sáu việc, theo thứ tự

| # | Việc | Vì sao đứng ở đây |
|---|---|---|
| 1 | **Xoá vết** — heal + clone | Khoảng trống lớn nhất: `grep -ril "healing\|cloneStamp\|spotRemoval"` trên cả `ShotDexKit/` lẫn `ShotDex/` trả về rỗng. Bụi cảm biến và dây điện là việc gần như bức nào cũng cần, và **không cần mô hình học** |
| 2 | **Mask bộ phận khuôn mặt** — da · mắt · môi | `VNDetectFaceLandmarksRequest` trả sẵn đa giác, không phải huấn luyện gì. Lightroom bản iPad **không có** People mask, nên đây là đi trước chứ không phải đuổi kịp |
| 3 | **Nhập `.cube` LUT vào editor ảnh** | Hạ tầng đã chạy trong Video Studio: `Domain/Video/CubeLUT.swift` + `Data/Sources/ImportedLUTStore.swift`. Phần còn lại chủ yếu là đường ống |
| 4 | **Mask Background và Depth Range** | Gần như miễn phí: `PhotoMask.isInverted` đã có, `ShotDexKit/Render/DepthImageReader.swift` đã đọc bản đồ độ sâu cho `depthBlur` |
| 5 | **Khử nhiễu tốt hơn, không ML** | Giữ `CINoiseReduction`, tiêu chỉnh cho ảnh ISO cao thay vì đuổi theo Denoise AI — quyết định của người dùng 2026-09-23 |
| 6 | **Hồ sơ ống kính cho ảnh JPEG** | `lensCorrection` hiện chỉ chạy khi nguồn là RAW (`EditorAdjustmentCatalog.swift`), và không có cơ sở dữ liệu hệ số méo nào để dựa |

## 2. Xoá vết (heal + clone)

**Không phải AI.** Lightroom's Heal chưa bao giờ là sinh ảnh: nó lấy mẫu một vùng khác rồi hoà biên theo
gradient để vân nền khớp thay vì dán một miếng có mép. Clone thì chép thẳng. Cả hai là toán, và là đúng
hình dạng của bộ rasterize nét cọ cùng tầng `PhotoDrawing` đã có trong kit.

- **Một lớp mới trong recipe**, không nhét vào `drawing`: mỗi vết mang **độ lệch nguồn** — thứ mask và nét
  vẽ không có. `PhotoHealingLayer` gồm danh sách vết, mỗi vết có đường bút, cỡ, độ mềm, độ lệch nguồn, và
  chế độ `heal` hay `clone`.
- **Nguồn tự chọn rồi cho sửa**: chạm là ShotDex đoán một vùng nguồn gần đó; kéo núm nguồn để đổi.
- **Thuộc về một khung hình cụ thể** nên **không chép sang ảnh khác** — vào đúng danh sách loại trừ của
  [FS-03.10](10-copy-paste-edits.md) cùng crop, mask, markup.
- Vẽ ở **độ phân giải của preview**, áp lại ở độ phân giải đầy đủ lúc lưu; preview **không** hạ độ phân giải
  ([FS-03.04](04-raw-and-render-graph.md)).

⚠️ **CẦN QUYẾT — ngưỡng "chỉn chu".** Một vết xoá đạt hay không đạt phải đo được, nếu không thì mỗi lần
review là một cuộc cãi. Đề xuất: trên ảnh thử có bụi cảm biến trên nền trời chuyển màu, sai lệch màu trung
bình trong vùng vá ≤ 2/255 so với nền quanh nó, và không có mép cứng nhìn thấy ở 100%.

## 3. Mask bộ phận khuôn mặt

`VNDetectFaceLandmarksRequest` (đã dùng ở `Data/Sources/SubjectVisionReader.swift`) trả về đa giác mắt,
môi, chân mày và viền mặt. Ba loại mask mới dựng từ đó:

| Loại | Dựng từ |
|---|---|
| `faceSkin` | viền mặt **trừ** mắt, môi, chân mày |
| `eyes` | hai đa giác mắt, nở ra vài pt |
| `lips` | đa giác môi |

**Tóc, quần áo, răng: không làm.** Vision không có phân đoạn theo bộ phận cho những thứ đó, và làm chúng
nghĩa là tự huấn luyện một mô hình — cùng cái giá vừa từ chối ở mục 5.

## 4. Nhập `.cube` LUT vào editor ảnh

Dùng lại **nguyên** `CubeLUTParser` và `ImportedLUTStore` đang chạy cho Video Studio; không viết bộ đọc thứ
hai. Thêm: một bước render trong `PhotoRenderService` và một lối vào ở chặng **Presets** của rail.

- LUT đã nhập nằm **cạnh** 48 film look, cùng một danh sách, nhóm riêng "My LUTs".
- LUT có **cường độ** như film look (`filterIntensity`), vì một LUT áp 100% thường là quá tay.
- Recipe lưu **định danh LUT**, không lưu cả bảng tra: một LUT 33³ là ~140KB, nhân với mỗi ảnh đã sửa là
  một cách làm phình cơ sở dữ liệu. File LUT sống trong `ImportedLUTStore`.

⚠️ **CẦN QUYẾT:** ảnh đã sửa bằng một LUT rồi người dùng **xoá LUT đó** thì render ra gì? Đề xuất: giữ
recipe nguyên vẹn, ảnh render **không có** bước LUT, và panel nói "LUT đã bị xoá" ngay tại hàng Look.

## 5. Mask Background và Depth Range

- **Background** = `subject` đảo ngược. Hôm nay đã làm được bằng tay qua `PhotoMask.isInverted`, nhưng phải
  tự nghĩ ra; thêm nó vào danh sách tạo mask là việc của nhãn, không phải của render.
- **Depth Range** = ngưỡng trên bản đồ chênh lệch mà `DepthImageReader` đã đọc cho `depthBlur`, đúng hình
  dạng của `luminanceRange` đang có. Chỉ hiện với ảnh **có** bản đồ độ sâu — cùng cổng `hasDepth` mà
  `depthBlur` đang dùng.

## 6. Khử nhiễu: tiêu chỉnh, không ML

Chốt 2026-09-23: **không tự huấn luyện mô hình.** Không có mô hình sẵn của Apple để dựa, và một file weight
cỡ mô hình tách bầu trời 41MB là thứ phải nuôi mãi. Thay vào đó:

- Tách **Luminance** và **Color** thành hai đường như hiện nay, nhưng thêm **Detail** (giữ vân) cho đường
  luminance — `CINoiseReduction` một mình xoá cả nhiễu lẫn vân da.
- Khử nhiễu chạy **trước** sharpening trong chuỗi render, và spec nói rõ thứ tự đó vì làm ngược là khuếch
  đại nhiễu rồi mới xoá.
- **Nói thật với người dùng**: ở ISO rất cao, kết quả sẽ không bằng Denoise AI của Lightroom. Không có chữ
  "AI" nào trong giao diện.

## 7. Hồ sơ ống kính cho ảnh JPEG

Apple không phát hành cơ sở dữ liệu hệ số méo; Adobe có một bộ đo được cấp phép. Nên phạm vi là **bó hẹp và
thành thật**:

- Một bảng hệ số **đo tay** cho một số ống kính phổ biến, khoá bằng tên ống kính đã chuẩn hoá
  (`LensNormalizer` + `sensor_database.json` đã biết ảnh chụp bằng gì).
- Ống kính **không có trong bảng** thì mục Optics vẫn hiện nhưng nói rõ "chưa có hồ sơ cho ống kính này" —
  không lặng lẽ không làm gì.
- RAW giữ nguyên đường cũ qua `CIRAWFilter`.

⚠️ **CẦN QUYẾT:** ai đo và đo bao nhiêu ống kính cho lần đầu? Không có câu trả lời thì mục này chỉ là một
khung rỗng.

## 8. Cố ý không đuổi theo

| Thứ | Vì sao không |
|---|---|
| Đồng bộ đám mây, thư viện kiểu Lightroom, chia sẻ web | ShotDex là local-only; thư viện là PhotoKit. Quyết định kiến trúc, không phải tính năng thiếu |
| Mô hình collection/collection-set | `SmartAlbumStore` đã làm đúng việc đó |
| Nâng trần 8 point color; look preset mang theo crop/mask | Hai lát cắt cố ý đã có lý do |
| Trình duyệt camera profile | 48 film look đã phục vụ nhu cầu "cho ra cái nhìn của máy tôi" |
| Denoise AI | Xem §6 |
| Nhập `.xmp` preset và profile `.dng` | Khác `.cube` hoàn toàn (schema XMP của Adobe, định dạng ma trận độc quyền). Để một `/intent` riêng |

**Versions** (tab Auto / Named) thì **không** nằm trong danh sách này: bản iPad của Lightroom có nó
(`lr-15`), nên nó là khoảng trống thật, chỉ là chưa xếp vào sáu mục trên. Cần một quyết định riêng.

## 9. Tiêu chí nghiệm thu

| # | Cho / Khi / Thì | Chứng minh |
|---|---|---|
| AC-1 | **Cho** ảnh JPG có một vết bụi trên nền trời · **Khi** chạm vết đó bằng công cụ **Heal** · **Thì** vùng vá lấy mẫu từ nền quanh nó, sai lệch màu trung bình ≤ **2/255**, và không có mép cứng ở zoom 100% | ⚠️ chưa có |
| AC-2 | **Cho** một vết heal đã tạo · **Khi** kéo núm nguồn sang chỗ khác · **Thì** vùng vá cập nhật theo, và cả thao tác là **một** bước Undo | ⚠️ chưa có |
| AC-3 | **Cho** ảnh A có lớp healing · **Khi** Copy Edits rồi Paste sang ảnh B · **Thì** B **không** nhận lớp healing (cùng luật với crop/mask/markup) | ⚠️ chưa có |
| AC-4 | **Cho** recipe có lớp healing lưu bằng bản mới · **Khi** mở bằng bản app cũ · **Thì** ảnh vẫn dựng được, lớp healing bị bỏ qua, và **không** mất các chỉnh sửa khác | ⚠️ chưa có — cần `data-migration` duyệt |
| AC-5 | **Cho** ảnh có đúng một khuôn mặt · **Khi** tạo mask **Face Skin** · **Thì** mask phủ vùng da mặt và **không** phủ mắt, môi, chân mày | ⚠️ chưa có |
| AC-6 | **Cho** ảnh **không có** khuôn mặt nào · **Khi** mở danh sách tạo mask · **Thì** ba loại khuôn mặt **mờ** và nói vì sao, không phải tạo xong mới báo rỗng | ⚠️ chưa có |
| AC-7 | **Cho** một file `.cube` 33³ hợp lệ · **Khi** nhập qua Files ở chặng Presets · **Thì** nó xuất hiện trong nhóm "My LUTs" và áp được với cường độ 0…100% | ⚠️ chưa có |
| AC-8 | **Cho** một file `.cube` **hỏng** (thiếu `LUT_3D_SIZE`) · **Khi** nhập · **Thì** hiện lý do cụ thể và **không** thêm mục rỗng nào vào danh sách | ⚠️ chưa có — `CubeLUTParser` đã nghiêm, cần test ở tầng UI |
| AC-9 | **Cho** ảnh đã sửa bằng một LUT · **Khi** xoá LUT đó khỏi thư viện · **Thì** ảnh render không có bước LUT, recipe giữ nguyên, và hàng Look nói "LUT đã bị xoá" | ⚠️ chưa có |
| AC-10 | **Cho** ảnh có chủ thể rõ · **Khi** tạo mask **Background** · **Thì** vùng chọn là phần bù của Subject, kiểm bằng tổng hai mask phủ kín khung | ⚠️ chưa có |
| AC-11 | **Cho** ảnh **không có** bản đồ độ sâu · **Khi** mở danh sách tạo mask · **Thì** **Depth Range** mờ — cùng cổng `hasDepth` mà `depthBlur` dùng | ⚠️ chưa có |
| AC-12 | **Cho** ảnh ISO 6400 · **Khi** đặt Luminance 60 và Detail 50 · **Thì** nhiễu hạt giảm đo được mà vân da **không** mất hẳn (so bằng phương sai cục bộ trên hai vùng) | ⚠️ chưa có |
| AC-13 | **Cho** một ảnh bất kỳ · **Khi** đọc chuỗi render · **Thì** khử nhiễu chạy **trước** sharpening | ⚠️ chưa có — test thuần trên thứ tự pipeline |
| AC-14 | **Cho** ảnh JPG chụp bằng ống kính **có** trong bảng hồ sơ · **Khi** bật Lens Corrections · **Thì** méo hình được nắn theo hệ số của ống kính đó | ⚠️ chưa có |
| AC-15 | **Cho** ảnh JPG chụp bằng ống kính **không** có trong bảng · **Khi** mở Optics · **Thì** nói rõ "chưa có hồ sơ cho ống kính này", không có nút chết | ⚠️ chưa có |
| AC-16 | **Cho** bản dựng bất kỳ · **Khi** tìm trong giao diện · **Thì** **không** có chữ "AI" ở bất cứ đâu thuộc khử nhiễu | ⚠️ chưa có — grep trong `Tools/gate` |

## 10. Việc còn treo

- ⚠️ Ngưỡng "chỉn chu" của xoá vết (§2) — số đề xuất đã có, cần người dùng chốt.
- ⚠️ Xoá LUT đang được một ảnh dùng (§4).
- ⚠️ Ai đo hồ sơ ống kính, và bao nhiêu ống cho lần đầu (§7).
- ⚠️ **Versions** có làm không (§8) — bản iPad của Lightroom có, ta chưa xếp vào đâu.
- ⚠️ Thứ tự ship sáu mục: làm tuần tự 1→6, hay gộp 3+4 (đều rẻ) lên trước mục 2?
