# FS-12.05 — Cắt, marker, snapping và fade

`FS-12.05` · `Domain/Video/VideoTimelineMath.swift` · `VideoTransitionSheet` · cập nhật 2026-10-03 (§3)

**Một câu:** những thao tác của một trang cắt thật — và chỗ nào cần nam châm thì mới đặt nam châm.

## 1. Quy tắc

- **Slider không được hứa cái timeline không cấp.**
- Marker ghim vào **thước thời gian**, không ghim vào clip.
- **Fade khác transition**: transition là thoả thuận giữa hai clip hàng xóm; fade là việc riêng của một clip.
- Marker **không bao giờ tới compositor** — nó là thứ người dựng nhìn, không phải thứ bản xuất ghi ra.

## 2. Độ dài transition

Là **sheet**, không phải dialog: chip các kiểu + slider Duration + **Apply to All** + một dòng nói
**timeline thật sự cấp bao nhiêu**.

- Độ dài transition tồn tại từ đầu mà **không UI nào chỉnh được** — dialog cũ chỉ chọn kiểu, và một dialog
  không chứa nổi slider. Trên iOS 26 nó còn vẽ thành popover và **giấu mất nút huỷ**
  ([BD-04](../../01-basic-design/BD-04-design-language.md)).
- Độ chồng lấn bị chặn ở **nửa clip ngắn hơn**, nên slider hứa 2s trên clip 0,6s là slider nói dối — dòng
  thông tin kia nói con số thật.

## 3. Cắt hai đầu clip

Chỉ **hai** cách: **tay nắm mép** trên timeline và lệnh **Trim** ở hàng lệnh clip ([04b](04b-command-rows.md)).
**Clip video không có dòng Duration** (chốt 2026-10-03): thời lượng hiện ở dòng phụ tên "6.2s · video"; ảnh và khung
freeze giữ slider Duration 0,5–10 s.

**Tay nắm mép** (mọi thiết bị, khi clip đang chọn):

- Hai tab rộng **12pt**, cao bằng clip, màu `#57BFD1`, glyph tối, nằm **ngoài** hai mép clip; vùng chạm 44pt
  (lấn 16 ra mỗi phía). Khác hai núm fade 10pt trắng ở góc trên (§6).
- Kéo trái dời điểm vào, kéo phải dời điểm ra. Video: dời cửa sổ trim trong nguồn, **quy đổi qua tốc độ clip**;
  ảnh và khung freeze: đổi thời lượng. Clip giữ chỗ bắt đầu, clip sau dời theo — lane video không có khoảng trống.
- Giới hạn: video trong nguồn, ngắn nhất **0,1 s**; ảnh **0,5–10 s**. Chạm giới hạn: tay nắm dừng, một haptic nhẹ.
- Trong lúc kéo: khung hiện đúng khung hình ở mép đang kéo, nhãn nổi ghi thời lượng mới; thả tay thì khung về
  playhead cũ (kẹp vào project).
- Nam châm như §5: mép dính playhead, marker, mép clip khác trong 8pt ngón, kèm haptic.
- Một lần kéo = một bước undo, thuộc phiên chọn — ✕ gỡ ([04 §5](04-tools-and-inspector.md)). Cử chỉ bị hệ thống
  huỷ giữa chừng: clip về như trước, không bước undo nào.
- Chuyển cảnh kề mép co theo luật nửa clip ngắn hơn (§2). Lane bị Lock: không có tay nắm.
- Clip iCloud chưa biết thời lượng nguồn: chỉ kéo **vào** được, không kéo ra quá điểm ra hiện tại.
- Giữ yên tay nắm 0,5 s là vào chế độ cắt từng khung có kính lúp ([17](17-precise-trim-and-input.md)); kéo ngay là
  trim thường ở đây.

**Lệnh Trim** — thao tác cắt hay dùng nhất không phải "đặt hai đầu" mà là **bỏ đoạn lấy đà** hoặc **bỏ đuôi**:

