# FS-12.09 — Media: thư viện ngay trong panel

`FS-12.09` · tier D · thay `Features/VideoStudio/VideoMediaPicker.swift` và tab của `VideoMediaPoolColumn.swift`
· `Data/Sources/PhotoLibraryService.swift` · cập nhật 2026-10-04 (iPad kiểu Mac)

**Một câu:** thêm ảnh và video vào phim mà không rời Video Studio — chạm là chèn ở playhead, giữ là kéo vào
timeline, và luôn thấy thứ gì đã có trong phim.

Nguồn intent: [2026-10-03-video-studio-canvas-chrome](../../_intents/2026-10-03-video-studio-canvas-chrome.md).
Board: `MP_P_*` ở [`docs/design/iphone/project/`](../../design/iphone/project/) · `MP_IL_*`, `MP_IP_Media` ở
[`docs/design/ipad/project/`](../../design/ipad/project/) (vẽ lại kiểu Mac 2026-10-04) · `MP_DI_Media`, `MP_DC_Media` ở
[`docs/design/duo/project/`](../../design/duo/project/).

## 1. Người dùng cần gì

Dựng phim là chọn đi chọn lại từng tấm. Trình chọn ảnh của hệ thống che cả màn, không kéo được vào đúng chỗ
và không biết tấm nào đã dùng — người dùng: "mở library thế này không có ý nghĩa". Thư viện phải nằm cạnh
timeline, đánh dấu thứ đã dùng, và tìm được theo máy, ống kính như ở Library.

## 2. Phạm vi

**Có:** tab Recents · Albums · In Video (n) · tìm · lưới có dấu đã dùng · chạm chèn · Select → Add (N) ·
giữ-kéo vào timeline · danh sách In Video · hàng quyền giới hạn. Pool iPad còn bốn tab: Media · Text · Stickers · Music.

**Cố ý không có:**
- Trình chọn ảnh của hệ thống trong Video Studio — vì nó là màn thứ hai che timeline; Collage vẫn dùng nó.
- Kéo một ô ra app khác — vì cử chỉ giữ-kéo thuộc về timeline; nhận thả **từ** app khác lên timeline vẫn giữ như hôm nay.
- Trần 400 mục và hàng "Browse All Photos…" — vì lưới đọc thẳng kết quả truy vấn lười của PhotoKit, cuộn tới mục cũ nhất.
- Tab Effects — look đã về công cụ Look ([06c](06c-photo-looks.md)).

## 3. Bố cục theo thiết bị

| | iPhone 402×874 | iPad ngang 1376×1032 | iPad dọc 1032×1376 | Duo trong 951×669 | Duo ngoài 466×678 |
|---|---|---|---|---|---|
| Mở từ | ô Media hàng đáy | tab Media của pool | nút Media của dock | ô Media hàng đáy | ô Media trong dải 84 |
| Vùng | panel cao theo tỉ lệ project: 16:9 340 · 1:1 320 · 4:5 300 · 9:16 278 · 4:3 360 · 21:9 340 | pool kính nổi 320×568 ở (8, 8) | dock 324 dưới timeline | cột phải 264, cao 385 | panel 232 dưới lát timeline 146 |
| Hàng tab | cách đỉnh panel 10, cao 30, lề 12 | segmented 294×36 (nút 95×32) ở y 121, dưới segmented 4 tab pool | segmented 420×36 (nút 137×32) ở dock + 13, lề 16; 🔍 44 ở x 972 | y 14, lề 9 | y 456, lề 12 |
| Lưới | 4 cột ô 99, khe 2, sát mép | 3 cột ô **96**, khe 4, lề 13 (x 21–317) | 8 cột ô **122**, khe 4, lề 16 | 3 cột ô 80, khe 4 | 4 cột ô 94, khe 2 |
| ✕ · tên · ✓ | hàng đáy 62: ✕ 44 ở x 14, ✓ 44 ở x 344 | không có | chân dock 64 ở y 1312: ✕ 44 ở x 16, ✓ 44 ở x 972 | góc phải hàng đáy: ✕ 40 ở x 620, ✓ 40 ở x 867 | dải 84: ✕ 44 ở y 504, ✓ 44 ở y 556 |
| Dòng phụ dưới "Media" | theo trạng thái (§4) | — | "Drag up onto the timeline" | "Drag onto the timeline" | "drag up" |

