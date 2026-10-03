# FS-12.04 — Thanh công cụ, việc cả video và mô hình chọn

`FS-12.04` · `Features/VideoStudio/` (`VideoStudioToolbar`, `VideoStudioSheetHost`, `VideoStudioModel`)
· cập nhật 2026-10-03 · nguồn intent [video-studio-canvas-chrome](../../_intents/2026-10-03-video-studio-canvas-chrome.md)

**Một câu:** thanh dưới chỉ để **thêm** vào timeline; chỉnh cả video là **Look** và **Video Settings**; chọn một
item thì đáy thành **✕ · tên · ✓** như editor ảnh, và lệnh của item là hàng đầu panel.

Hàng lệnh từng loại item: [04b](04b-command-rows.md). Kích thước: iPhone [07](07-phone-layout.md), Duo ngoài
[07b](07b-duo-cover-layout.md), màn rộng [03](03-timeline-and-desk-layout.md).

## 1. Người dùng cần gì

Người dựng cần biết nút nào **thêm** thứ mới, nút nào **chỉnh** thứ đang có. Chọn một clip thì phải thấy ngay mình
đang sửa cái gì, sửa xong thì **giữ** hay **bỏ** bằng một chạm — đúng như khi sửa một tấm ảnh.

## 2. Quy tắc

- **Thanh dưới = thêm vào timeline**: Media · Text · Sticker · Music · Look, đúng thứ tự này trên mọi thiết bị.
  Không công cụ "cả video" nào khác nằm ở đây.
- **Việc cả video có đúng hai chỗ**: Look (Filter · Adjust · Color — [06c](06c-photo-looks.md)) và Video Settings
  (nút tỉ lệ ở băng trên — [10](10-video-settings-and-export.md)). Ratio, Background, Volume chung **không còn là công cụ**.
