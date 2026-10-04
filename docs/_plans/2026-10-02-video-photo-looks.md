# Kế hoạch — Look ảnh cho video: một ô look cả video + một ô mỗi clip (FS-12.06c)

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-12.06c`](../02-functional-spec/FS-12-video-studio/06c-photo-looks.md) (16 AC — AC-16 thêm lúc duyệt) · [FS-12.06b §3](../02-functional-spec/FS-12-video-studio/06b-scopes-luts-and-tracking.md) (LUT là một loại look) · [FS-12.08 §2](../02-functional-spec/FS-12-video-studio/08-model-and-v1-limits.md) (project/clip giữ ô look) |
| Intent | [2026-09-30-user-wishes-research](../_intents/2026-09-30-user-wishes-research.md), mục 8 |
| Design | board trong repo — `F5_P_*` ở [`docs/design/iphone/project/`](../design/iphone/project/) · `F5_IL_Looks`, `F5_IP_Looks` ở [`docs/design/ipad/project/`](../design/ipad/project/) · `F5_DI_*`, `F5_DC_*` ở [`docs/design/duo/project/`](../design/duo/project/); board iPad vẽ lại kiểu Mac 2026-10-04 (commit `76df46d5`, xem khối M của [vs-wide-and-duo-layout](2026-10-03-vs-wide-and-duo-layout.md)). Hàng F5: `F5_P_Looks` · `F5_P_ClipLook` · `F5_DC_Looks` · `F5_DC_ClipLook` · `F5_DI_Looks` · `F5_DI_ClipLook` · `F5_IL_Looks` · `F5_IP_Looks`; dòng LUT mất trên `ES_P/DC/DI/IL_ExportSettings` — **4 board ES_* phải đổi chữ** theo spec (Q2, việc của canvas) |
| Phụ thuộc | intent [video-studio-canvas-chrome](../_intents/2026-10-03-video-studio-canvas-chrome.md) — khung Video Studio dựng lại theo canvas **trước** mọi task của plan này (người dùng chốt 2026-10-03) |
| Ngày | 2026-10-02 |
| Trạng thái | **approved 2026-10-03 — chờ intent video-studio-canvas-chrome (khung mới) xong mới code**. 16 task = 16 commit (task 16 là phép đo máy thật; chỉ commit nếu phải lật công tắc §5 của spec). Quyết định ở §6 |

> Dòng `Tiến độ` của intent đã ghi lúc duyệt 2026-10-03. Spec đã sửa theo §6 trong cùng commit duyệt. Task 1 chỉ
> bắt đầu khi khung mới của intent video-studio-canvas-chrome đã vào code: hàng đáy 5 ô, hàng lệnh clip có chỗ
> trước Delete, chân ✕ · tên · ✓ là nền mà panel Look gắn vào.

## 1. Hiểu đúng chưa

Video Studio hôm nay có **ba** thứ màu độc lập cho cả project: `filter` + `filterIntensity` (48 film look), `lut`
(LUT nhập, có `intensity` riêng), và chuỗi node. Spec gộp `filter` + `lut` thành **một ô look** có ba nguồn
(Presets · My Looks · LUTs) và một Amount, thêm **một ô look tuỳ chọn cho mỗi clip** thay (không chồng) look cả video.
My Look được **chép** vào project (không tham chiếu sống), nướng phần từng-pixel thành bảng 33³ khi chọn (cache 24
bảng), chạy Clarity/Texture/Sharpening/Dehaze, Vignette và Grain (đổi mẫu mỗi khung) từng khung, bỏ Noise Reduction và
hình học. Cả chuỗi grade (de-log → node → look của clip) chạy **trên từng clip trước khi trộn chuyển cảnh**, nên viền
letterbox không còn bị grade. Undo: một chạm = một bước; ✕ của panel trả về lúc mở, ✓ giữ. LUT mất file: phần đó như
không có, pill "· Missing", Export vẫn chạy với một dòng báo.

Không có migration (recipe là JSON trong `creations`, app chưa release — CLAUDE.md), không đụng `photo_metadata`.

## 2. Đối chiếu AC ↔ code

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 bảng 33³ (tone+HSL+curve+Velvia) lệch ≤ 1/255 so với chuỗi editor | ❌ (một phần) | Lưới 33³ + render qua `applyPreMaskStages` có ở `LookCubeBaker.swift:55-115`, nhưng ra **chuỗi `.cube`** (cho export) và chỉ test Mono (`LookExportCubeTests.swift:11-31`). `colourOnly` **bỏ Brilliance** (`LookCubeBaker.swift:21-38`) dù Brilliance là từng-pixel (`CIHighlightShadowAdjust` `inputRadius 0`, `PhotoRenderService.swift:1494-1507`, `:1548`, `:1564-1571`) | tách hàm dựng lưới dùng chung; `VideoLookBaker` (Domain) ra bảng float hai nửa (trước/sau Detail) có Brilliance; test 64×64 |
| AC-2 3 clip, My Looks → Moody Coast, All Clips → khung 1,0 s khớp editor ≤ 2/255; undo +1 | ❌ | Video không có My Looks: tool `filters` (`VideoStudioModel.swift:37`) chỉ dựng `FilterStrip` 48 film look (`VideoInspectorControls.swift:353-410`, `VideoStudioSheetHost.swift:568-580`); grain/vignette của look không có đường nào tới video | panel Look (task 6) + test render so với `PhotoRenderService.render` cùng look trên cùng khung |
| AC-3 cả video Velvia, clip 2 Night Teal → clip 2 chỉ Night Teal, chỉ clip 2 có pill | ❌ | `VideoClip` không có trường look (`VideoProjectModels.swift:106-175`); recipe ghi rõ "deliberately not per-clip" (`:471`); compositor grade một lần cho cả khung (`VideoFrameCompositor.swift:412-414`); `ClipBand` không có pill (`VideoTimelineTracks.swift:253-330`) | model ô look + resolver "clip thắng" + compositor theo clip + pill |
| AC-4 dissolve giữa hai look = trộn 50/50 hai khung đã grade; viền đúng màu nền | ⚠️ → tài liệu đúng, sửa code | Code làm **ngược**: hiệu ứng clip → `blend` → ghép lên nền → **rồi mới** `graded` cả khung (`VideoFrameCompositor.swift:381-414`), nên chuyển cảnh trộn ảnh chưa grade và viền letterbox bị grade theo | **Đã quyết: tài liệu đúng, sửa code** — thứ tự trong spec là điều kiện để có look riêng từng clip, và nền ra sai màu đã chọn là lỗi thấy được. Task 1 |
| AC-5 Amount 40 = 40% look + 60% khung trước look; undo +1; 0 = không look | ⚠️ → tài liệu đúng, sửa code | `filterIntensity` chỉ trộn phần film (`PhotoRenderService.swift:2217-2235`), LUT có `intensity` riêng (`VideoProjectModels.swift:446-458`, `VideoLUTRenderer.swift`), hai slider riêng (`VideoStudioSheetHost.swift:571-578`, `VideoColorPanel.swift:179-189`) | **Đã quyết: tài liệu đúng, sửa code** — một ô một Amount là điều spec chốt; trên video không có slider con nào để chỉnh phần còn lại. Task 4 |
| AC-6 NR 50 + Upright Auto + Grain 25 → "Skipped on video: Noise Reduction, Upright."; hai khung liền nhau khác mẫu hạt, σ ±10% | ⚠️ → tài liệu đúng, sửa code | Grain của kit cố ý **đứng yên** giữa các lần render (`PhotoRenderService.swift:1878-1880`, `CIRandomGenerator` theo toạ độ); không có danh sách "bỏ trên video" (chỉ có danh sách "mất trong .cube" `LookCubeBaker.swift:41-53`, khác tập) | **Đã quyết: tài liệu đúng, sửa code** — đứng yên đúng cho ảnh, sai cho video; thêm tham số `offset` (mặc định 0, ảnh không đổi). Task 5 |
| AC-7 Moody Coast sửa ở editor (lưu đè) → project vẫn Contrast 20, ô có viền; chạm lại → 60, undo +1 | ❌ | `LookPresetStore.save` lưu đè **giữ id** (`LookPresetStore.swift:175-196`, `:189`) — đúng cái cần để nhận ra "look gốc"; video chưa có bản chép | bản chép + id gốc trong ô; chạm ô đang chọn = lấy lại bản mới, giữ Amount |
| AC-8 LUT "Kodak 2383" đã xoá → clip 2 như không look; pill "· Missing"; Export chạy, có dòng báo | ❌ (một phần) | Renderer đã thoái hoá đúng: `VideoLUTRendererTests.aMissingFileLeavesTheFrameAlone`, `PhotoRenderService.applyLook` (`:2209-2215`); không có pill, không có dòng báo trong `VideoExportSheet.swift:18-60` | đếm ô mất LUT (cả LUT bên trong My Look) ở Domain; pill; chú thích; dòng Export |
| AC-9 Velvia → Moody Coast → Amount 70 → ✕ = không look, số bước undo như lúc mở | ❌ | panel công cụ không có ✕/✓: `titleButtons` cho `.none` là `EmptyView` (`VideoStudioSheetHost.swift:160-184`); undo là ngăn xếp ảnh chụp recipe, trần 40 (`VideoStudioModel.swift:597-660`) | `VideoLookSession` (Domain): ảnh chụp recipe + độ sâu undo lúc mở; ✕ khôi phục và cắt ngăn |
| AC-10 như AC-9, ✓ rồi Undo ×3 → Moody 100 → Velvia → không look | ❌ | như AC-9 | ✓ đóng phiên, không đụng ngăn undo |
| AC-11 playhead 7,0 s trong clip 2, This Clip, chạm Warm Fjord → chỉ clip 2; dòng phụ "Clip 2" (AC đã sửa lúc duyệt, Q4) | ❌ | không có đích; dòng phụ hiện là "N clips · 16:9" (`VideoStudioSheetHost.swift:146-158`); app gọi clip là "Clip 2" / "Photo 2" theo vị trí (`VideoViewerChrome.swift:77-93`), **không có tên địa điểm** nào để ra "· Coast" | đích + dòng phụ = tên clip của header viewer (Q4) |
| AC-12 clip 2 Night Teal, All Clips + Velvia → cả 3 Velvia, pill mất; một Undo trả Night Teal | ❌ | không có ô clip | luật All Clips xoá mọi ô clip trong **một** ảnh chụp undo |
| AC-13 Import Look… xmp → đầu My Looks, nhãn XMP, được chọn, editor thấy; cube → LUTs, được chọn; huỷ → không đổi | ❌ | Bộ nhập có sẵn và dùng chung kho: `LookExchangeModel.importTypes` (`LookExchangeModel.swift:31-33`), `startImport` (`:35-64`), `LookImportReportSheet`, kho chung trong `AppDependencies.swift:287-289`. Nhưng `PresetImporter.apply` chỉ trả báo cáo theo **tên** (`PresetImporter.swift:117-170`), không trả id look/LUT vừa thêm → không chọn được nó. Video có bộ nhập `.cube` riêng (`VideoColorPanel.swift:105-120`) | `apply` trả thêm id đã thêm; Video gọi đúng `LookExchangeModel` của editor; bỏ bộ nhập riêng |
| AC-14 khớp **cả board** F5_P/F5_DC/F5_DI/F5_IL ≤ 2pt; ô 70/60/66/72; Apply To tới được | ⚠️ → khung dựng lại trước (intent riêng) | Chrome nền của canvas **khác code từ trước 06c**: canvas có hàng đáy 5 ô `Media · Text · Sticker · Music · Look` không cuộn (`Main`, `DC1`, `DI1`), hàng lệnh clip `Split · Trim · Speed · Volume · Replace · Freeze · Duplicate · (Look) · Delete` ô 64×56 (`P2_ClipSelected`), chân ✕ · tên · ✓, cột phải Duo trong 264; code có hàng công cụ 10 ô cuộn dựng từ `GlobalTool.allCases` (`VideoStudioToolbar.swift:44-55`), lệnh clip `Split · Mute · Animate · Replace · Freeze` ô 52×54, Delete là thùng rác ở dòng tiêu đề (`VideoStudioSheetHost.swift:609-635`, `:632`; `VideoStudioMetrics.swift:645-646`), sheet 264 (`:311`), cột inspector 320 (`:33`), rail 92 (`:281`). Các board nền ghi "đề xuất 2/10", không FS nào sở hữu | **Đã quyết (Q1):** khung Video Studio dựng lại theo canvas bằng intent riêng [video-studio-canvas-chrome](../_intents/2026-10-03-video-studio-canvas-chrome.md), **trước** plan này; AC-14 giữ nguyên là khớp cả board. Task 15 |
| AC-15 HEVC 4K 30 fps, Moody + Clarity 30 + Texture 20 + Dehaze 15, preview 1280, máy thật → ≤ 3 khung rơi /10 s kể cả dissolve | ❓ | chưa đo — spec §9 yêu cầu đo **trước** `/plan`, phiên này không có máy thật. Chuỗi hôm nay đã chạy grade cả khung mỗi khung; sau task 1 một dissolve chạy grade **hai lần** | để cuối (task 16): đo trên iPhone 17 + iPad; trượt thì lật công tắc `VideoLookNeighbourPolicy` → bỏ cả bốn ở preview **và** export, chú thích nêu tên (spec §5) |

Không AC nào ✅: ngoài trần undo 40 (`VideoStudioModel.swift:599`) và kho look/LUT dùng chung, mọi mệnh đề đều cần code mới.

**Spec có, AC không có** (làm kèm test trong task gần nhất; `/verify` sẽ báo "có test, không có AC"):
~~Use Video Look~~ (nay là **AC-16**, Q7), gradient thay ô khi chưa có ảnh / iCloud offline (§3, §7), Amount
ẩn khi Original (§3), VoiceOver đọc tên look + "imported from Lightroom" + nhãn clip (§7), Split/Freeze giữ look của
clip (không nói trong spec — quyết định kỹ thuật §6).

## 3. Tái dùng

| Có sẵn | Dùng cho |
|---|---|
| `LookCubeBaker` — lưới sRGB 33³ + `applyPreMaskStages` | tách `latticeImage()` + `renderTable(of:recipe:)` dùng chung cho `.cube` export và video; **không** viết lưới thứ hai |
| `PhotoRenderService` các bước tĩnh (`applyLight`, `applyColor`, `applyCurve`, `applyLook`, `applyDetail`, `applyDehazePass`, `applyEffects`, `applyGrain`, `applyLUT`) | toàn bộ phép tính của look; video chỉ chia chúng thành "nướng vào bảng" và "chạy mỗi khung" |
| `LookPresetStore` (lưu đè giữ id, `source == .imported`, `displayName(of:)` cho tên preset đã đổi) | My Looks, nhận ra look gốc (AC-7), nhãn XMP, tên preset |
| `ImportedLUTStore` + `ImportedLUTFiles.table(for:)` + `LUTTableCache` (4 bảng, đọc file) | nguồn LUTs; cache 4 chỉ còn nuôi lượt nướng (FS-12.06b §3) |
| `LookExchangeModel` + `LookImportReportSheet` + `PresetImporter` | Import Look… (AC-13) — cùng picker, cùng báo cáo, cùng kho |
| `EditorPresetSource` (`EditorChromeModel.swift:222-245`: Presets · My Looks · LUTs, icon) | ba tab nguồn trong panel video |
| `swatchColors(for:)` của editor (`EditorToolPanels.swift:688-720`, đang `private` trong view) | chuyển về Domain (`LookSwatch`) để editor và video cùng một luật gradient hai tông |
| `VideoFilterThumbnails` (ảnh clip dưới playhead, `allowNetwork: false`) | mở rộng thành `VideoLookThumbnails` cho cả My Looks/LUTs (qua bảng đã nướng) — giữ luật không tải iCloud chỉ để vẽ ô |
| `VideoCompositionBuilder.videoComposition` lấy hiệu ứng/fade **từ recipe mới** theo `clipID` (`VideoCompositionBuilder.swift:254-310`) | look của clip đi đúng đường đó → đổi look chỉ là tầng "video composition", không dựng lại AVComposition |
| `InspectorSlider` (begin/endUndoGroup quanh một lần kéo) | Amount = một bước undo (AC-5) |
| `VideoViewerChrome.clipTitle` ("Clip 2" / "Photo 2") | dòng phụ "Look · Clip 2" (AC-11) — chuyển về `VideoClip`/Domain để hai chỗ một luật |
| `VideoSplitMath.copy` | thêm `look` để Split giữ look |

## 4. File đổi và tầng

| File | Tầng | Đụng gì | Mới / sửa |
|---|---|---|---|
| `Domain/Video/VideoProjectModels.swift` | Domain | `VideoLook { source: .preset(PhotoFilter) · .myLook(sourceID, name, isImported, recipe) · .lut(id, name); amount }`; `VideoProjectRecipe.look: VideoLook?` thay `filter`/`filterIntensity`/`lut`; `VideoClip.look: VideoLook?` (nil = theo cả video, `.preset(.original)` = Original riêng); xoá `VideoLUTReference.intensity` | sửa |
| `Domain/Video/VideoLookEditing.swift` | Domain | thuần: `effectiveLook(for:in:)`, đích (All Clips / This Clip / Selected), All Clips xoá ô clip, chạm lại = lấy bản chép mới giữ Amount, look mới Amount 1, `pillText`, `missingLUTLooks(in:lutExists:)`, `skippedOnVideo(_:)` + chữ chú thích, dòng phụ tiêu đề | mới |
| `Domain/Video/VideoLookSession.swift` | Domain | ảnh chụp recipe + độ sâu undo lúc mở panel; `cancel` / `commit` | mới |
| `Domain/Video/VideoLookBaker.swift` | Domain | look → `VideoLookRenderPlan` (bảng trước Detail, bảng sau Detail, tham số Detail/Dehaze, vignette, grain); khoá nội dung | mới |
| `Domain/Editing/LookExchange/LookCubeBaker.swift` | Domain | tách lưới + render bảng dùng chung; `.cube` export giữ nguyên đầu ra | sửa |
| `Domain/Editing/LookSwatch.swift` | Domain | gradient hai tông chuyển từ `EditorToolPanels.swift:688-720` | mới (editor gọi lại) |
| `Domain/Editing/LookExchange/PresetImporter.swift` | Domain | `apply` trả thêm id look/LUT đã thêm, theo thứ tự file | sửa |
| `ShotDexKit/Render/PhotoRenderService.swift` | Kit | `applyGrain(…, offset: CGPoint = .zero)`; `applyDetail` / `applyDehazePass` thêm `radiusScale: Double = 1`, `public` | sửa (mặc định giữ ảnh y hệt) |
| `Data/Sources/VideoLookTableCache.swift` | Data | LRU **24 bảng** (đếm bảng, không đếm look), khoá NSLock, `prepare(_:) async` (ngoài main) + `tables(for:)` đồng bộ (export/scope, nướng khi trượt) | mới |
| `Data/Sources/VideoFrameCompositor.swift` | Data | grade từng bên trước `blend`; nền không grade; `VideoRenderRecipe` giữ look đã giải theo `clipID`; tách `composeFrame(...)` tĩnh để test bằng CIImage | sửa |
| `Data/Sources/VideoMaskRenderer.swift` | Data | tham số `extent` (window giữ toạ độ canvas khi ảnh vào chỉ còn khung clip) | sửa |
| `Data/Sources/VideoCompositionBuilder.swift` | Data | `ClipRenderTiming` mang `clipID` + look; số khung cho grain | sửa |
| `Data/Sources/VideoLUTRenderer.swift` | Data | gỡ (LUT đi qua bảng đã nướng) hoặc chỉ còn dùng cho test | sửa / gỡ |
| `Features/VideoStudio/VideoStudioModel.swift` | Features | `GlobalTool.filters` → `.look`; `setLook(_:target:)`, `setLookAmount`, `useVideoLook(clipIDs:)`, phiên ✕/✓, pre-warm cache rồi `applyVideoTier`; `setShowsOriginal` tước cả look của clip; bỏ `setFilter*`/`setLUT*` | sửa |
| `Features/VideoStudio/VideoLookPanel.swift` | Features | panel Look: tiêu đề ✕ ✓ + dòng phụ, chip Filter · Adjust · Color, ba tab nguồn, ô (70/60/66/72), Amount, Apply To, chú thích, Import Look…; khối LOOK FOR THIS CLIP + Use Video Look (trắng) | mới |
| `Features/VideoStudio/VideoLookThumbnails.swift` | Features | thay `VideoFilterThumbnails` | mới (gỡ cái cũ) |
| `Features/VideoStudio/VideoStudioSheetHost.swift`, `VideoStudioToolbar.swift`, `VideoInspectorControls.swift` (gỡ `FilterStrip`), `VideoColorPanel.swift` (gỡ mục LUT + bộ nhập riêng), `VideoMediaPoolColumn.swift` (tab Effects, Q3), `VideoTimelineTracks.swift` (pill trên `ClipBand`), `VideoExportSheet.swift` (dòng LUT mất), `VideoScopeModel.swift` (grade theo clip dưới playhead), `VideoStudioMetrics.swift` (hình học panel Look theo máy) | Features | như cột trước | sửa |
| ~~`Tools/design-board`~~ | Tools | ~~`--offset-x`~~ — không cần: Q1 chốt khớp cả board sau khung mới, không so riêng khối panel | — |
| `ShotDexTests/VideoLook{Baker,Editing,Session,Render}Tests.swift`, `LookExportCubeTests` (giữ xanh), `VideoSplitMathTests` (+look) | Test | | mới / sửa |
| `ShotDexUITests/scripts/video-look-*.json` | Test | route `ui-drive` từng máy | mới |

Logic nằm ở Domain (thuần, test được) và Data (compositor, cache); View chỉ đọc. Không bảng GRDB mới, không migration.

## 5. Thứ tự task

Một AC = một task = một commit `feat(FS-12.06c): AC-n …`, `/build` sau mỗi commit, `/screens` + `design-parity` khi
đụng UI. Không có ✅; ⚠️ đi trước khi nền đã đủ (AC-4 làm được ngay trên model cũ), ❌ theo phụ thuộc. **Cả bảng chỉ bắt đầu
sau khi khung mới (intent video-studio-canvas-chrome) đã vào code.**

| # | Task | AC | Test kèm theo |
|---|---|---|---|
| 1 | Compositor: de-log + node + look chạy **từng bên** trước `blend`, rồi mới ghép lên nền; tách `composeFrame` tĩnh; `VideoMaskRenderer` nhận `extent` canvas | AC-4 ⚠️ | `VideoLookRenderTests.dissolveMixesTwoGradedFrames` (hai khung grade riêng, tiến độ 0,5, ≤ 1/255), `letterboxKeepsTheChosenBackground` (9:16 trên 16:9, pixel viền = màu nền đúng byte), `windowStaysWhereDrawnOnLetterboxedClip` |
| 2 | `VideoLookBaker` + lưới dùng chung với `LookCubeBaker`; Brilliance vào bảng; **đo thời gian nướng** mỗi look trên sim | AC-1 | `VideoLookBakerTests.tableMatchesEditorChain` (Exposure, Contrast, HSL, curve, Velvia; 64×64; ≤ 1/255), `brillianceIsBaked`, `LookExportCubeTests` vẫn xanh; log `bake ms` cho 10 look mẫu |
| 3 | Model `VideoLook` trên recipe + clip; resolver "clip thắng" (kể cả Original); `VideoLookTableCache` 24 bảng; compositor theo `clipID`; pill trên `ClipBand`; Split/Freeze giữ look | AC-3 | `VideoLookEditingTests.clipLookReplacesVideoLook`, `originalOnClipBeatsVideoLook`; `VideoLookRenderTests.middleFramesUseOwnLook` (clip 2 = Night Teal một mình ≤ 1/255); `pillOnlyOnClipsWithOwnLook`; `VideoSplitMathTests.splitKeepsLook`; `cacheEvictsBeyond24Tables` |
| 4 | Một Amount trộn **cả** look với khung trước look; Amount ẩn khi Original; look mới = 100 | AC-5 ⚠️ | `amountMixesWholeLook` (40 → 40/60 ≤ 1/255; 0 = không look); model: một lần kéo = +1 undo |
| 5 | Phần chạy mỗi khung: Clarity/Texture/Sharpening/Dehaze với `radiusScale = cạnh dài / 1920`; Vignette theo khung clip; Grain `offset` theo số khung; bỏ NR + hình học; chú thích "Skipped on video: …" / "Everything in this look applies to video."; công tắc `VideoLookNeighbourPolicy` | AC-6 ⚠️ | `skippedLineNamesNoiseReductionAndUpright`, `grainChangesEveryFrame` (hai khung liền: khác mẫu, σ ±10%), `neighbourRadiusScalesWithFrame` (1280 vs 3840 cùng ảnh sau khi thu về một cỡ), `PhotoRenderService` grain mặc định không đổi (test ảnh có sẵn) |
| 6 | Panel Look cả video trên 4 máy, gắn vào khung mới (ô **Look** của hàng đáy 5 ô, intent video-studio-canvas-chrome): `GlobalTool.look`, tiêu đề ✕ ✓ "Look · Whole video", chip Filter · Adjust · Color, Presets · My Looks · LUTs, ô + gradient (`LookSwatch`), nhãn XMP, Amount, Apply To, chú thích; gỡ `FilterStrip`, mục LUT trong Color, tab Effects của media pool iPad (Q3, FS-12.04 §2 đã sửa); sheet điện thoại cao 340 cho công cụ Look | AC-2 | `VideoLookRenderTests.myLookMatchesEditorAtOneSecond` (3 clip, Moody Coast, ≤ 2/255, cùng `offset` hạt cho ảnh editor); route `video-look-whole.json` (iPhone 26.5 + 18.6) — undo +1; ảnh chụp |
| 7 | All Clips đặt look cả video **và** xoá mọi ô clip — một ảnh chụp undo | AC-12 | `allClipsClearsClipLooksInOneStep`, `undoBringsBackNightTeal` |
| 8 | This Clip → clip dưới playhead; dòng phụ = tên clip của header viewer, "Clip 2" / "Photo 2" (Q4; `clipTitle` chuyển về Domain) | AC-11 | `thisClipTargetsClipUnderPlayhead` (7,0 s → clip 2), `subtitleNamesTheClip`, look cả video không đổi |
| 9 | Phiên panel: ✕ trả recipe lúc mở, cắt ngăn undo về độ sâu lúc mở | AC-9 | `VideoLookSessionTests.cancelRestoresAndLeavesNoUndo` |
| 10 | ✓ giữ từng bước | AC-10 | `commitKeepsEachStep` (Undo ×3: Moody 100 → Velvia → không look) |
| 11 | My Look là bản chép + id gốc; ô gốc có viền; chạm ô đang chọn = lấy bản mới, giữ Amount, +1 undo; look gốc bị xoá vẫn render | AC-7 | `copyIgnoresLaterEditUntilRetaken` (lưu đè Contrast 20 → 60 qua `LookPresetStore.save`; recipe mã hoá/giải mã như mở lại project), `retakeKeepsAmount`, `deletedSourceStillRenders` |
| 12 | LUT mất: phần LUT như không có (kể cả LUT trong My Look), pill "Kodak 2383 · Missing", chú thích, dòng Export (Q2); nhập lại không tự nối | AC-8 | `missingLUTRendersAsNoLook`, `missingLUTInsideMyLookKeepsTheRest`, `exportLineCountsLooks` (1, 2 — plural trong catalog); ảnh chụp sheet Export |
| 13 | Import Look… gọi `LookExchangeModel` của editor; `PresetImporter.apply` trả id; look vừa nhập được chọn cho đích hiện tại; huỷ picker không đổi | AC-13 | `PresetImportTests.applyReturnsAddedIDsInFileOrder`; `importSelectsFirstAddedForTarget` (xmp → My Looks, cube → LUTs); route `video-look-import.json` (fixture qua `importFixturesIfAsked`) |
| 14 | Look riêng từ clip: ô **Look** trong hàng lệnh clip ngay trước Delete (điện thoại/Duo, hàng của khung mới), khối LOOK FOR THIS CLIP trong inspector clip (iPad), This Clip · Selected · All Clips (**Selected luôn hiện**, tắt khi < 2 clip, Q5), **Use Video Look** chữ trắng (Q6), +1 undo | **AC-16** (Q7) | `VideoLookEditingTests.useVideoLookRemovesClipLookInOneStep` (clip 2 Night Teal → Use Video Look → clip 2 render Velvia, không pill, undo +1), `selectedDisabledBelowTwoClips`; route `video-look-clip.json`; ảnh chụp 4 máy |
| 15 | Hình học panel theo board: ô 70/60/66/72, Amount 40/36/34, Apply To tới được trên Duo trong 669; `design-parity` **cả board** F5 (chrome đã khớp nhờ intent video-studio-canvas-chrome, Q1) | AC-14 | `VideoStudioLayoutTests.lookPanelFitsEveryDevice` (đo theo `VideoStudioMetrics`), `design-board compare` ≤ 2pt trên cả 8 board F5; `Tools/sim-shot` cho Duo (trong/ngoài) và iPad |
| 16 | Đo máy thật iPhone 17 + iPad: 10 s HEVC 4K có dissolve; đo lại thời gian nướng trên iPhone 17. Trượt → lật `VideoLookNeighbourPolicy` (preview + export cùng bỏ, chú thích nêu tên) | AC-15 ❓ | Instruments/`CADisplayLink` đếm khung rơi; chỉ commit khi lật công tắc |

## 6. Quyết định (người dùng duyệt 2026-10-03)

Người dùng chấp nhận mọi đề nghị, **trừ Q1**: khung Video Studio phải khớp canvas **trước**, bằng một intent riêng.

| # | Chỗ lệch | Quyết định | Đổi trong spec / plan |
|---|---|---|---|
| Q1 | Chrome nền canvas ≠ code (AC-14, §3 "hàng đáy 5 ô", "trước Delete", ô 64×56, cột 264, rail 84) | **không** thu AC-14 về khối panel. Khung Video Studio dựng lại theo canvas bằng intent riêng [video-studio-canvas-chrome](../_intents/2026-10-03-video-studio-canvas-chrome.md), làm **trước**; plan này chờ nó xong mới code. AC-14 giữ là **khớp cả board** ≤ 2pt | FS-12.06c AC-14 ghi "cả board, đo sau khung mới"; trạng thái plan; task 6, 14, 15; bỏ `--offset-x` |
| Q1a | Ô Look nằm đâu khi chưa có hàng 5 ô | theo spec §3 như canvas: **Look** ở hàng đáy 5 ô (cả video), ô **Look** ngay trước Delete trong hàng lệnh clip — cả hai do khung mới cung cấp | không đổi spec; task 6, 14 |
| Q2 | Dòng LUT mất ở Export: spec "1 look is missing its LUT and exports without it." vs board ES_* "1 clip uses a missing LUT — it renders without it." | **tài liệu đúng**. Canvas phải đổi dòng đó trên **4 board**: `ES_P_ExportSettings`, `ES_DC_ExportSettings`, `ES_DI_ExportSettings`, `ES_IL_ExportSettings` → "1 look is missing its LUT and exports without it." | không đổi spec; việc của canvas (người giữ canvas); task 12 so với board sau khi sửa |
| Q3 | Tab **Effects** của media pool iPad vẫn đặt filter cả video; board `IL1`/`F5_IL` không có tab này | **bỏ tab Effects** | FS-12.04 §2 đã sửa (Filter → công cụ Look); task 6 |
| Q4 | AC-11 dòng phụ "Clip 2 · Coast" — app không có tên địa điểm cho clip | dòng phụ = **tên clip của header viewer** ("Clip 2" / "Photo 2") | FS-12.06c §3 (chân iPad), §4, AC-11; task 8 |
| Q5 | "Selected (khi chọn ≥ 2 clip)" — chọn trong Video Studio là một đích | **Selected luôn hiện, tắt khi < 2 clip**; sống khi có chọn nhiều | FS-12.06c §4; task 14 |
| Q6 | "Use Video Look (12.5, accent)" | **chữ trắng** (canvas v23; accent chỉ cho hành động chính) | FS-12.06c §3; task 14 |
| Q6b | "nhãn XMP góc trên phải, như ở editor" — editor ghi "Imported" dưới tên | **"như canvas"**; editor đổi theo là mục riêng trong `REVIEW_QUEUE.md` (FS-03.14), đã ghi lúc duyệt | FS-12.06c §3; `REVIEW_QUEUE.md` |
| Q7 | Use Video Look không có AC | **thêm AC-16**: "clip 2 Night Teal → Use Video Look → clip 2 theo look cả video, pill mất, undo +1" | FS-12.06c §8 có AC-16; task 14 |
| AC-4/5/6 | thứ tự grade, một Amount, hạt mỗi khung | **tài liệu đúng, sửa code** như plan đề nghị | task 1, 4, 5 |

**Quyết định kỹ thuật (tự chốt, ghi lại để review):**
- **Hai bảng khi có Detail:** look có Clarity/Texture/Sharpening/Dehaze → bảng 1 = calibration + light (gồm Brilliance), rồi bốn phép lân cận, rồi bảng 2 = color + curve + film/LUT — đúng thứ tự `RenderPass` của ảnh (`PhotoRenderService.swift:450-477`); không có Detail → gộp một bảng. Cache 24 đếm **bảng** nên vẫn ≤ ~14 MB.
- **Mọi look (kể cả LUT chọn thẳng) đi qua bảng 33³ đã nướng**: cache 4 bảng của `LUTTableCache` chỉ còn nuôi lượt nướng, project có 5 clip mỗi clip một LUT không đọc lại file text mỗi khung. FS-12.06b §3 đã sửa lúc duyệt 2026-10-03.
- **Nướng khi chọn, ngoài main** (`prepare` rồi mới `applyVideoTier`); compositor trượt cache thì nướng đồng bộ một lần (export không cần thời gian thực; preview chỉ trễ một khung).
- **Window giữ toạ độ canvas** dù ảnh vào node chỉ còn khung clip (tham số `extent`), vì người dùng vẽ window trên khung xem.
- **"Lens Correction" chỉ vào chú thích khi look mang chỉnh tay** (distortion, vignetting, CA, defringe khác 0); bật profile tự động không tính — nó nói về ống kính của ảnh, không phải lựa chọn của look.
- **Split và Freeze giữ look của clip; Replace bỏ** (media mới, như trim/speed hôm nay).
- **Nhãn XMP** hiện cho mọi look `source == .imported` (canvas), kể cả từ `.lrtemplate`/`.dng`.
- Tile My Looks/LUTs vẽ bảng + vignette, không hạt/không lân cận (ở 70pt không thấy, và giữ 50 lượt nướng rẻ).

## 7. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| **Hiệu năng:** dissolve chạy chuỗi grade **hai lần** + bốn phép lân cận > 33,3 ms (AC-15) | trung bình | công tắc `VideoLookNeighbourPolicy` dựng sẵn ở task 5; đo máy thật task 16; trượt → bỏ cả bốn ở preview **và** export |
| Nướng > 50 ms/look; My Looks 50 look = 50 lượt nướng cho ô | trung bình | đo trên sim ở task 2 (chỉ báo hiệu), xác nhận iPhone 17 ở task 16; ô điền dần, gradient trong lúc chờ; huỷ khi playhead sang clip khác |
| **Bộ nhớ:** 24 bảng × 575 KB ≈ 14 MB thêm vào compositor; extension sửa ảnh có trần ~120 MB (FS-12 AC-14) | thấp | LRU theo số bảng; `memory-leak` kiểm; không giữ ảnh tile ngoài `VideoLookThumbnails` |
| **Concurrency:** cache đọc từ hàng đợi compositor của AVFoundation và ghi từ task nướng | trung bình | `NSLock` như `LUTTableCache`/`StillFrameStore`; bảng bất biến sau khi nướng; `swift-concurrency` review |
| Đổi thứ tự grade (task 1) dời window/qualifier sang khung clip | trung bình | tham số `extent` canvas + test `windowStaysWhereDrawnOnLetterboxedClip`; tracker lưu delta nên không đổi |
| Scope đo sai clip sau khi look theo clip | thấp | `VideoScopeModel` lấy look đã giải của clip dưới playhead (task 3); FS-12.06c §4 câu cuối |
| HLG/log chưa de-log bị bảng 0…1 cắt | thấp | de-log đứng đầu chuỗi (spec §9 đã chấp nhận) |
| **Duo trong 669pt:** cột phải phải cuộn tới Apply To / Import | trung bình | cột cuộn được (`columnBody` đã là `ScrollView`); AC-14 đo "tới được" bằng dump sau khi cuộn |
| **XCUITest không liệt kê được Video Studio trên điện thoại** (memory `ui-driver-xcuitest`) | cao | dump `{"type":"button"}` + `Tools/sim-shot`; so board bằng ảnh + nút, không đòi cây đầy đủ |
| Kit đổi chữ ký `applyGrain`/`applyDetail` | thấp | tham số mặc định giữ ảnh y hệt; test ảnh vàng có sẵn phải xanh; `extension-boundary` |
| PhotoKit: ô vẽ từ clip iCloud-only khi offline | thấp | giữ `allowNetwork: false` (`VideoFilterThumbnails.swift:60-66`), gradient thay thế |
| Không migration: project cũ có `filter`/`lut` mở ra không look | chấp nhận | app chưa release (CLAUDE.md); decode vẫn khoan dung (khoá thừa bị bỏ qua) |
| Hai agent một checkout | thấp | `git commit -- <paths>`, không `add -A` (memory) |

## 8. Phản biện (điền sau khi chạy `challenger`)

| Phản đối | Trả lời / thay đổi |
|---|---|
| … | … |

## 9. Cách chứng minh là xong

- **Test** (`/test`): `VideoLookBakerTests` (AC-1), `VideoLookRenderTests` (AC-2, 3, 4, 5, 6, 8), `VideoLookEditingTests`
  (AC-3, 7, 11, 12, 13, Use Video Look), `VideoLookSessionTests` (AC-9, 10), `PresetImportTests` (AC-13),
  `VideoSplitMathTests`, `LookExportCubeTests` (không đổi đầu ra `.cube`), `VideoStudioLayoutTests` (AC-14). Full suite
  một lần cuối intent (`Tools/gate`).
- **Màn hình** (`/screens video-look`), iOS 26.5 + 18.6 (tier D không rẽ nhánh, vẫn chụp cả hai):
  iPhone 402×874 · Duo ngoài 466×678 · Duo trong 951×669 · iPad 13" ngang 1376×1032 · iPad dọc 1032×1376 (`Tools/sim-shot`
  cho Duo và iPad). Trạng thái: Look cả video (Presets / My Looks có XMP / LUTs), Amount ẩn ở Original, This Clip với dòng
  phụ, LOOK FOR THIS CLIP + Use Video Look, pill trên lane, pill "· Missing" + chú thích, sheet Export có dòng LUT mất,
  gradient khi chưa có ảnh, báo cáo Import Look….
- **design-parity**: 8 board F5 **cả board** (+ dòng LUT mất trên 4 board ES_* sau khi canvas sửa chữ, Q2) ≤ 2pt; render board từ
  `docs/design/<thiết bị>/project/` trước khi chạy.
- **Đo**: thời gian nướng/look (sim, task 2; iPhone 17, task 16); khung rơi 10 s (iPhone 17 + iPad thật, task 16).
- **Tài liệu** cùng commit task: cột "Chứng minh bằng" của FS-12.06c từng AC; FS-12.07 §5 dòng "Preview filter thật
  ô 62pt" (tab Effects đã bỏ — task 6); FS-12.01 (thứ tự grade trước chuyển cảnh — task 1). **Đã sửa lúc duyệt
  2026-10-03:** FS-12.06c (Q4/Q5/Q6/Q6b/Q7, AC-14, AC-16), FS-12.04 §2 (Q3), FS-12.06b §3 (cache 4 chỉ cho lượt nướng).
  DESIGN.md nếu ô look video
  thành component dùng chung với editor (`LookSwatch`).
- Ngoài phạm vi: `.cube` export liệt Brilliance là "mất" dù nó từng-pixel (`LookCubeBaker.swift:45`, spec §9 hàng
  cuối) → `REVIEW_QUEUE.md` khi làm task 2; nhãn "Imported" của editor đổi sang XMP (Q6b) → **đã ghi** `REVIEW_QUEUE.md`;
  chrome nền theo canvas (Q1) → intent video-studio-canvas-chrome, không phải REVIEW_QUEUE.

## 10. Agent ở giai đoạn Deploy

| Agent | Vì sao |
|---|---|
| `design-parity` | 8 board F5 + ES_* (AC-14), lặp tới khi qua |
| `device-layout` · `duo-ux-review` | panel Look trên iPhone, iPad hai hướng, Duo 669 và Duo ngoài sau rail |
| `perf-profiler` | chi phí mỗi khung: hai lượt grade trong dissolve, bốn phép lân cận, grain mỗi khung (AC-15) |
| `swift-concurrency` | nướng ngoài main, cache đọc trên hàng đợi compositor, huỷ lượt nướng tile |
| `memory-leak` | cache 24 bảng, ảnh tile, trần extension |
| `extension-boundary` | API kit mới (`offset`, `radiusScale`) `public`, không kéo app-only type vào kit |
| `ios26-parity` | tập action của panel Look giống nhau trên 26.5 và 18.6 |
| `a11y-voiceover` | nhãn ô "Look Moody Coast, imported from Lightroom, selected", nhãn clip "Look Night Teal", Use Video Look |
| `localization` · `copy-consistency` | chuỗi mới, plural dòng Export; "Amount" thay "Intensity"/"Strength", "Look" thay "Filter" |
| `photokit-guard` | ô vẽ từ clip iCloud-only không gọi mạng |
