# Kế hoạch — Phụ đề tự động (F4) · Trước/sau (F7) · Preset xuất (F8)

| Trường | Giá trị |
|---|---|
| Đặc tả | [`FS-12.14`](../02-functional-spec/FS-12-video-studio/14-captions.md) (17 AC) · [`FS-12.15`](../02-functional-spec/FS-12-video-studio/15-before-after.md) (15 AC) · [`FS-12.16`](../02-functional-spec/FS-12-video-studio/16-export-presets.md) (17 AC) — **49 AC** |
| Intent | [2026-10-03-video-studio-canvas-chrome](../_intents/2026-10-03-video-studio-canvas-chrome.md) — thứ tự build: chrome/thanh dưới → chọn item → Media → Video Settings/Export → Look (06c) → kích thước → **F1–F8**. Plan này là ba khúc F4, F7, F8 của bước cuối |
| Design | canvas Video Studio <https://claude.ai/artifact/B8NqQqRHcHoFknxQ9gHZPJ> (bản đang chạy `1790981542-377a`, khớp spec theo người giữ canvas). Hàng F4: `F4_P/IL/IP/DI/DC_Captions` · F7: `F7_P/IL/IP/DI/DC_BeforeAfter` · F8: `F8_P/IL/IP/DI/DC_ExportPresets`. Đã xuất 15 board + `canvas.json` về `build/design/video/project/` (2026-10-03). **Ba board spec ghi "chưa có" nay đã có:** `F4_IP_Captions`, `F7_DC_BeforeAfter`, `F8_IP_ExportPresets` (xem Q4). Pill Before/After của `F7_P` đã ở y 70 như spec |
| Phụ thuộc | xem §7 — plan chrome (FS-12.03/03b/07/07b), plan tools/chọn item (FS-12.04/04b), plan **vs-media-settings-export** (FS-12.09/10/10b), plan look [2026-10-02-video-photo-looks](2026-10-02-video-photo-looks.md) (FS-12.06c), plan F3 ducking (FS-12.13) |
| Ngày | 2026-10-03 |
| Trạng thái | **approved 2026-10-03** — bước **7** của thứ tự xây. 49 task = 49 commit (task 32 là phép đo máy thật, chỉ commit nếu phải bật đường lùi nửa độ phân giải) |

> Dòng `Tiến độ` của intent ghi lúc duyệt 2026-10-03.

## Duyệt 2026-10-03

- **Trạng thái:** approved 2026-10-03 — người dùng duyệt cả sáu plan Video Studio với mọi khuyến nghị đúng như từng
  plan đề nghị ("tài liệu đúng" / "code đúng"), kèm các câu trả lời sản phẩm dưới đây. Spec đã sửa trong cùng commit
  duyệt. Plan này là **bước 7** của thứ tự xây.
- **Thứ tự xây cả intent** (người dùng chốt 2026-10-03): 1 `vs-tools-selection-phone` khối 0, A–D (+ khối N lưu
  nháp) → 2 `vs-wide-and-duo-layout` task 4–15 → 3 `vs-media-settings-export` → 4
  [`2026-10-02-video-photo-looks`](2026-10-02-video-photo-looks.md) → 5 `vs-tools-selection-phone` khối E +
  `vs-wide-and-duo-layout` task 16–18 → 6 `vs-multiselect-beats-ducking` → 7 `vs-captions-compare-presets` → 8
  `vs-precise-trim-input` (task 1–2 của nó — bước driver, chỉ đụng `ShotDexUITests/` — được làm trước).
- **Task code đầu tiên của cả chuỗi là bộ giải mã khoan dung** cho `VideoProjectRecipe` (+ `VideoClip`, `MusicTrack`,
  `TimedOverlay`; mảng qua `LossyArray`) — **task 4 của `vs-tools-selection-phone` sở hữu**. Mọi plan thêm khoá vào
  recipe phụ thuộc nó và chỉ thêm khoá, không viết bộ giải mã thứ hai.
- **Lưu nháp (người dùng đổi 2026-10-03, thay câu trả lời "chỉ lưu khi Export"):** project video tự lưu thành nháp
  ~1 s sau mỗi thay đổi và ngay khi Back / xuống nền / đổi scene; Back không còn hỏi "Discard this video?"; Video
  Projects hiện nháp lẫn bản đã xuất — spec mới [FS-12.18](../02-functional-spec/FS-12-video-studio/18-drafts.md)
  (12 AC), làm ở **khối N** của `vs-tools-selection-phone`, ngay sau task 4. FS-12.14 AC-12 và FS-12.16 AC-8 giữ
  nghĩa "rời rồi mở lại".
- **Quyết định của plan này:**
  - **Q1 — người dùng chọn hướng khác đề nghị:** project **được lưu khi rời** bằng nháp tự lưu (FS-12.18, khối N của
    tools plan). FS-12.14 AC-12 và FS-12.16 AC-8 **giữ nguyên** nghĩa "rời studio rồi mở lại project" — mở lại từ
    Video Projects, dòng Draft. Task 13 và 40 chứng minh qua Back → Video Projects → chạm dòng; chúng phụ thuộc khối N.
    Trạng thái nhận dạng và đích xuất nằm trong recipe nên tự lưu cùng nháp.
  - **Q2 — FS-12.16 đúng cho Sẵn sàng** (FS-12.10b §2–3, AC-1, AC-2, AC-12, AC-13 đã sửa). Plan media dựng khung panel
    + Đang xuất/Lỗi và một nút Export tạm; **task 34 ở đây thay Sẵn sàng tạm bằng danh sách preset**; task 46 giữ
    đường Custom → Video Settings của task E2 bên media.
  - Q3 kỹ thuật, tự quyết ở task 11 như ghi. **Q4 duyệt:** `F4_IP_Captions`, `F7_DC_BeforeAfter`, `F8_IP_ExportPresets`
    đã vào FS-12.14 AC-15, FS-12.15 AC-14, FS-12.16 AC-14; dòng rủi ro "chưa có board" đã gỡ.
- Trường mới (`captions`, `exportTarget`, `exportFraming`) chỉ thêm khoá vào bộ giải mã khoan dung của tools plan task 4.
- **Board canvas phải sửa** (canvas Video Studio <https://claude.ai/artifact/B8NqQqRHcHoFknxQ9gHZPJ>, trước task
  `design-parity` đầu tiên của board đó):
  - `F8_P_ExportPresets`, `F8_IL`, `F8_IP`, `F8_DI`, `F8_DC_ExportPresets` nay là trạng thái Sẵn sàng **duy nhất** của
    Export Video: thêm chỗ dòng LUT mất ngay trên nút xuất (FS-12.10b §3) nếu board chưa có; dòng thông số một dòng
    (`F8_DI`, `F8_IL` đang gãy hai dòng — FS-12.16 §3); dòng phụ tiêu đề giữ tỉ lệ project (`F8_IL`, `F8_DI` — §4).
  - `F4_IL`, `F4_IP`, `F7_IL`, `F7_IP`, `F8_IL`, `F8_IP`: bỏ tên project, "Clip 2 · Coast" → "Clip 2" (cùng danh sách
    của plan màn rộng / tools); `F4_DI`, `F7_DI`, `F8_DI`: cột badge 100 (Lock · Mute).

## 1. Hiểu đúng chưa

- **F4 Phụ đề.** Chạm **Auto Captions** (ngay dưới Add Text) → xin quyền nhận dạng giọng nói một lần → đọc tiếng
  gốc của từng clip video (trong khoảng trim, không ghi file tạm) qua bộ nhận dạng **bắt buộc on-device** →
  chia khối (≤ 32 ký tự, ≤ 3,0 s, ngắt ở lặng ≥ 0,4 s hoặc dấu câu) → lane **C1**. Khối neo vào **clip + giờ nguồn**,
  nên trim/dời/tốc độ/thứ tự kéo phụ đề theo. Sáu lệnh Edit · Style · Split · Merge · Language · Delete. Xuất:
  **Burn into video** (vẽ trên cùng, đo theo khung xuất) hoặc **track phụ đề mềm** (văn bản theo thời gian + mã ngôn ngữ).
