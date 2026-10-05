# FS-12.12 — Nhịp nhạc: tìm nhịp, bắt nhịp, Cut to Beat

`FS-12.12` · tier D · `Domain/Video/` (lưới nhịp, toán dời cut — mới) · `Data/Sources/` (phân tích nhịp — mới, giải mã như
`Features/VideoStudio/VideoWaveform.swift`) · `Data/Sources/ImportedMusicStore.swift` · nguồn intent
[video-studio-canvas-chrome](../../_intents/2026-10-03-video-studio-canvas-chrome.md) F2 · cập nhật 2026-10-04 (iPad kiểu Mac)

**Một câu:** app tự tìm nhịp của bản nhạc ngay trên máy, vẽ vạch nhịp lên timeline, cho mép clip và thời lượng
dính vào nhịp, và dời mọi cut về ô nhịp gần nhất trong một bước undo.

Snapping chung, tay nắm mép clip, Trim to Playhead: [FS-12.05](05-cutting-markers-and-fades.md). Cắt từng khung:
[FS-12.17](17-precise-trim-and-input.md). Hàng lệnh nhạc, Beats là lệnh kiểu *mục*: [FS-12.04b](04b-command-rows.md).
Nhạc từ đâu: [FS-12.08 §3](08-model-and-v1-limits.md).

## 1. Người dùng cần gì

Reel du lịch đẹp khi hình đổi đúng phách nhạc. Hôm nay phải nghe, đoán, kéo từng mép clip tới chỗ "chắc là
phách", rồi nghe lại. Hôm nay code **chưa có** phát hiện nhịp nào.

## 2. Phạm vi

**Có:** phát hiện BPM và vị trí từng nhịp trên máy (AVFoundation giải mã, Accelerate tính); vạch nhịp trên băng
nhạc và dải tổng quan; **Snap to beats** theo **Every Beat · Every Bar**; Offset; Cut to Beat theo **Every Bar ·
2 Bars · 4 Bars** có xem trước.

**Cố ý không có:**
- Gửi nhạc lên máy chủ để phân tích — nhạc là file riêng của người dùng, và luật app là không mạng cho việc này.
- Nhịp khác 4/4 (3/4, 6/8) — **luôn coi là 4/4**; Offset sửa được phách lệch, không sửa được số phách mỗi ô.
- Gõ tay BPM, sửa từng vạch nhịp — một Offset cho cả lưới là đủ cho clip ngắn.
- Tự cắt video theo nhịp khi chèn media — Cut to Beat là lệnh người dùng chủ động bấm.

## 3. Màn hình (canvas Video Studio, hàng F2)

