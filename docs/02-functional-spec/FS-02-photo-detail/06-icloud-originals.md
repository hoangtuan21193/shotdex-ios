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

**Có:** viewer · editor một ảnh · editor nhiều ảnh (preload) · Share (chọn nhiều, menu ô, album, viewer) ·
Resize · Collage.

**Để đợt sau** (người dùng chốt 2026-10-01; mỗi việc một dòng ở `REVIEW_QUEUE.md`, mục *user-wishes wave 1
follow-ups*): Save All của editor nhiều ảnh · Paste Edits từ lưới · phần trăm cho Combine Photos (Focus Stack,
HDR, Panorama — hôm nay giữ *"N photos couldn't be downloaded"* + Retry) · luật đủ pixel cho Copy và kéo thả.
Bảng AC không có dòng nào cho chúng, nên đợt này không làm.

**Cố ý không có:**
- Nút "tải bản gốc về" cho cả thư viện. Vì Photos đã có công tắc Download and Keep Originals.
- Tiến độ riêng cho Copy và kéo thả. Vì hệ thống điều khiển phiên kéo.
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
- Lượt tải do người dùng bấm được đi cả mạng di động (BD-03.03 §2). Chúng **không** xin suất tải của index:
  pha chuẩn bị tự giới hạn **≤ 4 lượt song song**, và trong lúc chuẩn bị thì index tạm dừng qua cổng tương tác
  có sẵn, như khi đang mở viewer (người dùng chốt 2026-10-01). Vì lượt index đang bay có thể giữ suất tới 120 s,
  bắt lượt của người dùng chờ nó là sai thứ tự ưu tiên.

## 4. Từng màn

| Màn | Hôm nay (2026-10-01) | Luật |
|---|---|---|
| Viewer | trang đang hiện tải bản cỡ màn qua mạng; vòng 22pt hiện ngay khi byte chạy, không có số | trang đang hiện hỏi hệ thống **một lần với mạng tắt**; bản gốc chưa về thì bảng thông tin có glyph iCloud. Bản **cỡ màn** vẫn được tải qua mạng khi chưa phóng, như Photos ([01](01-pager-and-image-loading.md) §4); **bản gốc** chỉ tải khi phóng. Vòng 22pt đầy dần theo tiến độ khi bản cỡ màn **hoặc** bản gốc đang tải, **không có số** cạnh vòng; VoiceOver đọc phần trăm. Vì số tốn ~28pt dòng tiêu đề trên máy 402pt |
| Editor một ảnh | spinner không có %; chữ chỉ ghi iCloud khi máy không có cả bản xem trước | thẻ trên stage ghi *"Downloading from iCloud… 41%"* với thanh tiến độ xác định; Save tắt tới khi bản gốc về |
| Editor nhiều ảnh | preload tải bản gốc nhưng không báo gì | ô filmstrip có glyph iCloud khi bản gốc chưa về, có vòng tiến độ (không số) khi vòng preload đang tải ảnh đó. Save All: đợt sau (§2) |
| Share | chọn nhiều: spinner trên nút, ảnh hỏng bị bỏ im lặng · viewer: *"Unable to Share"* chỉ có OK | **như Photos**, cùng một luật cho viewer, lưới, chế độ chọn, menu ô và album (§9): share sheet mở ngay, chưa tải gì cho tới khi người dùng chọn đích; chọn đích xong mới chạy §5 trong modal nhỏ giữa màn. Bỏ hẳn alert *Unable to Share* ([04](04-actions-and-extras.md) §3) |
| Resize | *"Preparing original…"* không có %; tải trong vòng *Processing N of M* | §5 trước vòng xử lý, tiến độ tải hiện **trong modal xử lý của Resize** (§9); ảnh tải hỏng thì không nén và **không bị xoá** |
| Paste Edits (lưới) | tải im lặng trong vòng lặp | đợt sau (§2) |
| Collage | ô tải hỏng ra ô trống, chỉ báo lỗi khi **mọi** ô hỏng | Export chạy §5 ở cỡ ô, tiến độ tải hiện **trong modal export của Collage** (§9); có ô hỏng thì không lưu, báo + Retry |

## 5. Pha chuẩn bị bản gốc

