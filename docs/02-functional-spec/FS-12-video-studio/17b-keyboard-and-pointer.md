# FS-12.17b — Bàn phím, danh sách phím tắt và skim bằng con trỏ

`FS-12.17b` · tier D · `Features/VideoStudio/VideoStudioScreen.swift` (lớp phím ẩn) · `VideoMediaPoolColumn.swift`
· `VideoViewerChrome.swift` · nguồn intent [video-studio-canvas-chrome](../../_intents/2026-10-03-video-studio-canvas-chrome.md) (F6) · cập nhật 2026-10-04 (iPad kiểu Mac)

**Một câu:** cắm bàn phím là dựng được bằng phím như ở NLE trên máy tính, giữ ⌘ là thấy mọi phím; trên iPad, rê con
trỏ qua một video trong thư viện là xem lướt nó mà không chạm vào timeline.

Cắt từng khung, Frame zoom: [FS-12.17](17-precise-trim-and-input.md). Chọn nhiều (⌘A): [FS-12.11](11-multi-select-and-reorder.md). Trước/sau (\\): [FS-12.15](15-before-after.md).

## 1. Người dùng cần gì

Người dựng quen J/K/L, I/O, ⌘B từ Final Cut, Premiere, Resolve. Với iPad có Magic Keyboard, tay rời bàn phím để chạm
là chậm. Họ cũng cần biết phím nào có, mà không phải đi đọc tài liệu.

## 2. Phạm vi

**Có:** 28 phím tắt trên mọi máy; danh sách phím khi giữ ⌘; vùng In–Out; skim bằng con trỏ trên ô thư viện (iPad).

**Cố ý không có:**
- Đổi phím theo ý người dùng. *Vì 28 phím theo chuẩn chung của các NLE; đổi phím là một màn cài đặt riêng chưa ai xin.*
- Skim trên timeline. *Vì playhead là chỗ đang làm việc; canvas vẽ timeline đứng yên khi skim.*

## 3. 28 phím

Một danh sách duy nhất sinh ra **cả** phím **lẫn** danh sách hiển thị, nên danh sách không bao giờ ghi một phím không chạy.
Mọi phím chạy trên mọi máy; danh sách trên iPhone và Duo gộp còn 12 dòng (§4).

| Nhóm | Lệnh (tên như board) | Phím | Hôm nay |
|---|---|---|---|
| Playback | Play or Pause · Stop | Space · K | Space có |
| | Play Backward · Play Forward · Faster | J · L · L L | mới |
| | Back a Second · Forward a Second | ← · → | có |
| | Back a Frame · Forward a Frame | ⇧← · ⇧→ | có, sửa bước theo fps project |
| | Go to Start · Go to End | Home · End | có |
| Edit | Split at Playhead | ⌘B | có |
| | Mark In · Mark Out · Clear In and Out | I · O · ⌥X | mới |
| | Trim Start to Playhead · Trim End to Playhead | ⌥[ · ⌥] | mới (lệnh đã có ở transport) |
| | Delete · Add Marker | ⌫ · M | mới (lệnh đã có) |
| | Undo · Redo | ⌘Z · ⇧⌘Z | có |
| View | Zoom In · Zoom Out · Fit Timeline | ⌘+ · ⌘− · ⇧Z | mới |
| | Select All · Deselect | ⌘A · Esc | ⌘A mới; Esc có |
| | Before and After · Export… | \\ · ⌘E | \\ mới; ⌘E có (mở sheet, không xuất ngay) |

- **J/K/L:** L phát tới 1×; bấm L lần nữa 2×, lần ba 4×. J tương tự nhưng phát lùi. K dừng. Đang 2× hoặc 4× thì nút
  play có nhãn trắng 30×15 "2×"/"4×". Âm thanh: 1× và 2× có tiếng (giữ cao độ), 4× và phát lùi thì tắt tiếng.
