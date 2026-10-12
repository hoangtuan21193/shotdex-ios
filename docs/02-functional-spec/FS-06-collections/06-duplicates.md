# FS-06.06 — Duplicates

`FS-06.06` · `Features/Duplicates/` · `Domain/Duplicates/` · bảng `perceptual_hash` · `duplicate_groups`
· test `DuplicateSeriesTests`, `DuplicateReviewTests` · cập nhật 2026-10-04

**Một câu:** tìm ảnh trùng và gần trùng bằng dấu vân tay hình ảnh, gom nhóm sẵn vào cache, và **để người
dùng tự chọn tấm nào phải đi**.

## 1. Quy tắc

- **Không tự chọn hộ.** App đánh dấu được cả nhóm giúp, nhưng không tự quyết tấm nào bị xoá.
- **Mỗi nhóm luôn còn ít nhất một ảnh không bị đánh dấu** — đánh dấu hết một nhóm là xoá mọi bản
  ([06b §1](06b-duplicates-marks-merge-delete.md)).
- **Không ghi gì vào thư viện Photos trước khi người dùng bấm xác nhận** trong một alert nói rõ điều sẽ ghi ([06b §2](06b-duplicates-marks-merge-delete.md)).
- **Mở màn chỉ đọc cache** — không băm lại, không gom lại.
- **Không tự quét** khi thư viện đổi; chỉ cập nhật số ảnh chưa quét rồi mời Rescan. Ngoại lệ duy nhất: thư
  viện **chưa từng** quét.
- Chỉ ảnh, **không video**.

## 2. Dấu vân tay hình ảnh

Mỗi ảnh xin một bản **96px** (chế độ chất lượng cao để hệ thống gọi lại đúng một lần; dùng mạng theo đúng
chính sách của index), vẽ ép vào lưới xám **9×8** rồi lấy **64 bit**: mỗi bit trả lời "ô này tối hơn ô bên
phải không".

Không lấy được ảnh thì ghi một dòng **rỗng**, và chỉ thử lại ở lượt quét được phép dùng mạng.

## 3. Lượt quét

1. Dọn dòng của những ảnh đã biến mất.
2. Danh sách việc = ảnh **chưa có dấu vân tay**, hoặc **ngày sửa đã lệch** (ảnh vừa chỉnh).
3. Lô **200**, xin **8** ảnh song song, **ghi sau mỗi lô** nên huỷ giữa chừng thì lần sau chạy tiếp.

Tiến độ `Scanning N of M` + **Cancel**; một lượt tại một thời điểm.

- Cancel là nút chữ màu accent, **không đỏ**: ở màn này đỏ chỉ nghĩa là "ảnh sẽ mất". Huỷ giữ mọi lô đã ghi (Q8).
- **Lúc app còn đọc thư viện** (index chưa xong), ngay dưới dải chọn có dòng footnote *"Still reading photo info · N%"*,
  N cùng số với thẻ tiến độ của Library; index xong thì dòng biến mất và số ảnh chưa quét cập nhật (F2).
- Màn **không bao giờ** bảo người dùng tự index — app không có nút đó. Chưa có dòng dữ liệu nào: lúc đang index
  thì màn rỗng ghi dòng tiến độ trên; không index mà vẫn 0 ảnh thì *"No Photos"* (NF-04 "Không có ảnh").

## 4. Ba mức

| Mức | Luật |
|---|---|
| **Exact** | dấu vân tay bằng nhau **và** cùng kích thước pixel — bản xuất lại 2000px không gộp với bản gốc 6000px |
| **Similar** | lệch **≤ 10 / 64 bit** — thu nhỏ, xuất lại, cắt nhẹ, ảnh chụp liên tiếp |
| **Series** | cùng khoảnh khắc: cách nhau **≤ 30 giây** và lệch **≤ 20 / 64 bit**, tối thiểu **3** ảnh |

Mức đang dùng được nhớ lại (mặc định Similar), và dải chọn dựng từ **danh sách đầy đủ** nên thêm một mức
không thể quên cập nhật giao diện. Dải chọn còn có tab thứ tư **Bursts** (§7b) — không phải một mức trùng.
Bursts có trong code từ 2026-10-12 (`Features/Bursts/`, nguồn `Data/Sources/BurstLibrary.swift`), board `PH_DuplicatesBursts`, `IP_DuplicatesBursts`, `DI_DuplicatesBursts`.

## 5. Gom nhóm

Chạy ngoài luồng chính **sau lượt quét, cho cả hai mức**, mỗi mức ghi cache trong một giao dịch.

- Ảnh trùng dấu vân tay gộp trước bằng một bảng tra; việc tìm "gần giống" chỉ chạy trên **các dấu vân tay
  khác nhau** (một nghìn ảnh chụp màn hình trắng cùng dấu vân tay chỉ còn một đại diện).
