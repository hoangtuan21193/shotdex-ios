# FS-03.04b — RAW iOS chưa đọc được

`FS-03.04b` · `ShotDexKit/Render/PhotoRenderService.swift` · `Domain/Editing/EditorLoadFailure.swift`
· `Features/Shared/PhotoGridCollectionView.swift` · cập nhật 2026-10-01 (quyết định của `/plan` đã duyệt; JPEG → Edit RAW bắt đầu từ bản gốc)

**Một câu:** ảnh RAW mà iOS trên máy chưa giải được thì có dấu ngay trong thư viện, và mọi lối mở nó nói máy nào,
bản iOS nào, làm gì tiếp — chuyển DNG, chờ iOS, hay sửa JPEG đi kèm.

Nguồn intent: [2026-09-30-user-wishes-research](../../_intents/2026-09-30-user-wishes-research.md) mục 2. Luật RAW
chung và render: [FS-03.04](04-raw-and-render-graph.md).

## 1. Người dùng cần gì

Apple thêm máy mới vào bộ giải RAW chậm từ 6 tháng. Người chụp cần biết *trước khi mở editor* ảnh nào sửa không
được, vì máy nào, và làm gì: chuyển DNG, chờ bản iOS mới, hoặc sửa JPEG đi kèm.

Code 2026-10-01 chỉ có một câu chung, hiện sau khi đã tải cả file; cặp RAW+JPEG cũng hỏng vì nguồn mặc định là
RAW; chọn RAW trong menu Source thì lỗi bị nuốt. Mục này thay cả ba.

## 2. Biết trước bằng cách nào

- Đơn vị phán quyết là **máy ảnh × bản build iOS**, không phải từng ảnh: mỗi máy chỉ cần xét một file.
- Danh sách máy mà bộ giải của hệ thống công bố **lệch tên với EXIF** (đo 2026-10-01, macOS 27.0, 928 mục):
  - "Nikon Z 6 2" với EXIF `NIKON Z 6_2`; "Sony Alpha ILCE-7M4" với Make `SONY`, Model `ILCE-7M4`;
  - cùng một máy có hai tên ("Sony Alpha ILCE-7M IV" và "ILCE-7M4"); danh sách không nói tới chế độ nén của file.
  - **Đo trên sim 2026-10-02 (M1)**: 930 mục trên iOS 26.5, 932 trên 27.0 (thêm Leica M10-R, Leica S3, Leica V-Lux 3,
    Sony RX10V; bỏ Mamiya Leaf Credo 40MP, Phase One P40+; "Fujifilm FinePix HS20" đổi thành "… HS20 EXR"), 825–934
    trên các sim 18.6 (bộ giải là MobileAsset `RawCamera.bundle`, mỗi sim một bản). Có "Nikon Z 6 2", "Sony Alpha
    ILCE-7M4", "Fujifilm X-T4"; iPhone ghi bằng mã máy ("iPhone16,1 …"); **không có máy DNG nào** (DJI, ProRAW) —
    DNG luôn đi bậc 2.
  - **`CIRAWFilter(imageURL:)` không bao giờ trả nil** (26.5, 27.0, 18.6): file rác đuôi `.ARW` cho object có
    `outputImage` rỗng 0 × 0; RAF của máy lạ (X-T4 đổi tên thành `X-Q9`) và ARW/DNG cắt cụt cho `outputImage` nil.
    "Giải được" là `outputImage` khác nil và khác rỗng. Make/Model vẫn đọc được qua ImageIO ở file máy lạ và file cắt
    cụt; file rác và 2 KB đầu của ARW thì ImageIO không đọc nổi thuộc tính (AC-9). Đổi tên máy trong ARW (Sony) hay
    DNG (DJI) thì bộ giải vẫn đọc — chỉ RAF bị bộ giải chặn theo tên máy.
- Vì thế **không khớp tên không được coi là "chưa hỗ trợ"** — đánh dấu nhầm máy đọc được tệ hơn không đánh dấu.
- **Nguồn phán quyết** đi theo ba bậc, dừng ở bậc đầu tiên cho ra kết quả:
  1. tên máy **khớp** danh sách của bộ giải hệ thống ⇒ "đọc được";
  2. không khớp ⇒ thử giải **một file có sẵn trên máy** của máy đó (chép ra thư mục tạm, không decode ảnh);
     giải được ⇒ "đọc được". Hỏng ⇒ thử thêm **một file có sẵn khác** của cùng máy; cũng hỏng mới ghi "chưa đọc
     được" (người dùng chốt 2026-10-01 — một file hỏng riêng không được kéo cả máy). Máy chỉ có đúng một file trên
     máy thì một lần hỏng là đủ;
  3. mọi file của máy đó chỉ có trên iCloud ⇒ "chưa biết" tới khi editor mở một file. Không tải gì chỉ để xét.
