# FS-12.03b — Các băng của bàn dựng và lane màn rộng

`FS-12.03b` · `Features/VideoStudio/` (`VideoViewerChrome`, `VideoAudioMeterColumn`, `VideoTimelineGutter`,
`VideoMediaPoolColumn`) · test `VideoStudioDeskLayoutTests` · cập nhật 2026-10-04 (iPad theo canvas kiểu Mac)
· nguồn intent [video-studio-canvas-chrome](../../_intents/2026-10-03-video-studio-canvas-chrome.md)
· [ipad-mac-style](../../_intents/2026-10-04-ipad-mac-style.md) (iPad)

**Một câu:** bên trong bố cục rộng ([03](03-timeline-and-desk-layout.md)) — pool, hàng phát dưới khung, hàng công cụ
timeline, dải tổng quan, meter, track header — mỗi băng có một việc và lấy chiều cao từ sân khấu, không từ timeline.

Board iPad: [`docs/design/ipad/project/`](../../design/ipad/project/) `IL1_Main`, `IL3_TextOverlay`, `IL4_Music`,
`MP_IL_*`, `IP1_Main`; Duo: [`docs/design/duo/project/`](../../design/duo/project/) `DI1_Main`.

## 1. Pool, tên dưới khung, Quick Adjust

- **Pool** (chỉ iPad, panel kính nổi **320×568** ở (8, 8), bo 22): tiêu đề "Library" 20 semibold ở y 25 cùng
  **Select** (chữ, 68×44) · **Search Library** 44 · **Hide Media** 44; segmented **Media · Text · Stickers · Music**
  294×36 (nút 71×32) ở y 77; rồi nội dung tab từ y 121, lề 13. Nội dung tab Media: [09](09-media-panel.md).
- Tab **Text**: nút "Add Text" 294×44 bo 12 (và "Auto Captions" ngay dưới — [14](14-captions.md)), rồi "Fonts You
  Used" (hàng 302×50: "Aa" + tên font) và dòng "Fonts you use appear here, ready to reuse." Tab **Music**: dòng Video
  sound (slider, 44) + chú thích, "Add Music from Files…" 294×44, My Music (hàng 56: Preview 44 · tên + "3:24 · m4a" ·
  Delete 44) — cùng nội dung panel Music của iPhone ([04 §3](04-tools-and-inspector.md)).
- Tiêu đề mục trong pool và inspector viết **Title Case** ("Fonts You Used", "My Music") thay chữ hoa — theo bản Mac.
- Pool mở mặc định khi rộng ≥ 1100; dưới đó đóng, bật bằng capsule **Media Pool** ở đầu toolbar. Chỉ mở được khi
  khung còn ≥ 330pt.
- **Không còn viewer header** (bỏ 2026-10-04): Media Pool → capsule toolbar (pool đóng) / Hide Media (pool mở);
  Quick Adjust · Inspector → capsule 92 trên toolbar; **tên thứ dưới playhead** → đầu hàng phát dưới khung
  ("Clip 2" 17 semibold + "under playhead" 13, [04 §5](04-tools-and-inspector.md)); Before and After → cuối hàng
  phát. Tên vẫn cần vì khung hình là vùng duy nhất không tự nói nó đang chiếu gì — và pool mở là có hai tấm ảnh
  trên màn. Khi chọn nhiều, dòng này ghi "3 clips selected" ([11](11-multi-select-and-reorder.md)); khi skim,
  "Skimming · Lake · 0:02.3 / 0:05" ([17b §6](17b-keyboard-and-pointer.md)).
- **Quick Adjust**: dải 44 dưới khung: Speed (clip) · Duration (ảnh) · Video sound (âm gốc mọi clip; không có
  Master — [04 §2](04-tools-and-inspector.md)), mỗi cái bung slider tại chỗ. **Mặc định tắt**: bật sẵn là ăn 44pt của
  khung trên cửa sổ cao 669. iPad kiểu Mac: dải nằm trong sân khấu giữa khung và hàng phát, khung co lại 44 (board
  chưa vẽ trạng thái bật).

## 2. Hàng phát, hàng công cụ timeline, dải tổng quan

