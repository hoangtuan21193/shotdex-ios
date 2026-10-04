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
  và dòng tóm tắt "Listening for voices…". Không có giọng: "No voices in clip sound".
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
| AC-1 | clip 10 s, giọng tổng hợp 2,0–5,0 s, phần còn lại ồn nền −50 dBFS | phân tích Voices | đúng một đoạn, hai mép lệch ≤ 0,25 s | ⚠️ chưa có |
| AC-2 | nhạc mức 0,8; Amount −12 dB, Duck in 0,3, Recover 0,8; giọng 4,2–7,4 s | dựng đường mức | 0,8 tới 3,9 s; giảm thẳng tới 0,201 tại 4,2 s; giữ tới 7,4 s; về 0,8 tại 8,2 s | một phần: `VideoTimelineMathTests.musicRampsCoverTheWholeBed` (chưa có ducking) |
| AC-3 | như AC-2, giọng 4,2–5,0 s và 5,8–6,5 s | dựng đường mức | một chỗ lõm 3,9–7,3 s, không lên giữa hai đoạn (khoảng lặng 0,8 < 1,1) | ⚠️ chưa có |
| AC-4 | như AC-2, fade out 2,0 s cuối băng, giọng 16,0–18,4 s | đọc mức tại 17,4 s | 0,8 × 0,5 × 0,251 = 0,100 ±0,005 | ⚠️ chưa có |
| AC-5 | clip có gió −30 dBFS, không có giọng | chọn Voices, rồi Any Clip Sound | Voices: không lõm; Any Clip Sound: lõm suốt clip | ⚠️ chưa có |
| AC-6 | clip 2 có giọng, đã tắt tiếng | bật UNDER VOICES | không lõm ở clip 2; tóm tắt không đếm clip 2 | ⚠️ chưa có |
| AC-7 | clip video Speed 2×, trim 0–10 s, đặt ở 3,0 s, giọng ở nguồn 4,0–6,0 s | dựng | đáy lõm đúng 5,0–6,0 s timeline; không phân tích lại | ⚠️ chưa có |
| AC-8 | ducking bật, đã phân tích | đổi thứ tự clip 2 và 3 | chỗ lõm đi theo clip; số lần phân tích = 0 | ⚠️ chưa có |
| AC-9 | ducking bật | tắt UNDER VOICES | audio mix bằng đúng mix khi chưa bật; một Undo bật lại | ⚠️ chưa có |
| AC-10 | Amount −12 dB, đang phát | kéo Amount tới −18 dB trong một lần kéo | một bước undo; playback không ngắt; khung hình không dựng lại | ⚠️ chưa có |
| AC-11 | project mẫu nhưng nhạc là sóng sin 440 Hz, ducking bật | Export | trong file xuất, năng lượng dải 440 Hz ở 5,0–7,0 s thấp hơn ở 1,0–3,0 s 12 ±1 dB | ⚠️ chưa có — smoke test export |
| AC-12 | clip 3 chỉ có trên iCloud, máy không mạng | mở tab Ducking | tóm tắt có "· 1 clip not checked"; không lõm ở clip 3; các clip khác vẫn lõm đúng | ⚠️ chưa có |
| AC-13 | project mẫu, iPhone | mở tab Ducking | đồ thị 370×78; băng nhạc rộng 283,7 ±1pt; hai chỗ lõm, nhãn "−12 dB"; "Voices in 3 clips · 8.6s" | ⚠️ chưa có |
| AC-14 | đang phân tích 3 clip | đóng studio | tác vụ dừng ≤ 1 s; không crash; mở lại thì phân tích lại phần chưa xong | ⚠️ chưa có |
| AC-15 | iPhone · iPad · Duo trong · Duo ngoài, project mẫu | mở tab Ducking | khớp `F3_P_Ducking`, `F3_IL_Ducking`, `F3_DI_Ducking`, `F3_DC_Ducking` lệch ≤ 2pt | ⚠️ chưa có — agent `design-parity` |

| AC-16 | trạng thái của AC-13 và `F3_IL_Ducking` | `design-reviewer` đọc màu phần tô dưới chỗ lõm, dải giọng, nhãn Voice | đều là `timelineSpeech` #5E9CFF, chữ trên nhãn #06142E; không chỗ nào dùng #57BFD1 | ⚠️ chưa có — agent `design-reviewer` |

**Chưa chứng minh được:** AC-1 tới AC-16 (AC-2 một phần).

## 8. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Bộ phân loại "speech" đổi theo bản iOS → project mở lại hạ khác đi | chấp nhận khi chưa phát hành; AC-1 chạy trên cả iOS 18 và 26 |
| Clip quay có nhạc nền bị nhận là giọng | chip Voices / Any Clip Sound để người dùng chọn; không tách nguồn (§2) |
| Nhiều đoạn dốc âm lượng trên một băng làm audio mix nặng | gộp đoạn theo luật khoảng lặng (AC-3); đo với 50 đoạn khi `/plan` |
