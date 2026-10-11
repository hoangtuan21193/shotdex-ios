# FS-12.14 — Phụ đề tự động

`FS-12.14` · tier D · `Features/VideoStudio/` (mới) · `Domain/Video/VideoProjectModels.swift` · `Data/Sources/VideoFrameCompositor.swift`
· nguồn intent [video-studio-canvas-chrome](../../_intents/2026-10-03-video-studio-canvas-chrome.md) (canvas hàng F4) · cập nhật 2026-10-04 (iPad kiểu Mac)

**Một câu:** lời nói trong clip thành phụ đề sửa được, nhận dạng **hoàn toàn trên máy**, có kiểu chữ, ngôn ngữ, và
nướng vào video lúc xuất.

Code hôm nay: chưa target nào dùng Speech; chữ trên video là overlay chữ theo thời gian ([FS-12.08 §2](08-model-and-v1-limits.md)).
Board hàng F4: `F4_P_Captions` ([`docs/design/iphone/project/`](../../design/iphone/project/)) · `F4_IL_Captions`, `F4_IP_Captions` ([`docs/design/ipad/project/`](../../design/ipad/project/), kiểu Mac 2026-10-04) · `F4_DI_Captions`, `F4_DC_Captions` ([`docs/design/duo/project/`](../../design/duo/project/)). Riêng tư: [NF-03](../../04-non-functional-design/NF-03-privacy-and-security.md).

## 1. Người dùng cần gì

Reel người chụp quay có người nói (hướng dẫn viên, cô dâu chú rể, chính mình), và đa số người xem lướt
không bật tiếng. Gõ tay từng câu là nửa giờ cho một phút phim. Âm thanh riêng tư thì không được rời máy.

## 2. Phạm vi

**Có:** Auto Captions cho mọi clip video có tiếng; một lane phụ đề **C1**; sáu lệnh **Edit · Style · Split · Merge ·
Language · Delete**; bốn kiểu, cỡ, ba vị trí; công tắc **Burn into video**.

**Cố ý không có:**
- Nhận dạng qua máy chủ — kể cả khi máy không có model ngôn ngữ đó. *Vì* NF-03: âm thanh không rời máy.
- Hai ngôn ngữ trong một project, dịch phụ đề — một lane, một ngôn ngữ.
- Kiểu riêng cho từng khối — kiểu là của cả lane. *Vì* phụ đề lệch kiểu giữa câu trông như lỗi; chữ tự do đã có overlay chữ.
- Nhập/xuất `.srt` — chưa ai hỏi; thêm sau không đổi model.

## 3. Màn hình (canvas hàng F4)

| Máy · board | Bố cục khi đang sửa phụ đề |
|---|---|
| iPhone 402×874 · `F4_P_Captions` | panel 340 tại y 450; hàng lệnh 6 ô 64×56 tại y 460, cuộn ngang, mép phải mờ 32; thẻ tiến độ; hàng **Language** 42 "English (US) ›"; tiêu đề **CAPTIONS · N**; danh sách khối; đáy 84: ✕ 44 · "Caption 2" / "0:06.0 → 0:07.4" · ✓ 44 |
| Duo ngoài 466×678 · `F4_DC_Captions` | panel 382×344 tại y 334, hàng lệnh tại y 340, thẻ tiến độ rồi danh sách; dải 84: 5 công cụ mờ, khối tên 76×56 "Caption 2" / "6.0 → 7.4s", ✕ 44 tại y 504, ✓ 44 tại y 556, Export ẩn |
| Duo trong 951×669 · `F4_DI_Captions` | cột phải 264 (cao 385): hàng lệnh tại y 12, mục đang mở (board: Style); lane C1 khối cao 28; hàng đáy: 5 công cụ mờ, góc phải ✕ 40 · tên · ✓ 40 |
| iPad ngang 1376×1032 · `F4_IL_Captions` (kiểu Mac 2026-10-04) | tab **Text** của pool: **Add Text** và **Auto Captions** 294×44 + chú thích; inspector 360: hàng lệnh tại y 80 (Edit · Style · Split · Merge · Language …), thẻ tiến độ, **Caption 2** ô chữ 328×44 + Expand Text Field 44 + giờ, rồi **Style** segmented Clean · Box · Outline · Word by Word (4 × 80×32, một hàng), Size slider 44, **Position** segmented Bottom · Middle · Top, Burn into video công tắc; chân 64: ✕ 44 · tên · ✓ 44; lane C1 cao 44 (**khối cao bằng lane**) trên cùng, trên T1, header "C1 Captions" + Lock |
| iPad dọc 1032×1376 · `F4_IP_Captions` | như iPad ngang, nội dung trong dock 324: hàng lệnh y 1061; 3 cột 312 — Caption 2 (ô chữ + Expand) │ Caption Style segmented 312×36 + Size │ Position segmented 312×36 + Burn into video; chân 64 ở y 1312 |

