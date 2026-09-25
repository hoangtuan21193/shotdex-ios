# FS-01.10 — Focus Stack

`FS-01.10` · tier D · `ShotDexKit/Render/PhotoStackRenderer.swift` · `Features/Editing/PhotoStack*` · test
`PhotoStackRendererTests`, `FocusStack*Tests` · cập nhật 2026-09-24 · nguồn
[intent](../../_intents/2026-09-23-focus-stack-helicon-parity.md) · [spike](../../_intents/2026-09-24-focus-stack-spike.md)

**Một câu:** Combine Photos ▸ **Focus Stack** ghép một chuỗi focus bracketing (10–200 khung) thành một ảnh nét
suốt chiều sâu, ngang Helicon Focus ở bốn thứ người chụp macro cần: căn đúng khi ống kính đổi độ phóng, hai
cách ghép, hai tham số, và tô sửa từ một khung.

> Trạng thái: **đã build** (2026-09-24, plan `docs/_plans/2026-09-24-fs-01-10-focus-stack.md`, 9 task).
> 11/14 AC xanh; còn thiếu xem mục 7.
> Các dòng `⚠️ CẦN QUYẾT (tạm chốt)` được chốt theo mặc định đề xuất lúc người dùng vắng (2026-09-24) —
> người dùng xem lại khi duyệt.

## 1. Người dùng cần gì

Người chụp macro bấm một chuỗi khung, mỗi khung nét một lát mỏng; người chụp phong cảnh bấm 3–10 khung
từ tiền cảnh tới vô cực. Họ cần một tấm nét hết, không quầng ở mép vật, không bóng ma do ống kính phóng to
dần khi lấy nét — hôm nay họ mang sang Helicon hoặc Zerene trên máy tính.

## 2. Phạm vi

**Có:** căn dịch + co giãn + xoay · hai cách ghép · Radius · Smoothing · tô sửa từ một khung · báo khung
không căn được · không trần số khung · xuất JPEG theo dải.

**Cố ý không có:** cách ghép pyramid (Helicon C) · xuất bản đồ độ sâu · 3D · batch · Dust Map · DNG/TIFF —
chốt ở câu 1 và 3 của intent.

## 3. Luồng và màn

Tầng D như FS-01.09 §3: `Cancel` · `Focus Stack` · `Save`; stage đen; một panel. Panel, từ trên xuống:

1. **Method** — hai lựa chọn: **Depth Map** (bản đồ độ sâu — mượt, giữ màu, chuỗi dài, bề mặt trơn) và
   **Weighted** (trung bình có trọng số độ nét — lông, tóc, chi tiết đan chéo). Dưới là một câu nói cách đó hợp
   với cảnh nào.
2. **Radius** — slider 1–10. **Smoothing** — slider 0–10. Hàng slider tầng D sẵn có, không component mới.
3. **Retouch** — nút vào chế độ tô sửa (§5).
4. Dòng nhắc căn khung như hôm nay; khi có khung không căn được thì thay bằng dòng báo (§4).

- ⚠️ CẦN QUYẾT (tạm chốt, sửa theo số đo 2026-09-24): **cách ghép mặc định** — **Weighted**, **Radius 4,
  Smoothing 4**; chọn Depth Map thì Radius 4, Smoothing 4. Bản tạm chốt đầu (Weighted R2 S0, theo spike) đo trên
  chuỗi 16 khung của `FocusStackBracketTests` chỉ được 30,0 dB, R4 S4 được 35,5 dB. Trọng số của Weighted là
  (độ nét tương đối)⁸ — hơn bậc 4 1,3 dB trên cùng chuỗi.
- Đổi cách ghép hay tham số **không nạp lại khung**: dựng lại từ khung preview đã căn.
- Mở ra với > 50 khung: ước lượng thời gian trước khi ghép, như FS-14.01 §1.

## 4. Căn khung

- Khung đi **theo thứ tự lấy nét**: sắp theo thời điểm chụp, cùng thời điểm thì theo tên file. Không lấy thứ
  tự lưới hay thứ tự chạm.
- Mỗi khung căn với **khung liền trước**, mô hình dịch + co giãn + xoay (4 bậc tự do), rồi nối về khung đầu.
  *Vì* căn thẳng về khung đầu thì một nửa khung thất bại — khung nét gần và nét xa không có chi tiết sắc
  chung (spike §2). Không dùng mô hình phối cảnh đầy đủ: chuỗi trên tripod hay ray chỉ trôi co giãn + dịch.