- **F7 Trước/sau.** Before = bỏ look (cả video + từng clip), Adjust/Color/node/de-log/LUT, overlay, phụ đề; giữ cắt,
  tốc độ, chuyển cảnh, hiệu ứng chuyển động, tỉ lệ, nền, âm thanh. Side by Side (iPad, Duo trong) · Split (mọi máy)
  · Hold to Compare (điện thoại). **Một đồng hồ** cho hai bên, After cập nhật sống, không bao giờ tới export, không lưu.
- **F8 Preset.** Panel Export Video = năm preset + Custom; preset là **đích của một lần xuất**, không đổi tỉ lệ/Video
  Settings của project; chênh tỉ lệ thì **Fit on Background · Fill (Crop)** (mặc định Fill) với khung cắt vẽ trên preview;
  overlay bị cắt theo hình, phụ đề luôn trọn trong khung xuất. Project nhớ preset + Fit/Fill; chọn không phải bước undo;
  id lạ → preset trùng tỉ lệ.
- App chưa release: không migration, nhưng đọc khoan dung (một khối hỏng chỉ mất khối đó; id preset lạ không làm
  hỏng cả recipe). Không đụng `photo_metadata`.

## 2. Đối chiếu AC ↔ code

Ghi chú nền (đúng cho cả ba spec):

- Recipe giải mã **nghiêm**: `Creation.videoRecipe` là `try? decode(VideoProjectRecipe)` cả cục
  (`Core/Models/Creation.swift:102-105`), Codable tổng hợp, không `LossyArray` ở Video (`Domain/Video/VideoProjectModels.swift:460-513`).
- *(Đổi lúc duyệt: project tự lưu nháp — FS-12.18.)* Hôm nay project chỉ được ghi khi **xuất** (`recordCreation`, `Features/VideoStudio/VideoStudioModel.swift:1854-1869`); Back khi có
  sửa hỏi "Discard this video?" rồi bỏ (`VideoStudioScreen.swift:124-125`, `:780`).
- Compositor lấy kích thước canvas từ `request.renderContext.size` (`Data/Sources/VideoFrameCompositor.swift:365-368`), grade
  rồi nướng overlay ở cuối (`:412-428`); preview không nướng overlay — overlay sống là `VideoOverlayCanvas` vẽ trên player
  (`VideoOverlayGuides.swift:13-60`, `VideoStudioScreen.swift:792-822`).
- Writer: `.mp4`, chỉ H.264, bitrate `w×h×4,8` (= 0,16 bpp ở 30 fps), không track nào ngoài video/audio
  (`Data/Sources/VideoExportWriter.swift:94-113`). Export dựng ở `recipe.canvasSize()` (`VideoStudioService.swift:405-449`).

### FS-12.14 — Phụ đề tự động

Không target nào import `Speech` (grep: chỉ có `speechBubble` của overlay); Info.plist không có khoá xin quyền nhận dạng
(`ShotDex/Info.plist:27-43` có Calendars, Local Network, Location; `project.pbxproj:891` chỉ Photos). Không có lane phụ đề
nào trong model. → **mọi AC là ❌**, trừ AC-12 lệch luật lưu project.

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 xin quyền một lần, thẻ tiến độ, lane C1, "… of 3 clips" | ❌ | không có `SFSpeechRecognizer`, không lane C1; panel công cụ Text là của plan tools | `SpeechCaptionService` + `VideoCaptionSession` + hàng Auto Captions |
| AC-2 quyền bị từ chối → thẻ + Open Settings, không lane, undo không đổi | ❌ | như trên | nhánh `.denied` / `.restricted` |
| AC-3 mọi yêu cầu bắt buộc on-device; máy bay vẫn ra cùng số khối | ❌ (+ máy thật) | không có đường code | protocol `SpeechTranscribing`, giả trong test ghi lại `requiresOnDeviceRecognition`; máy thật cho chế độ máy bay |
| AC-4 en-US chọn được, vi-VN mờ "Not on this iPhone" | ❌ | — | `CaptionLanguages` (Domain) + danh sách |
| AC-5 khối ≤ 32 ký tự, ≤ 3,0 s, lệch ≤ 0,3 s, theo thứ tự | ❌ | — | `CaptionChunker` (Domain, thuần) |
| AC-6 trim đầu clip 2 thêm 1,0 s → khối dời 1,0 s; khối rơi ngoài trim ẩn; một Undo trả cả hai | ❌ | trim ở `VideoStudioModel.swift:684-720` chỉ đụng clip; vị trí clip từ `VideoTimelineMath.placements` (`Domain/Video/VideoTimelineMath.swift:62`) — dùng lại để quy giờ nguồn → timeline | `CaptionTimeline` (Domain); undo đi chung ảnh chụp recipe nên tự đúng |
| AC-7 Split tại ranh giới từ gần playhead | ❌ | — | `CaptionEditing.split` |
| AC-8 Merge với khối liền sau; mờ ở khối cuối | ❌ | — | `CaptionEditing.merge` |
| AC-9 Box 6% Bottom, nướng: chữ 65 ±3 px, tâm y 1632 ±19 ở 1080×1920; không hộp ở 9,0 s | ❌ | compositor không có tầng nào sau overlay (`VideoFrameCompositor.swift:412-428`) | `CaptionLayout` (Domain, dùng chung preview + export) + `VideoCaptionRenderer` (Data) |
| AC-10 Burn tắt → khung sạch; đúng một track phụ đề en-US, số mẫu = số khối | ❌ (+ đo) | writer chỉ thêm input video/audio (`VideoExportWriter.swift:94-131`) | spike `.mp4` + `tx3g` rồi `VideoSubtitleTrackWriter` |
| AC-11 ✕ khi đang 40% → dừng ≤ 1 s, không lane, undo như lúc mở panel | ❌ | luật ✕ của panel là việc plan tools / `VideoLookSession` (plan 06c task 9) | dùng chung phiên panel; huỷ task nhận dạng |
| AC-12 Back ở 58% → mở lại thấy khối clip 2 + "Captions stopped at 58%" + Continue | ⚠️ | Back có sửa → hỏi **Discard** rồi bỏ hết (`VideoStudioScreen.swift:124-125`, `:780`); project chỉ ghi khi xuất (`VideoStudioModel.swift:1854-1869`, FS-12.08 §5, FS-06.01b §5–6, FS-12.04 "hỏi Discard nếu project có thay đổi chưa xuất") → "mở lại project" sau Back không tồn tại | **hỏi Q1** |
| AC-13 clip 3 chỉ có trên iCloud → bỏ qua, "1 clip couldn't be read — it's in iCloud." + Retry | ❌ | clip không tải được đơn giản vắng khỏi `sources` (`VideoStudioService.swift:56-118`) — đủ để nhận ra | đọc tập clip thiếu nguồn; Retry = `loadSources` cho đúng các clip đó |
| AC-14 không có lời → "No speech found in these clips.", không lane | ❌ | — | nhánh rỗng trong session |
| AC-15 khớp `F4_P/IL/DI/DC` ≤ 2pt | ❌ | — | sau khung mới; thêm `F4_IP_Captions` (Q4) |
| AC-16 tắt Burn → dòng phụ "Saved as a subtitle track — …", một bước undo | ❌ | — | công tắc trong Style |
| AC-17 vạch overview + chip Voice = `timelineSpeech` #5E9CFF; chỉ khối đang chọn mang #57BFD1 | ❌ | token chưa có trong `EditorTheme` hay `DESIGN.md`; `EditorTheme.timelineSelection` hôm nay **= accent** (`Features/Editing/EditorTheme.swift:73`) trái DESIGN.md §3.3 (#57BFD1) — việc của plan chrome | token mới (nếu plan F3 chưa thêm) |

### FS-12.15 — Trước / sau