- **Lối vào trên mọi máy:** hàng **Auto Captions** ngay dưới Add Text — tab Text của pool (iPad) và panel công cụ
  Text (iPhone, Duo ngoài, Duo trong — chạm Text ở thanh dưới mở panel, FS-12.04 §3; board `TX_P_TextPanel`,
  `TX_DC_TextPanel`, `TX_DI_TextPanel`). Không có lối thứ hai (menu ⋯ của transport không có mục này). *Vì* một hành động một chỗ (DESIGN §1.3). Đã có lane C1 thì hàng đổi thành "Edit Captions".
- **Thẻ tiến độ** (lề 16, `r-md`, nền trắng 6%): "Transcribing on this iPhone…" (iPad: "on this iPad…") + phần trăm
  mono; thanh 5pt; dòng phụ "3 of 5 clips · nothing leaves the device". Xong thì thẻ biến mất.
- **Lane C1:** khối nền trắng 10%, `r-track`, chữ 12 semibold; khối đang chọn nền `timelineSelection` 22% + viền trong
  1,5pt; đoạn chưa nhận dạng là khối sọc "Transcribing…". iPhone không còn chỗ cho C1 trong lát 96: clip có lời
  mang chip **Voice** cao 16 ở đáy clip, và Project Overview có vạch 3pt ở vị trí từng khối.
- Khối đang chọn có viền đứt quanh phụ đề trên khung hình (iPad, Duo trong).
- **Màu "có lời" là token `timelineSpeech` #5E9CFF**, chữ trên nó #06142E — chip Voice **và** vạch khối trên Project
  Overview; cùng token với đoạn có giọng của ducking ([13](13-audio-ducking.md)), chỉ Video Studio (chốt 2026-10-03).
  Cyan `timelineSelection` chỉ còn ở khối đang chọn; board sửa vạch overview từ #57BFD1 sang #5E9CFF. Đề xuất token
  cho DESIGN.md §3.3: [12 §3](12-beats.md).

## 4. Nhận dạng

- **Chỉ trên máy:** mỗi yêu cầu bắt buộc nhận dạng on-device; không có model thì không chạy, không bao giờ rơi
  sang máy chủ. Một engine cho cả iOS 17–26 (bộ nhận dạng giọng nói của hệ thống).
- **Đọc gì:** tiếng gốc của từng clip video trong khoảng trim, đọc thẳng từ asset, **không ghi file tạm**. Ảnh,
  freeze và clip đã tắt tiếng bị bỏ qua. *Vì* thứ người dùng đã tắt tiếng thì không phải lời muốn hiện. Nhạc không đọc.
- **Quyền:** lần đầu chạm Auto Captions mới xin quyền nhận dạng giọng nói (một câu xin quyền mới trong Info.plist:
  "ShotDex turns speech in your clips into captions. It runs on this device; audio never leaves it.").
- **Ngôn ngữ:** danh sách = ngôn ngữ hệ thống nhận dạng được; ngôn ngữ chưa có model trên máy hiện mờ, dòng phụ
  "Not on this iPhone". Mặc định: ngôn ngữ của máy nếu có model, không thì English (US). App không tự tải model.
