# FS-12.07 — Bố cục iPhone

`FS-12.07` · `Features/VideoStudio/` (`VideoStudioScreen`, `VideoStudioCommandBand`, `VideoTimelineView`)
· `Domain/Video/TimelineLaneLayout.swift` · cập nhật 2026-10-03
· nguồn intent [video-studio-canvas-chrome](../../_intents/2026-10-03-video-studio-canvas-chrome.md)

**Một câu:** iPhone chỉ dùng dọc; khung video **cố định theo tỉ lệ project** ngay dưới băng trên, panel cao theo
tỉ lệ, và mở panel không bao giờ làm khung nhảy.

Duo màn ngoài: [07b](07b-duo-cover-layout.md). Mô hình chọn: [04](04-tools-and-inspector.md). Board: Main, P2–P5,
P8–P10, và ba board cần vẽ thêm: `P11_Ratio43`, `P12_Ratio219`, `P9_Collapsed` (§3).

## 1. Quy tắc

- **iPhone thường khoá hướng dọc** trong Video Studio. Màn ngang là của Duo màn trong; Duo và iPad không khoá.
- **Khung đặt ở y 60, kích thước theo tỉ lệ project, giữ suốt project** — không co khi panel mở, không giãn khi
  panel đóng. Phần panel lấy là phần của timeline.
- **Playhead cố định giữa vùng lane** (x 216); timeline cuộn dưới nó. Cột glyph 30pt bên trái **không nhận chạm**.
- Cử chỉ trên timeline đi qua UIKit: cử chỉ SwiftUI chết trong nội dung host của một scroll view.
- Điện thoại có đủ mọi chức năng của iPad; chỉ đường vào khác ([NF-05 §1](../../04-non-functional-design/NF-05-device-and-os-compatibility.md)).

## 2. Từ trên xuống (402×874)

| Vùng | y (pt) | Nội dung |
|---|---|---|
| Băng trên | 12–48 | trái: Back · Undo · Redo (đĩa 36, nền trắng 10%, x 10 / 50 / 90); giữa 138–264 để trống cho Dynamic Island; phải: **Video Settings** (đĩa 36, hình tỉ lệ, x 312) · **Export** (đĩa 36 accent, glyph tối, x 356) |
| Khung | 60 → 60 + h | theo §3, căn giữa ngang; nút Play 56 ở tâm khi dừng |
| Transport | ngay dưới khung, cao 40 | Go to Start · Back a Frame · timecode `0:08.4 / 0:24.0` ở giữa · Forward a Frame · Go to End · ⋯ (nút 40, x 6 / 46 / 276 / 316 / 356) |
| Timeline | dưới transport → 790 | thước 33 · cột glyph 30 · lane (§4) |
| Thanh dưới | 790–852 | nền `panelSolid`, kẻ trên 1pt trắng 10%; 5 ô 72×52 cách đều 78 từ x 9; icon + nhãn 10 |
| Vạch home | 852–874 | trống |

- Băng trên **chỉ icon**: không có chữ Export, không hàng thông số "1080p · 30", không nút Show original. So
  sánh trước/sau nằm ở tiêu đề panel Look ([15](15-before-after.md)). Export vẫn hiện khi đang chọn item.
- Menu ⋯ của transport: Split · Freeze · Trim Start to Playhead · Trim End to Playhead · Add Marker · Previous /
  Next Marker · Loop · **Snap to Edits** · Fit Timeline · **Tracks ▸** (Lock/Mute từng lane, tên `V1 · Video`,
  `A1 · Music`) · Delete Clip. Không có nút play trong hàng: khung đã có Play 56, chạm khung là pause.

## 3. Kích thước theo tỉ lệ project

| Tỉ lệ | Khung (x) | Transport y | Timeline khi không chọn | Khi chọn: lát timeline · dải tổng quan · panel |
|---|---|---|---|---|
| **16:9** | 402×226 (0) | 286 | 326–790 = **464** | 326–422 (**96**) · 422–450 · **340** (450–790) |
| **1:1** | 342×342 (30) | 402 | 442–790 = 348 | — · 442–470 · **320** (470–790) |
| **4:5** | 290×362 (56) | 422 | 462–790 = 328 | — · 462–490 · **300** (490–790) |
| **9:16** | 216×384 (93) | 444 | 484–790 = 306 | — · 484–512 · **278** (512–790) |
| **4:3** | 402×302 (0) | 362 | 402–790 = 388 | — · 402–430 · **360** (430–790) |
| **21:9** | 402×172 (0) | 232 | 272–790 = 518 | 272–422 (**150**) · 422–450 · **340** (450–790) |