Hôm nay có **một** cơ chế: giữ nút `rectangle.on.rectangle` ở băng trên → `setShowsOriginal(true)` thay video composition
bằng recipe đã bỏ filter, node, LUT, overlay (`VideoStudioModel.swift:1234-1252`; nút `VideoStudioCommandBand.swift:186-209`,
gọi ở `:77`). Không có Side by Side, Split, Swap, COMPARE.

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 iPhone: đường chia x 201, pill (10,70)/(336,70), COMPARE, Split chọn, undo không đổi | ❌ | không có chế độ so sánh | panel Look (plan 06c task 6) + hai cửa sổ |
| AC-2 nửa trái = render bỏ look/Adjust/Color/overlay, **giữ** zoomIn; nửa phải = After | ⚠️ một phần | luật bỏ đã có trong model (`:1242-1250`) và giữ hiệu ứng (hiệu ứng chạy trước grade, `VideoFrameCompositor.swift:384-414`) — nhưng không có ở Domain, không test, không vẽ được hai bên cùng khung | **đã chốt trong spec (§3)** → tài liệu đúng; chuyển luật về Domain, compositor vẽ cặp |
| AC-3 kéo tay nắm → x 100; VoiceOver "Before, 25 percent" | ❌ | — | |
| AC-4 Hold to Compare: giữ khung → Before, nhả → After; recipe/undo không đổi | ❌ (tái dùng) | giữ hiện là giữ **nút**, không phải giữ khung; phần "không đụng recipe" đã đúng (`:1235-1237`) | chế độ mới trên khung, dùng lại `setShowsOriginal` |
| AC-5 ✓ panel Look → tắt so sánh; mở lại thấy tắt | ❌ | — | |
| AC-6 iPad ngang: pool gập, 499×281 tại y 197,5, x 16/531; Show original vắng; chạm lại → pool mở | ❌ | pool là `@State isMediaPoolOpen` của Screen (`VideoStudioScreen.swift:309-311`, `:442-447`) — nhớ được trạng thái trước khi gập | |
| AC-7 iPad, phát 10 s máy thật: lệch 0 (dừng) / ≤ 1 (phát), ≤ 3 khung rơi | ❓ | chưa đo — phiên này không có máy thật | task 32, máy thật |
| AC-8 kéo Amount 80→40: After đổi, Before giữ từng pixel; undo +1 | ❌ | Amount là của plan 06c task 4 | |
| AC-9 iPad dọc Swap: After x 11, Before x 497 | ❌ | — | |
| AC-10 không có gì để so → hai bên giống, "No edits to compare yet." | ⚠️ | nút hôm nay **tắt** khi `!hasEdits` (`VideoStudioCommandBand.swift:77`) — `hasEdits` tính cả trim/thứ tự, còn spec cho nút luôn dùng được và nói ra bằng chữ | **đã chốt trong spec (§5)** → tài liệu đúng; vị từ `hasNothingToCompare` ở Domain |
| AC-11 so sánh bật (Split 30%) → Export: không đường chia/pill, khung = After | ✅ (theo cấu trúc) | export đọc `recipe` (`VideoStudioModel.swift:1830-1833`); `showsOriginal` không bao giờ vào recipe (`:1238-1252`) | khoá bằng test khi trạng thái so sánh ra đời (task 18) |
| AC-12 Duo trong: nút (148,12) → 330×186 tại y 96; giữ 1 s → cả hai là Before | ❌ | — | `Tools/ui-drive` + `Tools/sim-shot` |
| AC-13 footage log + de-log S-Log3: Before phẳng như nguồn | ⚠️ | `setShowsOriginal` **giữ** `inputTransform` (không gán lại ở `:1242-1250`) | **đã chốt trong spec (§3, §10)** → tài liệu đúng; bỏ de-log ở cả hai lối vào |
| AC-14 khớp `F7_P/IL/IP/DI` ≤ 2pt | ❌ | — | + `F7_DC_BeforeAfter` (Q4) |
| AC-15 bật: nền trắng glyph đen (iPhone/Duo), trắng 14% (iPad); không bao giờ #EB9526 | ⚠️ | glyph đang **accent** khi giữ (`VideoStudioCommandBand.swift:189-193`) | **đã chốt trong spec (§4)** → tài liệu đúng |

### FS-12.16 — Preset xuất

Hôm nay: sheet Export có Picker "Quality" 1080p/4K ghi thẳng vào `recipe.renderPreset` (`VideoExportSheet.swift:24-32`),
nút Export chạy ngay (`:97-111`); `VideoRenderPreset` chỉ có `hd1080`/`uhd4K` (`VideoProjectModels.swift:332-352`), tỉ lệ có
4 giá trị (`:21-62`); ước tính dùng 0,15 bpp (`VideoStudioModel.swift:1886-1893`). Không có khái niệm đích xuất, Fit/Fill
khi chênh tỉ lệ, hay khung cắt trên preview.

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 iPhone: panel "Export Video 0:24", YouTube chọn, không Fit/Fill, "Export for YouTube", Export băng trên hết accent, chưa xuất | ⚠️ | sheet hôm nay xuất ngay; **và** FS-12.10b §2–3 / AC-1 tả một trạng thái Sẵn sàng **khác** cho cùng panel (tóm tắt + "Saved to Photos…" + nút 362×50 ở (20,705); iPad form sheet 540) | **hỏi Q2** |
| AC-2 chọn Reels → viền + ✓; khung cắt 127×226 tại x 137,5; "YOUR PROJECT IS 16:9", Fill chọn | ❌ | — | `VideoExportFraming` (Domain) |
| AC-3 Reels + Fill → 1080×1920, 30 fps, H.264, 24,0 s ±1 khung; khung 8,4 s = vùng cắt giữa ≤ 2/255 | ❌ | export luôn ở `recipe.canvasSize()` (`VideoStudioService.swift:412`) | `VideoExportSpec` + tầng khung xuất trong compositor |
| AC-4 Fit → 1080×608 giữa, dải đúng màu nền | ❌ | — | |
| AC-5 Instagram 4:5 → 1080×1350; Square → 1080×1080 | ❌ | — | |
| AC-6 YouTube 4K mờ 0,28 + lý do; project toàn 4K → 3840×2160 HEVC | ❌ | cổng 4K và HEVC là của plan vs-media-settings-export | dùng lại cổng + writer |
| AC-7 Custom → Video Settings → "4:3 · 720p · 24 fps · H.264"; file 4:3 720p 24 fps | ❌ | 4:3, 720p, 24 fps chưa có (plan vs-media-settings-export) | |
| AC-8 chọn Reels + Fill, đóng, rời, mở lại → Reels + Fill; undo không đổi | ⚠️ | cùng gốc với F4 AC-12: rời studio = Discard, chỉ ghi khi xuất | **hỏi Q1** |
| AC-9 phụ đề trọn trong 1080×1920, chữ tại x 0,1 bị cắt | ❌ | — | tầng phụ đề sau khung xuất (task 9 + 43) |
| AC-10 Duo ngoài: chạm Export lần 1 mở, lần 2 xuất | ❌ | — | dải 84 là của plan chrome |
| AC-11 còn 40 MB → "Not enough space … about 60 MB needed…" | ❌ | luật chỗ trống là FS-12.10b §5 (plan vs-media-settings-export) | chỉ truyền ước tính của preset |
| AC-12 id "vimeo" → YouTube, không lỗi | ❌ | recipe giải mã nghiêm (`Creation.swift:102-105`): một raw value lạ của enum sẽ làm **mất cả project** | lưu id dạng `String?`, giải ở Domain |
| AC-13 VoiceOver "Reels / TikTok, 1080 by 1920, 30 frames per second, about 30 megabytes, selected" | ❌ | — | |
| AC-14 khớp `F8_P/IL/DI/DC` ≤ 2pt | ❌ | — | + `F8_IP_ExportPresets` (Q4) |
| AC-15 iPad: nút cài đặt "9:16 · 1080p · 30 fps" khi panel mở; dòng phụ tiêu đề giữ "5 clips · 16:9 · 0:24" | ❌ | nút cài đặt iPad là của plan chrome/settings | |
| AC-16 ~30 · ~72 · ~30 · ~21 · ~17 MB | ❌ | công thức hôm nay 0,15 bpp (`VideoStudioModel.swift:1886-1893`) — plan vs-media-settings-export đổi sang 0,16 bpp + HEVC × 0,6 | đọc công thức chung; đã kiểm tay: 30,2 · 72,1 · 30,2 · 21,4 · 17,2 MB |
| AC-17 không có "Save as Preset…"; chỉ 5 preset (+ Custom iPhone/iPad) | ✅ | grep "Save as Preset" = 0 trong `ShotDex/` | khoá bằng test (task 33) |