- Tab: cao 30, bo `r-sm`, chữ 12.5; nền trắng 20% khi mở, 6% khi không. Ô lưới vuông, không bo (DESIGN §5).
- **Select và Tìm** (chốt 2026-10-03), mọi máy đều có cả hai:
  - iPhone, Duo ngoài: cuối hàng tab, đẩy về mép phải — `Recents · Albums · In Video · 6 · Select · 🔍`; Select là
    chữ cao 30, 🔍 tròn 30.
  - Pool iPad: Select chữ 68×44 cạnh 🔍 44 ở hàng tiêu đề "Library" (Library · Select · 🔍 · Hide Media), y 25.
  - Duo trong: hàng tab cuộn ngang, Select và 🔍 ở cuối, mép phải mờ 24pt báo còn nữa.
  - *Vì giữ trên ô đã là kéo, nên chọn nhiều không vào bằng menu giữ.*
  Pool 320 (kiểu Mac 2026-10-04): hai hàng tab là segmented 294 — vừa, không còn luật thu đệm của pool 236.
- iPad ngang không có ✕/✓ cho Media: pool là cột thường trực, mỗi lần chèn là một bước undo thường.
- Lát timeline trên panel iPhone chỉ có ở 16:9 (96) và 21:9 (150), kèm dải tổng quan 28; 1:1, 4:5, 9:16, 4:3 chỉ còn
  dải tổng quan ([07 §3](07-phone-layout.md)).

## 4. Trạng thái

| Trạng thái | Hiển thị |
|---|---|
| Thường (Recents) | tab · nút **Select** · nút tìm tròn 30 (`Search Library`), chỗ đặt theo §3; dòng phụ iPhone "Tap adds at 0:08.4 · hold to drag" |
| Chọn nhiều | Select sáng; nút trắng **Add (3)** thay nút tìm; ô được chọn viền trắng 2 + số thứ tự góc trái trên; dòng phụ "3 selected · Add puts them at 0:08.4" |
| Đang kéo | ô gốc thành ô gạch đứt; bóng ảnh 70×70 phóng 1.1×, nghiêng −3°, viền trắng 2; dòng phụ "Drop between clips · back on the grid cancels" |
| In Video | danh sách theo thứ tự timeline, hàng 56 (iPhone và pool iPad 302×56); dòng phụ "6 items in this video"; pool iPad (không có dòng phụ) có chú thích cuối danh sách "In timeline order. Tap one to jump there and select it." (board `MP_IL_InVideo` kiểu Mac) |
| Albums | danh sách album (bìa · tên · số mục); chạm mở lưới của album, nút ‹ Albums ở chỗ hàng tab |
| Tìm | ô tìm thay hàng tab, Cancel bên phải; lưới là kết quả |
| Quyền `.limited` | hàng đầu Recents: khoá · "ShotDex can see the 12 items you chose." · nút **Manage Access…**; dòng phụ "Limited Photos access" |
| Bị từ chối | "No Access to Photos" + Open Settings (chữ của NF-04); In Video vẫn dùng được |
| Rỗng | thư viện rỗng: "No photos or videos yet." · In Video rỗng: "Nothing from your library is in this video yet." |

- Ô video: thời lượng góc phải dưới ("0:06", 10.5 đậm). **Dấu đã dùng:** tròn trắng 19, ✓ đen, góc phải trên cách 5;
  dùng từ 2 chỗ trở lên thì ✓ thành viên nang trắng chữ đen "×2", "×3"… (chốt 2026-10-03, đúng chữ này) — *vì dùng lại
  một cảnh làm mở và kết là có chủ ý.*
- **Số đếm = số hàng = số lần dùng** (chốt 2026-10-03): mỗi clip và mỗi sticker là một hàng của In Video, kể cả khi
  hai hàng cùng một mục thư viện; clip bị tách đôi là hai hàng. Số trên tab ("In Video · 6") luôn bằng số hàng.
  *Vì một luật thì tab và danh sách không bao giờ lệch nhau.*