- **Chia khối:** một dòng, ≤ 32 ký tự, ≤ 3,0 s; ngắt ở khoảng lặng ≥ 0,4 s hoặc dấu câu. Đặt tên theo thứ tự thời
  gian: "Caption 1", "Caption 2"…
- **Neo vào clip:** mỗi khối nhớ clip và giờ **trong nguồn**. Trim, dời, đổi tốc độ, đổi thứ tự clip thì phụ đề
  đi theo; khối rơi ra ngoài khoảng trim bị ẩn (không xoá), trả trim là hiện lại. Xoá clip là xoá khối của nó.
  *Vì* phụ đề neo theo giờ project sẽ lệch tiếng ngay lần trim đầu tiên.
- **Chạy nền trong studio:** sửa khối, phát, cắt vẫn làm được trong lúc nhận dạng; khối hiện dần theo clip.

## 5. Sáu lệnh

| Lệnh | Làm gì | Undo |
|---|---|---|
| **Edit** | thẻ tiến độ, Language, danh sách khối; chạm giờ của một hàng = chọn khối và dời playhead tới đầu khối; khối đang chọn là ô sửa chữ, ↗ mở trình sửa chữ toàn màn của overlay chữ | một lần sửa chữ = một bước |
| **Style** | **Clean · Box · Outline · Word by Word** (chip 28); **Size** 3–12%, mặc định 6%; **Bottom · Middle · Top**; **Burn into video**; dòng "✓ 12 captions · English (US)" | mỗi lần chạm/kéo một bước |
| **Split** | tách khối đang chọn tại playhead, ở ranh giới từ gần nhất; playhead ngoài khối thì mờ | một bước |
| **Merge** | gộp khối đang chọn với khối liền sau: chữ nối bằng một dấu cách, thời gian là hợp hai khoảng; khối cuối thì mờ | một bước |
| **Language** | danh sách ngôn ngữ; chọn ngôn ngữ khác = nhận dạng lại cả lane | cả lần thay là một bước |
| **Delete** | xoá khối đang chọn (`timelineDestructive`); chọn lane (chạm nhãn C1) rồi Delete = xoá cả lane | một bước |

- **Kiểu:** Clean = chữ trắng có bóng; Box = chữ trắng trên nền đen 62% bo 8 (như board); Outline = chữ trắng viền
  đen; Word by Word = như Box, từng từ hiện đúng lúc được nói. Khối đã sửa tay mất mốc từng từ → các từ chia đều.
- **Cỡ và vị trí:** Size là chiều cao chữ theo % cạnh ngắn **khung xuất**; tâm dòng ở 85% · 50% · 15% chiều cao.
  Đo theo khung xuất nên phụ đề luôn trọn trong khung, kể cả khi preset xuất cắt Fill ([FS-12.16](16-export-presets.md)).
- **Đổi ngôn ngữ khi đã có khối sửa tay:** hỏi "Transcribe again in Tiếng Việt? Your 3 edited captions will be
  replaced." · Transcribe · Cancel. Không có khối sửa tay thì làm luôn.
- Kéo khối trên C1 như thanh chữ trên T1: kéo thân để dời, kéo mép để đổi khoảng, không chồng khối kề; lane khoá thì không kéo được.

## 6. Burn into video và xuất

- **Bật (mặc định):** phụ đề vẽ lên mọi khung xuất, **trên cùng**, trên mọi overlay. Preview vẽ bằng lớp sống như
  overlay chữ; một hàm bố cục dùng chung cho preview và export, nên hai bên không trôi khỏi nhau.
- **Tắt** (chốt 2026-10-03): khung hình sạch; phụ đề đi thành **một track phụ đề mềm** trong file (văn bản theo thời
  gian, mang mã ngôn ngữ của lane), trình phát có nút CC bật được. Dòng phụ dưới công tắc khi tắt: "Saved as a
  subtitle track — Photos, Instagram and TikTok don't show it." *Vì nói trước rằng ba nơi đăng phổ biến bỏ qua nó.*
- Cùng một hàm chia và định giờ khối cho cả hai đường; track mềm không mang kiểu, cỡ, vị trí.

