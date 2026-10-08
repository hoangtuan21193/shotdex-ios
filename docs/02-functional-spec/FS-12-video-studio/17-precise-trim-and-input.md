# FS-12.17 — Cắt từng khung và scrub chính xác

`FS-12.17` · tier D · `Features/VideoStudio/` (timeline, viewer, inspector) · `Domain/Video/VideoTimelineMath.swift`
· nguồn intent [video-studio-canvas-chrome](../../_intents/2026-10-03-video-studio-canvas-chrome.md) (F6) · cập nhật 2026-10-04 (iPad kiểu Mac)

**Một câu:** dời mép một clip đúng từng khung hình, nhìn thấy khung mình đang cắt, bằng ngón tay, Apple Pencil
hay nút ±1 khung, và scrub timeline từng khung một.

Tay nắm mép clip và lệnh Trim (Start/End to Playhead): [FS-12.05](05-cutting-markers-and-fades.md). Chọn nhiều: [FS-12.11](11-multi-select-and-reorder.md). Bàn phím và
con trỏ: [FS-12.17b](17b-keyboard-and-pointer.md). Board hàng F6: `F6_P_*` ([`docs/design/iphone/project/`](../../design/iphone/project/)) · `F6_IP_PencilTrim`, `F6_IL_*` ([`docs/design/ipad/project/`](../../design/ipad/project/), kiểu Mac 2026-10-04) · `F6_DI_*`, `F6_DC_*` ([`docs/design/duo/project/`](../../design/duo/project/)).

## 1. Người dùng cần gì

Kéo mép clip ở 55 pt/giây thì một khung chỉ là 1,8pt, nhỏ hơn đầu ngón tay. Người dựng muốn bỏ đúng khung nháy
mắt cuối shot, hay cắt đúng khung trước khi người trong hình bước ra. Họ cần thấy khung ở mép, và cần một bước
không thể lệch: một chạm là một khung.

## 2. Phạm vi

**Có:** chế độ **Trim từng khung** cho clip trên lane video (video, ảnh, freeze); kính lúp; ±1 khung; **Frame zoom**
(1 khung = 12pt); Pencil trên iPad.

**Cố ý không có:**
- Ripple/roll/slip/slide trim. *Vì lane video không có khoảng trống (FS-12.05 §5), mép nào dời thì clip sau dồn theo.*
- Lối cắt bằng cử chỉ ngón tay cũ của FS-12.07. Đã bỏ (intent, câu chốt 2); chỉ còn tay nắm mép và lệnh Trim.
- Chế độ từng khung cho băng nhạc, chữ, sticker. *Vì chúng không có khung hình để nhìn; snapping 8pt đã đủ.*

## 3. Vào và ra chế độ

- **Vào:** giữ yên tay nắm mép **0,5 s** (lệch ≤ 4pt). Kéo ngay thì vẫn là trim thường của FS-12.05.
  Trên Duo trong và iPad còn vào được bằng ô **Trim** của hàng lệnh; khi đó mép hoạt động là mép gần playhead hơn.
- **Mép hoạt động:** mép vừa giữ. Chạm tay nắm còn lại để đổi mép; nhãn và kính lúp đổi theo.
- **✓** ghi cả phiên thành **một** bước undo. **✕** trả clip về đúng lúc vào chế độ, không để lại bước undo.
- **Back** ở băng trên khi đang trong chế độ = ✓ rồi rời màn. *Vì người dùng đã thấy kết quả, bỏ âm thầm là mất việc.*
- Đang trong chế độ, recipe chưa đổi. Phần bị cắt vẽ gạch chéo tại chỗ; phần nới thêm vẽ viền `timelineSelection`
  đè lên clip kế bên. Clip sau chỉ dồn khi bấm ✓.
  *Vì dựng lại composition mỗi khung thì một lần bấm ±1 phải chờ dựng lại; viewer tự giải mã khung ở mép.*
- Lane đang khoá: tay nắm không hiện, giữ không vào chế độ.

## 4. Bố cục từng máy