- Luật sinh bảng: panel = 662 − cao khung − lát; lát = 662 − cao khung − 340 nếu ≥ 96, không thì 0. Ra đúng sáu
  dòng trên. Tỉ lệ ngang luôn rộng hết 402 (chốt 2026-10-03): một luật, khung to nhất có thể.
- **Lát timeline** (chỉ khi đủ 96): thước 34 + cửa sổ (16:9: 62, 21:9: 116) cuộn dọc tới đúng lane của item đang chọn.
- **Dải tổng quan** 28: thanh 378×22 ở x 12, bo 4 — mỗi clip một khối, khối clip đang chọn viền 1,5pt `#57BFD1`
  nền 18%, khung trắng 50% là phần timeline đang nhìn, playhead đỏ 2pt, chấm marker 6pt. Kéo để seek.
- Panel: bo trên `r-lg` 16, nền `panelSolid`, grabber 36×4 ở y + 4; nội dung theo [04b](04b-command-rows.md).
- Đổi tỉ lệ trong Video Settings ([10](10-video-settings-and-export.md)): khung, transport, timeline nhảy **một
  lần** sang dòng mới; panel đang mở lấy chiều cao mới cùng lúc.

**Thu panel** (chốt 2026-10-03) — khi không có lát (1:1, 4:5, 9:16, 4:3) panel chọn item phủ hết timeline:

- Vuốt grabber **xuống** thu panel còn **78** (grabber + hàng lệnh) neo đáy 790, y 712–790. Item **vẫn chọn**, đáy vẫn
  ✕ · tên · ✓. Dải tổng quan ẩn; timeline đủ (thước + lane) chiếm từ dưới transport tới 712, cuộn tới lane của item,
  **tay nắm mép chạm được** (9:16: 484–712 = 228).
- Vuốt grabber **lên**, hoặc chạm một lệnh kiểu *mục* ([04b §4](04b-command-rows.md)), trả panel về đủ cao. Lệnh kiểu
  *hành động* chạy ngay ở trạng thái thu.
- Thu là trạng thái của phiên chọn: ✓, ✕ hay chọn item khác thì lần sau panel mở đủ cao. Không phải bước undo.
- 16:9 và 21:9 đã có lát nên grabber không thu. Panel công cụ (không chọn gì): vuốt xuống là đóng và giữ ([04 §4](04-tools-and-inspector.md)).

## 4. Timeline

- **Cuộn ngang = scrub** (haptic mỗi giây) · **cuộn dọc = lộ lane khuất** (khoá hướng) · **pinch = zoom**
  (mặc định 55pt/giây, dải 20–160) · phát thì tự trôi.
- Lane cao: **chữ/sticker 40 · video 80 · nhạc 46**, cách nhau 3, rail rỗng nền trắng 2,5% bo `r-track` 6;
  thumbnail clip rộng 60; ô chuyển cảnh 26×26 giữa hai clip; badge thời lượng `6.2s` ở góc phải dưới clip.
- Thước nằm ngoài vùng cuộn dọc. Chiều cao nội dung là hằng số tự tính, không ghim vào khung nhìn.
- Xếp lane tự động (thuần, có test): overlay **trên** video, nhạc **dưới**; trùng thời gian thì xuống lane mới,
  không giới hạn; kết quả chỉ phụ thuộc tập item, không phụ thuộc thứ tự mảng.
- Lane rỗng = nút gạch đứt `+ Text` / `+ Music` cao 40; băng nhạc vẽ sóng thật cắt theo trim, nhãn dính mép trái.
- Item đang chọn: viền trong 2pt `#57BFD1`; clip có **tay nắm mép** ([05 §3](05-cutting-markers-and-fades.md)).

## 5. Overlay chỉnh trực tiếp trên khung

- Chữ và sticker vẽ live trên player; preview không bake overlay (export thì có) — sửa overlay không dựng lại
  khung hình.
- Một ngón chạm chọn + kéo dời (ngưỡng 4pt, snap tâm + haptic + đường gióng `#57BFD1`), hai ngón pinch + xoay
  (mốc 45°); khung chọn trắng 1,5pt với 4 núm 10pt. Một cử chỉ = một bước undo. Chạm vùng trống = ✓.

## 6. Đồng hồ đo mức

