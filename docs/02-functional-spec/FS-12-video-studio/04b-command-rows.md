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
| AC-10 | các board P2, P3, P5, P9, P10, IL2–IL4, IP2, IP3, DI2, DI3, DC2, DC3 | `Tools/design-board compare` hàng lệnh với dump app | mọi ô lệnh lệch ≤ 2pt | ⚠️ một phần — phone: so mắt render `P2_ClipSelected` (Tools/design-board) với sim-shot iPhone 17 2026-10-04: ô 64×56, nhãn 10/500, khe 4, đệm 10, Delete đỏ cuối, hàng là đầu panel — khớp; **không có số đo**: XCUITest không liệt kê cây Video Studio trên phone nên không dump được để `design-board compare`. P9/P10 (9:16) chờ khối E; IL2–IL4, IP2, IP3 (vẽ lại kiểu Mac 2026-10-04: hàng ở inspector y 80 / dock + 9), DI2, DI3, DC2, DC3 chờ plan màn rộng |
| AC-11 | clip 1 ảnh 3,0 s, clip 2 video 6,2 s | chọn từng clip, dump phần nội dung | clip 1: dòng Duration có slider 0,5–10 s; clip 2: không phần tử nào tên "Duration", dòng phụ ở tên ghi "6.2s · video" | ⚠️ một phần — `VideoClipPanelSectionsTests.videoClipHasNoDurationSection`, `photoClipKeepsDuration`; sim-shot iPhone 17: clip video Speed (0.5× 1× 2× 4×) · Volume · Fade, không Duration, dòng phụ "2.0s · video"; clip ảnh Duration · Fade · Motion (2026-10-04). Duo/iPad chờ plan màn rộng |
| AC-12 | clip 2 đang chọn | Replace → chạm một ô → ✕ | Media chọn một mở trong panel clip; một chạm thay clip 2, Media đóng, clip 2 vẫn chọn; ✕ trả clip cũ | `VideoStudioMediaSessionTests.replaceViaSinglePickStaysInTheClipSession` + ảnh sim `vs3/out/rp` |

**Chưa chứng minh được:** AC-1, AC-2, AC-9, AC-10, AC-11.

## 8. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| board IL2 và IP2 thiếu ô Look trong hàng clip, P2/DI2/DC2 có | luật §1 thắng: một danh sách — bản kiểu Mac 2026-10-04 đã vẽ ô Look ("Look for this clip") trước Delete |
| board P3 vẽ ô Edit, code hiện nói "không có Edit" | theo board: Edit cuộn ô nhập chữ lên đầu và mở bàn phím |