| Máy | Board | Khi trong chế độ |
|---|---|---|
| iPhone 402×874 | F6_P_PreciseTrim | Panel ẩn, timeline cao 464 (như lúc không chọn). Pill nổi 248×48 bo 24 tại (77, 728): **‹ −1 Frame** · thời điểm 15pt + "−4 frames" 10.5pt · **+1 Frame ›** (nút 76×40 bo 12). Đáy 62: ✕ 44 · "Trim · Clip 2" / "0:09.07 · −4 frames" · ✓ 44 trắng |
| Duo trong 951×669 | F6_DI_TouchTrim | Cột phải 264: hàng lệnh (ô 64×56) bắt đầu **−1 Frame · +1 Frame · Frame Zoom · Trim** (Trim nền trắng 14%); Split ẩn; sau đó Speed … Delete. Dưới: Speed · Volume (clip video không có Duration — [05 §3](05-cutting-markers-and-fades.md)), khối **PRECISION** (2 công tắc, §7), chú thích. Hàng đáy: 5 công cụ mờ, không nhận chạm; bên phải ✕ 40 · "Trim · Clip 2" / "0:09.07 · −4 f" · ✓ 40 |
| iPad dọc 1032×1376 | F6_IP_PencilTrim (kiểu Mac 2026-10-04) | Dock 324: hàng lệnh có **Trim** bật (y 1061); **bốn** cột 238 cách 16 (dock thường là 3 × 312): **Trim** (Start to Playhead · End to Playhead 238×44 + "Or drag the clip's edges on the timeline.") │ Speed · Volume │ **Pencil** (2 công tắc 51×31, §8, + "Double-tap the Pencil to switch between trim and scrub.") │ **Precision** (2 công tắc, §7). Chân 64 ở y 1312: ✕ 44 · "Trim · Clip 2" / "0:09.07 · −4 frames" · ✓ 44 — cùng chữ với iPhone |
| iPad ngang 1376×1032 | không có board | như iPad dọc, các khối Trim · Speed/Volume · Pencil · Precision xếp dọc trong inspector 360 dưới hàng lệnh (y 80), cuộn |
| Duo ngoài 466×678 | F6_DC_PreciseTrim (vẽ thêm) | Vùng nội dung 382 rộng; panel ẩn, timeline 334–644; tên "Trim · Clip 2" / "0:09.07 · −4 frames" ở dòng đầu vùng timeline; pill 248×48 giữa vùng 382 (x 67), đáy pill cách 644 là 14pt (y 582–630); kính Ø124; dải 84: 5 công cụ mờ, ✕ 44 ở y 504, ✓ 44 ở y 556, Export ẩn — như khi chọn item |

- Viewer: nhãn góc trên trái "**Last frame** · 0:09.07" (mép cuối) hoặc "**First frame** · …" (mép đầu), cao 22
  trên iPhone, 24 trên Duo trong; viewer chiếu đúng khung đó. Khung video không đổi kích thước khi vào chế độ.
- −1 / +1 Frame của Duo trong = pill iPhone. Ô **Frame Zoom** bật/tắt Frame zoom (§6) quanh mép hoạt động.
- **Một chế độ, một tên:** đáy/chân mọi máy ghi "Trim · Clip 2" / "0:09.07 · −4 frames" (Duo trong rút "−4 f").

## 5. Kính lúp và bước từng khung

- **Kính lúp** hiện khi ngón (hoặc Pencil) đang giữ mép: tròn Ø124 (iPhone), Ø140 (Duo trong), **Ø152** (iPad kiểu Mac; trước 208); viền
  trắng 3pt; tâm ngang đúng mép. Đáy kính cách mép trên clip 2pt (iPhone), 25pt (Duo trong), 20pt (iPad); chạm mép màn thì
  trượt vào trong, cách mép 8pt. Nhấc tay thì kính ẩn; pill, nhãn viewer và chế độ vẫn còn.
- Trong kính: **10 khung liền nhau** (dải 13pt, bước 14pt trên iPhone), 5 khung trước và 5 khung sau đường cắt.
  Đường cắt dày 3pt màu `timelineSelection`. Nhãn đáy kính "0:09.07 · −4 f" (iPhone), "· −4 frames" (Duo trong, iPad).
- **Một khung = một khung của project** (fps trong Video Settings, mặc định 30), tính trên thời gian timeline.
  Clip tốc độ 2× thì một khung timeline dời cửa sổ cắt 2/fps giây trong nguồn.
- Clip ảnh: dời thời lượng ảnh từng khung, trong dải 0,5–10 s.
- **Số "−4 frames"** là số khung mép đã dời kể từ lúc vào chế độ; âm = sớm hơn. "−1 Frame" luôn dời mép sớm hơn 1 khung.
- **Thời điểm** hiện dạng phút:giây.phần trăm giây ("0:09.07") là thời điểm của mép trên timeline; playhead theo mép.
- Chạm biên (đầu/cuối nguồn, clip còn 0,1 s, ảnh 0,5 hoặc 10 s): nút bên đó mờ 35% và không nhận chạm. Kéo tới biên
  thì có một haptic va chạm, mép dừng lại.
