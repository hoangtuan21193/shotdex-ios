# FS-01.12b — Lượt lọc ảnh (Cull) và Delete Rejected

`FS-01.12b` · tier D · màn mới trong `Features/Library/` · dữ liệu và phím chung với [FS-01.12](12-rating-and-flags.md)
· nguồn intent [user-wishes-research](../../_intents/2026-09-30-user-wishes-research.md) mục 9 · cập nhật 2026-10-02

**Một câu:** đi qua cả buổi chụp từng tấm một, mỗi tấm một chạm, một phím hoặc một cú vuốt để giữ hay bỏ, rồi
đưa mọi tấm Rejected vào Recently Deleted bằng một lần xác nhận của hệ thống.

## 1. Người dùng cần gì

Buổi chụp 300–800 khung. Lượt 1 trả lời giữ hay bỏ, mỗi tấm dưới một giây. Lượt 2 chấm sao cho tấm giữ. Cuối
cùng dọn tấm bỏ. Compare thì so cạnh nhau theo nhóm. Màn này thì đi tuần tự từng tấm, tay không rời một chỗ.

## 2. Màn hình

Màn tier D mới, chạy trên một tập ảnh. Màn chỉ đọc và ghi sao, cờ, **không** có nút lưu: mỗi lần đặt là ghi
ngay, theo luật lưu của [FS-01.12 §4–5](12-rating-and-flags.md).

- **Tập ảnh** xếp theo ngày chụp, cũ trước, vì buổi chụp được xem theo đúng thứ tự nó diễn ra. Mở ra ở **ảnh đầu
  tiên chưa có cờ**; mọi ảnh đã có cờ thì mở ở ảnh đầu.
- Lối vào: §5. Không giới hạn số ảnh. Ảnh tải theo trang: trang hiện tại + 2 trang mỗi bên, cỡ màn, cho phép
  mạng — khác pager của viewer (±1, không mạng, [FS-02.01](../FS-02-photo-detail/01-pager-and-image-loading.md)),
  vì lượt lọc cần tấm sau sẵn ngay.
  **Không tải bản gốc.**
- Video có trong tập: hiện khung đại diện + nút play, tắt tiếng mặc định như Compare ([FS-01.08 §6](08-compare.md)).
- Ảnh chỉ có trên iCloud mà máy mất mạng: hiện bản có trên máy kèm glyph mây. Sao và cờ vẫn ghi được.
- Vuốt ngang = ảnh trước/sau. Pinch hoặc chạm đôi = phóng. Đang phóng thì kéo là kéo ảnh, không đặt cờ. Vuốt
  dọc: lên = Pick, xuống = Reject (§5). Cú vuốt bắt đầu trong vùng ảnh, nên không đụng mép home của hệ thống.
- Phím: các phím đặt sao và cờ của [FS-01.12 §6](12-rating-and-flags.md), cộng ←/→ ảnh trước/sau · `Z` phóng
  100%/vừa màn · ⌘Z undo · Esc đóng.
- **Undo** (nút + ⌘Z) lùi từng thao tác trong lượt, quay về đúng ảnh đã đổi. Đóng màn là hết lượt và hết undo.
- Đặt cờ ở **ảnh cuối** → thẻ tóm tắt: "240 photos · 52 picks · 120 rejected · 68 unflagged". Thẻ có ba nút:
  **Delete 120 Rejected…** (đỏ), **Review Unflagged** (mở lại lượt chỉ với ảnh chưa cờ), **Done**.
- Mỗi lần đặt cờ có rung nhẹ.
- **VoiceOver:** ảnh đọc "Photo 37 of 240, 3 stars, Picked". Vuốt lên/xuống chỉnh sao. Pick, Reject, Clear Flag
  là action.

## 3. Delete Rejected

- Dùng lệnh xoá của hệ thống. Hộp thoại "Delete 120 Photos?" của hệ thống **là** bước xác nhận
  ([FS-02.04 §1](../FS-02-photo-detail/04-actions-and-extras.md)). App không dựng hộp thoại riêng.
