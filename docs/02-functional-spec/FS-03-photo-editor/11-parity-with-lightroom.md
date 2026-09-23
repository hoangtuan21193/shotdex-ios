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
- **Bản v1 (2026-09-23) là vết tròn**, không phải nét bút: tâm, bán kính, độ mềm, độ mờ, nguồn. Toạ độ
  chuẩn hoá theo **khung sau crop** như mask và nét vẽ, nên — giống mask — đổi crop sau khi vá thì vết lệch.
  Pass vá chạy **ngay sau crop**, trước mask. Trường sửa màu của Heal là normalized convolution trên một vành
  quanh vết (`PhotoHealingRenderer`), không cần giải Poisson.
- **Công cụ trên canvas** (chặng **Heal** trên rail, cũng có trên bánh xe điện thoại): chạm ảnh là một vết
  mới với Size/Feather đang đặt; vết đang chọn hiện vòng nguồn nét đứt nối bằng một đường, kéo vòng nào thì
  dời vòng đó, **cả lần kéo là một bước Undo**; Size, Feather, Heal/Clone áp lên vết đang chọn; Delete Spot
  ở panel; ↺ ở thanh commit gỡ mọi vết.
- **Nguồn tự chọn rồi cho sửa**: chạm là ShotDex đoán một vùng nguồn gần đó; kéo núm nguồn để đổi.
- **Thuộc về một khung hình cụ thể** nên **không chép sang ảnh khác** — vào đúng danh sách loại trừ của
  [FS-03.10](10-copy-paste-edits.md) cùng crop, mask, markup.
- Vẽ ở **độ phân giải của preview**, áp lại ở độ phân giải đầy đủ lúc lưu; preview **không** hạ độ phân giải
  ([FS-03.04](04-raw-and-render-graph.md)).

**Ngưỡng "chỉn chu" (chốt 2026-09-23):** trên ảnh thử có bụi cảm biến trên nền trời chuyển màu, sai lệch màu
trung bình trong vùng vá **≤ 2/255** so với nền quanh nó, và **không có mép cứng** nhìn thấy ở 100%.

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

**Xoá một LUT đang được ảnh dùng (chốt 2026-09-23):** recipe giữ nguyên, ảnh render **không có** bước LUT,
và panel nói "LUT đã bị xoá" ngay tại hàng Look. `ImportedLUTStore.url(for:)` đã trả `nil` khi không còn file,
nên bước render chỉ cần bỏ qua chứ không ném.

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

Apple không phát hành cơ sở dữ liệu hệ số méo, và `.lcp` của Adobe là tài sản của họ. Nguồn dùng được là
**Lensfun** (chốt 2026-09-23):

- **Nhúng toàn bộ** cơ sở dữ liệu Lensfun (nguồn mở, **CC-BY-SA 3.0**), đổi XML sang JSON lúc build. Mô hình
  méo `poly3` / `poly5` / `ptlens` theo từng tiêu cự.
- **Ghi công** CC-BY-SA trong màn Giới thiệu. Không sửa dữ liệu tại chỗ — mọi chỉnh của ta nằm ở lớp khớp
  tên bên ngoài, để khỏi phải chia sẻ lại một bản dữ liệu đã sửa.
- **Rủi ro thật nằm ở khớp tên**, không ở hệ số: Lensfun khoá bằng chuỗi maker/model trong EXIF, mà mỗi hãng
  viết một kiểu. Khớp qua `LensNormalizer` + `sensor_database.json`.
- Ống **không khớp** thì nói rõ "chưa có hồ sơ cho ống kính này" **và cho chọn tay** từ danh sách.
- Lensfun gần như không có ống điện thoại — ảnh điện thoại đã được camera nắn sẵn, nên nhánh "chưa có hồ sơ"
  là câu trả lời đúng.
- RAW giữ nguyên đường cũ qua `CIRAWFilter`.

**Đã làm (2026-09-23):**

- `Tools/lensfun-to-json.py` đổi 56 file XML của Lensfun (`data/db`) sang `ShotDexKit/Resources/lensfun-distortion.json`
  (~840KB): 1527 ống có dữ liệu méo, 1054 thân máy (ngàm + crop factor). Chuỗi và hệ số chép nguyên văn.
- **Khớp** (`LensProfileMatcher`): EXIF Nikon chỉ ghi "16.0-35.0 mm f/4.0", nên thu hẹp theo **dải tiêu cự +
  khẩu độ lớn nhất** trước, rồi **ngàm của thân máy**, rồi **hãng**, cuối cùng mới để token tên phân xử
  ("EF24-70mm f/2.8L II USM" → bản Mark II). Kết quả lưu **đã giải** trong recipe
  (`PhotoLensProfileChoice`: id ống, crop factor thân máy, tự khớp hay tự chọn) — renderer chỉ tra theo id.