- Kéo mép khi đang giữ: mỗi khung đi qua một haptic chọn (tắt được, §7); mép luôn rơi đúng lưới khung.

## 6. Frame zoom — scrub từng khung

- Pinch timeline ra tới **12pt mỗi khung** (360 pt/giây ở 30 fps, 288 ở 24, 720 ở 60). Dải zoom cũ 20–160 pt/giây
  nâng trần lên mức này khi công tắc "Frame zoom on pinch" bật.
- Ở trần đó (board F6_P_FineScrub): pill 270×26 bo 13 ở giữa, cách đỉnh timeline 276, "**Frame zoom · 1 frame = 12 pt**";
  dòng gợi ý 11.5pt bên dưới ghi "pinch in to return" (board đang ghi "pinch out" — sửa board). Thước đổi sang "giây:khung f" mỗi 6 khung (72pt, "8:12f"), vạch nhỏ mỗi khung.
- Kéo timeline: mỗi 12pt là đúng một khung, một haptic chọn. Thả tay thì dừng ở khung gần nhất.
  Huy hiệu `timelineSelection` 92×18 phía trên ngón: "−1 f · 0:08.87" (số khung từ đầu cú kéo · thời điểm).
- Ở Frame zoom viewer tìm khung **chính xác** (không dung sai); scrub thường giữ dung sai hiện tại.
  *Vì dung sai ±0,05 s rộng hơn một khung 0,033 s: viewer sẽ chiếu sai khung.*
- Pinch vào là ra khỏi Frame zoom; pill biến mất.

## 7. Công tắc PRECISION

| Công tắc | Mặc định | Tắt thì |
|---|---|---|
| Frame steps with haptics | bật | không có haptic mỗi khung; bước vẫn đúng khung |
| Frame zoom on pinch | bật | trần zoom giữ 160 pt/giây; ô Frame Zoom vẫn dùng được |

- Lưu theo máy, không theo project. Duo trong: khối PRECISION trong cột phải. **iPad: hai công tắc là cột Precision cạnh cột
  Pencil** của chế độ Trim (board `F6_IP_PencilTrim` kiểu Mac đã vẽ) — transport bàn dựng iPad không có ⋯ (chốt 2026-10-03).
  iPhone, Duo ngoài: mục **Precision** trong menu ⋯ của transport. *Vì panel iPhone ẩn khi đang cắt, và điện thoại có đủ mọi thứ iPad có.*

## 8. Apple Pencil (iPad)

- Ô Trim bật: Pencil chạm mép là vào chế độ ngay, không cần giữ 0,5 s. Ngón tay vẫn cuộn timeline; lòng bàn tay bị bỏ qua.
- **Frame steps when held still**: Pencil đứng yên (lệch ≤ 2pt) 0,3 s giữa lúc kéo mép thì phần còn lại của nét đi
  1 khung mỗi 12pt.
- **Hover shows the trim point**: Pencil lơ lửng trên lane video thì một vạch 1pt `timelineSelection` và nhãn thời điểm
  chỉ chỗ mép sẽ rơi. Máy không có hover thì công tắc này ẩn.
- **Chạm đúp Pencil** (đời có chạm đúp) đổi giữa **trim** và **scrub**: ở scrub, Pencil trên lane dời playhead, không bắt mép.
  Dòng chú thích của khối TRIM nói điều này.

## 9. Dữ liệu và undo

| | |
|---|---|
| Project | không thêm trường; ✓ ghi vào cửa sổ cắt / thời lượng ảnh đã có của clip. Undo: một phiên = một bước |
| Theo máy | 4 công tắc (§7, §8), lưu trong cài đặt của app |

## 10. Đường hỏng

- **Clip chỉ có trên iCloud, không mạng:** kính lúp vẽ 10 dải xám và chữ "Offline"; viewer giữ khung cuối đã có.
  Bước ±1 vẫn chạy (chỉ là số học), ✓ vẫn ghi. Không gọi tải chỉ để vẽ kính.
- **Cử chỉ bị hệ thống huỷ** (cuộc gọi, Control Center) hoặc app xuống nền: mép dừng ở khung cuối đã tới, chế độ vẫn mở.
- **Bộ nhớ:** khung trong kính giải mã ở cỡ ≤ 2× kính; giữ tối đa 30 khung mỗi mép; cảnh báo bộ nhớ thì xả hết.
- **`.limited`:** không đổi gì — clip đã trong project thì đọc được.
- **Project 24 fps mà nguồn 30 fps:** mép rơi theo lưới khung của project; kính chiếu khung nguồn gần nhất.