iPad kiểu Mac tách 15 nút transport thành **hai hàng** (chốt 2026-10-04); Duo trong giữ một hàng 36 như cũ.

| Nhóm | Nút | iPad: ở đâu | Duo trong |
|---|---|---|---|
| Phát | Go to Start · Back a Frame · **Play** (đĩa 48 nền trắng 12%) · Forward a Frame · Go to End · Loop Playback | **hàng phát dưới khung**: ngang y 530–578 (x 538–816), dọc y 610–658 (x 355–633); nút 44 | hàng transport, nút 36 |
| So sánh | Before and After ([15](15-before-after.md)) | cuối hàng phát, mép phải khung: x 956 (ngang) / 960 (dọc), 44 | đĩa nổi trên khung |
| Sửa tại playhead | Split at Playhead · Freeze Frame · Trim Start to Playhead · Trim End to Playhead · Delete Clip | **hàng công cụ timeline** y 596 (ngang) / 672 (dọc), từ x 16, nút 44 cách 2 | hàng transport |
| Marker | Previous Marker · Add Marker · Next Marker | hàng công cụ timeline, sau một vạch ngăn, x 263–399 | hàng transport |
| Nhìn | timecode `0:08.4 / 0:24.0` mono 17 + Fit Timeline to Window 44 | đầu phải hàng công cụ timeline (Fit x 1316 / 972) | hàng transport |

- Nhóm "sửa tại playhead" tác động **clip dưới playhead**, không phải item đang chọn — đó là việc của hàng lệnh.
- **Loop là trạng thái phiên**, không vào project. Timecode đếm đúng nhịp render (30 khung).
- iPad: hai hàng luôn đủ chỗ (hàng phát 278 trong sân khấu 680; hàng công cụ chạy hết bề ngang) nên không còn ngưỡng
  780 rơi về hàng hẹp. Cửa sổ compact vẫn là hàng hẹp của điện thoại ([07 §2](07-phone-layout.md)).
- **Dải tổng quan** 22 (x 208 tới mép phải trừ 16, ngay dưới hàng công cụ): cả project trên một dải, mỗi clip một
  khối, playhead đỏ `#FF453A` 2pt, khung trắng 50% là phần timeline đang nhìn, chấm marker; kéo để seek. Cần vì ở mức
  zoom làm việc chỉ thấy vài giây.

## 3. Đồng hồ đo mức

- iPad: cột **44** (hai bar 6 cách 3 + thang dB 26) ngay phải khung, cách 10, **cao bằng khung** (340 ngang, 524
  dọc). Bỏ bậc 32 "chỉ bar khi sân khấu < 820": sân khấu iPad ngang có pool chỉ còn 680 mà board vẫn vẽ thang.
  Duo trong không có meter.
- Đọc **chính bản mix của recipe tại playhead**: đường bao đỉnh stereo từng clip (không normalize) × âm lượng ×
  mute, cộng năng lượng với đường bao từng bản nhạc, × đường fade — **đúng đường fade export ghi ra** — ra dBFS.
- Không dùng waveform của lane nhạc: cái đó normalize để lấp lane nên bản to và bản nhỏ vẽ giống nhau.
- Thang **tuyến tính theo dB**: sàn −54, vàng từ −18, đỏ từ −6; gradient được mask chứ không co.
- Đọc được cả khi dừng và khi scrub — thứ một bộ nghe lén lúc phát không làm được.

## 4. Track header và lane

| | iPad (ngang, dọc) | Duo trong |
|---|---|---|
| Cột trái | **track header 200**: thẻ 192 bo 8 ở x 8 (nền `trackChip`) — badge `T1`/`V1`/`A1` 30×22 · tên 15 (62 rộng) · **Lock** 40×44 · **Mute** 40×44 (lane chữ chỉ Lock, ở x 156); lane bắt đầu x 208 | **cột badge 100**: lề 6 · badge 26 · khe 4 · **Lock** 28 · khe 4 · **Mute** 28 · lề 4; không tên |
| Lane chữ / video / nhạc | **44 / 104 / 52**, cách 4; lane nền `emptyLane` bo 6 | 34 / 66 / 40 |
| Lane phụ đề C1 ([14](14-captions.md)) | 44, khối cao bằng lane | 34 (khối 28) |
| Thumbnail clip | 88 rộng | 54 rộng |
| Thước | **28** | 33 |

