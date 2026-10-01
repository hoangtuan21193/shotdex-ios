# FS-02.06 — Bản gốc trên iCloud

`FS-02.06` · tier B/C/D · `Data/Sources/PhotoEditingService.swift` · `Features/Shared/PhotoShareSheet.swift` ·
`Features/Editing/CompressionController.swift` · `Features/Library/PhotoDetailScreen.swift` · cập nhật 2026-10-01

**Một câu:** người dùng luôn biết bản gốc của một ảnh đã có trên máy hay đang tải (tới đâu), bản gốc của cả mẻ
được tải xong trước khi sửa hàng loạt, xuất, Resize hay Share, và không đường nào âm thầm xuất ra bản xem trước.

Nguồn intent: [2026-09-30-user-wishes-research](../../_intents/2026-09-30-user-wishes-research.md) mục 1.
Tải trong viewer: [01](01-pager-and-image-loading.md) §4–5. Mạng và suất tải: [BD-03.03](../../01-basic-design/BD-03-metadata-indexing-flow/03-network-thermal-and-gate.md).

## 1. Người dùng cần gì

Máy bật Optimize Storage thì phần lớn bản gốc nằm trên iCloud, trên máy chỉ còn bản xem trước. Người chụp cần
biết mình đang cầm bản nào. Bấm Share, Resize hay Save All thì phải thấy việc tải đang chạy, được huỷ, và được
báo tên những ảnh không tải được. Một ảnh 1536px gửi đi thay cho ảnh 24MP là lỗi mất dữ liệu, không phải lỗi hiển thị.

## 2. Phạm vi

Spec này chỉ phủ các đường **ảnh tĩnh**.

**Có:** viewer · editor một ảnh · editor nhiều ảnh (preload, Save All) · Share (chọn nhiều, menu ô, viewer) ·
Resize · Paste Edits từ lưới · Collage. Combine Photos (Focus Stack, HDR, Panorama) giữ thông báo
*"N photos couldn't be downloaded"* + Retry đã có, chỉ thêm phần trăm.

**Cố ý không có:**
- Nút "tải bản gốc về" cho cả thư viện. Vì Photos đã có công tắc Download and Keep Originals.
- Tiến độ riêng cho Copy và kéo thả. Vì hệ thống điều khiển phiên kéo. Hai đường này vẫn theo luật đủ pixel (§3).
- Upload to Server: FS-15.02 đã có bước *Preparing* (iCloud) và chép nguyên file, nên không đổi gì.
- **Dấu iCloud trên ô lưới.** Dấu chỉ có ở viewer, filmstrip và lúc bấm thao tác. Vì hỏi hệ thống cho từng ô
  đang hiện đụng [NF-01](../../04-non-functional-design/NF-01-performance.md) luật 1 và 4.
- **Video Studio**, kể cả ảnh tĩnh đặt trên timeline: để trọn cho FS-12
  ([FS-12.08 §6](../FS-12-video-studio/08-model-and-v1-limits.md)).

## 3. Luật chung

- **Đủ pixel mới là bản gốc.** Với mạng tắt, hệ thống vẫn gắn nhãn "bản cuối" cho bản xem trước của Optimize
  Storage, nên cái nhãn đó không đủ. Cái app kiểm là kích thước pixel.
  - Bản gốc: đúng rộng × cao của ảnh, sau khi tính orientation.
  - Bản theo cỡ yêu cầu (Collage): cạnh dài ≥ 90% của min(cỡ yêu cầu, cạnh dài của ảnh). Cùng ngưỡng với [01](01-pager-and-image-loading.md) §4.
- **Chuẩn bị xong mới làm.** Mọi thao tác xuất hay ghi đều chạy pha *chuẩn bị bản gốc* (§5) trước khi ghi ra byte
  nào. Riêng Resize còn phải chạy pha này trước khi xoá bản gốc nào.
- **Không im lặng.** Chuẩn bị quá **350 ms** thì hiện tiến độ, cùng ngưỡng với vòng quay của viewer. Ảnh tải hỏng
  thì nói số lượng và cho lối ra. Không bao giờ lặng lẽ bỏ ảnh đó.