- Phạm vi là **ảnh Rejected trong tập đang xem**: tập của lượt lọc, hoặc đúng các ảnh lưới đang hiện. Không bao
  giờ là Rejected ở chỗ khác — cùng luật "Delete không đụng ảnh không nhìn thấy" của [FS-01.06](06-multi-select.md).
- Quyền `.limited`: chỉ xoá ảnh thấy được — tập đang xem vốn chỉ có ảnh thấy được.
- Ảnh chỉ có trên iCloud: xoá **không cần tải** về.
- Xong: gỡ dòng cờ của ảnh đã xoá. Banner "120 photos moved to Recently Deleted. Recover them in Photos within
  30 days." Không có Undo, vì app không đọc được Recently Deleted.
- Huỷ ở hộp thoại hoặc lệnh xoá lỗi: PhotoKit làm cả mẻ hoặc không làm gì, nên không đổi gì và cờ giữ nguyên. Lỗi
  thì có thông báo + **Try Again** ([NF-04](../../04-non-functional-design/NF-04-empty-and-error-states.md)).

## 4. Thiết bị và iOS

- Cùng chức năng trên iPhone 402×874, iPad 1376×1032, Duo trong 951×669, Duo ngoài 466×678.
- Mọi control nằm trong vùng an toàn, kích thước ≥ 44×44. Trên Duo ngoài, mọi control nằm ngoài rail 84pt bên phải.
- Tier D nên không rẽ nhánh theo iOS 26. Lối vào (menu) giống nhau ở cả hai nhánh.

