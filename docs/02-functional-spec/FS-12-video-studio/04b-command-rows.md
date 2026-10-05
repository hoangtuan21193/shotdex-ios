# FS-12.04b — Hàng lệnh của item đang chọn

`FS-12.04b` · `Features/VideoStudio/VideoStudioCommandBand.swift` · `VideoStudioSheetHost.swift`
· cập nhật 2026-10-04 (iPad kiểu Mac) · nguồn intent [video-studio-canvas-chrome](../../_intents/2026-10-03-video-studio-canvas-chrome.md)

**Một câu:** chọn một item thì lệnh của nó là **hàng đầu tiên của panel** — ô 64×56, cuộn ngang, xếp theo tần
suất dùng, **Delete đỏ đứng cuối** — và phần dưới là thông số của item.

Mô hình chọn (✕ · tên · ✓): [04 §5](04-tools-and-inspector.md).

## 1. Quy tắc

- **Một danh sách lệnh cho mỗi loại item, mọi thiết bị đọc chung.** iPad không có lệnh nào iPhone thiếu và
  ngược lại — kiểm bằng cách lặp danh sách.
- **Thứ tự = tần suất dùng**, không theo nhóm chức năng. **Delete luôn cuối**, màu `timelineDestructive` `#FF6B5E`.
- Không có nút Delete nào khác cho item (không thùng rác trên hàng tiêu đề).
- **Lệnh không áp dụng cho loại item thì ẩn**, không mờ; thứ tự phần còn lại giữ nguyên.
- Một hàng cuộn ngang ở mọi bề rộng, kể cả cột 264 của Duo trong — không gập thành lưới.
- **Mute không phải một lệnh**: là nút loa ở đầu dòng Volume.

## 2. Ô lệnh

| Thuộc tính | Giá trị |
|---|---|
| Ô | **64×56**, bo `r-cell` 10, icon trên + nhãn 10pt weight 500, khoảng icon–nhãn 5 |
| Hàng | đệm ngang 10, khoảng giữa ô 4, cao 56; mép phải có dải mờ 32pt về màu panel |
| Đang bật | nền trắng 14% |
| Không làm được lúc này | glyph trắng 28%, có chú thích ở dòng dưới hàng (vd. "Waiting for iCloud") |
| Ngăn dưới hàng | đường kẻ 1pt trắng 7%, cách hàng 6, cách nội dung 4 |

Vị trí hàng: iPhone y panel + 10; Duo ngoài panel + 6; Duo trong cột phải + 12; iPad ngang inspector x + 13, y 80
(ngay dưới hàng capsule toolbar, rộng 336 — thấy 5 ô, cuộn); iPad dọc dock + 9 (rộng 1000, đủ cả hàng, không cuộn)
— số iPad theo canvas kiểu Mac 2026-10-04 ([03 §2–§3](03-timeline-and-desk-layout.md)).

## 3. Lệnh từng loại item

| Item | Hàng lệnh |
|---|---|
| **Clip video** | Split · Trim · Speed · Volume · Replace · Freeze · Duplicate · Look · Delete |
| **Clip ảnh** | Split · Trim · Replace · Duplicate · Look · Delete |
| **Khung freeze** | Split · Trim · Duplicate · Look · Delete |
| **Chữ** | Edit · Font · Color · Style · Align · Animate · Duplicate · Delete |
| **Sticker** | Animate · Duplicate · Delete |
| **Nhạc** | Beats · Ducking · Replace · Add Track · Duplicate · Delete |

- *Sticker không có board:* dời, phóng, xoay đã làm trực tiếp trên khung; ba lệnh là đúng những gì còn lại.
- **Rotate** chỉ có ở chế độ **một video** (Photo Detail → Edit, [01](01-render-and-export-pipeline.md) bảng lối vào):
  ô Rotate đứng ngay trước Delete của clip video; project nhiều clip không có ô này (chốt 2026-10-03).
- Beats thuộc [12](12-beats.md), Ducking thuộc [13](13-audio-ducking.md); chưa làm thì ẩn, thứ tự còn lại giữ.
- Chế độ Trim từng khung đổi đầu hàng thành −1 Frame · +1 Frame · Frame Zoom · Trim ([17](17-precise-trim-and-input.md)).
- Look của clip mở khối **LOOK FOR THIS CLIP** ([06c §3](06c-photo-looks.md)).

