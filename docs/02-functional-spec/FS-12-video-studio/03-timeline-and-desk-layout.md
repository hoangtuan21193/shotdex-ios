# FS-12.03 — Timeline và bố cục bàn dựng

`FS-12.03` · `Features/VideoStudio/` · `Domain/Video/VideoStudioMetrics.swift`
· test `VideoStudioLayoutTests` · `VideoStudioDeskLayoutTests` · cập nhật 2026-09-22

**Một câu:** trên cửa sổ rộng, màn này thành một bàn dựng — thư viện bên trái, khung hình và đồng hồ đo ở
giữa, inspector bên phải.

Bố cục điện thoại: [FS-12.07](07-phone-layout.md).

## 1. Quy tắc

- **Phần dư của màn thuộc về quanh khung hình**, không thuộc về dưới các track — đen quanh preview là thứ
  mọi NLE đều có.
- **Timeline chỉ lấy đúng phần lane cần**; phần dư trả về băng preview.
- Bố cục bàn dựng gate theo **bề rộng cửa sổ ≥ 600**, thấp hơn ngưỡng 700 của các quyết định khác — mấy
  băng này tiêu **chiều cao mà cửa sổ cao đang thừa**.
- **Khung hình phải tự nói nó đang chiếu gì** khi có hai tấm ảnh trên màn cùng lúc.

## 2. Chia preview và timeline

- Preview lấy đúng chiều cao fit của khung (tối thiểu **150**); timeline lấy phần còn lại nhưng không dưới
  **248**.
- Project ngang được timeline cao (~390 trên máy 17 Pro) thay vì một dải đen; project dọc thì preview bị
  kẹp để timeline giữ 248.
- **Trần theo nội dung áp cho mọi bề rộng**: trước đây chỉ áp từ 700pt nên **điện thoại cũng dính** — ba
  lane nằm trên đỉnh một vùng đen ~330pt có playhead kẻ dọc giữa chỗ trống, còn preview thì ép lên sát băng
  trên.
- **Bề rộng đưa vào phép chia phải trừ mọi cột chrome**: preview vẽ trong cột cạnh chúng, tính chiều cao
  fit từ bề rộng cả cửa sổ là tính cho một cột không tồn tại.
- Panel ngữ cảnh 264pt trượt lên, **và chồng bên trên nhấc lên đúng phần chênh** để **toàn bộ timeline vẫn
  thấy** — clip đang chọn không còn bị panel che. Phần nhấc lấy từ chỗ dư của timeline trước, hết mới co
  preview.
- **Panel neo trong chồng khi cửa sổ còn dư chiều cao**: nếu bỏ panel ra khỏi băng preview mà khung vẫn giữ
  đúng cỡ fit tự nhiên thì panel xuống nằm **dưới** timeline — không che gì, timeline không nhúc nhích, và
  chỗ đen vốn chỉ để đệm quanh khung nay thành điều khiển của thứ đang chọn. iPad dọc 16:9 dư ~470pt nên
  neo được; iPhone và iPad ngang không dư nên panel vẫn trượt đè.
- **Không khoá hướng cho Video Studio**: màn dọc phải dùng được, nên phần dư của màn dọc phải có việc để
  làm chứ không phải khoá hướng để né.
- **Cửa sổ quá thấp thì timeline lui hẳn** (chỉ khi cao ≤ **660** — thấp hơn mọi iPhone đang bán, tức là
  màn cover hướng ra ngoài) và preview giữ nguyên: đo trên màn cover Duo, mở panel là ba vùng cùng vỡ
  (preview 150, timeline 140, khung 266×150); lui timeline thì khung vẫn 344×194. Trong ba vùng đó timeline
  là cái **lấy lại được bằng một thao tác**, còn một cái khung không nhìn thấy thì không.
- Đóng panel: vuốt tay nắm xuống, chạm timeline trống, **hoặc chạm vùng đen ngoài khung khi đang dừng**.

## 3. Năm băng của bàn dựng

| Băng | Nội dung |
|---|---|
| **Media pool** (trái, rộng 300 / 236 dưới 900pt) | thư viện mở sẵn cạnh project — đúng chỗ các NLE để browser |
| **Đồng hồ đo mức** (cạnh khung, rộng 50 có thang dB / 32 chỉ có bar dưới 820pt) | nằm **trong cột khung hình**, không phải một cột chạy suốt màn |
| **Viewer header** (cao 32) | nút Media Pool · **tên thứ đang nằm dưới playhead** · tổng timecode · nút Inspector |
| **Transport** (cao 44) | trái: Split · Freeze · Delete tại playhead. Giữa: đầu · lùi 1 khung · play/pause · tiến 1 khung · cuối · **Loop**. Phải: Fit to Window + timecode |
| **Project overview** (cao 22) | cả project trong một dải trên thước, mỗi clip một khối, playhead đỏ, khung trắng đánh dấu phần timeline đang phóng to; kéo để seek |

- **Media pool đọc thẳng thư viện ảnh** (giới hạn **400** item), không qua index: pool cần thứ thư viện
  đang có **ngay lúc này**, và duyệt cả 55k asset trên main trước khi xin thumbnail đầu tiên là cái giá
  không ai trả. Chạm = nối vào lane Video; kéo = thả xuống timeline (hoặc ra ngoài app).
