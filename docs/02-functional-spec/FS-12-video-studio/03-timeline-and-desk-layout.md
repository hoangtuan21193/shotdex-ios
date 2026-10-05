# FS-12.03 — Bố cục cửa sổ rộng: iPad ngang, iPad dọc, Duo màn trong

`FS-12.03` · `Features/VideoStudio/` (`VideoStudioScreen`, `VideoMediaPoolColumn`, `VideoViewerChrome`)
· `Domain/Video/VideoStudioDeskGeometry.swift` · test `VideoStudioLayoutTests` · `VideoStudioDeskGeometryTests`
· `VideoStudioDeskLayoutTests` · cập nhật 2026-10-04 (iPad theo canvas kiểu Mac)
· nguồn intent [video-studio-canvas-chrome](../../_intents/2026-10-03-video-studio-canvas-chrome.md)
· [ipad-mac-style](../../_intents/2026-10-04-ipad-mac-style.md) (iPad)

**Một câu:** cửa sổ rộng có ba hình dạng — iPad ngang là bàn dựng kiểu Mac (media pool kính nổi · khung · inspector
360, toolbar capsule ở trên), iPad dọc dồn điều khiển xuống một dock dưới timeline, Duo màn trong đặt cột 264 cạnh
khung vì chiều cao mới là thứ thiếu.

Board: iPad [`docs/design/ipad/project/`](../../design/ipad/project/) (`IL*`, `IP1_Main`…`IP3_TextOverlay`,
`IP_Export`; vẽ lại kiểu Mac 2026-10-04, commit `76df46d5`, brief
[IPAD_STYLE.md](../../design/ipad/IPAD_STYLE.md)) · Duo [`docs/design/duo/project/`](../../design/duo/project/)
(`DI*`). Bên trong các băng (pool, hàng phát, hàng công cụ timeline, meter, track header, lane):
[03b](03b-desk-bands-and-lanes.md). iPhone: [07](07-phone-layout.md). Mô hình chọn: [04](04-tools-and-inspector.md).

## 1. Quy tắc

- **Phần dư của màn thuộc về quanh khung hình**; panel phụ tiêu **chiều đang dư** — cửa sổ ngang thì cột dọc,
  cửa sổ dọc thì dock ngang ([DESIGN §10](../../../DESIGN.md)).
- **iPad nói ngôn ngữ của bản Mac** (chốt 2026-10-04, intent [ipad-mac-style](../../_intents/2026-10-04-ipad-mac-style.md)):
  hàng toolbar là các capsule kính cao 44 ở y 24 (24pt trên cùng để status bar), không còn băng trên 64 và viewer
  header 32; pool là panel kính nổi; mọi nút ≥ 44. iPhone và Duo **không đổi**.
- **Bố cục chọn theo cửa sổ, không theo tên máy:**

| Cửa sổ | Bố cục | Board |
|---|---|---|
| compact, inset phải < 84 | iPhone ([07](07-phone-layout.md)); trên iPad không khoá hướng | `P1_Main`, `P*` (iPhone) |
| compact, inset phải ≥ 84 | Duo ngoài ([07b](07b-duo-cover-layout.md)) | `DC*` (Duo) |
| rộng ≥ 600, **cửa sổ thấp** (< 720, [NF-05 §4](../../04-non-functional-design/NF-05-device-and-os-compatibility.md)) | Duo trong (§4) | `DI*` (Duo) |
| rộng ≥ 600, không thấp, rộng > cao | iPad ngang (§2) | `IL*` (iPad) |
| rộng ≥ 600, không thấp, cao ≥ rộng | iPad dọc (§3) | `IP1_Main`…`IP3_TextOverlay`, `IP_Export` (iPad) |

- Đổi cỡ cửa sổ (xoay iPad, Stage Manager, gập/mở Duo) đổi bố cục **giữ nguyên** item đang chọn và phiên ✕/✓.
- iPad và Duo **không khoá hướng**.
- Khi không chọn gì, cột/dock điều khiển hiện **Look cả video** — chỗ trống được dùng cho việc cả video hay làm
  nhất. Chọn item thì cột/dock thành lệnh + thông số của item, chân có ✕ · tên · ✓.

## 2. iPad ngang 1376×1032 (IL1–IL5)

