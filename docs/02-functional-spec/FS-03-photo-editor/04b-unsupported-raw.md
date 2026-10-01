# FS-03.04b — RAW iOS chưa đọc được

`FS-03.04b` · `ShotDexKit/Render/PhotoRenderService.swift` · `Domain/Editing/EditorLoadFailure.swift`
· `Features/Shared/PhotoGridCollectionView.swift` · cập nhật 2026-10-01

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
- Vì thế **không khớp tên không được coi là "chưa hỗ trợ"** — đánh dấu nhầm máy đọc được tệ hơn không đánh dấu.
- **Nguồn phán quyết** đi theo ba bậc, dừng ở bậc đầu tiên cho ra kết quả:
  1. tên máy **khớp** danh sách của bộ giải hệ thống ⇒ "đọc được";
  2. không khớp ⇒ thử giải **một file có sẵn trên máy** của máy đó (chép ra thư mục tạm, không decode ảnh);
     giải được ⇒ "đọc được", hỏng ⇒ "chưa đọc được";
  3. mọi file của máy đó chỉ có trên iCloud ⇒ "chưa biết" tới khi editor mở một file. Không tải gì chỉ để xét.
- Kết quả thật của mỗi lần editor mở file **đè** phán quyết "chưa biết". Máy đã "đọc được" mà một file vẫn hỏng
  (chế độ nén lạ) thì chỉ file đó báo lỗi; máy không bị đổi phán quyết.
- Phán quyết gắn với **bản build iOS**: lên bản build mới thì xét lại ở lần mở app kế tiếp.
- "Ảnh này là RAW-only" lấy từ đuôi tên file đã index, qua **cùng bảng đuôi** của nhãn định dạng trên tile.
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
- **Thông báo**, một câu nói máy, một câu nói việc cần làm (tiếng Anh, qua String Catalog):
  - biết máy: *"iOS 27.0 doesn't support RAW files from the Nikon Z5II yet. Convert the file to DNG with Adobe DNG
    Converter, or wait for an iOS update that adds this camera."*;
  - không có tên máy trong EXIF: như trên, thay tên máy bằng đuôi file (*"RAW files like this .ARW"*);
  - file DNG vẫn hỏng và không có JPEG đi kèm: *"iOS 27.0 can't read this DNG file. Convert the original again
    with the latest Adobe DNG Converter, or share it to edit on a computer."*, hai nút **Share Original** · **OK**.
    Share Original gửi nguyên byte file gốc qua share sheet. Vì NF-04 bắt mọi lỗi có lối ra.
- Tên máy lấy từ index đã chuẩn hoá ([BD-05](../../01-basic-design/BD-05-imaging-business-rules.md)); chưa index thì
  đọc Make/Model trong đầu file lúc mở. Phiên bản iOS lấy từ hệ thống, không viết cứng.
- Phán quyết đã có thì **Edit không tải gì**: thông báo hiện ngay, editor không mở, không có spinner iCloud.
- **Mọi cặp RAW+JPEG hỏi trước khi editor mở**, máy đọc được hay không: action sheet *"Edit which version?"* →
  **Edit RAW** · **Edit JPEG** · **Cancel**.
  - Máy "chưa đọc được": Edit RAW mờ, kèm dòng lý do *"iOS can't read this RAW yet"*.
  - Không nhớ lựa chọn: lần Edit sau lại hỏi.
  - Menu Source trong editor vẫn có; với máy "chưa đọc được", RAW trong menu đó mờ kèm cùng lý do. Bốn mục RAW
    của Adjust ẩn như mọi nguồn không phải RAW.
- Lỗi của bộ giải luôn ra **đúng thông báo RAW** kể cả khi ImageIO không đọc nổi thuộc tính file — nguồn là RAW
  theo UTI của file thì không bao giờ rơi về câu chung "The photo couldn't be decoded.".

## 4. Các lối khác dùng cùng ảnh

| Lối | Hành vi |
|---|---|
| Resize | ảnh đó vào danh sách lỗi của lượt chạy, kèm đúng câu thông báo; ảnh khác vẫn chạy ([FS-03.07](07-resize-and-compression.md)) |
| Collage · Video Studio · Combine (HDR, Focus Stack, Panorama) | hỏi trước khi thêm ảnh (dưới bảng) |
| Duplicates | không đổi — so bằng thumbnail của PhotoKit |
| Share | gửi nguyên file gốc, không cần giải |
| Edit in ShotDex, ảnh trên file server | cùng thông báo, cùng luật cặp RAW+JPEG ([EX-05](../../03-extensions-and-integrations/EX-05-edit-action-extension.md), [FS-17](../FS-17-import-from-server/README.md)) |

