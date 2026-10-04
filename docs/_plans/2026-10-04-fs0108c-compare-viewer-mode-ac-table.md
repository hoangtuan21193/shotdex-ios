# Bảng đối chiếu AC ↔ code — FS-01.08c Compare là chế độ của Viewer

Thuộc [plan](2026-10-04-fs0108c-compare-viewer-mode.md). Đặc tả:
[`FS-01.08c`](../02-functional-spec/FS-01-library/08c-compare-viewer-mode.md) (26 AC). Đọc code ngày 2026-10-04.

**Ký hiệu.** ✅ code đã đạt (chỉ viết test khoá) · ⚠️ᴰ lệch, nhưng **D15 đã chốt** "tài liệu đúng" (code còn làm theo
FS-01.08 cũ mà 08c thay thế — không hỏi lại) · ⚠️ lệch **cần hỏi** (xem plan §8) · ❌ chưa có · ⏳ chờ plan khác.

## Code hôm nay, một đoạn

Compare là một `fullScreenCover` riêng, **tầng D đen**: `ZStack { Color.black … }.statusBarHidden()`
(`CompareScreen.swift:300-312`). Một cách nhìn duy nhất — cột chồng theo `CompareLayout.columns` (khung ≥ 330, ≤ 3 cột,
`CompareLayout.swift:14-39`) và `distribute` (`:52-67`), cuộn dọc (`CompareScreen.swift:374-406`). **Chạm khung = đánh
dấu xoá** (`onSingleTap: onToggleMark`, `:670`, `:680`; caption cũng là nút, `:712-725`). Dấu là **một `Set` cục bộ**
(`localMarks`, `:291`) hoặc binding vào `DuplicateReviewSession.marks` (`:280`, `:318-327`;
`DuplicatesScreen.swift:139-145`) — **không** phải cờ `PhotoMarks`, nên mất khi đóng. Vòng rỗng / thùng rác đỏ góc
trên-phải (`:692-703`), viền đỏ 3pt + mờ 0.82 (`:586`, `:608-616`). Góc trên-phải: dòng gợi ý *"Tap a photo…"* khi
0 dấu, nút đỏ đặc `Delete N Photo` khi có (`:442-447`, `:477-506`). Xoá: `photoLibrary.deleteAssets` rồi **đóng khi
còn < 2** (`:533-548`); đường Duplicates trả về `DuplicatesModel.delete(ids:)` (`DuplicatesModel.swift:661-688`) rồi
**đóng màn** (`CompareScreen.swift:515-526`). Đồng bộ phóng/kéo luôn bật, không công tắc nào trên UI
(`CompareScrollSynchronizer`, `:17-126`; cờ `isZoomSyncEnabled`/`isPanSyncEnabled` `:18-19` không ai đổi), kéo ảnh
cần **hai ngón** (`panRequiresTwoFingers: true`, `:681`; video `:151-154`). Không phím nào (không
`PhotoMarkKeyButtons`), không Select/Candidate, không Survey, không Make Select. Lối vào: chế độ chọn ở 4 màn
(`LibraryScreen.swift:159-163`, `AlbumDetailScreen.swift:59`, `OnThisDayScreen.swift:99`,
`SmartAlbumDetailScreen.swift:111`) — mỗi màn một bản `comparePhotos(_:)` gần giống hệt (`LibraryScreen.swift:436-449`,
`AlbumDetailScreen.swift:471-480`, `OnThisDayScreen.swift:336-343`, `SmartAlbumDetailScreen.swift:462-468`) — và
Duplicates (`DuplicatesModel.swift:614-633`). Viewer cũng **luôn tối** (`PhotoDetailScreen.swift:203`, `:316`).