| Vùng | Khung (pt) | Nội dung |
|---|---|---|
| Toolbar | y 24–68 | capsule kính cao 44 bo 22 (`glass`, viền `glassStroke`, bóng `glassShadow`), cách nhau 12, nút trong capsule 40. Trái: pool mở → capsule **Back** 44 ở x 344 (ngay phải pool); pool đóng → capsule **Media Pool** 44 ở x 16 rồi Back ở x 72. Tiêu đề **"5 clips · 16:9 · 0:24"** 20 semibold + dòng phụ **"0:24 · ~30 MB"** 13 ở x 400 (pool đóng: x 128) — không tên project (chốt 2026-10-03). Phải, từ mép 16 vào: pill **Export** 124×44 accent bo `r-export` 19 (x 1236) · capsule 92 **Quick Adjust · Inspector** (x 1132) · capsule 226 **Video Settings** "16:9 · 1080p · 30 fps ⌃⌄" một dòng (x 894, [10](10-video-settings-and-export.md)) · capsule 140 **Undo · Redo · Show original** (x 742) |
| Media pool | x 8–328, y 8–576 (**320×568**) | panel kính nổi bo 22 (`sidebar`, bóng `sidebarShadow`), cao từ y 8 — đứng cạnh toolbar chứ không dưới nó; tiêu đề "Library" + Select · Search Library · Hide Media; tab Media · Text · Stickers · Music ([03b §1](03b-desk-bands-and-lanes.md)) |
| Sân khấu | x 336–1016, y 80–520 | khung 16:9 → **604×340** ở (352, 130), viền 1pt; meter 44 ở x 966, cao bằng khung |
| Hàng phát | y 530–578, trong sân khấu | trái x 352: tên thứ dưới playhead ("Clip 2" + "under playhead"); nhóm phát 6 nút, Play 48 (x 538–816); phải: **Before and After** 44 ở x 956 ([03b §2](03b-desk-bands-and-lanes.md)) |
| Inspector | x 1016–1376, y 0–584, **360** | cột `panelSolid`, kẻ trái 1pt `hairline`, không bo, cao từ mép trên — capsule Quick Adjust · Inspector và Export nằm đè lên đầu cột; nội dung từ y 80, lề 16; chân **64** ở y 520: ✕ 44 · tên · ✓ 44 khi đang chọn |
| Tay nắm chia | y 586, 36×4 | giữa hàng phát và hàng công cụ ([03b §4](03b-desk-bands-and-lanes.md)) |
| Hàng công cụ timeline | y 596–640, hết bề ngang | sửa tại playhead · marker · timecode · Fit, nút 44 ([03b §2](03b-desk-bands-and-lanes.md)) |
| Dải tổng quan | x 208–1360, y 644–666 | cao 22 |
| Timeline | y 672–1032 = **360** | thước 28 · lane từ y 704: 44 / 104 / 52 cách 4 · track header **200** (thẻ 192) · lane x 208–1360 = 1152 · 70pt/giây |

- Pool **320** và inspector **360** cố định ở 13": cả hai chỉ đứng cạnh sân khấu; hàng công cụ, dải tổng quan và
  timeline chạy hết bề ngang (1152 cho lane ≈ 16,5 giây).
- **Khung nhỏ hơn bố cục trước** (604×340 thay 810×456) khi pool mở: sân khấu chỉ còn 680 giữa hai cột. Đó là giá
  người dùng chọn khi duyệt canvas kiểu Mac; ẩn pool (Hide Media) trả 328pt cho sân khấu, khung lớn theo.
- Export và nút Video Settings **vẫn hiện** khi đang chọn: chân inspector đã có ✕ · ✓, toolbar không phải nhường chỗ.

## 3. iPad dọc 1032×1376 (IP1–IP3)

