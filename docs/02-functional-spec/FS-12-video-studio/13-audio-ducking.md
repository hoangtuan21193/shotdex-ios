# FS-12.13 — Tự hạ nhạc khi có tiếng người

`FS-12.13` · tier D · `Data/Sources/VideoCompositionBuilder.swift` (audio mix) · `Domain/Video/VideoTimelineMath.swift`
(đường âm lượng nhạc) · `Features/VideoStudio/VideoAudioEnvelope.swift` (đọc âm thanh clip) · nguồn intent
[video-studio-canvas-chrome](../../_intents/2026-10-03-video-studio-canvas-chrome.md) F3 · cập nhật 2026-10-04 (iPad kiểu Mac)

**Một câu:** một băng nhạc tự hạ xuống một lượng dB trong lúc clip có tiếng người (hoặc có tiếng bất kỳ), rồi tự
lên lại — không phải vẽ tay đường âm lượng.

Nhạc nhiều băng, fade nhạc: [FS-12.02](02-editing-capabilities.md), [FS-12.08](08-model-and-v1-limits.md). Một đường
dựng cho preview và export: [FS-12.01](01-render-and-export-pipeline.md). Hàng lệnh nhạc, Ducking là lệnh kiểu *mục*,
nút loa: [FS-12.04b](04b-command-rows.md).

## 1. Người dùng cần gì

Reel có đoạn người kể chuyện vào máy, có đoạn chỉ cảnh. Để nhạc đủ to cho đoạn cảnh thì lời nói bị nhạc lấp; để
nhạc nhỏ thì đoạn cảnh nhạt. Hôm nay mỗi băng nhạc chỉ có một âm lượng và fade hai đầu — code **chưa có** ducking.

## 2. Phạm vi

**Có:** công tắc **UNDER VOICES** cho từng băng nhạc; **Amount**, **Duck in**, **Recover**; nguồn kích hoạt
**Voices** hoặc **Any Clip Sound**; đồ thị cả phim (iPhone, Duo ngoài); nhãn **Voice** trên lane V1 (iPad, Duo trong).

**Cố ý không có:**
- Hạ âm thanh clip dưới nhạc (ngược chiều) — "Only the music moves. Each clip keeps its own level."
- Vẽ tay keyframe âm lượng — ducking là luật, không phải đường tự do.
- Nhận dạng giọng qua mạng — phân tích chạy trên máy (SoundAnalysis có sẵn lớp "speech").
- Tách giọng khỏi nhạc trong cùng một clip (clip quay có nhạc nền) — clip được coi như một nguồn.

## 3. Màn hình (canvas Video Studio, hàng F3)

Lối vào: chọn băng nhạc → ô **Ducking** trong hàng lệnh nhạc (Beats · **Ducking** · Replace · Add Track · Duplicate · Delete).

| Máy · board | Bố cục tab Ducking |
|---|---|
| iPhone · `F3_P_Ducking` | panel 340 tại y 450: **đồ thị 370×78**, chú giải (ô xanh 10×8 "Voices" · vạch trắng 12×2 "Music level"), UNDER VOICES 38 + công tắc, Amount 40 "−12 dB", Duck in 36 "0.3s", Recover 36 "0.8s", chip **Voices · Any Clip Sound** 28, dòng "Voices in 3 clips · 8.6s" 36, Volume 40 "80" (cuộn tới); đáy ✕ · "Morning Drive" / "Music · 0.0 → 18.4s" · ✓ |
| iPad ngang · `F3_IL_Ducking` (kiểu Mac 2026-10-04) | inspector 360: hàng lệnh y 80 (Beats · Ducking · Replace · Add Track · Duplicate …), **Level** "−9 dB" + thanh 328, Volume "80" (đĩa loa 40), **Under Voices** công tắc 51×31, Amount · Duck in · Recover (slider 44), **Duck Under** segmented Voices · Any Clip Sound 328×36, dòng tóm tắt "Voices in 3 clips · 8.6s", chú thích "Only the music moves. Each clip keeps its own level.", Fade (Fade in 1.5s · Fade out 2.0s) cuộn tới; chân 64 "Morning Drive" / "Music · 18.4s"; pool bên trái mở tab Music |
| Duo trong · `F3_DI_Ducking` | cột 264: Volume 36, UNDER VOICES 38, Amount 40, Duck in 36, Recover 36, chip, dòng tóm tắt; đáy phải ✕ · "Morning Drive" · ✓ |
| Duo ngoài · `F3_DC_Ducking` | không timeline; panel 382×344 tại y 334: đồ thị **354×78**, UNDER VOICES, Amount, Duck in, Recover; chip và tóm tắt cuộn tới; dải 84: "Morning Drive" / "Music" |