- **Thêm RAW "chưa đọc được" vào Collage, Video Studio hay Combine thì hỏi trước**, một lần cho cả lượt thêm.
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
| AC-1 | 12 NEF RAW-only, EXIF `NIKON Z 6_2`, danh sách hệ thống có "Nikon Z 6 2" | lượt xét phán quyết chạy | máy ghi "đọc được"; 0 trong 12 tile có dấu | ⚠️ chưa có |
| AC-2 | 8 ARW RAW-only (có sẵn trên máy) của máy không khớp danh sách, bộ giải trả rỗng, và 5 HEIC | lượt xét chạy xong | đúng 8 tile có glyph tam giác ở hàng glyph trạng thái, VoiceOver đọc "RAW not supported by iOS"; 5 HEIC không có; chạm tile mở viewer | ⚠️ chưa có |
| AC-3 | 1 ảnh của AC-2, máy tên "Sony ILCE-7M5" trong index | bấm Edit ở Photo Detail | thông báo đủ hai câu, có "Sony ILCE-7M5" và "iOS 27.0"; editor không mở | ⚠️ chưa có |
| AC-4 | ảnh của AC-2 chỉ có trên iCloud, phán quyết đã có | bấm Edit | thông báo hiện trong ≤ 1 s, 0 byte tải về, không có spinner "Downloading from iCloud…" | ⚠️ chưa có |
| AC-5 | cặp RAW+JPEG của máy "chưa đọc được" | bấm Edit, chọn Edit JPEG | action sheet *Edit which version?* có Edit RAW mờ kèm *iOS can't read this RAW yet*; editor mở JPEG; menu Source có RAW mờ; không có mục White Balance | ⚠️ chưa có |
| AC-6 | ARW RAW-only, Make/Model trong EXIF rỗng, bộ giải trả rỗng | bấm Edit | thông báo nói ".ARW", không có tên máy; trước đó tile **không** có dấu (không biết ≠ chưa hỗ trợ) | ⚠️ chưa có |
| AC-7 | file DNG RAW-only mà bộ giải trả rỗng | bấm Edit | thông báo "can't read this DNG file" kèm câu nhắc "latest Adobe DNG Converter"; hai nút Share Original · OK | ⚠️ chưa có |
| AC-8 | như AC-7 | bấm Share Original | share sheet mở với đúng file DNG gốc, cùng số byte với tài nguyên gốc trong Photos | ⚠️ chưa có |
| AC-9 | file RAW mà ImageIO không đọc nổi cả thuộc tính | bấm Edit | vẫn là thông báo RAW (dạng có tên máy hoặc đuôi file), không phải "The photo couldn't be decoded." | ⚠️ chưa có |
| AC-10 | máy "chưa biết" (mọi file chỉ trên iCloud), 6 ảnh; editor mở 1 ảnh và bộ giải hỏng | đóng thông báo, về lưới | 6 tile của máy đó có dấu, không cần mở lại app | ⚠️ chưa có |
| AC-11 | phán quyết "chưa đọc được" ghi ở iOS 27.0; máy lên 27.1 và bộ giải đọc được | mở app | máy được xét lại, 0 tile còn dấu, Edit mở editor bình thường | ⚠️ chưa có |
| AC-12 | 3 ARW RAW-only của máy không khớp danh sách, cả 3 chỉ trên iCloud | lượt xét chạy xong | máy ghi "chưa biết"; 0 byte tải về; 0 tile có dấu | ⚠️ chưa có |
| AC-13 | 8 ảnh của AC-2, 3 ảnh của AC-12, 5 HEIC | chọn **Unsupported RAW** trong menu con kiểu chụp | lưới còn đúng 8 ảnh của AC-2 | ⚠️ chưa có |
| AC-14 | Resize 3 ảnh: 2 JPEG + 1 ảnh của AC-2 | chạy Resize | 2 bản mới trong Photos; danh sách lỗi có 1 dòng mang câu của AC-3; không tạo file từ bản xem trước | ⚠️ chưa có |
| AC-15 | Collage, chọn 4 ảnh trong đó 1 ảnh của AC-2 | thêm vào collage | hỏi *1 RAW photo can't be read on this iOS* với Convert to JPEG · Skip These 1 · Cancel; Convert → ô đó dùng bản xem trước đúng cỡ nhúng, 0 asset mới trước khi Save; Skip → collage 3 ảnh; Cancel → không thêm ảnh nào | ⚠️ chưa có |
| AC-16 | cặp RAW+JPEG của máy đọc được | bấm Edit hai lần, lần 1 chọn Edit RAW rồi đóng editor | lần 1 action sheet có cả hai mục sáng, editor mở RAW; lần 2 action sheet hiện lại | ⚠️ chưa có |
| AC-17 | ảnh của AC-2 mở trong viewer | chạm glyph tam giác ở bảng thông tin | thẻ có tên máy, "iOS 27.0" và câu "You can still view the preview, but you can't edit the RAW."; vùng chạm ≥ 44pt | ⚠️ chưa có |
| AC-18 | Video Studio, thêm 5 ảnh, 2 ảnh của AC-2 | chọn Skip These 2 | timeline có đúng 3 clip ảnh; không có clip nào từ bản xem trước | ⚠️ chưa có |

**Chưa chứng minh được:** AC-1…AC-18. Cần một file RAW thật của máy mà iOS trên sim chưa đọc (không có mặt người), và
một cách giả bộ giải trả rỗng trong test.

## 7. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Danh sách máy trên iOS có thể khác bản macOS đã đo | đo lại trên sim 26.5 và 27.0 ở task đầu của `/plan` |
| Thứ tự file của cặp RAW+JPEG: index có thể ghi tên file RAW, làm cặp trông như RAW-only | đo trên cặp thật trước khi dựa vào đuôi file |
| Bản xem trước nhúng có độ phân giải khác nhau theo máy; PhotoKit có thể không trả gì | đo trên 3 hãng; tile trống thì vẫn có dấu |
| Share tắt vị trí: ImageIO không ghi được kiểu RAW nào (đo macOS 27.0: 22 kiểu, không có RAW/DNG), nên file RAW đi **còn nguyên GPS** | thuộc mục 3 của intent (riêng tư khi chia sẻ), báo sang spec đó |
