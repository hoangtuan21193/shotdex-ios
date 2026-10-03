# FS-12.03b — Các băng của bàn dựng và lane màn rộng

`FS-12.03b` · `Features/VideoStudio/` (`VideoViewerChrome`, `VideoAudioMeterColumn`, `VideoTimelineGutter`)
· test `VideoStudioDeskLayoutTests` · cập nhật 2026-10-03
· nguồn intent [video-studio-canvas-chrome](../../_intents/2026-10-03-video-studio-canvas-chrome.md)

**Một câu:** bên trong bố cục rộng ([03](03-timeline-and-desk-layout.md)) — pool, viewer header, transport, dải
tổng quan, meter, track header — mỗi băng có một việc và lấy chiều cao từ băng preview, không từ timeline.

## 1. Pool và viewer header

- **Pool** (chỉ iPad, rộng 236): tiêu đề "Library" 34 (Search Library · Hide Media), hàng tab 38 **Media · Text ·
  Stickers · Music** (nhãn 10,5), rồi nội dung tab. Nội dung tab Media: [09](09-media-panel.md).
- Tab **Text**: nút "Add Text" 44 bo 12 rồi "FONTS YOU USED" (hàng 50: "Aa" 22 + tên font 13) và dòng "Fonts you use
  appear here, ready to reuse." Tab **Music**: dòng Video sound, "Add Music from Files…", MY MUSIC — cùng nội
  dung panel Music của iPhone ([04 §3](04-tools-and-inspector.md)).
- Pool mở mặc định khi rộng ≥ 1100; dưới đó đóng, bật bằng nút Media Pool. Chỉ mở được khi khung còn ≥ 330pt.
- **Viewer header** 32: Media Pool · **tên thứ dưới playhead** ("Clip 2" — [04 §5](04-tools-and-inspector.md)) · Quick Adjust · Inspector.
  Tồn tại vì khung hình là vùng duy nhất không tự nói nó đang chiếu gì — và pool mở là có hai tấm ảnh trên màn.
- **Quick Adjust**: dải 44 dưới khung: Speed (clip) · Duration (ảnh) · Video sound (âm gốc mọi clip; không có
  Master — [04 §2](04-tools-and-inspector.md)), mỗi cái bung slider tại chỗ. **Mặc định tắt**: bật sẵn là ăn 44pt của
  khung trên cửa sổ cao 669.

## 2. Transport và dải tổng quan

| Nhóm | Nút (iPad 40pt, Duo trong 36pt) |
|---|---|
| Sửa tại playhead | Split at Playhead · Freeze Frame · Trim Start to Playhead · Trim End to Playhead · Delete Clip |
| Phát | Go to Start · Back a Frame · **Play** (nền trắng 12%) · Forward a Frame · Go to End · Loop Playback |
| Marker | Previous Marker · Add Marker · Next Marker |
| Nhìn | Fit Timeline to Window + timecode `0:08.4 / 0:24.0` |

- Nhóm "sửa tại playhead" tác động **clip dưới playhead**, không phải item đang chọn — đó là việc của hàng lệnh.
- **Loop là trạng thái phiên**, không vào project. Timecode đếm đúng nhịp render (30 khung).
- Dưới 780pt sân khấu, transport rơi về hàng hẹp của điện thoại ([07 §2](07-phone-layout.md)).
- **Dải tổng quan** 22: cả project trên một dải, mỗi clip một khối, playhead đỏ `#FF453A` 2pt, khung trắng 50% là
  phần timeline đang nhìn, chấm marker; kéo để seek. Cần vì ở mức zoom làm việc chỉ thấy vài giây.

## 3. Đồng hồ đo mức

- Cột 50 có thang dB (32, chỉ bar, khi sân khấu < 820), nằm **trong cột khung**, cao bằng sân khấu.
- Đọc **chính bản mix của recipe tại playhead**: đường bao đỉnh stereo từng clip (không normalize) × âm lượng ×
  mute, cộng năng lượng với đường bao từng bản nhạc, × đường fade — **đúng đường fade export ghi ra** — ra dBFS.
- Không dùng waveform của lane nhạc: cái đó normalize để lấp lane nên bản to và bản nhỏ vẽ giống nhau.
- Thang **tuyến tính theo dB**: sàn −54, vàng từ −18, đỏ từ −6; gradient được mask chứ không co.
- Đọc được cả khi dừng và khi scrub — thứ một bộ nghe lén lúc phát không làm được.

## 4. Track header và lane

| | iPad (ngang, dọc) | Duo trong |
|---|---|---|
| Cột trái | **track header 104**: thẻ 92 — badge `T1`/`V1`/`A1` + tên + **Lock** + **Mute** | **cột badge 100**: lề 6 · badge 26 · khe 4 · **Lock** 28 · khe 4 · **Mute** 28 · lề 4; không tên |
| Lane chữ / video / nhạc | **44 / 104 / 52** | 34 / 66 / 40 |
| Thumbnail clip | 88 rộng | 54 rộng |
| Thước | 39 | 33 |

- **Duo trong có Lock và Mute** (chốt 2026-10-03): đĩa 28 nền trắng 10%, glyph 13, vùng chạm 32 rộng × cao lane
  (lane chữ 34 vẫn đủ); lane chữ chỉ có Lock. *Vì hàng transport Duo không có ⋯ — bỏ hai nút là Lock/Mute không tới
  được trên Duo trong, trái luật đủ mọi chức năng.* Cột rộng thêm 36pt so với board cũ: board DI* vẽ lại.