Pha này **tải hết cả mẻ rồi mới làm**: chưa ghi, chưa xoá gì cho tới khi mọi ảnh đã về hoặc người dùng đã chọn
ở bước 4. Vì ảnh hỏng phải lộ ra trước khi Resize tạo bản nén hay xoá bản gốc. Cái giá là chỗ trống bằng tổng
dung lượng gốc cả mẻ, nên bước 2 kiểm trước.

1. **Hỏi với mạng tắt** từng ảnh, xem ảnh nào đã có bản gốc trên máy. Ảnh đã có đi qua ngay, không tính vào bộ đếm.
2. **Kiểm chỗ trống cho cả mẻ** trước khi tải byte đầu tiên: tổng dung lượng gốc của các ảnh cần tải phải nhỏ
   hơn chỗ trống dành cho việc người dùng yêu cầu. Thiếu thì báo *"Not enough space to download these
   originals — needs 1.4 GB, 380 MB free."* + OK, và không tải gì.
   - Dung lượng lấy từ index; dòng chưa có thì hỏi PhotoKit kích thước tài nguyên gốc (chỉ cho các ảnh của mẻ);
     PhotoKit cũng không trả được thì ảnh đó không tính vào tổng và pha vẫn chạy (người dùng chốt 2026-10-01).
3. **Tải**, hiện tiến độ ở chỗ của thao tác đó (§9): Share — modal nhỏ giữa màn, sau khi đã chọn đích ·
   thao tác không phải Share (Resize, Collage, lưu hàng loạt) — ngay trong màn/modal xử lý có sẵn của chính nó.
   Toolbar Library **không** có token tải (người dùng chốt 2026-10-01).
   - Phần trăm là trung bình theo ảnh: ảnh xong tính 1, ảnh đang tải tính phần đã về.
   - Số liệu dùng chữ số đều. Viewer và filmstrip chỉ có vòng, không số.
4. **Kết thúc:**
   - tất cả về thì làm tiếp thao tác, không dừng lại;
   - có ảnh hỏng thì hiện *"2 of 12 photos couldn't be downloaded from iCloud."*, danh sách tên ảnh hỏng, và ba
     nút **Continue with 10** (tuỳ thao tác: *Share 10*) · **Retry** · **Cancel**. Share: ngay trong modal §9.
     Thao tác khác: ngay trong màn/modal xử lý của thao tác đó (§9).
- **Cancel** dừng mọi lượt tải trong ≤ 1 s. Không tạo asset, không xoá ảnh, đích share không nhận file nào; file
  tạm của pha này bị xoá.
- Hết chỗ giữa chừng là lỗi **chỗ trống**, không được gọi là lỗi iCloud.

## 6. Trạng thái

| Trạng thái | Điều kiện | Hiển thị |
|---|---|---|
| có trên máy | đủ pixel (§3) | không có gì |
| chỉ trên iCloud | hỏi với mạng tắt không ra bản đủ pixel | glyph iCloud (viewer, filmstrip) |
| đang tải | hệ thống báo tiến độ | viewer, filmstrip: vòng xác định, không số · editor một ảnh, pha chuẩn bị (§5): thanh xác định kèm % · Share: modal *Downloading from iCloud · 63% · 24 MB* |
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

## 9. Chỗ hiện tiến độ tải

### Share — như Photos

Người dùng chốt 2026-10-01: Share chạy như Photos của iOS ở **mọi** lối vào — viewer, lưới, chế độ chọn, menu ô,
album, smart album, On This Day.

1. Chạm Share → share sheet của hệ thống **mở ngay** như bình thường. Chưa tải byte nào: mỗi mục là một nguồn dữ
   liệu **lười**, chỉ khai kiểu file và bản xem trước có sẵn trên máy.
2. Người dùng chọn đích (Save to Files, Messages, AirDrop…) → lúc đó mới chạy §5 cho các mục đích xin.
3. Trong lúc đó một **modal nhỏ giữa màn**: *"Downloading from iCloud · 63% · 24 MB"*, thanh xác định, nút
   **Cancel**. Modal ở lại tới khi bản gốc đã sẵn sàng; ảnh đã có trên máy thì modal không hiện (ngưỡng 350 ms, §3).
