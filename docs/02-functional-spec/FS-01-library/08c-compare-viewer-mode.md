# FS-01.08c — Compare là một chế độ của Viewer (mọi thiết bị)

`FS-01.08c` · tier B (theo sáng/tối như Viewer, **không** tầng D) · `Features/Library/Compare/` · `Domain/Compare/`
· test `CompareLayoutTests`, `CompareSessionTests`, `CompareModelTests` · cập nhật 2026-10-12 · nguồn: D15 ([DECISIONS](../../../.planboard/macos-app/DECISIONS.md)),
intent [iPad](../../_intents/2026-10-04-ipad-mac-style.md) · board `MAC_Compare(Survey)`, `IP_Compare(Survey)`,
`PH_Compare`, `DI_Compare(Survey)`, `DC_Compare`

> **Thay thế trong [08](08-compare.md):** §1 (chạm = đánh dấu xoá) · §2 dấu riêng của Duplicates (mất khi rời nhóm) ·
> §3 (một cách nhìn tự co, số cột 330pt, chồng theo cột) · §4 phần chạm-để-đánh-dấu, vòng tròn rỗng, góc trên-phải ·
> §7 câu "dấu bỏ đi khi đóng". **Giữ nguyên:** §2 cổng Duplicates, §4 xác nhận/huỷ/hỏng, §5 đồng bộ, §6 video và bản cao.

**Một câu:** trong Viewer, đổi Single → **2-Up** (Select cạnh Candidate) hoặc **Survey** (mọi ảnh cùng lúc), cùng mức
phóng, cắm Pick/Reject từng ảnh; **Reject = đánh dấu xoá**, và một nút **Delete N** xoá các ảnh Reject theo nguồn.

## 1. Quy tắc

- Compare **là Viewer**: cùng nền, cùng sáng/tối, cùng thanh và nút Close/Back. Không còn màn đen riêng (DESIGN.md §2).
- Cờ là cờ của [FS-01.12](12-rating-and-flags.md): đặt ở đây thì lưới, Cull, bộ lọc Rejected thấy ngay, và **còn sau khi đóng**.
- **Chạm ảnh = chọn khung làm khung đang làm việc** (viền amber), không đổi cờ. Phím `0–5 P X U` áp cho khung đó.
- Phóng và kéo **luôn đồng bộ** giữa các khung (08 §5) trên mọi máy; không có nút bật/tắt đồng bộ.
- Khung cao theo đúng tỉ lệ ảnh; không cắt về chiều cao chung.

## 2. Chế độ theo máy

| Máy | Segmented | 2-Up | Survey |
|---|---|---|---|
| Mac 1440×900 | Single · 2-Up · Survey (toolbar) | hai khung 700×740 cạnh nhau | lưới 3 cột, ô 456×304 |
| iPad 1376×1032 | như Mac | hai khung 664×832 | lưới 3 cột, ô 432×288 |
| Duo trong 951×669 | như Mac (góc trên-phải) | hai khung 451×453 | lưới 3 cột, ô 264×176, sao 32pt |
| iPhone 402×874 | **Single · Compare** | **xếp chồng**: Select trên, Candidate dưới, khung 370×294 | không có |
| Duo ngoài 466×678 | Single · Compare | xếp chồng, khung 350×224, mọi thứ trong x ≤ 366 (rail 84pt) | không có |

- Mỗi khung: ảnh, tên + một dòng EXIF, sao và cờ. iPad/Mac: 5 sao + segmented **None · Pick · Reject** (iPad cao 44pt).
  iPhone/Duo: hàng Cull 340pt `[Reject 44] [★×5] [Pick 44]` như [12b §5](12b-culling-pass.md).
- Mac/iPad có filmstrip dưới đáy (100pt iPad, 88pt Mac): ảnh trong phép so có viền amber, ảnh Reject mờ.
- Gập Duo: 2-Up → Compare xếp chồng; Survey → Compare xếp chồng với **khung đang làm việc làm Select**.
- iPhone và Duo ngoài: segmented **Single · Compare** chỉ có trong Viewer đã mở bằng Compare (§7); Viewer mở từ một ảnh
  **không** có lối vào Compare — không segmented, không dòng trong ⋯ (planboard mac-ipad-v2 Q4).