- Dùng lại bộ dò và so khớp điểm đặc trưng của FS-14, không dùng bộ căn dịch của Vision.
- Khung **không căn được** bị **loại** khỏi ảnh ghép, và panel ghi "2 of 40 frames couldn't be lined up and
  were left out" kèm cách xem đó là khung nào. Không lặng lẽ ghép khung chưa căn.
- Khung giải mã hỏng (iCloud mất mạng…) cũng được nói ra theo cùng cách — hôm nay nó bị bỏ không báo.

## 5. Tô sửa (Retouch)

- Chế độ Retouch: stage hiện ảnh ghép; dưới là **dải khung** (filmstrip của editor, không component mới).
- Chọn một khung trong dải, rồi tô trên stage: vùng tô lấy điểm ảnh **từ khung đó**. Mặc định chọn sẵn khung
  **nét nhất ở chỗ vừa chạm** (như "auto-pick" của Helicon).
- Mỗi nét tô là một bước **Undo**. Rời Retouch giữ nguyên các nét; đổi cách ghép hay tham số thì hỏi trước khi
  xoá chúng.
- ⚠️ CẦN QUYẾT (tạm chốt khi build, 2026-09-24): nét tô **ghi dưới dạng nét** (điểm chuẩn hoá 0…1 + khung
  nguồn theo chỉ số khung đầu vào), không phải bản đồ "khung nào thắng" 2 byte/điểm ảnh. *Vì* nét không phụ thuộc
  độ phân giải — cùng nét tô trên preview được phát lại y hệt lúc Save ở độ phân giải gốc, không phải phóng một
  bitmap 1600px lên 48 MP. Các nét liền nhau cùng khung dùng chung một mặt nạ, vẽ ở cạnh dài ≤ 2048px bằng
  `BrushStrokeRasterizer` của editor (cùng mép mềm với bút mask), nên bộ nhớ theo số lần đổi khung, không theo số
  nét (`FocusStackRetouch.swift`).
- Bút: một slider **Brush** (1–25% cạnh ngắn, mặc định 6%), mép mềm cố định. Dải khung mở đầu bằng ô **Auto**
  (mặc định): mỗi nét lấy khung nét nhất tại điểm bắt đầu; chạm một khung trong dải thì mọi nét sau lấy khung đó.
- Đổi Method/Radius/Smoothing khi còn nét → alert "Clear Retouch?" (Clear Retouch and Change / Keep Retouch) —
  alert chứ không phải confirmation dialog, vì iOS 26 vẽ dialog thành popover giấu Cancel.
- Bút tô chỉ sống trong phiên; không lưu.

## 6. Lưu

- Như FS-01.09 §3: Save → ảnh mới, Cancel giữ lựa chọn, lưu xong mở viewer theo màn đang đứng.
- Full-res **theo dải**, khung giữ trên đĩa và ánh xạ vào bộ nhớ — cùng cách FS-14.02 §6. JPEG chất lượng 0,95.
  Đã build (task 6, 8): từng khung gốc ghi vào thư mục phiên (`PhotoStackSession`), rồi `streamedFocusStack`
  (`FocusStackStreaming.swift`) ghép **từng khung một** vào bộ đệm cố định — Depth Map: kết quả 8-bit + độ nét
  half + mặt nạ 8-bit; Weighted: đỉnh độ nét half + tổng màu/trọng số RGBAh (trọng số ở kênh alpha). Mỗi lượt
  render đi theo dải 256 hàng và chỉ đưa cho Core Image đúng hàng của dải (cộng lề cho bộ lọc đọc lân cận) — đưa
  cả bộ đệm thì Core Image chép lại cả bộ đệm mỗi lượt. Bộ đệm và ảnh ra ở không gian màu của khung đầu (P3 giữ
  P3). Preview vẫn ghép cả graph trong bộ nhớ ở 1600px.
- Đo trên simulator (`FocusStackExportTests`): 12 MP, 4 → 12 khung — bản cũ 233 → 437/513 MB, bản mới phẳng
  (Weighted 275 → 275, Depth Map 172 → 172 MB). 24 MP × 4: Weighted 412 MB, Depth Map 343 MB.
- ⚠️ CẦN QUYẾT (tạm chốt khi build): **không tăng theo cỡ ảnh** chưa đạt — bộ nhớ vẫn tỉ lệ số điểm ảnh (10 byte/
  điểm cho Weighted). Đủ cho 24 MP dưới 500 MB; 48–61 MP sẽ vượt. Ghép hẳn theo dải từ khung mmap như FS-14.02
  §6 là việc sau.