Thanh ngang **LEVEL** 370×8 ở đầu panel của track nhạc đang chọn (board P5), cùng thang dB và ngưỡng với cột meter
của iPad ([03b §3](03b-desk-bands-and-lanes.md)), đọc cả bản mix tại playhead.

## 7. Đường hỏng

- Project luôn còn ít nhất 1 clip: khi chỉ còn một, ô Delete của clip mờ 28% kèm dòng "A video needs at least one
  clip." — không có trạng thái khung rỗng.
- Đang xuất: hàng công cụ mờ, panel xuất 340 (board P7, [10b](10b-export.md)).

## 8. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | iPhone 402×874, Video Studio mở dọc | xoay máy sang ngang | giao diện vẫn dọc, khung vẫn 402×226 ở y 60 | ✅ `VideoStudioOrientationTests.anIPhoneRunsPortraitOnly`; route `video-studio-orientation.json` + `Tools/sim-shot` (dọc trước/sau xoay, 2026-10-03). Phần "khung 402×226 ở y 60" chứng minh lại ở FS-12.07 AC-2 |
| AC-2 | project 16:9, không chọn | dump | khung 402×226 y 60; transport y 286 cao 40; timeline 326–790; 5 ô 72×52 ở y 795 | ⚠️ chưa có |
| AC-3 | 6 project 16:9 / 1:1 / 4:5 / 9:16 / 4:3 / 21:9 | chọn một clip ở mỗi project | khung không đổi so với lúc không chọn (±0pt); panel 340 / 320 / 300 / 278 / 360 / 340 với đáy 790; 4:3 khung 402×302, 21:9 khung 402×172 + lát 272–422 | ⚠️ chưa có |
| AC-4 | luật §3 | test thuần với cao khung 226, 342, 362, 384, 302, 172 | ra lát 96/0/0/0/0/150 và panel 340/320/300/278/360/340 | ⚠️ chưa có |
| AC-5 | project 16:9, chọn băng nhạc ở lane thứ 4 | chụp màn | cửa sổ 62 của lát timeline hiện đúng lane nhạc đó | ⚠️ chưa có |
| AC-6 | không chọn | dump băng trên | Back, Undo, Redo, Video Settings, Export — không có Show original, không có chữ "Export"; không phần tử nào trong x 138–264 | ⚠️ chưa có |
| AC-7 | iPhone nhỏ nhất còn chạy iOS 17 (375 rộng) | mở project 16:9 | timecode không bị cắt; đủ 6 nút transport | `VideoStudioDeskLayoutTests.theCompactTransportFitsTheNarrowestPhone` (cần cập nhật số) |
| AC-8 | project 16:9, đang chọn clip, panel mở | pinch trên lát timeline | zoom đổi, panel và khung không đổi vị trí | ⚠️ chưa có |
| AC-9 | các board Main, P2–P5, P8–P10, P11_Ratio43, P12_Ratio219, P9_Collapsed | `Tools/design-board compare` với dump app cùng trạng thái | mọi phần tử chrome lệch ≤ 2pt | ⚠️ chưa có — agent `design-parity` |
| AC-10 | iOS 26.5 và iOS 18.6 | dump Main và P2 hai bên | cùng tập nút | ⚠️ chưa có — agent `ios26-parity` |
| AC-11 | project 9:16, clip 2 đang chọn, panel 278 | vuốt grabber xuống | panel 78 ở y 712–790 có grabber + hàng lệnh; đáy ✕ · Clip 2 · ✓; timeline 484–712 có tay nắm mép clip 2; khung không đổi (±0pt) | ⚠️ chưa có |
| AC-12 | như AC-11 | kéo tay nắm phải clip 2 vào 1,0 s, rồi vuốt grabber lên | trim áp, đúng một bước undo, clip 2 vẫn chọn; panel về 278 | ⚠️ chưa có |
| AC-13 | như AC-11 | bấm ✓, rồi chọn lại clip 2 | panel mở đủ 278, không thu | ⚠️ chưa có |

**Chưa chứng minh được:** AC-2, AC-3, AC-4, AC-5, AC-6, AC-8, AC-9, AC-10, AC-11, AC-12, AC-13.

## 9. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| khoá hướng bằng cờ cả app làm khoá luôn Library | khoá chỉ khi Video Studio đang trình chiếu, trả lại khi đóng |
| lane 80pt làm timeline 306 (9:16) chỉ hiện 3 lane | cuộn dọc lộ lane còn lại; chiều cao nội dung tự tính |