- Mẹo lọc: hai dấu vân tay lệch ≤ 10 bit thì **chắc chắn có ít nhất một byte lệch ≤ 1 bit** — nên chỉ cần
  dò 8 byte × 9 biến thể rồi mới đếm chính xác.
- Nhóm là **thành phần liên thông**: a giống b, b giống c thì c vào cùng nhóm dù a và c xa hơn ngưỡng.
- Trong nhóm, ảnh xếp **tốt nhất trước**: nhiều pixel hơn → file lớn hơn → favorite → cũ hơn. Nhóm xếp theo
  ảnh mới nhất trước. Cùng một hàm dựng nhóm cho cả lúc gom mới lẫn lúc đọc cache, nên thứ tự y hệt.
- Đọc cache: ảnh mất dòng dữ liệu hoặc mất khỏi thư viện thì bị bỏ; nhóm còn một ảnh thì biến mất.

## 6. Series — vì sao không dùng lại cách gom kia

Series **không phải một nấc lỏng hơn trên cùng cái thang**: nó hỏi câu khác — *"đây có phải một loạt ảnh của
cùng một khoảnh khắc không"* — và trả lời bằng **thời gian cộng độ giống**. Đúng thứ hai mức kia được xây để
bỏ đi: các khung **cố tình khác nhau** — cùng bối cảnh, đổi tư thế.

- Sắp theo ngày chụp rồi **cắt chuỗi** ở chỗ tấm kế cách tấm **ngay trước nó** quá 30 giây hoặc lệch quá 20
  bit. Nối *hàng xóm với hàng xóm* nên một loạt được phép **trôi**: tấm đầu và tấm cuối có thể rất khác nhau
  miễn mỗi bước ở giữa đều nhỏ.
- Cách gom theo thành phần liên thông sẽ vui vẻ nối hai loạt cách nhau mấy tiếng chỉ vì trông giống nhau.
- Ngưỡng 20 bit rộng hơn mức Similar **có chủ đích** — chủ thể phải cử động thì mới là một loạt; vẫn thấp xa
  mức ~32 bit của hai ảnh không liên quan, và cái siết thật sự là **30 giây**.
- Tối thiểu 3 ảnh: hai tấm cách nhau 20 giây là chuyện chụp bình thường.
- Ảnh **không có ngày chụp bị loại** chứ không đoán — không có thời gian thì không có gì để nối.
- Trong một loạt, ảnh xếp **theo thứ tự chụp**, không phải tốt-nhất-trước: thứ đang xem xét là tư thế đổi
  thế nào từ khung này sang khung kế, mà một loạt sắp theo dung lượng thì không còn là một loạt.
- Ở mức này dải trên ghi "Reviewed N of M series" và **bỏ** phần "~MB to free" (ở một loạt tư thế, câu trả lời
  thường là giữ vài tấm); thẻ **không có bản giữ, nhãn Keep hay chip lý do** — khung dẫn đầu là khung **đầu tiên**,
  gắn nhãn vào là nói dối về lý do nó đứng đầu (§7.2). Có màn rỗng riêng.

## 7. Màn hình (v2, duyệt trên canvas 2026-10-04)

Board: `PH_Duplicates` · `PH_DuplicatesPinched` · `IP_Duplicates` · `DI_Duplicates` · `DC_Duplicates`
(màn rộng: [06b §4](06b-duplicates-marks-merge-delete.md)). Tier A. Mục tiêu v2: **chọn nhanh và chắc tay** — người
dùng app dọn ảnh hay than ba điều: sợ xoá nhầm, không biết bản nào tốt hơn, mất công đánh dấu từng ô.

### 7.1 Dải trên cùng đóng băng

Dưới thanh điều hướng (Back · **Duplicates** · ⋯) là một dải nền `.bar` dính ở trên, viền tóc ở đáy; các thẻ cuộn
bên dưới nó.

- Hàng 1: dải chọn **Exact · Similar · Series** (segmented) + nút **sắp xếp** dạng viên "Most space first ▾" — menu
  **Most space first** (nhóm giải phóng nhiều nhất lên đầu) · **Newest first** · **Oldest first**; nhớ lại lần sau.
- Hàng 2: **"Reviewed 4 of 12 groups · ~96 MB to free"** (Series: "Reviewed 2 of 8 series", không có MB, §6) + vạch
  tiến độ xanh 4pt; dưới là **"Scanned 2 days ago · 148 photos not scanned yet"** ("Library up to date" khi không còn gì).
  Bên phải: nút tròn **Rescan** 32pt (vùng chạm 44).
