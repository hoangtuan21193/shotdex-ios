# FS-12.03 — Bố cục cửa sổ rộng: iPad ngang, iPad dọc, Duo màn trong

`FS-12.03` · `Features/VideoStudio/` (`VideoStudioScreen`, `VideoMediaPoolColumn`, `VideoViewerChrome`)
· `VideoStudioMetrics.swift` · test `VideoStudioLayoutTests` · `VideoStudioDeskLayoutTests` · cập nhật 2026-10-03
· nguồn intent [video-studio-canvas-chrome](../../_intents/2026-10-03-video-studio-canvas-chrome.md)

**Một câu:** cửa sổ rộng có ba hình dạng — iPad ngang là bàn dựng ba cột, iPad dọc dồn điều khiển xuống một dock
dưới timeline, Duo màn trong đặt cột 264 cạnh khung vì chiều cao mới là thứ thiếu.

Bên trong các băng (pool, meter, transport, track header, lane): [03b](03b-desk-bands-and-lanes.md). iPhone:
[07](07-phone-layout.md). Mô hình chọn: [04](04-tools-and-inspector.md).

## 1. Quy tắc

- **Phần dư của màn thuộc về quanh khung hình**; panel phụ tiêu **chiều đang dư** — cửa sổ ngang thì cột dọc,
  cửa sổ dọc thì dock ngang ([DESIGN §10](../../../DESIGN.md)).
- **Bố cục chọn theo cửa sổ, không theo tên máy:**

| Cửa sổ | Bố cục | Board |
|---|---|---|
| compact, inset phải < 84 | iPhone ([07](07-phone-layout.md)); trên iPad không khoá hướng | Main, P* |
| compact, inset phải ≥ 84 | Duo ngoài ([07b](07b-duo-cover-layout.md)) | DC* |
| rộng ≥ 600, **cửa sổ thấp** (< 720, [NF-05 §4](../../04-non-functional-design/NF-05-device-and-os-compatibility.md)) | Duo trong (§4) | DI* |
| rộng ≥ 600, không thấp, rộng > cao | iPad ngang (§2) | IL* |
| rộng ≥ 600, không thấp, cao ≥ rộng | iPad dọc (§3) | IP* |

- Đổi cỡ cửa sổ (xoay iPad, Stage Manager, gập/mở Duo) đổi bố cục **giữ nguyên** item đang chọn và phiên ✕/✓.
- iPad và Duo **không khoá hướng**.
- Khi không chọn gì, cột/dock điều khiển hiện **Look cả video** — chỗ trống được dùng cho việc cả video hay làm
  nhất. Chọn item thì cột/dock thành lệnh + thông số của item, chân có ✕ · tên · ✓.

## 2. iPad ngang 1376×1032 (IL1–IL4)

| Vùng | Khung (pt) | Nội dung |
|---|---|---|
| Băng trên | y 12–52 | trái x 20: Back · Undo · Redo · Show original (đĩa 40, cách 10); giữa: **không có tên project** (project không có tên — chốt 2026-10-03; board IL*/IP* bỏ "Iceland Road Trip"), chỉ "5 clips · 16:9 · 0:24" 12; phải: "0:24 · ~30 MB" 11 · nút **16:9 · 1080p · 30 fps** (cao 32, bo 8 — mở Video Settings, [10](10-video-settings-and-export.md)) · pill **Export** accent cao 40 |
| Pool | x 0–236, y 64–604 | tab Media · Text · Stickers · Music ([03b §1](03b-desk-bands-and-lanes.md)) |
| Viewer header | x 236–1096, y 64–96 | Media Pool · tên thứ dưới playhead · Quick Adjust · Inspector (nút 36×28 bo 7) |
| Khung | sân x 236–1046, y 96–604 | 16:9 → **810×456** ở y 122 |
| Meter | x 1046–1096, y 96–604 | cột 50 có thang dB |
| Inspector | x 1096–1376, y 64–604, **280** | bo trên trái 16; chân 58 ở y 546: ✕ 40 · tên · ✓ 40 khi đang chọn |
| Transport | y 604–648, hết bề ngang | 15 nút 40 + timecode ([03b §2](03b-desk-bands-and-lanes.md)) |
| Dải tổng quan | x 104–1360, y 652–674 | cao 22 |
| Timeline | y 678–1032 = **354** | track header 104 · lane 44 / 104 / 52 · 70pt/giây |

- Pool **236** và inspector **280** cố định ở 13": cả hai chỉ đứng cạnh khung, timeline chạy hết 1376 (1272 cho
  lane ≈ 18 giây). Transport đủ 15 nút nên không bao giờ rơi về hàng hẹp.
- Export và nút cài đặt **vẫn hiện** khi đang chọn: chân inspector đã có ✕ · ✓, băng trên không phải nhường chỗ.