- **Đứng im 15 giây ở 0%** (tính trên mọi lượt tải đang chạy) thì hiện *"iCloud isn't responding — check iCloud
  Photos in Settings or the Photos app."*. App không tự huỷ lượt tải, cùng luật với [01](01-pager-and-image-loading.md) §5.
- Lượt tải do người dùng bấm được đi cả mạng di động (BD-03.03 §2). Chúng dùng chung **4 suất** tải iCloud của
  toàn app, và trong lúc chuẩn bị thì index tạm dừng, như khi đang mở viewer.

## 4. Từng màn

| Màn | Hôm nay (2026-10-01) | Luật |
|---|---|---|
| Viewer | vòng 22pt chỉ hiện khi đang phóng, không có số | trang đang hiện hỏi hệ thống **một lần với mạng tắt**; bản gốc chưa về thì bảng thông tin có glyph iCloud; phóng → vòng 22pt đầy dần theo tiến độ, **không có số** cạnh vòng; VoiceOver đọc phần trăm. Vì số tốn ~28pt dòng tiêu đề trên máy 402pt |
| Editor một ảnh | spinner không có %; chữ chỉ ghi iCloud khi máy không có cả bản xem trước | thẻ trên stage ghi *"Downloading from iCloud… 41%"* với thanh tiến độ xác định; Save tắt tới khi bản gốc về |
| Editor nhiều ảnh | preload tải bản gốc nhưng không báo gì | ô filmstrip có glyph iCloud khi bản gốc chưa về, có vòng tiến độ (không số) khi vòng preload đang tải ảnh đó; Save All chạy §5 trong modal có sẵn |
| Share | chọn nhiều: spinner trên nút, ảnh hỏng bị bỏ im lặng · viewer: *"Unable to Share"* chỉ có OK | §5 cho mọi lối vào; viewer tải về rồi mở share sheet (thay câu *Unable to Share* ở [04](04-actions-and-extras.md) §3) |
| Resize | *"Preparing original…"* không có %; tải trong vòng *Processing N of M* | §5 trước vòng xử lý; ảnh tải hỏng thì không nén và **không bị xoá** |
| Paste Edits (lưới) | tải im lặng trong vòng lặp | §5 trong modal có sẵn |
| Collage | ô tải hỏng ra ô trống, chỉ báo lỗi khi **mọi** ô hỏng | Export chạy §5 ở cỡ ô; có ô hỏng thì không lưu, báo + Retry |

## 5. Pha chuẩn bị bản gốc

Pha này **tải hết cả mẻ rồi mới làm**: chưa ghi, chưa xoá gì cho tới khi mọi ảnh đã về hoặc người dùng đã chọn
ở bước 4. Vì ảnh hỏng phải lộ ra trước khi Resize tạo bản nén hay xoá bản gốc. Cái giá là chỗ trống bằng tổng
dung lượng gốc cả mẻ, nên bước 2 kiểm trước.

1. **Hỏi với mạng tắt** từng ảnh, xem ảnh nào đã có bản gốc trên máy. Ảnh đã có đi qua ngay, không tính vào bộ đếm.
2. **Kiểm chỗ trống cho cả mẻ** trước khi tải byte đầu tiên: tổng dung lượng gốc (lấy từ index) của các ảnh
   cần tải phải nhỏ hơn chỗ trống dành cho việc người dùng yêu cầu. Thiếu thì báo *"Not enough space to download these
   originals — needs 1.4 GB, 380 MB free."* + OK, và không tải gì.
3. **Tải**, hiện tiến độ ở chỗ của màn đó: token *↓ 3/12 · 41%* ở tầng B/C (§9), modal có sẵn ở tầng D.
   - Phần trăm là trung bình theo ảnh: ảnh xong tính 1, ảnh đang tải tính phần đã về.
   - Số liệu dùng chữ số đều. Viewer và filmstrip chỉ có vòng, không số.