- **⇧← / ⇧→** bước **một khung của project** (fps của Video Settings), không còn cố định 1/30 s.
- **⌘+ / ⌘−** nhân/chia mức zoom cho 2, quanh playhead, trong dải 20 pt/giây … trần của FS-12.17 §6.
- **⌫** xoá thứ đang chọn; không chọn gì thì không làm gì. *Vì một phím cạnh Return không được xoá thứ người dùng không nhìn thấy.*
- **⌘A** chọn mọi clip trên lane video, vào chế độ chọn nhiều của FS-12.11.
- Mọi phím **không có phím bổ trợ** (Space, J, K, L, I, O, M, \\, ⌫) **im lặng khi đang gõ chữ** vào một ô nhập.
- Có sheet phủ Video Studio (Export, Video Settings, chọn nhạc): mọi phím của Video Studio im lặng.
- **Trong chế độ Trim từng khung:** ⇧← / ⇧→ = −1 / +1 Frame (dời mép, không dời playhead); Return = ✓; Esc = ✕.
- **Esc theo thứ tự:** thoát chế độ Trim (✕) → đóng danh sách phím → bỏ chọn.

## 4. Danh sách phím khi giữ ⌘

| Máy | Board | Hình dạng |
|---|---|---|
| iPhone 402×874 | F6_P_Keyboard | Chiếm chỗ của panel (cao theo tỉ lệ project, 340 với 16:9 tại y 450), bo trên 16. Đầu 46: icon phím 24 · "Keyboard Shortcuts" 14.5 đậm · ✕ 32. Dòng 36 "Keyboard connected" · "hold ⌘ for this list". 12 dòng cao 32, nắp phím ≥ 24×24 bo 6, chữ 12; danh sách cuộn. Timeline thu còn lát 96 + dải tổng quan 28; hàng 5 công cụ giữ nguyên |
| Duo trong 951×669 | F6_DI_Keyboard | Phủ đen 50%; thẻ 640×300 bo 20 tại (155, 150). Đầu: "Keyboard Shortcuts" 16 đậm · "Hold ⌘ to see these again". Hai cột 290 cách 12, dòng 34, 6 + 6 dòng |
| iPad 1376×1032 | F6_IL_Shortcuts (chỉ để so tên, nhóm) | **Danh sách phím của hệ thống** khi giữ ⌘ — app không vẽ thẻ riêng. Khai báo đủ 28 phím trong ba nhóm **Playback** (11) · **Edit** (10) · **View** (7), tên đúng board |
| Duo ngoài 466×678 | F6_DC_Keyboard (vẽ thêm) | Dạng iPhone trong vùng panel 334–644: đầu 46 (icon 24 · "Keyboard Shortcuts" · ✕ 32), dòng "Keyboard connected", 12 dòng cao 32 cuộn; khung 382×215 và transport không đổi |

- 12 dòng của iPhone và Duo (thẻ tự vẽ), đúng thứ tự board: Play or Pause · Backward · Stop · Forward · Back · Forward a Frame ·
  Split at Playhead · Mark In · Out · Trim Start · End to Playhead · Delete · Add Marker · Undo · Redo · Zoom In · Out ·
  Deselect · Export…
- **Mở:** tự hiện **một lần** khi Video Studio nhận phím đầu tiên từ bàn phím cứng (một lần cho mỗi lần cài app); sau đó giữ
  ⌘ 0,6 s. *Vì dòng "Hold ⌘ to see these again" nói người dùng đã thấy nó một lần.*
- **Đóng:** iPhone, Duo ngoài: ✕ hoặc Esc (danh sách nằm chỗ panel, không che khung nên được ở lại). Duo trong: thả ⌘
  nếu mở bằng giữ ⌘; chạm ra ngoài hoặc Esc nếu tự hiện. iPad: hệ thống tự đóng khi thả ⌘.