- In Video, mỗi hàng: thumbnail · tên như trên timeline · "Photo · clip 1" / "Video · clip 2" / "Photo · sticker"
  · khoảng giờ "0:03–0:09" chữ đơn cách · chevron. Hàng của thứ đang dưới playhead có nền sáng.

## 5. Hành vi

**Chạm (ngoài Select):** chèn ở playhead — playhead trong một clip thì tách clip đó, chèn vào vết cắt; playhead
đúng mép clip thì chèn ở mép, không tách. Playhead nhảy tới cuối clip mới. *Vì chạm liên tiếp ba ô phải ra ba clip đúng thứ tự.*

**Select → Add (N):** chạm ô để thêm/bỏ; số thứ tự đánh lại khi bỏ một ô. Add chèn cả N ở playhead **theo thứ
tự chọn**, một bước undo. Add (0) mờ. Chạm Select lần nữa thoát và bỏ hết lựa chọn.

**Giữ-kéo:**
- Giữ **0,3s**, ngón trôi < 10pt → bóng nhấc lên (haptic nhẹ). Trôi ≥ 10pt trước 0,3s là cuộn lưới.
- Nhận dạng giữ-rồi-kéo là của **UIKit, gắn trên chính scroll view của lưới**; khi nó bắt đầu thì pan của scroll view
  bị huỷ. *Vì cử chỉ SwiftUI chết trong nội dung host của UIScrollView (đã gặp ở timeline).*
- Đang chọn nhiều thì kéo một ô đã chọn mang **cả nhóm** (chồng ảnh có số), chèn theo thứ tự chọn.
- Trên timeline: vạch trắng 4×(cao lane video) dính vào **ranh giới clip gần ngón nhất**, viên nang trắng
  68×20 chữ đơn cách "+ 0:09.2" phía trên vạch; mỗi lần đổi ranh giới có một tick haptic.
- Ngón trong 40pt mép trái/phải timeline → timeline tự cuộn, nhanh dần theo độ sâu.
- Không có lát timeline (iPhone 1:1, 4:5, 9:16, 4:3): đích thả là **dải tổng quan** — vạch và viên nang vẽ trên dải.
  *Vì đó là chỗ duy nhất còn thấy cả project.*
- Thả trên đích → chèn ở ranh giới đó, **không tách clip**, một bước undo. Thả lại lưới, trên khung hình hay
  ngoài màn → huỷ: bóng bay về ô gốc 0,25s, project không đổi, không có bước undo.

**In Video:** chạm một hàng → playhead nhảy tới đầu item và chọn nó. iPad ngang: pool giữ In Video, inspector
chuyển sang item. Máy khác: Media đóng như ✓, panel / dock / cột phải chuyển sang item (chung một chỗ).

**✕ / ✓** (iPhone, iPad dọc, Duo): Media là một phiên như panel của editor ảnh.
- ✕ trả project về đúng lúc mở Media và không để lại bước undo nào.
- ✓ giữ từng bước đã làm; còn ô đang chọn chưa Add thì ✓ Add luôn — *mất ba ô đã chọn khi bấm ✓ là lỗi im lặng.*

**Tìm:** cùng ngôn ngữ truy vấn của Library ([FS-01.03](../FS-01-library/03-search.md)) — "85mm", "ISO 3200",
tên máy — trên index của app. *Đây là thứ trình chọn hệ thống không làm được.*

- **Manage Access…** mở trình chọn quyền giới hạn của hệ thống; đóng lại thì lưới nạp lại tại chỗ. Nhãn này dùng
  **mọi nơi**, cả Library (chốt 2026-10-03, §9).
- **iCloud:** asset chỉ có trên iCloud vào timeline ngay rồi tải nguồn; tải hỏng thì clip bị gỡ kèm
  câu sẵn có "One clip couldn't be loaded and was left out. It may still be in iCloud — check your connection and add it again."

## 6. Dữ liệu

| | |
|---|---|
| Đọc từ | PhotoKit trực tiếp (Recents, Albums, quyền); index của app cho Tìm |
| Ghi vào | công thức project: clip mới; overlay ảnh (sticker) **giữ id asset nguồn** để có dấu đã dùng và hàng In Video; sticker cũ chưa có id thì không có dấu |
| Không lưu | tab đang mở, album, chuỗi tìm, các ô đang chọn — trạng thái phiên |
| `photo_metadata` | không đụng (BD-02); trường id nguồn mới không migration (app chưa phát hành), đọc vẫn khoan dung |