4. Ghi lại metadata theo [FS-08.06](../FS-08-settings/06-share-metadata-privacy.md) chạy **sau khi tải**, trong
   cùng pha modal đó; modal chỉ đóng khi file cuối cùng đã ghi xong.
5. Có ảnh hỏng: bước 4 của §5 hiện ngay trong modal (*Share 10* · Retry · Cancel). Cancel: đích không nhận gì.

- Không còn alert *Unable to Share*, không còn spinner trên nút Share.
- Modal canh giữa vùng an toàn của scene, nên trên Duo ngoài không nằm dưới dải 84pt.

### Thao tác không phải Share — trong màn xử lý của chính nó

Người dùng chốt 2026-10-01: **không có token tải iCloud trên toolbar Library** — không ở nhánh iOS nào, không
trong chế độ chọn. Token index cạnh nút gear ([FS-01.02 §2](../FS-01-library/02-navigation-and-condition-bar.md))
giữ nguyên chỗ và hành vi, không bị thay.

- Resize, Collage và lưu hàng loạt báo tiến độ tải **ngay trong màn/modal xử lý có sẵn của chính chúng**, trước
  pha xử lý: một dòng *"Downloading from iCloud · 3 of 12 · 42%"* (chữ số đều) và thanh tiến độ xác định. Cancel
  là nút Cancel có sẵn của màn đó. Không đẻ thêm kiểu modal.
  - Resize: modal xử lý *Processing N of M*. Collage: modal export. Lưu hàng loạt (Save All, đợt sau — §2):
    modal lưu của editor nhiều ảnh.
- Kết thúc có ảnh hỏng: bước 4 của §5 hiện ngay trong màn/modal đó.
- Glyph iCloud và modal tải của Share phải vào từ điển icon của `DESIGN.md` §8 — người dùng tự sửa file đó.