- Kết quả thật của mỗi lần editor mở file **đè** phán quyết "chưa biết". Máy đã "đọc được" mà một file vẫn hỏng
  (chế độ nén lạ) thì chỉ file đó báo lỗi; máy không bị đổi phán quyết.
- Phán quyết gắn với **bản build iOS**: lên bản build mới thì xét lại ở lần mở app kế tiếp.
- "Ảnh này là RAW-only" lấy từ đuôi tên file đã index, qua **cùng bảng đuôi** của nhãn định dạng trên tile.
  App có **một** bảng đuôi RAW duy nhất — bảng của nhãn định dạng tile, thêm `FFF` — dùng chung cho nhãn định dạng
  trong viewer, smart album kiểu RAW và luật RAW-only này (người dùng chốt 2026-10-01).
  Cặp RAW+JPEG không được đánh dấu ở lưới: lưới, viewer và mọi màn khác vẫn hiện JPEG bình thường.

## 3. Hiển thị

- **Tile lưới** ([FS-01.01b §6](../FS-01-library/01b-grid-engine-and-gestures.md)): ảnh RAW-only của máy "chưa
  đọc được" mang glyph **tam giác cảnh báo** trắng 10pt ở hàng glyph trạng thái; VoiceOver đọc "RAW not supported
  by iOS". Glyph chỉ là dấu: chạm tile vẫn mở viewer như mọi tile. Vì 10pt không đủ vùng chạm 44pt.
- **Viewer** có cùng glyph ở bảng thông tin, vùng chạm ≥ 44pt. Chạm glyph mở một thẻ:
  *"Nikon Z5II — iOS 27.0 can't read RAW files from this camera yet. You can still view the preview, but you
  can't edit the RAW."*
- Glyph phải vào từ điển icon của `DESIGN.md` §8 — người dùng tự sửa file đó.
- **Mục lọc "Unsupported RAW"** nằm trong menu con kiểu chụp ([FS-01.05 §3](../FS-01-library/05-filtering-and-sorting.md)),
  gom mọi ảnh RAW-only của máy "chưa đọc được" để chuyển DNG một lượt. Máy "chưa biết" không vào mục này.
  - Là mục thứ hai sau Panoramas không do hệ thống định nghĩa: nó hỏi bảng phán quyết (§5), không hỏi bitmask.
  - Có cả trong menu lọc của màn album ([FS-06.09](../FS-06-collections/09-album-filter-menu.md)): ở đó lọc bằng
    danh sách id ảnh lấy từ index, giới hạn trong tập id của album, như Panoramas do ShotDex ghép.
- **Thông báo**, một câu nói máy, một câu nói việc cần làm (tiếng Anh, qua String Catalog):
  - biết máy: *"iOS 27.0 doesn't support RAW files from the Nikon Z5II yet. Convert the file to DNG with Adobe DNG
    Converter, or wait for an iOS update that adds this camera."*;
  - không có tên máy trong EXIF: như trên, thay tên máy bằng đuôi file (*"RAW files like this .ARW"*);
  - file DNG vẫn hỏng và không có JPEG đi kèm: *"iOS 27.0 can't read this DNG file. Convert the original again
    with the latest Adobe DNG Converter, or share it to edit on a computer."*, hai nút **Share Original** · **OK**.
    Share Original gửi nguyên byte file gốc qua share sheet. Vì NF-04 bắt mọi lỗi có lối ra.
    Settings → Metadata When Sharing không phải All Metadata thì Share Original đi qua alert RAW của
    [FS-08.06 §5](../FS-08-settings/06-share-metadata-privacy.md): **Share as JPEG** mờ kèm lý do *"iOS can't read
    this RAW yet"* (không render được RAW này); còn **Share RAW with Location** · **Skip**.
- Tên máy lấy từ index đã chuẩn hoá ([BD-05](../../01-basic-design/BD-05-imaging-business-rules.md)); chưa index thì
  đọc Make/Model trong đầu file lúc mở. Phiên bản iOS lấy từ hệ thống, không viết cứng.