- Nhóm **đã xem** = có ít nhất một dấu xoá, hoặc đã bấm Keep all.
- Đang quét: hàng 2 thành "Scanning N of M" + vạch + **Cancel** chữ (§3).
- Regular width: cả dải nằm một hàng (dải chọn 330pt · sắp xếp · tiến độ ≤ 400pt · trạng thái · Rescan).

### 7.2 Thẻ quyết định

Mỗi nhóm là một thẻ bo `r-lg`, đệm 12:

- Đầu thẻ: **"5 photos"** + bên phải **"~24.9 MB to free"** (giữ bản đề xuất, bỏ phần còn lại); dòng dưới
  **"Sep 9, 2026 · 4 s apart"** (khoảng từ tấm đầu tới tấm cuối: s / min / h / days). Exact ghi **"Identical files"** thay
  khoảng thời gian.
- Trái: **bản giữ** cỡ lớn (rộng = 2 ô + 1 khe, bo `r-md`), góc dưới trái nhãn **"✓ Keep"** nền đen 55%; dưới ảnh dòng
  "6240×4160 · 18.9 MB"; dưới nữa tối đa **2 chip lý do**: Edited · RAW · Favorite · Live · Largest — chip chỉ hiện khi
  nó làm bản giữ khác ít nhất một bản sao.
- Bản giữ là **đề xuất**: bản đã chỉnh → favorite → file lớn hơn → nhiều pixel hơn (D3). **Keep Only This** trên một ô
  khác đổi bản giữ của nhóm đó sang ô ấy (nhớ suốt phiên như dấu).
- Phải: các **bản sao** thành lưới `N` cột (mặc định 2 ở compact, 3 ở regular), ô vuông bo `r-sm`, khe 4; khe giữa
  bản giữ và lưới 8. Dưới mỗi ô **một điểm khác** so với bản giữ, theo thứ tự: "Not edited" · "JPEG only" ·
  "Not favorite" · "Still photo" · nếu không có thì kích thước "3120×2080".
- Chân thẻ: ba nút viên cao 34 (vùng chạm 44): **"Mark the other 4"** đỏ (chỉ một bản sao: "Mark the other one";
  nhóm đã có dấu: **"Unmark"** màu chữ thường) · **"Keep all"** (đang giữ cả: "✓ Keeping all", chạm lại để bỏ) ·
  **Compare** dồn phải.
- **Series** không có bản giữ (khung đầu của một loạt tư thế không phải lời khuyên): mọi khung chung một lưới `N + 2` cột
  theo thứ tự chụp, caption "+4 s" tính từ khung đầu, không có "Mark the other", không có "~MB to free".
- Glyph trạng thái: favorite / đã chỉnh / RAW / Live đọc **một lần khi thẻ hiện ra**, ngoài luồng chính, chỉ tài nguyên
  trên máy (không mạng), nhớ suốt màn. Chúng là nguồn của chip lý do và dòng khác biệt; VoiceOver đọc đủ cả bốn.

### 7.3 Đánh dấu

- **Chạm ô = đánh dấu xoá** (đĩa thùng rác trắng trên đỏ, viền đỏ 3pt, ảnh mờ còn 45%), chạm lại bỏ. Ô chưa dấu có
  vòng trắng rỗng. Đỏ chỉ nghĩa là "ảnh sẽ mất"; dấu tick accent của lưới là "đang chọn". Dấu ghi theo id ảnh, sống
  suốt phiên app ([06b §1](06b-duplicates-marks-merge-delete.md)).
- Menu giữ lâu: **Keep Only This** · Mark for Deletion / Unmark · Compare.
- **Compare là đường xem kỹ** vì ô nhỏ khó phân biệt: mở màn so sánh, chia sẻ luôn tập dấu; nút đỏ ở đó chỉ xoá **đúng
  id của nhóm đang mở** ([FS-01.08](../FS-01-library/08-compare.md)). Xoá trong Compare mà nhóm còn ≥ 2 ảnh thì Compare ở
  lại (V2); lỗi xoá do chính Compare báo (Q2).

### 7.4 Nhóm đã quyết tự thu gọn

- Bấm **Mark the other N** hoặc **Keep all** → thẻ thu thành **một dòng 56pt**: tối đa 3 ảnh nhỏ 32pt (ảnh mang dấu mờ +
  viền đỏ 2pt) · **"Keeping 1 · deleting 2"** ("deleting 2" màu đỏ) hoặc **"Keeping all 2"** · dòng dưới "Sep 21, 2026 ·
  8.9 MB to free" / "… · nothing to delete" · chevron xuống. Chạm dòng → mở lại thẻ.
- Đánh dấu từng ô **không** tự thu gọn (người dùng đang cân nhắc). Bỏ hết dấu của một nhóm đã thu → nhóm mở lại.

### 7.5 Pinch