- Nút ✕ của iPhone đọc VoiceOver là "Close"; mỗi dòng đọc "Split at Playhead, Command B".
- **iPad dùng danh sách của hệ thống** (chốt 2026-10-03), không tự hiện lần đầu. *Vì iPadOS đã vẽ danh sách đó từ các
  phím app khai báo; thẻ tự vẽ sẽ chồng lên nó.* iPhone và Duo không có danh sách hệ thống nên vẽ thẻ riêng.

## 5. Vùng In–Out

- I đặt In, O đặt Out tại playhead. Trên thước: cờ trắng 18×18 chữ "I" / "O" đậm 11, vùng giữa tô sáng. ⌥X xoá cả hai.
- O trước In thì In = 0; đặt In sau Out thì Out bị xoá. Ghim vào thước như marker: xoá clip không kéo In–Out theo.
- Lưu trong project (hai giá trị tuỳ chọn, giây), không tới compositor, không phải bước undo. *Vì nó là chỗ đang làm, như playhead.*
- **In–Out chỉ để xem** (chốt 2026-10-03): có vùng thì **Loop Playback** lặp trong vùng, **Go to Start / Go to End**
  (nút transport và Home / End) nhảy tới In / Out. Chỉ có In thì Go to End về cuối project; chỉ có Out thì Go to Start về 0.
- Không có "Export In to Out", không xoá theo vùng. *Vì cả hai đụng export và mọi lane; chưa ai xin.*

## 6. Skim bằng con trỏ (iPad, board F6_IL_HoverScrub)

- Con trỏ trên một **ô video** của thư viện Media (Recents, Albums, In Video): vị trí ngang trong ô → thời điểm trong nguồn
  (46% của 0:05 → 0:02.3). Viewer chiếu khung nguồn đó, chưa áp look. *Vì clip chưa ở trong project.*
- Dòng tên dưới khung (đầu hàng phát, thay viewer header đã bỏ ở bố cục kiểu Mac 2026-10-04 — [03b §1](03b-desk-bands-and-lanes.md)) đổi thành "**Skimming** · Lake · 0:02.3 / 0:05"; ô có vạch dọc 1pt tại con trỏ; nhãn 76×20 bo 10 trên ô ghi
  thời điểm; dưới hàng ô dòng "Click adds · drag to place" 10.5pt, 55% trắng, căn phải.
- Playhead, thời gian transport và timeline **không đổi**. Con trỏ rời ô: viewer trở lại khung tại playhead ngay khung kế.
- Ô ảnh: viewer chiếu ảnh, dòng tên "Skimming · <tên>", không có vạch, không nhãn thời điểm.
- Đang phát thì không skim. *Vì hai thứ tranh nhau một viewer.*
- Click = chèn ở playhead; kéo = đặt vào timeline ([FS-12.09](09-media-panel.md)). Con trỏ trên tay nắm mép clip có hình mũi tên hai chiều ngang.
- Giải mã: một yêu cầu đang chạy, yêu cầu mới thay cũ, tối đa 30 lần/giây, cỡ viewer (cạnh dài ≤ 1280).

## 7. Đường hỏng

- **Video chỉ có trên iCloud** (có mạng hay không): skim **không** tải; viewer phóng to thumbnail của ô, dòng tên thêm
  "· Not downloaded". Nhãn thời điểm vẫn chạy.