- **Lock là trạng thái phiên**: chặn chọn và mọi thao tác kéo trong lane; khoá lane chứa item đang chọn = ✓.
- **Mute lane Video** đi qua âm lượng và nhớ mức cũ (0 là mức chỉnh được nên không suy mute từ âm lượng).
  **Mute lane nhạc** đặt 0 cho mọi track trong lane trong **một** bước undo. Lane chữ không có Mute.
- Thumbnail xin theo **chiều cao ô × scale màn** (sàn 240px) — ô 88pt ở 3× cần 264px.
- Nửa trái ở mốc 0 không để trống: thước kẻ đường nền hết bề rộng, rail rỗng từng lane phía sau.
- **Tay cầm chia preview / timeline** (iPad, grabber 36×4 ở đỉnh timeline): 0…400pt thêm cho timeline, mặc định 0;
  có hành động trợ năng bước 40pt.

## 5. Phím tắt và viền khung

- Bảng phím đầy đủ ở [17b](17b-keyboard-and-pointer.md). Riêng với phiên chọn: **Esc bỏ chọn = ✓** (giữ thay đổi);
  Esc chỉ là ✕ trong chế độ Trim từng khung ([17](17-precise-trim-and-input.md)). *Vì Esc của NLE là bỏ chọn, không
  bao giờ là hoàn tác; ✕ là nút bấm có chủ ý.*
- **Viền khung canvas**: nét 1pt đúng vùng nội dung xuất, vì nền letterbox và sân khấu cùng đen làm ảnh 3:2 trong
  project 16:9 trông như project 3:2.

## 6. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | project 10 s, âm lượng 1, fade in 2 s, fade out 2 s | đọc hệ số meter tại 0 · 1 · 5 · 9 s | 0 · 0,5 · 1 · 0,5 — đúng đường fade export dùng | `VideoStudioDeskLayoutTests.theMeterReadsTheSameFadeEnvelopeTheExportWrites` |
| AC-2 | thang meter | test thuần 0 dB, sàn, nửa sàn, −120, +6 | 1 · 0 · 0,5 · kẹp 0 · kẹp 1 | `VideoStudioDeskLayoutTests.theMeterScaleIsLinearInDecibels` |
| AC-3 | iPad ngang 1376×1032 | dump transport | đủ 15 nút theo 4 nhóm §2 trong một hàng 44, không nút nào ngoài mép | ⚠️ một phần — vị trí: `VideoStudioDeskGeometryTests.theTransportAlwaysGetsTheFullRowOnA13InchIPad` (hàng chạy hết 1376 dù pool/inspector mở hay đóng), dump `ipad-vs-landscape.json`: 15 nút trong một hàng, nút cuối Fit ở x 1231, không frame `inf`; nội dung (nút 40, Play trắng 12%, Delete theo playhead, timecode `0:08.4`) chờ task 16 |
| AC-4 | iPad, lane V1 Volume 60 | bấm Mute lane rồi bấm lại | lần 1 không tiếng; lần 2 về 60 | `VideoStudioTrackSwitchTests.mutingTheVideoLaneRestoresItsLevel` |
| AC-5 | iPad, 2 track nhạc trong A1 | bấm Mute A1 rồi Undo một lần | cả hai về mức cũ | `VideoStudioTrackSwitchTests.mutingAMusicLaneUndoesInOneStep` |
| AC-6 | clip 2 đang chọn, Speed đổi 2×, bàn phím cắm | bấm Esc rồi ⌘Z | sau Esc: bỏ chọn, Speed vẫn 2×; sau ⌘Z: 1× | `VideoStudioTrackSwitchTests.escapeKeepsTheChangeAndUndoRevertsIt` (gọi `pressEscape()`, hành động duy nhất của phím Esc) |
| AC-7 | iPad ngang, pool tab Music | dump | dòng "Video sound" ở đầu, nút "Add Music from Files…" (không phải "Import from Files…") | ⚠️ chưa có |
| AC-8 | Duo trong 951×669 | dump timeline | cột badge 100 có nút Lock ở T1 · V1 · A1 và Mute ở V1 · A1; lane 34 / 66 / 40 | ⚠️ một phần — số: `VideoStudioLayoutTests.eachWindowClassGetsItsLaneTier` (bậc lane theo lớp cửa sổ, iPhone 40/80/46 là `Lanes.phone`), `VideoStudioDeskLayoutTests.duoInnerGutterIsA100ptBadgeColumnWithLockAndMute` (6·26·4·28·4·28·4, vùng chạm 34–66 / 66–98, nhãn Lock Text/Video/Music 2, Mute Video); **dump chưa có**: sim Duo boot ở trạng thái gập, màn trong không mở được từ dòng lệnh |
| AC-9 | các board IL1, IP1, DI1 | `Tools/design-board compare` transport, dải tổng quan, track header | lệch ≤ 2pt | ⚠️ chưa có — agent `design-parity` |

**Chưa chứng minh được:** AC-3, AC-7, AC-9.

## 7. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| board IL4 ghi "Import from Files…", các board khác "Add Music from Files…" | một hành động một tên: "Add Music from Files…"; sửa IL4 |
| hai nhóm Trim to Playhead (transport và hàng lệnh) tác động hai clip khác nhau | nhãn transport ghi rõ "at Playhead"; hàng lệnh chỉ sửa item đang chọn |