Đã có và dùng lại được: cờ thật + nhớ trong bộ nhớ (`PhotoMarks.setFlag`/`apply`, `PhotoMarks.swift:154-166`,
`:239-244`), bảng `photo_flag` (`PhotoMarksStore.swift:109-124`), xoá kèm gỡ cờ (`PhotoLibraryService.swift:967-975`
→ `AppDependencies.swift:346-352`), bộ xoá Rejected (`RejectedDeleter.swift:8-50`, `RejectedDeletion.swift:7-18`),
phím `0–5 P X U` (`MarkKeyCommand.swift:18-40`, `PhotoMarkKeyButtons` `PhotoMarkMenus.swift:122`), hàng Cull
`[Reject][★×5][Pick]` (`CullScreen.swift:170-220`, `CullLayout.swift:11-17` — **tầng D**), ô lưới mờ 45 % khi Reject
(`PhotoGridCollectionView.swift:2044`, `:2237`, `:2281`), cổng "giữ ít nhất một" (`DuplicatesModel.swift:457-490`),
nguồn danh sách id cho Viewer (`PhotoListModel`, `PhotoListModel.swift:14`), lớp cửa sổ
(`VideoStudioWindowClass.resolve`, `VideoStudioWindowClass.swift:31-50`).

## Bảng

