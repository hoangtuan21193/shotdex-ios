# FS-03.09b — Sửa nhiều ảnh và Reference View

`FS-03.09b` · `Features/Editing/EditorSession.swift` · `EditorFilmstrip` · `EditorReferencePane` ·
`EditorPreviewCache` · `EditorPreviewPreloader`
· cập nhật 2026-09-29

**Một câu:** một phiên sửa nhiều ảnh giữ **bản nháp theo từng ảnh**, không giữ pixel — và trên màn rộng có
một khung mẫu ghim cạnh ảnh đang sửa.

Bố cục màn rộng: [FS-03.09](09-wide-screen-and-batch-editing.md).

## 1. Quy tắc

- Phiên giữ **danh sách ảnh + recipe nháp theo id**, **không giữ ảnh đã decode**: editor vẫn mỗi lần một
  ảnh, nhân lên 20 ảnh là 20 bản gốc mở cùng lúc. Preview của cả phiên nằm **trên đĩa**, không nằm trong
  RAM (§2).
- Sync chỉ ghi vào **nháp** — không đụng đĩa, không ghi đè ảnh nguồn.
- **Lưu trong phiên nhiều ảnh KHÔNG đóng editor.**
- Lưu cả mẻ chạy **không dựng giao diện**: một ảnh lỗi không dừng mẻ.
- Pane tham chiếu là thứ **để nhìn**, không phải thứ đang sửa.

## 2. Vào và chuyển ảnh

- Lối vào: chế độ chọn → ⋯ → **Edit**, có ở Library, Album, Smart Album, On This Day. Video bị loại vì
  editor ảnh không mở được.
- Đổi ảnh: chốt crop → lưu nháp → **gửi preview của ảnh cũ vào cache** → đóng ảnh cũ → mở ảnh mới → **áp
  nháp đè lên recipe đọc từ ảnh** (nháp mới hơn) *trước* lần render đầu — áp sau thì recipe đã lưu bị vẽ ra,
  hiện lên, rồi mới bị vẽ đè.
- **Preload cả phiên, cache trên đĩa.** Mở editor nhiều ảnh là một vòng nền đi **hết mọi ảnh**, từ ảnh đang
  hiện ra ngoài (kế · trước · kế+2 · trước−2 …), **mỗi lần một ảnh**: mở session → tải bản gốc (cho phép
  iCloud) → render preview 2400px đã sửa (recipe = nháp của phiên, không có thì recipe đã lưu) và bản chưa
  sửa → ghi HEIC (~1 MB/ảnh; ảnh chưa sửa thì hai bản là **một file**) vào thư mục tạm của phiên
  (`ShotDexPhoto-Previews-*`) → đóng session, trừ hai ảnh kề (giữ trong bộ đệm 3 session). RAM chỉ giữ
  **3 preview đã giải mã** quanh ảnh đang hiện; cảnh báo bộ nhớ xả RAM, giữ file. **Đóng editor là xoá cả
  thư mục.**
  - Chạm một ảnh đã có trong cache: preview hiện **ngay, đậm 100%**, chỉ có pill `PREPARING` ở góc trên trái
    stage trong lúc công cụ còn đang mở. Trước đây mỗi lần chạm filmstrip — kể cả chạm lại ảnh vừa rời —
    đều mở lại bản gốc sau một thẻ "Loading full-quality preview…" và ảnh mờ 35%.
  - Preview chỉ là **kết quả** khi được vẽ đúng recipe ảnh sẽ mở với (so vân tay SHA256 của recipe). Ảnh đã
    sửa khác đi kể từ lúc cache (Sync, Auto Sync, Paste) → preview cũ chỉ là **placeholder mờ** và ảnh render
    lại; ảnh đổi trong thư viện (modificationDate) → bỏ cả mục; ảnh vừa lưu → bỏ mục. Khi trúng và ảnh
    không có layer, editor **dùng luôn preview làm bản settle** (histogram, eyedropper đọc từ nó) và dùng
    bản chưa sửa đã cache làm nền tương tác thay vì render lại.
  - Vòng preload **nhường ảnh đang hiện**: chờ khi editor đang mở một ảnh chưa có cache, đang render, đang
    kéo slider hay đang lưu. Không bị huỷ khi chuyển ảnh — nó chỉ chọn ảnh kế tiếp quanh vị trí mới. Hệ quả
    có chủ ý: lướt filmstrip nhanh hơn tốc độ mở ảnh thì những ảnh bị lướt qua chưa kịp vào cache.
  - Recipe có **layer chữ** (token `{camera}`) hoặc Upright chưa giải: vòng preload chỉ vẽ bản chưa sửa;
    lần mở đầu editor tự vẽ, lúc rời ảnh thì kết quả vào cache. RAW được vẽ **cùng nguồn sửa ống kính** mà
    editor sẽ tự chọn khi mở, để preview và lần settle đầu không lệch nhau một bước chỉnh méo.