## 7. Ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Hiệu năng | xin thumbnail đúng cỡ ô × scale màn, cache có trần, nạp trước tối đa 2 màn lưới (NF-01, NF-02) |
| Thiết bị | năm cột của §3; Duo ngoài không đặt gì vào dải 84 ngoài ô công cụ và ✕/✓; iPad mọi nút ≥ 44 (kiểu Mac) |
| iOS 26 vs trước | cùng một bộ hành động trên hai nhánh |
| Truy cập | ô: "Video, 0:06, in this video"; action **Insert at Playhead** và **Select** thay cho kéo |

## 8. Tiêu chí nghiệm thu

Project mẫu: 16:9, 5 clip 24,0s (Falls ảnh 0–3,0 · Coast video 3,0–9,2 · Lake video 9,2–14,2 · Night ảnh 14,2–17,2
· Forest video 17,2–24,0) + sticker "Road" 6,0–8,0; playhead 8,4.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | project mẫu, Media mở, một ảnh chưa dùng | chạm ô đó | Coast tách tại 8,4; ảnh vào giữa; 7 clip, 27,0 s; ô có ✓; tab thành "In Video · 8" (7 clip + sticker); playhead 11,4 | `MediaInsertMathTests.tapSplitsCoastAt8_4` (Coast tách ở 8,4, 7 clip, kết 27,0 s, playhead 11,4, `useCount` 8), `.edgeInsertsWithoutSplit`, `.threeTapsKeepOrder`, `.severalGoInInTheOrderGiven`; sim 26.5: hai lần chạm cùng ô ở playhead 0 → 0:06.0 / 0:15.0, ô "×2", tab "In Video · 5" (`vs3/out/m4/04-tap2.png`) |
| AC-2 | project mẫu, Select, chọn 3 ô | bấm Add (3) | 3 clip mới theo thứ tự 1-2-3 sau vết cắt 8,4; một Undo về đúng 5 clip | `VideoStudioMediaSessionTests.addThreeInSelectionOrderOneUndo` (chọn C·X·A·B, bỏ X → số 1-2-3 đánh lại; Add → C, A, B sau vết cắt 8,4; một Undo về 5 clip), `.confirmAddsPendingSelection` (✓ còn ô chọn → Add rồi đóng; ✕ không thêm); sim 26.5: ô chọn viền trắng + số 1·2·3, nút trắng "Add (3)", dòng phụ "3 selected · Add puts them at 0:00.0", Add → 3 clip mới, In Video · 6 (`vs3/out/m6`) |
| AC-3 | project mẫu, video 14,0s trong lưới | giữ 0,3s, kéo tới giữa Lake và Night | vạch trắng ở 14,2 + viên nang "+ 0:14.2"; thả → video là clip 4 bắt đầu 14,2, Lake không bị tách, tổng 38,0s | ⚠️ một phần — `MediaInsertMathTests.nearestBoundaryBetweenLakeAndNight` (14,5 s → ranh giới 14,2 trước clip 4), `.autoscrollSpeedGrowsWithDepth`, `.dropDoesNotSplit` (video 14,0 s ở ranh giới 3 → clip 4 từ 14,2, Lake nguyên, 38,0 s), `VideoStudioMediaSessionTests.dropLandsOnTheNearestSeam` (hình học lane giả → vạch ở x 311, thả → clip 4, một Undo về như cũ), `.draggingAPickCarriesTheGroup`; sim 26.5 (`ui-drive` bước `drag` có `pressSeconds` 0,4): bóng 70 nghiêng, ô gốc gạch đứt, viên nang "+ 0:03.0", dòng phụ "Drop between clips…", thả → clip mới ở 3,0, tổng 12,0 s (`vs3/out/m11burst/b040.png`, `vs3/out/m11/04-dropped.png`); **haptic: máy thật**; **đích dải tổng quan khi không có lát timeline: code có (overview công bố hình học), chưa chụp** — bố cục iPhone theo tỉ lệ (lát/dải 28) là khối E của plan tools |
| AC-4 | đang kéo như AC-3 | thả lại trên lưới | project vẫn 5 clip 24,0s; nút Undo không đổi trạng thái | `VideoStudioMediaSessionTests.cancelledDropChangesNothing` (ra khỏi đích → thả: recipe và trạng thái Undo không đổi, bóng bay về); sim 26.5: kéo rồi thả lại trên lưới → vẫn 0:12.0, In Video · 4 (`vs3/out/m11/05-cancelled.png`) |
| AC-5 | lưới Recents đứng yên | vuốt dọc 30pt trong 0,2s đầu | lưới cuộn, không bóng nào nhấc lên | sim 26.5: vuốt dọc nhanh trên lưới → lưới cuộn, không bóng nào nhấc (`vs3/out/m11/03-swiped.png`); nhận dạng giữ là `UILongPressGestureRecognizer` 0,3 s / 10 pt trên chính collection view, chạy song song với pan, nhấc thì huỷ pan |
| AC-6 | Falls dùng ở clip 1 và clip 6 | mở Recents | ô Falls hiện "×2"; xoá clip 6 → về ✓; xoá cả clip 1 → không còn dấu | `MediaUsageTests.twoUsesShowTimesTwo` (Falls ở clip 1 + clip 6 → ×2), `.deletingBackToOneShowsCheck` (xoá clip 6 → ✓, xoá clip 1 → không dấu), `.tabCountIsEveryUse`; ô lưới vẽ ✓ tròn 19 / viên nang ×n từ `MediaUsage.badge` (sim 26.5: 3 ô đã dùng mang ✓, ảnh `vs3/out/m3/02-media.png`) |
| AC-7 | project mẫu | mở In Video, chạm "Coast" | 6 hàng đúng thứ tự timeline có khoảng giờ; playhead 3,0, clip 2 được chọn; iPhone mở panel clip | `MediaUsageTests.inVideoRowsInTimelineOrder` (6 hàng theo nơi bắt đầu: Falls · Coast · Road · Lake · Night · Forest, "0:03–0:09"…), `VideoStudioMediaSessionTests.inVideoTapJumpsAndSelects` (Coast → playhead 3,0, clip 2 chọn, Media đóng như ✓; Road → 6,0, sticker chọn); sim 26.5: tab In Video, hàng dưới playhead sáng, dòng phụ "3 items in this video", chạm hàng 2 → 0:03.0 và panel clip "Photo 2" (`vs3/out/m7`). Lệch board `MP_P_InVideo`: board vẽ sticker Road ở cuối; spec ghi "thứ tự timeline" nên code xếp theo điểm bắt đầu; tên hàng là ngày chụp (timeline không đặt tên clip) |
| AC-8 | Media mở, đã chạm chèn 2 ô | bấm ✕ | về 5 clip 24,0s; số bước undo bằng lúc mở Media | `VideoStudioMediaSessionTests.cancelRestoresAndLeavesUndoDepth` (Media mở, chèn 2 ô ở 8,4 → ✕ → 5 clip như lúc mở, ngăn undo dài đúng như lúc mở, redo rỗng), `.commitKeepsEachStep`; ✕ · Media · ✓ ở chân panel iPhone, chân dock iPad dọc, góc phải hàng đáy Duo trong, dải 84 Duo ngoài |
| AC-9 | quyền `.limited`, 12 mục được cấp | mở Recents | đúng 12 ô + hàng "ShotDex can see the 12 items you chose." + Manage Access…; cấp thêm 3 → 15 ô, panel không đóng | ⚠️ một phần — code: hàng khoá · "ShotDex can see the N items you chose." · Manage Access… trên Recents khi `.limited` (N = số mục fetch được), lưới nạp lại theo `assetChangeToken` ngay trong panel, trình chọn quyền giới hạn mở từ controller trên cùng (không còn mở từ root bị che); bị từ chối: "No Access to Photos" + Open Settings, In Video vẫn dùng; rỗng: "No photos or videos yet."; `VideoMediaLibraryTests.limitedRowCountsGrantedItems` (chữ + số ít); **sim `.limited` 12 → 15: chưa làm** — cần `simctl privacy reset` + chạm tay trên simulator dùng chung với các phiên khác |
| AC-10 | video chỉ có trên iCloud, máy không mạng | chạm ô đó | sau khi tải hỏng: vẫn 5 clip, hiện câu "One clip couldn't be loaded…" | `VideoMediaOriginalsTests.offlineVideoIsLeftOutWithMessage` (project mẫu, chạm video chỉ có trên iCloud ở 8,4, tải hỏng → đúng 5 clip như trước — vết cắt cũng được trả —, câu "One clip couldn't be loaded…", Undo không có bước rỗng, playhead về 8,4), `.inCloudPhotoReadsFromTheDownloadedFile` (ảnh tải về thư mục phiên, bản xuất là đỏ của file), `.inCloudVideoOpensFromTheDownloadedFile`; sim 26.5 `-ShotDexFakeICloud cloud=all,fail=4,seconds=1`: chạm ô → câu iCloud, vẫn 3 clip 0:09, Undo tắt (`vs3/out/m8/04-failed.png`); **máy thật chế độ máy bay: chưa làm** |
| AC-11 | thư viện 55 000 mục | cuộn Recents tới cuối | thấy mục cũ nhất; không có hàng "Browse All Photos…"; bộ nhớ app tăng < 60MB so với lúc mở | ⚠️ một phần — `VideoMediaLibraryTests.recentsIsTheWholeFetchNoCap` (fetch không `fetchLimit`, mới nhất trước), `.prefetchWindowIsTwoScreens`, `.prefetchMovesByTheDifferenceOnly`; lưới `UICollectionView` trên `PHFetchResult` lười, hàng "Browse All Photos…" và trần 400 đã gỡ khỏi Media (sim 26.5: 102 mục cuộn được, ảnh `vs3/out/m1`); **máy thật 55 000 mục, bộ nhớ < 60 MB: chưa đo** (cần thư viện thật + Instruments) |
| AC-12 | thư viện có 20 ảnh chụp ở 85mm | gõ "85mm" vào tìm | lưới đúng 20 ô | `VideoMediaLibraryTests.searchUsesTheLibraryQueryLanguage` (index trong bộ nhớ: 20 dòng 85 mm + 12 dòng 35 mm → "85mm" ra đúng 20 id, qua `SearchService.resolve` + `LibraryQueries`); sim 26.5: 🔍 thay hàng tab bằng ô tìm + Cancel, gõ chạy tìm sau 0,35 s, lưới là kết quả (`vs3/out/m10/03-search.png`) |
| AC-13 | iPad 1376×1032 | mở Video Studio | pool kính nổi 320×568 ở (8, 8) có đúng 4 tab Media · Text · Stickers · Music (segmented 294×36); hàng Recents · Albums · In Video · 6 (segmented 294×36) vừa trong pool; hàng tiêu đề có Library · Select (68×44) · 🔍 44 · Hide Media 44; lưới 3 × 96 khe 4 | ⚠️ cần làm lại theo bố cục kiểu Mac 2026-10-04 — bằng chứng cũ (`VideoStudioDeskLayoutTests.poolMediaGridIsThreeColumnsOf69`, dump `vs3/out/m15` trên iPad Pro 13 26.5: tab 59×38, Select 54×30, lưới 3 × 69 trong pool 236; commit `0fbde9bf`) đo pool 236; thứ tự tab và tiêu đề vẫn đúng, mọi khổ đổi — **chờ bố cục iPad kiểu Mac** (2026-10-04: pool 236 → 320 kính nổi, board iPad mới ở `docs/design/ipad`); lưới lấy bề rộng từ chỗ chứa, không cứng 236 |
| AC-14 | VoiceOver bật, ô video 0:06 đang dùng | đọc ô | "Video, 0:06, in this video" + action Insert at Playhead, Select | ⚠️ một phần — `MediaUsageTests.accessibilityLabelSaysInThisVideo` ("Video, 0:06, in this video"; ảnh chưa dùng: "Photo, <ngày>"); ô có hai custom action **Insert at Playhead** (= chạm) và **Select** (bật Select và chọn ô); **VoiceOver thật trên máy / Accessibility Inspector: chưa chạy** |
| AC-15 | từng board `MP_P_MediaPicker` · `MP_P_Drag` · `MP_P_InVideo` · `MP_P_Limited` · `MP_IL_MediaPicker` · `MP_IL_InVideo` · `MP_IP_Media` · `MP_DI_Media` · `MP_DC_Media` · `MP_P_Drag916` | `design-parity` | mọi phần tử board đặt tên lệch ≤ 2pt (sau khi board sửa theo §9) | ⚠️ chưa có |
| AC-16 | iPhone, project mẫu, Media mở | dump hàng tab | thứ tự Recents · Albums · In Video · 6 · Select · 🔍, Select và 🔍 nằm hết trong x ≤ 390 | ảnh sim 26.5 (`vs3/out/m2/03-albums.png`, khung 402 pt): hàng tab Recents · Albums · In Video · 3 · Select · 🔍, nút tìm tròn 30 kết thúc ở x 390, lề 12; **dump: không có** — XCUITest không liệt kê Video Studio trên iPhone |
| AC-17 | Duo trong 951×669, Media mở | vuốt hàng tab sang trái | Select và 🔍 hiện ở cuối; trước khi vuốt mép phải hàng có dải mờ 24pt | ⚠️ một phần — cột Duo trong (lưới `.duoColumn`): hàng tab là `ScrollView` ngang, lề 9, y 14, Recents · Albums · In Video · 3 · Select · 🔍 (Select ở x 924,5, 🔍 ở 988,5 — ngoài mép 951 trước khi vuốt), mép phải mờ 24 pt; ảnh stand-in iPad Pro 13 `-VideoStudioStandIn duoInner` (`vs3/out/m16/host-20-duo-media.png`), ✕ · Media · ✓ ở góc phải hàng đáy; **vuốt hàng tab: chưa chứng minh** — trong stand-in trên iPad xoay ngang, kéo của `ui-drive` không cuộn được cả lưới lẫn hàng (chạm thì được), cần máy Duo thật |
| AC-18 | Falls dùng ở clip 1, clip 6 và một sticker | mở Recents | ô Falls hiện viên nang "×3", không còn ✓ tròn | `MediaUsageTests.stickerCountsAsAUse` (2 clip + 1 sticker → ×3; sticker không id, chữ: không tính) |
| AC-19 | thư viện có album "Hikes" 42 mục; iPhone, Media mở | chạm Albums, chạm "Hikes", rồi ‹ Albums | danh sách album có bìa · tên · số mục ("42"); lưới album đúng 42 ô, có dấu đã dùng như Recents; nút ‹ Albums ở chỗ hàng tab; chạm nó về danh sách album | ⚠️ một phần — `VideoMediaLibraryTests.albumGridIsTheAlbumFetch` (lưới album = fetch của album, không trần, cùng dấu đã dùng như Recents); danh sách album bìa · tên · số mục, "‹ Albums" thay hàng tab; sim 26.5 không có album nào → chỉ chụp được trạng thái rỗng "No albums yet." (`vs3/out/m2/03-albums.png`); **album 42 mục: chưa chụp** (cần tạo album trên sim) |

