# FS-12.07b — Bố cục Duo màn ngoài

`FS-12.07b` · `Features/VideoStudio/` (`VideoStudioScreen`, `VideoStudioToolbar`, `VideoStudioMetrics`)
· cập nhật 2026-10-03 · nguồn intent [video-studio-canvas-chrome](../../_intents/2026-10-03-video-studio-canvas-chrome.md)

**Một câu:** trên màn ngoài 466×678 của Duo, công cụ dời vào **dải an toàn 84pt bên phải**, trả 136pt cho nội dung:
khung 382×215, transport 40, timeline 344.

iPhone: [07](07-phone-layout.md). Mô hình chọn: [04](04-tools-and-inspector.md). Board: DC1–DC4.

## 1. Quy tắc

- **Dải 84pt bên phải (x 382–466) là chỗ của công cụ.** iOS đặt status bar dọc ở đó; Video Studio ẩn status bar
  nên chạm trong dải tới được app (đã đo trên simulator).
- Bố cục này chọn theo **inset phải ≥ 84** của cửa sổ, không theo tên máy
  ([NF-05 §3](../../04-non-functional-design/NF-05-device-and-os-compatibility.md)).
- Cửa sổ thấp + compact: giữ số đo compact, chỉ khác ở những gì ghi dưới đây (NF-05 §4).
- Không control nào trong **nắp y 0–72** của dải (lỗ camera x 400–437 · y 29–66 và góc bo trên) và không control
  nào dưới **y 600** (góc bo dưới bắt đầu ~612; 34pt cuối là vạch home).

## 2. Nội dung (x 0–382)

| Vùng | y (pt) | Nội dung |
|---|---|---|
| Hàng trên | 6–42 | Back · Undo · Redo — đĩa 34 nền trắng 10%, cách 6, từ x 10; **không có ⋯ và không có Show original** — so sánh nằm ở header của Look ([FS-12.15](15-before-after.md)) (chốt 2026-10-03) |
| Khung | 45–260 | 382×215 (16:9); tỉ lệ khác fit trong 382×215 (9:16 → 121×215 căn giữa); Play 50 ở tâm |
| Transport | 260–300 | Go to Start · Back a Frame · timecode · Forward a Frame · Go to End · ⋯ (nút 40), menu ⋯ như iPhone |
| Timeline | 300–644 = **344** | thước 33 · cột glyph 30 không nhận chạm · lane chữ 34 / video 66 / nhạc 40 · thumbnail 54 · ô chuyển cảnh 22 |
| Vạch home | 644–678 | trống |

## 3. Dải 84

| Phần | Khung (pt) | Không chọn gì | Đang chọn item |
|---|---|---|---|
| Nắp | y 0–72 | sọc chéo tối, không nút | như cũ |
| 5 công cụ | ô 64×56 ở x 392, y 80–360, nhãn 9,5 | trắng; ô đang mở panel nền trắng 14% | trắng 30%, không nhận chạm |
| Tên item | 76×56 ở (386, 440) | — | tên 11pt (cắt đuôi) + dòng phụ 9,5 ("6.2s", "Text") |
| Nút trên | đĩa 44 ở (402, 504) | **Video Settings** (hình tỉ lệ) | **✕** |
| Nút dưới | đĩa 44 ở (402, 556) | **Export** (accent) | **✓** (trắng, glyph đen) |

- Cột 5 ô ngắn hơn 140pt so với 10 công cụ cũ — y 360–440 bỏ trống có chủ đích, để ✕ và ✓ nằm đúng chỗ ngón cái
  phải chạm tới khi cầm máy một tay.
- Export **ẩn** khi đang chọn: xuất giữa chừng một phiên chưa ✓ là xuất thứ người dùng chưa quyết.

## 4. Panel

- **Panel chọn item**: dải tổng quan y 306–328 (x 12, rộng 358); panel từ y 334, nội dung tới 644 (nền kéo tới
  678), bo trên 16; hàng lệnh ở y + 6 ([04b](04b-command-rows.md)); dòng thông số cao 36.
- **Panel công cụ** (Music, Look, Media): từ y 300 tới 644, **phủ cả timeline**, grabber 36×5 ở y + 6, nội dung
  từ y + 14. Khung 382×215 và transport không đổi.
- Chiều cao không đổi theo item hay lệnh (luật [04 §2](04-tools-and-inspector.md)).
- **Thu panel chọn** (chốt 2026-10-03, cùng luật [07 §3](07-phone-layout.md)): vuốt grabber xuống → panel còn **78**
  (grabber + hàng lệnh) neo đáy 644, y 566–644; dải tổng quan ẩn; timeline 300–566 lộ lại, cuộn tới lane của item,
  tay nắm mép chạm được; item vẫn chọn, ✕ / ✓ vẫn ở dải 84. Vuốt lên hoặc chạm lệnh kiểu *mục* trả về đủ cao.

## 5. Gập và mở máy

- Mở máy khi đang chọn item: màn trong nhận đúng item đó, phiên chọn và bản chụp ✕ còn nguyên; panel thành cột
  264 ([03 §5](03-timeline-and-desk-layout.md)).
- Gập máy khi panel công cụ đang mở: màn ngoài mở lại đúng panel đó.
- *Vì:* trạng thái chọn là của phiên, không của bố cục; gập máy không được là một cách bấm ✕.

## 6. Hàng trên không có ⋯

Mọi thứ đã có chỗ: Video Settings và Export ở dải 84, việc timeline ở ⋯ của transport. *Vì hai nút ⋯ trên một màn
382pt là hai chỗ tìm cùng một thứ.*