- **Đồ thị** trải cả phim theo chiều ngang: nhãn "A1 · music" 9,5pt mờ góc trên trái; hộp băng nhạc trắng 0,05 cao 50;
  **đường mức nhạc** trắng 1,6pt, chỗ lõm tô xanh 0,3 bên dưới, nhãn "−12 dB" ở đáy chỗ lõm; dải clip cao 8 ở đáy
  (clip xám 0,2, đoạn có giọng xanh); playhead đỏ 2pt (`clipping`). Lõm 26pt ở −12 dB, tỉ lệ thẳng theo dB, kẹp ở đáy hộp.
- **Trên timeline:** băng nhạc vẽ cùng đường mức trắng + pill "−12 dB" 60×16 nền đen 0,7. iPad và Duo trong vẽ thêm
  nhãn **Voice** (cao 16 / 14, chữ tối) ở mép dưới lane V1 trên mỗi đoạn có giọng. Đường mức hiện khi ducking bật;
  nhãn Voice, phần tô xanh và pill chỉ hiện khi tab Ducking đang mở.
- **Xanh giọng là token `timelineSpeech` #5E9CFF**, chữ trên nó **#06142E** — **một** token cho đoạn có giọng ở đây
  và cho phụ đề ở [14](14-captions.md); chỉ Video Studio (chốt 2026-10-03). Cyan `timelineSelection` #57BFD1 vẫn chỉ là
  "đang chọn". Đề xuất token cho DESIGN.md §3.3: [12 §3](12-beats.md).

## 4. Hành vi

- **Mặc định tắt** với băng mới. *Vì* nhạc tự đổi mức khi người dùng chưa hỏi là bất ngờ.
- **Amount** −3…−24 dB, bước 1 dB, mặc định −12. **Duck in** 0,1–1,0 s, mặc định 0,3. **Recover** 0,2–2,0 s, mặc định 0,8.
- **Đường mức:** nhạc bắt đầu hạ **Duck in giây trước** khi giọng bắt đầu và chạm đáy đúng lúc giọng vào (dựng offline
  nên nhìn trước được); giữ đáy tới hết giọng; lên lại trong **Recover** giây.
- Khoảng lặng giữa hai đoạn giọng ngắn hơn Duck in + Recover thì **giữ đáy**, không lên rồi xuống. *Vì* nhạc nhấp
  nhô giữa hai câu nghe như lỗi.
- **Cộng dồn:** mức nhạc = Volume băng × fade băng × ducking (không có Master — [04 §2](04-tools-and-inspector.md)).
  Ducking chỉ hạ, không bao giờ nâng.
- **Voices:** đoạn được lớp "speech" của bộ phân loại trên máy nhận, cửa sổ ~1 s chồng 50% (độ phân giải ~0,5 s),
  bỏ đoạn ngắn hơn 0,3 s. **Any Clip Sound:** mức RMS cửa sổ 50 ms trên −40 dBFS sau âm lượng clip.
- **Clip không kích hoạt:** clip ảnh / freeze, clip tắt tiếng, clip âm lượng 0, lane V1 tắt tiếng, Video sound 0.
- **Thời gian:** phân tích theo giây nguồn của clip, quy ra timeline qua trim và tốc độ mỗi lần dựng. Đổi thứ tự,
  trim, tốc độ **không** phân tích lại.