## 3. 2-Up

- Khung trái/trên là **Select** (nhãn amber), khung kia là **Candidate** (nhãn `Candidate 1 of 3`).
- Sang candidate kế: vuốt ngang trên khung Candidate (cảm ứng), `←`/`→` (bàn phím); Select đứng yên.
- **Make Select** (toolbar iPad/Mac, phím `↑`; thanh dưới iPhone/Duo) đổi chỗ: Candidate thành Select.
- Zoom: popup **Fit · 100%**; phím `Z` đổi Fit ↔ 100%. Mỗi khung có nhãn `100%` (iPhone/Duo kèm glyph liên kết).
- iPhone/Duo đang phóng: **một ngón kéo ảnh** (cả hai khung theo); vuốt ngang chỉ đổi candidate khi khung ở Fit —
  như pager của Viewer.

## 4. Survey

- Mọi ảnh của phép so cùng lúc, vừa khung (không phóng ở Duo; iPad/Mac có popup Fit). Chạm = khung làm việc.
- Khung đang làm việc có **Remove from Survey** (✕/⊖ 44pt; Mac phím `⌫`) — rút khỏi phép so, không đổi cờ.
- Ảnh Reject trong Survey mờ còn 45% (như ô lưới, 12 §7) và có nhãn đỏ **Rejected**.
- **Hơn 6 ảnh:** ô thu lại cho cả phép so vừa màn, tới cỡ tối thiểu = ½ ô của Survey 6 ảnh (Mac 228×152,
  iPad 216×144, Duo trong 132×88); quá cỡ đó thì giữ cỡ tối thiểu và lưới cuộn dọc.

## 5. Reject và Delete N

- Reject = đánh dấu xoá: nhãn đỏ `× Rejected` trên khung, VoiceOver *"Rejected, marked for deletion"*.
- **Delete N Photos**: đỏ chữ, **không nổi bật** (kính hoặc viền, không nền đỏ). iPad/Mac: toolbar trước Edit; iPhone/Duo:
  góc dưới-phải, chỗ Viewer để Delete. Chỉ xoá ảnh Reject **trong phép so này** (luật 12b §3).
- Chữ trên nút theo đích, như Cull ở mọi thiết bị (FS-18 01b §1): chỉ ảnh Photos hoặc chỉ thư mục không có Thùng rác →
  **Delete N Photos**; có file đi Thùng rác (kể cả khi trộn) → **Move N Photos…**; chỉ ảnh NAS → **Hide N Photos**.
  Menu và `⌘⌫` cùng chữ với nút.
- 0 ảnh Reject: nút hiện **mờ**, chữ **Delete**, không bấm được — làm mờ, không ẩn (DESIGN.md).
- Mac: `⌘⌫` = nút xoá; **Keep Only This** có ở menu chuột phải của khung và menu **Photo**.
- Có ≥ 1 Reject (iPhone/Duo): dòng *"Touch and hold to keep only this one"* ngay trên nút Delete.
- Giữ-lâu một khung: **Make Select** · Share (iPhone/Duo) · **Remove from Comparison** · **Keep Only This** (đỏ) —
  Reject mọi ảnh *khác* trong phép so, bỏ Reject của chính nó (Pick giữ nguyên).

## 6. Xoá theo nguồn

| Nguồn của ảnh | Xác nhận | Đi đâu |
|---|---|---|
| Photos | hộp thoại hệ thống *"Delete 2 Photos?"* là bước xác nhận (FS-02.04 §3) | Recently Deleted, 30 ngày |
| Thư mục cục bộ (Mac) | hộp của app *"Move 2 Photos to the Trash?"* | Thùng rác; `.xmp` đi cùng file |
| Thư mục không có Thùng rác (iPad, iPhone, Duo) | hộp của app, rồi **hộp đỏ thứ hai** *"Delete 2 Photos Permanently?"* | xoá hẳn file và `.xmp` |
| Server/NAS (FS-19) | hộp của app *"Hide 2 Photos? They stay on “NAS Home”."* | ẩn trong ShotDex, file không đổi (D6) |