4. **Kết thúc:**
   - tất cả về thì làm tiếp thao tác, không dừng lại;
   - có ảnh hỏng thì hiện *"2 of 12 photos couldn't be downloaded from iCloud."*, danh sách tên ảnh hỏng, và ba
     nút **Continue with 10** (tuỳ thao tác: *Share 10*) · **Retry** · **Cancel**. Ở tầng B/C, panel §9 tự mở ra.
- **Cancel** dừng mọi lượt tải trong ≤ 1 s. Không tạo asset, không xoá ảnh, không mở share sheet; file tạm của pha này bị xoá.
- Hết chỗ giữa chừng là lỗi **chỗ trống**, không được gọi là lỗi iCloud.

## 6. Trạng thái

| Trạng thái | Điều kiện | Hiển thị |
|---|---|---|
| có trên máy | đủ pixel (§3) | không có gì |
| chỉ trên iCloud | hỏi với mạng tắt không ra bản đủ pixel | glyph iCloud (viewer, filmstrip) |
| đang tải | hệ thống báo tiến độ | viewer, filmstrip: vòng xác định, không số · editor một ảnh, pha chuẩn bị (§5): thanh xác định kèm % |
| đứng im | 15 s ở 0% | glyph iCloud cam + câu *iCloud isn't responding…* |
| không mạng | hệ thống trả lỗi mạng | *"Couldn't Download from iCloud"* + lối ra |
| thiếu chỗ | §5 bước 2, hoặc hết chỗ giữa chừng | dung lượng cần và dung lượng còn trống |
| quyền giới hạn | `.limited`, ảnh bị gỡ khỏi tập chọn giữa chừng | *"Can't Open This Photo"* + **Open Settings** (cùng câu với editor) |

## 7. Dữ liệu

| | |
|---|---|
| Đọc từ | PhotoKit (tài nguyên và tiến độ tải) · kích thước pixel của asset · dung lượng file đã index |
| Ghi vào | không có. Trạng thái "đã có trên máy" **không lưu vào DB**: hệ thống dọn bản gốc mà không báo thay đổi, nên giá trị lưu sẽ sai |
| Người dùng tự nhập? | không |

## 8. Ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Hiệu năng | không hỏi theo từng ô lưới ([NF-01](../../04-non-functional-design/NF-01-performance.md) luật 1, 4); viewer chỉ hỏi cho trang đang hiện |
| Bộ nhớ | bản gốc tải về đĩa, không giữ trong RAM; editor nhiều ảnh vẫn đi từng ảnh một ([NF-02](../../04-non-functional-design/NF-02-memory-and-resources.md) §2) |
| Riêng tư | kiểm chỗ trống dùng lý do đã khai báo cho việc báo máy hết chỗ; không cần thêm lý do mới |
| Thiết bị | cùng một chức năng trên iPhone 402×874, iPad 1376×1032, Duo trong 951×669 và Duo ngoài 466×678. Trên Duo ngoài, tiến độ không được nằm dưới dải 84pt bên phải |
| iOS 26 vs trước | hai nhánh có cùng tập hành động: Cancel, Retry, Continue |
| Truy cập | VoiceOver đọc cả phần trăm, kể cả ở vòng không số, ví dụ *"Downloading from iCloud, 41 percent"*; glyph iCloud có nhãn *"Original in iCloud"* |

## 9. Tiến độ ở tầng B/C

Share từ lưới, chế độ chọn, menu ô, album và viewer dùng chung một chỗ báo tiến độ. Màn tầng D (editor, Resize,
Paste Edits, Collage) báo trong modal có sẵn của nó.

- **Token** nằm ở ô token index: trên cùng bên trái, cạnh nút gear ([FS-01.02 §2](../FS-01-library/02-navigation-and-condition-bar.md)).
  Chữ *"↓ 3/12 · 42%"*, chữ số đều, cùng viên kính với token index ở cả hai nhánh iOS.
  - Lúc tải thì index tạm dừng (§3), nên token tải **thay** token index; tải xong thì token index quay lại.
- **Chạm token** mở panel thả xuống cùng kiểu với panel index: *"Downloading from iCloud · 3 of 12 · 42% · for
  Share"*, thanh tiến độ xác định, nút **Cancel**. Kết thúc có ảnh hỏng thì panel mở sẵn với bước 4 của §5.