- Phán quyết đã có thì **Edit không tải gì**: thông báo hiện ngay, editor không mở, không có spinner iCloud.
- **Mọi cặp RAW+JPEG hỏi trước khi editor mở**, máy đọc được hay không: action sheet *"Edit which version?"* →
  **Edit RAW** · **Edit JPEG** · **Cancel**.
  - Máy "chưa đọc được": Edit RAW mờ, kèm dòng lý do *"iOS can't read this RAW yet"*.
  - Không nhớ lựa chọn: lần Edit sau lại hỏi.
  - Cặp đã có bản sửa ShotDex trên RAW mà người dùng chọn **Edit JPEG**: bản sửa mang sang JPEG, bỏ năm thông
    số chỉ có ở nhóm RAW (Temperature, Tint, Sharpness, Luminance Noise, Color Noise của nhóm RAW) — người dùng
    chốt 2026-10-01.
  - Chiều ngược lại: cặp đã có bản sửa ShotDex trên JPEG mà người dùng chọn **Edit RAW**: editor mở RAW **từ bản
    gốc**, không mang gì của bản sửa JPEG sang — người dùng chốt 2026-10-01.
  - Menu Source trong editor vẫn có; với máy "chưa đọc được", RAW trong menu đó mờ kèm cùng lý do. Bốn mục RAW
    của Adjust ẩn như mọi nguồn không phải RAW.
- Lỗi của bộ giải luôn ra **đúng thông báo RAW** kể cả khi ImageIO không đọc nổi thuộc tính file — nguồn là RAW
  theo UTI của file thì không bao giờ rơi về câu chung "The photo couldn't be decoded.".

## 4. Các lối khác dùng cùng ảnh

| Lối | Hành vi |
|---|---|
| Resize | RAW-only: ảnh đó vào danh sách lỗi của lượt chạy, kèm đúng câu thông báo; ảnh khác vẫn chạy ([FS-03.07](07-resize-and-compression.md)). **Cặp** RAW+JPEG mà RAW không đọc được: Resize dùng JPEG của cặp |
| Editor nhiều ảnh (chọn nhiều → Edit) | tới lượt ảnh RAW không đọc được thì hiện đúng thông báo, kèm **Skip** sang ảnh kế; các ảnh khác sửa bình thường |
| Collage · Video Studio | hỏi trước khi thêm ảnh (dưới bảng) |
| Combine (HDR, Focus Stack, Panorama) | **đợt sau** — dòng ở `REVIEW_QUEUE.md` (người dùng chốt 2026-10-01) |
| Duplicates | không đổi — so bằng thumbnail của PhotoKit |
| Share | gửi nguyên file gốc, không cần giải |
| Edit in ShotDex, ảnh trên file server | **đợt sau** — dòng ở `REVIEW_QUEUE.md`. Hướng khi làm: cùng thông báo, cùng luật cặp RAW+JPEG ([EX-05](../../03-extensions-and-integrations/EX-05-edit-action-extension.md), [FS-17](../FS-17-import-from-server/README.md)) |

- **Thêm RAW "chưa đọc được" vào Collage hay Video Studio thì hỏi trước**, một lần cho cả lượt thêm.
  Vì luật intent: không bao giờ âm thầm xuất ra bản xem trước.
  - *"2 RAW photos can't be read on this iOS"* — *"Convert them to JPEG first? ShotDex uses the JPEG preview
    inside the RAW (1616 × 1080)."* Các ảnh khác cỡ thì nêu cỡ nhỏ nhất.
  - **Convert to JPEG** — dùng bản xem trước nhúng ở đúng cỡ của nó; không ghi gì vào thư viện.
  - **Skip These 2** — thêm các ảnh còn lại; **Cancel** — không thêm ảnh nào.

## 5. Dữ liệu

- Phán quyết là **kết quả quét**, không phải dữ liệu người dùng: bảng vệ tinh mới, một dòng mỗi máy × bản build
  iOS (máy · bản build · kết quả · nguồn: danh sách / thử file / editor · lúc nào).
- Không thêm cột vào bảng metadata chính ([BD-02 §1](../../01-basic-design/BD-02-database-design.md)).
- Lưới không hỏi database ở từng ô ([NF-01](../../04-non-functional-design/NF-01-performance.md)): dấu đi cùng lượt nạp lưới.
- Có bảng mới thì sửa BD-02 §3 trong cùng lượt làm; app chưa release nên không cần tương thích ngược.