- **Mỗi băng nhạc** có công tắc và thông số riêng; A1 và A2 cùng bật thì mỗi băng hạ theo luật của nó.
- **Một đường dựng:** ducking là thêm đoạn dốc âm lượng vào audio mix chung của preview và export. Đổi thông số chỉ
  dựng lại tầng âm thanh — không dựng lại khung hình, playback không ngắt.
- **Phân tích chạy khi** mở tab Ducking hoặc bật công tắc, nền, có thể huỷ. Trong lúc chạy: đồ thị hiện đường phẳng
  và dòng tóm tắt "Listening for voices…". Không có giọng: "No voices in clip sound". Với **Any Clip Sound** dòng tóm tắt
  là "Sound in 3 clips · 9.4s" / "No sound in the clips" (chốt khi làm, 2026-10-05).
- **Code:** `Domain/Video/DuckingMath.swift` (kích hoạt, gộp, mức, dốc), `Data/Sources/VoiceActivityAnalyzer.swift`
  (SoundAnalysis + RMS 50 ms ở 16 kHz), `ClipSoundAnalyzer` trong `AudioAnalysisCache.swift` (cache theo asset, chỉ đọc phần
  mới), `Features/VideoStudio/VideoDuckingModel.swift`, `VideoDuckingPanel.swift` (panel + đồ thị),
  `VideoTimelineTracks.swift` (`DuckingLaneLine`, nhãn Voice), `VideoCompositionBuilder.audioMix(…activity:)`.
- **Kết quả là dữ liệu suy ra:** cache theo asset trong thư mục Caches, chỉ phần nguồn đang dùng; trim rộng ra thì
  phân tích phần mới. Không vào recipe.

## 5. Dữ liệu

| | |
|---|---|
| Ghi vào recipe (mỗi băng nhạc) | bật/tắt · Amount dB · Duck in s · Recover s · Voices/Any Clip Sound — thiếu khoá thì về mặc định §4 |
| Không ghi | đoạn có giọng — cache theo asset |
| Đọc dữ liệu cũ | khoá thiếu hay hỏng về mặc định, không làm hỏng cả project (đọc khoan dung) |
| Người dùng tự nhập? | có → recipe ở bảng `creations`, không đụng `photo_metadata` |

## 6. Đường hỏng

| Tình huống | Hành vi |
|---|---|
| Clip chỉ có trên iCloud, không mạng | clip đó không phân tích được, không gây lõm; tóm tắt thêm "· 1 clip not checked"; khi clip tải về thì tự phân tích |
| Quyền `.limited` thu hồi một asset | như iCloud: "not checked"; trạng thái lỗi của clip theo FS-12 README AC-13 |
| Clip không có track âm thanh | bỏ qua, không đếm |
| Export khi phân tích chưa xong | export chờ phân tích (hiện trong tiến độ export), không xuất bản thiếu ducking |
| Đóng studio giữa chừng | huỷ phân tích ≤ 1 s, không để file tạm |
| Hết bộ nhớ đĩa | cache không ghi được → giữ kết quả trong RAM cho phiên này |
| Undo | công tắc, chip, mỗi lần kéo slider là một bước |

## 7. Tiêu chí nghiệm thu