- Xoá xong: khung đã xoá rời phép so; còn ≥ 2 → ở lại chế độ đang dùng; còn 1 → **Single** trên ảnh đó; 0 → lưới.
- Huỷ ở hộp nào cũng không đổi gì (trừ trộn nguồn, dưới), cờ giữ nguyên. Hỏng → *"Couldn't Update Photos"* + lý do + OK, cờ giữ nguyên (08 §4).
- **Trộn nguồn:** một hộp của app liệt kê từng đích (*"2 from Photos · 1 to the Trash · 1 hidden on “NAS Home”"*);
  xác nhận → phần Photos vẫn qua hộp hệ thống; huỷ ở đó chỉ giữ lại phần Photos, phần khác đã chạy.
- Cờ của ảnh thư mục/NAS nằm ở **bảng Cờ chung** (FS-19); Reject còn ghi vào `.xmp` thành sao −1 (Pick: trường riêng ShotDex).

## 7. Lối vào và thoát

- Chế độ chọn → **Compare** (≥ 2 mục, không trần trên): ảnh chọn đầu là Select, thứ tự = thứ tự chọn; mở ở 2-Up
  (iPhone/Duo ngoài: Compare).
- Từ Duplicates: như 08 §2, giữ cổng *"Keep at least one photo in this group."* trên nút Reject của ảnh cuối.
- Reject trong Compare mở từ Duplicates ghi **cờ thật** của FS-01.12 — còn sau khi rời nhóm, lưới và bộ lọc Rejected thấy.
- **Màn rộng** (iPad, Duo trong, Mac): Viewer mở từ một ảnh (không chọn) rồi bấm 2-Up: Select = ảnh đang xem,
  **Candidate = ảnh kế trong lưới**.
- **iPhone và Duo ngoài:** so sánh **chỉ** bắt đầu từ chế độ chọn với ≥ 2 ảnh — chọn 1 ảnh thì nút Compare mờ; không có
  "Compare with Next" trong ⋯, không nút trên Viewer Single (planboard mac-ipad-v2 Q4). Gập Duo giữa phiên so (§2) không
  phải lối vào — phiên đang mở đi tiếp ở màn ngoài.
- Close (iPhone/Duo), Back hoặc `Esc` (iPad/Mac) về lưới. Cờ đã đặt **ở lại** — khác 08 §7.

## 8. Ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Bộ nhớ | luật bản cao 08 §6 giữ nguyên: ≤ 2 bản cạnh dài ≤ 3000px, nhả khi về Fit ([NF-02](../../04-non-functional-design/NF-02-memory-and-resources.md)) |
| Dữ liệu | cờ ở bảng cờ của FS-01.12, không cột mới trong `photo_metadata` ([BD-02](../../01-basic-design/BD-02-database-design.md)); ảnh NAS bị ẩn: bảng riêng (FS-19) |
| iOS 26 vs trước | cùng nút, cùng chữ ở hai nhánh, theo đúng chrome của Viewer ở mỗi nhánh |
| Truy cập | khung đọc *"Photo, DSC04513.ARW, No rating, Rejected, marked for deletion"*; sao và cờ là control riêng có nhãn |
| Tài liệu khác phải sửa | FS-01.12 §3 dòng "Cờ trong Compare — cố ý không có" · FS-06.06b §1 "nút thùng rác của pane" · 08 §2 dấu Duplicates · DESIGN.md §9 trạng thái phá huỷ của card Compare · board iPad/Mac bỏ *Sync Zoom and Pan* · `MAC_Compare(Survey)` thêm Delete N |