## 4. Hai kiểu lệnh

| Kiểu | Lệnh | Chạm |
|---|---|---|
| **Mục** | Trim · Speed · Volume · Look · Edit · Font · Color · Style · Align · Animate · Beats · Ducking | sáng ô; khối của nó lên đầu phần nội dung; chạm lại = tắt, nội dung về đầu |
| **Hành động** | Split · Replace · Freeze · Duplicate · Add Track · Delete | làm ngay một lần, không sáng ô |

- Trim có khối riêng: hai chip **Start to Playhead** · **End to Playhead** (cao 30, bo 8) + dòng "Or drag the
  clip's edges on the timeline." 11pt — [05 §3](05-cutting-markers-and-fades.md). Các dòng chung theo sau.
- **Ngoại lệ Duo trong** (chốt 2026-10-03): ô Trim **vào thẳng chế độ Trim từng khung** ([17 §4](17-precise-trim-and-input.md),
  board `F6_DI_TouchTrim`), cột phải **không** có hai chip Start/End to Playhead — transport bàn dựng Duo đã có
  Trim Start/End to Playhead và 669pt không dư một hàng.
- Speed, Volume, Edit, Font, Color, Style, Align, Animate cuộn dòng/nhóm của mình lên đầu; không có khối riêng.
- Phần nội dung mặc định của clip video: Speed (chip 0.5× 1× 2× 4×) · Volume · FADE (Fade in, Fade out) · MOTION
  (chip hiệu ứng) — **không có dòng Duration** (chốt 2026-10-03, [05 §3](05-cutting-markers-and-fades.md)).
- Ảnh và khung freeze: Duration (slider 0,5–10 s) · FADE · MOTION.
- **iPad (kiểu Mac, 2026-10-04): chọn một trong nhiều là nút pop-up**, không phải lưới chip — cùng lựa chọn, cùng
  thứ tự với iPhone/Duo (chúng giữ chip):
  - **MOTION**: "Motion: Zoom In ⌃⌄" cao 44, hết bề rộng cột (328 ngang · 312 dọc), mở menu 10 hiệu ứng (None · Zoom In ·
    Zoom Out · Pan Left · Pan Right · Shake · Blur In · Blur Out · Soft Glow · Vignette Pulse).
  - Chữ: **Font** "Font: SF Pro" 328×44 (dọc 212×44, cạnh B · I 44); **Animate** hai pop-up "Animate In: Fade" ·
    "Animate Out: None" 160×44 (dọc 152×44). Ô chữ 328×44 + nút Expand Text Field 44; Align là segmented 180×36;
    ô màu 44; Size · Opacity · Outline · Shadow là dòng slider 44.
  - Tiêu đề mục viết Title Case ("Fade", "Motion", "Style") thay chữ hoa; slider 44 với núm 28; segmented 36.
  - **Dòng thông số kiểu Mac** (chốt 2026-10-05, board `IL2_ClipSelected`/`IP2_ClipSelected`, áp cho mọi dòng slider của
    inspector/dock iPad — clip, nhóm chữ, Ducking): nhãn **17** thường ở cột **96**, slider rãnh 4 · vệt trắng 75 % · núm
    trắng **28**, số **15** chữ phụ ở cột **60** (cách slider 4) — dòng **44**. **Speed** = slider 0,25–4× rồi segmented
    **0.5× · 1× · 2× · 4×** cao 36 (ô 32, bo 12, ô chọn nổi) bắt đầu ở cột slider (rộng 232 ngang · 216 dọc), **không**
    phải chip. **Volume**: nút loa **tròn 40** (đĩa 28 nền trắng 10 %) rồi "Volume" ở cột 84. Clip: "Fade in" / "Fade out"
    dưới tiêu đề **Fade** 15 đậm cao 28 (dock 24); **Motion** cũng vậy. Hàng màu của chữ: **7 ô 44** — White · Black ·
    #F2C94C · #E8604C · #4FA3E0 · #7BC47F · Custom Color (bảng màu hệ thống) — đĩa 30, ô chọn có vòng trắng 2pt cách 2pt.
    Code: `VideoDeskInspectorRows.swift` (`DeskSliderRow`, `DeskVolumeRow`, `DeskSpeedPresets`, `DeskSwatchRow`).
    **iPhone và Duo giữ** dòng slider chung `EditorValueSlider` (`InspectorSlider`, nhãn hoa, cao 34) và chip Speed.