**Spec có, AC không có** (làm kèm test trong task gần nhất; `/verify` sẽ báo "có test, không có AC"):
F4 — lệnh **Edit** (danh sách, chạm giờ = chọn + dời playhead, ↗ trình sửa chữ toàn màn) → task 7; **Delete** khối / cả
lane (chạm nhãn C1) → task 8; kéo khối trên C1 (thân dời, mép đổi khoảng, không chồng, lane khoá) → task 6; hỏi "Transcribe
again…" khi đổi ngôn ngữ có khối sửa tay → task 5; Word by Word chia đều khi đã sửa tay → task 9; viền đứt quanh phụ đề
đang chọn (iPad, Duo trong) → task 17; "máy không có model nào" → task 4. F7 — **Duo ngoài** (board `F7_DC` nay đã có)
→ task 31; Undo/Redo khi đang so sánh → task 27; phím `\` là của plan F6 (gọi `toggleBeforeAfter()` của task 18).
F8 — vuốt panel xuống để đóng, nhãn "Export" của Custom, dòng "… · then choose where it goes" cho project ảnh server → task 34.

## 3. Tái dùng

| Có sẵn | Dùng cho |
|---|---|
| `VideoTimelineMath.placements` / `clipIndex(at:)` | quy giờ nguồn của khối → timeline (F4); chọn clip dưới playhead |
| `VideoSplitMath.split` | tách clip → chia lại khối theo giờ nguồn (F4) |
| `TextOverlayLayout` + `PhotoRenderService.overlayLayer` (kit) + cache overlay của compositor (`VideoFrameCompositor.swift:662-676`) | đo và vẽ chữ phụ đề; hộp Box vẽ quanh bounds của cùng layout → preview và export một hàm |
| `VideoOverlayCanvas` (proxy sống theo `currentTime`) | lớp phụ đề sống trên preview (F4) và cắt theo vùng After (F7) |
| `VideoStudioService.loadSources` (clip không tải được vắng khỏi kết quả) | nhận ra clip iCloud không đọc được + Retry (F4 AC-13) |
| `setShowsOriginal` + `applyVideoComposition` (tầng rẻ, không dựng lại composition) | Hold to Compare, giữ lâu trên Duo trong (F7) |
| `composeFrame` tĩnh + grade từng bên trước `blend` (plan 06c task 1) | vẽ Before và After từ **cùng** ảnh nguồn đã giải trong một request (F7) |
| `VideoLookSession` / phiên panel ✕ · ✓ (plan 06c task 9, plan tools) | ✕ trong lần nhận dạng đầu (F4 AC-11) |
| Bảng kích thước khung, cổng 4K, công thức ước tính, writer HEVC/fps, kiểm chỗ trống, khung panel Export Video (plan vs-media-settings-export) | toàn bộ thông số của preset (F8) — preset **không** có bảng riêng |
| Nhãn **Voice** + đọc âm thanh clip theo giờ nguồn (plan F3 ducking) | chip Voice của clip có lời; nếu F3 đã có bộ đọc PCM của clip thì `ClipAudioReader` dùng lại nó |
| `EditorChromeModel.splitFraction` + split của editor ảnh (`EditorImageStage.swift:786-830`) | **không** dùng chung view (số đo khác: đường 1pt/tay nắm 30 vs 2pt/34 theo canvas) — ghi `REVIEW_QUEUE.md` cho `component-consistency` |
| `importFixturesIfAsked` (cờ khởi chạy cho route `ui-drive`) | cờ `-ShotDexFakeSpeech` nạp bản chép sẵn — simulator không có model on-device đáng tin |

## 4. File đổi và tầng

| File | Tầng | Đụng gì | Mới / sửa |
|---|---|---|---|
| `Domain/Video/VideoCaptions.swift` | Domain | `VideoCaptionLane { language: String, style: String, sizePercent, position: String, burnsIn, cues: LossyArray<CaptionCue>, recognition: CaptionRecognitionState }`, `CaptionCue { id, clipID, sourceStart, sourceEnd, text, words: [CaptionWord]?, isEdited }`; enum `CaptionStyle`/`CaptionPosition` giải từ chuỗi (lạ → mặc định) | mới |
| `Domain/Video/CaptionChunker.swift` | Domain | từ + mốc → khối (32 ký tự · 3,0 s · lặng 0,4 s · dấu câu), tên "Caption n" | mới |
| `Domain/Video/CaptionTimeline.swift` | Domain | khối → khoảng timeline qua placement/trim/tốc độ; ẩn ngoài trim; luật khi xoá/tách/nhân bản/thay clip; kéo khối trên C1 | mới |
| `Domain/Video/CaptionEditing.swift` | Domain | Split (ranh giới từ gần nhất), Merge, Delete, sửa chữ (`isEdited`, bỏ mốc từ) | mới |
| `Domain/Video/CaptionLayout.swift` | Domain | cỡ chữ = % cạnh ngắn khung xuất, tâm 85/50/15%, hộp Box, số từ hiện ở Word by Word | mới |
| `Domain/Video/CaptionRecognitionPlan.swift` | Domain | clip nào đọc (video, không tắt tiếng, có trim), tiến độ %, "N of M clips", tiếp tục từ chỗ dừng, gộp kết quả vào recipe **và** các ảnh chụp undo đã có lane | mới |
| `Domain/Video/CaptionLanguages.swift` | Domain | danh sách = ngôn ngữ nhận dạng được × có model; mặc định; chữ "Not on this iPhone/iPad" | mới |
| `Domain/Video/VideoBeforeAfter.swift` | Domain | `mode` (sideBySide/split/hold), `fraction`, `isSwapped`; `beforeRecipe(_:)`; `hasNothingToCompare(_:)`; hình học hai khung theo máy; chuỗi VoiceOver ±10% | mới |
| `Domain/Video/VideoExportPreset.swift` | Domain | 5 preset hằng số (id, tên, tỉ lệ, kích thước, fps, codec); `resolve(storedID:aspect:)`; dòng thông số; nhãn VoiceOver; hàng theo máy (5 / 6) | mới |
| `Domain/Video/VideoExportFraming.swift` | Domain | `VideoExportSpec { size, fps, codec, framing }`; Fit/Fill: canvas ảo, vùng cắt, khung Fit; khung cắt trên preview + pill "9:16 · Fill" | mới |
| `Domain/Video/VideoProjectModels.swift` | Domain | `captions: VideoCaptionLane?`, `exportTarget: String?`, `exportFraming: String?` — đều optional để giải khoan dung | sửa |
| `Data/Sources/SpeechCaptionService.swift` | Data | `SFSpeechRecognizer` sau protocol `SpeechTranscribing` + `SpeechAuthorizing`; `requiresOnDeviceRecognition = true` mọi request; từ chối khi `!supportsOnDeviceRecognition`; huỷ ≤ 1 s | mới |
| `Data/Sources/ClipAudioReader.swift` | Data | `AVAssetReader` → `AVAudioPCMBuffer` theo khoảng trim, luồng, không file tạm (dùng lại bộ đọc của F3 nếu có) | mới hoặc dùng lại |
| `Data/Sources/VideoCaptionRenderer.swift` | Data | raster phụ đề (cache theo khối + kiểu + cỡ + khung + số từ hiện) | mới |
| `Data/Sources/VideoSubtitleTrackWriter.swift` | Data | mẫu `tx3g` + mô tả định dạng, mã ngôn ngữ của lane | mới |
| `Data/Sources/VideoFrameCompositor.swift` | Data | tách **kích thước canvas** khỏi `renderContext.size`; tầng khung ra `VideoOutputStage { single · pair(gap, swapped) · reframe(spec) }`; Before/After cùng nguồn; phụ đề vẽ **sau** khung ra | sửa |
| `Data/Sources/VideoCompositionBuilder.swift`, `VideoStudioService.swift`, `VideoExportWriter.swift` | Data | `renderSize` khung ra ≠ canvas layout; `export(spec:)`; preview cặp so sánh; thêm input phụ đề | sửa |
| `Features/VideoStudio/VideoCaptionSession.swift` | Features | `@Observable`: task nhận dạng, tiến độ, lỗi; gọi model qua API recipe/undo | mới |
| `Features/VideoStudio/VideoCaptionsPanel.swift`, `VideoCaptionProxyLayer.swift` | Features | sáu lệnh, thẻ tiến độ, Language, danh sách, Style; lớp sống trên preview | mới |
| `Features/VideoStudio/VideoBeforeAfterStage.swift` | Features | hai cửa sổ cắt của cùng một khung ra, đường chia + tay nắm, pill | mới |
| `Features/VideoStudio/VideoExportPresetsPanel.swift` | Features | trạng thái Sẵn sàng của Export Video: hàng preset, Fit/Fill, khung cắt, nút "Export for …" | mới (thay nội dung Sẵn sàng của `VideoExportSheet`) |
| `VideoStudioModel.swift`, `VideoStudioScreen.swift`, `VideoTimelineTracks.swift` (lane C1, chip Voice), `VideoViewerChrome.swift` (nút iPad), `VideoStudioCommandBand.swift` (nút Duo trong, bỏ accent), `VideoStudioMetrics.swift`, panel Look (plan 06c) | Features | như cột trước | sửa |
| `Features/Editing/EditorTheme.swift`, `DESIGN.md` §3.3 | Features / docs | `timelineSpeech` #5E9CFF + chữ #06142E (nếu plan F3 chưa thêm) | sửa |
| `ShotDex/Info.plist` + `ShotDex/InfoPlist.xcstrings` (mới, en + vi) | App | `NSSpeechRecognitionUsageDescription` = câu ở FS-12.14 §4 | sửa / mới |
| `ShotDexTests/Caption*Tests.swift`, `VideoBeforeAfter*Tests.swift`, `VideoExportPreset*Tests.swift`, `VideoCaptionExportTests`, `VideoPresetExportTests` | Test | Swift Testing, như `VideoLUTRendererTests` | mới |
| `ShotDexUITests/scripts/video-captions-*.json`, `video-compare-*.json`, `video-presets-*.json` | Test | route `ui-drive` từng máy | mới |

Không bảng GRDB mới, không migration: mọi trường mới nằm trong JSON recipe của `creations`.

## 5. Thứ tự task

Một AC = một task = một commit `feat(FS-12.1x): AC-n …`; `/build` sau mỗi commit; đụng UI thì `/screens` + `design-parity`
với board tương ứng. Trong mỗi spec: ✅ (khoá test) → ⚠️ (theo quyết định, sớm nhất phụ thuộc cho phép) → ❌ theo phụ thuộc.
Ba khối theo đúng thứ tự intent F4 → F7 → F8; **cả bảng chỉ bắt đầu sau khi các plan ở §7 đã vào code**.

### F4 — FS-12.14 (task 1–17)

| # | Task | AC | Test kèm theo |
|---|---|---|---|
| 1 | Model lane/khối (lossy) + `CaptionChunker`; **cùng commit**: `NSSpeechRecognitionUsageDescription` trong `Info.plist` + `InfoPlist.xcstrings` (en, vi) — luật FS-12.14 §10 | AC-5 | `CaptionChunkerTests.blocksStayWithin32CharsAnd3s`, `breaksAtPauseOrPunctuation`, `startWithin0_3sOfFirstWord`, `namesInTimeOrder`; `VideoCaptionDecodingTests.oneBrokenCueLosesOnlyItself`, `unknownStyleFallsBackToClean` |
| 2 | `SpeechCaptionService` + `ClipAudioReader`: mọi request on-device, locale không có model thì không chạy, đọc đúng khoảng trim, không file tạm | AC-3 | `SpeechCaptionServiceTests.everyRequestRequiresOnDevice` (giả ghi lại cờ), `localeWithoutModelNeverStarts`, `readsOnlyTheTrimWindow` (asset tổng hợp), `leavesNoTemporaryFiles`; **máy thật**: chế độ máy bay ra cùng số khối |
| 3 | Hàng Auto Captions dưới Add Text (panel Text của plan tools; tab Text của pool iPad); xin quyền một lần; `CaptionRecognitionPlan`; thẻ tiến độ; lane C1 tạo = một bước undo; khối hiện dần theo clip | AC-1 | `CaptionRecognitionPlanTests.skipsPhotosFreezesAndMutedClips`, `progressCountsClips`; `VideoCaptionSessionTests.asksPermissionOnce`, `laneAppearsAsOneUndoStep`; route `video-captions-auto.json` với `-ShotDexFakeSpeech` |
| 4 | Quyền bị từ chối / hạn chế (thẻ, Open Settings chỉ khi từ chối); máy không có model nào → hàng mờ + dòng phụ | AC-2 | `deniedShowsCardNoLaneNoUndo`, `restrictedHasNoSettingsButton`, `noModelDimsTheRow` |
| 5 | Language: `CaptionLanguages`; ngôn ngữ không model mờ, chạm không đổi; đổi ngôn ngữ = nhận dạng lại cả lane = một bước undo; hỏi "Transcribe again…" khi có khối sửa tay | AC-4 | `CaptionLanguagesTests.unavailableIsDimAndInert`, `defaultIsDeviceLanguageIfModelElseEnUS`; `languageChangeIsOneUndoStep`, `editedCuesTriggerConfirmation` |
| 6 | Neo vào clip: `CaptionTimeline`; trim/dời/tốc độ/thứ tự; ẩn ngoài trim, trả trim là hiện; xoá clip xoá khối; tách clip chia lại khối; nhân bản clip chép khối (id mới); thay clip bỏ khối; kéo khối trên C1 qua `TimelineDragZone` (UIKit pan) | AC-6 | `CaptionTimelineTests.trimHeadShiftsCue` (6,0–7,4 → 5,0–6,4), `cueInsideTrimmedSecondHides`, `oneUndoRestoresBoth`, `deleteClipDeletesItsCues`, `splitClipReassignsBySourceTime`, `speedScalesCue`, `dragNeverOverlapsNeighbour` |
| 7 | Split khối tại playhead (ranh giới từ gần nhất; ngoài khối thì mờ); lệnh Edit (danh sách, chạm giờ = chọn + dời playhead, ↗ trình sửa chữ toàn màn) | AC-7 | `CaptionEditingTests.splitAtNearestWordBoundary` ("starts right" 6,0–6,7 · "here." 6,7–7,4), `splitDisabledOutsideCue`; một Undo về một khối |
| 8 | Merge với khối liền sau (mờ ở khối cuối); Delete khối / cả lane | AC-8 | `mergeJoinsTextAndUnionsTime` ("Listen to that water." 10,8–13,1), `mergeDisabledOnLast`, `deleteLaneFromLabel` |
| 9 | Style (4 kiểu, Size 3–12%, Bottom/Middle/Top) + `CaptionLayout` dùng chung; `VideoCaptionProxyLayer` trên preview; compositor vẽ phụ đề **sau** mọi overlay, theo khung ra (lúc này khung ra = canvas). Bộ dựng video mẫu cho smoke test: dùng của plan vs-media-settings-export, chưa có thì tạo ở đây | AC-9 | `CaptionLayoutTests.boxSixPercentBottomOn1080x1920` (65 ±3 px, y 1632 ±19), `wordByWordRevealsAtWordTimes`, `editedCueSpreadsWordsEvenly`; `VideoCaptionExportTests.boxAt6_5sNoneAt9_0s` |
| 10 | Công tắc Burn into video + dòng phụ khi tắt; một bước undo | AC-16 | `burnToggleIsOneUndoStep`; ảnh chụp Style |
| 11 | Spike rồi `VideoSubtitleTrackWriter`: `AVAssetWriter` `.mp4` + `tx3g` (`canAdd`, đọc lại, mã ngôn ngữ, số mẫu); không được thì `.mov` (Q3). Burn tắt → khung sạch | AC-10 | `VideoCaptionExportTests.softTrackOneSamplePerCue` (en-US, mẫu 6,5 s = "starts right here."), `burnOffLeavesFramesClean`; đo trên sim: Photos nhập file giữ hay bỏ track (chấp nhận được cả hai) |
| 12 | ✕ trong lần nhận dạng đầu: huỷ ≤ 1 s, xoá lane, trả độ sâu undo lúc mở panel (phiên panel dùng chung); ✓ khi đang chạy thì chạy tiếp | AC-11 | `cancelStopsWithinOneSecond` (giả chậm), `cancelRemovesLaneAndRestoresUndoDepth`, `doneKeepsRecognising` |
| 13 | Tiếp tục: `recognition` lưu trong lane; "Captions stopped at 58%" + Continue chỉ chạy clip chưa xong — mở lại qua nháp (FS-12.18, khối N tools plan) | AC-12 ⚠️ | `continueTranscribesOnlyRemainingClips` (clip 3, 5); `stoppedStateSurvivesEncodeDecode`; route Back → Video Projects → chạm dòng Draft |
| 14 | Clip không đọc được (iCloud/`.limited`): bỏ qua, dòng phụ + Retry; clip khác vẫn chạy; không spinner treo | AC-13 | `unreadableClipIsSkippedWithRetry`, `retryReloadsOnlyMissingClips` |
| 15 | Không có lời → "No speech found in these clips.", không lane, undo không đổi | AC-14 | `noSpeechCreatesNoLane` |
| 16 | Token `timelineSpeech` (+ DESIGN.md §3.3 nếu plan F3 chưa thêm); chip Voice 16 trên clip có lời (iPhone); vạch 3pt trên Project Overview; khối đang chọn mới mang #57BFD1 | AC-17 | agent `design-reviewer`; `CaptionTimelineTests.overviewMarksMatchCues` |
| 17 | Hình học theo board: panel 340 iPhone, panel 382×344 Duo ngoài, cột 264 Duo trong, inspector 280 iPad, lane C1 44/34 (iPad), 28 (Duo); viền đứt quanh phụ đề đang chọn | AC-15 | `VideoStudioLayoutTests.captionsPanelFitsEveryDevice`; `design-board compare` ≤ 2pt trên `F4_P/IL/IP/DI/DC`; `Tools/sim-shot` cho Duo và iPad |

### F7 — FS-12.15 (task 18–32)

| # | Task | AC | Test kèm theo |
|---|---|---|---|
| 18 | `VideoBeforeAfter` là trạng thái màn hình trên model (không vào recipe, không undo); `toggleBeforeAfter()` cho phím `\` của plan F6 | AC-11 ✅ | `VideoBeforeAfterTests.exportIgnoresCompareState` (recipe gửi export giống hệt khi bật Split 30%), `compareStateIsNotUndoable` |
| 19 | `beforeRecipe(_:)` ở Domain: bỏ look cả video + look clip, node, **de-log**, LUT, overlay, phụ đề; giữ phần còn lại. `setShowsOriginal` và giữ lâu Duo trong đi qua nó | AC-13 ⚠️ | `beforeDropsDeLog` (render ≤ 1/255 so với nguồn), `beforeKeepsEffectsTransitionsAudio` |
| 20 | Compositor vẽ **cặp**: Before + After từ cùng ảnh nguồn đã giải trong một request; canvas tách khỏi `renderContext.size`; `VideoOutputStage.pair` | AC-2 ⚠️ | `VideoBeforeAfterRenderTests.leftIsBeforeWithZoomIn`, `rightIsAfter`, `noStickerOrTextOnBefore` (qua `composeFrame` tĩnh) |
| 21 | `hasNothingToCompare` thay cổng `hasEdits`; "No edits to compare yet." | AC-10 ⚠️ | `nothingToCompareWhenNoLookAdjustColorOverlay`, hai bên giống từng pixel |
| 22 | Màu nút theo §4, không bao giờ accent | AC-15 ⚠️ | agent `design-reviewer`; ảnh chụp bật/tắt 3 máy |
| 23 | iPhone: nút tròn 32 ở header panel Look (x 280), COMPARE dưới Amount (Split · Hold to Compare 181×30), đường chia 2pt + tay nắm 34, pill (10,70)/(336,70); hai cửa sổ cắt của **một** player — spike hai `AVPlayerLayer` cùng player; không được thì `AVPlayerItemVideoOutput` + hai `CALayer` `contentsRect` | AC-1 | route `video-compare-phone.json`; `VideoBeforeAfterTests.phoneSplitGeometry` (x 201 ±1) |
| 24 | Kéo tay nắm 0–100%; VoiceOver adjustable ±10% | AC-3 | `fractionFromDrag` (x 100 → 25%), `accessibilityValueReadsPercent` |
| 25 | Hold to Compare: giữ khung = Before, nhả = After (tầng rẻ, một bên) | AC-4 | `holdNeverTouchesRecipeOrUndo` |
| 26 | Đóng panel Look (✓/✕) tắt so sánh (iPhone, Duo ngoài) | AC-5 | `closingLookPanelTurnsCompareOff` |
| 27 | After sống: Amount/Adjust/Color đổi After ở khung kế; Before không đổi; Undo/Redo khi đang so sánh | AC-8 | `amountDragChangesOnlyAfter` (Before giống từng pixel), undo +1 |
| 28 | iPad ngang: nút 36×28 ở viewer header (x 918), pool tự gập/trả, hai khung 499×281 tại y 197,5 (x 16 / 531), Side by Side · Split giữa header, dòng "Both sides play and scrub together · 0:08.4", Show original ẩn khỏi băng trên | AC-6 | `VideoBeforeAfterTests.iPadLandscapeFrames`; route `video-compare-ipad.json` + `sim-shot` |
| 29 | iPad dọc: 473×266 tại y 226, dock ba cột LOOK · COMPARE · ADJUST, **Swap sides** | AC-9 | `swapPutsAfterLeft` (After x 11, Before x 497) |
| 30 | Duo trong: nút (148,12) thay Show original, giữ ≥ 0,3 s = xem bản gốc; 330×186 tại y 96, khe 8; Side by Side · Split 112×28 dưới Amount | AC-12 | `Tools/ui-drive` `video-compare-duo.json` + `Tools/sim-shot inner` |
| 31 | Parity `F7_P/IL/IP/DI` + `F7_DC` (Duo ngoài, khung 382×215, COMPARE trong panel Look 382) | AC-14 | `design-board compare` ≤ 2pt; `sim-shot cover` |
| 32 | **Máy thật** iPad (+ iPhone 17): đếm lệch khung và khung rơi 10 s Side by Side; trượt → Before nửa độ phân giải khi phát, đủ khi dừng (spec §10) | AC-7 ❓ | `CADisplayLink` + so số khung hai bên; chỉ commit nếu bật đường lùi |

### F8 — FS-12.16 (task 33–49)

| # | Task | AC | Test kèm theo |
|---|---|---|---|
| 33 | `VideoExportPreset` 5 hằng số; hàng theo máy (iPhone/iPad 6, Duo 5); không có preset tự lưu | AC-17 ✅ | `VideoExportPresetTests.exactlyFivePresets`, `rowsPerDevice`; dump ở task 49: không "Save as Preset…" |
| 34 | Trạng thái Sẵn sàng của Export Video = danh sách preset (**theo Q2**): chạm Export lần đầu chỉ mở; một accent (nút băng trên về trắng 10%, accent sang "Export for …"); đóng bằng ✕/chạm lại/vuốt; nhãn Custom "Export"; dòng server | AC-1 ⚠️ | `firstTapOpensNeverExports`, `exportButtonTitle`; route `video-presets-phone.json` |
| 35 | Lưu `exportTarget`/`exportFraming` dạng chuỗi; `resolve` id lạ/thiếu → preset trùng tỉ lệ project (khác → Custom) | AC-12 | `unknownIDFallsBackToAspect` ("vimeo" → YouTube), `recipeWithVimeoStillDecodes` |
| 36 | Dung lượng từng dòng = công thức FS-12.10 với thông số preset; một dòng, cắt "…" | AC-16 | `estimatesMatchTable` (~30 · ~72 · ~30 · ~21 · ~17 MB) |
| 37 | Nhãn VoiceOver dòng preset + trait selected | AC-13 | `accessibilityLabelReadsSpec`; agent `a11y-voiceover` |
| 38 | Chọn dòng; hàng YOUR PROJECT IS … (ẩn khi trùng tỉ lệ), mặc định Fill; khung cắt / khung Fit trên preview + pill | AC-2 | `VideoExportFramingTests.fillCropRectOnPhone` (127×226 tại x 137,5 ±1), `fitShowsBands` |
| 39 | iPad: nút cài đặt ghi thông số đích khi panel mở, về giá trị project khi đóng; dòng phụ tiêu đề giữ tỉ lệ project | AC-15 | `settingsLabelFollowsTargetWhileOpen`; ảnh chụp |
| 40 | Chọn preset / Fit-Fill **không** là bước undo: `restore()` giữ nguyên đích hiện tại khi Undo/Redo; lưu cùng recipe; mở lại từ Video Projects (nháp FS-12.18) | AC-8 ⚠️ | `presetIsNotAnUndoStep`, `undoKeepsCurrentTarget`, `targetSurvivesEncodeDecode` |
| 41 | `VideoExportSpec` → `export(spec:)`; layout trên **canvas ảo** phủ khung ra, cắt giữa (CI lười nên chỉ trả phí pixel khung ra); fps/codec theo spec | AC-3 | `VideoPresetExportTests.reelsFillIs1080x1920At30` (24,0 s ±1 khung), `frameMatchesCentreCrop` ≤ 2/255 |
| 42 | Fit on Background: khung project thu vào giữa, dải là nền project (màu / Blur theo FS-12.10) | AC-4 | `reelsFitCentresAndFillsBands` (1080×608, màu nền) |
| 43 | Phụ đề vẽ sau tầng reframe → luôn trọn; overlay nướng trước → bị cắt như preview | AC-9 | `captionsStayInsideOnFill`, `overlayAtX0_1IsCropped` |
| 44 | Instagram 4:5, Square | AC-5 | `instagramIs1080x1350`, `squareIs1080x1080` |
| 45 | YouTube 4K theo cổng 4K của FS-12.10: mờ 0,28 + lý do, chạm không chọn; project toàn 4K → 3840×2160 HEVC | AC-6 | `fourKRowDisabledByGate`; `youTube4KIsHEVC3840` (sim); đo bộ nhớ trên máy thật |
| 46 | Custom mở Video Settings; quay lại Custom chọn, dòng thông số thật; xuất theo Video Settings | AC-7 | `customLineReadsProjectSettings`, `customExportIs4x3At720p24` |
| 47 | Thiếu chỗ: luật FS-12.10b §5 với ước tính của preset; không bắt đầu, không file tạm | AC-11 | `insufficientSpaceBlocksStart` (chỗ trống tiêm vào) |
| 48 | Duo ngoài: Export trong dải 84 lần 1 mở panel 5 dòng, lần 2 xuất; chạm công cụ = đóng panel + mở công cụ; chú thích "Export in the rail uses the chosen preset." | AC-10 | `Tools/ui-drive` `video-presets-duo-cover.json` + `sim-shot cover` |
| 49 | Parity `F8_P/IL/DI/DC` + `F8_IP` (sheet 660); dump không "Save as Preset…" | AC-14 | `design-board compare` ≤ 2pt; `sim-shot` iPad/Duo |

## 6. Quyết định kỹ thuật (tự quyết, có lý do)

| # | Quyết định | Vì sao |
|---|---|---|
| K1 | Một **tầng khung ra** trong compositor (`single` · `pair` · `reframe`), tách kích thước canvas layout khỏi `renderContext.size` | F7 (khung đôi) và F8 (cắt/Fit) cần cùng một chỗ; phụ đề đặt **sau** tầng này nên luôn đo theo khung xuất |
| K2 | So sánh = compositor vẽ một khung đôi [Before \| After]; màn hình hiện qua hai cửa sổ cắt của **cùng** player | một đồng hồ là chắc chắn (lệch 0 khung); kéo đường chia chỉ dời mặt nạ, không dựng lại composition. Spike ở task 23 chọn giữa hai `AVPlayerLayer` và `AVPlayerItemVideoOutput` |
| K3 | Trường mới đều `Optional` / chuỗi, giải ở Domain | recipe giải nghiêm cả cục (`Creation.swift:102-105`): một raw value lạ là mất project — trái luật lossy |
| K4 | Kết quả nhận dạng gộp vào recipe **và** vá vào các ảnh chụp undo/redo đã có lane, không đẩy bước undo | Undo một lần sửa tay giữa lúc nhận dạng không được xoá phần máy vừa nghe; Undo qua lúc tạo lane thì lane mất và nhận dạng dừng |
| K5 | `exportTarget`/`exportFraming` ngoài undo: `restore()` chép đích hiện tại vào ảnh chụp được khôi phục | spec: chọn preset không là bước undo; nếu ảnh chụp mang đích cũ thì Undo một chỉnh màu sẽ lặng lẽ đổi preset |
| K6 | Nhận dạng theo từng clip, đọc PCM bằng `AVAssetReader` và nạp `SFSpeechAudioBufferRecognitionRequest` | spec cấm file tạm; một engine cho iOS 17–26 (không dùng `SpeechAnalyzer` của iOS 26) |
| K7 | Tách clip → khối chia theo giờ nguồn; nhân bản → chép khối (id mới); thay clip → bỏ khối | "neo vào clip" (§4): cùng lời thì cùng phụ đề, nguồn khác thì lời khác |
| K8 | UI route trên simulator dùng `-ShotDexFakeSpeech` | simulator không có model on-device đáng tin (spec §10); AC-3 và tốc độ đo trên máy thật |

## 7. Phụ thuộc chéo plan

| Plan | Cần gì từ nó | Task chờ |
|---|---|---|
| chrome / thanh dưới (FS-12.03, 03b, 07, 07b) | băng trên (Video Settings, Export), hàng đáy 84 (thay bằng nút "Export for …"), dải 84 Duo ngoài, viewer header iPad (Quick Adjust), header lane, Project Overview iPhone, sửa `timelineSelection` về #57BFD1 (`EditorTheme.swift:73`) | 16, 17, 28, 30, 34, 39, 48 |
| tools / chọn item (FS-12.04, 04b) | panel công cụ Text (hàng Auto Captions), chân ✕ · tên · ✓, hàng lệnh 64×56, phiên panel ✕/✓, chọn lane/khối như một item, lệnh Duplicate clip | 3, 6–8, 12 |
| tools khối N — lưu nháp (FS-12.18) | rời studio rồi mở lại project từ Video Projects | 13, 40 |
| **vs-media-settings-export** (FS-12.09, 10, 10b) | trường resolution/fps/codec/Fit-Fill/nền trong recipe, bảng kích thước, cổng 4K, công thức 0,16 bpp, writer HEVC + fps, kiểm chỗ trống, khung panel Export Video + trạng thái xuất/huỷ/lỗi, panel Video Settings, bộ dựng video mẫu cho smoke test, giải mã khoan dung của recipe nếu plan đó viết `init(from:)` | 9, 11, 34–49 |
| look ảnh cho video [2026-10-02-video-photo-looks](2026-10-02-video-photo-looks.md) (06c) | task 1 (grade từng bên, `composeFrame` tĩnh), task 3 (`VideoLook` trên recipe/clip — Before bỏ nó), task 4 (Amount), task 6 (panel Look chứa COMPARE), task 9 (phiên ✕) | 19–31 |
| F3 ducking (FS-12.13) | token `timelineSpeech`, nhãn Voice, bộ đọc âm thanh clip theo giờ nguồn | 2, 16 (task tự thêm nếu F3 chưa có) |
| F6 bàn phím (FS-12.17b) | phím `\` gọi `toggleBeforeAfter()`; ⌘E mở panel Export (không xuất) | cung cấp ở task 18, 34 |

## 8. Câu hỏi chờ quyết (⚠️ thật)

| # | Chỗ lệch | Đề nghị |
|---|---|---|
| **Q1** *(duyệt khác đề nghị: nháp tự lưu FS-12.18, hai AC giữ nguyên)* | FS-12.14 AC-12 / §8 "rời studio ở 58% → khối được lưu, mở lại thấy Continue" và FS-12.16 AC-8 "rời studio, mở lại → Reels + Fill" cần project **được lưu khi rời**. Code và FS-12.08 §5 / FS-06.01b / FS-12.04 chỉ lưu khi **xuất**; Back có sửa = hỏi Discard rồi bỏ | **code đúng** — sửa hai AC thành "Export → mở lại từ Video Projects" (recipe xuất mang trạng thái nhận dạng và đích xuất): *một bản nháp tự lưu là mô hình lưu mới mà Discard và danh sách Video Projects (dòng = sản phẩm đã xuất, có ảnh bìa) đều chưa có, không nên đẻ ra bên trong một tính năng phụ đề*. Nếu muốn giữ chữ của spec thì phải mở intent riêng cho "lưu nháp" |
| **Q2** *(duyệt theo đề nghị)* | Hai spec tả **cùng** trạng thái Sẵn sàng của Export Video khác nhau: FS-12.10b §2–3, AC-1, AC-12 (`P7_ExportReady`, `IL5`, `DI6`), AC-13 (cấm chữ "1080p"/"4K" ngoài hàng tóm tắt; iPad form sheet 540) vs FS-12.16 §5, AC-1, AC-14 (danh sách preset, "YouTube 4K", sheet 660, nút 382×50 ở đáy) | **FS-12.16 đúng cho trạng thái Sẵn sàng; sửa FS-12.10b** (§2–3, AC-1, AC-12, AC-13) để chỉ còn các trạng thái Đang xuất · Đang lưu · Lỗi · huỷ · thiếu chỗ: *F8 là lớp sau cùng của cùng panel, giữ cả hai là xây Sẵn sàng hai lần rồi đập một*. Đề nghị plan vs-media-settings-export dựng khung panel + trạng thái, để nội dung Sẵn sàng cho task 34 |
| Q3 | FS-12.14 AC-10 chưa nói container; writer hôm nay `.mp4` | kỹ thuật, tự quyết ở task 11: giữ `.mp4` nếu `tx3g` vào được và đọc lại đúng; không thì **`.mov` chỉ khi Burn tắt** (Photos nhận cả hai). Báo lại nếu phải đổi |
| Q4 *(duyệt, spec đã sửa)* | `F4_IP_Captions`, `F7_DC_BeforeAfter`, `F8_IP_ExportPresets` đã có trên canvas, nhưng AC-15 / AC-14 / AC-14 không liệt kê, và §10/§4/§9 của ba spec còn ghi "chưa có board" | **tài liệu cần thêm**: thêm ba board vào AC parity tương ứng và bỏ dòng rủi ro "chưa có board" — task 17, 31, 49 đã chấm cả ba |

⚠️ đã chốt sẵn trong spec, không hỏi lại: F7 AC-2/AC-13 (Before bỏ de-log), AC-10 (nút luôn dùng được + "No edits to
compare yet."), AC-15 (không accent) — **tài liệu đúng, sửa code** (task 19–22).

## 9. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| Tốc độ nhận dạng on-device chưa đo; clip dài có thể vượt giới hạn một request | trung bình | đo trên iPhone 17 (mục tiêu ≤ 1× thời lượng tiếng); nếu request dài hỏng thì cắt ở khoảng lặng ~55 s trong `ClipAudioReader` |
| Callback `SFSpeechRecognizer` chạy trên hàng đợi riêng; huỷ ≤ 1 s; tiến độ nhảy MainActor mỗi buffer | trung bình | cầu nối `AsyncThrowingStream`, `onCancel` gọi `task.cancel()`, báo tiến độ mỗi 1% như writer (`VideoExportWriter.swift:156-176`); agent `swift-concurrency` |
| Bộ nhớ khi Fill từ 9:16 lên YouTube 4K: canvas ảo 3840×6827 → still giải ở cạnh 6827 | trung bình | trần giải still = min(nguồn, canvas ảo); LRU 4 của `StillFrameStore` tính theo byte; đo xuất 4K trên máy thật; agent `memory-leak` |
| Khung đôi khi so sánh gấp đôi chi phí preview (cộng grade 06c) | trung bình | Before không grade (rẻ hơn After); mỗi bên ≤ 1280 cạnh dài; task 32 đo, trượt thì Before nửa độ phân giải khi phát |
| Hai `AVPlayerLayer` cùng player có thể chỉ một lớp hiện hình | thấp–trung bình | spike ở task 23; đường lùi `AVPlayerItemVideoOutput` + `contentsRect` |
| Track `tx3g` trong `.mp4` qua `AVAssetWriter`, và qua Photos | trung bình | spike task 11 (Q3); Photos bỏ track là chấp nhận được (dòng phụ §6 nói trước) |
| Duo trong 669pt: cột 264 cao 385 chứa thẻ tiến độ + danh sách + Style | trung bình | board `F4_DI` quyết; cuộn trong cột; `Tools/sim-shot` có mask |
| Phụ đề sống vẽ lại mỗi tick `currentTime` | thấp | cache `CaptionLayout` theo khối; raster compositor cache theo (khối, kiểu, cỡ, khung, số từ hiện) |
| Project JSON lớn vì mốc từng từ | thấp | ~40 byte/từ, 10 phút nói ≈ 60 KB; mất mốc khi sửa tay |
| `timelineSelection` hôm nay = accent (`EditorTheme.swift:73`) — AC-17 cần #57BFD1 | chắc chắn nếu plan chrome chưa sửa | phụ thuộc §7; task 16 kiểm |
| Câu xin quyền mới chỉ có en + vi; các câu xin quyền khác chưa có bản vi | — | ghi `REVIEW_QUEUE.md` (ngoài bảng AC) |

## 10. Phản biện (điền sau khi chạy `challenger`)

| Phản đối | Trả lời / thay đổi |
|---|---|
| *(chưa chạy — chạy `challenger` trên Q1, K2 và việc gộp ba spec vào một plan trước khi duyệt)* | |

## 11. Cách chứng minh là xong

- **Test (Swift Testing):** `CaptionChunkerTests`, `CaptionTimelineTests`, `CaptionEditingTests`, `CaptionLayoutTests`,
  `CaptionLanguagesTests`, `CaptionRecognitionPlanTests`, `VideoCaptionDecodingTests`, `SpeechCaptionServiceTests`,
  `VideoCaptionSessionTests`, `VideoCaptionExportTests` · `VideoBeforeAfterTests`, `VideoBeforeAfterRenderTests` ·
  `VideoExportPresetTests`, `VideoExportFramingTests`, `VideoPresetExportTests`; `VideoStudioLayoutTests` thêm ba panel.
  Chạy test liên quan mỗi task; full suite + `Tools/gate` một lần khi xong cả intent.
- **Màn hình phải chụp** (cả nhánh iOS 26.5 và 18.6, mỗi máy): F4 — lần đầu (xin quyền), đang 58%, từ chối, không lời,
  Style, Language; F7 — Split, Side by Side, Hold, Swap, Duo trong; F8 — panel mở với YouTube, Reels + Fill, Fit, 4K mờ,
  Custom, Duo ngoài hai lần chạm. Duo dùng `Tools/ui-drive` + `Tools/sim-shot` (không dùng MCP sim tool); iPhone
  Video Studio không enumerate được nên dựa vào dump nút + `sim-shot`.
- **Parity:** `design-parity` trên 15 board F4/F7/F8 (kể cả ba board của Q4), lệch ≤ 2pt.
- **Đo máy thật:** iPhone 17 — tốc độ nhận dạng, chế độ máy bay (F4 AC-3), xuất 4K HEVC Fill (bộ nhớ); iPad — đồng bộ
  và khung rơi Side by Side (F7 AC-7). **Đo trên sim:** track phụ đề `.mp4`/`.mov` + nhập Photos, HEVC, hai `AVPlayerLayer`.
- **Agent ở giai đoạn Deploy:** `swift-concurrency` (nhận dạng, huỷ, khung đôi), `memory-leak` (4K Fill, raster phụ đề,
  khung đôi), `privacy-manifest` (câu xin quyền, NF-03), `photokit-guard` (đọc AVAsset của clip, iCloud, `.limited`),
  `data-migration` (trường recipe mới, giải khoan dung), `localization` (InfoPlist.xcstrings, chữ mới), `a11y-voiceover`
  (tay nắm, dòng preset, lane C1), `design-parity`, `device-layout`, `ios26-parity`, `design-reviewer` (`timelineSpeech`,
  màu nút so sánh), `perf-profiler` (khung đôi 30 fps).
- **Tài liệu cập nhật cùng commit:** cột "Chứng minh bằng" của FS-12.14/15/16 theo từng AC; FS-12.08 §2 (project giữ lane
  phụ đề + đích xuất); FS-12.01 §9 (track phụ đề mềm, tầng khung ra); DESIGN.md §3.3 (`timelineSpeech`, nếu plan F3 chưa);
  NF-03 (câu xin quyền đã có trong Info.plist); FS-12.10b theo Q2; AC parity theo Q4.