**Chưa chứng minh được:** AC-1 → AC-19.

## 9. Đã chốt (2026-10-03) và rủi ro

- **Select và Tìm** ở cả bốn bố cục — chỗ đặt ở §3. Board cần sửa theo: `MP_P_MediaPicker` · `MP_P_Drag` ·
  `MP_P_Limited` · `MP_P_InVideo` · `MP_IL_*` · `MP_DI_Media` · `MP_DC_Media`.
- **"Manage Access…"** là nhãn duy nhất cho quyền giới hạn (NF-04 đòi cùng một chữ cho cùng trạng thái).
  Việc kèm, chưa làm ở lượt này: banner Limited Access của Library ([FS-09](../FS-09-onboarding-and-permissions.md) §3,
  [NF-04](../../04-non-functional-design/NF-04-empty-and-error-states.md)) đổi nút **Manage** → **Manage Access…**.
- **Dấu dùng nhiều lần** là viên nang "×2", "×3"… thay cho ✓ (§4).

| Rủi ro | Xử lý |
|---|---|
| Không có board kéo cho project 1:1 / 4:5 / 9:16 (đích là dải tổng quan) | vẽ thêm `MP_P_Drag916` trước khi code phần này |
| Pan UIKit và cuộn ngang timeline giành nhau khi bóng ở mép | timeline tự cuộn chỉ chạy khi bóng đang nhấc; pan của timeline tắt suốt lúc kéo |