| Vùng | Khung (pt) | Nội dung |
|---|---|---|
| Toolbar | y 24–68 | trái: capsule **Media Pool** 44 x 16 · **Back** 44 x 72 · tiêu đề + dòng phụ ở x 128; phải: Export 124×44 x 892 · Quick Adjust · Inspector 92 x 788 · Video Settings 226 x 550 (một dòng như ngang — bỏ nút hai dòng) · Undo · Redo · Show original 140 x 398 |
| Khung + meter | y 80–604 | khung **932×524** ở (28, 80) · meter 44 ở x 970 |
| Hàng phát | y 610–658 | tên dưới playhead ở x 28; nhóm phát x 355–633; Before and After 44 ở x 960 |
| Tay nắm chia | y 662 | |
| Hàng công cụ timeline | y 672–716 | như iPad ngang; Fit ở x 972 |
| Dải tổng quan | x 208–1016, y 720–742 | |
| Timeline | y 748–1052 = **304** | thước 28 · lane 780–1044 (44 / 104 / 52) · track header 200 · 60pt/giây |
| **Dock** | y 1052–1376 = **324** | bo trên 16, kẻ trên 1pt `hairline`; 3 cột **312** ở x 16 · 360 · 704 (cách 32, kẻ dọc giữa) thấy hết một lượt, không một panel cuộn |

- **Không chọn gì**: tiêu đề "Look · Whole video" ở x 16, y 1060 và bên phải 4 nút thêm **Media · Text · Sticker ·
  Music** **104×44** (x 576–1016, cách 8); 3 cột là Look ([06c](06c-photo-looks.md)).
- **Đang chọn**: hàng lệnh ở dock + 9 (y 1061, rộng 1000); 3 cột thông số 312 từ y 1125 (clip: Speed · Volume |
  Fade | Motion); chân **64** ở y 1312: ✕ 44 (x 16) · tên · ✓ 44 (x 972). **Timeline không bị che.**
- Pool đóng mặc định (rộng < 1100); nút Media Pool ở đầu toolbar bật nó.

## 4. Duo màn trong 951×669 (DI1–DI4)

Chiều cao là thứ thiếu: **385 (khung) + 40 (transport) + 188 (timeline) + 56 (hàng đáy) = 669**. Khung bị giới hạn
theo chiều cao nên 264pt bên phải là miễn phí — inspector nằm ở đó. **Không đổi theo bố cục kiểu Mac của iPad.**

| Vùng | Khung (pt) | Nội dung |
|---|---|---|
| Khung | x 1,5–685,5, y 0–385 | 684×385 (9:16 → 217×385); Back · Undo · Redo · Show original nổi trên khung ở (16, 12), đĩa 36 nền đen 55%, cách 8 |
| Cột phải | x 687–951, y 0–385, **264** | nền `panelSolid`; Look khi không chọn, lệnh + thông số khi chọn (dòng 36) |
| Transport | y 385–425 | 15 nút 36 + timecode, kẻ trên 1pt |
| Timeline | y 425–613 = **188** | cột badge **100** (T1 · V1 · A1 + nút Lock · Mute nhỏ — [03b §4](03b-desk-bands-and-lanes.md)) · lane 34 / 66 / 40 (bậc compact) · 55pt/giây |
| Hàng đáy | y 613–669 = **56** | trái từ x 40: 5 công cụ 72×50 cách 4; phải tới x 907: nút cài đặt 2 dòng cao 40 · pill Export cao 40 |

- **Đang chọn**: 5 công cụ trắng 30% không nhận chạm; nhóm phải thay bằng ✕ 40 · tên 14 + dòng phụ 11 · ✓ 40 ở
  x 620–907. Hàng lệnh là hàng đầu cột phải, cách góc bo 40.
- Không có pool, meter, viewer header: mỗi thứ tốn 32–300pt của chiều đang thiếu. Media mở trong cột phải
  ([09](09-media-panel.md)).

## 5. Cột/dock khi ẩn

- Nút **Inspector** (capsule toolbar trên iPad) tắt cột/dock; chọn một item khi cột đang tắt thì **cột tự mở** —
  ✕ · ✓ nằm ở đó, ẩn là mất đường kết thúc phiên. Bỏ chọn không tự đóng lại.
- **Hide Media** (trong tiêu đề pool) đóng pool; nút **Media Pool** hiện ở đầu toolbar để mở lại.