## 7. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | Duo gập, màn ngoài 466×678, project 16:9, không chọn | dump | khung 382×215 y 45; transport y 260; timeline 300–644; 5 ô 64×56 ở x 392 y 80–360; Video Settings y 504; Export y 556 | ✅ `VideoStudioDeskGeometryTests.duoCoverIdle` + route `duo-vs-cover.json` 2026-10-04, Duo (27.1) màn ngoài: dump — Media/Text/Sticker/Music/Look 64×56 ở x 392 y 80·136·192·248·304, Video Settings (402,504) 44, Export (402,556) 44, transport y 260 (Go to Start x 6 … More x 336), Play giữa khung y 152; `sim-shot cover` |
| AC-2 | như AC-1 | chạm ô Music (x 424, y 276) | panel Music mở 300–644; ô Music nền trắng 14% | ✅ route `duo-vs-cover.json` (chạm điểm 0,91 · 0,407 = (424, 276)): `sim-shot cover` — panel Add Music từ y 300 phủ timeline, khung + transport không đổi, ô Music sáng |
| AC-3 | như AC-1 | dump vùng x 382–466, y 0–72 và y > 600 | không có phần tử nhận chạm nào | ✅ `VideoStudioDeskGeometryTests.nothingTappableInTheCapOrBelow600` + dump `duo-vs-cover.json`: phần tử thấp nhất của dải là Export 556–600, cao nhất là Media từ y 80 |
| AC-4 | như AC-1 | chọn clip 2 | ✕ ở y 504, ✓ ở y 556; tên "Clip 2" ở y 440; Video Settings và Export không còn; 5 ô trắng 30% | ✅ `VideoStudioDeskGeometryTests.duoCoverSelected` + route `duo-vs-cover-select.json` 2026-10-04, Duo màn ngoài (chọn clip 1 — clip 2 nằm dưới dải ở bề rộng này): `sim-shot cover` — tên "Photo 1 / 3.0s · photo" ở y ~470, ✕ ở 504, ✓ trắng glyph đen ở 556, không còn Video Settings/Export, 5 ô mờ 30% |
| AC-5 | clip 2 đang chọn | chạm ô Media | không có gì mở | ✅ `duo-vs-cover-select.json`: chạm (424, 108) — ô Media — khi đang chọn: ảnh sau giống hệt ảnh trước (ô không nhận chạm, `toolsAreInert`) |
| AC-6 | clip 2 đang chọn | dump | dải tổng quan y 306; panel bắt đầu y 334; khung vẫn 382×215 ở y 45 | ✅ `duoCoverSelected` (tổng quan 12/306/358×22, panel 334–644) + `sim-shot cover` của `duo-vs-cover-select.json`: dải tổng quan dưới transport, hàng lệnh Split…Delete ở đầu panel, khung không đổi |
| AC-7 | project 9:16 | mở Video Studio | khung 121×215 căn giữa trong x 0–382 | ✅ `VideoStudioDeskGeometryTests.aPortraitProjectFitsCentred` (121×215 ở x 130,5 — cùng hàm fit khung xem trước dùng); chưa chụp project 9:16 thật |
| AC-8 | clip 2 đang chọn, Speed đổi sang 2× | mở máy | màn trong: góc phải hàng đáy là ✕ · Clip 2 · ✓; bấm ✕ trả Speed về 1× | ⚠️ chưa có — mở máy bằng tay trong Simulator.app |
| AC-9 | DC1, DC2 | `Tools/sim-shot <udid> out.png cover` (có mask) | Back và ✓ không bị góc bo cắt | ✅ `Tools/sim-shot … cover` (có mask) 2026-10-04: DC1 (`duo-vs-cover.json`) — Back ở (10,7) nguyên đĩa; DC2 (`duo-vs-cover-select.json`) — ✓ ở (402,556) nguyên đĩa, cách góc bo dưới |
| AC-10 | các board DC1–DC4, DC2_Collapsed | `Tools/design-board compare` với dump app cùng trạng thái | mọi phần tử chrome lệch ≤ 2pt | ⚠️ chưa có — agent `design-parity` |
| AC-11 | như AC-1 | dump hàng trên y 6–42 | đúng 3 đĩa Back · Undo · Redo; không có ⋯, không có Show original | ✅ `duoCoverIdle` (3 đĩa ở x 10/50/90, y 7–41) + dump `duo-vs-cover.json`: Back (10,7) · Undo (50,7) · Redo (90,7) 34pt, không nút nào khác trong y 6–42 của nội dung |
| AC-12 | clip 2 đang chọn | vuốt grabber xuống | panel 78 ở y 566–644; timeline 300–566 có tay nắm mép clip 2; ✕ y 504, ✓ y 556 vẫn còn; khung không đổi | ⚠️ một phần — số: `VideoStudioDeskGeometryTests.duoCoverCollapsedPanelIs78At566` (panel 566–644, timeline 300–566, không dải tổng quan); bố cục đọc `session.isCollapsed`; **cử chỉ vuốt grabber + đặt cờ là của plan `vs-tools-selection-phone` (khối E), chưa có** nên chưa chụp được |

**Chưa chứng minh được:** AC-8, AC-10, AC-12.

## 8. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| status bar hiện lại (alert hệ thống) làm dải 84 không nhận chạm | ẩn status bar suốt Video Studio; kiểm lại sau mỗi alert |
| người dùng không biết grabber thu được panel chọn | grabber luôn hiện, cùng cử chỉ vuốt xuống như panel công cụ; xem lại sau lần thử trên máy thật |