- Ô Trim bật khối hai chip **Start to Playhead** · **End to Playhead** + dòng "Or drag the clip's edges on the
  timeline." Chip bỏ phần trước / sau playhead của **clip đang chọn**.
- Playhead ngoài clip đang chọn hoặc trùng mép: hai chip mờ 28%, dòng chú thích thành "Move the playhead into this
  clip." Phần còn lại dưới mức tối thiểu: không làm gì, haptic lỗi.
- Ảnh dời thời lượng; video dời cửa sổ trim quy đổi qua tốc độ — thời gian cục bộ chạy theo tốc độ, cửa sổ trim
  thì không.
- Transport màn rộng và menu ⋯ của iPhone có cặp **Trim Start / End to Playhead** cùng phép tính, tác động **clip
  dưới playhead** ([03b §2](03b-desk-bands-and-lanes.md)).
- *Vì sao video không có Duration:* slider thời lượng của video là lối cắt thứ ba, không biết dời đầu hay đuôi.

## 4. Marker

Thời điểm + màu (bảng **5 màu cố định**) + ghi chú.

- **Ghim vào thước, không vào clip** — cắt một shot không được kéo theo mọi ghi chú.
- Chấm trên dải tổng quan, chạm để nhảy tới. Transport có add / prev / next.
- Nút add **đổi thành "đổi màu"** khi playhead đã nằm trên một marker (dung sai 0,5s), thay vì chồng hai
  chấm lên một pixel.

## 5. Snapping

Kéo nhạc hoặc caption thì dính vào mép clip, marker, playhead và hai đầu project. Ngưỡng **8pt ngón tay**
quy ra giây theo mức zoom hiện tại, nên cảm giác như nhau ở mọi mức phóng.

**Vì sao không có "khép khoảng trống khi xoá clip"**: lane video ở đây **không thể có khoảng trống** — clip
xếp nối đuôi theo thời lượng, xoá một cái là tự khép. Thứ nằm tự do được là nhạc và caption, nên đó mới là
chỗ cần nam châm.

## 6. Fade hai đầu clip

- Kẹp ở **nửa clip mỗi đầu** để hai fade không bao giờ cắt nhau và để lại một shot không bao giờ hiện đủ.
- Clip đang chọn vẽ nêm mờ + nút tròn để kéo.
- Đi cùng đường "recipe tươi" với hiệu ứng theo clip (kéo nút **không** dựng lại composition), và **áp
  sau** hiệu ứng: fade một khung đã blur là đúng, blur một khung đã fade là sai.

## 7. Preview look thật

Ô look trong panel Look ([06c](06c-photo-looks.md)) vẽ đúng khung dưới playhead qua từng look, cỡ ô, ở mức ưu tiên
nền, cache tới khi playhead sang clip khác.

## 8. Tiêu chí nghiệm thu — cắt hai đầu (§3)