## 6. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | iPad 1376×1032, project 16:9, không chọn | dump | toolbar capsule cao 44 ở y 24 (Export 124×44 ở x 1236); pool 320×568 ở (8, 8); inspector 360 ở x 1016 (y 0–584) hiện "Look · Whole video"; khung 604×340 ở (352, 130); hàng phát y 530; hàng công cụ y 596; timeline y 672 cao 360; lane từ x 208 | ⚠️ một phần — số (khối M, M1): `VideoStudioDeskGeometryTests.iPadLandscapeIdle` (toolbar 0/24/1376×44, pool 8/8/320×568, inspector 1016/0/360×584, sân khấu 336/80/680×440, khung 604×340 ở (352, 130), meter 44 ở x 966 cao bằng khung, hàng phát 530 (352–1000), tay nắm 670/586, hàng công cụ 596, overview 208/644/1152, timeline 672/360), `theToolRowRunsTheFullWidth`, `shuttingAColumnWidensTheStage`, `theToolbarStartsPastAnOpenPool`; dump `ipad-vs-landscape.json` 2026-10-05 (iPad Pro 13" ngang, M2): Back 347/26 40, Undo 745 · Redo 791 · Show original 837, Video Settings 897/26 222×40, Quick Adjust 1135 · Inspector 1179, Export 1236/24 124×44 — khớp `IL1_Main` 0pt; tiêu đề ở x 400 (20 + 13); không còn viewer header; dọc (`ipad-vs-portrait.json`): Media Pool 19 · Back 75 · tiêu đề 128. Pool, cột inspector và lane: chờ M3, M4, M9 |
| AC-2 | như AC-1 | chọn clip 2 | chân inspector y 520 cao 64 có ✕ 44 · "Clip 2" · ✓ 44; khung không đổi (±0pt); Export vẫn hiện | ✅ `VideoStudioDeskGeometryTests.iPadLandscapeSelectedKeepsTheFrame` (khung chọn == không chọn; chân 1016/520/360×64, ✕/✓ 44); dump `ipad-vs-select.json` 2026-10-05, iPad Pro 13" ngang (khối M, M4), clip 1 chọn: hàng lệnh Split…Delete 64×56 từ (1029, 80); Discard Changes (1033, 530) 44 · "Clip 1" / "32.3s · video" giữa · Keep Changes (1316, 530) 44 (board 531/1317 — lệch 1); Export (1236, 24) và Video Settings vẫn hiện; khung không đổi (352, 130) | |
| AC-3 | iPad 1032×1376, không chọn | dump | khung 932×524 ở (28, 80); hàng phát y 610; timeline 748–1052; dock y 1052 cao 324, tiêu đề có Media · Text · Sticker · Music 104×44; pool đóng, nút Media Pool ở x 16 | ⚠️ cần làm lại theo bố cục kiểu Mac 2026-10-04 — bằng chứng cũ (`iPadPortraitIdle` + `ipad-vs-portrait.json`) đo header 64, khung 982×552, transport 648, timeline 722, nút dock cao 32; dock 1052/324 vẫn đúng |
| AC-4 | như AC-3 | chọn clip 2 | hàng lệnh trong dock ở y 1061; chân ✕ · tên · ✓ cao 64 ở y 1312; timeline 748–1052 không bị phủ | ⚠️ cần làm lại theo bố cục kiểu Mac 2026-10-04 — bằng chứng cũ (`iPadPortraitSelectedFooterAt1316` + `ipad-vs-select.json` dọc) đo chân 60 ở y 1316, hàng lệnh dock + 8, timeline 722 |
| AC-5 | Duo mở 951×669, không chọn | dump | khung 684×385 ở y 0; cột 264 ở x 687; transport y 385; timeline 188; hàng đáy y 613 có 5 công cụ từ x 40 và Export | ⚠️ một phần — số: `VideoStudioDeskGeometryTests.duoInnerBandsSumToTheWindow` (385+40+188+56 = 669, khung 684×385, cột 687/264, transport 385, timeline 425/188, hàng đáy 613; 5 công cụ từ x 40, nhóm phải tới 907), `duoInnerHasNoPoolMeterOrHeader`; ảnh + dump **bản đứng thay** 951×669 trên iPad Pro 13" (route `duo-vs-inner-standin.json`, cờ Debug `-VideoStudioStandIn duoInner`): Back/Undo/Redo/Show original 36 ở (16,12) cách 8, Media…Look 72×50 ở x 40–416 y 616, Video Settings 661,5–813,5 và Export tới 907 y 621; **trên Duo thật chưa có** — sim boot gập, màn trong không mở được từ dòng lệnh |
| AC-6 | như AC-5 | chọn clip 2 | ✕ · Clip 2 · ✓ ở x 620–907; Export ẩn; 5 công cụ trắng 30% | ⚠️ một phần — `VideoStudioDeskGeometryTests.duoInnerSelectedFooterSpans620To907` + bản đứng thay 951×669 trên iPad (`duo-vs-inner-select-standin.json`): dump — Discard Changes (620,621) 40, Keep Changes (867,621) 40, không còn Video Settings/Export, hàng lệnh Split… ở (697,10) đầu cột; ảnh: 5 công cụ mờ 30%; **trên Duo thật chưa có** (sim gập) |
| AC-7 | iPad Stage Manager, cửa sổ 1000×800, clip 2 đang chọn | kéo cửa sổ xuống cao 700 | bố cục đổi sang Duo trong; clip 2 vẫn chọn; ✕ trả đúng trạng thái lúc chọn | ⚠️ một phần — `VideoStudioWindowClassTests.shrinkingAStageManagerWindowChangesClassOnly` (1000×800 → iPad ngang, 1000×719/700 → Duo trong), `aClassChangeKeepsTheSelectionAndItsCancel` (clip 2 chọn, 2×, đổi lớp → vẫn chọn, cùng phiên, ✕ → 1×), `VideoDeskColumnsTests.classChangeKeepsColumns`; **kéo cửa sổ Stage Manager xuống 700 bằng tay: chưa làm** (không lái được bằng `ui-drive`); lần xoay iPad trên máy đo ở bố cục cũ — chạy lại cùng AC-9 |
| AC-8 | iPad ngang, Inspector tắt | chọn clip 2 | cột inspector 360 mở, chân có ✕ · ✓ | ⚠️ cần làm lại theo bố cục kiểu Mac 2026-10-04 — luật vẫn có test (`VideoDeskColumnsTests.selectingOpensAClosedInspector`, `deselectingLeavesItOpen` — thuần, không đổi), nhưng route `ipad-vs-inspector-closed.json` đo cột 280 và nút Inspector ở viewer header; nay nút ở capsule toolbar và cột 360 |
| AC-9 | iPad, Video Studio mở ngang | xoay sang dọc | bố cục dọc, không khoá hướng; item đang chọn giữ nguyên | ⚠️ cần làm lại theo bố cục kiểu Mac 2026-10-04 — route `ipad-vs-rotate.json` 2026-10-04 (clip 2 vẫn chọn sau khi xoay) chạy trên bố cục cũ; chạy lại khi khối M xong |
| AC-10 | các board `IL1_Main`–`IL5_Export`, `IP1_Main`–`IP3_TextOverlay`, `IP_Export` (iPad kiểu Mac), `DI1_Main`–`DI4_Music` | `Tools/design-board compare` với dump app cùng trạng thái | mọi phần tử chrome lệch ≤ 2pt | ⚠️ chưa có — agent `design-parity` |
| AC-11 | Duo trong, DI1 và DI2 | `Tools/sim-shot` có mask | Back và ✓ không bị góc bo cắt | ⚠️ chưa có |