Project mẫu: 5 clip (3.0s ảnh · 6.2s video · 5.0s video · 3.0s ảnh · 6.8s video, tổng 24,0 s); "Morning Drive" A1
0,0–18,4 s Volume 80, fade 0; giọng nói tổng hợp bằng bộ đọc của hệ thống trong test (không giọng người thật,
không nhạc có bản quyền) ở 4,2–7,4 s, 10,8–13,0 s và 18,7–21,9 s.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | clip 10 s, giọng tổng hợp 2,0–5,0 s, phần còn lại ồn nền −50 dBFS | phân tích Voices | đúng một đoạn, hai mép lệch ≤ 0,25 s | ✅ `VoiceActivityAnalyzerTests.syntheticVoiceOneSegment`: giọng `say` 3,0 s (fixture `ShotDexTests/Fixtures/voice-3s.caf`, không người thật) đặt ở 2,0 s trong 10 s ồn trắng −50 dBFS → một đoạn **2,00–4,95 s**, cả trên iOS 27.0 (iPhone 17, 0,16 s cho 10 s) lẫn iOS 18.6 (iPhone 16, 0,32 s); `spansAreInSourceSeconds` (phân tích từ nguồn 12,0 → 14,0–17,0). Bộ phân loại `SNClassifySoundRequest(.version1)` lớp "speech", cửa sổ 1 s chồng 0,5; mép chỉnh theo RMS 50 ms (12 dB trên nền) |
| AC-2 | nhạc mức 0,8; Amount −12 dB, Duck in 0,3, Recover 0,8; giọng 4,2–7,4 s | dựng đường mức | 0,8 tới 3,9 s; giảm thẳng tới 0,201 tại 4,2 s; giữ tới 7,4 s; về 0,8 tại 8,2 s | ✅ `DuckingMathTests.singleDipShape` (0,8 tại 3,9; 0,201 tại 4,2; giữa dốc 4,05 là trung bình; giữ tới 7,4; 0,8 tại 8,2; các dốc nối liền 0–18,4); `VideoTimelineMathTests.musicRampsCoverTheWholeBed` vẫn xanh |
| AC-3 | như AC-2, giọng 4,2–5,0 s và 5,8–6,5 s | dựng đường mức | một chỗ lõm 3,9–7,3 s, không lên giữa hai đoạn (khoảng lặng 0,8 < 1,1) | ✅ `DuckingMathTests.shortGapHoldsTheFloor` (gộp thành 4,2–6,5; 0,8 tại 3,9 và 7,3; đáy ở 5,4; cách 1,2 s thì là hai lõm) |
| AC-4 | như AC-2, fade out 2,0 s cuối băng, giọng 16,0–18,4 s | đọc mức tại 17,4 s | 0,8 × 0,5 × 0,251 = 0,100 ±0,005 | ✅ `DuckingMathTests.fadeAndDuckMultiply` (0,100 tại 17,4 từ chính các dốc đưa vào mix; chỗ dốc fade và dốc lõm chồng nhau chia 4 đoạn thẳng, lệch < 1 % so với tích thật — D-11) |
| AC-5 | clip có gió −30 dBFS, không có giọng | chọn Voices, rồi Any Clip Sound | Voices: không lõm; Any Clip Sound: lõm suốt clip | ✅ `DuckingMathTests.windWithoutVoice` (Voices không lõm; Any Clip Sound lõm 9,2–14,2 = cả clip 3; ở mức clip 5 % thì −56 dB, không lõm); `VoiceActivityAnalyzerTests.noiseIsNotAVoice` (ồn −30 dBFS: bộ phân loại không gọi là giọng, RMS nghe thấy cả 10 s) |
| AC-6 | clip 2 có giọng, đã tắt tiếng | bật UNDER VOICES | không lõm ở clip 2; tóm tắt không đếm clip 2 | ✅ `DuckingMathTests.mutedClipNeverTriggers` (tắt tiếng, âm 0, V1 = 0, clip ảnh — không kích hoạt; tóm tắt 2 clip), `VideoAudioMixDuckingTests.mutedClipLeavesTheMixAlone` (mix: 0,8 suốt 4,2–7,4, clip 3 vẫn lõm) |
| AC-7 | clip video Speed 2×, trim 0–10 s, đặt ở 3,0 s, giọng ở nguồn 4,0–6,0 s | dựng | đáy lõm đúng 5,0–6,0 s timeline; không phân tích lại | ✅ `DuckingMathTests.speedTwoMapsSourceToTimeline` (5,0–6,0; trim từ 5 → 3,0–3,5) — giây nguồn quy ra timeline mỗi lần dựng, phân tích không biết tới speed (`DuckingMath.triggers`) |
| AC-8 | ducking bật, đã phân tích | đổi thứ tự clip 2 và 3 | chỗ lõm đi theo clip; số lần phân tích = 0 | ✅ `VideoDuckingModelTests.reorderAnalysesZeroTimes` (bộ phân tích giả đếm: 3 lần lúc đầu, đổi clip 2↔3 vẫn 3; Lake 4,6–6,8, Coast 9,2–12,4), `widerTrimReadsOnlyTheNewPart` (trim ra 6,2 → 8,0 chỉ đọc 6,2–8,0; ghép RMS và giọng) |
| AC-9 | ducking bật | tắt UNDER VOICES | audio mix bằng đúng mix khi chưa bật; một Undo bật lại | ✅ `VideoAudioMixDuckingTests.offEqualsNeverOn` (`getVolumeRamp` 74 mốc của mix tắt = mix không có ducking; bật thì 0,201 trong 4,2–7,4 và 10,8–13,0), `DuckingMathTests.offIsThePlainRamps`, `VideoDuckingSettingsTests.toggleIsOneUndo`, `DuckingMathTests.decodesLeniently` (khoá thiếu/hỏng/ngoài khoảng) |
| AC-10 | Amount −12 dB, đang phát | kéo Amount tới −18 dB trong một lần kéo | một bước undo; playback không ngắt; khung hình không dựng lại | ✅ (logic) `VideoDuckingSettingsTests.amountDragOneUndoNoRebuild`: 13 bước kéo −12 → −18 = một Undo, `structuralRebuildRequests` không tăng, `audioTierRequests` tăng — mọi thông số đi tầng chỉ-âm-thanh (`applyAudioMix`, gán mix mới không ngắt phát); Duck in/Recover/chip cũng vậy. Chưa nghe trên máy thật |
| AC-11 | project mẫu nhưng nhạc là sóng sin 440 Hz, ducking bật | Export | trong file xuất, năng lượng dải 440 Hz ở 5,0–7,0 s thấp hơn ở 1,0–3,0 s 12 ±1 dB | ✅ (D-12) `VideoDuckingExportTests.sine440DipsTwelveDecibels`: sin 440 Hz qua **đúng** `VideoCompositionBuilder.audioMix` mà export đưa `VideoExportWriter`, đọc bằng `AVAssetReaderAudioMixOutput` → **−12,00 dB** (iOS 27.0 và 18.6). Export chờ phân tích ("Listening for voices…" trong tiến độ export, `VideoStudioModel.export`). Smoke qua `VideoExportWriter` đầy đủ chưa chạy |
| AC-12 | clip 3 chỉ có trên iCloud, máy không mạng | mở tab Ducking | tóm tắt có "· 1 clip not checked"; không lõm ở clip 3; các clip khác vẫn lõm đúng | ✅ (logic) `VideoDuckingModelTests.unreadableClipIsNotChecked` (nguồn giả ném lỗi → `unreadable`, clip 3 không lõm, hai clip kia lõm; "Voices in 2 clips · 5.4s · 1 clip not checked"; không tự thử lại, `retryUnreadable` thì đọc lại). Chưa thử iCloud thật không mạng; "tự phân tích khi tải về" hiện là lần mở studio sau — studio chưa nghe PhotoKit báo clip đã tải |
| AC-13 | project mẫu, iPhone | mở tab Ducking | đồ thị 370×78; băng nhạc rộng 283,7 ±1pt; hai chỗ lõm, nhãn "−12 dB"; "Voices in 3 clips · 8.6s" | ⚠️ một phần — `DuckingMathTests.graphGeometry` (băng 18,4/24 s trong 370 = 283,7pt; lõm 26pt ở −12 dB, 50 ở −24 — kẹp ở đáy hộp), `sampleProjectTriggers` + `VideoDuckingModelTests.summaryWords` ("Voices in 3 clips · 8.6s"); đồ thị vẽ trên Duo ngoài 354×78 (`build/proofs/fs1213/f3-dc-ducking-cover.png`, project 3 ảnh nên không lõm); iPad ngang trên timeline: hai lõm + pill "−12 dB", "Voices in 3 clips · 8.6s" (`build/proofs/fs1213/f3-il-ducking-landscape.png`). **Ảnh iPhone chưa chụp** (Video Studio trên phone không liệt kê được cho driver) |
| AC-14 | đang phân tích 3 clip | đóng studio | tác vụ dừng ≤ 1 s; không crash; mở lại thì phân tích lại phần chưa xong | ✅ `VideoDuckingModelTests.closeCancelsWithinOneSecond` (3 phân tích 30 s đang chạy, `cancelAll` < 1 s, không giữ nửa kết quả; mở lại phân tích đủ 3); `close()` gọi `ducking.cancelAll()`; bộ đọc PCM kiểm huỷ mỗi buffer, không ghi file tạm (đọc thẳng vào RAM) |
| AC-15 | iPhone · iPad · Duo trong · Duo ngoài, project mẫu | mở tab Ducking | khớp `F3_P_Ducking`, `F3_IL_Ducking`, `F3_DI_Ducking`, `F3_DC_Ducking` lệch ≤ 2pt | ⚠️ một phần (`Tools/design-board compare`, 2026-10-05). **Duo trong** `F3_DI` (stand-in, route `video-ducking-duo-inner-standin.json`, `build/proofs/fs1213/f3-di-ducking-standin.png`): Volume, UNDER VOICES, Amount, Duck in, Recover, chip, tóm tắt khớp; còn chip lệch y −4 và nút loa báo 44×44 (vùng chạm) thay đĩa 26 của board. **iPad ngang** `F3_IL` (route `video-ipad-landscape-proofs.json`): dòng kiểu Mac (Volume + loa 40, Under Voices, Amount · Duck in · Recover 168×44, Duck Under 328×36, tóm tắt, chú thích, Fade) đúng kích thước nhưng cao hơn board ~45pt vì **thiếu dòng Level** "−9 dB" + thanh 328 — đó là đồng hồ mức riêng của băng, cần đo mức từng track (chưa có; đồng hồ chung cạnh khung là của cả mix) — để mở. Nhãn Voice trên V1 và pill "−12 dB" trên băng hiện khi tab mở. **Duo ngoài** `F3_DC` (route `video-ducking-duo-cover.json`): đồ thị 354×78, UNDER VOICES, Amount, Duck in, Recover theo thứ tự board; cả panel thấp 21pt vì tay nắm của panel ngoài (như FS-12.12 AC-15, đã vào REVIEW_QUEUE). **iPhone** `F3_P`: chưa so. Số Amount trên hàng slider chung của phone/Duo hiện "−12" (cột số của `EditorValueSlider` không chứa "−12 dB"); iPad hiện "−12 dB" |
| AC-16 | trạng thái của AC-13 và `F3_IL_Ducking` | `design-reviewer` đọc màu phần tô dưới chỗ lõm, dải giọng, nhãn Voice | đều là `timelineSpeech` #5E9CFF, chữ trên nhãn #06142E; không chỗ nào dùng #57BFD1 | ✅ agent `design-reviewer` (2026-10-05, đọc mã): tô dưới lõm `timelineSpeech` 30 %, dải giọng trên dải clip, ô chú giải, glyph dòng tóm tắt, nhãn **Voice** trên V1 — đều `timelineSpeech`, chữ nhãn `timelineSpeechInk`; token đúng #5E9CFF / #06142E, có trong DESIGN.md §3.3; không chỗ nào dùng #57BFD1 hay accent; pill "−12 dB" 60×16 đen 70 %, đường mức trắng 1,6, playhead `clipping` 2pt. Hai điểm nhỏ nó nêu đã sửa: ô chú giải dùng màu đầy như dải giọng, nhãn Voice bo `trackRadius` thay số 3. Ảnh iPad ngang: `build/proofs/fs1213/f3-il-ducking-landscape.png` |

**Chưa chứng minh được:** AC-13 (ảnh iPhone), AC-15 (một phần: dòng Level trên iPad, iPhone chưa so); AC-10/AC-12 mới là logic — chưa nghe trên máy thật, chưa thử iCloud không mạng.

## 8. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Bộ phân loại "speech" đổi theo bản iOS → project mở lại hạ khác đi | chấp nhận khi chưa phát hành; AC-1 chạy trên cả iOS 18 và 26 |
| Clip quay có nhạc nền bị nhận là giọng | chip Voices / Any Clip Sound để người dùng chọn; không tách nguồn (§2) |
| Nhiều đoạn dốc âm lượng trên một băng làm audio mix nặng | gộp đoạn theo luật khoảng lặng (AC-3); đo với 50 đoạn khi `/plan` |