## 6. Tiêu chí nghiệm thu

iOS 27.0 trong bảng là ví dụ; câu thật lấy phiên bản từ hệ thống.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | 12 NEF RAW-only, EXIF `NIKON Z 6_2`, danh sách hệ thống có "Nikon Z 6 2" | lượt xét phán quyết chạy | máy ghi "đọc được"; 0 trong 12 tile có dấu | ✅ `RAWVerdictPassTests.listedCameraIsReadableWithoutAProbe`, `RAWDecoderVerdictTests` (tên đo trên 26.5 + danh sách thật của sim), `RAWVerdictStoreTests`, `FileTypeBadgeTests.oneListEverywhere`; "0 dấu" theo lưới: task 4 |
| AC-2 | 8 ARW RAW-only (có sẵn trên máy) của máy không khớp danh sách, bộ giải trả rỗng, và 5 HEIC | lượt xét chạy xong | đúng 8 tile có glyph tam giác ở hàng glyph trạng thái, VoiceOver đọc "RAW not supported by iOS"; 5 HEIC không có; chạm tile mở viewer | ✅ `UnsupportedRAWIndexTests.refusedCameraMarksItsRAWsOnly` (8 / 0 HEIC, thử đúng 2 file), `.secondFileDecodingKeepsTheCameraReadable` (Q5), `.onlyLocalFileRefusedMarks`, `.pairKeptAsRAWIsNotMarked`, `.otherBuildsVerdictIsIgnored`; `SystemRAWDecoderProbeTests` (bộ giải thật của sim: RAF máy X-Q9 → từ chối, ARW → đọc, cặp hai thứ tự) · iPhone 17 26.5 (2026-10-02, `unsupported-raw-grid.json`): sau Re-index lượt xét ghi Fujifilm X-Q9 = unreadable (file), tile `M3D.RAF` có tam giác trắng ở hàng glyph (ô trống vì Photos không trả thumbnail cho RAF này — M3), dump: *Photo, file type RAW, ISO 160 · 16mm · f/3.6, RAW not supported by iOS*; các RAW khác (Sony, DJI, Leica, OM) và HEIC không có. Chạm tile mở viewer: AC-17. iPad, Duo, 18.6: chưa chụp |
| AC-3 | 1 ảnh của AC-2, máy tên "Sony ILCE-7M5" trong index | bấm Edit ở Photo Detail; rồi chọn ảnh đó cùng 2 JPEG và Edit (nhiều ảnh) | lần 1: thông báo đủ hai câu, có "Sony ILCE-7M5" và "iOS 27.0"; editor không mở. Lần 2: tới ảnh đó thì hiện cùng thông báo kèm Skip; Skip sang ảnh kế, 2 JPEG sửa và lưu được | ✅ `UnsupportedRAWMessageTests` (câu đúng chữ với "Sony ILCE-7M5" + "iOS 27.0"; từ index trước khi tải gì; từ đầu file RAF máy X-Q9; `EditorLoadFailure.unsupportedRAW`), `MultiPhotoEditSkipTests` (Skip sang ảnh kế, ảnh cuối thì về ảnh trước; editor nhiều ảnh có Skip thay vì đóng) · iPhone 17 26.5 (2026-10-02, MCP tap + `Tools/sim-shot`): viewer `M3D.RAF` → Edit → alert *Can't Edit This RAW* "iOS 26.5 doesn't support RAW files from the Fujifilm X-Q9 yet. …" + OK, editor không mở; chọn 2 JPG + RAF → Edit → chạm RAF ở filmstrip → cùng alert với **Skip** → về JPG 2/3, sửa tiếp được. Chưa bấm Save trên sim (không sửa ảnh mẫu dùng chung) |
| AC-4 | ảnh của AC-2 chỉ có trên iCloud, phán quyết đã có | bấm Edit | thông báo hiện trong ≤ 1 s, 0 byte tải về, không có spinner "Downloading from iCloud…" | ✅ `UnsupportedRAWGateTimingTests.answerComesFromTheIndexAlone` (câu trả về < 1 s trên index 6 008 dòng, 0 lần hỏi bộ giải/PhotoKit), `.editorFailsWithoutLoading` (editor nhiều ảnh: không session, không phần trăm tải, không spinner), `.viewerAsksTheIndexFirst` · iPhone 17 26.5: alert hiện ngay trên viewer, không có màn editor (ảnh ở AC-3). Phần "0 byte từ iCloud" trên ảnh thật chỉ trên iCloud: chờ máy thật (sim không có iCloud) |
| AC-5 | cặp RAW+JPEG của máy "chưa đọc được" | bấm Edit, chọn Edit JPEG | action sheet *Edit which version?* có Edit RAW mờ kèm *iOS can't read this RAW yet*; editor mở JPEG; menu Source có RAW mờ; không có mục White Balance | ⚠️ chưa có |
| AC-6 | ARW RAW-only, Make/Model trong EXIF rỗng, bộ giải trả rỗng | bấm Edit | thông báo nói ".ARW", không có tên máy; trước đó tile **không** có dấu (không biết ≠ chưa hỗ trợ) | ⚠️ chưa có |
| AC-7 | file DNG RAW-only mà bộ giải trả rỗng | bấm Edit | thông báo "can't read this DNG file" kèm câu nhắc "latest Adobe DNG Converter"; hai nút Share Original · OK | ⚠️ chưa có |
| AC-8 | như AC-7; Settings → Metadata When Sharing = All Metadata | bấm Share Original | share sheet mở với đúng file DNG gốc, cùng số byte với tài nguyên gốc trong Photos; đổi Settings sang No Location rồi bấm lại → alert RAW của FS-08.06 có Share as JPEG mờ kèm *iOS can't read this RAW yet*, chọn Share RAW with Location → cùng file DNG nguyên byte | ⚠️ chưa có |
| AC-9 | file RAW mà ImageIO không đọc nổi cả thuộc tính | bấm Edit | vẫn là thông báo RAW (dạng có tên máy hoặc đuôi file), không phải "The photo couldn't be decoded." | ✅ `PhotoRenderServiceInspectTests.unreadableHeaderOfARAWIsUnsupported` (file rác đuôi `.ARW`, và cùng file không đuôi với UTI ARW), `.firstTwoKilobytesOfAnARWAreUnsupported` (2 KB đầu ARW thật: `.unsupportedRAW`, câu "RAW files like this .ARW", không có "couldn't be decoded"), `.junkJPEGIsStillCannotDecode` |
| AC-10 | máy "chưa biết" (mọi file chỉ trên iCloud), 6 ảnh; editor mở 1 ảnh và bộ giải hỏng | đóng thông báo, về lưới | 6 tile của máy đó có dấu, không cần mở lại app | ⚠️ chưa có |
| AC-11 | phán quyết "chưa đọc được" ghi ở iOS 27.0; máy lên 27.1 và bộ giải đọc được | mở app | máy được xét lại, 0 tile còn dấu, Edit mở editor bình thường | ⚠️ chưa có |
| AC-12 | 3 ARW RAW-only của máy không khớp danh sách, cả 3 chỉ trên iCloud | lượt xét chạy xong | máy ghi "chưa biết"; 0 byte tải về; 0 tile có dấu | ✅ `RAWVerdictPassTests.iCloudOnlyCameraIsUnknown`, `.unknownIsRejudgedWhenAFileArrives`, `.systemProbeNeverUsesTheNetwork`; 0 tile có dấu khi máy "chưa biết": `UnsupportedRAWIndexTests` (task 4). Máy thật cho phần 0 byte iCloud |
| AC-13 | 8 ảnh của AC-2, 3 ảnh của AC-12, 5 HEIC; một album chứa 4 ảnh của AC-2 + 2 HEIC | chọn **Unsupported RAW** trong menu con kiểu chụp, ở Library rồi ở album đó | Library còn đúng 8 ảnh của AC-2; album còn đúng 4 | ⚠️ chưa có |
| AC-14 | Resize 4 ảnh: 2 JPEG + 1 ảnh của AC-2 + 1 cặp RAW+JPEG của máy "chưa đọc được" | chạy Resize | 3 bản mới trong Photos (bản của cặp làm từ JPEG của cặp); danh sách lỗi có 1 dòng mang câu của AC-3; không tạo file từ bản xem trước | ✅ `CompressionRAWPairTests` (vòng chạy: 3 bản, 1 dòng lỗi, chỉ xoá 3 gốc; `unreadablePairUsesJPEG`; preview lấy ảnh đọc được đầu tiên), `PhotoRenderServiceInspectTests` (bộ giải từ chối → `.unsupportedRAW`); câu của AC-3 trong dòng lỗi: `UnsupportedRAWMessageTests.resizeFallsBackOnTheNamedError` (lỗi mang câu AC-3, cặp vẫn về JPEG) — dòng lỗi là `localizedDescription` của lỗi đó |
| AC-15 | Collage, chọn 4 ảnh trong đó 1 ảnh của AC-2 | thêm vào collage | hỏi *1 RAW photo can't be read on this iOS* với Convert to JPEG · Skip These 1 · Cancel; Convert → ô đó dùng bản xem trước đúng cỡ nhúng, 0 asset mới trước khi Save; Skip → collage 3 ảnh; Cancel → không thêm ảnh nào | ⚠️ chưa có |
| AC-16 | cặp RAW+JPEG của máy đọc được | bấm Edit ba lần: lần 1 chọn Edit RAW, chỉnh Exposure +1 và Temperature của nhóm RAW, Save Changes; lần 2 chọn Edit JPEG, chỉnh Contrast +20, Save Changes; lần 3 chọn Edit RAW | lần 1 action sheet có cả hai mục sáng, editor mở RAW; lần 2 action sheet hiện lại, editor mở JPEG có Exposure +1, không có Temperature của nhóm RAW; lần 3 action sheet hiện lại, editor mở RAW từ bản gốc: Exposure 0, Contrast 0, không mang gì của bản sửa JPEG | ⚠️ chưa có |
| AC-17 | ảnh của AC-2 mở trong viewer | chạm glyph tam giác ở bảng thông tin | thẻ có tên máy, "iOS 27.0" và câu "You can still view the preview, but you can't edit the RAW."; vùng chạm ≥ 44pt | ⚠️ chưa có |
| AC-18 | Video Studio, thêm 5 ảnh, 2 ảnh của AC-2 | chọn Skip These 2 | timeline có đúng 3 clip ảnh; không có clip nào từ bản xem trước | ⚠️ chưa có |