## 3. iPad dọc 1032×1376 (IP1–IP3)

| Vùng | Khung (pt) | Nội dung |
|---|---|---|
| Băng trên | y 12–52 | như iPad ngang (không tên project); dòng "5 clips · 16:9 · 0:24" căn ở x 356; nút cài đặt cao 40 bo 10, hai dòng "16:9 · 1080p" / "30 fps · ~30 MB" |
| Viewer header | y 64–96, hết bề ngang | như iPad ngang; Media Pool tắt mặc định (rộng < 1100) |
| Khung + meter | y 96–648 | khung 982×552 · meter 50 ở x 982 |
| Transport | y 648–692 | như iPad ngang |
| Dải tổng quan | x 104–1016, y 696–718 | |
| Timeline | y 722–1052 = **330** | track header 104 · lane 44 / 104 / 52 · 60pt/giây |
| **Dock** | y 1052–1376 = **324** | bo trên 16, kẻ trên 1pt trắng 7%; 3 cột 344 thấy hết một lượt, không một panel cuộn |

- **Không chọn gì**: tiêu đề dock 46 "Look · Whole video" và bên phải 4 nút thêm **Media · Text · Sticker ·
  Music** (cao 32, bo 8); 3 cột là Look ([06c](06c-photo-looks.md)).
- **Đang chọn**: hàng lệnh ở dock + 6; 3 cột thông số 344×190 ở dock + 72 (clip: Duration · Speed · Volume |
  FADE | MOTION); chân 60 ở dock + 264 (y 1316): ✕ · tên · ✓. **Timeline không bị che.**

## 4. Duo màn trong 951×669 (DI1–DI4)

Chiều cao là thứ thiếu: **385 (khung) + 40 (transport) + 188 (timeline) + 56 (hàng đáy) = 669**. Khung bị giới hạn
theo chiều cao nên 264pt bên phải là miễn phí — inspector nằm ở đó.

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

- Nút Inspector tắt cột (iPad); chọn một item khi cột đang tắt thì **cột tự mở** — ✕ · ✓ nằm ở đó, ẩn là mất
  đường kết thúc phiên. Bỏ chọn không tự đóng lại.