## 7. Dữ liệu

| | |
|---|---|
| Project giữ | một lane phụ đề tuỳ chọn: ngôn ngữ, kiểu, cỡ, vị trí, Burn into video, trạng thái nhận dạng (tới clip nào); mỗi khối: id, clip, giờ đầu/cuối trong nguồn, chữ, mốc từng từ, cờ "đã sửa tay" |
| Lưu ở | công thức project trong bảng Video Projects ([FS-06.01b](../FS-06-collections/01b-album-management-and-creations.md)); chữ người dùng sửa **không** vào `photo_metadata` ([BD-02](../../01-basic-design/BD-02-database-design.md)) |
| Đọc khoan dung | một khối hỏng chỉ mất khối đó; ngôn ngữ không còn trên máy thì lane vẫn mở và vẫn sửa được. App chưa release: không migration |

## 8. Đường hỏng

| Tình huống | Hành vi |
|---|---|
| Quyền bị từ chối / bị hạn chế | thẻ "Speech recognition is off for ShotDex." + **Open Settings** (bị hạn chế: không có nút); không tạo lane, không thêm bước undo |
| Máy không có model ngôn ngữ nào | hàng Auto Captions mờ, dòng phụ "On-device speech recognition isn't available on this iPhone." |
| Không mạng | chạy y hệt — không có lời gọi mạng nào |
| Clip chỉ có trên iCloud, máy không mạng | clip đó bị bỏ qua; dòng phụ "1 clip couldn't be read — it's in iCloud." + **Retry**; clip khác vẫn chạy |
| Không có lời nào | "No speech found in these clips."; không tạo lane |
| ✕ trong lần nhận dạng đầu | dừng nhận dạng, xoá lane, trả số bước undo như lúc mở panel (luật ✕ của 06c §7) |
| ✓ khi đang nhận dạng | chạy tiếp; lane đầy dần |
| Rời studio khi đang 58% | dừng; khối đã có được lưu cùng nháp ([18](18-drafts.md)); mở lại thấy thẻ "Captions stopped at 58%" + **Continue** chạy tiếp từ clip chưa xong |
| `.limited`, hết bộ nhớ | clip mất quyền đọc bị bỏ qua như iCloud; không ghi file tạm nên không cần chỗ trống |

## 9. Tiêu chí nghiệm thu

