# FS-12.11 — Chọn nhiều clip và đổi thứ tự

`FS-12.11` · tier D · `Features/VideoStudio/VideoStudioModel.swift` (chọn, dời, xoá clip) · `VideoTimelineScroller.swift`
(giữ-rồi-kéo) · `Domain/Video/VideoTimelineMath.swift` (điểm thả) · nguồn intent
[video-studio-canvas-chrome](../../_intents/2026-10-03-video-studio-canvas-chrome.md) F1 · cập nhật 2026-10-04 (iPad kiểu Mac)

**Một câu:** chọn vài clip một lúc rồi đổi tốc độ, âm lượng, look, motion, nhân đôi, xoá hoặc dời cả nhóm
trong một thao tác và một bước undo.

Hàng lệnh, hai kiểu lệnh (mục / hành động), nút loa: [FS-12.04b](04b-command-rows.md). Look từng clip:
[FS-12.06c](06c-photo-looks.md). Fade, snapping: [FS-12.05](05-cutting-markers-and-fades.md). ⌘A, Esc:
[FS-12.17b](17b-keyboard-and-pointer.md).

## 1. Người dùng cần gì

Dựng reel 20 clip thì hay phải làm cùng một việc cho nhiều clip: chậm 0,5× cả đoạn B-roll, tắt tiếng mọi clip có
gió, dời ba shot hoàng hôn ra cuối. Hôm nay mỗi clip một lần chọn, một lần undo, và chỉ dời được từng clip một.

## 2. Phạm vi

**Có:** chế độ chọn nhiều trên lane video; bảy lệnh nhóm **Speed · Volume · Look · Motion · Move · Duplicate ·
Delete**; kéo cả nhóm tới một ranh giới clip; lệnh Move không cần kéo.

**Cố ý không có:**
- Chọn lẫn clip với chữ, sticker, nhạc — lệnh nhóm chỉ có nghĩa khi mọi item cùng loại.
- Split, Trim, Freeze, Replace cho nhóm — mỗi lệnh cần một vị trí trong *một* clip.
- Kéo nhóm sang lane khác — lane video chỉ có một ([FS-12.04 §4](04-tools-and-inspector.md)).

## 3. Màn hình (canvas Video Studio, hàng F1)

| Máy · board | Bố cục khi đang chọn nhiều |
|---|---|
| iPhone 402×874 · `F1_P_MultiSelect` | timeline giữ đủ 464 (y 326); panel lô **260** tại y 530 trượt đè phần dưới timeline, còn 204pt timeline để chạm thêm clip; đáy 62: ✕ 44 · "3 Clips" / "14.2s · 2 videos + 1 photo" · ✓ 44 |
| iPad ngang 1376×1032 · `F1_IL_MultiSelect` (kiểu Mac 2026-10-04) | inspector 360: hàng lệnh 7 ô ở y 80 (thấy 5, cuộn), rồi các mục **Speed · Audio · Fade · Look** (Title Case) xếp chồng, dòng "Applies to the 2 videos · the photo keeps its 3.0s" dưới Speed; chân 64: ✕ 44 · "3 Clips" / phụ đề như iPhone · ✓ 44; dòng tên dưới khung (đầu hàng phát) ghi "3 clips selected" |
| Duo trong 951×669 · `F1_DI_Reorder` | cột phải 264: hàng lệnh, Speed, Volume, LOOK ô 46; hàng đáy: 5 công cụ mờ 0,3, góc phải ✕ 40 · "2 Clips" / "8.0s" · ✓ 40 |
| Duo ngoài 466×678 · `F1_DC_MultiSelect` | timeline cao **240** và thu về **18 pt/s** để thấy gần hết phim; panel lô 104 (hàng lệnh + một hàng điều khiển); dải 84: 5 công cụ mờ, khối tên 76×56 tại y 440 "3 Clips" / "14.2s", ✕ 44 tại y 504, ✓ 44 tại y 556 |