- Pool mặc định **mở khi rộng ≥ 1100**, còn lại đóng và bật bằng nút trong viewer header. Chỉ mở được khi
  khung hình còn **≥ 330pt** sau khi trừ pool và meter.
- **Viewer header tồn tại vì khung hình là vùng duy nhất trên màn không tự nói nó đang chiếu gì** — và khi
  pool mở thì trên màn có **hai** tấm ảnh cùng lúc.
- **Loop là trạng thái của phiên**, không phải một phần của project: nó nói cách người ta đang *xem*.
- Timecode đếm ở đúng nhịp render, nếu không bước một khung sẽ nhảy hai số ở trường cuối.
- **Project overview là tấm bản đồ**: timeline đậu ở playhead giữa cố định nên ở mức phóng làm việc chỉ
  thấy vài giây của một project dài mấy phút.

## 4. Đồng hồ đo mức lấy tín hiệu từ đâu

Player **không cấp số đo**, nên meter đọc **chính bản mix của recipe tại playhead**:

- Đường bao đỉnh stereo từng clip (ép 2 kênh, **không normalize** vì meter đọc mức tuyệt đối) nhân âm lượng
  và mute, cộng năng lượng với đường bao **riêng của bản nhạc** (cache theo file nên hai track cùng bài chỉ
  decode một lần), nhân đường fade — **đúng đường fade mà export ghi ra** — rồi đổi sang dBFS.
- **Không dùng waveform của lane nhạc**: cái đó normalize để lấp đầy lane 52pt nên bản to và bản nhỏ vẽ
  giống hệt nhau.
- Đó là mức file xuất ra sẽ có, và **đọc được cả khi dừng lẫn khi scrub** — thứ một bộ nghe lén lúc phát
  không làm được.
- Thang **tuyến tính theo decibel** (sàn −54, vàng từ −18, đỏ từ −6); gradient được **mask** chứ không co,
  nếu không màu đỏ rơi xuống −40 mỗi khi mix nhỏ tiếng.

## 5. Track header và lane ở màn rộng

- Cột glyph thành **track header rộng 104**: badge `V1`/`T1`/`A1` + tên lane + **Lock** và **Mute**.
- **Lock là trạng thái phiên** (không vào project, không vào undo): nó chặn chọn và chặn mọi thao tác mà
  một cú kéo trên timeline có thể gọi, và khoá xong thì bỏ chọn luôn thứ đang chọn trong lane đó.
- **Mute lane Video** đi qua âm lượng (nhớ giá trị cũ để trả lại — 0 là một mức người dùng chỉnh được nên
  không đọc trạng thái mute từ âm lượng được). **Mute lane nhạc** đặt âm lượng 0 cho mọi track trong lane
  trong **một** bước undo.
- **Lane text không có nút mute** — ở đó không có gì để nghe.
- Lane nở ở màn rộng: cao **44 / 104 / 52** (so với 34 / 66 / 40), thước 30, ô clip 88 (so với 54). Track
  66pt trên màn 1032pt là track điện thoại đặt lên tablet, mà **thumbnail chính là thứ để quyết định một cú
  cắt**.
- Ô clip xin thumbnail theo **chiều cao ô × scale màn** (sàn 240px) thay vì một hằng số — ô 88pt ở 3× cần
  264px, phóng 240px lên là đúng cái filmstrip mờ mà lane cao hơn lẽ ra phải sửa.
- **Nửa trái ở mốc 0 không được để trống**: thước kẻ **đường nền chạy hết bề rộng** kể cả nơi chưa có mốc
  thời gian, và phía sau có **rail rỗng cho từng lane** — nửa trái phải đọc ra là "timeline chưa bắt đầu",
  không phải "màn hình hỏng".
- **Tay cầm kéo chia preview / timeline** (chỉ ở màn rộng, 0…400pt cộng thêm cho timeline, mặc định 0):
  luật "phần dư thuộc về quanh khung" vẫn là câu trả lời **khi không ai hỏi**; tay cầm là cách người dùng
  hỏi. Có hành động accessibility bước 40pt vì kéo bằng cử chỉ thì VoiceOver không dùng được.

## 6. Phím tắt

Space play/pause · ←/→ ±1s · ⇧←/⇧→ ±1 khung · Home/End · ⌘Z / ⇧⌘Z · ⌘B split · **⌘E mở sheet Export**
(không xuất luôn — phím tắt đưa người dùng tới đúng chỗ cái nút đưa tới, không tự ghi vào thư viện) ·
Esc bỏ chọn.

## 7. Vẽ viền khung canvas

Compositor letterbox lên màu nền (mặc định đen) còn stage cũng đen, nên ảnh 3:2 trong project 16:9 trông
**đúng như một project 3:2** — người dùng không nhìn thấy cái khung mình sắp xuất. Một nét 1pt vẽ đúng
vùng nội dung. Đây là lý do thật của "470pt đen không hiểu vì sao" trên iPad dọc.

## 8. Tiêu chí nghiệm thu

Xem [README](README.md).