- **Filmstrip** dưới canvas ở cả hai layout (124pt/thumbnail 96 trên điện thoại; **72/56** ở màn rộng —
  panel đã tiêu bề rộng, dải không nên tiêu thêm một phần mười chiều cao). Ẩn khi xem tràn viền và khi
  đang vẽ.
- Badge trên thumbnail: viền accent = đang sửa · biểu tượng slider = **có nháp chưa lưu** · dấu tick = đã lưu.
- Thumbnail tải theo thang **local → iCloud**, có placeholder và spinner. Máy bật Optimize Storage (đa số
  thư viện đầy) thì request local-only trả rỗng cho phần lớn khung, và dải ảnh trước đây là một hàng ô xám
  không phân biệt được đang tải hay hỏng.

## 3. Sync

⋯ → **Sync to N Photos**, hai mức:

| Mức | Chép gì |
|---|---|
| **Sync Look** | tone · màu · curve · film look — đúng lát cắt của Copy Edits |
| **Sync Everything** | thêm crop, mask, markup |

Bản đầu bê nguyên recipe, tức dán crop 4:5 và mask khuôn mặt của một tấm chân dung lên 39 tấm phong cảnh —
đúng thứ Copy Edits cố tình từ chối ([FS-03.10](10-copy-paste-edits.md)).

- **Auto Sync**: bật thì mọi thay đổi đã chốt tự rải sang phần còn lại theo mức đang chọn. Hiện dưới dạng
  **toggle sáng trong menu ⋯, không phải chế độ ẩn** — Lightroom giấu nó sau ⌥-click và người dùng bỏng
  tay suốt mười lăm năm; iPad thì không có ⌥-click để lộ ra.
- **Apply Previous**: nhớ ảnh vừa rời, áp recipe của nó lên ảnh hiện tại theo mức đang dùng.
- **Paste Edits thẳng từ lưới**: chọn ảnh → ⋯ → Paste Edits, dán look đang có trong clipboard lên cả loạt
  bằng cùng vòng lặp không giao diện, **không mở editor**. Chỉ hiện khi clipboard có nội dung.

## 4. Lưu

- Lưu một ảnh xong thì **nhảy sang ảnh kế còn nháp** (quét xuôi rồi vòng lại), chỉ đóng khi hết. Bản đầu
  đóng ngay sau mỗi lần lưu nên sync 20 ảnh chỉ lưu được 1, và badge "đã lưu" là code không bao giờ chạy tới.
- **Save All**: sheet lưu có thêm `Save Changes to N Photos` / `Save N Copies` khi phiên có từ 2 ảnh mang
  nháp. Vòng lặp chạy **không dựng editor** — editor tồn tại để nuôi preview tương tác, 40 cái trong một
  vòng lặp là vẽ ảnh không ai nhìn.
- Một ảnh lỗi thì **gom lại, báo cuối**, và ảnh đó **giữ nháp** để thử lại.
- Token `{camera}` trong markup giãn **theo từng ảnh**, không phải một lần cho cả mẻ.
- Tiến trình là **modal giữa màn có scrim**.

## 5. Reference View

Chỉ ở layout rộng. Giữ một thumbnail trong filmstrip → **Use as Reference** → khung đó ghim cạnh canvas,
ảnh đang sửa ở phần còn lại.

**Đây là lý do màn to tồn tại**: việc thật của một phiên sửa nhiều ảnh là kéo 40 khung về giống một khung
mẫu, mà "làm giống tấm kia" thì không thể làm khi chỉ thấy một tấm.

- Cũng có hàng **Use as Reference / Clear Reference** trong menu ⋯ khi phiên nhiều ảnh — không chỉ trong
  menu ngữ cảnh trên thumbnail 56pt. Ghim bị **xoá khi cửa sổ hẹp lại**, nếu không badge sẽ còn lại mà
  không gì xoá được.
- **Hướng chia canvas do hình học quyết định, không cố định** (thuần, 7 test): so diện tích ảnh thật sự
  phủ được khi chia dọc và khi chia ngang, chọn cái lớn hơn.
  - Ảnh ngang trong canvas cao thì **xếp chồng** — chia dọc là cắt đúng chiều mà ảnh đang cần.
  - Ảnh dọc trong canvas rộng thì **cạnh nhau**. Hoà thì ưu tiên cạnh nhau (mắt đi theo một đường ngang dễ
    hơn cắt ngang).
  - Đo trên iPad dọc: chuyển từ cạnh-nhau sang xếp-chồng làm ảnh rộng gấp đôi (215pt → 425pt). Ảnh 3:2 giữ
    ưu thế xếp chồng lâu hơn trực giác — canvas 1300×900 vẫn nên chồng, phải tới cỡ 1800×700 cạnh nhau mới
    thắng.