- **Clip đang chọn:** viền trong 2pt `timelineSelection` (#57BFD1) + huy hiệu tròn 19pt cùng màu, dấu ✓ tối, cách
  mép phải và mép trên 5pt.
- **Pill trạng thái** ở mép trên vùng lane: nền #57BFD1, chữ tối 11pt, "3 selected" rồi "14.2s" mờ 0,8; 190×22
  (iPad kiểu Mac 154×26, ở x 212 đầu thước). Pill ẩn trong lúc kéo dời.
- **Hàng lệnh** ô 64×56 bo `r-cell`, cuộn ngang, mép phải mờ 32pt; Delete chữ `timelineDestructive`.
- Phụ đề đáy đếm loại: "2 videos + 1 photo"; chỉ một loại thì bỏ phần đếm. Số nhiều đi qua String Catalog.

## 4. Vào, ra, thêm bớt

**Ba cử chỉ trên thân clip** (chốt 2026-10-03), phân biệt bằng thời gian giữ và 10pt dịch chuyển:

| Giữ | Rồi | Kết quả |
|---|---|---|
| **≥ 0,5 s**, lệch ≤ 10pt | thả tay | **vào chế độ chọn nhiều**, clip đó được chọn |
| **≥ 0,32 s** | kéo > 10pt | **dời** — cả nhóm nếu clip đó đang được chọn, không thì riêng clip đó |
| 0,32–0,5 s, lệch ≤ 10pt | thả tay | **không gì** — không chọn, không dời, không bước undo |

Lệch > 10pt trước 0,32 s là cuộn timeline. *Vì đó là cử chỉ quen của Photos và không tốn ô lệnh nào.*

- **Thêm / bớt:** trong chế độ chọn, chạm một clip là bật/tắt nó. Bớt tới 0 clip = thoát như ✓.
  Con trỏ trên iPad: ⌘-click bật/tắt, Shift-click chọn dải liên tiếp; ⌘A chọn mọi clip, Esc thoát.
- **Chạm chữ, sticker hoặc nhạc** khi đang chọn nhiều = thoát như ✓ rồi chọn item đó. *Vì* đó là luật chuyển
  chọn giữa hai item đơn.
- **✓ (Keep Changes)** giữ mọi thay đổi, mỗi lệnh vẫn là một bước undo riêng. **✕ (Discard Changes)** trả project
  về đúng lúc vào chế độ chọn (kể cả Move và Duplicate) và trả lại số bước undo như trước — cùng luật với panel
  look (06c AC-9, AC-10) và Duplicate của 04b. Delete đóng phiên như ở 04b: sau đó chỉ Undo mới trả lại.
- Duo ngoài: vào chế độ chọn thì timeline thu về 18 pt/s; ra thì về mức zoom cũ.

## 5. Bảy lệnh nhóm

Nội dung panel mặc định: Speed · Volume · FADE · LOOK · MOTION (iPad vẽ chồng hết như board). **Speed, Volume,
Look, Motion** là lệnh kiểu *mục*, **Move, Duplicate, Delete** kiểu *hành động* — chạm theo luật 04b §4. Lệnh
không áp dụng cho nhóm thì **ẩn** (04b): nhóm không có video thì không có ô Speed và Volume. Mỗi lệnh = **một**
bước undo; kéo slider gom thành một nhóm.

| Lệnh | Làm gì cho nhóm |
|---|---|
| **Speed** | slider + chip 0.5× · 1× · 2× · 4× chỉ áp cho **clip video**; ảnh giữ thời lượng — dòng chú thích nói đúng điều đó: "Applies to the 2 videos · the photo keeps its 3.0s". Giá trị khác nhau thì nhãn ghi "Mixed", không chip nào sáng; kéo là đặt mọi video về cùng một giá trị |
| **Volume** | slider 0–100 + đĩa loa 26pt = Mute. Chỉ đụng clip có âm thanh. Đang lẫn có tắt có bật thì đĩa loa vẽ trạng thái bật; chạm = tắt tiếng **cả nhóm** |
| **Fade** (section dưới Volume, không có ô riêng) | Fade in / Fade out cùng một giá trị cho mọi clip, mỗi clip tự kẹp ở nửa thời lượng của nó |
| **Look** | hàng ô look từng clip của 06c, áp cho mọi clip đang chọn (ô **Selected** của 06c); khác nhau thì dòng Look ghi "Mixed" |
| **Motion** | chip None · Zoom In · Zoom Out · Pan Left · Pan Right… như một clip, áp cho cả nhóm |
| **Move** | vào trạng thái dời không cần kéo (§6) |
| **Duplicate** | chèn bản sao của cả nhóm **ngay sau clip cuối của nhóm**, giữ thứ tự tương đối; bản sao thành nhóm đang chọn |
| **Delete** | xoá cả nhóm, các clip còn lại khép liền; thoát chế độ chọn. Nhóm là **mọi** clip của project thì Delete **mờ** 0,28 (không ẩn — lệnh áp dụng được, chỉ bị chặn): project luôn còn ít nhất một clip |

## 6. Dời nhóm

- **Kéo:** giữ một clip trong nhóm rồi kéo. Nhóm nhấc thành **chồng** 131×54 (ô thumbnail đầu 80, các ô sau thu
  về 50), viền 2pt #57BFD1, huy hiệu đếm 22pt ("2"). Chỗ cũ của nhóm tối 0,66 với viền đứt 1,5pt #57BFD1.
- **Điểm thả** chỉ là **ranh giới giữa hai clip** (kể cả đầu và cuối): vạch 3×82 #57BFD1 có quầng sáng, pill
  "Move 2 clips here" 100×18 phía trên. Ngón tay qua điểm giữa một clip thì vạch nhảy sang ranh giới kế.
- Ngón vào vùng 44pt sát mép trái/phải của lane thì timeline tự cuộn.
- **Move (không kéo):** vạch chèn đặt ở ranh giới gần playhead nhất; cuộn timeline để dời vạch (playhead đứng
  giữa); chạm pill để thả. *Vì* người dùng VoiceOver và người cầm một tay cần một đường không phải giữ-rồi-kéo.
- **Thả xong:** nhóm vào đúng thứ tự cũ của nó trên timeline, kể cả khi các clip không liền nhau; tổng thời lượng
  không đổi; nhóm vẫn được chọn.
- **Chuyển cảnh:** ranh giới giữa hai clip **vẫn kề nhau** sau khi dời giữ chuyển cảnh của nó; mọi ranh giới
  **mới sinh ra** là cắt thẳng (None). *Vì* crossfade chọn cho hai shot cụ thể vô nghĩa giữa hai shot khác. Luật
  này áp cả cho dời một clip.
- **Huỷ:** thả lại vào chỗ cũ, thả ngoài vùng lane, hoặc cử chỉ bị hệ thống cắt → không đổi gì, không thêm bước undo.

## 7. Dữ liệu

| | |
|---|---|
| Đọc / ghi | thứ tự clip và chuyển cảnh trong recipe; recipe lưu JSON ở bảng `creations` ([FS-06.01b](../FS-06-collections/01b-album-management-and-creations.md)) |
| Trường mới | **không** — tập đang chọn là trạng thái màn hình, không lưu; bản sao mang id mới |
| Người dùng tự nhập? | có → nằm trong recipe ở bảng riêng, không đụng `photo_metadata` |

## 8. Đường hỏng

| Tình huống | Hành vi |
|---|---|
| Lane video đang khoá | vẫn chọn được; năm lệnh sửa mờ 0,28; giữ-rồi-kéo không nhấc nhóm |
| Clip chỉ có trên iCloud, máy không mạng | Duplicate dùng chung nguồn đã nạp; clip đang lỗi thì bản sao cũng lỗi, không tải thêm |
| Không mạng, quyền `.limited`, hết bộ nhớ | không áp dụng — lệnh nhóm chỉ sửa recipe, không đọc thư viện, không ghi file |
| Undo giữa chế độ chọn | trả recipe về bước trước; clip không còn tồn tại tự rời nhóm |

## 9. Tiêu chí nghiệm thu

Project mẫu: 5 clip theo thứ tự 3.0s ảnh · 6.2s video · 5.0s video · 3.0s ảnh · 6.8s video (tổng 24,0 s),
mọi ranh giới cắt thẳng (None) trừ khi AC ghi khác.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | project mẫu, không chọn gì | giữ clip 2 trong 0,5 s rồi thả, xê dịch < 10pt | clip 2 có viền 2pt + huy hiệu ✓; pill "1 selected · 6.2s"; đáy ✕ · "1 Clip" · ✓; hàng lệnh đúng 7 ô từ Speed tới Delete | ✅ `VideoStudioMultiSelectTests.holdReleaseEntersWithOneClip` (nhóm một clip, chân "1 Clip" / "6.2s", hàng 7 lệnh Speed…Delete, recipe và Undo không đổi), `enteringKeepsTheOpenSession`; route `video-multiselect-ipad.json` (iPad 13", giữ clip 2 0,6 s): clip 2 mang trait selected, pill "1 selected, 6.2s" 154×26 ở (212, 673) khớp `F1_IL_MultiSelect`, hàng lệnh Speed (1029, 80) … Delete, chân ✕ · "1 Clip" · ✓, dòng đầu hàng phát "1 clip selected", Undo tắt (`build/proofs/fs1211/t4-ipad-one-clip.png`); iPhone 17 (27.0) `t4-phone-one-clip.png`: viền 2pt + huy hiệu ✓ 19, pill 190×22, chân "1 Clip" |
| AC-2 | chế độ chọn, clip 2 đã chọn | chạm clip 3 rồi clip 4 | pill "3 selected · 14.2s"; phụ đề "14.2s · 2 videos + 1 photo"; chạm clip 3 lần nữa → "2 selected" | ✅ `VideoStudioMultiSelectTests.toggleDownToZeroExitsLikeDone` (3 clip → 14,2 s · "14.2s · 2 videos + 1 photo", chạm lại clip 3 → 2, về 0 = ✓), `tappingAnotherItemKeepsAndMovesOn`, `pointerClicksExtendAndToggle` (⇧-click dải, ⌘-click bật/tắt); `VideoClipGroupEditingTests.summaryCountsKinds`; route `video-multiselect-ipad.json` (iPad 13", Fit): chạm clip 3, 4 → pill "3 selected, 14.2s", chân "3 Clips" / "14.2s · 2 videos + 1 photo", "3 clips selected" đầu hàng phát; chạm clip 3 lần nữa → "2 selected, 9.2s" (`build/proofs/fs1211/t5-ipad-three-clips.png`). ⌘/⇧-click qua bàn phím phần cứng: chỉ ở tầng model, sim không gửi được phím bổ trợ |
| AC-3 | clip 2, 3, 4 đang chọn, Speed 1× | chạm chip 2× | clip 2 dài 3,1 s, clip 3 dài 2,5 s, clip 4 vẫn 3,0 s; tổng 18,4 s; một Undo trả cả hai video về 1× | ✅ `VideoClipGroupEditingTests.speedTouchesOnlyVideos` (3,0 · 3,1 · 2,5 · 3,0 · 6,8 = 18,4 s; "Mixed"; dòng "Applies to the 2 videos · the photo keeps its 3.0s"), `VideoStudioMultiSelectTests.oneUndoRestoresBothSpeeds`, `groupSpeedDragIsOneStep`; route `video-multiselect-ipad.json` (iPad 13"): chip 2× sáng, clip 2 "3 to 6", clip 3 "6 to 8", ảnh "8 to 11", pill "3 selected, 8.6s", dòng chú thích dưới chip (`build/proofs/fs1211/t7-ipad-speed-2x.png`) |
| AC-4 | clip 1 và 4 (đều ảnh) đang chọn | nhìn hàng lệnh | đúng 5 ô Look · Motion · Move · Duplicate · Delete; không có Speed, Volume | ✅ `VideoClipGroupEditingTests.photoOnlyGroupHasFiveCommands` (`VideoItemCommand.groupCommands(hasVideo:)` — ẩn, không mờ), `VideoStudioMultiSelectTests.photoOnlyGroupRowHasNoSpeedOrVolume`; ảnh iPhone 17 (27.0) nhóm toàn ảnh: đúng 5 ô Look · Motion · Move · Duplicate · Delete (`build/proofs/fs1211/t4-phone-one-clip.png`) |
| AC-5 | clip 2 đã tắt tiếng, clip 3 chưa; cả hai đang chọn | chạm đĩa loa | cả hai tắt tiếng; một Undo trả đúng trạng thái lẫn ban đầu | ✅ `VideoClipGroupEditingTests.speakerMutesWholeMixedGroup` (lẫn → loa vẽ bật; chỉ video có tiếng), `VideoStudioMultiSelectTests.oneUndoRestoresMixedMute` (một chạm tắt cả hai, một Undo trả clip 2 tắt · clip 3 bật); route `video-multiselect-ipad.json` (iPad 13"): chạm "Mute" → clip 2, 3 mang loa gạch, nút thành "Unmute", Volume mờ (`build/proofs/fs1211/t8-ipad-group-muted-fade.png`) |
| AC-6 | clip 2, 3 đang chọn | Duplicate | 7 clip; bản sao ở vị trí 4 và 5, cùng tốc độ, look, motion; ranh giới 3→bản sao là None; nhóm chọn là hai bản sao; tổng 35,2 s; một Undo về 5 clip | ✅ `VideoClipGroupEditingTests.duplicateInsertsAfterLastKeepsOrder` (7 clip, bản sao ở vị trí 4, 5 cùng tốc độ/look/motion, id mới; 2→3 giữ Crossfade, 3→bản sao và mọi ranh giới mới là None), `transitionsFollowTheirTwoClips`; `VideoStudioMultiSelectTests.duplicateIsOneUndo` (35,2 s, nhóm là hai bản sao, một Undo về 5 clip); route `video-group-commands-ipad.json` (iPad 13"): 7 clip, bản sao "14 to 20" · "20 to 25" mang trait selected, pill "2 selected, 11.2s" (`build/proofs/fs1211/t10-ipad-duplicated.png`) |
| AC-7 | clip 2, 3, 4 đang chọn; ranh giới 1→2 Crossfade 0,5 s | Delete | còn clip 1 và 5 liền nhau, ranh giới 1→5 là None, tổng 9,8 s; thoát chế độ chọn; một Undo trả 5 clip **và** Crossfade 1→2 | ✅ `VideoClipGroupEditingTests.deleteMiddleThreeLeavesNoneBoundary` (1·5, 1→5 None, 9,8 s; xoá mọi clip bị từ chối, recipe y nguyên), `VideoStudioMultiSelectTests.oneUndoRestoresClipsAndCrossfade` (thoát chọn; một Undo trả 5 clip **và** Crossfade 1→2), `deletingOneClipLeavesACut` (luật cặp id cho xoá một clip — Q-a); route `video-group-commands-ipad.json` (iPad 13"): Delete trên clip 2–4 → còn ảnh 0–3 · video 3–9, không còn chọn, Undo bật (`build/proofs/fs1211/t11-ipad-group-deleted.png`) |
| AC-8 | cả 5 clip đang chọn | nhìn ô Delete | mờ 0,28, chạm không xoá gì | ✅ `VideoStudioMultiSelectTests.deletingEveryClipIsRefused` (Delete còn trong hàng, `isItemCommandEnabled` false, chạm không xoá, không bước undo; bỏ một clip thì bật lại); route `video-group-commands-ipad.json` (iPad 13"): chọn cả 5 → ô Delete `isEnabled` = false (hàng lệnh vẽ ô tắt chữ trắng 0,28), chạm vẫn 5 clip, "5 Clips, 24.0s · 3 videos + 2 photos" (`build/proofs/fs1211/t12-ipad-delete-dimmed.png`) |
| AC-9 | clip 3, 4 đang chọn; ranh giới 3→4 và 1→2 Crossfade 0,5 s | giữ clip 3, kéo tới ranh giới 0:03.0, thả | thứ tự 1·3·4·2·5; thời lượng từng clip không đổi; ranh giới 3→4 giữ Crossfade; 1→3, 4→2, 2→5 là None; một Undo trả thứ tự **và** Crossfade 1→2 | ✅ `VideoClipGroupEditingTests.moveGroupKeepsInnerTransitionDropsOthers` (1·3·4·2·5, độ dài giữ, 3→4 Crossfade, 1→3 · 4→2 · 2→5 None), `fingerPastMidpointJumpsToNextBoundary`, `singleClipMoveUsesTileCentres`; `VideoStudioMultiSelectTests.oneUndoRestoresOrderAndCrossfade`; route `video-group-drag-ipad.json` (iPad 13", Fit): giữ clip 3 của nhóm 3·4, kéo tới 0:03.0 → chồng 131×54 + huy hiệu "2", vạch 3×82 + pill "Move 2 clips here" ở 3 s, chỗ cũ tối 0,66 viền đứt (`build/proofs/fs1211/t13-ipad-group-drag.png`); thả → ảnh 0–3 · video 3–8 · ảnh 8–11 · video 11–17 · video 17–24, nhóm vẫn chọn. Tự cuộn ở 44pt mép lane: có code (CADisplayLink trong `VideoTimelineScroller`), chưa có route |
| AC-10 | clip 1 và 4 (không liền nhau) đang chọn | kéo nhóm tới cuối, thả | thứ tự 2·3·5·1·4 | ✅ `VideoClipGroupEditingTests.nonContiguousGroupLandsInTimelineOrder` (ngón ở 23,9 s → ranh giới cuối 5; 2·3·5·1·4, tổng 24,0 s). Kéo trên màn hình đi cùng đường với AC-9 (`video-group-drag-ipad.json`) |
| AC-11 | đang kéo nhóm như AC-9 | thả lại đúng chỗ cũ | thứ tự và chuyển cảnh y nguyên; số bước undo không đổi | ✅ `VideoClipGroupEditingTests.dropAtOriginIsNoOp` (thả ở ranh giới 1, 2, 3 của chính nhóm → không đổi), `VideoStudioMultiSelectTests.cancelledDragAddsNoUndo`; route `video-group-drag-ipad.json` (iPad 13"): kéo nhóm 3·4 rồi thả lại trong chỗ cũ, và thả lên khung (ngoài lane) → thứ tự 1·2·3·4·5 y nguyên, Undo tắt cả hai lần; lần kéo thật sau đó dời được |
| AC-12 | clip 4 đang chọn, playhead 2,8 s | Move, để nguyên vị trí, chạm "Move 1 clip here" | thứ tự 1·4·2·3·5 | ⚠️ chưa có |
| AC-13 | vào chế độ chọn, chạm 2× rồi Duplicate | bấm ✕ | recipe bằng đúng lúc trước khi giữ clip; Undo không còn hai bước vừa làm | ⚠️ chưa có |
| AC-14 | Duo ngoài, timeline 55 pt/s | vào chế độ chọn rồi bấm ✓ | lúc chọn: timeline 240 cao, 18 pt/s (clip 6.2s rộng 112 ±2pt); sau ✓: về 55 pt/s | ⚠️ chưa có — `Tools/ui-drive` + `Tools/sim-shot` |
| AC-15 | iPhone 402×874 · iPad 1376×1032 · Duo trong 951×669 · Duo ngoài 466×678, project mẫu | dựng đúng trạng thái từng board | khớp `F1_P_MultiSelect`, `F1_IL_MultiSelect`, `F1_DI_Reorder`, `F1_DC_MultiSelect` lệch ≤ 2pt; không control nào dưới góc bo hay dải 84 | ⚠️ chưa có — agent `design-parity` |
| AC-16 | project mẫu, không chọn gì | giữ clip 2 trong 0,4 s, lệch < 10pt, rồi thả | không chế độ chọn, không pill; đáy vẫn 5 công cụ; thứ tự và số bước undo không đổi | ✅ route `video-press-release.json` (iPad 13" 26.5, project mẫu từ `Tools/video-fixtures`) 2026-10-05: sau khi giữ clip 2 0,4 s rồi nhả — không clip nào chọn, không ✕ · ✓, thứ tự 1·2·3·4·5, Undo tắt (`build/proofs/fs1211/t3-ipad-ac16-press-release.png`); `TimelinePressClassifierTests.theGateSwallowsOnlyThePressesTap` (chạm của thân clip bị nuốt sau một lần giữ). Trước task 3 nhả tay chọn clip 2 |
| AC-17 | project mẫu, không chọn gì | giữ clip 4 trong 0,35 s rồi kéo (> 10pt) tới ranh giới 0:03.0, thả | thứ tự 1·4·2·3·5; chỉ clip 4 dời; không vào chế độ chọn; một bước undo | ✅ route `video-press-drag.json` (iPad 13", Fit 48,7 pt/s, playhead 12 s) 2026-10-05: giữ clip 4 0,35 s rồi kéo qua giữa clip 2 → thứ tự ảnh 0–3 · ảnh 3–6 · video 6–12 · video 12–17 · video 17–24 (= 1·4·2·3·5), timeline không cuộn (playhead vẫn 12,0 s), Undo bật, không clip nào chọn. Mọi clip giờ nhận giữ-rồi-kéo, không chỉ clip đang chọn |
| AC-18 | luật ba cử chỉ §4 | test thuần với (giữ 0,2 s, lệch 15pt) · (0,4 s, 2pt) · (0,6 s, 2pt) · (0,6 s, 20pt) | cuộn · không gì · vào chế độ chọn · dời | ✅ `TimelinePressClassifierTests.fourCasesFromTheSpec` (cuộn · không gì · vào chọn · dời) + `boundariesBelongToTheLongerGesture` (0,32 / 0,5 s, 10pt) + `aHeldPressIsPendingUntilItMovesOrLifts`; long-press của timeline lấy `minimumPressDuration` và `allowableMovement` từ `TimelinePressClassifier` |
| AC-19 | clip 2 (video 6,2 s) và clip 4 (ảnh 3,0 s) đang chọn, chưa fade | đặt Fade in 2,0 s ở section FADE | clip 2 fade in 2,0 s; clip 4 fade in 1,5 s (kẹp ở nửa 3,0 s); một Undo trả cả hai về 0 | ✅ `VideoClipGroupEditingTests.groupFadeClampsPerClip` (2,0 s → clip 2 2,0 · clip 4 1,5; trần thanh trượt 3,1), `VideoStudioMultiSelectTests.groupFadeIsOneUndo`; mục Fade (In · Out) dưới Volume trong panel nhóm (`t8-ipad-group-muted-fade.png`) |
| AC-20 | clip 1 và 4 (đều ảnh) đang chọn, Motion None | chạm chip Zoom In | cả hai clip Zoom In; một Undo trả cả hai về None | ✅ `VideoStudioMultiSelectTests.groupMotionAppliesToAll` (clip 1, 4 → Zoom In, một Undo về None); Look nhóm: `groupLookWritesEverySelectedClip` (ô Look mở khối look của clip nhắm **Selected**, "2 Clips", một chạm một bước cho mọi clip, khác nhau → "Mixed"); ảnh iPhone 17 (27.0) panel nhóm: FADE · Look "Whole video ›" · MOTION (`build/proofs/fs1211/t9-phone-group-panel.png`) |

**Chưa chứng minh được:** AC-12 tới AC-15.

## 10. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Giữ-để-chọn và giữ-để-kéo cùng một ngón: phân biệt bằng 10pt dịch chuyển | đo trên máy thật; ngưỡng nằm ở Domain, có test |
| Cử chỉ SwiftUI chết trong timeline (UIScrollView) | cả chạm chọn lẫn kéo nhóm đi qua UIKit như reorder hiện có |
| Duplicate 10 clip 4K: bản sao dùng chung nguồn nên không tốn bộ nhớ giải mã thêm | giữ đúng luật "hai clip con dùng chung nguồn đã nạp" của Split ([FS-12.02](02-editing-capabilities.md)) |