- **Chế độ chọn** ẩn toolbar của màn: token hiện ở đầu bên trái nav bar của lớp phủ chọn
  ([FS-01.06](../FS-01-library/06-multi-select.md)), cùng chữ, cùng panel.
- Glyph iCloud và token tải phải vào từ điển icon của `DESIGN.md` §8 — người dùng tự sửa file đó.

## 10. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | ảnh 6000×4000 (24 MB) chỉ trên iCloud; trên máy có bản xem trước 1536px | mở trang đó trong viewer, không phóng | bảng thông tin hiện glyph iCloud trong ≤ 1 s, không byte nào được tải; VoiceOver đọc *Original in iCloud* | ⚠️ chưa có |
| AC-2 | như AC-1, Wi-Fi | pinch phóng | vòng 22pt đầy dần qua ≥ 3 ảnh chụp cách nhau 2 s, không có số cạnh vòng; VoiceOver đọc *Downloading from iCloud, N percent*; tải xong thì glyph mất | ⚠️ chưa có |
| AC-3 | như AC-1 | mở editor | thẻ ghi *Downloading from iCloud… N%*, không ghi *Loading full-quality preview…*; Save tắt; nguồn khi về đúng 6000×4000 | ⚠️ chưa có |
| AC-4 | AC-3 đang ở 30% | bấm Cancel | editor đóng trong ≤ 1 s, lượt tải bị huỷ, không còn thư mục `ShotDexPhoto-*` của phiên đó | ⚠️ chưa có |
| AC-5 | ảnh chỉ trên iCloud, Airplane Mode | mở editor | trong ≤ 15 s hiện *Couldn't Download from iCloud* hoặc *iCloud isn't responding…*; có nút đóng; không vòng quay vô hạn | `EditorLoadFailureTests.networkFailuresReadAsICloud` (phân loại lỗi) · ⚠️ chưa chụp |
| AC-6 | chọn 12 ảnh, 3 ảnh chỉ trên iCloud (60 MB) | bấm Share | sau 350 ms token *↓ 1/3 · N%* hiện ở đầu trái nav bar của lớp phủ chọn; chạm token thì panel ghi *Downloading from iCloud · 1 of 3 · N% · for Share* + Cancel; share sheet mở với đúng 12 mục | ⚠️ chưa có |
| AC-7 | như AC-6; tắt mạng khi ảnh thứ 2 đang tải | chờ pha chuẩn bị kết thúc | panel tự mở: *2 of 12 photos couldn't be downloaded from iCloud.*, tên 2 ảnh hỏng, Share 10 · Retry · Cancel; không share sheet nào mở trước khi người dùng chọn | ⚠️ chưa có |
| AC-8 | viewer đang ở một ảnh chỉ trên iCloud | bấm Share | ảnh tải về, có tiến độ, rồi share sheet mở với dữ liệu 6000×4000; không còn alert *Unable to Share* chỉ có OK | ⚠️ chưa có |
| AC-9 | Resize 5 ảnh, 2 ảnh chỉ trên iCloud, không mạng, Delete Originals bật | bấm Resize, rồi chọn Continue with 3 | tạo đúng 3 bản; xoá đúng 3 bản gốc; 2 ảnh kia vẫn còn trong thư viện và không có bản nén nào | ⚠️ chưa có |
| AC-10 | Resize 20 ảnh chỉ trên iCloud, đang tải ảnh thứ 4 | bấm Cancel | 0 asset mới, 0 ảnh bị xoá, modal đóng trong ≤ 1 s | ⚠️ chưa có |
| AC-11 | ảnh 6000×4000; bản nhận về 1536×1024, được gắn nhãn "bản cuối" | kiểm đủ pixel | coi là **chưa có** bản gốc; 4000×6000 với orientation xoay 90° thì đạt; bản theo cỡ 1800px: 1620 đạt, 1619 không đạt | ⚠️ chưa có (test thuần) |
| AC-12 | collage 4 ô, 1 ảnh chỉ trên iCloud, không mạng | bấm Export | không lưu gì; *1 photo couldn't be downloaded* + Retry · Cancel; không có collage nào được lưu với ô trống | ⚠️ chưa có |
| AC-13 | phiên editor 5 ảnh, ảnh 3 chỉ trên iCloud | mở editor nhiều ảnh | ô 3 trên filmstrip có glyph iCloud, đổi sang vòng tiến độ không số khi vòng preload tải nó; chạm ô 3 khi ảnh chưa về thì thẻ ghi *Downloading from iCloud… N%* | ⚠️ chưa có |
| AC-14 | Share 10 ảnh chỉ trên iCloud, tổng 1,4 GB; máy còn 380 MB | bấm Share | trước byte đầu tiên, hiện *Not enough space… needs 1.4 GB, 380 MB free.* + OK; không lượt tải nào bắt đầu | ⚠️ chưa có |
| AC-15 | quyền `.limited`; ảnh đang tải trong editor bị gỡ khỏi tập chọn | lượt tải trả lỗi quyền | *Can't Open This Photo* + Open Settings · Cancel; mọi nút đều đóng editor | `EditorLoadFailureTests.permissionErrorsOfferSettings` · `.anUnavailablePhotoUnderLimitedAccessIsTheSelection` · ⚠️ chưa chụp |
| AC-16 | Resize 5 ảnh chỉ trên iCloud, Delete Originals bật; ảnh 5 tải hỏng | alert *1 of 5 photos couldn't be downloaded* hiện | lúc đó chưa có asset mới nào và chưa ảnh nào bị xoá; bản gốc của 4 ảnh đã về nằm sẵn trên đĩa | ⚠️ chưa có |
| AC-17 | lưới có ảnh chỉ trên iCloud | cuộn lưới | không ô nào có dấu iCloud; không có lượt hỏi tài nguyên PhotoKit nào theo ô | ⚠️ chưa có |
| AC-18 | Library đang index ở 40%; menu ô của 1 ảnh chỉ trên iCloud | bấm Share | token *Indexing 40%* đổi thành *↓ 1/1 · N%* cùng chỗ, cạnh gear; tải xong share sheet mở và token index quay lại; iOS 26.5 và 18.6 cùng chỗ | ⚠️ chưa có |