| Máy · board | Bố cục |
|---|---|
| iPhone · `F2_P_BeatDetect` | chọn băng nhạc: lát timeline 96 + dải tổng quan 28 tại y 422, panel 340 tại y 450; hàng lệnh nhạc **Beats · Ducking · Replace · Add Track · Duplicate · Delete**, Beats sáng; thẻ nhịp (đĩa 34 vàng mờ, "96 BPM · 4/4", "30 beats marked on A1 · found on this iPhone"); **Snap clips to beats** 42 + công tắc 42×26; **SNAP TO** Every Beat · Every Bar 30; **Offset** 40 "0 ms"; nút **Cut Clips to Beat** 44 bo `r-md`; chú thích "Moves every cut to the nearest bar. Photos stretch, videos trim. One undo."; **LEVEL** 370×8; đáy ✕ · "Morning Drive" / "Music · 96 BPM" · ✓ |
| iPhone · `F2_P_BeatDuration` | chọn **clip ảnh** (clip 4 · Night): slider **Duration** 46 có vạch nhịp 1×18 vàng 0,45 trên rãnh, vạch đang dính 0,95; núm vàng 18 viền quầng 3pt; giá trị vàng "3.30s"; dòng "Ends on beat 28 · 0:17.50 · hold to move freely"; đáy "Clip 4 · Night" / "3.30s · on beat 28". Clip video không có Duration ([05 §3](05-cutting-markers-and-fades.md)) — board vẽ lại cho clip ảnh |
| iPad ngang · `F2_IL_BeatSnap` (kiểu Mac 2026-10-04) | kéo tay nắm mép phải clip 2: đường dọc vàng 1,5pt cao hết vùng lane, pill vàng **206×26** "Beat 14 · 0:08.75 · −0.45s" chữ tối trên thước; inspector 360: ô **Trim** sáng, **không** có dòng Duration (clip video), Speed · Volume, rồi mục **Beats · A1 Morning Drive** ("96 BPM · 4/4 detected", Snap to beats công tắc 51×31, **Snap To** segmented Every Beat · Every Bar 328×36, Offset slider 44); chân 64 dòng phụ "5.75s · on beat 14" |
| Duo trong · `F2_DI_CutToBeat` | cột 264 ở trạng thái xem trước: **CUT TO BEAT**, chip Every Bar · 2 Bars · 4 Bars, "4 cuts move · largest +0.8s", "Photos stretch, videos trim", Snap to beats, Offset, nút trắng **Apply to 5 Clips** 40; lane V1 có mũi tên vàng từ mỗi cut tới ô nhịp đích + pill 40×16 "−0.5s" / "+0.8s"; đáy phải ✕ · "Morning Drive" / "96 BPM" · ✓ |
| Duo ngoài · `F2_DC_Beats` | không có timeline: dải tổng quan 358×22 tại y 306 mang vạch nhịp; panel 382×344 tại y 334: thẻ nhịp "Morning Drive · 96 BPM" / "30 beats marked on A1", Snap 40, chip, **Cut Clips to Beat** 40, chú thích ngắn "Every cut moves to the nearest bar. One undo."; Offset và LEVEL nằm dưới, cuộn panel tới |

- **Vạch nhịp trên băng nhạc:** ô nhịp (bar) = vạch 2×12 + ô vuông 6×6 trên đầu; nhịp thường = vạch 1×7 vàng 0,7.
  Trên dải tổng quan: bar 1×8, nhịp 1×5 vàng 0,55. Hai nhịp cách nhau dưới 6pt thì chỉ vẽ bar — dày hơn là thành vệt.
- Vạch hiện khi **Snap clips to beats** bật, hoặc khi tab Beats đang mở.
- **Màu nhịp là token `timelineBeat` #FFD60A** (đúng vàng hệ thống bản tối), chữ trên nó **#1A1500** — chỉ Video
  Studio, chỉ cho vạch, pill, núm và mũi tên nhịp (chốt 2026-10-03). Accent #EB9526 vẫn chỉ ở Export; cyan #57BFD1
  vẫn chỉ là "đang chọn".
- **DESIGN.md §3.3** có hai token chỉ cho Video Studio (thêm 2026-10-05, task 22 của plan): `timelineBeat` #FFD60A
  (chữ `timelineBeatInk` #1A1500) và `timelineSpeech` #5E9CFF (chữ `timelineSpeechInk` #06142E, [13](13-audio-ducking.md),
  [14](14-captions.md)), cùng trong `EditorTheme`.

## 4. Tìm nhịp

- **Khi nào:** lần đầu mở tab Beats của một băng, hoặc lần đầu bật Snap, nếu file đó chưa có kết quả. Chạy nền,
  không chặn UI; đóng tab vẫn chạy tiếp; xoá băng hoặc đóng studio thì huỷ trong ≤ 1 s.
- **Cách:** giải mã mono 11 025 Hz; độ mạnh khởi âm theo khung ~23 ms; tempo từ tự tương quan trong **60–180 BPM**;
  vị trí từng nhịp bám lưới cho phép trôi ±5% (nhạc thu sống không giữ tempo tuyệt đối); phách 1 của ô nhịp là pha
  có năng lượng trầm mạnh nhất trong 4 pha.