- Pane tham chiếu hiển thị ảnh **như nó đang nằm trong thư viện** (kèm edit đã lưu), **không render lại
  qua một editor thứ hai** — nhân đôi bộ nhớ editor cho một tấm không ai động vào.
- Nhãn "Reference" **nổi lên trên** ảnh chứ không chiếm một hàng: xếp thành hàng thì ảnh mẫu tụt thấp hơn
  ảnh đang sửa 44pt, đúng thứ phá hỏng việc so sánh.
- **Khoá zoom/pan giữa hai pane** (mặc định bật, nút link trong header pane): hai pane bằng kích thước và
  ảnh đều fit trong đó, nên cùng mức phóng + cùng offset rơi đúng cùng vùng của mỗi ảnh. Pane tham chiếu
  **không tự pan được** — kéo nó rời khỏi ảnh đang sửa thì mất nghĩa so sánh.

## 6. Chưa có

- **Undo theo từng ảnh** — lịch sử nằm trên editor nên đổi ảnh là mất.
- Flag / rating.

## 7. Tiêu chí nghiệm thu

Mới có cho preload/cache preview (§2); phần còn lại của trang **chưa viết** — xem
[README — Việc còn nợ](../../README.md#6-việc-còn-nợ). Máy: iPhone 17 iOS 26.5, iPad Pro 13" iOS 26.5.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | phiên 5 ảnh vừa mở ở ảnh 1, để yên 30 s | chạm ảnh 2 rồi ảnh 5 trên filmstrip lần đầu | ảnh hiện đậm 100% ngay khung chụp đầu sau chạm (≤ 1,2 s), **không** có "Loading full-quality preview…"; chỉ pill `PREPARING` ở góc trên trái tới khi công cụ sẵn | ✅ `EditorPreviewCacheTests.preloadOrderWalksOutwardFromTheCurrentPhoto` · `.preloadOrderCoversEveryPhotoOnce` · `.needsPreloadUntilBothHalvesAreThere` · `iphone-batch-preview-cache.json` (`2-photo2-first-tap`, `4-photo3-first-tap`, `7-photo5-first-tap`) · `ipad-batch-preview-cache.json` (`i3-photo3-first-tap`) |
| AC-2 | ảnh 2 đã kéo Exposure lên +0,39, rồi chuyển sang ảnh 3 | chạm lại ảnh 2 | ảnh 2 hiện ngay, đậm 100%, với Exposure +0,39, không spinner (pill `PREPARING` nếu có thì chỉ tới khi công cụ sẵn); chạm lại ảnh 1 chưa sửa cũng vậy | ✅ `EditorPreviewCacheTests.storedPreviewComesBackFromMemory` · `.evictedPreviewIsReadBackFromDisk` · `.unchangedPhotoSharesOneFile` · `iphone-batch-preview-cache.json` (`5-photo2-back-tap`, `6-photo1-back-tap`) · `ipad-batch-preview-cache.json` (`i4-photo1-back-tap`, `i5-photo2-back-tap`) |
| AC-3 | preview đã cache của một ảnh vẽ ở recipe A | nháp của ảnh đổi sang B (Sync), hoặc ảnh đổi trong thư viện, hoặc vừa lưu | A không còn là kết quả: với B là placeholder cũ, ảnh render lại; đổi trong thư viện hay vừa lưu thì mục bị bỏ | ✅ `EditorPreviewCacheTests.hitOnlyWhenTheFingerprintMatches` · `.aNewModificationStampReplacesTheWholeEntry` · `.invalidateDropsThePhoto` · ⚠️ chưa chụp màn Sync → mở ảnh đã cache |
| AC-4 | phiên đã preload 5 ảnh | đóng editor; hoặc hệ thống báo thiếu bộ nhớ | đóng: thư mục `ShotDexPhoto-Previews-*` bị xoá, một lần ghi đang dở không tạo lại mục; thiếu bộ nhớ: RAM giữ 0 preview, file còn; bình thường RAM giữ ≤ 3 preview đã giải mã | ✅ `EditorPreviewCacheTests.clearRemovesTheDirectory` · `.memoryWarningKeepsTheDisk` · `.recentListKeepsOnlyTheNewest` · `.replacedFilesAreHandedBackForDeletion` · ⚠️ chưa đo bộ nhớ trên máy thật |