**Chưa chứng minh được:** AC-1…AC-18. Cần một file RAW thật của máy mà iOS trên sim chưa đọc (không có mặt người), và
một cách giả bộ giải trả rỗng trong test.

## 7. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Danh sách máy trên iOS có thể khác bản macOS đã đo | đã đo (M1, §2): 930 / 932 mục, khác nhau 9 dòng; bậc 1 chỉ ghi "đọc được", nên lệch tên chỉ đẩy máy xuống bậc 2 |
| Thứ tự file của cặp RAW+JPEG: index có thể ghi tên file RAW, làm cặp trông như RAW-only | **đo M3 (sim 26.5, 2026-10-02)**: cặp theo thứ tự Photos và ShotDex tự tạo (JPEG `.photo` + RAW `.alternatePhoto`) → index ghi tên JPEG, không trông như RAW-only. Thứ tự ngược (RAW `.photo` + JPEG `.alternatePhoto`, khi người dùng chọn RAW làm bản gốc) → index ghi tên RAW. Vì vậy lượt xét hỏi `assetResources` của từng ảnh mang đuôi RAW thuộc máy không khớp (không tải gì) và ghi riêng những ảnh có kèm bản JPEG/HEIC; ảnh đó không bao giờ có dấu |
| Bản xem trước nhúng có độ phân giải khác nhau theo máy; PhotoKit có thể không trả gì | **đo M3**: Photos nhận RAW-only hỏng (ARW/DNG cắt cụt, RAF máy lạ), chỉ từ chối file rác (`PHPhotosError` 3302). `requestImage` cỡ tối đa: RAF máy lạ → **nil** (lỗi -1, tile trống) dù ImageIO đọc được bản nhúng 4416 × 2944; ARW/DNG cắt cụt → 160 × 120; ARW đọc được → 1616 × 1080. Convert to JPEG (Collage, Video Studio) vì thế lấy bản nhúng bằng ImageIO từ file gốc có sẵn, không qua `requestImage`. Tile trống vẫn có dấu |
| Share tắt vị trí: ImageIO không ghi được kiểu RAW nào (đo macOS 27.0: 22 kiểu, không có RAW/DNG), nên file RAW đi **còn nguyên GPS** | alert RAW của FS-08.06 §5; Share Original của RAW không đọc được đi qua alert đó với Share as JPEG mờ (§3) |