**Chưa chứng minh được:** AC-1 → AC-11 (AC-1, 2, 3, 4, 8, 9 đã xanh trên bố cục iPad cũ, mở lại 2026-10-04).

## 7. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| luật cũ "pool 300 khi ≥ 900" và "inspector 320" còn trong code và test | đã đổi ở task 6 của plan wide-duo; nay đổi tiếp sang 320/360 ở khối M |
| cửa sổ Stage Manager vừa dưới 720 vừa rất rộng thì cột 264 thừa chỗ | chấp nhận ở v1; bố cục chọn theo chiều thiếu |
| capsule Quick Adjust · Inspector và Export nằm đè lên đầu cột inspector (cột cao từ y 0) | nội dung cột bắt đầu ở y 80; chạm trong y 24–68 thuộc capsule, không thuộc cột |
| board kiểu Mac chưa vẽ: iPad ngang pool đóng với khung đơn, Quick Adjust bật | khung fit vào sân khấu x 0–1016 trừ meter; Quick Adjust đặt trong sân khấu ([03b §1](03b-desk-bands-and-lanes.md)); vẽ thêm board trước `design-parity` |
| iPad trước iOS 26 không có Liquid Glass cho capsule và pool | nền `glass`/`sidebar` mờ đặc, cùng khung và cùng nút trên hai nhánh |