| AC | Trạng thái | Bằng chứng | Việc · task |
|---|---|---|---|
| AC-1 iPad 4 ảnh → 2-Up, Select = ảnh đầu, `Candidate 1 of 3`; nền như Viewer Single, sáng và tối | ⚠️ᴰ + ⏳ | cover đen riêng (`CompareScreen.swift:300-312`), 3 cột chồng (`CompareLayout.swift:28-39`), không vai Select/Candidate; Viewer cũng luôn tối (`PhotoDetailScreen.swift:203`, `:316`) | chế độ trong Viewer + `CompareSession` (task 2). Nửa "sáng" chờ Viewer sáng/tối của FS-21 (AC-52) — §7 lựa chọn K4; vị trí segmented trên toolbar chờ FS-21 (K5) |
| AC-2 Candidate làm việc, `X` → nhãn `Rejected`, `Delete 1 Photo`; lưới mờ 45 % + cờ | ⚠️ᴰ | dấu là `Set` cục bộ (`CompareScreen.swift:291`), không phím (không `PhotoMarkKeyButtons`), mất khi đóng; lưới mờ 45 % **đã có** cho cờ thật (`PhotoGridCollectionView.swift:2237`, `:2281`) | ghi qua `PhotoMarks.apply` + `PhotoMarkKeyButtons(ids: { [working] })`; hàng Cull dùng chung trên iPhone/Duo. Task 4 |
| AC-3 iPhone vuốt trái trên Candidate → `Candidate 2 of 3`, Select đứng yên | ❌ | một cột cuộn dọc (`CompareScreen.swift:374-406`), không có candidate | bố cục xếp chồng + vuốt (UIKit, `ZoomableImageView.onSwipe` `:60`). Task 11 |
| AC-4 iPhone pinch Select lên 100 % → cả hai 100 %, cùng tâm tỉ lệ, nhãn `100%` | ❌ (đồng bộ có sẵn) | đồng bộ tỉ lệ đã đúng (`CompareScrollSynchronizer.mirror`, `CompareScreen.swift:77-91`, `normalizedOffset` `:117-125`); không có khái niệm 100 % (zoomScale 1 = Fit), không nhãn | `CompareZoom` thuần (100 % = pixel ảnh ÷ (bề rộng Fit × scale màn)). Task 12 |
| AC-5 Make Select → A/B đổi vai, cờ/sao không đổi | ❌ | không có | `CompareSession.makeSelect()`. Task 13 |
| AC-6 Survey 6 (iPad), chạm ô 3 rồi `P` → viền amber, `Picked`; 5 ô kia không đổi | ⚠️ᴰ | chạm = bật/tắt dấu xoá (`CompareScreen.swift:345-352`, `:415`) | chạm = khung làm việc; `P` qua `PhotoMarks`. Task 15 (cần Survey của task 14 — ngoại lệ thứ tự ⚠️ trước ❌) |
| AC-7 Remove from Survey → còn 5 ô, ảnh 3 còn trong thư viện, cờ giữ, tiêu đề `5 Photos` | ❌ | không có | `CompareSession.remove(_:)`. Task 16 |
| AC-8 giữ-lâu khung 2 → Keep Only This → 3 ảnh kia Reject, ảnh 2 không; `Delete 3 Photos` | ⚠️ᴰ | `markAllOthers` đúng nghĩa nhưng trên dấu cục bộ (`CompareScreen.swift:358-363`), menu `:617-630` | chuyển luật vào `CompareSession.keepOnly` (Pick giữ nguyên), ghi cờ thật. Task 5 |
| AC-9 4 ảnh Photos, 2 Reject, Delete → xác nhận → Recently Deleted; còn 2 khung ở 2-Up; dòng cờ bị gỡ | ⚠️ (hỏi Q1) | ở lại khi ≥ 2 **đã có** (`CompareScreen.swift:540-543`); gỡ cờ khi app xoá **đã có** (`AppDependencies.swift:349-352`) — nhưng FS-19.05 §5 + FS-18 07 §2 đổi FS-01.12 AC-9 sang "mồ côi 30 ngày, không gỡ ngay" | xoá qua `RejectedDeleter`, `CompareSession.afterDeletion`. Task 6; câu chữ AC theo Q1 |
| AC-10 3 ảnh, 2 Reject, xoá → còn 1 → Viewer Single trên ảnh đó | ⚠️ᴰ | còn < 2 thì **đóng** (`CompareScreen.swift:543`), Duplicates thì đóng luôn (`:523`) | `afterDeletion` → `.single(id)`; Viewer nhảy tới index của ảnh trong nguồn. Task 8 |
| AC-11 3 ảnh, 1 Reject, Delete → Cancel hệ thống → 0 cảnh báo, 3 khung, cờ còn | ✅ (cơ chế) | huỷ = `PHPhotosError.userCancelled` → `.cancelled`, không banner (`RejectedDeleter.swift:24-25`; test `RejectedDeletionCancelTests.cancelChangesNothing`); Compare cũ nuốt huỷ (`CompareScreen.swift:544-546`), Duplicates trả `false` (`DuplicatesModel.swift:668-669`) | test khoá ở tầng `CompareModel` (dựng ở task 2) với bộ xoá giả. Task 3 |
| AC-12 Mac, thư mục `2026 Japan`, 1 Reject → *Move 1 Photo to the Trash?* → file + `.xmp` vào Thùng rác | ❌ ⏳ | không có nguồn thư mục, không target Mac | chờ FS-19 (nguồn, bộ định tuyến xoá) + FS-18 (target Mac). Task 21 |
| AC-13 NAS, 1 Reject → *Hide 1 Photo?* → ẩn; file NAS cùng SHA-256 | ❌ ⏳ | không có nguồn NAS được index | chờ FS-19 (Hide + bảng ẩn). Task 22 |
| AC-14 Duo trong Survey 6, ô 4 làm việc → gập → Duo ngoài xếp chồng, Select = ảnh 4, mọi control x ≤ 366 | ❌ (+ ❓ đo tay) | không có Survey, không xếp chồng; `simctl` không gập (memory `iphone-duo-ios27`) | `CompareSession.fold(to:)` (thuần) + `CompareLayout.stacked(cover)`. Task 19; gập bằng tay trong Simulator.app |
| AC-15 Duplicates nhóm 2, ảnh 1 Reject → Reject ảnh 2 → không đổi, rung + *Keep at least one…* | ❌ | cổng chỉ có ở lưới Duplicates (`DuplicatesModel.swift:457-480`); Compare mở từ đó **bỏ qua** cổng (`CompareScreen.swift:345-352`) — trái cả 08 §2 lẫn FS-06.06b §1 | cổng thuần trên vị từ "bị đánh dấu" (K2). Task 17 |
| AC-16 iPad/Mac 2-Up: 0 nút *Sync Zoom and Pan*; pinch Select → cả hai 100 % | ✅ (iPad, phần đồng bộ) | không có công tắc nào trên UI; `mirror` chép zoom + offset sang mọi khung (`CompareScreen.swift:77-91`) | test khoá `CompareScrollSynchronizer` (UIScrollView thật, `@MainActor`). Task 1 — viết ngay trên code hôm nay. Phần "100 %" theo task 12; phần Mac ⏳ FS-18 |
| AC-17 Duplicates nhóm 3 → Compare → Reject ảnh 2 → đóng cả hai → lưới mờ 45 %, bộ lọc Rejected có nó | ⚠️ᴰ | Compare từ Duplicates ghi `session.marks` trong bộ nhớ (`DuplicatesScreen.swift:140-144`, `DuplicateReviewSession.swift`), không phải cờ | ghi cờ thật; Duplicates đọc cờ theo K2. Task 9 |
| AC-18 Mac Survey 6, 2 Reject: `Delete 2 Photos` trước Edit; `⌘⌫`; Keep Only This ở menu chuột phải + menu Photo | ❌ ⏳ | không có target Mac | chờ FS-18. Task 23 |
| AC-19 iPad 2-Up: segmented cờ cao 44 ±1 | ❌ | khung không có control nào (`CompareScreen.swift:568-658`) | `PhotoFlagSegmented` (None · Pick · Reject, 44) + 5 sao. Task 18 |
| AC-20 iPhone 2-Up 100 %: một ngón kéo cả hai khung, vẫn `Candidate 1 of 3`; về Fit rồi vuốt → `2 of 3` | ⚠️ᴰ | hai ngón mới kéo ảnh (`CompareScreen.swift:681`, `ZoomableImageView.swift:53`) — luật 08 §5 cũ; gói 6 điểm của D15 đổi sang một ngón | một ngón kéo khi > Fit, vuốt đổi candidate chỉ ở Fit (như pager Viewer). Task 10 |
| AC-21 iPad Compare 12 → Survey: ô 216×144, cuộn tới đủ 12 | ❌ | toán cột cũ (≥ 330, ≤ 3 cột) không có ô cỡ tối thiểu | `CompareLayout.survey(count:area:class:)`. Task 14 |
| AC-22 3 ảnh, 0 Reject → **Delete** mờ, bấm không mở hộp | ⚠️ᴰ | 0 dấu → dòng chữ gợi ý thay cho nút (`CompareScreen.swift:442-447`, `:457-473`) | nút luôn có, `.disabled` + chữ "Delete" (DESIGN "làm mờ, không ẩn"). Task 7 |
| AC-23 Mac, 1 ảnh Photos + 1 ảnh thư mục, cả hai Reject → một hộp liệt kê 2 đích | ❌ ⏳ (+ hỏi Q2, Q3) | không có | chờ FS-19 + FS-18. Task 24 |
| AC-24 iPad, ổ ngoài không Thùng rác, 1 Reject → hộp đỏ thứ hai → Delete Permanently | ❌ ⏳ | không có nguồn thư mục | chờ FS-19 (hộp đỏ thứ hai dùng chung với Cull). Task 25 |
| AC-25 `DSC04513.ARW` thư mục: Reject → thoát → mở lại → `.xmp` sao −1, vẫn Rejected | ❌ ⏳ | không có sidecar writer | chờ FS-19 (ghi `.xmp`); Compare chỉ đi qua `PhotoMarks` nên tự được. Task 26 |
| AC-26 Viewer từ ô 5 (không chọn) → 2-Up → Select 5, Candidate 6, `Candidate 1 of 1` | ❌ | Viewer không có control chế độ nào (`PhotoDetailScreen.swift:268-294`); chọn 1 ảnh thì Compare đã mờ (`SelectionBarViews.swift:190`) | `CompareSession.start(viewing:next:)` từ `PhotoBrowsingSource.photoId(at: i+1)` chỉ ở màn rộng; iPhone/Duo ngoài chỉ vào từ chọn ≥ 2 (mac-ipad-v2 Q4). Task 20 |

**Tổng: 2 ✅ (AC-11, AC-16) · 9 ⚠️ (AC-1, 2, 6, 8, 9, 10, 17, 20, 22 — 8 là ⚠️ᴰ đã chốt, 1 cần hỏi: AC-9) · 15 ❌
(trong đó 8 chờ plan khác: AC-12, 13, 18, 23, 24, 25 hoàn toàn; AC-1, AC-16 một phần) · 0 ❓ đứng riêng; ❓ đi kèm
AC-14 (gập không lái được bằng sim). AC-26 đã chốt (planboard mac-ipad-v2 Q4: iPhone/Duo ngoài chỉ vào từ chọn ≥ 2).**