- **Đánh số** theo board: nhịp đầu của bản nhạc trên timeline là số 0 (96 BPM bắt đầu 0,0 s → Beat 14 = 8,75 s); chỉ
  đếm nhịp nằm trong cửa sổ trim của băng ("30 beats marked on A1" cho 18,4 s).
- **Trạng thái thẻ nhịp:** đang tìm "Finding beats…" + vòng quay trong đĩa 34; xong như board; tự tương quan quá
  yếu → "No steady beat" / "Snap needs music with a clear beat", công tắc Snap và Cut mờ 0,28; file không đọc được →
  "Can't read this track".
- Kết quả là **dữ liệu suy ra**: cache theo file nhạc (tên + kích thước + ngày sửa) trong thư mục Caches, không vào
  recipe. Mất cache thì tìm lại; kết quả giống hệt vì thuật toán tất định.

## 5. Bắt nhịp

- **Một nguồn nhịp mỗi project:** bật Snap trên A2 thì A1 tự tắt. *Vì* hai lưới khác tempo làm điểm dính mơ hồ.
- **SNAP TO:** Every Beat = mọi nhịp; Every Bar = chỉ phách 1. **Offset** −250…+250 ms, bước 5 ms, nấc giữa ở 0,
  dời cả lưới: vạch, điểm dính và Cut to Beat.
- **Cái gì dính:** mép clip khi kéo tay nắm; slider Duration của ảnh và khung freeze (video không có Duration — mép
  video dính qua tay nắm); mép chữ và sticker khi kéo (thêm vào danh sách điểm dính có sẵn của FS-12.05 §5). Băng nhạc nguồn **không** dính vào nhịp
  của chính nó.
- Ngưỡng **8pt ngón tay** quy ra giây theo zoom, như snapping hiện có; trên slider là 8pt trên rãnh. Dính thì rung
  nhẹ một lần, núm và giá trị đổi vàng.
- **"hold to move freely"** (slider): dừng ngón 0,5 s giữa lúc kéo thì tắt dính tới khi nhấc tay.
- **Tay nắm mép:** kéo ngay thì dính nhịp; giữ yên trước khi kéo là vào chế độ cắt từng khung của FS-12.17, ở đó
  **không** dính nhịp. *Vì* chế độ đó sinh ra để đặt mép giữa hai nhịp.

## 6. Cut to Beat

- Chạm **Cut Clips to Beat** (iPhone, Duo ngoài) mở trạng thái xem trước trong panel; Duo trong và iPad vẽ nó ngay
  trong cột. *Vì* dời bốn cut cùng lúc mà không thấy trước là bất ngờ, và board Duo trong vẽ bước xem trước.
- **Đích của mỗi cut** = ô nhịp gần nhất (Every Bar · 2 Bars · 4 Bars) tính từ vị trí **hiện tại** của cut; cut có
  chuyển cảnh lấy điểm giữa vùng chồng. Cut đã nằm trên đích (≤ 1 khung) không tính là "move".
- **Cách đạt đích:** ảnh co giãn thời lượng; video dời cuối trim. Đích cần thêm hình mà nguồn video không còn, hoặc
  làm ảnh dưới 0,5 s → cut đó **đứng yên** và dòng tóm tắt thêm "· 1 can't move". *Vì* nhảy sang nhịp xa hơn là
  cắt đi hình người dùng chọn.
- **Xem trước:** mũi tên vàng 2pt từ cut tới đích + vạch đứt 2×74 tại đích + pill độ dời. iPhone: lát timeline
  cuộn tới lane V1. Duo ngoài (không có timeline): mỗi đích là vạch vàng 2pt trên dải tổng quan.
- **Apply to N Clips** = một bước undo cho mọi thời lượng. Rời xem trước (chạm ô lệnh khác, ✕, đổi chọn) = không đổi gì.

## 7. Dữ liệu