## 6. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | iPad 1376×1032, project 16:9, không chọn | dump | pool rộng 236; inspector 280 ở x 1096 hiện "Look · Whole video"; khung 810×456 ở (236, 122); timeline y 678 cao 354 | ✅ `VideoStudioDeskGeometryTests.iPadLandscapeIdle` (mọi rect của IL1) + route `ipad-vs-landscape.json` 2026-10-04, iPad Pro 13": dump — "Browse All Photos…" rộng 236 (pool), "Look, Whole video" ở x 1110 trong cột từ 1096, Play giữa khung ở x 641; sim này còn lưu divider +111 nên transport/timeline cùng lùi đúng 111 (493/567) — route giờ khởi chạy với `-video.timelineExtraHeight 0` |
| AC-2 | như AC-1 | chọn clip 2 | chân inspector y 546 có ✕ · "Clip 2" · ✓; khung không đổi (±0pt); Export vẫn hiện | ✅ `VideoStudioDeskGeometryTests.iPadLandscapeSelectedKeepsTheFrame` (khung chọn == khung idle, chân 1096/546/280×58) + route `ipad-vs-select.json` 2026-10-04, iPad Pro 13" ngang: dump — Discard Changes (1110,555) và Keep Changes (1322,555) 40pt trong chân, Play giữa khung ở y 350 như lúc idle, Export (1250,12) vẫn có |
| AC-3 | iPad 1032×1376, không chọn | dump | dock y 1052 cao 324, tiêu đề có Media · Text · Sticker · Music; pool đóng | ✅ `VideoStudioDeskGeometryTests.iPadPortraitIdle` (header 64, khung 982×552, meter x 982, transport 648, overview 696, timeline 722–1052, dock 1052/324), `aNarrowPortraitDockSplitsItsWidthInThree` + route `ipad-vs-portrait.json` 2026-10-04, iPad Pro 13" dọc: dump — Media · Text · Sticker · Music cao 32 ở y 1059 (x 662–1018), transport y 648,5, không có pool; chạm Music → panel Music trong dock |
| AC-4 | như AC-3 | chọn clip 2 | hàng lệnh trong dock; chân ✕ · tên · ✓ ở y 1316; timeline 722–1052 không bị phủ | ✅ `iPadPortraitSelectedFooterAt1316` + route `ipad-vs-select.json` dọc: dump — hàng lệnh Split…Delete ở y 1060 (dock + 8), Discard/Keep Changes ở y 1327 (chân 1316–1376), clip 2 trên timeline y 827 không bị phủ; 3 cột Duration · Fade · Motion |
| AC-5 | Duo mở 951×669, không chọn | dump | khung 684×385 ở y 0; cột 264 ở x 687; transport y 385; timeline 188; hàng đáy y 613 có 5 công cụ từ x 40 và Export | ⚠️ một phần — số: `VideoStudioDeskGeometryTests.duoInnerBandsSumToTheWindow` (385+40+188+56 = 669, khung 684×385, cột 687/264, transport 385, timeline 425/188, hàng đáy 613; 5 công cụ từ x 40, nhóm phải tới 907), `duoInnerHasNoPoolMeterOrHeader`; ảnh + dump **bản đứng thay** 951×669 trên iPad Pro 13" (route `duo-vs-inner-standin.json`, cờ Debug `-VideoStudioStandIn duoInner`): Back/Undo/Redo/Show original 36 ở (16,12) cách 8, Media…Look 72×50 ở x 40–416 y 616, Video Settings 661,5–813,5 và Export tới 907 y 621; **trên Duo thật chưa có** — sim boot gập, màn trong không mở được từ dòng lệnh |
| AC-6 | như AC-5 | chọn clip 2 | ✕ · Clip 2 · ✓ ở x 620–907; Export ẩn; 5 công cụ trắng 30% | ⚠️ một phần — `VideoStudioDeskGeometryTests.duoInnerSelectedFooterSpans620To907` + bản đứng thay 951×669 trên iPad (`duo-vs-inner-select-standin.json`): dump — Discard Changes (620,621) 40, Keep Changes (867,621) 40, không còn Video Settings/Export, hàng lệnh Split… ở (697,10) đầu cột; ảnh: 5 công cụ mờ 30%; **trên Duo thật chưa có** (sim gập) |
| AC-7 | iPad Stage Manager, cửa sổ 1000×800, clip 2 đang chọn | kéo cửa sổ xuống cao 700 | bố cục đổi sang Duo trong; clip 2 vẫn chọn; ✕ trả đúng trạng thái lúc chọn | ⚠️ một phần — `VideoStudioWindowClassTests.shrinkingAStageManagerWindowChangesClassOnly` (1000×800 → iPad ngang, 1000×719/700 → Duo trong), `aClassChangeKeepsTheSelectionAndItsCancel` (clip 2 chọn, 2×, đổi lớp → vẫn chọn, cùng phiên, ✕ → 1×), `VideoDeskColumnsTests.classChangeKeepsColumns`; trên máy: xoay iPad dọc → ngang giữ clip 2 chọn (`ipad-vs-select.json`); **kéo cửa sổ Stage Manager xuống 700 bằng tay: chưa làm** (không lái được bằng `ui-drive`) |
| AC-8 | iPad ngang, Inspector tắt | chọn clip 2 | cột inspector mở, chân có ✕ · ✓ | ✅ `VideoDeskColumnsTests.selectingOpensAClosedInspector`, `deselectingLeavesItOpen` + route `ipad-vs-inspector-closed.json` 2026-10-04, iPad Pro 13" ngang: tắt Inspector → khung rộng ra, chọn clip 2 → cột 280 mở; chân ✕ · ✓ của cột: `ipad-vs-select.json` (Discard/Keep Changes ở y 555) |
| AC-9 | iPad, Video Studio mở ngang | xoay sang dọc | bố cục dọc, không khoá hướng; item đang chọn giữ nguyên | ✅ route `ipad-vs-rotate.json` 2026-10-04, iPad Pro 13" (26.5/27): mở dọc, chọn clip 2 (ảnh driver dọc: clip 2 viền xanh, khối 2 của dải tổng quan sáng), xoay ngang, chờ 12 s, `Tools/sim-shot` ngang: clip 2 vẫn chọn, inspector vẫn là lệnh của clip — trên bố cục **cũ**; chạy lại ở task 18 khi bố cục mới vào |
| AC-10 | các board IL1–IL4, IP1–IP3, DI1–DI4 | `Tools/design-board compare` với dump app cùng trạng thái | mọi phần tử chrome lệch ≤ 2pt | ⚠️ chưa có — agent `design-parity` |
| AC-11 | Duo trong, DI1 và DI2 | `Tools/sim-shot` có mask | Back và ✓ không bị góc bo cắt | ⚠️ chưa có |

**Chưa chứng minh được:** AC-5, AC-6, AC-7, AC-10, AC-11.

## 7. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| luật cũ "pool 300 khi ≥ 900" và "inspector 320" còn trong code và test | đổi số theo bảng §2, sửa test bố cục bàn dựng cùng commit |
| cửa sổ Stage Manager vừa dưới 720 vừa rất rộng thì cột 264 thừa chỗ | chấp nhận ở v1; bố cục chọn theo chiều thiếu |
