# FS-05.04 — Đóng watermark lúc xuất

`FS-05.04` · tier D (Resize, màn Watermark) + A (Settings, sheet xuất) · `Data/Sources/SignaturePresetStore.swift`
· `ShotDexKit/Render/PhotoRenderService+Overlay.swift` · `Features/Editing/CompressionScreen.swift`
· `Features/Shared/PhotoShareSheet.swift` · `Data/Sources/ShareExportPipeline.swift` · nguồn intent
[user-wishes-research](../../_intents/2026-09-30-user-wishes-research.md) mục 6 · cập nhật 2026-10-02

**Một câu:** chữ ký đã lưu trong Markup ([FS-05.03 §8](03-canvas-gestures-and-render.md#8-preset-watermark)) được
đóng lên ảnh ở mọi lối xuất ra file — Resize, Share, sheet xuất của ảnh server, xuất ra Files (đợt 2 mục 4) — mà
không phải mở editor từng tấm.

## 1. Người dùng cần gì

Giao 200 ảnh proof cho khách, hay đăng 10 ảnh lên mạng, người chụp muốn mỗi tấm có logo và dòng credit ở cùng một
góc, cùng cỡ. Hôm nay chữ ký chỉ dán được trong editor, từng ảnh một, và còn đổi luôn bản trong thư viện.
Họ cần bật một lần lúc xuất, thấy trước dấu nằm đâu, và chắc chắn bản gốc không bị đóng dấu.

## 2. Phạm vi

**Có:** Resize (một ảnh và cả mẻ) · Share ở mọi lối của [FS-08.06 §2](../FS-08-settings/06-share-metadata-privacy.md),
gồm kéo thả · sheet xuất của ảnh server ([FS-17.06 §6](../FS-17-import-from-server/06-edit-and-export.md)) · xuất ra
Files (đợt 2 mục 4) · upload lên server **khi** lượt đó gửi bản render theo preset kích thước (đợt 2 mục 4).

**Cố ý không có:**
- Video — đóng dấu là mã hoá lại cả clip, cùng lý do FS-08.06 không ghi lại video. Video đi nguyên và có ghi chú.
- Upload bản gốc (All Originals, Only RAW, FS-15.02) — đó là bản lưu trữ; bản gốc có dấu là hỏng bản gốc.
- Save Copy của editor, Collage, Video Studio, Panorama — các màn này tự đặt chữ ký được bằng lớp của mình.
- Copy lên clipboard — giữ như hôm nay, không đóng dấu.
- Mọi extension. "Save to ShotDex" nhận ảnh **vào** thư viện, không gì rời máy; extension sửa ảnh là editor.
  Vì vậy không có đường đóng dấu nào chạy dưới trần ~120 MB.
- Tạo chữ ký mới ngoài editor — vẫn làm ở Markup → `⋯` → Save as Preset.
- App tự đóng dấu của chính nó — không bao giờ, kể cả bản dùng thử (intent mục 13).

## 3. Dấu được dựng thế nào

- Dấu là **cả cụm lớp** của preset, dựng thành **một khối**. Các lớp giữ vị trí với nhau theo cạnh ngắn, không theo
  khung ảnh lúc lưu. Vì nếu theo khung, logo và dòng credit tách xa nhau trên ảnh dọc.
  - Preset lưu thêm tỉ lệ khung của ảnh lúc lưu; thiếu thì coi là 3:2.
- Lớp kính lúp bị bỏ khỏi dấu, vì nó phóng một chỗ của một tấm ảnh cụ thể. Chữ, ảnh, hình và nét vẽ tay giữ nguyên.
- Token (`{camera}`, `{lens}`…) thay **theo từng ảnh** của mẻ, cùng nguồn giá trị mà editor dùng cho ảnh đó, và cùng
  luật bỏ cụm rỗng của [FS-05.02 §2](02-text-tokens-and-styling.md#2-token-exif).
- Dấu ghép **cuối cùng, ở kích thước xuất**, sau mọi chỉnh sửa và mọi lớp markup có sẵn của ảnh (FS-05.03 §7).
- Chỉ raster **khung bao của dấu**, không raster cả khung ảnh. Mẻ không có token thì raster một lần cho mỗi cỡ xuất.

| Thuộc tính | Dải | Mặc định | Lưu dạng | Hiển thị |
|---|---|---|---|---|
| Watermark | preset đã lưu | preset dùng lần trước | id preset | tên preset |
| Position | 9 điểm neo (3×3) | dưới-phải | điểm neo | lưới 3×3 |
| Margin | 0–10%, bước 0,5% | 3% | phần cạnh ngắn | `3%` |
| Size | chiều cao khối 1–25%, bước 1% | cỡ của preset lúc lưu | phần cạnh ngắn | `− 55 px +` trên ảnh đang xem trước, chạm số để gõ px |
| Opacity | 10–100%, bước 5% | 100% | phân số | `%`, nhân với độ mờ riêng của từng lớp |

- Điểm neo góc đặt góc tương ứng của khối cách hai cạnh ảnh đúng Margin. Neo giữa cạnh cách một cạnh, căn giữa theo
  chiều kia. Neo tâm thì bỏ qua Margin.
- **Size theo cạnh ngắn**, như luật cỡ chữ "px của ảnh" ([FS-03.17 §5 D13](../FS-03-photo-editor/17-wide-design.md)):
  ảnh 1080 px và ảnh 6000 px nhìn giống nhau. Số px là của ảnh đang xem trước; ảnh khác cỡ trong mẻ theo cùng tỉ lệ.
- Khối rộng hơn ảnh trừ hai Margin (chữ dài trên ảnh dọc 9:16) thì **thu đều cho vừa**, không cắt chữ, không xuống dòng.

## 4. Đặt ở đâu

Form xuất có **một hàng 44pt Watermark** (giá trị `Off` hoặc tên preset, `›`). Resize: giữa Metadata và Delete
Originals; sheet xuất: section riêng ngay dưới Format. Chạm → màn **Watermark** toàn màn tầng D, nền tối, Done trên
phải:
- iPhone 402×874: xem trước cao 320pt ở trên, pill `i / N` và vuốt ngang qua các ảnh của mẻ. Dưới là công tắc
  **Add Watermark**, hàng chip preset cao 48pt như chip Size của Resize, lưới **Position** 3×3 ô 36pt (120×120),
  slider **Margin** và **Opacity** 44pt, stepper **Size**.
- iPad 1376×1032 và Duo trong 951×669: xem trước bên trái, cột điều khiển 320pt bên phải, cuộn dọc.
- Duo ngoài: vùng 382pt sau rail 84pt; xem trước 382×240 ở trên, điều khiển cuộn bên dưới.

| Lối xuất | Bật/tắt mặc định | Đổi cho lần này |
|---|---|---|
| Resize, xuất ra Files, sheet xuất ảnh server, upload bản render | lựa chọn lần trước (§5) | hàng Watermark |
| Share, kéo thả | Settings → Sharing and Export → **Watermark When Sharing** (`Off` / tên preset; mặc định `Off`) | một dòng của app trong share sheet, như FS-08.06 §4 |

**Share** có thêm **một dòng hành động** của app, sau hai dòng mức metadata:
- *Share With Watermark* khi Watermark When Sharing là Off; *Share Without Watermark* khi nó là tên một preset.
- Đầu sheet giữ tiêu đề *"PhotoA · Location removed"*; dòng thứ hai thêm *"Watermark: Credit"*, nối các ghi chú
  khác bằng " · ". Chưa có preset nào thì không có dòng hành động lẫn ghi chú này.
- Chọn dòng nào thì share sheet đóng rồi mở lại, như dòng mức metadata. Lựa chọn một lần không ghi đè Settings.

## 5. Hành vi

- **Không bao giờ giao đi một ảnh không có dấu khi người dùng đã bật watermark.** Ảnh không đóng được dấu (RAW iOS
  không đọc được, file hỏng) bị bỏ khỏi mẻ và nêu tên, cùng chỗ với ảnh tải hỏng (modal của FS-02.06).
- **Bản gốc không bao giờ mang dấu.** Bật watermark thì Resize tắt và làm mờ **Delete Originals**, dòng phụ *"Originals
  are kept when you add a watermark."*; sheet xuất ảnh server làm mờ **Replace Original** với lý do *"Watermarked
  copies are saved as new files."* Vì nếu không, bản sạch duy nhất của tấm ảnh mất.
- **Render rồi mới ghi metadata.** File có dấu được mã hoá lại, rồi ghi metadata của file nguồn theo mức của lượt đó
  (FS-08.06 §3). Luật "nguyên byte" của All Metadata không áp khi có dấu.

| Nguồn | File ra khi có dấu |
|---|---|
| JPEG, HEIC, PNG, TIFF | cùng định dạng; JPEG và HEIC chất lượng 95% ở Share, chất lượng của form ở Resize và sheet xuất. HEIC ở No Metadata ra JPEG như FS-08.06 |
| RAW | JPEG đủ cỡ, giải RAW theo mặc định như *Share as JPEG*. **Không hỏi** alert RAW của FS-08.06, vì RAW không mang dấu được; dòng thứ hai của đầu sheet ghi *"RAW sent as JPEG"* |
| RAW iOS không đọc được | bỏ khỏi mẻ, nêu tên; cặp RAW+JPEG thì làm từ JPEG như [FS-03.07 §5](../FS-03-photo-editor/07-resize-and-compression.md) |
| Live Photo | ảnh tĩnh có dấu, như share hôm nay |
| Video | đi nguyên; ghi chú *"Videos aren't watermarked"* ở đầu share sheet và ở summary |

- **Ảnh chỉ có trên iCloud** tải bản gốc trước, trong modal của FS-02.06. Không đóng dấu lên bản xem trước.
- **Ảnh đã có chữ ký trong bản chỉnh sửa.** Bản chỉnh đã có lớp dán từ **cùng** preset thì ảnh đó **không** bị
  đóng thêm dấu; summary và đầu sheet ghi *"1 photo already had this watermark"*. Lớp dán từ preset mang theo id
  của preset. Lớp từ preset khác, hay lớp markup thường, không tính.
- **Nhớ lựa chọn.** Cấu hình (preset, Position, Margin, Size, Opacity) **và** bật/tắt được nhớ, chung cho mọi lối có
  form (Resize, xuất ra Files, sheet xuất ảnh server, upload bản render). Ngoại lệ có ghi ở FS-03.07 §1. *Vì chỉnh
  lại năm thứ mỗi lần là đúng cái người dùng than, và xem trước luôn vẽ dấu.* Share theo Settings (§4).
- **Xem trước.** Resize vẽ dấu lên xem trước 320pt (một ảnh) và lên từng trang của carousel 250pt (cả mẻ), bằng
  đúng bộ raster của bản xuất. Share không có xem trước; đầu sheet nói tên dấu.
- **Preset bị xoá** sau lần dùng trước: hàng về `Off`, không âm thầm lấy preset khác.
- **Preset mất file ảnh logo**: chip ghi *"Missing file"*, không chọn được. Font không còn thì lùi như FS-05.02 §5
  và chip ghi *"Unavailable"*; xuất vẫn chạy.
- **Chưa có preset nào**: hàng mờ, ghi `None`; màn Watermark nói *"No watermarks yet"* và *"In the editor, open
  Markup, set up a caption or a logo, then choose Save as Preset."*
- **Token rỗng hết** trên một ảnh (preset chỉ có `{lens}`, ảnh không có lens): ảnh đi không dấu và được nêu tên
  trong summary — không có gì để đóng, nhưng không im lặng.
- **Huỷ giữa mẻ** và **hết chỗ trống**: như lối xuất đó hôm nay (FS-03.07 §5, FS-08.06 §5, FS-17.06 §4). Không có
  Undo: không gì trong thư viện bị đổi.

## 6. Dữ liệu và ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Lưu ở đâu | cấu hình dấu, công tắc nhớ và Watermark When Sharing nằm trong cài đặt của app, cạnh preset. **Không** đụng database, không cột `photo_metadata` ([BD-02](../../01-basic-design/BD-02-database-design.md)) |
| Bộ nhớ | đỉnh RAM khi đóng dấu một ảnh 48MP cao hơn lúc xuất không dấu ≤ 40 MB — không có bitmap cỡ cả khung (~195 MB, FS-05.01 AC-38). Mẻ đi tuần tự, một ảnh một lúc ([NF-02](../../04-non-functional-design/NF-02-memory-and-resources.md)) |
| Thiết bị | iPhone 402×874 · iPad 1376×1032 · Duo trong 951×669 · Duo ngoài 466×678 (382pt sau rail); phone có đủ mọi thứ của iPad |
| iOS 26 vs trước | hai nhánh có cùng hàng, cùng màn, cùng dòng share; không dùng API iOS 27 |
| Truy cập | lưới Position đọc *"Position, bottom right"*; Size đọc giá trị px; chip preset đọc tên và *"Missing file"* |
| Chữ | String Catalog; một tên **Watermark** ở form, Settings và share sheet |

Design canvas: chưa có board Resize, Share hay sheet xuất. Cần thêm vào canvas editor, nối vào hàng của từng thiết
bị: màn Watermark và Resize có hàng Watermark ở hàng `PH*`, `IP*`, `DI*`, `DC*`. Canvas Video Studio không đổi.

## 7. Tiêu chí nghiệm thu

Ảnh **A** = JPEG 6000×4000, Sony ILCE-7M4, GPS 10.7769 N 106.7009 E. Preset **Credit** = một dòng chữ trắng
`© Nguyen An · {camera}` + logo PNG 400×400, lưu từ ảnh 3:2 ngang. Cấu hình **W** = Credit, dưới-phải, Margin 3%,
Size 4%, Opacity 100%.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | ảnh A, Resize 2048px, cấu hình W | Save to Photos | ảnh mới 2048×1365; khung bao của dấu có cạnh phải x = 2007 ±1, cạnh dưới y = 1324 ±1, cao 55 ±1 px; mọi pixel ngoài khung bao trùng bản Resize không dấu | ⚠️ chưa có |
| AC-2 | như AC-1 | mở Resize | xem trước 320pt có dấu ở dưới-phải; tâm khung bao lệch ≤ 1pt so với vị trí tính từ AC-1. Ảnh trên iPhone, iPad, Duo trong, Duo ngoài | ⚠️ chưa có |
| AC-3 | 3 ảnh của Sony ILCE-7M4, Fujifilm X-T5, iPhone 17 Pro; cấu hình W | Resize 3 ảnh | chữ trong dấu của từng file lần lượt là `© Nguyen An · Sony ILCE-7M4`, `… Fujifilm X-T5`, `… iPhone 17 Pro` | ⚠️ chưa có (luật token: `OverlayTokenResolverTests`) |
| AC-4 | Settings: Watermark When Sharing = Credit, Metadata = No Location; ảnh A | Share → Save to Files | file JPEG có dấu ở dưới-phải; không có nhóm GPS; còn Make `SONY`, Model `ILCE-7M4` | ⚠️ chưa có |
| AC-5 | Settings: Watermark When Sharing = Off; ảnh A | Share, chạm *Share With Watermark* | sheet đóng rồi mở lại, dòng thứ hai có *Watermark: Credit*; file nhận được có dấu; Settings vẫn Off | ⚠️ chưa có |
| AC-6 | ARW Sony 6000×4000 iOS đọc được + RAF máy mới iOS chưa đọc + ảnh A; Settings: Watermark When Sharing = Credit | Share → Save to Files | không có alert RAW; Files nhận 2 file: JPEG 6000×4000 có dấu từ ARW, và A có dấu; RAF bị bỏ và nêu tên trong modal; đầu sheet có *RAW sent as JPEG* | ⚠️ chưa có |
| AC-7 | ảnh A + MOV 10,0 s; Settings: Watermark When Sharing = Credit | Share → Save to Files | SHA-256 của MOV nhận được bằng file gốc; A có dấu; đầu sheet có *Videos aren't watermarked* | ⚠️ chưa có |
| AC-8 | 5 ảnh, Resize, Delete Originals đang bật | bật watermark | Delete Originals tắt và mờ, dòng phụ *Originals are kept when you add a watermark.*; chạy xong thư viện vẫn còn đủ 5 bản gốc | ⚠️ chưa có |
| AC-9 | 2 JPEG trên NAS đã sửa; sheet xuất, đích Original Folder, cấu hình W | mở hàng Watermark rồi Done | Replace Original mờ, lý do *Watermarked copies are saved as new files.*; Export tạo `<tên>_edited.jpg` có dấu; 2 file gốc trên NAS giữ SHA-256 | ⚠️ chưa có |
| AC-10 | ảnh dọc, Resize ra 1080×1920; dấu ở Size 4% có bề rộng tự nhiên 1200 px | Save to Photos | khối thu đều còn rộng 1080 − 2×32 = 1016 ±1 px; không lớp nào bị cắt; tỉ lệ khối giữ nguyên | ⚠️ chưa có |
| AC-11 | ảnh A đã có lớp dán từ Credit trong editor | Resize với cấu hình W | ảnh ra chỉ có **một** dấu Credit; summary ghi *1 photo already had this watermark* | ⚠️ chưa có |
| AC-12 | Resize: Credit, trên-trái, Margin 5%, Opacity 60% rồi Save | mở Resize cho một ảnh khác, rồi sheet Export ra Files | ở cả hai form hàng Watermark ghi *Credit*; màn Watermark mở ở trên-trái, 5%, 60%, công tắc bật | ⚠️ chưa có |
| AC-13 | lần trước dùng preset **Logo**; file ảnh logo của nó đã bị xoá khỏi thư mục của app | mở Resize | hàng Watermark ghi `Off`; chip Logo trong màn Watermark ghi *Missing file* và không chọn được | ⚠️ chưa có (lưu preset: `PhotoOverlayModelsTests.signaturePresetRoundTrips`) |
| AC-14 | HEIC 48MP 8064×6048, Resize Original, cấu hình W | Save to Photos | đỉnh RAM cao hơn cùng lượt không dấu ≤ 40 MB, đo trên iPhone 17 26.5 | ⚠️ chưa có |
| AC-15 | 10 ảnh, 4 ảnh chỉ có trên iCloud; Settings: Watermark When Sharing = Credit | Share → Save to Files | modal FS-02.06 tải 4 bản gốc; Files nhận 10 file có dấu, mỗi file đúng cỡ pixel của bản gốc, không file nào ở cỡ bản xem trước | ⚠️ chưa có (modal tải: `CompressionPreparationTests.copiesReadThePreparedOriginals`) |

**Chưa chứng minh được:** AC-1…AC-15 — chưa có code.

## 8. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| mã hoá lại HEIC/JPEG để đóng dấu làm mất gain map HDR và depth của ảnh Portrait | chấp nhận: file có dấu là SDR. Đo lúc `/plan` xem Core Image giữ được gain map khi ghép dấu hay không |
| tên trong editor là "Presets" / "Sign" / "Rename Signature", còn lối xuất gọi là "Watermark" | chạy `copy-consistency` sau khi làm; spec này dùng **Watermark** ở mọi lối xuất |
| hai lối (Resize nhớ lựa chọn, Share theo Settings) có thể làm người dùng quên dấu đang bật | xem trước luôn vẽ dấu; đầu share sheet luôn nêu tên dấu |
| dấu màu trắng trên trời trắng không đọc được | không tự đổi màu theo nền; người dùng chọn preset khác hoặc thêm viền/bóng trong editor |