- **Duo trong có Lock và Mute** (chốt 2026-10-03): đĩa 28 nền trắng 10%, glyph 13, vùng chạm 32 rộng × cao lane
  (lane chữ 34 vẫn đủ); lane chữ chỉ có Lock. *Vì hàng transport Duo không có ⋯ — bỏ hai nút là Lock/Mute không tới
  được trên Duo trong, trái luật đủ mọi chức năng.* Cột rộng thêm 36pt so với board cũ: board DI* vẽ lại.
- **Lock là trạng thái phiên**: chặn chọn và mọi thao tác kéo trong lane; khoá lane chứa item đang chọn = ✓.
- **Mute lane Video** đi qua âm lượng và nhớ mức cũ (0 là mức chỉnh được nên không suy mute từ âm lượng).
  **Mute lane nhạc** đặt 0 cho mọi track trong lane trong **một** bước undo. Lane chữ không có Mute.
- Thumbnail xin theo **chiều cao ô × scale màn** (sàn 240px) — ô 88pt ở 3× cần 264px.
- Nửa trái ở mốc 0 không để trống: thước kẻ đường nền hết bề rộng, rail rỗng từng lane phía sau.
- **Tay nắm chia sân khấu / timeline** (iPad, grabber 36×4 giữa hàng phát và hàng công cụ: y 586 ngang, 662 dọc):
  0…400pt thêm cho timeline, mặc định 0; có hành động trợ năng bước 40pt.

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
| AC-3 | iPad ngang 1376×1032 | dump hàng phát và hàng công cụ timeline | hàng phát y 530–578: 6 nút phát (Play 48, các nút 44) + Before and After 44 ở x 956; hàng công cụ y 596–640: 5 nút sửa · 3 marker · timecode `0:08.4 / 0:24.0` · Fit 44 ở x 1316; đủ 15 nút của §2, không nút nào ngoài mép | ✅ (iPad) `VideoStudioDeskLayoutTests.theTwoDeskRowsCarryFifteenControls` (lặp `VideoTransportControl.allCases`: hàng phát 6, hàng công cụ 9, mỗi nút đúng một hàng; nhóm phát 278), `deleteInTheTransportRemovesTheClipUnderThePlayhead` (clip 1 chọn, playhead ở clip 2 → clip 2 mất), `VideoStudioDeskGeometryTests.iPadLandscapeIdle` (hàng phát 530, hàng công cụ 596 hết bề ngang); `Tools/design-board compare` `IL1_Main` / `IP1_Main` với dump `ipad-vs-landscape.json` / `ipad-vs-portrait.json` 2026-10-05 (khối M, M8): Go to Start…Loop, Play 48, Before and After, Split…Delete, 3 marker, Fit — 0 phần tử lệch quá 2pt; Play nền trắng 12% chữ trắng; timecode `0:00.0 / 0:38.3` mono 17. · Duo trong (task 16, 2026-10-05): `theTransportRowHasFifteenControlsInFourGroups` (một hàng 40, nút 36 cách 2, lề 36, nhóm phát giữa cửa sổ) + `Tools/design-board compare` `DI1_Main` với dump bản đứng thay 951×669 trên iPad (`duo-vs-inner-standin.json`): 15 nút từ Split (36, 387) tới Fit (755.7, 387) — 0 nút lệch quá 2pt; Play trắng 12%, Delete theo playhead, timecode `0:00.0 / 0:38.3` dùng chung với iPad |
| AC-4 | iPad, lane V1 Volume 60 | bấm Mute lane rồi bấm lại | lần 1 không tiếng; lần 2 về 60 | `VideoStudioTrackSwitchTests.mutingTheVideoLaneRestoresItsLevel` |
| AC-5 | iPad, 2 track nhạc trong A1 | bấm Mute A1 rồi Undo một lần | cả hai về mức cũ | `VideoStudioTrackSwitchTests.mutingAMusicLaneUndoesInOneStep` |
| AC-6 | clip 2 đang chọn, Speed đổi 2×, bàn phím cắm | bấm Esc rồi ⌘Z | sau Esc: bỏ chọn, Speed vẫn 2×; sau ⌘Z: 1× | `VideoStudioTrackSwitchTests.escapeKeepsTheChangeAndUndoRevertsIt` (gọi `pressEscape()`, hành động duy nhất của phím Esc) |
| AC-7 | iPad ngang, pool tab Music | dump | dòng "Video sound" ở đầu, nút "Add Music from Files…" (không phải "Import from Files…") | ✅ `VideoStudioDeskLayoutTests.thePoolHasFourTabsInOrder` (Media · Text · Stickers · Music) + route `ipad-vs-pool-music.json` 2026-10-05 (bố cục kiểu Mac, M3), iPad Pro 13" ngang: tab Music — "Video sound" ở y 121 (đầu tab), "Add Music from Files…" 294×44 ở (21, 181), "My Music" Title Case ở y 242; không có "Import from Files…"; tab Text: Add Text 294×44 ở (21, 121), "Fonts You Used" ở y 184, dòng trống | |
| AC-8 | Duo trong 951×669 | dump timeline | cột badge 100 có nút Lock ở T1 · V1 · A1 và Mute ở V1 · A1; lane 34 / 66 / 40 | ⚠️ một phần — số: `VideoStudioLayoutTests.eachWindowClassGetsItsLaneTier` (bậc lane theo lớp cửa sổ, iPhone 40/80/46 là `Lanes.phone`), `VideoStudioDeskLayoutTests.duoInnerGutterIsA100ptBadgeColumnWithLockAndMute` (6·26·4·28·4·28·4, vùng chạm 34–66 / 66–98, nhãn Lock Text/Video/Music 2, Mute Video); dump bản đứng thay 951×669 trên iPad (`duo-vs-inner-standin.json`): Lock Text/Video/Music ở x 34 rộng 32, Mute Video ở x 66, cao bằng lane 34/66/40; **dump trên Duo thật chưa có**: sim Duo boot ở trạng thái gập |
| AC-9 | các board `IL1_Main`, `IP1_Main` (iPad kiểu Mac), `DI1_Main` | `Tools/design-board compare` hàng phát, hàng công cụ timeline, dải tổng quan, track header | lệch ≤ 2pt | ⚠️ một phần — iPad (khối M, M8–M9): `VideoStudioDeskLayoutTests.theDeskTrackHeaderIs200WithLockAndMute44` (thẻ 192 ở x 8, badge 30×22, tên 62, Lock/Mute 40×44; lane từ x 208, thước 28, lane 704 / 752 / 860 / 916), `theDeskMeterIsAsTallAsTheFrame`, `theTwoDeskRowsCarryFifteenControls`; `Tools/design-board compare` `IL1_Main` và `IP1_Main` với dump `ipad-vs-landscape.json` / `ipad-vs-portrait.json` 2026-10-05: hàng phát, hàng công cụ timeline, track header (T1 16/715, Lock Text 156/704, Lock Video 116/782, Mute Video 156/782) — 0 phần tử lệch quá 2pt; còn lại chỉ là nội dung mẫu của board (Music 2, nhãn viewer, marker). `DI1_Main` (Duo trong): chờ task 17–18 | |

**Chưa chứng minh được:** AC-9 (Duo trong: track badge/lane; DI1 trên máy Duo thật).

## 7. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| board IL4 ghi "Import from Files…", các board khác "Add Music from Files…" | một hành động một tên: "Add Music from Files…"; sửa IL4 |
| hai nhóm Trim to Playhead (transport và hàng lệnh) tác động hai clip khác nhau | nhãn transport ghi rõ "at Playhead"; hàng lệnh chỉ sửa item đang chọn |
| iPad kiểu Mac: hàng công cụ timeline (Split/Trim at Playhead) và hàng lệnh của inspector (Split/Trim) cùng hiện trên màn | như trên — hai chỗ, hai đích (playhead vs item chọn); nhãn VoiceOver giữ "at Playhead" |
| board kiểu Mac chưa vẽ Quick Adjust bật | đặt dải 44 trong sân khấu (§1); vẽ board trước `design-parity` |