Các phần khác: xem [README](README.md).

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | clip 2 video, nguồn 10,0 s, trim 0–10, tốc độ 1×, bắt đầu ở 3,0 s; clip 3 sau nó | kéo tay nắm trái vào 2,0 s | trim 2–10; clip 2 vẫn bắt đầu 3,0 s, dài 8,0 s; clip 3 sớm 2,0 s; đúng một bước undo | ✅ `VideoEdgeTrimMathTests.leadingDragMovesTheSourceInPoint` (2–10), `VideoEdgeTrimModelTests.leadingDragTrimsAndPullsTheNextClipIn` (clip 3 sớm 2,0 s, một bước undo, playhead về chỗ cũ); sim iPhone 17: kéo tay nắm trái clip video 2,0 → 1,5 s, tab #57BFD1 hai mép, playhead về 0 (route `video-studio-edge-trim.json`, 2026-10-04) |
| AC-2 | như AC-1 nhưng tốc độ 2× (clip dài 5,0 s) | kéo tay nắm phải vào 1,0 s | điểm ra nguồn 10 → 8; clip dài 4,0 s | ✅ `VideoEdgeTrimMathTests.trailingDragConvertsThroughSpeed` (2×, tay nắm phải vào 1 s: nguồn ra 10 → 8, dài 4 s) |
| AC-3 | như AC-1 | kéo tay nắm phải ra thêm 3,0 s | dừng ở 10,0 s nguồn, có một haptic | ✅ `VideoEdgeTrimMathTests.dragPastTheSourceStopsAndReportsTheLimit` (dừng ở 10 s, báo giới hạn; view gõ một haptic nhẹ khi vừa chạm — cảm giác haptic chỉ đo được trên **máy thật**), kẹp nguồn `VideoTimelineMathTests.trimClampsIntoTheSourceWithAMinimumLength` |
| AC-4 | clip ảnh 3,0 s | kéo tay nắm phải vào 2,8 s | dừng ở 0,5 s | ✅ `VideoEdgeTrimMathTests.photoEdgeClampsAtHalfASecond` (ảnh 3 s kéo vào 2,8 s → dừng 0,5 s; kéo ra → 10 s) |
| AC-5 | clip 2 video 0–10, 1×, playhead ở 4,0 s trong clip | chạm Trim → Start to Playhead | clip 2 dùng nguồn 4–10, dài 6,0 s; Undo một lần về 0–10 | ✅ `VideoClipTrimMathTests.startToPlayheadKeepsTheTail` (0–10, playhead 4 → 4–10, 6,0 s), `startToPlayheadOnTheSelectedClipUndoesOnce` (chip tác động clip đang chọn, một Undo về 0–10) |
| AC-6 | clip 2 tốc độ 2×, playhead cách đầu clip 1,5 s | Start to Playhead | điểm vào nguồn = 3,0 s | ✅ `VideoClipTrimMathTests.startToPlayheadConvertsThroughSpeed` (2×, cách đầu 1,5 s → điểm vào 3,0 s) |
| AC-7 | clip 2 đang chọn, playhead nằm trong clip 3 | chạm Trim | hai chip mờ 28%, dòng "Move the playhead into this clip." | ✅ `VideoClipTrimMathTests.chipsAreUnavailableOutsideTheClip` (ngoài clip hoặc trùng mép → không làm gì, không bước undo; dưới tối thiểu → không đổi + haptic lỗi); sim-shot iPhone 17: chip mờ 28% + "Move the playhead into this clip." khi playhead ở mép clip (2026-10-04) |
| AC-8 | marker ở 6,0 s, mép phải clip 2 ở 6,1 s (cách 5pt ở zoom hiện tại) | kéo tay nắm phải 4pt về phía marker rồi thả | mép = 6,0 s đúng marker, một haptic | ⚠️ chưa có |
| AC-9 | AC-1 đã làm, clip 2 vẫn đang chọn | bấm ✕ | trim về 0–10; Redo tắt | ⚠️ chưa có |
| AC-10 | đang kéo tay nắm, hệ thống huỷ cử chỉ (cuộc gọi tới) | huỷ | clip như trước lúc kéo; số bước undo không đổi | ⚠️ chưa có |
| AC-11 | clip 1 video chỉ có trên iCloud, máy không mạng, chưa biết thời lượng nguồn | kéo tay nắm phải ra ngoài | không dài thêm; kéo vào thì ngắn lại bình thường | ⚠️ chưa có |
| AC-12 | các board IL2, IP2 | `Tools/design-board compare` tay nắm mép clip 2 | hai tab 12pt cao bằng clip, lệch ≤ 2pt | ⚠️ chưa có — agent `design-parity` |
| AC-13 | clip 2 video đang chọn trên iPhone, iPad, Duo trong, Duo ngoài | dump panel / inspector | không có dòng Duration nào; clip 1 ảnh đang chọn thì có | ⚠️ một phần — như FS-12.04b AC-11: `VideoClipPanelSectionsTests` + sim-shot phone (video không Duration, ảnh có); 3 máy còn lại chờ plan màn rộng |

**Chưa chứng minh được:** AC-8, AC-9, AC-10, AC-11, AC-12, AC-13.
