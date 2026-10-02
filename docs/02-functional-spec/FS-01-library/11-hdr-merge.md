# FS-01.11 — HDR

`FS-01.11` · tier D · `ShotDexKit/Render/` (cạnh `PhotoStackRenderer`) · `Features/Editing/PhotoStack*` · test
`HDR*Tests`, `StripImageWriterTests` · cập nhật 2026-10-01 · nguồn [intent](../../_intents/2026-09-30-hdr-merge.md) ·
[spike](../../_intents/2026-09-30-hdr-merge-spike.md)

**Một câu:** Combine Photos ▸ **HDR** ghép một loạt chụp bù trừ sáng (từ 2 khung) thành một ảnh giữ được cả vùng
sáng của khung tối lẫn vùng tối của khung sáng. Căn khung khi chụp cầm tay, khử bóng ma bốn mức, một thanh độ mạnh.

> Trạng thái: **đã build, `/verify` 2026-10-01: 19/22 AC xanh** — còn AC-14 (iPhone 12), AC-19 (Duo màn trong), AC-20 (máy thật).
> Design: board `PH19_HDR`, `PH20_HDRSaveAs`, `IPP13_HDR`, `DC13_HDR` trên [canvas editor](https://claude.ai/artifact/T4tEUQrJtxBbi48HokiL9F), dựng từ số đo app 2026-10-02. Chưa có board Duo màn trong và iPad ngang. Mọi `⚠️ CẦN QUYẾT` đã chốt với người dùng ngày 2026-10-01.

## 1. Người dùng cần gì

Người chụp phong cảnh, nội thất, kiến trúc bấm một loạt AEB (−2 / 0 / +2 EV, hay 5 khung ±4 EV) để giữ trời sáng
lẫn góc tối. Hôm nay họ phải mang loạt đó sang Lightroom hay app khác để ghép. Stack Exposures (Average/Lighten/
Darken) không làm được việc này: trung bình ba khung lệch sáng ra một tấm xám đục.

## 2. Phạm vi

**Có:** ghép từ RAW khi cả loạt là RAW · căn dịch + co giãn + xoay · khử bóng ma Off / Low / Medium / High · một
thanh Strength · xuất 8-bit theo dải · báo khung không căn được, không tải được.

**Cố ý không có:** HDR gain map · xuất DNG hay TIFF · ghép HDR rồi ghép panorama trong một lượt · batch nhiều loạt ·
bộ thanh trượt tone đầy đủ, Auto Tone (sửa tiếp trong editor) — chốt ở câu 1–4 của intent và ngày 2026-10-01.

## 3. Luồng và màn

Tầng D như [FS-01.09](09-photo-stacking.md) §3 và DESIGN §10.3b: `Cancel` · `HDR` · `Save`; stage đen; một panel. Panel, từ trên
xuống:

1. **Câu giải thích** một dòng: *Merges a bracketed series into one photo that keeps the highlights and the shadows.*
2. **Deghost** — segmented control chữ `Off · Low · Medium · High` (DESIGN §6, cao 32). Dưới là một câu nói mức đang
   chọn làm gì. **Mặc định Medium** (spike §4).
3. **Strength** — hàng slider tầng D sẵn có, 0–100, **mặc định 60**. Strength 0 là khung tham chiếu có phục hồi vùng
   sáng (§5).
4. Dòng nhắc căn khung như Focus Stack; khi có khung bị loại, loạt không phải bracket hay loạt lẫn RAW thì thay
   bằng dòng báo (§4, §5).

- **Không có Auto Tone** (chốt 2026-10-01). Nút Auto của editor đã bị gỡ ở FS-03.09 AC-27; chỉnh tone tiếp thì
  mở ảnh ra trong editor.
- Strength 60 là mặc định tạm; số cuối chốt bằng mắt trên loạt chụp thật ở `/verify`. *Vì* ở 100 spike thấy mây
  bị "HDR quá tay" (§2).
- Đổi Deghost hay Strength **không nạp lại và không căn lại khung**: dựng lại từ khung preview đã căn.
- Preview ở 1600px như Focus Stack.

## 4. Thứ tự, tham chiếu, căn khung

- **Thứ tự theo phơi sáng**, tối trước, không theo thứ tự chọn hay thứ tự lưới. Phơi sáng của từng khung tính từ EXIF:
  log₂(thời gian phơi × ISO ÷ khẩu độ²). **Không cộng Exposure Bias** — trong một loạt AEB máy đã thực hiện mức bù bằng
  cách đổi tốc độ (hay ISO, khẩu), cộng nữa là đếm hai lần. Bias chỉ dùng khi thiếu bộ ba đó; thiếu cả bias thì đo độ
  sáng trung vị sau khi giải mã. Cả loạt dùng **một** nguồn: nguồn đầu tiên mà mọi khung đều có.
- **Khung tham chiếu** là khung có phơi sáng ở giữa (loạt chẵn thì lấy khung sáng hơn trong hai khung giữa). Khử
  bóng ma giữ nội dung của khung này, và EXIF của ảnh ra là EXIF của khung này.
- **Căn khung:** dùng lại nguyên văn bộ căn của [Focus Stack](10-focus-stack.md) §4 — mỗi khung căn với khung liền kề
  theo thứ tự phơi sáng, trên bản đã đưa về phơi sáng của khung tham chiếu (cháy như nó cháy), mô hình 4 bậc tự do.
  Hai chuỗi đi **từ khung tham chiếu** ra hai phía, nên một khung lạc ở đâu cũng không cắt chuỗi và ảnh ra giữ khung
  hình của khung tham chiếu; không khung nào căn được với nó thì khung gần nhất đứng thay (`prepareHDR`). Spike: bước 3 EV, cầm tay ±30 px,
  xoay ±1,5° đều dưới 0,4 px ở 1536px.
- Khung **không căn được** bị loại, và panel nói ra, như Focus Stack §4. Còn ít hơn 2 khung thì không ghép, và nói lý do.
- **Các khung không phải một loạt bracket** (phơi sáng lệch nhau dưới 0,5 EV): **vẫn ghép**, và dòng nhắc đổi thành
  *These photos have about the same exposure. HDR works best on a bracketed series.* Dòng HDR trong menu không
  mờ, vì menu không đọc EXIF (chốt 2026-10-01, câu 5 của intent).
- Loạt chỉ phủ một phần cảnh: khung tối nhất vẫn cháy trên 1% diện tích → dòng báo *Some highlights are bright in every
  frame and can't be recovered.*

## 5. Ghép

- **Cả loạt là RAW** (hay cặp RAW+JPEG, lấy RAW) → ghép **từ dữ liệu RAW**: giải mã tuyến tính không tone của bộ giải,
  gộp thành một ảnh radiance, trọng số theo thời gian phơi, bỏ mẫu cháy (spike §2).
- **Loạt JPEG/HEIC** → cùng đường sau khi đảo ngược đường sRGB (quản lý màu của Core Image làm việc đó khi đọc vào).
  Đây là xấp xỉ: JPEG của máy có đường tông riêng.
- **File của từng khung** (`HDRFrameSource`): ảnh server lấy file RAW đi kèm nếu có; ảnh thư viện lấy resource RAW nếu
  có (cặp RAW+JPEG lấy RAW), không thì bản hiện tại. Phơi sáng đọc từ EXIF của chính file; ISO của CR3 nằm ở
  `ISOSpeed`/`RecommendedExposureIndex`, không ở `ISOSpeedRatings`. RAW trong loạt lẫn đọc qua đường tông của bộ giải.
- **Loạt lẫn RAW và không RAW** → dùng **bản đã render cho mọi khung**, và nói ra một dòng: *Some of these photos
  aren't RAW, so all of them are merged from their processed versions.* *Vì* trộn radiance của RAW với JPEG đã
  tone thì lệch sáng giữa các khung (chốt 2026-10-01).
- **Tone map:** trộn các phơi sáng ảo của radiance theo kim tự tháp Laplace (exposure fusion). Phơi sáng ảo là
  Strength × stop của từng khung, **cộng phơi sáng của khung tối nhất ở mọi Strength** (chốt 2026-10-01): vùng sáng
  chỉ khung tối nhất giữ được luôn lấy lại, Strength chỉ quyết độ nâng vùng tối và độ nén tương phản. Strength 0 là
  khung tham chiếu có phục hồi vùng sáng. *Vì* không có nó, ở Strength 60 loạt thử ±2 còn 2,9% điểm trắng.
- Trọng số fusion chỉ là độ phơi sáng tốt (Mertens), **không** tương phản (đo ở mức điểm ảnh, preview và bản lưu
  khác nhau) và **không** độ bão hoà (bằng 0 trên chủ thể xám); phơi sáng ảo đã cháy có trọng số 0.
- **Các dải của kim tự tháp theo cỡ ảnh**: 9 dải, σ dải thô nhất = cạnh ngắn / 16, mỗi dải mịn hơn chia đôi. *Vì* với
  số tầng cố định, preview và bản lưu cho hai ảnh khác nhau (spike §6: 18–23 dB). Cạnh ngắn/16 như bộ trộn panorama:
  /8 thì dải thô kéo màu trắng của phơi sáng sáng sang vùng sáng cạnh mảng trung tính lớn (0,9% điểm trắng ở loạt thử).
- **Phơi sáng ảo thêm** ở mức khung tối nhất − 1 stop (khoảng đệm cho fusion vọt quá 1 cạnh vùng sáng); vùng mà cả khung
  tối nhất cũng cháy thì ép về trắng, không để thành xám. Đo 2026-10-01 trên loạt ±2 cảnh 10 EV: 0 điểm trắng ở
  Strength 0 / 60 / 100; Strength 0 tối hơn khung tham chiếu ~⅓ stop (trung vị). Giới hạn phơi sáng thêm vào riêng vùng
  sáng thì lệch còn một nửa nhưng lại 0,2% trắng ở 100 — chọn bản không trắng.
- **Khử bóng ma:** mỗi điểm ảnh so với khung **neo** — khung tham chiếu nếu nó chưa cháy ở đó, không thì khung ngắn hơn
  gần nhất còn đọc được. Khung lệch khỏi khung neo quá ngưỡng nhiễu của mức đang chọn thì bị bỏ ở đó, có giãn vùng.
  *Vì* so cố định với khung giữa thì bỏ sót vật di chuyển trong vùng trời cháy (spike §4).
- Ngưỡng từng mức lấy theo mô hình nhiễu của cảm biến, cả lượng tử 14-bit. Spike: z = 12 / 7 / 5, giãn 2 / 4 / 8 px ở
  1536px; chỉnh lại trên loạt thật ở `/verify`.

## 6. Lưu

- Như FS-01.09 §3: Save → ảnh mới, Cancel giữ lựa chọn, lưu xong mở viewer theo màn đang đứng.
- **Full-res theo dải**: 128–256 hàng, mọi khung cùng mở, đọc xen kẽ theo dải (spike §5: 5 × 24 MP, ~400–500 MB trên
  Mac). Radiance của dải ghép xong thì đi qua tone map.
- **Tone map của bản lưu chạy trên cả tấm**, không suy ra từ preview (spike §6: chênh ~30 dB). Hai lượt (`HDRExporter`):
  radiance full-res theo dải 256 hàng vào một bộ đệm half-float (192 MB ở 24 MP), mọi bộ giải mã cùng sống; rồi thả
  bộ giải mã, tone map từ bộ đệm theo dải 512 hàng, mỗi dải chỉ lấy các hàng radiance mà dải thô nhất với tới (3σ),
  ghi thẳng vào bộ ghi theo dải `StripImageWriter` (tách từ panorama). File lưu khớp render một mảnh 43,5 dB.
- **Định dạng ra theo luật lưu của editor** ([FS-03.06](../FS-03-photo-editor/06-saving-recipe-and-live-photo.md)):
  Save hỏi JPEG hay HEIC, **mặc định JPEG**; máy không ghi được HEIC thì báo trước là dùng JPEG. JPEG ở chất lượng
  0,95 như Focus Stack. Cả hai đường ghi phải đi **theo dải** (chốt 2026-10-01).
- EXIF là của **khung tham chiếu**: máy, ống kính, ngày, vị trí. Bỏ thời gian phơi, ISO, khẩu độ và Exposure Bias —
  chúng không còn tả ảnh ra (như panorama chỉ giữ phơi sáng khi mọi khung khớp).
- Khung gốc nào tải hỏng lúc lưu thì dừng và báo, không lưu ảnh thiếu khung.
- **Trần của Save**: loạt 5 khung RAW 24 MP, footprint đỉnh **≤ 700 MB** và **≤ 60 s** trên iPhone 12 (chốt
  2026-10-01). Nới hơn Focus Stack (500 MB) vì nền của bộ giải RAW (~400 MB trên Mac) chưa đo trên iPhone.
- *Đo 2026-10-01 (simulator iPhone 17, 26.5, `HDRExportTests.rawDecoderFloor`):* riêng bộ giải RAW, 24 MP, theo dải —
  1 bộ giải +171 MB; 5 bộ giải cùng sống, dải 256 hàng +372 MB (4,8 s); dải 128 hàng +337 MB. Còn ~330 MB cho ghép
  và tone map trong trần 700 MB. Số trên iPhone thật chưa có.

## 7. Menu

- Combine Photos có thêm dòng **HDR**: [FS-01.09](09-photo-stacking.md) §1 đã ghi bốn dòng; DESIGN §10.3b sửa cùng lượt build.
- Tên dòng **HDR** (như Lightroom *Photo Merge ▸ HDR*); thứ tự **Focus Stack · Panorama · HDR · Stack Exposures**
  — ba việc ghép thành một ảnh mới, rồi việc ghép cùng một phơi sáng (chốt 2026-10-01).
- Mờ khi < 2 ảnh, như các dòng khác. Video bị bỏ qua.

## 8. Tiêu chí nghiệm thu

Loạt thử là khung ảo có đáp án như spike §1: cảnh 14 EV dựng từ RAW thật không mặt người, nhiễu shot + đọc,
14-bit, cháy ở 1. Test dựng loạt từ ảnh nhỏ đóng trong test bundle, không dùng thư viện ảnh.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | loạt 5 khung RAW −4…+4 EV, cảnh 14 EV, đứng yên | ghép, deghost Off | sai số radiance ≤ 0,03 stop RMS; ảnh đã tone map ≥ 48 dB so với tone map của cảnh sạch | `HDRMergeTests.fiveFramesOfAFourteenStopSceneMergeWithinThreeHundredthsOfAStop` — 0,016 stop; `HDRToneMapTests.theMergedSeriesToneMapsLikeTheCleanScene` — 55,5 dB |
| AC-2 | loạt 3 khung −2/0/+2 EV của cảnh 10 EV | ghép | vùng cháy ở EV 0 khôi phục, sai số ≤ 0,05 stop RMS; không còn điểm nào cháy ở ảnh ra | `HDRMergeTests.threeFramesRecoverTheReferencesClippedHighlights` — vùng cháy 0,011 stop, cả ảnh 0,017; `HDRToneMapTests.nothingIsLeftClippedAtAnyStrength` — 0 điểm trắng ở Strength 0/60/100 |
| AC-3 | loạt 5 khung chọn theo thứ tự xáo | ghép | cùng kết quả như thứ tự đúng; khung tham chiếu là khung EV 0 | `HDRBracketOrderTests.shuffledSelectionComesBackDarkestFirstWithTheMiddleAsReference`, `HDRMergeTests.aShuffledSelectionMergesToTheSamePicture` |
| AC-4 | loạt 5 khung, bước 3 EV, mỗi khung lệch tới ±30 px và xoay tới ±1,5° | căn | sai số căn ≤ 0,5 px ở 1536px cho mọi khung; không khung nào bị loại | `HDRMergeTests.alignsAcrossThreeStops` — 0,08–0,22 px ở 1536 (960 px, −6…+6 EV) |
| AC-5 | loạt có 1 khung ảnh khác cảnh chen vào | ghép | khung đó bị loại; panel ghi *1 of 6 frames couldn't be lined up and were left out.* | `HDRMergeTests.leavesOutAFrameFromAnotherScene`, `HDRStackModelTests.aStrayFrameIsLeftOutAndCounted` (câu trên panel) |
| AC-6 | một mảng kết cấu dịch 3 px mỗi khung, khung tham chiếu đọc được ở đó | ghép ở Off / Low / Medium / High | sai số ở vùng động ≥ 0,5 / ≤ 0,25 / ≤ 0,1 / ≤ 0,1 stop | `HDRDeghostTests.aSwayingPatchIsCaughtFromMediumUp` — 0,61 / 0,050 / 0,027 / 0,021 |
| AC-7 | loạt đứng yên, không gì di chuyển | ghép ở Medium; rồi High | ≤ 0,5% điểm ảnh tĩnh bị bỏ nhầm ở Medium; ≤ 3% ở High | `HDRDeghostTests.aStillSeriesKeepsAlmostEveryPixel` — 0% / 0% trên nhiễu đúng mô hình; nhiễu thật chưa đo (§9) |
| AC-8 | vật sáng di chuyển 70 px/khung trong vùng trời cháy ở EV 0 | ghép ở Medium | chỉ còn **một** bản của vật (lấy từ khung neo), không bóng chồng | `HDRDeghostTests.somethingMovingThroughClippedSkyComesOutOnce` — dọc vệt: Off 0,11, Medium 0,007 stop |
| AC-9 | màn HDR đang mở | đổi Deghost, rồi Strength | preview dựng lại, không nạp lại và không căn lại khung (đếm số lần đọc khung) | `HDRStackModelTests.optionsReRenderWithoutReadingFramesAgain` — 3 lần đọc khung trước và sau khi đổi Deghost, Strength |
| AC-10 | mở màn HDR | nhìn panel | Medium chọn sẵn; Strength 60; không có Auto Tone; câu giải thích hiện | `HDRStackModelTests.optionsReRenderWithoutReadingFramesAgain` (mặc định); `hdr-panel.json` ảnh `02-hdr-default` (iPhone 17, 26.5): Medium chọn sẵn, Strength 60, câu giải thích, không Auto Tone |
| AC-11 | 5 khung cùng phơi sáng (lệch < 0,5 EV) | mở màn | vẫn ghép; dòng báo *These photos have about the same exposure…* | `HDRBracketOrderTests.framesAtOneExposureAreFlagged`, `HDRStackModelTests.aSeriesAtOneExposureMergesAndSaysSo` |
| AC-12 | loạt 3 khung, khung tối nhất vẫn cháy 5% diện tích | mở màn | dòng báo *Some highlights are bright in every frame…* | `HDRStackModelTests.highlightsClippedInEveryFrameAreNamed` |
| AC-13 | preview 1600px và bản lưu của cùng loạt | thu bản lưu về 1600px rồi so | ≥ 32 dB — số tầng kim tự tháp theo cỡ ảnh | `HDRToneMapTests.thePreviewMatchesTheSave` — 35,1 dB (loạt ±2, cảnh 10 EV, 960→256). Fixture 14 EV cạnh cứng: 30,0 dB, nhưng chỉ clamp không tone map đã 30,7 — trần của phép đo, không phải của tone map |
| AC-14 | 5 khung RAW × 24 MP | Save trên iPhone 12 | footprint đỉnh ≤ 700 MB, ≤ 60 s; như nhau (± 10%) ở 3 khung | 🟡 simulator: `HDRExportTests.aFullSizeRAWSaveStaysUnderTheCeiling` (chạy theo yêu cầu: `touch build/measure-memory` rồi chỉ suite này — đo cả tiến trình nên chỉ có nghĩa khi chạy một mình, và trong full suite nó giữ GPU làm gate treo 2026-10-02) — 5 khung +533 MB / 18 s (HEIC +498 MB), 3 khung +407 MB / 13 s. iPhone 12 chưa đo; ±10% **không đạt** (−24%): mọi khung cùng mở là thiết kế của §6, nên bộ nhớ theo số khung |
| AC-15 | ảnh HDR đã lưu | xem EXIF trong viewer | máy, ống kính, ngày, vị trí của khung tham chiếu; không thời gian phơi, ISO, khẩu, Exposure Bias | `HDRMetadataTests.theReferencesGearStaysAndItsExposureGoes`, `HDRStackModelTests.saveWritesTheFormatAndTheReferencesMetadata` (EXIF của file đã lưu); viewer: ảnh ở task 11 |
| AC-16 | 2 khung chỉ có trên iCloud, máy mất mạng | mở màn | *2 photos couldn't be downloaded* + Retry; không ghép thiếu khung mà không báo | `HDRStackModelTests.aMissingFrameIsCountedNotDropped` (đường iCloud: `PhotoStackModel` chung với Focus Stack, FS-01.10 AC-12) |
| AC-17 | đang lưu | Cancel | không asset nào được tạo; thư mục tạm của phiên rỗng | `HDRExportTests.cancellingLeavesNoFile`, `HDRStackModelTests.cancellingTheSaveWritesNothing` |
| AC-18 | chọn 2 ảnh | mở ⋯ ▸ Combine Photos | bốn dòng Focus Stack · Panorama · HDR · Stack Exposures; chọn 1 ảnh thì dòng HDR mờ | `CombinePurposeTests.theSubmenuIsFourRowsInOrder`; ảnh menu bốn dòng: iPhone 26.5 `01-combine-menu`, iPad và Duo màn ngoài (mờ khi chưa chọn ảnh nào) |
| AC-19 | iPhone 26.5 + 18.6, iPad 13", Duo trong và ngoài | mở màn HDR với loạt 3 khung, đổi từng control, Save | ảnh từng trạng thái; không control bị cắt hay che; viewer mở ảnh vừa lưu | 🟡 iPhone 17 26.5: `hdr-panel.json` (menu, panel, Save As; viewer sau lưu đã chụp 2026-10-01); iPhone 16 **18.6**: `hdr-panel-18.json` (menu, panel, Save As); iPad Pro 13" dọc: `hdr-panel-ipad.json`; Duo màn ngoài: `hdr-panel-duo-cover.json` + `sim-shot`. Không cắt, không che. Board `PH19_HDR`, `PH20_HDRSaveAs`, `IPP13_HDR`, `DC13_HDR` trên canvas editor khớp dump trong 2 pt (`Tools/design-board compare`). **Chưa có:** Duo màn trong (simulator không mở gập được) |
| AC-20 | quyền ảnh `.limited`, cả loạt nằm trong tập được chọn | Save | ảnh mới hiện trong lưới Library | ⚠️ chưa có |
| AC-21 | loạt 3 CR3 + 2 JPEG | mở màn | ghép từ bản đã render của cả 5; dòng báo *Some of these photos aren't RAW…* | `HDRBracketOrderTests.aMixedSeriesIsFlaggedAndDoesNotMergeFromRAW`, `HDRFrameSourceTests.aRAWReadsLinearOrProcessed`, `HDRStackModelTests.aMixedSeriesSaysItUsesTheProcessedVersions` |
| AC-22 | Save, chọn HEIC | lưu | ảnh ra là HEIC; máy không ghi được HEIC thì báo trước và lưu JPEG | `HDRExportTests.writesTheFormatAskedFor`, `HDRStackModelTests.saveWritesTheFormatAndTheReferencesMetadata`; `hdr-panel.json` ảnh `05-save-format`: alert Save As JPEG · HEIC · Cancel (máy không ghi được HEIC: chỉ JPEG + câu báo — chỉ đọc code, simulator ghi được HEIC) |

## 9. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Chỉ có khung ảo; loạt chụp thật, nhiễu thật, đường tông JPEG của hãng chưa thử | `/verify` chạy trên loạt thật; ngưỡng deghost chỉnh lại |
| Nền bộ nhớ của bộ giải RAW trên iPhone chưa đo (~400 MB trên Mac) | đo trước tiên ở task đầu của `/plan`; AC-14 là cổng |
| Tone map cỡ đầy đủ theo lát trên GPU chưa được đo bộ nhớ | dựa trên bộ trộn đa dải của FS-14; AC-13 và AC-14 là cổng |
| Máy chụp 3 khung ±2 EV không đủ cho cảnh rất ngược sáng | nói ra (AC-12), không giả là đã khôi phục |
| Không trần số khung; bộ nhớ chỉ đo ở 5 khung | AC-14 đo 3 và 5 khung; `/plan` đo thêm 9 khung trước khi chốt |
| Fusion để viền tối (giá trị về 0) ở cạnh sáng/tối rất gắt: ~0,4% điểm ảnh trên loạt thử 10 EV cạnh cứng | xem trên loạt chụp thật ở `/verify`; ảnh thật ít cạnh 10 EV liền nhau |