Chụm/mở hai ngón trên danh sách đổi **số bản sao mỗi hàng** theo bậc 1…5 như lưới Library: mở ra = ô to hơn, chụm vào
= nhiều ô hơn; bản giữ co giãn theo (luôn 2 ô + 1 khe). Trong lúc pinch có HUD viên kính **"3 per row"** ở trên, rung
nhẹ mỗi bậc. Mật độ nhớ riêng cho compact và regular.

### 7.6 Thanh dưới nổi

Có dấu thì hiện thanh nổi thay thanh Delete đỏ cũ: viên kính **"2 marked · 8.9 MB"** / "Recently Deleted for 30 days" +
viên đỏ cao 48 **"🗑 Delete 2"** chữ trắng. Compact: viên kính giãn hết phần còn lại; regular: cụm đứng giữa. Tab bar ẩn
khi có dấu (iOS 26 lẫn tab bar tự vẽ trước 26). Phạm vi đếm và cổng chặn: [06b §1, §3](06b-duplicates-marks-merge-delete.md).

## 7b. Tab Bursts

Dải chọn là **Exact · Similar · Series · Bursts**. Bursts là lối vào chính của màn chọn khung
([FS-02.05](../FS-02-photo-detail/05-burst-selection.md)); ⋯ → Select Frames… trong viewer là lối thứ hai.

- Danh sách lấy thẳng từ PhotoKit: **mọi burst** trong thư viện mà app thấy ≥ 2 khung, mới nhất trước. Không
  dùng dấu vân tay, không cần Rescan.
- Mỗi hàng: ảnh bìa (khung đại diện) · *"24 frames"* · ngày chụp · *"2 suggested by Photos"* hoặc *"No suggestion"*.
- Số khung và số gợi ý đếm khi hàng hiện ra, không đếm cả thư viện lúc mở tab ([NF-01](../../04-non-functional-design/NF-01-performance.md) luật 1).
- Chạm một hàng mở màn chọn khung của burst đó. Xoá xong thì hàng cập nhật tại chỗ; burst còn 1 khung thì biến mất.
- Dòng tóm tắt là *"N bursts"*; không có Merge, Rescan hay nút đỏ ở tab này. Thư viện không có burst → màn rỗng
  *"No Bursts"*.
- Series giữ nguyên: loạt chụp nhanh không phải burst thật vẫn ở Series, xoá qua Compare.

## 8. Merge, Delete và dấu xoá

Ở [06b](06b-duplicates-marks-merge-delete.md): dấu sống bao lâu và cổng chặn "xoá mọi bản" (§1), Merge chỉ ở
Exact sau một alert (§2), Delete (§3), màn rộng (§4), AC-1…AC-21 (§5).

## 9. Tiêu chí nghiệm thu

Merge, dấu xoá, glyph, quét, trạng thái đang index, màn rộng và Compare: AC-1…AC-21 ở
[06b §5](06b-duplicates-marks-merge-delete.md#5-tiêu-chí-nghiệm-thu). Luật gom Exact/Similar/Series **chưa có AC** — xem
[README — Việc còn nợ](../../README.md#6-việc-còn-nợ). Tab Bursts:

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-B1 | thư viện có 3 burst (24, 10, 5 khung), burst 24 khung được Photos gợi ý 2 khung, và 1 loạt Series không phải burst | mở Duplicates, chọn tab Bursts | dải chọn ghi Exact · Similar · Series · Bursts; 3 hàng mới nhất trước, mỗi hàng có bìa, số khung, ngày; hàng 24 khung ghi *2 suggested by Photos*, hai hàng kia *No suggestion*; loạt Series không có trong tab | `BurstModelTests.deletingAllButOneDropsTheBurstFromTheTab` (thứ tự, số gợi ý), `BurstSelectionTests.burstRowsAreNewestFirstAndSayTheirCounts`; sim với `-ShotDexFakeBursts`: 4 tab, hàng có bìa/số khung/ngày/gợi ý · ❓ burst thật cần máy thật |
| AC-B2 | như AC-B1 | chạm hàng 24 khung | màn chọn khung mở với 24 khung của đúng burst đó | route `bursts-iphone`: chạm hàng 6 khung → màn chọn khung `Frame 1 of 6` (burst giả) |
| AC-B3 | burst 5 khung, giữ 1 khung, xoá 4 | quay lại tab Bursts | hàng của burst đó biến mất; tóm tắt đổi từ *3 bursts* thành *2 bursts* | `BurstModelTests.deletingAllButOneDropsTheBurstFromTheTab`; route `bursts-iphone2`: giữ 1/2, xoá → hàng biến mất, *1 burst* |
| AC-B4 | thư viện không có burst nào | mở tab Bursts | màn rỗng *No Bursts*; không có nút Rescan | `BurstModelTests.noBurstsListsNothing`; view: *No Bursts*, không Rescan/Merge (⋯ ẩn ở tab này) |