## 11. Đã chốt (2026-10-03) — việc của canvas

- **Duo ngoài có đủ cắt từng khung và danh sách phím:** vẽ thêm `F6_DC_PreciseTrim` (bố cục ở §4) và `F6_DC_Keyboard`
  (danh sách dạng iPhone trong vùng panel 334–644, [17b §4](17b-keyboard-and-pointer.md)) trước khi code phần Duo ngoài.
  *Vì điện thoại có đủ mọi thứ iPad có.*
- **Hai chỗ chữ trên board:** F6_P_FineScrub sửa "pinch out to return" → "pinch in to return"; chân F6_IP_PencilTrim
  sửa theo iPhone ("Trim · Clip 2" / "0:09.07 · −4 frames").
- F6_DI_TouchTrim và F6_IP_PencilTrim bỏ dòng Duration của clip video.
- F6_IP_PencilTrim thêm hai công tắc PRECISION cạnh khối PENCIL (§7).

## 12. Tiêu chí nghiệm thu

Project mẫu 30 fps: Clip 1 ảnh 3,0 s · **Clip 2** video nguồn 12,0 s, cắt [0,0–6,2] · Clip 3 video 5,0 s. Mép cuối Clip 2 ở 9,20 s.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | iPhone, project mẫu, Clip 2 đang chọn | giữ yên mép cuối Clip 2 0,5 s | pill 248×48 tại (77, 728); đáy "Trim · Clip 2" với ✕ và ✓; hàng 5 công cụ ẩn; viewer ghi "Last frame · 0:09.20"; kính Ø124 hiện | ✅ `FrameTrimSessionTests.entersAtTrailingEdge` (mép 9,20, "0:09.20", "Last frame · 0:09.20", viewer = khung cuối 6,2 − 1/30, kính 5 trước / 5 từ đường cắt), `theModelOpensTheTrimOnTheEdge` (giữ → mở, playhead 9,20, chân "Trim · Clip 2" / "0:09.20 · 0 frames", recipe không đổi, lane khoá không mở); `VideoStudioLayoutTests.frameTrimPillAt77x728` (248×48 giữa, cách chân 14 → (77, 728) trên board), `loupeClearsClipBy2pt` (Ø124 ở (154, 280) như board, trượt vào cách mép 8); route `vs-f6-trim-enter.json` iPhone 17 (26.5) 2026-10-08 — chọn clip 1 (ảnh 3,0 s), bước `drag` `hold 0.7` trên tay nắm mép cuối: `build/proofs/fs1217/t6-phone-hold-loupe.png` — panel ẩn, timeline về cao lúc không chọn, kính Ø124 trên mép với 10 dải, pill ‹ −1 Frame · 0:03.00 · +1 Frame ›, chân "Trim · Photo 1" / "0:03.00 · 0 frames" thay hàng 5 công cụ, viewer "Last frame · 0:03.00". Pill ở y 716 thay 728: chân phone nằm ở 778 trên iPhone 17 (inset 34), board vẽ 790 — cùng độ lệch khung đã ghi ở FS-12.06c AC-14 (6); pill vẫn cách chân 14 |
| AC-2 | AC-1 | bấm −1 Frame 4 lần | nhãn "0:09.07 · −4 frames"; Clip 3 vẫn bắt đầu ở 9,20 s; recipe chưa đổi | ✅ `FrameTrimSessionTests.fourFramesEarlier` (mép 9,0667, "0:09.07", "−4 frames" / "−4 f", cửa sổ nguồn 6,2 − 4/30; qua model: recipe `==` lúc vào, Clip 3 vẫn ở 9,20, playhead theo mép, chân "0:09.07 · −4 frames", không bước undo); route `vs-f6-trim-enter.json` iPhone 17 (26.5): bấm −1 Frame ×4 trên pill → "0:02.87 · −4 frames" ở pill và chân, badge clip vẫn 3.0s, tay nắm mép cuối đứng ở mép ảo, phần cắt gạch chéo (`build/proofs/fs1217/t7-phone-minus-four.png`) |
| AC-3 | AC-2 | bấm ✓ | Clip 2 dài 6,067 s (±1 ms), Clip 3 bắt đầu ở 9,067 s; undo thêm đúng 1 bước; Undo một lần trả về 6,2 s | ✅ `VideoStudioFrameTrimTests.commitAddsOneUndo` (6,0667 ±1 ms, Clip 3 ở 9,0667, đúng 1 bước, clip vẫn chọn, Undo → 6,2), `backCommitsFirst` (Back = ✓ rồi rời), `deselectingKeepsTheTrimAndAnUnmovedTrimWritesNothing`; route `vs-f6-trim-commit-cancel.json` iPhone 17 (26.5): −4 frames rồi ✓ → badge clip 2.9s, tổng 0:08.8, Undo bật, panel clip trở lại (`build/proofs/fs1217/t8-phone-after-commit.png`) |
| AC-4 | AC-2 | bấm ✕ | recipe bằng hệt lúc trước khi giữ mép; số bước undo không đổi | ✅ `VideoStudioFrameTrimTests.cancelRestoresAndKeepsUndoDepth` (recipe `==` lúc trước khi giữ, checkpoint và bước mới nhất của lịch sử không đổi, clip vẫn chọn, playhead về mép; ✕ của clip sau đó vẫn gỡ bước tốc độ trước đó); route `vs-f6-trim-commit-cancel.json`: giữ lại mép, −2 frames ("0:02.80 · −2 frames"), ✕ → clip vẫn 2.9s, panel clip trở lại (`build/proofs/fs1217/t9-phone-*.png`) |
| AC-5 | Clip 2 tốc độ 2×, đang trong chế độ ở mép cuối | bấm −1 Frame | mép trên timeline sớm hơn 1/30 s; cửa sổ cắt trong nguồn ngắn đi 2/30 s | ✅ `FrameTrimSessionTests.speedTwoMovesSourceTwice` (mép 6,1 → 6,1 − 1/30; `trimEnd` 6,2 → 6,2 − 2/30; bước nguồn của kính 2/30 — cùng phép quy đổi `VideoEdgeTrimMath.drag` của kéo tay nắm), `projectGridWinsOverSourceRate` (project 24 fps: mép rơi lưới 1/24 — từ 9,2 lệch lưới bước đầu về 220/24 rồi 219/24; kính xin khung nguồn cách 1/24) |
| AC-6 | Clip 1 ảnh 0,5 s, chế độ ở mép cuối | bấm −1 Frame | thời lượng giữ 0,5 s; nút −1 Frame mờ 35%, không nhận chạm | ✅ `FrameTrimSessionTests.photoAtMinimumCannotShorten` (0,5 s: `canStep(-1)` sai, bước không dời, vẫn 0,5; +1 vẫn được; 10 s ngược lại), `videoAtSourceEndCannotLengthen` (cuối nguồn không nới, đầu nguồn không lùi, clip 0,1 s không ngắn hơn; kéo quá biên dừng ở biên, báo `hitLimit` một lần); nút pill đọc `canStep`: mờ 35% + `.disabled` (`VideoFrameTrimPill.stepButton`) — biên là cùng `VideoEdgeTrimMath` của kéo tay nắm |
| AC-7 | iPhone, không chọn gì, zoom 55 pt/giây | pinch ra hết cỡ | zoom dừng ở 360 pt/giây; hiện "Frame zoom · 1 frame = 12 pt"; nhãn thước cách nhau 72pt | ✅ `TimelineZoomMathTests.ceilingIs360At30`, `ceilingIs288At24`, `ceilingIs720At60`, `rulerLabelsEvery72pt` ("8:12f" · "8:18f" · "8:24f" · "9:00f", 72pt); route `vs-f6-frame-zoom.json` iPhone 17 (26.5) 2026-10-08: bước `pinch` theo id `VideoTimeline` (M4 đạt — cây phone không duyệt được nhưng truy vấn `scrollViews` theo id chạy) ×12 → dump `VideoTimeline` giá trị `360`; ảnh `build/proofs/fs1217/t13-phone-frame-zoom.png`: pill 270×26 "Frame zoom · 1 frame = 12 pt", dòng "Drag slowly to step one frame · pinch in to return", thước "0:00f · 0:06f · 0:12f" cách 72; pinch vào ×0,5 → pill mất, thước về giây (`t13-phone-pinched-in.png`). Timeline phone ở bản dựng này thấp hơn board nên pill lên trên (min(276, cao − 66)) |
| AC-8 | AC-7, playhead ở 8,90 s | kéo timeline 36pt sang phải | playhead lùi đúng 3 khung (8,80 s); 3 haptic; huy hiệu "−3 f · 0:08.80"; khung viewer bằng khung nguồn tại 8,80 s | ⚠️ một phần — `TimelineZoomMathTests.drag36ptIsThreeFrames` (360 pt/s: 36pt = 3 khung, 8,90 → 8,80, vượt 3 vạch = 3 haptic, chữ huy hiệu "−3 f · 0:08.80", thả giữa hai khung dừng ở khung gần hơn); ở Frame zoom `scrub(to:exact:)` seek dung sai 0 (khung viewer đúng), haptic mỗi vạch theo công tắc, `scrollViewWillEndDragging` đặt chỗ dừng lên vạch khung; route `vs-f6-frame-scrub.json` iPhone 17 (26.5): giữ ngón khi kéo → huy hiệu 92×18 "−2 f · 0:00.20" trên làn video ngay playhead, thước "0:06f" (`build/proofs/fs1217/t14-phone-frame-scrub-badge.png`) — kéo của driver hụt ~10pt (độ trễ nhận pan, đã ghi ở REVIEW_QUEUE), nên 36pt thành 2 khung; **D5 chưa đo**: đếm haptic trên máy thật |
| AC-9 | "Frame zoom on pinch" tắt | pinch ra hết cỡ | zoom dừng ở 160 pt/giây; không có pill Frame zoom | ✅ `TimelineZoomMathTests.switchOffStopsAt160` (công tắc tắt → trần 160, không ở Frame zoom nên không pill), `pinchStopsAt160WhenFrameZoomOff`, `noFrameZoomStateBelowCeiling`; pinch đọc trần từ `VideoInputPreferences.frameZoomOnPinch` (`VideoTimelineView.zoomCeiling`); công tắc ở mục **Precision** của ⋯ transport (iPhone, Duo ngoài). Lượt UI với công tắc tắt: chưa chạy (hàng trong menu ⋯ của phone không nhận chạm của driver) |
| AC-10 | Duo trong, Clip 2 chọn | giữ mép cuối 0,5 s | 4 ô đầu cột phải: −1 Frame · +1 Frame · Frame Zoom · Trim (bật); không có Split; 5 công cụ hàng đáy không nhận chạm | ⚠️ một phần — `VideoStudioDeskLayoutTests.duoInnerTrimRowOrder` (−1 · +1 · Frame Zoom · Trim rồi Speed … Delete, không Split), `VideoStudioFrameTrimTests.trimCellPicksEdgeNearerPlayhead` (ô Trim mở ở mép gần playhead, ô sáng, chạm lại = ✓, ✕ của chân kết thúc trim trước, clip vẫn chọn), `footersNameTheTrim` ("0:09.07 · −4 f" ở chân hẹp); **bản đứng thay** 951×669 trên iPad Pro 13" (`-VideoStudioStandIn duoInner`, route `vs-f6-trim-duo-inner-standin.json`, 2026-10-08): ô Trim → hàng lệnh −1 Frame 696 · +1 Frame 764 · Frame Zoom 832 · Trim 900 (sáng) · Speed 968… ở y 12, khớp `F6_DI_TouchTrim` ≤ 2pt; cột: Speed · Volume, PRECISION hai công tắc, chú thích; 5 công cụ đáy mờ; chân ✕ 620 · "Trim · Clip 1" / "0:32.23 · −4 f" · ✓ 867 khớp board; nhãn viewer "Last frame · 0:32.23" 24 cao ở (12, 330) như board (`build/proofs/fs1217/t15-duo-inner-standin-trim.png`); **giữ mép trên Duo thật: chưa** — sim boot gập |
| AC-11 | iPad dọc, ô Trim bật | Pencil kéo mép cuối, đứng yên 0,3 s, rồi đi tiếp 24pt sang trái | mép sớm hơn đúng 2 khung; một ngón tay kéo timeline cùng lúc thì cuộn, không cắt | ⚠️ một phần — phép tính: `PencilFrameStepperTests.stillThenTwentyFourPointsIsTwoFrames` (nghỉ 0,3 s rồi 24pt trái = đúng −2 khung, đổi sang điểm timeline theo zoom), `driftOverTwoPointsResetsStillness`; code: pan riêng `allowedTouchTypes = [.pencil]` bắt đầu ngay trên tay nắm khi ô Trim mở phiên trim (không cần giữ 0,5 s), pan cuộn và pan tay nắm chỉ nhận ngón tay khi đó, chạm `majorRadius` > 35 (lòng bàn tay) bị bỏ, `UIHoverGestureRecognizer` (`zOffset` > 0) vẽ vạch 1pt + thời điểm và bật công tắc hover lần đầu máy báo; **D4 chưa đo** — XCUITest không giả được Pencil, cần iPad + Pencil thật |
| AC-12 | iPad dọc, ô Trim bật | chạm đúp Pencil rồi kéo Pencil trên Clip 2 | playhead chạy theo Pencil; cửa sổ cắt Clip 2 không đổi | ⚠️ một phần — `PencilFrameStepperTests.scrubModeMovesPlayheadOnly` (chạm đúp đổi trim ↔ scrub chỉ khi ô Trim mở phiên; ở scrub playhead theo, cửa sổ cắt Clip 2 không đổi; ra khỏi phiên về trim); code: `UIPencilInteraction` (`pencilInteraction(_:didReceiveTap:)` iOS 17.5, `pencilInteractionDidTap` 17.0–17.4), ở scrub pan Pencil không bắt tay nắm và pan cuộn nhận Pencil như ngón tay; chú thích khối Pencil "Double-tap the Pencil to switch between trim and scrub."; **D4 chưa đo** — cần Pencil thật |
| AC-13 | project **mở khi có mạng**, Clip 2 là luồng iCloud (không phải file trên máy), rồi mất mạng | vào chế độ, bấm −1 Frame 2 lần, bấm ✓ | kính vẽ dải xám + "Offline"; không có request mạng; Clip 2 ngắn đi 2 khung | ⚠️ một phần — `VideoEdgeFrameSourceTests.streamingAssetIsOfflineWithoutDecoding` (asset URL không phải file → `isLocal` sai, không gọi generator, không cache), `VideoStudioFrameTrimTests.offlineClipStillTrims` (nguồn không có trên máy → kính offline, không khung nào giải mã; −1 ×2 rồi ✓ vẫn ghi 6,2 − 2/30); kính vẽ 10 dải xám và "Offline" (`VideoFrameTrimLoupe`); composition PhotoKit trên file máy (slow-mo, video đã sửa) vẫn là local (`decodesTheLastFrameAtTheSizeAsked` + iPad dọc); **D7 chưa đo** — luồng iCloud thật, Optimize Storage, xem không có request (máy thật) |
| AC-14 | VoiceOver bật, Clip 2 chọn | focus tay nắm mép cuối, vuốt xuống một lần | đọc "Clip 2 end, 0:09.20"; sau vuốt mép sớm hơn 1 khung, đọc "0:09.17" | ⚠️ một phần — `VideoStudioFrameTrimTests.adjustableDecrementStepsOneFrame` (tên "Clip 2 end", giá trị "0:09.20"; điều chỉnh xuống = `stepClipEdge(−1)`: ghi ngay một bước undo, đọc "0:09.17"; Undo về 9,20; cuối nguồn không nới); dump `vs-f6-edge-handle-a11y-ipad.json` iPad Pro 13" dọc 2026-10-08: hai phần tử riêng cạnh clip — "Clip 1 start" giá trị `0:00.00` và "Clip 1 end" `0:32.34` (12×88, `clipStartHandle` / `clipEndHandle`); **D6 chưa đo**: vuốt VoiceOver thật trên máy (hoặc Accessibility Inspector → Decrement) chưa chạy |
| AC-15 | board F6_P_PreciseTrim, F6_P_FineScrub, F6_DI_TouchTrim, F6_IP_PencilTrim, F6_DC_PreciseTrim | `design-parity` chạy trên từng board | mọi phần tử lệch ≤ 2pt, không thiếu, không thừa | ⚠️ một phần — `Tools/design-board compare` 2026-10-08: **F6_DC_PreciseTrim** (Duo thật, màn ngoài) mọi phần tử đặt tên ≤ 2pt; **F6_DI_TouchTrim** (bản đứng thay 951×669) hàng lệnh, chân, công cụ, nhãn viewer ≤ 2pt — lệch còn lại là nội dung (Show original thay bằng nút trước/sau FS-12.15, loa 44 của hàng Volume chung); **F6_IP_PencilTrim** (iPad Pro 13" dọc) cột, nút, dòng ≤ 2pt, công tắc hệ thống iOS 26 61×28 thay 51×31 của board; **F6_P_PreciseTrim** (iPhone 17, dump nút `vs-f6-trim-phone-parity.json`): −1 / +1 Frame, ✕ · ✓ đúng x, **thấp hơn board 12pt** — hàng đáy phone ở 778 trên iPhone 17 (inset 34), board vẽ 790, cùng độ lệch khung FS-12.06c AC-14 (6); transport khác y vì project mẫu trên sim không phải 16:9; **F6_P_FineScrub**: so bằng mắt (`build/proofs/fs1217/t13-*`) — pill, dòng gợi ý, thước khung đúng mẫu; timeline trên sim thấp hơn board nên pill đứng cao hơn 276 |
| AC-16 | Duo ngoài 466×678, Clip 2 chọn | giữ yên mép cuối Clip 2 0,5 s | panel ẩn, timeline 334–644; pill 248×48 tại (67, 582); ✕ ở y 504, ✓ ở y 556; Export ẩn; không control nào trong dải 84 ở y < 72 hay > 600 | ✅ `VideoStudioDeskGeometryTests.duoCoverFrameTrim` (dải tên 300–334, timeline 334–644, pill (67, 582) 248×48, ✕ 504 · ✓ 556, dải 84 sạch ngoài 72–600); Duo sim thật, màn ngoài, route `vs-f6-trim-duo-cover.json` 2026-10-08: chọn clip 1, vuốt grabber xuống (panel 78 — FS-12.07b AC-12), giữ mép cuối 0,7 s → `sim-shot cover` có kính Ø124 (`build/proofs/fs1217/t17-duo-cover-hold-loupe.png`); −1 Frame ×4 → dump so `F6_DC_PreciseTrim`: mọi phần tử đặt tên ≤ 2pt (chỉ ô chuyển cảnh lệch — nội dung); ảnh `t17-duo-cover-trim.png`: "Trim · Photo 1" / "0:02.87 · −4 frames" đầu vùng timeline, pill, ✕ · ✓ ở dải 84, Export ẩn, 5 công cụ mờ |
| AC-17 | iPad dọc và Duo trong, Clip 2 trong chế độ, đã −4 frames | dump chân / đáy | "Trim · Clip 2" và "0:09.07 · −4 frames" (Duo trong "−4 f"); không có dòng Duration | ✅ `VideoFrameGridTests.compactFrameLabel` ("0:09.07 · −4 frames" / "0:09.07 · −4 f"), `VideoStudioFrameTrimTests.footersNameTheTrim` (chân rộng và hẹp đọc cùng phiên trim); `VideoStudioDeskGeometryTests.portraitTrimColumnsFillTheDock` (4 cột 238 cách 16 ở x 16 · 270 · 524 · 778); dump iPad Pro 13" dọc (`vs-f6-trim-ipad-portrait.json`, 2026-10-08): ô Trim → chân "Trim · Clip 1" / "0:32.34 · 0 frames" 64 ở y 1312, dock 4 cột Trim (Start/End to Playhead 238×44) │ Speed · Volume (không Duration — clip video) │ Pencil │ Precision, `Tools/design-board compare` `F6_IP_PencilTrim`: cột, nút, dòng Speed/presets/Volume ≤ 2pt; công tắc hệ thống iOS 26 61×28 (board 51×31, mép phải trùng); "Hover shows the trim point" ẩn đúng luật (sim chưa báo hover); viewer chiếu khung cuối của clip (`build/proofs/fs1217/t16-ipad-portrait-trim.png`); Duo trong (bản đứng thay): "0:32.23 · −4 f" (AC-10). iPad ngang: các khối xếp dọc trong inspector 360 (code `clipParams`, chưa chụp) |

**Chưa chứng minh được:** cả 17. Toán bước khung (AC-2…6, AC-8) đặt ở Domain, test thuần không cần simulator.

## 13. Rủi ro

| Rủi ro | Xử lý |
|---|---|
| Board iPad kiểu Mac `F6_IP_PencilTrim` ghi nhãn đáy kính "0:09.07 · −4f"; §5 ghi iPad "· −4 frames" | spec giữ "−4 frames" (cùng chữ với chân); **board đã sửa 2026-10-04** |
| Giải mã 10 khung chính xác mỗi lần bấm ±1 trễ quá 100 ms với HEVC 4K | giải mã ở cỡ kính, chỉ thêm 1 khung mới mỗi bước; đo trên máy thật trước khi chốt |
| Timeline ở 360 pt/giây với project 10 phút rộng 216 000pt | thumbnail chỉ dựng ô giao vùng nhìn (±1 ô) — **đã sửa 2026-10-08** (task 13: `ClipFilmstrip.drawnCells`, test `VideoStudioLayoutTests.filmstripBuildsOnlyVisibleCells`); còn đo M6 (bộ nhớ, Instruments) và D2 (60 fps cuộn ở 360–720 pt/giây, project 10 phút, máy thật) theo NF-01 |
| Long-press 0,32 s trên timeline hôm nay là đổi thứ tự clip, và FS-12.11 dùng giữ 0,5 s trên clip để vào chế độ chọn — cả hai tới trước hoặc cùng lúc với tay nắm | vùng chạm của tay nắm không thuộc hai cử chỉ đó; giữ trên **thân** clip vẫn theo [FS-12.11](11-multi-select-and-reorder.md) |