- EXIF của ảnh ghép là của **khung đầu** (theo thứ tự chụp): máy, ống kính, ngày, vị trí. Bỏ cỡ ảnh, hướng và
  khoảng cách lấy nét — chúng không còn tả ảnh ghép (`StackedPhotoMetadata`).
- Save lấy đúng các khung preview đã nạp; khung gốc nào tải hỏng lúc lưu thì dừng và báo, không lưu ảnh thiếu khung.
- Bộ nhớ **không tăng theo số khung** và **không tăng theo cỡ ảnh**.

## 7. Tiêu chí nghiệm thu

Chuỗi thử là khung ảo có đáp án như spike §1 (16 khung, breathing 0/2/5%), dựng trong test từ ảnh nhỏ đóng
trong test bundle. PSNR so với ảnh nét hoàn toàn, bỏ viền 60 px. Đã dựng: `FocusStackFixture.depthBracket` —
cảnh sinh bằng seed (không phải ảnh đóng gói), giới hạn băng tần, bản đồ độ sâu nền 12 m / dải 5 m / đĩa 1,2 m và
0,6 m, 5 mức mờ theo độ lệch diop, lấy mẫu bilinear qua phép breathing + lệch + xoay. Khung đơn tốt nhất 24,9 dB.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | chuỗi 16 khung, breathing 2% | ghép Weighted | PSNR ≥ 33 dB, và ≥ khung đơn tốt nhất + 2 dB | ✅ `FocusStackBracketTests.weightedRebuildsTheBracket` — Weighted 35,5 dB, khung đơn tốt nhất 24,9 dB; bộ căn ≤ 1 px (`FocusStackAlignmentTests`) |
| AC-2 | chuỗi breathing 5% | căn | sai lệch trung bình của phép căn ≤ 1 px | ✅ `FocusStackAlignmentTests.breathingBracketLinesUpWithinAPixel` (0, 2, 5%) |
| AC-3 | chuỗi 16 khung, đảo thứ tự chọn | ghép | cùng kết quả như thứ tự đúng (sắp theo thời điểm chụp) | ✅ `FocusStackOrderTests` (5 test: thời điểm chụp, cùng giây theo số file, số so như số, không ngày đi cuối, đảo thứ tự chọn) |
| AC-4 | chuỗi có 1 khung ảnh khác cảnh chen vào giữa | ghép | khung đó bị loại; panel ghi "1 of 17 frames couldn't be lined up…" | ✅ `FocusStackAlignmentTests.aFrameFromAnotherSceneIsLeftOutAndTheChainGoesOn`, `PhotoStackRendererTests.aFocusStackLeavesOutAFrameItCannotLineUp` + `focus-stack-excluded.json` ảnh `01` (iPhone 17 Pro 26.5: "1 of 3 frames couldn't be lined up and were left out.") |
| AC-5 | cùng chuỗi | chạy Depth Map rồi Weighted | cả hai ≥ 33 dB; Weighted ≥ Depth Map ở vùng mép độ sâu | ⚠️ một nửa: `FocusStackBracketTests.bothMethodsHoldAndWeightedHoldsTheEdges` — Weighted 35,5 dB ✅, Weighted ≥ Depth Map ở mép độ sâu ✅; **Depth Map 32,3 dB < 33** (tốt nhất 33,0 ở Radius 8) — ghi `withKnownIssue`, chưa sửa |
| AC-6 | màn Focus Stack đang mở | đổi Method, Radius, Smoothing | preview dựng lại, không nạp lại khung (số lần đọc khung không đổi) | ✅ `FocusStackMethodTests.preparingOnceThenStackingMatchesCombine` (căn một lần, ghép lại cho ra cùng điểm ảnh); model giữ khung đã căn |
| AC-7 | mở màn Focus Stack | nhìn panel | Weighted chọn sẵn, Radius 4, Smoothing 4; chọn Depth Map thì Radius 4, Smoothing 4 | ✅ `PhotoStackModelTests.aFocusStackOpensOnWeighted`, `pickingAMethodResetsItsSliders`, `FocusStackMethodTests.defaultsFollowTheSpike` + `focus-stack-panel.json` ảnh `01` (iPhone 17 Pro 26.5) |
| AC-8 | ảnh ghép có một vùng lấy sai khung | Retouch: chọn khung 5, tô vùng đó | điểm ảnh trong vùng tô trùng khung 5 (sai ≤ 1/255); ngoài vùng không đổi | ✅ `FocusStackRetouchTests.aStrokePutsBackItsFramesPixelsAndNothingElse` (lõi nét ≤ 1/255 so khung, ngoài nét không đổi) + `focus-stack-retouch.json` ảnh `01`–`03` (iPhone 17 Pro 26.5) |
| AC-9 | vừa tô 3 nét | Undo 3 lần | ảnh ghép trùng từng điểm ảnh với trước khi tô | ✅ `FocusStackRetouchTests.undoingEveryStrokeGivesBackTheStackPixelForPixel` + ảnh `04` (2 nét, Undo, còn `Retouch (1)` ở ảnh `05`) |
| AC-10 | chạm một điểm trong Retouch | — | khung được chọn sẵn là khung có độ nét cao nhất tại điểm đó | ✅ `FocusStackRetouchTests.theFrameOfferedIsTheSharpestWhereTheUserTouched` + `PhotoStackModelTests.retouchStartsOnAutoAndAFramePickTurnsItOff` + ảnh `02` (Auto, khung vừa chọn viền xám) |
| AC-11 | 100 khung × 24 MP | Save | footprint đỉnh ≤ 500 MB, và như nhau (± 10%) ở 10 khung | ⚠️ một nửa: `FocusStackExportTests.memoryDoesNotGrowWithTheNumberOfFrames` (12 MP, 4 và 12 khung, phẳng; đo khi process test đã yên, vì các suite khác chạy chung làm lệch footprint) + `a24MegapixelStackStaysUnderBudget` (24 MP × 4 ≤ 500 MB trên simulator: 412/343 MB); 100 khung trên máy thật chưa đo |
| AC-12 | 3 khung chỉ trên iCloud, máy mất mạng | mở màn | báo "3 photos couldn't be downloaded" + Retry; không ghép với số khung thiếu mà không báo | ⚠️ một nửa: code có (`PhotoStackModel.missingFramesMessage`, `retryMissingFrames`; Save thiếu khung gốc thì dừng với `StackSaveError.framesMissing`, không lưu); simulator không giả được iCloud mất mạng — ảnh chụp chờ máy thật |
| AC-13 | đang lưu | Cancel | không asset nào được tạo; thư mục tạm của phiên rỗng | ✅ `PhotoStackSessionTests` (thư mục phiên mất khi remove và khi phiên bị bỏ) + `FocusStackStreamingTests.aCancelledStackStopsBeforeItFinishes` (huỷ thì ném `CancellationError`, không trả ảnh); Save kiểm huỷ trước mỗi khung, trong từng khung khi ghép, trước ghi asset, và xoá thư mục phiên ở `defer` |
| AC-14 | ảnh ghép đã lưu | xem EXIF trong viewer | máy, ống kính, ngày của khung đầu; không tiêu cự lấy nét | ✅ `StackedPhotoMetadataTests` (giữ máy/ống/ngày/GPS, bỏ SubjectDistance, cỡ và hướng) + `StackedPhotoJPEGTests` (JPEG đọc lại đúng) + `focus-stack-save.json` ảnh `02`/`03` (iPhone 17 Pro 26.5: viewer mở ảnh mới với "D800E · 16mm f/10", ngày và vị trí của khung đầu) |

**Chưa chứng minh được** (sau `/verify` 2026-09-24): AC-5 (Depth Map thiếu 0,7 dB), AC-11 (100 khung trên máy
thật), AC-12 (iCloud mất mạng — cần máy thật). AC-11 là mục tiêu, đo trên máy thật mới chốt.

**Lệch spec đã biết** (REVIEW_QUEUE 2026-09-24): §4 "kèm cách xem đó là khung nào" chưa có — panel chỉ nói số
khung; câu số ít ("1 of 3 … were") cần biến thể số nhiều trong String Catalog.

## 8. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Chỉ có khung ảo; lông tóc thật và quầng mép thật chưa thử | `/verify` chạy thêm trên chuỗi macro thật |
| Khung chụp cùng giây (máy bắn 10 khung/giây) làm thứ tự theo thời điểm chụp không chắc | đường lùi theo tên file; AC-3 là cổng |
| Bộ dò điểm đặc trưng là của FS-14 (phiên khác) | chỉ dùng qua API public của kit, không sửa |
| Bản spike tốn 1,1–1,4 GB ở 24 MP (float trên CPU) | render theo dải, half-float; AC-11 là cổng |