## 9. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | iPad 1376×1032, chế độ chọn có 4 ảnh, máy ở chế độ sáng rồi tối | bấm Compare | 2-Up: Select = ảnh chọn đầu, `Candidate 1 of 3`; nền và chữ giống Viewer Single ở cùng chế độ (ảnh chụp cả sáng và tối), không nền đen tầng D | ⚠️ một nửa: iPad dọc 2-Up đúng vai (route `cmp-ipad`); Viewer còn luôn tối → nửa sáng chờ FS-21 AC-52 |
| AC-2 | như AC-1, khung Candidate đang làm việc | bấm `X` | Candidate có nhãn `Rejected`; toolbar có **Delete 1 Photo**; lưới sau khi đóng: ô đó mờ 45% và có cờ Reject | `CompareModelTests.xOnTheWorkingFrameRejectsItForReal`; route iPhone: Reject → nhãn `Rejected`, `Delete 1 Photo` |
| AC-3 | iPhone 402×874, Compare 4 ảnh, Candidate 1 of 3 | vuốt trái trên khung Candidate | khung dưới thành `Candidate 2 of 3`; khung Select không đổi ảnh | `CompareSessionTests.swipeMovesOnlyTheCandidate`; route `cmp-iphone`: vuốt → `Candidate 2 of 3` |
| AC-4 | iPhone, cả hai khung ở Fit | pinch khung Select lên 100% | cả hai khung 100%, cùng tâm tỉ lệ; nhãn `100%` trên cả hai | `CompareZoomTests.hundredPercentIsOnePixelPerPixel` · ❓ pinch trên sim chưa chụp |
| AC-5 | 2-Up, ảnh A Select, ảnh B Candidate | Make Select | B là Select, A là Candidate; cờ và sao của hai ảnh không đổi | `CompareSessionTests.makeSelectSwapsRolesNotMarks` |
| AC-6 | Survey 6 ảnh (iPad), không cờ | chạm ô 3 rồi bấm `P` | ô 3 viền amber, nhãn `Picked`; 5 ô còn lại không đổi | `CompareSessionTests.tapSetsTheWorkingFrameOnly`; route `cmp-ipad`: chạm ô 3 → viền amber |
| AC-7 | Survey 6 ảnh, ô 3 đang làm việc | Remove from Survey | còn 5 ô; ảnh 3 vẫn trong thư viện, cờ không đổi; tiêu đề `5 Photos` | `CompareSessionTests.removeKeepsTheRestAndTheTitle` |
| AC-8 | Compare 4 ảnh, 0 Reject | giữ-lâu khung 2 → Keep Only This | 3 ảnh khác Reject, ảnh 2 không Reject; `Delete 3 Photos` | `CompareSessionTests.keepOnlyRejectsTheOthersAndKeepsAPick`, `CompareModelTests.keepOnlyGivesDeleteThree` |
| AC-9 | Compare 4 ảnh Photos, 2 Reject | Delete 2 Photos → xác nhận ở hộp hệ thống | 2 ảnh vào Recently Deleted; còn 2 khung ở 2-Up; 0 Reject; dòng cờ của 2 ảnh bị gỡ | `CompareSessionTests.twoLeftStayInTwoUp`, `CompareModelTests.deletedFramesLeaveAndOnlyThisComparisonsRejectsGo` |
| AC-10 | Compare 3 ảnh Photos, 2 Reject | Delete 2 Photos → xác nhận | còn 1 ảnh → Viewer về Single trên ảnh đó | `CompareSessionTests.oneLeftGoesSingleOnIt`; route `cmp-iphone-delete`: xoá 2/3 → Single trên ảnh còn lại |
| AC-11 | Compare 3 ảnh, 1 Reject | Delete → Cancel ở hộp hệ thống | 0 cảnh báo; 3 khung; cờ Reject còn | `CompareModelTests.cancelInTheSystemDialogKeepsFramesAndFlags` |
| AC-12 | Mac, 3 ảnh của nguồn thư mục `2026 Japan`, 1 Reject | Delete → *Move 1 Photo to the Trash?* → Move | file và `.xmp` của nó ở Thùng rác; nguồn còn 2 ảnh trong lưới | ⚠️ chưa có |
| AC-13 | 3 ảnh của nguồn NAS, 1 Reject | Delete → *Hide 1 Photo?* → Hide | ảnh mất khỏi lưới ShotDex; file trên NAS có cùng SHA-256 như trước | ⚠️ chưa có |
| AC-14 | Duo trong, Survey 6 ảnh, ô 4 đang làm việc | gập máy | Duo ngoài mở Compare xếp chồng, Select = ảnh 4; mọi control trong x ≤ 366 | ⚠️ chưa có (không có lệnh gập trên sim) |
| AC-15 | Duplicates nhóm 2 ảnh, ảnh 1 Reject | bấm Reject trên ảnh 2 | ảnh 2 không đổi; rung cảnh báo + *Keep at least one photo in this group.* | `DuplicateKeepGateTests`, `CompareModelTests.theGroupsLastPhotoRefusesReject` |
| AC-16 | iPad và Mac, 2-Up | đọc toolbar; pinch khung Select lên 100% | 0 nút *Sync Zoom and Pan*; cả hai khung 100% | `CompareScrollSynchronizerTests` (không có công tắc trong code) |
| AC-17 | Duplicates nhóm 3 ảnh, mở Compare | Reject ảnh 2 → đóng Compare và Duplicates | lưới: ảnh 2 mờ 45% có cờ Reject; bộ lọc Rejected chứa nó | route `cmp-dup`: Reject trong Compare → đóng → ô Duplicates đã đánh dấu; cờ là `photo_flag` thật (lưới mờ 45 % theo FS-01.12) |
| AC-18 | Mac, Survey 6 ảnh, 2 Reject | đọc toolbar; bấm `⌘⌫`; chuột phải khung 1 | **Delete 2 Photos** ngay trước Edit; `⌘⌫` mở cùng hộp xác nhận; menu chuột phải và menu Photo có **Keep Only This** | ⚠️ chưa có |
| AC-19 | iPad 1376×1032, 2-Up | dump khung segmented cờ | cao 44pt ±1 | ⚠️ chưa có |
| AC-20 | iPhone 402×874, 2-Up 100%, `Candidate 1 of 3` | vuốt trái một ngón trên Candidate | ảnh dịch ở cả hai khung; vẫn `Candidate 1 of 3`; về Fit rồi vuốt → `Candidate 2 of 3` | code: `panRequiresTwoFingers` bỏ, vuốt chỉ ở Fit · ❓ chưa chụp ở 100% |
| AC-21 | iPad, Compare 12 ảnh | mở Survey | ô 216×144; lưới cuộn dọc tới đủ 12 ô | `CompareLayoutTests.twelveOnIPadShrinkTo216x144AndScroll` |
| AC-22 | Compare 3 ảnh, 0 Reject | đọc nút Delete | **Delete** mờ, bấm không mở hộp nào | `CompareModelTests.noRejectsMeansADisabledDelete`; ảnh chụp iPhone/iPad: `Delete` mờ |
| AC-23 | Mac, Compare: 1 ảnh Photos + 1 ảnh thư mục `2026 Japan`, cả hai Reject | Delete 2 Photos → xác nhận → Delete ở hộp hệ thống | 1 hộp của app liệt kê 2 đích; ảnh Photos vào Recently Deleted, file vào Thùng rác | ⚠️ chưa có |
| AC-24 | iPad, nguồn thư mục ổ ngoài, 1 Reject | Delete → xác nhận → hộp đỏ thứ hai | **Delete Permanently** → file và `.xmp` mất khỏi ổ; Cancel ở hộp thứ hai → file còn, cờ còn | ⚠️ chưa có |
| AC-25 | ảnh `DSC04513.ARW` của nguồn thư mục | Reject trong Compare → thoát app → mở lại | `.xmp` cạnh file có sao −1; ảnh vẫn Rejected | ⚠️ chưa có |
| AC-26 | (a) iPad 1376×1032, Viewer mở từ ô 5 của lưới, không chọn · (b) iPhone 402×874 và Duo ngoài, Viewer mở từ ô 5 · (c) iPhone, chế độ chọn | (a) bấm 2-Up · (b) đọc thanh trên và ⋯ · (c) chọn 1 ảnh, rồi chọn thêm 1 → Compare | (a) Select = ảnh 5, Candidate = ảnh 6, `Candidate 1 of 1` · (b) 0 segmented Single · Compare, 0 dòng Compare trong ⋯ · (c) 1 ảnh: Compare mờ; 2 ảnh: Compare mở xếp chồng, Select = ảnh chọn đầu | `CompareSessionTests.fromTheViewerTheCandidateIsTheNextCell`, `ViewerModeTests.compactSingleOffersNoCompare`; route iPad Viewer → 2-Up `Candidate 1 of 1`; dump iPhone Viewer: 0 segmented |

**Chưa chứng minh được:** AC-12, 13, 18, 23, 24, 25 (chờ FS-19/FS-18) · AC-14 (không gập được trên sim; code `CompareSession.fold`) · AC-19 (chưa dump iPad ngang) · nửa sáng AC-1 · AC-4/AC-20 bằng cử chỉ.