## 10. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | ảnh 6000×4000 (24 MB) chỉ trên iCloud; trên máy có bản xem trước 1536px | mở trang đó trong viewer, không phóng | bảng thông tin hiện glyph iCloud trong ≤ 1 s; **không tải bản gốc** (bản cỡ màn được phép tải qua mạng, như Photos); VoiceOver đọc *Original in iCloud* | ⚠️ chưa có |
| AC-2 | như AC-1, Wi-Fi | pinch phóng | vòng 22pt đầy dần qua ≥ 3 ảnh chụp cách nhau 2 s, không có số cạnh vòng (vòng cũng hiện khi bản cỡ màn đang tải); VoiceOver đọc *Downloading from iCloud, N percent*; bản gốc về thì glyph mất | ⚠️ chưa có |
| AC-3 | như AC-1 | mở editor | thẻ ghi *Downloading from iCloud… N%*, không ghi *Loading full-quality preview…*; Save tắt; nguồn khi về đúng 6000×4000 | ⚠️ chưa có |
| AC-4 | AC-3 đang ở 30% | bấm Cancel | editor đóng trong ≤ 1 s, lượt tải bị huỷ, không còn thư mục `ShotDexPhoto-*` của phiên đó | ⚠️ chưa có |
| AC-5 | ảnh chỉ trên iCloud, Airplane Mode | mở editor | trong ≤ 15 s hiện *Couldn't Download from iCloud* hoặc *iCloud isn't responding…*; có nút đóng; không vòng quay vô hạn | `EditorLoadFailureTests.networkFailuresReadAsICloud` (phân loại lỗi) · ⚠️ chưa chụp |
| AC-6 | chọn 12 ảnh, 3 ảnh chỉ trên iCloud (60 MB) | bấm Share, rồi chọn Save to Files | share sheet mở ngay với đúng 12 mục và **0 byte** đã tải; sau khi chọn đích, quá 350 ms thì modal giữa màn ghi *Downloading from iCloud · N% · M MB* + Cancel; Files nhận đủ 12 file, 3 ảnh iCloud ở cỡ gốc | ⚠️ chưa có |
| AC-7 | như AC-6; tắt mạng khi ảnh thứ 2 đang tải | chờ pha chuẩn bị kết thúc | modal ghi *2 of 12 photos couldn't be downloaded from iCloud.*, tên 2 ảnh hỏng, Share 10 · Retry · Cancel; đích chưa nhận file nào trước khi người dùng chọn | ⚠️ chưa có |
| AC-8 | viewer đang ở một ảnh chỉ trên iCloud | bấm Share, rồi chọn Save to Files | share sheet mở ngay, chưa tải gì; sau khi chọn đích, modal giữa màn có tiến độ + Cancel; Files nhận dữ liệu 6000×4000; không còn alert *Unable to Share* chỉ có OK | ⚠️ chưa có |
| AC-9 | Resize 5 ảnh, 2 ảnh chỉ trên iCloud, không mạng, Delete Originals bật | bấm Resize, rồi chọn Continue with 3 | tạo đúng 3 bản; xoá đúng 3 bản gốc; 2 ảnh kia vẫn còn trong thư viện và không có bản nén nào | ⚠️ chưa có |
| AC-10 | Resize 20 ảnh chỉ trên iCloud, đang tải ảnh thứ 4 | bấm Cancel | trước khi bấm: modal xử lý của Resize ghi *Downloading from iCloud · k of 20 · N%* với thanh xác định (toolbar Library không có token tải); sau khi bấm: 0 asset mới, 0 ảnh bị xoá, modal đóng trong ≤ 1 s | ⚠️ chưa có |
| AC-11 | ảnh 6000×4000; bản nhận về 1536×1024, được gắn nhãn "bản cuối" | kiểm đủ pixel | coi là **chưa có** bản gốc; 4000×6000 với orientation xoay 90° thì đạt; bản theo cỡ 1800px: 1620 đạt, 1619 không đạt | ⚠️ chưa có (test thuần) |
| AC-12 | collage 4 ô, 1 ảnh chỉ trên iCloud, không mạng | bấm Export | không lưu gì; *1 photo couldn't be downloaded* + Retry · Cancel; không có collage nào được lưu với ô trống | ⚠️ chưa có |
| AC-13 | phiên editor 5 ảnh, ảnh 3 chỉ trên iCloud | mở editor nhiều ảnh | ô 3 trên filmstrip có glyph iCloud, đổi sang vòng tiến độ không số khi vòng preload tải nó; chạm ô 3 khi ảnh chưa về thì thẻ ghi *Downloading from iCloud… N%* | ⚠️ chưa có |
| AC-14 | Share 10 ảnh chỉ trên iCloud, tổng 1,4 GB; máy còn 380 MB | bấm Share, rồi chọn Save to Files | trước byte đầu tiên, modal hiện *Not enough space… needs 1.4 GB, 380 MB free.* + OK; không lượt tải nào bắt đầu; Files không nhận file nào | ⚠️ chưa có |
| AC-15 | quyền `.limited`; ảnh đang tải trong editor bị gỡ khỏi tập chọn | lượt tải trả lỗi quyền | *Can't Open This Photo* + Open Settings · Cancel; mọi nút đều đóng editor | `EditorLoadFailureTests.permissionErrorsOfferSettings` · `.anUnavailablePhotoUnderLimitedAccessIsTheSelection` · ⚠️ chưa chụp |
| AC-16 | Resize 5 ảnh chỉ trên iCloud, Delete Originals bật; ảnh 5 tải hỏng | alert *1 of 5 photos couldn't be downloaded* hiện | lúc đó chưa có asset mới nào và chưa ảnh nào bị xoá; bản gốc của 4 ảnh đã về nằm sẵn trên đĩa | ⚠️ chưa có |
| AC-17 | lưới có ảnh chỉ trên iCloud | cuộn lưới | không ô nào có dấu iCloud; không có lượt hỏi tài nguyên PhotoKit nào theo ô | ⚠️ chưa có |
| AC-18 | Library đang index ở 40%; menu ô của 1 ảnh chỉ trên iCloud | bấm Share, rồi chọn Save to Files | share sheet mở ngay; sau khi chọn đích, modal giữa màn có tiến độ + Cancel; toolbar Library không có token tải nào, token index vẫn ở chỗ cũ cạnh gear; index tạm dừng trong lúc tải và chạy tiếp khi modal đóng; iOS 26.5 và 18.6 cùng hành vi | ⚠️ chưa có |

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
| Nguồn lười của share sheet: có đích xin dữ liệu ngay khi được chọn, có đích có thể hết giờ chờ một lượt tải dài | đo trên máy thật với Files, Messages, AirDrop; đích nào không nhận được bản gốc thì ghi vào đây |