- **iPad: khối chữ hiện mọi mục cùng lúc** (người dùng chốt 2026-10-05, board `IL3_TextOverlay`, `IP3_TextOverlay`)
  — không phải một công cụ một lúc như iPhone và Duo (hai máy này giữ luật "Mục" ở bảng trên). Chỉ chữ; sticker giữ
  như cũ (Size · Opacity · Starts at, Animate là mục).
  - **Inspector ngang** (cột 360, cuộn): ô chữ 328×44 + Expand 44 (y 150) · Font 328×44 (202) · Align segmented
    180×36 + B · I 44 cạnh nó (254) · Size (298) · Opacity (342) · **Color** 28 + hàng màu (392) · **Style** 28:
    Outline, màu viền khi Outline > 0, Shadow, Blur khi Shadow > 0 (472) · **Animate** 28: In · Out 160×44, In
    time / Out time khi khác None (596) · rồi **Spacing** (Tracking, Line spacing) và Starts at — phần board không vẽ
    nằm **sau** các hàng board vẽ, để không đẩy hàng nào của board.
  - **Dock dọc** (ba cột 312, thấy hết): cột 1 ô chữ 312×44 · Font 212×44 + B · I · Size · Starts at │ cột 2 Color
    24 + hàng màu · Align 180×36 · Opacity · Tracking · Line spacing │ cột 3 Style 24 · Outline · Shadow · In · Out
    152×44. Cột nào dài hơn 187 thì cuộn riêng.
  - Pop-up Animate ghi ngắn "In: Fade" · "Out: None" (hai nút cùng hàng); VoiceOver vẫn đọc "Animate In: Fade".
    Ba ô Align đọc "Align Left" · "Align Center" · "Align Right".
  - Ô lệnh vẫn sáng như luật "Mục"; chạm Font/Color/Style/Align/Animate ở **inspector ngang** đưa mục đó lên đầu
    cột (cuộn, không thay nội dung); **Edit** đặt con trỏ vào ô chữ (bàn phím lên). Ở dock mọi mục đã thấy, chạm chỉ
    làm sáng ô (Edit vẫn mở bàn phím).
- Khối Trim trên iPad: hai nút **Start to Playhead** · **End to Playhead** 238×44 (dọc, cột đầu của dock — board
  `F6_IP_PencilTrim`) thay chip 30.
- **Split** = ✓ cho clip đang chọn, cắt tại playhead, mở phiên mới trên nửa phải — ✕ của nửa phải không gỡ vết
  cắt. *Vì Split là sửa cấu trúc như Delete, không thuộc phiên của một item.*
- **Duplicate** = ✓ cho item gốc, chèn bản sao ngay sau nó, chọn bản sao; ✕ gỡ bản sao.
- **Replace** mở Media ở chế độ chọn một ([09 §5](09-media-panel.md), chốt 2026-10-04) ngay trong panel của clip: một chạm thay clip và đóng Media; Cancel không đổi gì; việc thay là một bước trong phiên ✕ / ✓ của clip — ✕ trả clip và nguồn cũ. Không dùng trình chọn ảnh của hệ thống.
- **Delete** của clip mờ khi project chỉ còn 1 clip (project luôn còn ít nhất một clip).

## 5. Nút loa ở dòng Volume

- Đĩa 26pt nền trắng 10% (iPad kiểu Mac: **40**) ở đầu dòng Volume của clip video và của nhạc; nhãn trợ năng "Mute" / "Unmute".
- Bật Mute: glyph loa gạch, slider mờ 30% nhưng **giữ số** — tắt Mute trả đúng mức cũ. Mỗi lần chạm một bước undo.

## 6. Panel không đổi chiều cao