- **Pass nắn** (`PhotoRenderService.applyLensProfile`): `CIWarpKernel` với poly3 / poly5 / ptlens, bán kính chuẩn
  hoá theo quy ước PTLens (r = 1 là nửa cạnh ngắn của khung hiệu chuẩn, nhân crop thân máy / crop ống), hệ số
  nội suy tuyến tính giữa hai tiêu cự đã đo gần nhất, và **tự phóng vừa đủ** để góc/cạnh không lộ khoảng trống
  (tối đa 1,5×). Chưa xử lý khác biệt tỉ lệ khung (hiệu chuẩn 3:2 so với ảnh 4:3) — xấp xỉ.
- **Panel** (Optics › Lens Profile): công tắc; tên ống + "Found from EXIF"/"Chosen by you" + **Change**; không
  khớp thì "No profile for this lens yet. Choose yours from the list." + **Choose Lens**; RAW thì nói đã do bộ
  giải RAW nắn. Danh sách chọn tay tìm được, nhóm "Fits <ngàm>" lên đầu, ghi công Lensfun ở cuối.
- **Ghi công** CC-BY-SA 3.0 ở Settings › Acknowledgements (cùng GRDB).

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
| AC-1 | **Cho** ảnh JPG có một vết bụi trên nền trời · **Khi** chạm vết đó bằng công cụ **Heal** · **Thì** vùng vá lấy mẫu từ nền quanh nó, sai lệch màu trung bình ≤ **2/255**, và không có mép cứng ở zoom 100% | ✅ `PhotoHealingTests.healMatchesTheSurroundingSky` (3 nguồn, kể cả nguồn lệch dọc sang vùng trời nhạt hơn): trung bình ~0.5/255, tệ nhất ~1.9/255 quanh vết |
| AC-2 | **Cho** một vết heal đã tạo · **Khi** kéo núm nguồn sang chỗ khác · **Thì** vùng vá cập nhật theo, và cả thao tác là **một** bước Undo | ✅ `PhotoHealingTests.draggingTheSourceIsOneUndoStep`, `panelSlidersEditTheSelectedSpot`; ảnh chụp công cụ Heal (iPad 26.5) |
| AC-3 | **Cho** ảnh A có lớp healing · **Khi** Copy Edits rồi Paste sang ảnh B · **Thì** B **không** nhận lớp healing (cùng luật với crop/mask/markup) | ✅ `PhotoHealingTests.healingIsNeverCopied`; bảng loại trừ ở FS-03.10 |
| AC-4 | **Cho** một recipe có một phần tử không đọc được (loại mask, loại component, film look lạ) · **Khi** decode · **Thì** chỉ mất đúng phần tử đó; crop, màu, curve, filter, các mask khác và markup **còn nguyên**; một preset hỏng không xoá cả My Looks | ✅ `RecipeLossyDecodingTests` (4 test) |
| AC-5 | **Cho** ảnh có đúng một khuôn mặt · **Khi** tạo mask **Face Skin** · **Thì** mask phủ vùng da mặt và **không** phủ mắt, môi, chân mày | ✅ `FaceMaskTests.faceSkinCoversSkinOnly`, `eyesAndLipsCoverTheirPartOnly` (khuôn mặt vẽ tay, hình học thuần). ⚠️ Vision trên ảnh người thật chưa chụp — thư viện simulator không có ảnh chân dung |
| AC-6 | **Cho** ảnh **không có** khuôn mặt nào · **Khi** mở danh sách tạo mask · **Thì** ba loại khuôn mặt **mờ** và nói vì sao, không phải tạo xong mới báo rỗng | ✅ `FaceMaskTests.faceRowsAreGatedOnFaces`; ba hàng mờ "No face found in this photo" trong New Mask |
| AC-7 | **Cho** một file `.cube` 33³ hợp lệ · **Khi** nhập qua Files ở chặng Presets · **Thì** nó xuất hiện trong nhóm "My LUTs" và áp được với cường độ 0…100% | ✅ `PhotoLUTTests.recipeLUTIsAppliedAtItsIntensity`, `lutIDRoundTrips`, `lutAndFilmLookReplaceEachOther`; nhóm **My LUTs** ở Presets (`EditorFiltersPanel.myLUTs`) |
| AC-8 | **Cho** một file `.cube` **hỏng** (thiếu `LUT_3D_SIZE`) · **Khi** nhập · **Thì** hiện lý do cụ thể và **không** thêm mục rỗng nào vào danh sách | ✅ `PhotoLUTTests.brokenCubeNamesTheProblem`, `brokenCubeIsNotAdded`; lý do từ `LUTImportMessage` |
| AC-9 | **Cho** ảnh đã sửa bằng một LUT · **Khi** xoá LUT đó khỏi thư viện · **Thì** ảnh render không có bước LUT, recipe giữ nguyên, và hàng Look nói "LUT đã bị xoá" | ✅ `PhotoLUTTests.deletedLUTRendersWithoutALook`; hàng "LUT deleted · this photo renders without it" ở My LUTs |
| AC-10 | **Cho** ảnh có chủ thể rõ · **Khi** tạo mask **Background** · **Thì** vùng chọn là phần bù của Subject, kiểm bằng tổng hai mask phủ kín khung | ✅ `MaskKindParityTests.backgroundIsSubjectInverted`, `addingBackgroundMaskInvertsSubject`, `invertedMaskIsTheComplement` |
| AC-11 | **Cho** ảnh **không có** bản đồ độ sâu · **Khi** mở danh sách tạo mask · **Thì** **Depth Range** mờ — cùng cổng `hasDepth` mà `depthBlur` dùng | ✅ `MaskKindParityTests.depthRangeIsGatedOnDepth`, `depthRangeSelectsTheBand`; hàng mờ trong New Mask khi `!hasDepthSource` |
| AC-12 | **Cho** ảnh ISO 6400 · **Khi** đặt Luminance 60 và Detail 50 · **Thì** nhiễu hạt giảm đo được mà vân da **không** mất hẳn (so bằng phương sai cục bộ trên hai vùng) | ✅ `NoiseReductionSplitTests` (ảnh tổng hợp: nhiễu ±0.08 trên nền phẳng và vân ±0.12 — phương sai nhiễu còn <25%, vân giữ >60%; đo thực ~9% và ~70%) |
| AC-13 | **Cho** một ảnh bất kỳ · **Khi** đọc chuỗi render · **Thì** khử nhiễu chạy **trước** sharpening | ✅ `DetailPassOrderTests` trên `PhotoRenderService.detailPassOrder` |
| AC-14 | **Cho** ảnh JPG chụp bằng ống kính **có** trong bảng hồ sơ · **Khi** bật Lens Corrections · **Thì** méo hình được nắn theo hệ số của ống kính đó | ✅ `LensProfileTests.nikonGenericExifFindsTheRightLens` (EXIF thật của ảnh D800E trong thư viện sim → "Nikon AF-S Nikkor 16-35mm f/4G ED VR"), `canonNameTokensPickTheMarkII`, `warpMovesEdgesAndFillsCorners`; ảnh chụp Optics bật profile (iPad 26.5) |
| AC-15 | **Cho** ảnh JPG chụp bằng ống kính **không** khớp Lensfun · **Khi** mở Optics · **Thì** nói rõ "chưa có hồ sơ cho ống kính này" **và** có lối chọn ống thủ công, không có nút chết | ✅ `LensProfileTests.noLensDataMeansNoMatch`; ảnh chụp D90 không có dữ liệu ống: "No profile for this lens yet" + Choose Lens, và danh sách chọn tay |
| AC-16 | **Cho** bản dựng bất kỳ · **Khi** tìm trong giao diện · **Thì** **không** có chữ "AI" ở bất cứ đâu thuộc khử nhiễu | ✅ `EditorParityTests.noiseReductionNeverClaimsToBeAI` (tên nhóm, tên ngắn, tên đầy đủ của mọi slider Detail/RAW) |

## 9b. Tương thích recipe

- **App chưa release — không giữ tương thích ngược** (chốt 2026-09-23, ghi ở `CLAUDE.md`). Đổi nghĩa khoá,
  đổi thứ tự pipeline, đổi raw value: cứ làm, không quy đổi giá trị cũ, không cờ phiên bản, không ghi chú
  phát hành.
- **Không bump `formatVersion`** — nó là cổng khớp tuyệt đối, không phải cơ chế tương thích.
- **Decode khoan dung** (`ShotDexKit/Models/LossyDecoding.swift`) giữ nguyên, vì đó là **độ bền** chứ không
  phải tương thích: một mask, component, overlay hay preset không đọc được chỉ mất chính nó.

## 10. Việc còn treo

- ⚠️ **Versions** có làm không (§8) — bản iPad của Lightroom có, ta chưa xếp vào đâu.
- ⚠️ Thứ tự ship sáu mục: làm tuần tự 1→6, hay gộp 3+4 (đều rẻ) lên trước mục 2?