**Design canvas:** màn **mới**, chưa có board. Phải thêm board iPhone · iPad · Duo trong · Duo ngoài vào hàng
thiết bị tương ứng của canvas [ShotDex Photo Editor](https://claude.ai/artifact/T4tEUQrJtxBbi48HokiL9F)
**trước** khi code, theo bố cục §5; viên Delete trên thanh điều kiện vẽ cùng hàng đó.

## 5. Bố cục, lối vào và thao tác

Chốt 2026-10-02.

- **Bố cục kiểu Lightroom mobile, nền đen**, từ trên xuống:
  - **Thanh trên 52pt:** ✕ 44pt trái · giữa "37 / 240" (số đơn cách) và dòng phụ "52 picks · 120 rejected" ·
    Undo 44pt phải.
  - **Ảnh** chiếm phần giữa.
  - **Hàng điều khiển 60pt:** `[Reject 44] 16 [★×5, ô chạm 44, glyph 22] 16 [Pick 44]` = 340pt, căn giữa.
  - **Filmstrip 56pt:** ô vuông 44pt, không bo; ô hiện tại viền trắng 2pt; glyph cờ/sao nhỏ trên ô.
- **Theo máy:**

| Máy | Khác iPhone 402×874 ở chỗ |
|---|---|
| iPad 1376×1032 | filmstrip 72pt (ô 60pt); thêm một dòng EXIF dưới thanh trên |
| Duo trong 951×669 | ảnh cao ~500pt; còn lại như iPhone |
| Duo ngoài 466×678 | hàng 340pt nằm trong 382pt khả dụng, ngoài rail 84pt bên phải |

- **Lối vào, hai đường:**
  - chế độ chọn → ⋯ → **Cull N Photos** (icon `flag.2.crossed`), ngay sau Combine Photos
    ([FS-01.06 §3](06-multi-select.md)). Tập ảnh là các ảnh đang chọn;
  - viewer ⋯ → **Cull From Here**: tập ảnh là cả danh sách lưới mà viewer đang duyệt, mở ở ảnh đang xem.
- **Delete Rejected ngoài lượt lọc:** khi bộ lọc Rejected đang bật, thanh điều kiện có viên đỏ **Delete 120**
  cao 32pt, ghim mép phải, cạnh Clear ([FS-01.05 §6](05-filtering-and-sorting.md)). Trong lượt lọc thì dùng
  thẻ tóm tắt (§2). Cả hai đi qua đúng luật §3.
- **Vuốt dọc:** lên = Pick, xuống = Reject. Đóng màn chỉ bằng ✕ hoặc Esc — khác viewer, nơi vuốt xuống là đóng.
- **Tự sang ảnh sau:** đặt **cờ** thì sang ảnh sau; đặt **sao** thì đứng lại. *Vì lượt 1 là P/X qua cả buổi,
  lượt 2 chấm sao cho tấm giữ.* Đặt cờ ở ảnh cuối thì mở thẻ tóm tắt thay vì sang ảnh sau.

## 6. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | màn Cull 240 ảnh đang ở ảnh 37, chưa cờ | bấm `P`, rồi `3`, rồi ⌘Z hai lần | `P`: 37 Picked, màn sang 38, bộ đếm "38 / 240"; `3`: 38 có 3 sao, vẫn ở 38; ⌘Z lần 1: 38 về 0 sao; ⌘Z lần 2: 37 bỏ cờ, màn về 37 | ✅ `CullSessionTests.pickAdvancesStarStaysUndoReturns` (đúng chuỗi AC trên 240 ảnh), `.flagOnTheLastPhotoOpensTheSummary`, `.keysCoverMarksAndZoomWithoutClashing`; phím thật qua `ShotDexUITests/scripts/cull-keys.json` (iPhone 17 26.5: "4 / 5" → `P` → "5 / 5", 3 picks → `3` → vẫn "5 / 5" → ⌘Z, ⌘Z → "4 / 5", 2 picks; Esc đóng). ⚠️ rung nhẹ chỉ thấy trên máy thật |
| AC-2 | màn Cull trên iPhone, ảnh 10 chưa cờ, mức phóng 1× | vuốt lên; rồi ở ảnh 11 phóng 2× và vuốt xuống | ảnh 10 Picked và màn sang 11; ở 2× cú vuốt kéo ảnh, 11 vẫn không cờ | ✅ `CullGesturePolicyTests` (1×: lên Pick, xuống Reject, ngang lật trang; 2×: không gì), `ShotDexUITests/scripts/cull-swipe.json` (iPhone 17 26.5, ảnh 2 và 3 thay cho 10 và 11: vuốt lên ở 1× → ảnh 2 Picked, sang "3 / 5"; chạm đôi phóng 2,5× rồi vuốt xuống → ảnh bị kéo, ảnh 3 vẫn không cờ, vẫn "3 / 5") |
| AC-3 | chọn 240 ảnh, 36 ảnh chụp sớm nhất đã có cờ | mở lượt lọc | màn đứng ở ảnh thứ 37 theo ngày chụp, bộ đếm "37 / 240" | ✅ `CullSessionTests.startsAtFirstUnflaggedByCaptureDate` (240 xáo trộn, 36 sớm nhất có cờ → p036, "37 / 240"), `.nilDatesLast`, `.cullFromHereOpensOnThatPhoto`; `ShotDexUITests/scripts/cull-open.json` (iPhone 17 26.5: chọn 5 → ⋯ **Cull 5 Photos** → mở ở "4 / 5", ảnh chưa cờ đầu tiên; so board `PH23`: ✕/Undo lệch y+8 = vùng an toàn thật của iPhone 17 (62pt) so với 54pt của board, hàng điều khiển và filmstrip khớp ≤ 2pt) |
| AC-4 | màn Cull 240 ảnh: 52 Picked, 119 Rejected, đang ở ảnh 240 chưa cờ | bấm `X` | thẻ tóm tắt hiện "240 photos · 52 picks · 120 rejected · 68 unflagged" với Delete 120 Rejected…, Review Unflagged, Done | ✅ `CullSummaryTests.counts` (52 / 119 + `X` trên ảnh cuối → thẻ, "240 photos · 52 picks · 120 rejected · 68 unflagged", "Delete 120 Rejected…"), `.reviewUnflaggedSubset`; `ShotDexUITests/scripts/cull-summary.json` (iPhone 17 26.5: Pick rồi Reject ở ảnh cuối → thẻ "End of Set"). Hàng không có gì để làm thì ẩn (0 Rejected → không Delete, 0 unflagged → không Review) thay vì hiện nút chết |
| AC-5 | mở màn Cull trên iPhone 17, iPad 13", Duo trong, Duo ngoài | chụp ảnh màn và dump phần tử | 5 sao, Pick, Reject, Undo, X, bộ đếm đều có trên 4 máy, mỗi cái ≥ 44×44, nằm trong vùng an toàn; trên Duo ngoài không cái nào có x > 382pt | ⚠️ chưa có — `Tools/ui-drive` + `Tools/sim-shot` |
| AC-6 | album X có 240 ảnh, 120 Rejected; ngoài X còn 30 ảnh Rejected | bật lọc Rejected trong X, bấm viên **Delete 120** trên thanh điều kiện, xác nhận ở hộp thoại hệ thống | lệnh xoá mang đúng 120 id của X; 30 ảnh kia vẫn Rejected; 120 dòng cờ bị gỡ; banner nói Recently Deleted 30 ngày, không có Undo | ✅ `RejectedDeletionTests.onlyVisibleRejected` (240 / 120 trong X → đúng 120 id, 30 ngoài X không đụng), `.deletedRejectedRowsGone` (1 lệnh xoá 120 id, 120 dòng cờ gỡ, 30 còn Rejected, banner "120 photos moved to Recently Deleted. Recover them in Photos within 30 days." không Undo); `ShotDexUITests/scripts/rejected-delete-pill.json` (iPhone 17 26.5: Rejected bật → viên đỏ **Delete 1** cạnh Clear, chip không bị đẩy ra; chạm → hộp thoại hệ thống "Allow “ShotDex” to delete this photo?" đúng 1 ảnh). So board `PH26`: viên cao 32 trong vùng chạm 44, mép phải 382 so với 386 (lề chrome của app), y +8 do vùng an toàn thật. ⚠️ album X 240 ảnh trên sim chưa dựng |
| AC-7 | như AC-6 | bấm Cancel ở hộp thoại hệ thống | 0 ảnh mất, 120 ảnh vẫn Rejected | ⚠️ chưa có |
| AC-8 | màn Cull 50 ảnh chỉ có trên iCloud, máy mất mạng | đi qua cả 50, đặt cờ mỗi ảnh | mỗi ảnh hiện bản có trên máy kèm glyph mây; 50 cờ được ghi; 0 yêu cầu bản gốc | ✅ phần sim: `CullImagePolicyTests.neverRequestsOriginal` (cỡ màn, trần 2.800 px, không bao giờ `PHImageManagerMaximumSize`), `.warmsTwoPagesEachSide`; màn không có đường tải bản gốc (chỉ `probe`, không `fetch`); `ShotDexUITests/scripts/cull-icloud.json` với `-ShotDexFakeICloud cloud=all,stall`: bản có trên máy + glyph mây, `X` ghi cờ, ⌘Z gỡ. ⚠️ 50 ảnh chỉ iCloud + mất mạng thật → máy thật |

**Chưa chứng minh được:** AC-1 → AC-8 (màn chưa có code).

## 7. Rủi ro

| Rủi ro | Xử lý |
|---|---|
| iOS 27: mỗi phím trong lượt lọc là một lần ghi Photos, 800 lần trong 10 phút | thay đổi thư viện đã gộp 1 s và chỉ là thay đổi nội dung nên lưới không nạp lại; đo nhiệt và pin trên máy với 800 ảnh trước `/plan` |
| Vuốt lên = Pick trùng thói quen "vuốt lên mở Info" của viewer | màn này không có Info, nên vuốt lên chỉ mang một nghĩa; thanh trên ghi rõ màn đang là Cull |