| | |
|---|---|
| Ghi vào recipe (mỗi băng nhạc) | Snap bật/tắt · Every Beat/Every Bar · Offset ms — thiếu khoá thì mặc định tắt, Every Beat, 0 |
| Không ghi | BPM, vị trí nhịp — cache theo file (§4) |
| Đọc dữ liệu cũ | thiếu khoá hay khoá hỏng thì về mặc định, không làm hỏng cả project (đọc khoan dung) |
| Người dùng tự nhập? | có → recipe ở bảng `creations`, không đụng `photo_metadata` |

## 8. Đường hỏng

| Tình huống | Hành vi |
|---|---|
| Không mạng, máy bay | chạy bình thường — nhạc đã nằm trong app, phân tích không gọi mạng |
| Quyền `.limited`, ảnh iCloud | không áp dụng cho việc tìm nhịp; Cut to Beat chỉ sửa recipe |
| Hết bộ nhớ đĩa | cache không ghi được thì vẫn dùng kết quả trong RAM cho phiên này |
| Huỷ giữa chừng | xoá băng / đóng studio huỷ phân tích; không để file tạm |
| Undo | Snap, SNAP TO, Offset (một lần kéo), Apply mỗi thứ một bước |

## 9. Tiêu chí nghiệm thu

Project mẫu: 5 clip 3.0s ảnh · 6.2s video (nguồn 10 s, trim 0–6,2) · 5.0s video · 3.0s ảnh · 6.8s video, cắt thẳng;
"Morning Drive" 96 BPM đặt 0,0–18,4 s trên A1. File thử nhịp là click tổng hợp trong test — không dùng nhạc có bản quyền.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | click 30 s, 96 BPM, 4/4, phách 1 to gấp đôi, bắt đầu 0,0 s | phân tích | BPM 96 ±0,5; mọi nhịp lệch ≤ 20 ms; nhịp 0, 4, 8… là phách 1 | ✅ `BeatDetectorTests.click96BarAccented` (click tổng hợp 30 s trong test: 96,0 BPM, 48 nhịp, mọi nhịp lệch ≤ 1 ms so với click — AC cho 20 ms — phách 1 ở nhịp 0, 4, 8…), `click170NotHalved` (170, không 85), `click60NotDoubled` (60, không 120); `BeatDetector` ở Domain, Accelerate (khung 256 / bước 128, tự tương quan 60–180 BPM chọn đỉnh nhanh hơn khi hai đỉnh gần bằng, lập trình động trôi ±5 %, mỗi nhịp ghim vào khởi âm tới mili-giây, phách 1 = pha mạnh nhất dưới 200 Hz) |
| AC-2 | click 120 BPM, 0,37 s im lặng ở đầu | phân tích | nhịp đầu ở 0,37 ±0,02 s; BPM 120 ±0,5 | ✅ `BeatDetectorTests.leadingSilenceShiftsFirstBeat` (120 BPM sau 0,37 s im lặng: nhịp đầu 0,3696 s, 120,0 BPM; không nhịp nào bịa trong khoảng lặng — hai đầu không có khởi âm bị bỏ) |
| AC-3 | 30 s tiếng ồn trắng | phân tích | thẻ "No steady beat"; Snap và Cut Clips to Beat mờ 0,28; không vạch nào | ✅ `BeatDetectorTests.whiteNoiseHasNoSteadyBeat` (ồn trắng 30 s, độ tin cậy dưới ngưỡng 0,3, không nhịp), `VideoBeatsModelTests.unreadableFileShowsCantRead` (file hỏng → "Can't read this track", ồn → "No steady beat", không lưới), `foundBeatsAreNotFoundTwice`; route `video-beats-ipad.json` (iPad 13", "White Noise" từ `Tools/video-fixtures`): thẻ "No steady beat" / "Snap needs music with a clear beat", không vạch trên băng (`build/proofs/fs1212/t23-ipad-no-steady-beat.png`); dump cùng trạng thái: Snap clips to beats, Snap To, Offset, Cut to Beat đều `isEnabled` = false (vẽ mờ 0,28) |
| AC-4 | project mẫu, iPhone, zoom 55 pt/s | mở tab Beats của A1 | thẻ "96 BPM · 4/4" / "30 beats marked on A1 · found on this iPhone"; vạch bar cách nhau 137,5 ±1pt, nhịp 34,4 ±1pt | ✅ (logic + iPad) `BeatGridTests.ticksAt55pps` (30 nhịp trong 0–18,4 s, bar cách 137,5pt và nhịp 34,375pt ở 55 pt/s, nhịp 14 ở 8,75 s, phách 1 ở 0, 4, 8…; "30 beats marked on A1 · found on this iPhone", "96 BPM · 4/4"), `placementAndTrimShiftTheGrid`, `denseBeatsDrawOnlyBars` (dưới 6pt chỉ vẽ bar); `MusicBeatAnalyzerTests.decodesWavAndCaches` (WAV 44,1 kHz viết trong test → 96 BPM; lần hai từ cache, giống hệt), `cacheReadsBackFromDisk`; route `video-beats-ipad.json` (iPad 13", "Morning Drive" từ `Tools/video-fixtures music`): ô Beats sáng, thẻ "96 BPM · 4/4" / "39 beats marked on A1 · found on this iPad" (băng dài theo video 24 s), vạch bar + nhịp vàng trên băng nhạc và dải tổng quan (`build/proofs/fs1212/t22-ipad-beats-found.png`). Ảnh iPhone 55 pt/s chưa chụp (khung phone đen trên sim 27.0, chỉ chrome) |
| AC-5 | Snap bật, Every Beat; clip 4 (ảnh Night) bắt đầu 14,2 s, dài 3,0 s; iPhone | kéo Duration tới 3.25s | giá trị dính **3.30s** (cuối = 17,5 s = beat 28); núm và số vàng; dòng "Ends on beat 28 · 0:17.50 · hold to move freely"; rung 1 lần | ✅ `BeatGridTests.durationSnapsToBeat28` (3,25 → **3,30**, nhịp 28 ở 17,5 s; dòng "Ends on beat 28 · 0:17.50 · hold to move freely"), `VideoBeatSnapTests.snapOnA2TurnsA1Off` (một nguồn nhịp mỗi project, một bước undo); route `video-beat-snap-ipad.json` (iPad 13", Morning Drive, Snap bật): kéo Duration của ảnh 4 → giá trị vàng **3.30s** hai chữ số, núm vàng có quầng, vạch nhịp trên rãnh, dòng "Ends on beat 28 · 0:17.50…", chân "3.30s · on beat 28" (`build/proofs/fs1212/t24-ipad-duration-on-beat-28.png`). Rung một lần: chỉ khi nhịp dính đổi (`VideoBeatSlider`), sim không cảm được |
| AC-6 | như AC-5 | dừng ngón 0,5 s rồi kéo tới 3.25s | giá trị 3.25s, núm trắng, không rung | ✅ (logic) `BeatSliderLogicTests.holdHalfSecondReleasesSnap` (dừng 0,6 s dưới 2pt rồi kéo tiếp → tự do tới khi nhấc; kéo tới 3,25 s giữ 3,25 s, không dính, không rung), `aSteadyDragKeepsSnapping` (kéo liền hay dừng dưới 0,5 s vẫn dính); luật nằm ở `BeatSliderHold` (Domain) mà `VideoBeatSlider` gọi mỗi lần di. Trên sim chưa có ảnh: bước `drag` của driver chỉ giữ ở **cuối** cú kéo, không dừng giữa chừng được |
| AC-7 | iPad 70 pt/s, Snap bật Every Beat, clip 2 (video) cuối ở 9,2 s | kéo tay nắm phải về tới cách 8,75 s dưới 8pt | cuối clip 2 = 8,75 s; pill "Beat 14 · 0:08.75 · −0.45s"; đường vàng hết vùng lane; dòng phụ chân inspector "5.75s · on beat 14"; không có dòng Duration | ✅ `TimelineSnappingTests.edgeSnapsToBeat14At70pps` (8pt = 0,114 s ở 70 pt/s: kéo tới 8,8 dính nhịp 14 ở 8,75, không dính mép nào; pill "Beat 14 · 0:08.75 · −0.45s"), `preciseTrimIgnoresBeats` (hỏi không kèm nhịp → không dính — chế độ cắt từng khung FS-12.17 chưa có, nó sẽ gọi đường này), `VideoEdgeBeatSnapTests.edgeDragStopsOnBeat14` (WAV 96 BPM giải mã thật; preview mang nhịp 14, chân "5.75s · on beat 14", thả → clip 2 dài 5,75 s); route `video-beat-snap-ipad.json` (iPad 13", Fit 48,7 pt/s): kéo tay nắm phải clip 2 → pill vàng 206×26 trên thước, đường vàng 1,5pt hết các lane, chân inspector "5.75s · on beat 14", clip video không có dòng Duration (`build/proofs/fs1212/t27-ipad-edge-on-beat-14.png`). Mép chữ/sticker: dính nhịp qua cùng `snappedTime` lúc thả |
| AC-8 | như AC-7 nhưng Every Bar | kéo tay nắm tới 8,75 s | không dính 8,75; chỉ dính 7,5 hoặc 10,0 khi trong 8pt | ✅ `TimelineSnappingTests.everyBarSkipsOffbeats` (Every Bar: 8,75 không dính; 7,5 — bar 12 — và 10,0 dính trong 8pt), `VideoBeatDivisionTests.everyBarIsOneStep`; route `video-beats-ipad.json` (iPad 13"): Snap bật, SNAP TO "Every Beat · Every Bar", Every Bar sáng, Offset "0 ms" dưới nó (`build/proofs/fs1212/t28-ipad-snap-every-bar.png`) |
| AC-9 | Snap bật | kéo Offset tới +50 ms một lần | mọi vạch và điểm dính dời +0,05 s; một Undo về 0 ms | ✅ `BeatGridTests.offsetShiftsEveryBeat` (+50 ms dời mọi vạch, và mọi điểm dính, đúng 0,05 s; "+50 ms", "0 ms"), `VideoBeatOffsetTests.offsetDragIsOneUndo` (một lần kéo tới +50 = một bước, Undo về 0; bước 5 ms, kẹp ±250); thanh Offset có nấc ở 0 trong tab Beats, mờ 0,28 khi không có nhịp |
| AC-10 | project mẫu, Every Bar | mở xem trước Cut to Beat | "4 cuts move · largest +0.8s"; độ dời −0.5 · +0.8 · +0.8 · +0.3 s; recipe chưa đổi | ✅ `CutToBeatMathTests.previewSampleProject` (đích 2,5 · 10,0 · 15,0 · 17,5; dời −0.5 · +0.8 · +0.8 · +0.3; "4 cuts move · largest +0.8s"; độ dài các clip không đổi), `widerSpacingsUseFewerBars` (2 Bars, 4 Bars); route `video-beats-ipad.json` (iPad 13", xem trước ngay trong inspector): Cut to Beat · Every Bar · 2 Bars · 4 Bars, mũi tên vàng + vạch đứt + pill "−0.5s" trên lane V1 (`build/proofs/fs1212/t29-ipad-cut-to-beat-preview.png`) — media mẫu trên sim có nguồn đúng bằng độ dài clip nên ở đó là "2 cuts move · largest −0.5s · 2 can't move" |
| AC-11 | như AC-10 | Apply to 5 Clips | clip 1 = 2,5 s, clip 2 = 7,5 s (trim 0–7,5), clip 3 = 5,0 s, clip 4 = 2,5 s, clip 5 bắt đầu 17,5 s; một Undo trả cả 5 | ✅ `CutToBeatMathTests.applyStretchesPhotosTrimsVideos` (2,5 · 7,5 trim 0–7,5 · 5,0 · 2,5; clip 5 bắt đầu 17,5), `VideoCutToBeatModelTests.applyIsOneUndo` (WAV 96 BPM giải mã thật; Apply một bước, một Undo trả cả 5); route `video-beats-ipad.json`: "Apply to 5 Clips" → ảnh 0–2,5 · video 2,5–8,7 · video 8,7–13,7 · ảnh 13,7–17,5, Undo bật |
| AC-12 | như AC-10 nhưng clip 2 nguồn chỉ 6,2 s | mở xem trước | cut 9,2 s đứng yên; tóm tắt "3 cuts move · largest +0.8s · 1 can't move" | ✅ `CutToBeatMathTests.shortSourceCutStays` (nguồn clip 2 chỉ 6,2 s: cut 9,2 không tới được 10,0, clip 2 giữ 6,2 s; "3 cuts move · largest +0.8s · 1 can't move") |
| AC-13 | đang xem trước như AC-10 | chạm ô Ducking | recipe và số bước undo không đổi | ✅ `VideoCutToBeatModelTests.leavingPreviewChangesNothing` (đang xem trước, chạm một ô lệnh khác hoặc ✕ → xem trước đóng, recipe và Undo y nguyên). Ô Ducking chưa dựng (FS-12.13) — test dùng ô Volume, cùng một đường `toggleItemSection` |
| AC-14 | bài 3:24 m4a 44,1 kHz, máy thật iPhone 17, chế độ máy bay | mở tab Beats | xong ≤ 5 s; bộ nhớ tăng ≤ 30 MB; không request mạng; xoá băng giữa chừng thì dừng ≤ 1 s | ⚠️ chưa có trên máy thật — **số đo sim** (iPhone 17, iOS 27.0, 2026-10-05): bài click 3:24 112 BPM viết làm WAV 44,1 kHz trong test → giải mã + tìm nhịp **0,56 s**, 381 nhịp, 112,0 BPM (`MusicBeatAnalyzerTests.longTrackTimeOnTheSimulator`); huỷ giữa chừng dừng < 1 s (`cancelStopsWithinOneSecond`); không có lời gọi mạng nào trên đường này (đọc file cục bộ qua `AudioPCMReader`). Bộ nhớ: PCM mono 11 025 Hz của 3:24 là ~9 MB Float giữ một lúc trong `BeatDetector.analyze`, cộng hai đường khởi âm ~17 k Float — chưa đo đỉnh bằng Instruments. Còn lại cho máy thật iPhone 17: m4a thật, chế độ máy bay, ≤ 5 s, ≤ 30 MB |
| AC-15 | iPhone · iPad · Duo trong · Duo ngoài, project mẫu | dựng đúng trạng thái từng board | khớp `F2_P_BeatDetect`, `F2_P_BeatDuration`, `F2_IL_BeatSnap`, `F2_DI_CutToBeat`, `F2_DC_Beats` lệch ≤ 2pt | ⚠️ chưa có — agent `design-parity` |

| AC-16 | mọi trạng thái của AC-4 → AC-12 | `design-reviewer` đọc màu vạch, pill, núm, mũi tên nhịp | đều là `timelineBeat` #FFD60A, chữ trên pill #1A1500; không chỗ nào dùng #EB9526 hay #57BFD1 cho nhịp | ⚠️ chưa có — agent `design-reviewer` |

**Chưa chứng minh được:** AC-14 tới AC-16.

## 10. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Tempo bắt nhầm gấp đôi / một nửa (192 hoặc 48) | khoá dải 60–180; AC-1, AC-2 kèm thêm click 170 BPM khi viết test |
| Nhạc tự do (ambient, field recording) cho lưới giả | ngưỡng độ tin cậy → "No steady beat" thay vì vẽ lưới sai (AC-3) |
| Cut to Beat kéo dài video tới phần người dùng đã cắt bỏ | chỉ dời cuối trim; dòng "Photos stretch, videos trim" nói trước; một Undo |