- **Âm gốc cả project** là dòng **"Video sound"** đầu panel Music (0–100, chú thích "Original clip audio, whole
  project") — **mức âm duy nhất của cả project** (chốt 2026-10-03).
- **Không có Master** cho cả bản mix: project không giữ trường đó, Quick Adjust không có dòng đó. Mỗi track nhạc có
  Volume riêng, meter báo đỏ khi vượt. *Vì board chỉ vẽ Video sound; ít một slider làm cùng một việc.*
- **Một chỗ chọn, một chỗ giữ/bỏ**: khi có item đang chọn, ✕ và ✓ là hai nút duy nhất kết thúc việc sửa nó.
- **Panel giữ nguyên chiều cao** từ lúc mở tới lúc đóng, đổi lệnh hay đổi item cũng vậy — khung video không nhảy.
  Ngoại lệ duy nhất là người dùng tự thu panel chọn item còn 78 bằng grabber ([07 §3](07-phone-layout.md), [07b §4](07b-duo-cover-layout.md)).
- Danh sách công cụ và danh sách lệnh dựng từ **một nguồn**, mọi thiết bị đọc chung
  ([NF-05 §1](../../04-non-functional-design/NF-05-device-and-os-compatibility.md)).

## 3. Thanh dưới — mỗi công cụ mở gì

| Công cụ | Mở | Kết quả |
|---|---|---|
| **Media** | thư viện trong panel ([09](09-media-panel.md)) | chạm = chèn ở playhead; kéo = thả vào timeline |
| **Text** | thêm một khối chữ "Text" từ playhead tới hết video, chọn nó, mở lệnh **Edit** | phiên chọn mở ngay (§5) |
| **Sticker** | trình chọn ảnh tĩnh; chọn xong thêm sticker từ playhead tới hết video và chọn nó | huỷ trình chọn: không đổi gì |
| **Music** | panel Music: Video sound · Add Music from Files… · My Music | chọn một bài = thêm track tại playhead, chọn track đó |
| **Look** | panel Look cả video ([06c](06c-photo-looks.md)) | — |

- Ô đang mở panel có nền trắng 14%; chạm lại ô đó = đóng panel và **giữ** thay đổi.
- Nơi đặt thanh: iPhone hàng đáy 62pt; Duo ngoài cột 5 ô trong rail 84; Duo trong hàng đáy 56pt bên trái;
  iPad ngang là 4 tab pool (Media · Text · Stickers · Music) + inspector mặc định là Look; iPad dọc là 4 nút ở
  tiêu đề dock + dock mặc định là Look.
- *Vì sao Text thêm ngay chứ không mở trang chọn kiểu:* chưa có gallery kiểu chữ; khối chữ trống ở playhead là
  thứ người dùng sửa được ngay.

## 4. Panel công cụ (không có item nào đang chọn)

- Cùng khung với panel chọn item (chiều cao theo thiết bị/tỉ lệ). Ô đang mở sáng; Export vẫn hiện.
- Đóng/huỷ theo từng công cụ, như board vẽ:

| Công cụ | Giữ / huỷ ở đâu |
|---|---|
| Media | đáy thành ✕ · Media · ✓ như một phiên ([09](09-media-panel.md)) |
| Look | ✕ và ✓ ở tiêu đề panel ([06c §7](06c-photo-looks.md)) |
| Music | tiêu đề 46pt: icon 24 · "Add Music" 14,5 · ✕ 32 ở phải; thanh dưới giữ 5 công cụ |
| Video Settings | chỉ có Done ✓ ở tiêu đề, không ✕ — mọi thay đổi áp ngay ([10 §4](10-video-settings-and-export.md)) |

- **✕ ở đâu cũng là: bỏ mọi thay đổi từ lúc mở panel**, không để lại bước undo nào — cùng luật với ✕ của item.
- Đóng bằng cách khác — ✓, chạm lại ô công cụ, vuốt grabber xuống, chạm timeline trống, mở công cụ khác — là
  **giữ**; mỗi thay đổi đã là một bước undo.

## 5. Mô hình chọn

Phiên chọn bắt đầu khi một item được chọn và kết thúc ở ✓ hoặc ✕. Máy ghi lại project **lúc phiên bắt đầu**.
Chọn nhiều clip một lúc dùng cùng ✕ · "N Clips" · ✓ ([11](11-multi-select-and-reorder.md)).

| Sự kiện | Kết quả |
|---|---|
| chạm một clip / băng chữ / sticker / nhạc | chọn nó (viền `#57BFD1`), đáy thành ✕ · tên · ✓, panel mở với hàng lệnh |
| **✓** | giữ, bỏ chọn, đáy về 5 công cụ; mỗi thay đổi trong phiên vẫn là một bước undo riêng |
| **✕** | project về đúng lúc phiên bắt đầu; các bước undo của phiên bị gỡ (Redo không đưa lại); bỏ chọn |
| ✕ khi chưa đổi gì | chỉ bỏ chọn, ngăn undo không đổi |
| item vừa **thêm** (Text, Sticker, Music, Duplicate) | phiên bắt đầu **trước** lúc thêm: ✕ gỡ luôn item vừa thêm |
| chạm item khác | ✓ cho item cũ rồi chọn item mới — không bao giờ mất việc mà không bấm ✕ |
| chạm timeline trống / vùng đen ngoài khung khi đang dừng | = ✓ |
| lệnh **Delete** | xoá item, kết thúc phiên như ✓; một bước undo khôi phục |
| Undo / Redo trong phiên | đi từng bước như thường; Undo qua mốc đầu phiên thì phiên kết thúc, bỏ chọn |
| Back khi đang chọn | = ✓, lưu nháp ngay rồi đóng — **không hỏi Discard** ([18](18-drafts.md)) |
| Esc (bàn phím) | = ✓ ([03b §5](03b-desk-bands-and-lanes.md)); Return = ✓ |
| lane bị Lock | không chọn được item trong lane; khoá lane đang chứa item chọn = ✓ |
| 5 công cụ khi đang chọn | iPhone: thanh thay hẳn bằng ✕ · tên · ✓; Duo trong và Duo ngoài: mờ 30%, không nhận chạm; iPad ngang: pool vẫn dùng được, chèn từ pool = ✓ cho item cũ trước; iPad dọc: 4 nút thêm nhường chỗ cho hàng lệnh |

- **Tên** ở giữa: dòng 1 là tên item cỡ 14 đậm (clip: "Clip 2" / "Photo 2" / "Freeze 2" — số thứ tự
  trên timeline, cùng tên viewer header dùng; app không có tên địa điểm nên không có phần "· Coast" của board; chữ:
  nội dung chữ; nhạc: tên bài), dòng 2 mono 11 trắng 35%: "6.2s · video", "Text · 1.0 → 5.0s", "Music · 0.0 → 18.4s".
- ✕ là đĩa tối `rgba(24,24,26,.82)` viền trong 1pt trắng 14%; ✓ là đĩa **trắng, glyph đen** — accent chỉ dành cho
  Export ([DESIGN §3.1](../../../DESIGN.md)).
- Chỗ đặt ✕ · tên · ✓: iPhone thay hàng đáy; Duo trong góc phải hàng đáy (x 620–907); Duo ngoài chân rail; iPad
  chân inspector (ngang) / chân dock (dọc). Đo ở từng doc bố cục.

## 6. Dữ liệu

| | |
|---|---|
| Đọc / ghi | recipe của project (JSON), không thêm trường nào cho chrome |
| Phiên chọn | trạng thái phiên trong bộ nhớ (bản chụp recipe + độ sâu undo lúc bắt đầu), không lưu, không vào undo |
| Người dùng tự nhập? | không có gì mới |

## 7. Đường hỏng

- Clip chỉ có trên iCloud, máy không mạng: chọn được, panel mở; lệnh cần nguồn (Freeze, Split video) mờ kèm chú
  thích "Waiting for iCloud" thay vì im lặng không làm gì.
- Huỷ trình chọn Sticker / Replace / Files: không thêm gì, phiên chọn (nếu có) giữ nguyên.
- `.limited`: Replace và Media chỉ hiện ảnh đã cho phép kèm "Manage Access…" ([09](09-media-panel.md)).
- Hết bộ nhớ khi ghi project: thay đổi vẫn ở trong phiên, banner "Couldn't save your video draft" + Try Again
  ([18 §6](18-drafts.md)); ✕/✓ vẫn chạy.
- Project lưu từ bản cũ còn khoá Master: bỏ qua khi đọc (đọc khoan dung, app chưa phát hành nên không migration).

## 8. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | iPhone 402×874, project 3 clip, không chọn gì | dump phần tử hàng đáy | đúng 5 nút theo thứ tự Media · Text · Sticker · Music · Look, không có Ratio/Filter/Adjust/Color/Volume/Background | ✅ `VideoStudioToolsTests.theBottomRowIsTheFiveAddToolsInOrder`, `theRowSpreadsFiveCellsOverTheWidth`; sim-shot iPhone 17 (26.5) 2026-10-04: Media · Text · Sticker · Music · Look, không cuộn (XCUITest không liệt kê được Video Studio trên phone nên không dump) |
| AC-2 | danh sách công cụ của mọi bố cục (iPhone, Duo trong, Duo ngoài, iPad) | duyệt từng bố cục | mỗi bố cục có đủ 5 công cụ (iPad: 4 tab/nút + Look mặc định), kiểm bằng lặp, không đếm | ✅ `VideoStudioWindowClassTests.everyLayoutOffersTheFiveAddTools` (lặp `VideoStudioWindowClass.allCases` × `VideoAddTool.allCases`; iPad: 4 nút/tab + Look mặc định) |
| AC-3 | clip 2 đang chọn, Speed đổi 1× → 2× rồi Volume 100 → 60 | bấm ✕ | clip 2 về 1× và 100; số bước undo bằng lúc trước khi chọn; Redo tắt | ⚠️ chưa có |
| AC-4 | như AC-3 | bấm ✓ rồi Undo hai lần | lần 1: Volume về 100, Speed vẫn 2×; lần 2: Speed về 1× | ✅ `VideoSessionCommitTests.commitKeepsEachStep` (2× + Volume 60, ✓, Undo → Volume 100 Speed 2×, Undo → 1×), `undoPastTheSessionStartDeselects`, `VideoEditHistoryTests`; sim-shot iPhone 17: chân ✕ · Photo 2 · ✓ (2026-10-04) |
| AC-5 | không chọn gì | bấm Text rồi ✕ | project không có khối chữ mới; ngăn undo như trước khi bấm Text | ✅ `VideoAddSessionTests.textThenCancelLeavesNoBlockAndNoUndo` (+ `stickerThenCancelRemovesIt`, `musicThenCancelRemovesTheTrack`); sim-shot iPhone 17: Text → khối "Text" ở playhead, Edit sáng, bàn phím lên (2026-10-04) |
| AC-6 | clip 2 đang chọn, Speed đã đổi sang 2× | chạm băng chữ GOLDEN HOUR | clip 2 giữ 2×; đáy là ✕ · GOLDEN HOUR · ✓; panel cùng chiều cao như trước (±0pt) | ⚠️ chưa có |
| AC-7 | project 3 clip, clip 2 đang chọn | bấm Delete | còn 2 clip liền nhau, đáy về 5 công cụ; Undo một lần trả clip 2 về đúng chỗ | ✅ `VideoDeleteTests.deleteKeepsClipsContiguousAndUndoesOnce`, `deleteFromTheTransportMenuIsUndoable`, `captionAndMusicDeletesAreOneStepEach` |
| AC-8 | Duo trong 951×669, clip 2 đang chọn | chạm ô Media | không có gì mở; 5 ô công cụ vẽ trắng 30% | ⚠️ chưa có |
| AC-9 | panel Music mở, Video sound 100 → 40 | bấm ✕ ở tiêu đề panel | Video sound về 100, không còn bước undo nào của lần mở này | ⚠️ chưa có |
| AC-10 | như AC-9 | chạm lại ô Music | panel đóng, Video sound giữ 40; Undo một lần về 100 | ⚠️ chưa có |
| AC-11 | clip 1 là video chỉ có trên iCloud, máy không mạng | chọn clip 1 | panel mở; Freeze mờ, có chữ "Waiting for iCloud"; không spinner quay mãi | ⚠️ chưa có |
| AC-12 | lane V1 bị Lock | chạm clip 2 | không chọn; đáy vẫn 5 công cụ | ✅ `VideoSelectionSessionTests.aLockedLaneRefusesSelection` |
| AC-13 | iOS 26.5 và iOS 18.6, cùng project, clip 2 đang chọn | dump hai bên | cùng tập nút: ✕, ✓, mọi lệnh hàng đầu panel | ⚠️ chưa có — agent `ios26-parity` |
| AC-14 | iPad ngang, Quick Adjust bật, clip 2 (video) dưới playhead; iPhone, panel Music mở | dump cả hai | Quick Adjust: Speed · Video sound, không có Master; panel Music: Video sound là dòng âm lượng duy nhất trên "Add Music from Files…" | ✅ iPad Pro 13 (dọc) dump nút 2026-10-04: Quick Adjust = Duration · Video sound (clip ảnh; clip video thay Duration bằng Speed), không "Master", meter "Mute Video Sound"; iPhone 17 sim-shot panel Music: Video sound là dòng âm duy nhất trên "Add Music from Files…"; `VideoStudioToolPanelTests.theMusicCellOpensTheMusicPanel` |
| AC-15 | project JSON còn khoá Master = 0,5; Video sound 100, clip 2 Volume 100 | mở project, Export | project mở bình thường; mức âm clip 2 trong file xuất = mức nguồn (không nhân 0,5) | ✅ `VideoRecipeDecodingTests.aMasterKeyIsIgnored` (JSON có Master 0,5 mở ra, ghi lại không còn khoá) + `VideoAudioMixTests.clipGainIsVideoSoundOnly` (tham số audio mix của clip tại 1 s = 1,0); smoke export file dùng chung test của plan Export |

**Chưa chứng minh được:** AC-3, AC-6, AC-8, AC-9, AC-10, AC-11, AC-13.

## 9. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| ✕ gỡ bước undo nhưng một thao tác nền (dựng lại preview) đang chạy trên bản cũ | ✕ huỷ lần dựng đang chạy rồi dựng lại từ bản chụp |
| người quen thanh cũ tìm Ratio ở hàng đáy | Video Settings có hình tỉ lệ đúng của project ngay băng trên |