AC có ảnh chụp phải chụp trên iPhone 402×874, iPad 1376×1032, Duo trong 951×669 và Duo ngoài 466×678 (dùng
`Tools/sim-shot`), trên cả iOS 26.5 và 18.6.

**Chưa chứng minh được:** AC-1…18. Simulator không có thư viện iCloud Photos, nên các AC này phải chụp trên máy
thật bật Optimize Storage. AC-11 là test thuần, viết được ngay.

## 11. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Simulator không giả được "chỉ trên iCloud" | phần quyết định (đủ pixel, phân loại lỗi, đếm, phần trăm) viết thành logic thuần có test; phần còn lại chụp trên máy thật |
| Settings đã tắt dữ liệu di động cho Photos | lỗi rơi vào *không mạng*; câu báo nhắc Settings → Photos *(cần đo trên máy thật)* |
| iCloud của máy ngừng phục vụ trên toàn máy (BD-03.03) | luật đứng im 15 s; lượt tải không bị huỷ và tự chạy tiếp khi dịch vụ sống lại |
| Tải xong rồi hệ thống lại dọn bản gốc trước khi dùng tới | kiểm đủ pixel lại ngay lúc dùng, không tin kết quả của bước 1 |
| Nav bar của lớp phủ chọn trên 402pt đã chật (Compare · Edit · ⋯ · ×); thêm token có thể đẩy × ra ngoài | đo ở `/plan` trên iPhone 402pt và Duo ngoài 382pt; không vừa thì báo người dùng trước khi làm |
| Viewer không có ô token cạnh gear; Share từ viewer chưa có chỗ đặt token | ⚠️ chưa đo — đề xuất token ở đầu trái thanh trên của viewer; hỏi người dùng ở `/plan` |