Chiều cao panel đặt theo thiết bị (và tỉ lệ project trên iPhone), không theo item hay lệnh đang bật:
iPhone 340 / 320 / 300 / 278 / 360 / 340 cho 16:9 / 1:1 / 4:5 / 9:16 / 4:3 / 21:9 ([07](07-phone-layout.md)) · Duo ngoài
334–644 · Duo trong cột 385 · iPad ngang inspector 440 (y 80–520, trên chân 64 — cột 360 cao 584) · iPad dọc dock 324 (nội
dung 1052–1312, trên chân 64). Nội dung dài hơn thì cuộn, có dải mờ
30pt ở đáy và thanh cuộn 3×70. Thu còn 78 bằng grabber (iPhone không lát, Duo ngoài) là việc của người dùng, không
của lệnh ([07 §3](07-phone-layout.md)).

## 7. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | clip 2 là video | chọn clip 2, dump hàng lệnh | đúng 9 ô theo thứ tự §3, Delete cuối, chữ `#FF6B5E` | ⚠️ một phần — `VideoItemCommandsTests.videoClipRowIsTheSpecOrder` (thứ tự §3, Delete cuối đỏ, Rotate chỉ ở chế độ một video); Look của clip đã bật (FS-12.06c task 14, 2026-10-05): hàng đủ 9 ô; sim-shot hàng lệnh clip ảnh iPhone 17 (2026-10-04), có Look: `build/proofs/fs1206c/t14-phone-s2-clip-look.png` |
| AC-2 | clip 1 là ảnh | chọn clip 1 | Split · Trim · Replace · Duplicate · Look · Delete; không có ô Speed/Volume/Freeze | ⚠️ một phần — `VideoItemCommandsTests.photoRowHasNoSpeedVolumeFreeze`; ảnh iPhone 17 (2026-10-05): Split · Trim · Replace · Duplicate · Look · Delete — `build/proofs/fs1206c/t14-phone-s2-clip-look.png` |
| AC-3 | danh sách lệnh của cả 6 loại item | lặp qua iPhone, Duo ngoài, Duo trong, iPad ngang, iPad dọc | mỗi bố cục ra đúng cùng danh sách (so phần tử, không đếm) | ✅ `VideoItemCommandsTests.everyLayoutGetsTheSameCommands` (lặp `VideoStudioWindowClass.allCases` × 6 loại item, so phần tử với phone; một hàng cuộn mọi bề rộng — `VideoCommandBand` dạng lưới đã bỏ) |
| AC-4 | iPhone, clip 2 đang chọn, panel 340 | chạm Trim | ô Trim nền trắng 14%; hai chip Start/End to Playhead ở đầu nội dung; panel vẫn 340 (±0pt) | ✅ `VideoItemSectionTests.trimTogglesItsBlock`; sim-shot iPhone 17: ô Trim nền trắng 14%, hai chip Start/End to Playhead + "Or drag the clip's edges on the timeline." đầu nội dung, panel giữ cao (chiều cao panel là hằng của cửa sổ) (2026-10-04) |
| AC-5 | như AC-4 | chạm Trim lần nữa | hai chip biến mất; nội dung bắt đầu bằng Speed | ✅ `VideoItemSectionTests.tappingTrimAgainReturnsToSpeed` (chạm lại Trim: tắt, nội dung về Speed; Volume sáng thì dòng Volume lên đầu) |
| AC-6 | clip 2 Volume 80 | chạm loa rồi chạm lại | lần 1: không tiếng, slider vẫn 80, mờ; lần 2: về 80; hai bước undo | ✅ `VideoMuteSpeakerTests.muteKeepsTheLevelAndUndoesStepwise` (lần 1 im, giữ 80; lần 2 về 80; hai bước undo; nhạc như vậy); sim-shot iPhone 17: đĩa loa đầu dòng Volume của clip video (route `video-studio-video-clip.json`, 2026-10-04) |
| AC-7 | clip 10,0 s đang chọn, playhead 4,0 s | chạm Split rồi ✕ | còn 2 clip `[0,0–4,0]` `[4,0–10,0]`, không chọn gì | ✅ `VideoSplitDuplicateTests.splitThenCancelKeepsTheCut` (còn [0–4] [4–10], không chọn gì) |
| AC-8 | băng chữ GOLDEN HOUR đang chọn | chạm Duplicate rồi ✕ | còn đúng 1 khối GOLDEN HOUR, không chọn gì | ✅ `VideoSplitDuplicateTests.duplicateThenCancelLeavesOneBlock` (còn 1 khối GOLDEN HOUR, không chọn, không bước undo), `duplicateClipInsertsAfterAndSharesTheSource` (clip chèn ngay sau, chung nguồn; nhạc bắt đầu ở cuối bản gốc) |
| AC-9 | Duo trong 951×669, clip 2 đang chọn | vuốt hàng lệnh sang trái | ô Delete hiện đủ trong cột 264, không gập thành lưới | ⚠️ chưa có |
| AC-10 | các board P2, P3, P5, P9, P10, IL2–IL4, IP2, IP3, DI2, DI3, DC2, DC3 | `Tools/design-board compare` hàng lệnh với dump app | mọi ô lệnh lệch ≤ 2pt | ⚠️ một phần — phone: so mắt render `P2_ClipSelected` (Tools/design-board) với sim-shot iPhone 17 2026-10-04: ô 64×56, nhãn 10/500, khe 4, đệm 10, Delete đỏ cuối, hàng là đầu panel — khớp; **không có số đo**: XCUITest không liệt kê cây Video Studio trên phone nên không dump được để `design-board compare`. P9/P10 (9:16) chờ khối E; IL2–IL4, IP2, IP3 (vẽ lại kiểu Mac 2026-10-04: hàng ở inspector y 80 / dock + 9), DI2, DI3, DC2, DC3 chờ plan màn rộng · **iPad kiểu Mac (khối M, M4–M10, 2026-10-05)**: dump `ipad-vs-select.json` / `ipad-vs-popups.json` trên iPad Pro 13": hàng lệnh clip ngang Split…Delete 64×56 từ (1029, 80) — khớp `IL2_ClipSelected` 0pt; dọc từ (16, 1061) — khớp `IP2_ClipSelected`; chọn một trong nhiều là pop-up 44: "Motion: None" 328×44, "Font: System" 224×44 + B · I 44, "Animate In" · "Animate Out" 160×44 (`VideoClipPanelSectionsTests.iPadMotionIsAPopUpWithEveryEffect` — một danh sách cho chip phone và pop-up iPad); tiêu đề mục Title Case. Bảng chữ iPad vẽ mọi mục cùng lúc (IL3/IP3) — app theo từ 2026-10-05 (§4, AC-13) |
| AC-11 | clip 1 ảnh 3,0 s, clip 2 video 6,2 s | chọn từng clip, dump phần nội dung | clip 1: dòng Duration có slider 0,5–10 s; clip 2: không phần tử nào tên "Duration", dòng phụ ở tên ghi "6.2s · video" | ⚠️ một phần — `VideoClipPanelSectionsTests.videoClipHasNoDurationSection`, `photoClipKeepsDuration`; sim-shot iPhone 17: clip video Speed (0.5× 1× 2× 4×) · Volume · Fade, không Duration, dòng phụ "2.0s · video"; clip ảnh Duration · Fade · Motion (2026-10-04). Duo/iPad chờ plan màn rộng |
| AC-12 | clip 2 đang chọn | Replace → chạm một ô → ✕ | Media chọn một mở trong panel clip; một chạm thay clip 2, Media đóng, clip 2 vẫn chọn; ✕ trả clip cũ | `VideoStudioMediaSessionTests.replaceViaSinglePickStaysInTheClipSession` + ảnh sim `vs3/out/rp` |
| AC-13 | iPad 13" (inspector ngang 360; dock dọc 1032×1376), khối chữ GOLDEN HOUR đang chọn | `Tools/design-board compare` IL3/IP3 với dump app | ô chữ, Font, B, I, Align, Size, Opacity, Color, Style, Outline, Shadow, Animate In/Out đều có, lệch ≤ 2pt; mọi mục thấy cùng lúc, không cần chạm ô lệnh | ⚠️ một phần — dock dọc trên iPad Air 13" (1024×1366, sim clone 26.5; board là iPad Pro 1376): `build/proofs/fs1204b-text-dock-portrait.png` — ba cột thấy hết (ô chữ · Font: System + B · I · Size · Starts At │ Color · hàng màu · Align · Opacity · Tracking │ Style · Outline · Shadow · In · Out); `compare --offset-y 10` (bù chiều cao máy): hàng lệnh, B, I, Align, Animate Out khớp x, **lệch y −4 đều** — cột dock bắt đầu ở y 1125 theo FS-12.03 §3, board IP3 vẽ 1129 (cùng lệch đã ghi ở FS-12.03 AC-10 (f)). Còn lệch là phần của hàng thông số clip đang làm riêng: slider vẫn là hàng chung `EditorValueSlider` (nhãn hoa, cao 34 trong ô 44), hàng màu 9 chấm 26 thay 7 ô 44 + Custom Color. **Inspector ngang chưa chụp**: bước `orientation` của driver không xoay được sim clone iPad Air 13, sim iPad Pro mới tạo treo lúc cài (máy quá tải); `1AEFA523` là của phiên khác **Inspector ngang (2026-10-05, iPad Pro 13" `1AEFA523`, route `video-ipad-landscape-proofs.json`, `build/proofs/fs1204b/il3-text-inspector-landscape.png`)**: mọi mục thấy cùng lúc — ô chữ, Font, Align, B, I, Size, Opacity, Color, Style (Outline, Shadow), Animate; `compare` IL3: Align, B 1224,250 · I 1272,250 44, 7 ô màu từ 1025,420 cách 46 và Custom Color lệch ≤ 1pt; slider giờ là dòng kiểu Mac (`DeskSliderRow`) và hàng màu 7 ô 44 (`DeskSwatchRow`). Khác board chỉ ở nhãn: app đọc "Bold"/"Italic" và tên màu (White · Black · Yellow · Red · Blue · Green) thay "B"/"I"/mã hex |
| AC-14 | iPad, khối chữ đang chọn; iPhone, cùng khối | chạm Align ở iPad; chạm Align ở iPhone | iPad: ô Align sáng, mọi mục vẫn hiện (ngang: Align lên đầu cột); iPhone: chỉ phần Align như trước | ⚠️ một phần — `VideoDeskTextPanelTests.everyTextCommandHasItsOwnSection` (mỗi ô lệnh chữ có đúng một mục để đưa lên, không ô nào là chạm chết; Spacing là mục duy nhất không ô lệnh nào gọi); ảnh dock `build/proofs/fs1204b-text-dock-align-lit.png` (Align sáng, ba cột không đổi). Cuộn lên đầu ở inspector ngang chưa chụp (như AC-13); iPhone/Duo không đổi code (`VideoStudioSheetHost.textParams` chỉ rẽ khi `isDesk`) **Inspector ngang** (cùng route, `build/proofs/fs1204b/il3-text-align-lit-landscape.png`): chạm Align → ô Align sáng, cột cuộn để Align lên đầu, mọi mục vẫn hiện |

| AC-15 | iPad 13" ngang, clip 2 (video) đang chọn; cùng clip trên iPhone | `Tools/design-board compare` IL2 với dump app; mở panel clip trên iPhone | iPad: Speed là slider + segmented 0.5× 1× 2× 4× (không chip), Volume có loa tròn 40, Fade in / Fade out dưới "Fade", nhãn 17 — mọi dòng lệch ≤ 2pt; iPhone: hàng slider chung và chip như trước | ✅ iPad ngang (route `video-ipad-landscape-proofs.json`, iPad Pro 13" `1AEFA523`, 2026-10-05, `build/proofs/fs1204b/il2-clip-rows-landscape.png`): Speed 1128,150 168×44 · Speed Presets 1128,196 232×36 (ô 56×32) · Mute 1026,240 40×40 · Volume 1156,238 140×44 · Fade in 1128,318 · Fade out 1128,362 — lệch ≤ 1pt so với `IL2_ClipSelected` (chỉ khác nội dung "Motion: None" vs board "Zoom In"). iPhone/Duo: nhánh `phoneClipSection` không đổi. ⚠️ dock dọc `IP2`: sim không xoay sang dọc trong lượt này (bước `orientation` của driver), chưa so |

**Chưa chứng minh được:** AC-1, AC-2, AC-9, AC-10, AC-11; AC-15 ở dock dọc (2026-10-05).

## 8. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| board IL2 và IP2 thiếu ô Look trong hàng clip, P2/DI2/DC2 có | luật §1 thắng: một danh sách — bản kiểu Mac 2026-10-04 đã vẽ ô Look ("Look for this clip") trước Delete |
| board P3 vẽ ô Edit, code hiện nói "không có Edit" | theo board: Edit cuộn ô nhập chữ lên đầu và mở bàn phím |