Project mẫu: 3.0s ảnh · 6.2s video · 5.0s video · 3.0s ảnh · 6.8s video (24,0 s, như [FS-12.11 §9](11-multi-select-and-reorder.md)); ba
video có lời tiếng Anh dựng sẵn từ giọng đọc tổng hợp (không mặt người), mốc từng từ đã biết.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | project mẫu, quyền chưa hỏi | chạm Auto Captions, rồi Allow | hệ thống hỏi đúng một lần; thẻ "Transcribing on this iPhone…" chạy từ 0%; lane C1 xuất hiện; dòng phụ "… of 3 clips" | ⚠️ một phần — `VideoCaptionSessionTests.asksPermissionOnce` (hỏi đúng một lần, lần sau đọc trạng thái), `laneAppearsAsOneUndoStep` (lane = +1 undo; khối "The road to Vík" · "starts right here." · "Listen to" · "that water." ở 3,2 · 6,0 · 10,8 · 12,0 s), `resultsReachTheUndoSnapshots` (K4); `CaptionRecognitionPlanTests.skipsPhotosFreezesAndMutedClips`, `progressCountsClips`; route `video-captions-ipad.json` (`-ShotDexFakeSpeech`, iPad Pro 13" ngang): Auto Captions dưới Add Text → thẻ "Transcribing on this iPad… 0% · 0 of 3 clips · nothing leaves the device", C1 sọc "Transcribing…", rồi 11 khối trên C1 + vạch #5E9CFF trên overview, hàng đổi thành Edit Captions. **Lối vào iPhone/Duo đã chốt (2026-10-11):** chạm Text ở thanh dưới mở panel Text (FS-12.04 §3), Auto Captions ngay dưới Add Text trên iPhone, Duo ngoài và Duo trong; mục tạm trong menu ⋯ của transport bỏ — bằng chứng lối vào: task Text panel (chưa có). Hộp thoại quyền thật chỉ có trên máy thật |
| AC-2 | quyền đã bị từ chối | chạm Auto Captions | thẻ "Speech recognition is off for ShotDex." + Open Settings; không lane; số bước undo không đổi | ✅ `VideoCaptionSessionTests.deniedShowsCardNoLaneNoUndo` (thẻ "Speech recognition is off for ShotDex." + Open Settings, không lane, undo không đổi), `restrictedHasNoSettingsButton` |
| AC-3 | bất kỳ project; bộ nhận dạng giả trong test | bắt đầu nhận dạng | mọi yêu cầu gửi đi đều bắt buộc on-device; máy bật chế độ máy bay vẫn ra cùng số khối | ⚠️ một phần — `SpeechCaptionServiceTests.everyRequestRequiresOnDevice` (mọi request `requiresOnDeviceRecognition = true`), `localeWithoutModelNeverStarts` (không model → không request, không đường máy chủ), `readsOnlyTheTrimWindow` (đọc đúng khoảng trim, giờ nguồn), `leavesNoTemporaryFiles`; **còn máy thật**: chế độ máy bay ra cùng số khối |
| AC-4 | máy có model en-US, không có vi-VN | mở Language | English (US) chọn được; Tiếng Việt mờ, dòng phụ "Not on this iPhone", chạm không đổi gì | ✅ `CaptionLanguagesTests.unavailableIsDimAndInert` (English (US) chọn được; Tiếng Việt mờ, "Not on this iPhone"), `defaultIsDeviceLanguageIfModelElseEnUS`; `VideoCaptionSessionTests.languageChangeIsOneUndoStep` (vi-VN không đổi gì; de-DE = nhận dạng lại cả lane, +1 undo), `editedCuesTriggerConfirmation` |
| AC-5 | clip 2 có câu 12 từ, mốc từ đã biết | nhận dạng xong | mọi khối ≤ 32 ký tự và ≤ 3,0 s; đầu khối lệch ≤ 0,3 s so với mốc từ đầu tiên; khối xếp theo thời gian | ✅ `CaptionChunkerTests.blocksStayWithin32CharsAnd3s`, `breaksAtPauseOrPunctuation` ("The road to Vík" · "starts right here." · "Listen to that water," · "it never stops."; lặng 0,39 s không ngắt, 0,40 s ngắt), `startWithin0_3sOfFirstWord` (đầu khối = mốc từ đầu), `namesInTimeOrder`; đọc khoan dung: `VideoCaptionDecodingTests.oneBrokenCueLosesOnlyItself`, `unknownStyleFallsBackToClean` |
| AC-6 | khối "starts right here." 6,0–7,4 s nằm trong clip 2 | trim đầu clip 2 thêm 1,0 s | khối dời về 5,0–6,4 s trên timeline, chữ không đổi; khối có nguồn nằm hẳn trong 1,0 s bị cắt thì ẩn; một Undo trả lại cả hai | ✅ `CaptionTimelineTests.trimHeadShiftsCue` (6,0–7,4 → 5,0–6,4), `cueInsideTrimmedSecondHides` (ẩn, không xoá; trả trim là hiện), `oneUndoRestoresBoth`, `deleteClipDeletesItsCues`, `splitClipReassignsBySourceTime`, `duplicateClipCopiesCues`, `speedScalesCue`, `dragNeverOverlapsNeighbour` |
| AC-7 | Caption 2 = "starts right here." 6,0–7,4 s, playhead 6,7 s giữa "right" và "here" | Split | hai khối "starts right" 6,0–6,7 và "here." 6,7–7,4; một Undo về một khối | ✅ `CaptionEditingTests.splitAtNearestWordBoundary` ("starts right" 6,0–6,7 · "here." 6,7–7,4; một Undo về một khối), `splitDisabledOutsideCue` |
| AC-8 | Caption 3 "Listen to" 10,8–11,6, Caption 4 "that water." 12,0–13,1 | chọn Caption 3, Merge | một khối "Listen to that water." 10,8–13,1; Merge mờ khi chọn khối cuối | ✅ `CaptionEditingTests.mergeJoinsTextAndUnionsTime` ("Listen to that water." 10,8–13,1), `mergeDisabledOnLast`, `deleteLaneFromLabel` |
| AC-9 | Style Box, Size 6%, Bottom, Burn into video bật; xuất 1080×1920 | đọc khung ở 6,5 s | có hộp phụ đề, chữ cao 65 ±3 px (6% của 1080), tâm dòng ở y 1632 ±19 (85%); khung ở 9,0 s (không khối) không có hộp | ✅ `CaptionLayoutTests.boxSixPercentBottomOn1080x1920` (64,8 px, tâm y 1632), `wordByWordRevealsAtWordTimes`, `editedCueSpreadsWordsEvenly`; `VideoCaptionExportTests.boxAt6_5sNoneAt9_0s` (xuất thật 1080×1920: chữ 65 ±3 px, hộp tâm 1632 ±19 ở 6,5 s; 9,0 s không hộp, không chữ). Ghi chú: compositor trộn trong ánh sáng tuyến tính nên hộp đen 62% trên xám 139 đọc ra 89 (như overlay chữ hôm nay) |
| AC-10 | như AC-9 nhưng Burn into video tắt | xuất | khung 6,5 s không có pixel phụ đề; file có đúng một track phụ đề, ngôn ngữ en-US, số mẫu bằng số khối, mẫu tại 6,5 s là "starts right here." | ✅ `VideoCaptionExportTests.softTrackOneSamplePerCue` (đúng một track `tx3g` trong `.mp4` — Q3: không cần `.mov` —, en-US, 2 mẫu có chữ cho 2 khối, mẫu 6,5 s = "starts right here."; khoảng giữa hai khối là mẫu rỗng), `burnOffLeavesFramesClean`. Photos nhập file giữ hay bỏ track: chưa đo |
| AC-11 | lần nhận dạng đầu đang 40% | bấm ✕ | nhận dạng dừng trong ≤ 1 s; không lane, không khối; số bước undo bằng lúc mở panel | ✅ `VideoCaptionSessionTests.cancelRemovesLaneAndRestoresUndoDepth` (✕ → dừng < 1 s, không lane, độ sâu undo như lúc mở panel), `cancelStopsWithinOneSecond`, `doneKeepsRecognising` |
| AC-12 | nhận dạng 58%, đã xong clip 2 | bấm Back, mở lại project | khối của clip 2 còn nguyên; thẻ "Captions stopped at 58%" + Continue; Continue chỉ nhận dạng clip 3 và 5 | ⚠️ một phần — `VideoCaptionSessionTests.continueTranscribesOnlyRemainingClips` (thẻ "Captions stopped at 58%", Continue chỉ đọc clip 3 và 5), `stoppedStateSurvivesEncodeDecode` (Back ghi `stoppedAtPercent`, lane đi cùng nháp); route Back → Video Projects → dòng Draft chưa chạy |
| AC-13 | clip 3 chỉ có trên iCloud, máy không mạng | Auto Captions | clip 2 và 5 có khối; dòng phụ "1 clip couldn't be read — it's in iCloud." + Retry; không spinner treo | ✅ `VideoCaptionSessionTests.unreadableClipIsSkippedWithRetry` (clip iCloud bỏ qua, clip khác có khối, "1 clip couldn't be read — it's in iCloud." + Retry, không chạy treo); Retry nạp lại nguồn của đúng các clip đó (`VideoStudioModel.reloadSources(for:)`) — chưa đo trên máy không mạng |
| AC-14 | 3 clip video chỉ có gió, không lời | Auto Captions | "No speech found in these clips."; không lane C1; undo không đổi | ✅ `VideoCaptionSessionTests.noSpeechCreatesNoLane` ("No speech found in these clips.", không lane, bước tạo lane được rút lại — undo không đổi); ảnh `build/proofs/fs1214/F4_DC-no-speech-card.png` (Duo ngoài), `F4_P-no-speech-card.png` (iPhone) — project toàn ảnh |
| AC-15 | iPhone 402×874 · iPad 1376×1032 · Duo trong 951×669 · Duo ngoài 466×678; Caption 2 đang chọn, 58% | dựng đúng trạng thái từng board | khớp `F4_P_Captions`, `F4_IL_Captions`, `F4_IP_Captions` (iPad dọc 1032×1376), `F4_DI_Captions`, `F4_DC_Captions` lệch ≤ 2pt; không control nào dưới góc bo hay dải 84 | ⚠️ một phần — `Tools/design-board compare` 2026-10-06: **F4_IL** (route `video-f4f7f8-ipad-landscape.json`, `-ShotDexFakeSpeechSlow`): thẻ tiến độ, Caption 2 + Expand, giờ, Style 4×80×32, Size 44, Position 3 nút, Burn — khớp ≤ 2pt sau khi chỉnh (`build/proofs/fs1214/F4_IL-caption2-style.png`); **F4_DI** (stand-in): chip Style gói hai dòng như board sau khi sửa, Position lệch theo hàng chip; **F4_DC** (Duo thật, gập): hàng lệnh 361 khớp từ 2026-10-08 (board vẽ tay nắm 17, FS-12.07b §4), rail ✕ 504 · ✓ 556 khớp; **F4_P** (iPhone 17 26.5): dự án ảnh của sim → thẻ "No speech found", hàng lệnh +81 vì project 4:3 (panel theo tỉ lệ) — chưa so được trạng thái có khối; **F4_IP** chưa đo: bước `orientation: portrait` của driver không xoay sim iPad (đã có trong REVIEW_QUEUE) |
| AC-16 | panel Style, Burn into video bật | tắt công tắc | dòng phụ "Saved as a subtitle track — Photos, Instagram and TikTok don't show it."; một bước undo | ✅ `VideoCaptionSessionTests.burnToggleIsOneUndoStep`; dòng phụ "Saved as a subtitle track — Photos, Instagram and TikTok don't show it." dưới công tắc khi tắt (`captionSubtitleTrackNote`) |
| AC-17 | lane C1 có khối, iPhone | chụp dải tổng quan; `design-reviewer` đọc màu | vạch khối và chip Voice là `timelineSpeech` #5E9CFF; chỉ khối đang chọn mang #57BFD1 | ⚠️ một phần — code: vạch overview và chip Voice dùng `EditorTheme.timelineSpeech`, chỉ khối đang chọn `timelineSelection` (overview `VideoViewerChrome`, `VideoTimelineTracks.voiceSpans`); `CaptionTimelineTests.overviewMarksMatchCues`; ảnh iPad: vạch #5E9CFF trên overview. Chưa: ảnh chip Voice iPhone, agent `design-reviewer` |

**Chưa chứng minh được:** AC-1 (lối vào iPhone/Duo chờ chốt), AC-3 (máy thật — simulator không có model on-device đáng tin), AC-12 (route mở lại nháp), AC-15 (parity), AC-17 (ảnh iPhone + `design-reviewer`).

## 10. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Tốc độ nhận dạng on-device chưa đo; project 10 phút có thể mất vài phút | đo trên iPhone 17 trước `/plan`: mục tiêu ≤ 1× thời lượng tiếng; chạy nền nên không chặn sửa |
| Simulator thường không có model on-device | AC chạy bằng bộ nhận dạng giả ở test; AC-3 và đo tốc độ trên máy thật |
| Info.plist chưa có câu xin quyền nhận dạng giọng nói (NF-03 §4 đã ghi luật "chỉ trên máy") | việc của code: thêm khoá xin quyền nhận dạng giọng nói với câu ở §4 (và bản dịch trong String Catalog) cùng commit đầu tiên của Auto Captions |
| Track phụ đề mềm chưa thử qua đường ghi file và qua Photos | đo ở `/plan` trên máy thật; Photos nhập file mà bỏ track là chấp nhận được — dòng phụ §6 đã nói trước |