- **`.limited`:** thư viện chỉ có ảnh được phép; skim chỉ chạm tới những ô đó.
- **Phát lùi không được** (item không hỗ trợ): J lùi bằng chuỗi tìm khung 15 lần/giây, tắt tiếng; nhãn vẫn "1×/2×/4×".
- **Rút bàn phím** khi danh sách đang mở: danh sách đóng. Đang 2× thì vẫn phát 2× tới khi chạm nút play.
- **Phím rơi vào lane khoá** (⌥[, ⌫ trên clip ở lane khoá): không làm gì, như nút tương ứng.

## 8. Tiêu chí nghiệm thu

Project mẫu 30 fps của [FS-12.17 §12](17-precise-trim-and-input.md), playhead 8,40 s. Bàn phím cứng nối qua simulator.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | project 24 fps, playhead 2,000 s | bấm ⇧→ | playhead 2,0417 s (±1 ms) | ✅ `VideoFrameGridTests.stepAt24fps` (2,000 → 2,0417 ±1 ms), `stepAt60fps`, `offGridStepsToNextLine`, `shiftRightStepsOneProjectFrame` (qua `model.stepFrames` — hàm chung của ⇧←/→ và Back/Forward a Frame của cả hai transport; read-out đếm cùng lưới: `00:00:02:01`); route `vs-keys-frame-step.json` iPad Pro 13" dọc 2026-10-08: Video Settings → 24, ⇧→ → giá trị "Project Overview" `00:00:00:01`, ⇧← về `…:00` (phím trong simulator giao không đều — một lượt mất hai → trần, một lượt ⇧→ tới hai lần — số đếm chính xác do unit test chứng minh) |
| AC-2 | đang dừng | bấm L, L | phát tới rate 2,0; nhãn "2×" trên nút play; bấm K thì rate 0 | ✅ `VideoShuttleTests.lTwiceIsTwoX`, `kStops`, `fourXAndReverseAreMuted`, `theModelKeepsTheRate`; iPad dọc (2026-10-08, `Tools/ui-drive` phím l, l rồi k): nút "Pause" value "2×", thẻ 2× trên đĩa play (`build/proofs/fs1217/t23-ipad-ll-2x.png`), sau K nút về "Play". Phát lùi (J) đo trên máy: M5 `canPlayReverse` chưa đo |
| AC-3 | playhead 5,0 s rồi 12,0 s | bấm I tại 5,0 s, O tại 12,0 s, bật Loop, Space | phát tới 12,0 s thì quay về 5,0 s; cờ I và O trên thước; ⌥X xoá cả hai | ✅ `VideoInOutRangeTests.loopTargetIsIn` (In 5 · Out 12: quay về 5; Play ngoài vùng bắt đầu ở In), `outBeforeInResetsIn`, `inAfterOutClearsOut`, `marksAreClampedToTheProject`; `VideoStudioInOutTests.keysMarkAndClear` (I, O, ⌥X qua `VideoKeyboardRouter`, không bước undo), `undoKeepsInOut`, `inOutIsSavedWithTheDraft`, `decodesWithoutTheKeys`; iPad dọc (2026-10-08, `Tools/ui-drive`: I tại 0:03.24, O tại 0:07.37, Loop, Space, dump mỗi giây): playhead 5,0 → 6,2 → **3,2** → 4,4 → 5,6 → 6,8 — không ra khỏi vùng; cờ "In Point"/"Out Point" 18×18 trên thước (`build/proofs/fs1217/t27-ipad-in-out-flags.png`); ⌥X: hết cờ. Loop quay đầu bằng `addBoundaryTimeObserver` tại Out |
| AC-4 | playhead 7,0 s trong Clip 2 (bắt đầu 3,0 s) | bấm ⌥[ | Clip 2 bắt đầu nguồn ở 4,0 s, dài 2,2 s; undo thêm 1 bước | ✅ **lệnh**: `VideoTrimToPlayheadTests.startAtSevenSecondsInClipTwo` (nguồn 4,0, dài 2,2), `speedTwoHalvesTheLocalDelta`, `edgeOrBelowMinimumDoesNothing`, `theModelAddsOneUndoStep` (+1 bước, Undo trả 0–6,2) — phép tính là `VideoClipTrimMath.trimToPlayhead`, dùng chung cho nút transport, chip và phím; **phím**: `VideoKeyboardRouterTests.optionBracketTrimsClipUnderPlayhead` (⌥[ nguồn 4,0 dài 2,2, một bước undo; ⌥] cắt đuôi), `lockedLaneIgnoresOptionBracket`; iPad dọc (2026-10-08, `Tools/ui-drive` L, K rồi ⌥[ tại 0:03.2): tổng 0:38.3 → 0:35.1 (`build/proofs/fs1217/t24-ipad-option-bracket.png`) |
| AC-5 | đang sửa chữ của một text overlay | gõ "jim k" | ô nhập có "jim k"; playhead đứng yên; không có In mới | ✅ `VideoKeyboardGateTests.bareKeysSilentWhileTyping` (đang gõ: I, K, Space, ←, ⇧←, ⌥[, ⌫ không đăng ký và không làm gì; phím ⌘ vẫn chạy), `everythingSilentUnderSheet` (dưới sheet/alert không phím nào, cả ⌘); iPad dọc (2026-10-08, `Tools/ui-drive`: Text, chạm ô chữ, `typeText "jim k"`): ô có "…jim k", playhead vẫn 0:00.0, không có cờ In (`build/proofs/fs1217/t30-ipad-typing-jim-k.png`). Đang gõ = `VideoTextInputMonitor` (thông báo begin/end editing của UITextField/UITextView); dưới sheet = cờ sheet của màn hình + `nestedModalCount` của panel. Lệch có chủ ý: khi gõ, im cả phím ⇧/⌥ (⇧← chọn chữ, ⌥[ gõ "“"), không chỉ phím trần |
| AC-6 | không chọn gì | bấm ⌫ | recipe không đổi | ✅ `VideoKeyboardDeleteTests.deleteWithoutSelectionDoesNothing` (recipe không đổi, không có bước undo, phím xám trong menu iPad); kèm `deleteRemovesTheSelectedClip` (⌫ xoá clip **đang chọn**, không phải clip dưới playhead; Undo trả lại), `lockedLaneKeepsTheSelectedClip` — `VideoStudioModel.deleteSelection()` |
| AC-7 | zoom 55 pt/giây | bấm ⌘+ hai lần | zoom 220 pt/giây; ⌘− hai lần về 55 | ✅ `TimelineZoomMathTests.commandPlusTwiceFrom55Is220` (55 → 110 → 220), `minusBack` (220 → 55; dừng ở 20), `ceilingWithFrameZoomOff` (160 khi tắt Frame zoom on pinch, 360 khi bật ở 30 fps); iPad dọc (2026-10-08, `Tools/ui-drive` ⌘= ×2 rồi ⌘- ×2, đọc value của `VideoTimeline`): 60 → 240 → 60 (`build/proofs/fs1217/t26-ipad-cmd-plus-twice.png`) |
| AC-8 | iPhone, lần đầu cắm bàn phím | bấm Space | danh sách hiện trong vùng panel với 12 dòng như board; khung video không đổi kích thước | ⚠️ chưa có |
| AC-9 | Duo trong, danh sách đã tự hiện một lần | giữ ⌘ 0,6 s rồi thả | thẻ 640×300 hiện khi giữ, biến mất khi thả; mở lại app không tự hiện nữa | ⚠️ chưa có |
| AC-10 | iPad, bàn phím cứng | giữ ⌘ | danh sách phím của hệ thống có đủ 28 lệnh, chia Playback · Edit · View, tên đúng board F6_IL_Shortcuts; không có thẻ do app vẽ | ⚠️ một phần — danh mục: `VideoShortcutCatalogTests.twentyEightInThreeGroups` (11/10/7), `namesMatchBoard` (tên từng nhóm như F6_IL_Shortcuts, nắp phím "⌘B" "⇧←" "L L"…), `noTwoShareAKey` (27 phím, Faster = L lần nữa, không đăng ký lần hai), `compactListHasTwelveRowsInBoardOrder`, `bareKeysAreTheBoardsNine`; đăng ký: iPad = menu bar `VideoStudioCommands` (Playback là menu riêng, Edit sau mục dán của hệ thống, View) qua `focusedSceneValue` — Undo/Redo giữ ở lớp nút ẩn vì menu Edit hệ thống giữ ⌘Z cho mọi ô nhập; iPhone/Duo = lớp nút ẩn sinh từ cùng danh mục (route `vs-keys-phone-layer.json`: →→ rồi ⌘B tách clip ở 2,0 s). **M3**: giữ ⌘ bằng XCUITest không gọi được danh sách hệ thống trên iPad sim (`vs-keys-ipad-cmd-hud-probe.json` — không có lớp nào hiện) → nhóm và số lệnh trong danh sách hệ thống chỉ kiểm được trên máy thật với bàn phím |
| AC-11 | chế độ Trim từng khung mở, đã −4 frames | bấm Esc | như ✕: recipe như trước khi vào chế độ | ⚠️ chưa có |
| AC-12 | iPad, video Lake 5,0 s trong thư viện, playhead 8,40 s | con trỏ tới 46% bề ngang ô | dòng tên dưới khung "Skimming · Lake · 0:02.3 / 0:05"; viewer chiếu khung nguồn 2,3 s; transport vẫn "0:08.4" | ⚠️ chưa có |
| AC-13 | AC-12 | con trỏ rời ô | dòng tên trở lại tên clip dưới playhead; viewer chiếu khung 8,40 s | ⚠️ chưa có |
| AC-14 | video chỉ có trên iCloud, tắt mạng | rê con trỏ qua ô | không có request mạng; viewer chiếu thumbnail; dòng tên có "· Not downloaded" | ⚠️ chưa có |
| AC-15 | board F6_P_Keyboard, F6_DI_Keyboard, F6_DC_Keyboard, F6_IL_HoverScrub | `design-parity` trên từng board | mọi phần tử lệch ≤ 2pt, không thiếu, không thừa | ⚠️ chưa có |
| AC-16 | In 5,0 s, Out 12,0 s, playhead 8,4 s | bấm Home, rồi End | playhead 5,0 s, rồi 12,0 s; ⌥X rồi Home → 0,0 s | ✅ `VideoInOutGoToTests.homeGoesToInEndToOut` (Home 5,0, End 12,0 qua `VideoKeyboardRouter`), `onlyInMeansEndIsProjectEnd` (chỉ In: End → 24,0; chỉ Out: Home → 0), `clearedHomeIsZero` — Home/End và cả bốn nút Go to Start/End của transport (iPhone, Duo, iPad) cùng gọi `goToStart()`/`goToEnd()` |
| AC-17 | In 5,0 s, Out 12,0 s | Export | file dài đủ 24,0 s (In–Out không cắt bản xuất); recipe clip không đổi | ✅ `VideoInOutExportTests.placementsIgnoreInOut` (project 24,0 s, In 5 · Out 12: vị trí clip, tổng 24,0 s và clip không đổi); `VideoExportInOutSmokeTests.inOutDoesNotShortenTheExport` — xuất thật (compositor → writer) project 6,0 s có In 1 · Out 4: file dài 6,0 s ±1 khung (rút từ 24 s cho nhanh — cùng luật, ¼ thời gian xuất) |
| AC-18 | Duo ngoài, lần đầu cắm bàn phím | bấm Space | danh sách hiện trong vùng 334–644 với 12 dòng như F6_DC_Keyboard; khung 382×215 không đổi | ⚠️ chưa có — `Tools/sim-shot` |

**Chưa chứng minh được:** cả 18. Phím tắt chưa có test nào hôm nay; `Tools/ui-drive` chưa có bước bấm phím — cần
thêm bước `key` vào driver trước khi AC-1…AC-11 có chứng minh.

## 9. Rủi ro

| Rủi ro | Xử lý |
|---|---|
| Phát lùi trên composition có compositor riêng có thể không được hỗ trợ | phương án tìm khung 15 lần/giây ở §7; đo trước khi chốt |
| Bắt sự kiện "giữ ⌘" trên iPhone cần đọc phím bổ trợ thô, không qua lớp phím tắt | thử trên Duo thật; không được thì mở danh sách bằng mục trong menu ⋯ |
| Skim 30 lần/giây với HEVC 4K làm nóng máy | hạ xuống 15 lần/giây khi máy báo nhiệt độ cao (NF-01) |
