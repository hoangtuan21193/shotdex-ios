# FS-06.06 — Duplicates

`FS-06.06` · `Features/Duplicates/` · `Features/Bursts/` · `Domain/Duplicates/` · bảng `perceptual_hash` · `duplicate_groups`
· `duplicate_quality` · `duplicate_review` · test `DuplicateGrouperTests`, `DuplicateSeriesTests`, `DuplicateReviewTests`,
`DuplicateQualityTests`, `DuplicateReviewStoreTests` · cập nhật 2026-10-17 (v3)

**Một câu:** tìm ảnh trùng và gần giống, **nói cho người chụp biết tấm nào tốt hơn và vì sao**, và để họ tự chọn tấm nào
phải đi — nhanh với phần chắc chắn, kỹ với phần cần mắt người.

Nguồn v3: intent [2026-10-17-duplicates-v3](../../_intents/2026-10-17-duplicates-v3.md), quyết định
`.planboard/duplicates-v3/DECISIONS.md` (D1–D12, A1–A8). Dấu xoá, xoá, thừa hưởng, màn rộng: [06b](06b-duplicates-marks-merge-delete.md).
Màn chọn khung dùng chung: §8 (thay phần màn hình của [FS-02.05](../FS-02-photo-detail/05-burst-selection.md)).

## 1. Quy tắc

- **Không tự chọn hộ.** App gợi ý bản giữ và đánh dấu được cả loạt giúp, nhưng chỉ sau khi người dùng xem; không gì
  được đánh dấu sẵn lúc mở màn.
- **Gợi ý luôn kèm lý do người dùng kiểm được** ("Sharpest · eyes open", "Biggest file"). Không có lý do đo được thì
  nói thật lý do đang dùng, không gắn nhãn "best".
- **Ảnh favorite, đã chỉnh, hoặc nằm trong album người dùng tạo không bao giờ được tự đánh dấu** — kể cả qua *Remove
  the other N* hay Dọn nhanh. Người dùng vẫn tự chạm đánh dấu được (A2).
- **Mỗi nhóm luôn còn ít nhất một ảnh không bị đánh dấu** ([06b §1](06b-duplicates-marks-merge-delete.md)).
- **Không ghi gì vào Photos trước hộp xác nhận xoá của hệ thống** ([06b §3](06b-duplicates-marks-merge-delete.md)).
- **Ảnh nguyên liệu không phải rác.** Bracket và focus stack được gọi đúng tên, có nút ghép, không có nút đỏ (§5).
- **Mở màn chỉ đọc cache** — không băm lại, không gom lại. Không tự quét khi thư viện đổi; ngoại lệ: chưa từng quét.
- Chỉ ảnh, **không video**.
- Mọi phân tích chạy trên máy; không ảnh nào rời máy.

## 2. Dấu vân tay hình ảnh

Không đổi so với v2. Mỗi ảnh xin một bản **96px** (chế độ chất lượng cao, dùng mạng theo đúng chính sách của index), vẽ
ép vào lưới xám **9×8** rồi lấy **64 bit**: mỗi bit trả lời "ô này tối hơn ô bên phải không". Không lấy được ảnh thì ghi
một dòng **rỗng**, chỉ thử lại ở lượt quét được phép dùng mạng.

## 3. Lượt quét

1. Dọn dòng của những ảnh đã biến mất.
2. Danh sách việc = ảnh **chưa có dấu vân tay**, hoặc **ngày sửa đã lệch**.
3. Lô **200**, xin **8** ảnh song song, **ghi sau mỗi lô** — huỷ giữa chừng thì lần sau chạy tiếp.
4. Gom nhóm (§4) — **kết quả hiện dần**: sau mỗi lô đã gom, nhóm mới hiện vào danh sách; dải trên ghi *"Scanning 1,200
   of 38,000 · 40 found so far"* + **Cancel** (chữ accent, không đỏ) (A4).
5. **Chấm chất lượng** (§6) cho ảnh **đã nằm trong một nhóm** thuộc loại Look-alike hoặc Same moment — không chấm cả
   thư viện. Chấm xong nhóm nào thì thẻ nhóm đó cập nhật lý do tại chỗ; trong lúc chờ, thẻ ghi *"Checking sharpness…"*
   thay cho chip lý do.

- Ảnh chỉ có trên iCloud mà lượt này không được dùng mạng: dòng trạng thái ghi *"148 photos only in iCloud — will check
  on Wi-Fi"* thay cho *"not scanned yet"* (A4).
- **Lúc app còn đọc thư viện** (index chưa xong): dòng *"Still reading photo info · N%"*, N cùng số với Library (F2).
  Màn không bao giờ bảo người dùng tự index.
- Pass quét và pass chấm tuân [NF-01](../../04-non-functional-design/NF-01-performance.md) luật 5: resume được, huỷ tức thì,
  nhường khi người dùng đang tương tác và khi máy nóng.

## 4. Gom nhóm và loại nhóm

v3 bỏ ba "mức" độ chặt (Exact · Similar · Series) và tab Bursts. **Gom một lần**, mỗi cụm thuộc **đúng một loại** (D4):

| Loại (chữ trên màn) | Luật | Bản giữ đề xuất |
|---|---|---|
| **Copies** | quan hệ "bản sao": dấu vân tay bằng nhau, cùng kích thước pixel, **và** cùng giây chụp (hoặc cùng ngày sửa khi thiếu ngày chụp). Mọi ảnh của nhóm cùng kích thước | luật file D3: đã chỉnh → favorite → file lớn hơn → nhiều pixel hơn |
| **Smaller copies** | cũng là nhóm bản sao (thành phần liên thông của quan hệ "bản sao" ở trên **cộng** quan hệ "bản nhỏ": lệch ≤ 10/64 bit, nhỏ hơn ≥ 25% cạnh dài, cùng giây chụp **hoặc** bản nhỏ thiếu ngày chụp EXIF — gửi lại qua WhatsApp/Zalo/AirDrop, bản xuất cỡ nhỏ), khi nhóm có **ít nhất hai kích thước** | bản lớn hơn, **trừ khi** có bản xuất đã chỉnh (§7.4) — khi đó bản xuất là bản giữ |
| **Same moment** | chuỗi theo thời gian: tấm kế cách tấm **ngay trước** ≤ 30 s và lệch ≤ 20 bit, tối thiểu **3** ảnh; burst PhotoKit (≥ 2 khung app thấy được) luôn vào đây | theo điểm chất lượng (§6) |
| **Look-alikes** | lệch ≤ 10/64 bit, không thuộc ba loại trên (thành phần liên thông như v2) | theo điểm chất lượng (§6), rồi D3 |
| **Screenshots** | mọi nhóm mà mọi ảnh là ảnh chụp màn hình (cờ của hệ thống) | luật file D3 |

- Thứ tự ưu tiên khi một ảnh khớp nhiều luật: Copies → Smaller copies → Same moment → Look-alikes. Ảnh đã vào loại trước
  không vào loại sau; nhóm còn < 2 ảnh sau khi rút bị bỏ.
- Hai ảnh **khác tiêu cự > 10%** (EXIF `focalLength`) không bao giờ cùng nhóm — cùng cảnh 24mm và 35mm là hai khung hình,
  không phải bản sao (persona An).
- Copies đòi cùng giây chụp vì một chuỗi tripod (góc phố, 20 khung) có dấu vân tay bằng nhau nhưng là 20 khoảnh khắc khác
  nhau; v2 gộp chúng vào Exact và đề nghị Merge.
- Burst của máy ảnh (Sony 10 fps) và burst iPhone giờ cùng một loại, cùng một màn chọn khung (§8).
- Ảnh **không có ngày chụp** không vào Same moment (không đoán), vẫn vào các loại khác.
- Thuật toán dò lân cận (8 byte × 9 biến thể, gộp trùng dấu vân tay bằng bảng tra trước) giữ nguyên v2.
- Đọc cache: ảnh mất dòng dữ liệu hoặc mất khỏi thư viện thì bị bỏ; nhóm còn một ảnh thì biến mất.

## 5. Bộ nguyên liệu: bracket và focus stack

Sau khi gom, app đọc thêm EXIF **chỉ cho ảnh trong nhóm** (bù sáng, chế độ chụp) — không index lại cả thư viện; kết quả
ở bảng `duplicate_quality` (§10). Một nhóm (bất kỳ loại) là **bộ nguyên liệu** khi (D5):

| Bộ | Luật | Thẻ hiện |
|---|---|---|
| **Bracket** | ≥ 2 khung, chụp trong ≤ 2 s/khung, cùng tiêu cự, **bù sáng khác nhau** ≥ 0.7 EV theo bước đều (vd −2/0/+2) | *"Bracket · 5 frames · ±2 EV"* · nút **Merge to HDR** ([FS-01.11](../FS-01-library/11-hdr-merge.md)) · **Not duplicates** |
| **Focus stack** | ≥ 10 khung, chụp ≤ 1 s/khung, cùng bù sáng, cùng tiêu cự, dấu vân tay lệch ≤ 6 bit giữa hai khung liền kề | *"Focus stack? · 24 frames"* · nút **Focus Stack** ([FS-01.10](../FS-01-library/10-focus-stack.md)) · **Choose frames** (§8) · **Not duplicates** |

- Bộ nguyên liệu **không** có *Remove the other N*, không có nút đỏ, **không** tính vào "~GB to free" ở dải trên hay màn tóm
  tắt. Người dùng vẫn đánh dấu từng khung được (vòng ở góc, §7.4).
- Thiếu EXIF bù sáng (ảnh xuất lại, ảnh từ app khác): không đoán là bracket; nhóm ở lại loại gốc của nó.
- Focus stack có dấu "?" vì luật chỉ dựa vào thời gian + độ giống; một chuỗi tripod 12 khung chụp liên tục cũng khớp —
  nên thẻ đưa cả **Choose frames** để chọn khung như Same moment.
- Merge to HDR / Focus Stack mở màn ghép có sẵn với đúng id của bộ; ghép xong ảnh mới vào thư viện, bộ gốc **không** bị
  đánh dấu.

**Bộ panorama: không làm ở v3** (người dùng 2026-10-17). Không có tín hiệu đáng tin — EXIF không ghi, dấu vân tay của
hai khung lệch nửa khung hình thường > 20 bit nên hầu như không vào nhóm nào. Khung panorama lỡ vào Look-alikes thì người
dùng bấm *Not duplicates* (§9).

## 6. Chấm chất lượng (D1)

Chạy cho ảnh trong nhóm Look-alikes và Same moment (và khung của bộ nguyên liệu, để chọn khung). Đầu vào là ảnh **512px**
cạnh dài, cùng chính sách mạng như dấu vân tay. Mỗi ảnh ra:

| Điểm | Đo gì | Nhãn trên ảnh |
|---|---|---|
| **Sharpness** | độ nét theo biến thiên cạnh (variance of Laplacian), chuẩn hoá trong nhóm | bản tốt nhất: *Sharpest*; bản kém ≥ 35% so với bản tốt nhất: *Soft* |
| **Eyes** | mỗi khuôn mặt: mắt mở/nhắm và chất lượng khuôn mặt (Vision) | *Eyes open* trên bản giữ khi một bản khác có mắt nhắm; *Eyes closed* trên bản có ≥ 1 khuôn mặt mắt nhắm |
| **Exposure** | % điểm ảnh cháy sáng (≥ 250/255) và bệt tối (≤ 5/255) | *Blown highlights* khi > 2% cháy và bản giữ ≤ 0.5%; *Too dark* tương tự với bệt tối |

- **Thứ hạng** trong Look-alikes / Same moment: không ai có mắt nhắm trước → nét hơn → ít cháy sáng hơn → rồi D3. Bản đứng
  đầu là **bản giữ đề xuất**; Same moment v3 **có** bản giữ đề xuất (v2 không có) vì giờ có lý do đo được.
- Nhãn mắt chỉ hiện khi độ tin cậy của Vision ≥ ngưỡng đặt sau spike (§12); dưới ngưỡng thì không nói gì về mắt.
- Nhóm **chưa chấm xong** hoặc ảnh **không chấm được** (iCloud, không mạng): bản giữ theo D3, chip ghi đúng lý do D3
  (*Biggest file*, *Edited*, *Favorite*), không bao giờ *Sharpest*.
- Chấm một lần, lưu ở `duplicate_quality` khoá theo id ảnh + ngày sửa; ảnh đổi thì chấm lại. Không lưu ảnh, không lưu
  khuôn mặt — chỉ số và khung chữ nhật khuôn mặt chuẩn hoá (dùng cho *Zoom to face*, §8).
- Ngân sách: **≤ 20 ms một ảnh** trên iPhone 15 (512px) — số thật đo ở spike §12.

## 7. Màn hình (v3)

Board: `PH_Duplicates` · `PH_DuplicatesSummary` · `PH_DuplicatesLargeGroup` · `PH_DuplicatesPinched` · `PH_BurstFrames`
và bản `IP_` · `DI_` · `DC_` tương ứng (vẽ lại 2026-10-17; `PH_DuplicatesBursts` bị bỏ cùng tab Bursts). Tier A cho danh
sách, tier D cho màn chọn khung. Màn rộng, Duo: [06b §4](06b-duplicates-marks-merge-delete.md).

### 7.1 Lối vào

- Dòng **Duplicates** ở Collections ▸ Utilities ghi phụ đề *"~4.2 GB to free"* (từ cache; chưa từng quét: *"Not checked
  yet"*). Con số không tính bộ nguyên liệu.
- Lối từ viewer (⋯ ▸ **Choose Frames…** trên ảnh burst) mở thẳng màn chọn khung (§8), không qua tóm tắt.

### 7.2 Màn tóm tắt (D2)

Mở Duplicates là màn tóm tắt (khi đã có kết quả quét), không phải danh sách thẻ:

- Tiêu đề lớn *"~4.2 GB to free"*, dòng phụ *"312 groups · checked 2 min ago"*.
- Thẻ **Quick clean** (nền `.secondarySystemGroupedBackground`, `r-lg`): *"212 copies · 1.2 GB"* + dòng *"Exact copies and
  smaller re-shares. Your favorites, edits and album photos are never included."* + nút **Review 212…** — đây là **nút
  accent duy nhất** của màn ([DESIGN.md §4](../../../DESIGN.md)).
- Thẻ **Choose yourself**: *"100 groups · 3.0 GB"* + đếm theo loại (Look-alikes 48 · Same moment 40 · Screenshots 12) + nút
  **Start** kiểu `.bordered` `.tint(.secondary)`.
- Thẻ **Source frames** khi có bộ nguyên liệu: *"6 brackets · 2 focus stacks"* + **Show**. Không có GB.
- **Review 212…** mở sheet **xem trước**: danh sách nhóm Quick clean (mỗi dòng: bản giữ + số bản sẽ xoá + MB), bỏ tick từng
  nhóm được, nút chân sheet **Select 205 photos** (số theo tick). Chạm nút → các bản sao mang dấu, sheet đóng, thanh xoá
  hiện (06b §3). **Chưa xoá gì.**
- Ảnh favorite / đã chỉnh / trong album người dùng tạo: nhóm có bản sao như vậy vẫn ở Quick clean nhưng bản đó **không**
  được chọn và dòng ghi *"1 kept: in album Mai & Huy"*.
- Chưa từng quét: màn tóm tắt thay bằng tiến độ quét (§3); kết quả hiện dần vào hai thẻ.
- Không có nhóm nào: màn rỗng *"No Duplicates"* + *"Checked 2 min ago"* + nút **Check Again**.

### 7.3 Danh sách (Choose yourself, Show, hoặc lọc)

- Dải trên đóng băng (nền `.bar`): **hàng lọc** dạng viên cuộn ngang, bề rộng mỗi viên cố định theo chữ dài nhất của nó
  (A6): **All · Copies · Smaller copies · Look-alikes · Same moment · Screenshots · Source frames**, mỗi viên kèm số nhóm;
  loại không có nhóm thì ẩn. Viên đang chọn kiểu trung tính (nền card + chữ đậm), không nền accent.
- Hàng 2 (một dòng, A6): *"Reviewed 4 of 100 · ~3.0 GB to free"* + vạch tiến độ 4pt + nút sắp xếp
  **Easiest first ▾** (A7: nhóm có khoảng cách điểm lớn nhất giữa bản giữ và bản kế lên đầu — gợi ý chắc nhất trước) ·
  **Most space first** · **Newest first** · **Oldest first**; nhớ lại lần sau. Rescan chuyển vào ⋯ với chữ **Check Again** (A3).
- ⋯: **Check Again** · **Ignored (3)** (A1) · **Clear Selection**.
- Quyền `.limited` hoặc bị từ chối: banner trên cùng *"ShotDex can see 1,240 of your photos"* / *"ShotDex can't see your
  photos"* + **Settings**; Check Again mờ với dòng lý do khi bị từ chối (A5).

### 7.4 Thẻ nhóm

Thẻ bo `r-lg`, đệm 12:

- Đầu thẻ: tên loại + số ảnh (*"Look-alikes · 9 photos"*) + bên phải *"~24.9 MB to free"*; dòng dưới *"Sep 9, 2026 · within
  4 seconds"* (A3).
- Lưới `N + 2` cột như v2 (bản giữ 2×2 ô góc trên trái, khe 4, `DuplicateCardMetrics`). Trên bản giữ: tối đa **2 chip lý
  do** (§6 hoặc D3) và nhãn **✓ Keep**.
- **Chú thích dưới mỗi bản sao** (D10): tối đa **2 dòng chữ trắng trên nền đen 55%** trong ảnh, góc dưới trái:
  - dòng 1 — điều bản này **thua** bản giữ, bằng lời, theo ưu tiên: *Eyes closed* · *Soft* · *Blown highlights* · *Smaller
    copy* · *Not edited* · *JPEG only* · *Still photo*;
  - dòng 2 — nguồn hoặc nơi ở, nếu có: *WhatsApp* · *Export of DSC01234* · *In album: Mai & Huy* · *Favorite*;
  - thông số chụp chỉ khi **khác nhau trong nhóm**: *−2 EV*, *35mm*, *1/60 s*.
  - Không có gì để nói → không có chú thích (ô sạch). Pixel và MB chỉ ở màn xem to.
  - Chữ **không đỏ** (đỏ chỉ nghĩa là "ảnh sẽ mất").
- **Chạm ảnh = mở to** (D7): mở viewer của nhóm (§7.6). **Vòng 26pt ở góc trên phải (vùng chạm 44)** = đánh dấu / bỏ dấu:
  có dấu thì đĩa thùng rác trắng trên đỏ, viền đỏ 3pt, ảnh mờ còn 45% (như v2).
- Menu giữ lâu: **Keep just this one** · **Remove** / **Don't remove** · **Compare**.
- Chân thẻ: **Remove the other 8** (đỏ; không đánh dấu ảnh A2 — khi có, nút ghi *"Remove the other 6"* và dưới thẻ *"2 kept:
  favorite, in album"*) · **Keep all** · **Not duplicates** (trong menu của Keep all: chạm Keep all = giữ cả phiên này; giữ lâu
  → *Not duplicates* = không bao giờ hiện lại) · **Compare** dồn phải.
  - Same moment và focus stack: nút trái là **Choose frames** (mở §8) thay cho Remove the other.
  - Same moment: bản giữ đề xuất 2×2 ở đầu, các khung còn lại theo **thứ tự chụp** (người dùng 2026-10-17) — một loạt
    sắp theo điểm không còn đọc được như một loạt. Thứ tự "tốt nhất" ở mọi loại khác dùng **một** hàm: D3 + điểm (§6).
- **Nhóm lớn** (D9): từ **12 ảnh** trở lên, thẻ chỉ hiện bản giữ + **một hàng** bản sao, rồi viên **Show all 51**; chạm mở cả
  lưới (một lần, nhớ suốt màn). Nút chân thẻ luôn nằm ngay dưới phần đang hiện.
- **Thu gọn** (v2 §7.4) sau Remove the other / Keep all: viền đỏ của các ô vừa đánh dấu **giữ 0.6 s**, rung nhẹ, rồi mới thu
  thành dòng 56pt; danh sách giữ vị trí cuộn của thẻ kế (D9). Đánh dấu từng ô không thu gọn.
- Haptic: `.selection` khi đánh dấu một ô; `.impact(.light)` cho Remove the other / Keep all; `.warning` khi chạm cổng
  "giữ ít nhất một"; `.success` khi xoá xong.
- Pinch đổi số bản sao mỗi hàng 1…5 như v2 (HUD *"3 per row"*).

### 7.5 Thẻ bộ nguyên liệu

Như §7.4 nhưng: đầu thẻ *"Bracket · 5 frames · ±2 EV"*; dưới mỗi khung là thông số khác nhau (*−2 EV*); không có bản giữ
2×2 (mọi khung một lưới theo thứ tự chụp); chân thẻ **Merge to HDR** / **Focus Stack** (`.bordered`) · **Choose frames**
(focus stack) · **Not duplicates**. Không có nút đỏ.

### 7.6 Xem to trong nhóm

Chạm một ảnh trong thẻ → viewer tier D của **riêng nhóm đó**: vuốt ngang qua các ảnh của nhóm, pinch zoom, dưới đáy
**Keep this** (đổi bản giữ của nhóm sang ảnh này, rồi về thẻ) · **Remove** / **Don't remove** · thông số (kích thước, MB, nguồn,
điểm §6). Vuốt xuống để đóng. Với Same moment / bộ nguyên liệu, chạm mở thẳng màn chọn khung (§8) tại khung đó.

## 8. Màn chọn khung dùng chung (D8)

Một màn cho **mọi** chuỗi cùng khoảnh khắc: burst PhotoKit, Same moment, focus stack, và lối ⋯ ▸ Choose Frames… từ viewer.
Thay phần màn hình của FS-02.05 §4; luật xoá burst của FS-02.05 §2 (đường chính, đường chép chờ §9 máy thật) giữ nguyên.

- **Khung lớn** chiếm mọi chiều cao còn lại (bỏ khoảng đen thừa; trên iPhone 17 khung lớn cao ≥ 520pt).
- **Dải phim** ở đáy, thumbnail **56pt**, khung đang xem viền accent; khung có *Eyes closed* hoặc *Soft* có **chấm đỏ 6pt**
  góc trên — chấm là "khung yếu", không phải "sẽ xoá". Khung đã chọn giữ có tick.
- **Zoom đồng bộ**: pinch/pan trên khung lớn rồi vuốt dải phim → khung mới mở **cùng vùng, cùng tỉ lệ**. Nút **Zoom to face**
  (chỉ khi khung có khuôn mặt đã lưu) nhảy tới khuôn mặt lớn nhất ở tỉ lệ 100%; chạm lại → khuôn mặt kế.
- Khung lớn có chip điểm (§6): *Sharpest · eyes open*, *Eyes closed*, *Soft*.
- **Chọn giữ**: nút vòng **44pt** ở góc dưới phải khung lớn (A6), hoặc chạm đôi khung lớn.
- Đáy (vùng ngón cái): **Keep picks, remove the rest** (đỏ, số trong chữ: *"Keep 3, remove 21"*) · **Done** (đóng, giữ
  lựa chọn làm dấu của nhóm). Không chọn gì: nút đỏ mờ với dòng *"Choose at least one frame to keep"*. Nút đóng nằm ở
  đáy, vuốt xuống để đóng (A6); không có nút X ở góc trên trái.
- Lựa chọn trong màn này **là** dấu của nhóm (06b §1): đóng màn thì thẻ hiện đúng các khung đã đánh dấu.
- **iPad**: thêm chế độ **Survey** dùng lại từ Compare ([FS-01.08c](../FS-01-library/08c-compare-viewer-mode.md)): 2–6 khung
  cùng lúc, zoom đồng bộ giữa các ô. iPhone không có Survey.
- **Duo**: màn trong và màn ngoài đều có đủ màn chọn khung (người dùng 2026-10-17). Màn ngoài: khung lớn trong 382×678
  (sau rail 84), dải phim 48pt.
  **Duo màn trong 951×669 nằm ngang**: dải phim **dọc bên phải 72pt** (thumbnail 56pt), khung lớn dùng trọn chiều cao
  (người dùng 2026-10-17); board `DI_BurstFrames`.

## 9. Not duplicates và Ignored (A1)

- **Not duplicates** trên một nhóm: nhóm biến khỏi danh sách và mọi số đếm; lưu ở `duplicate_review` (§10), sống qua tắt
  app và Check Again.
- Nhóm đó sau này có **thêm** ảnh mới → hiện lại với dòng *"New photo since you marked these as not duplicates"*; ảnh cũ
  không bị đánh dấu.
- ⋯ ▸ **Ignored (N)**: danh sách nhóm đã bỏ qua, mỗi dòng có **Show again**.

## 10. Dữ liệu

Theo [BD-02 §1](../../01-basic-design/BD-02-database-design.md): kết quả quét đắt tiền và dữ liệu người dùng chọn **không**
nằm trong `photo_metadata`.

| Bảng | Giữ gì | Loại |
|---|---|---|
| `perceptual_hash` | dấu vân tay (v2) | kết quả quét |
| `duplicate_groups` | cache nhóm + **loại nhóm** + cờ bộ nguyên liệu | cache, gom lại được |
| `duplicate_quality` *(mới)* | id ảnh, ngày sửa, điểm nét, điểm mắt + độ tin cậy, % cháy/bệt, khung khuôn mặt chuẩn hoá, bù sáng EXIF, cờ "bản xuất" | kết quả quét đắt tiền |
| `duplicate_review` *(mới)* | dấu xoá theo id ảnh; nhóm Keep all; bản giữ người dùng chọn; Not duplicates (tập id thành viên) | dữ liệu người dùng |

- Dọn: dòng của một ảnh bị xoá khi PhotoKit báo ảnh đó đã xoá. `duplicate_review` **không** bị quét đối chiếu với
  `photo_metadata` (rỗng sau Clear Index, thiếu khi đang index hay `.limited`); Clear Index giữ nó, xoá `duplicate_quality`.
- Decode khoan dung: một dòng hỏng không làm mất cả danh sách dấu.

## 11. Chữ trên màn (A3, tiếng Anh Mỹ)

| v2 | v3 |
|---|---|
| Exact / Similar / Series / Bursts | Copies / Smaller copies / Look-alikes / Same moment / Screenshots / Source frames |
| Mark the other N | Remove the other N |
| Mark for Deletion / Unmark | Remove / Don't remove |
| Keep Only This | Keep just this one |
| Rescan | Check Again |
| Largest | Biggest file |
| Merge N Groups… | *(bỏ — Quick clean thay thế)* |
| 4 s apart / +4 s | within 4 seconds / 4 s later |
| N photos not scanned yet | N photos not checked yet / only in iCloud — will check on Wi-Fi |
| Select Frames… (viewer) | Choose Frames… |

## 12. Spike trên máy thật (trước khi code §6)

Theo intent: chạy trên iPhone thật với ảnh của người dùng, **không commit ảnh**, ghi số vào `docs/_intents/` như spike
panorama/HDR. Đo: (1) thời gian chấm 1.000 ảnh nhóm ở 512px; (2) tỉ lệ đúng của *Eyes closed* trên ≥ 200 khung burst
người dùng tự gán nhãn; (3) độ tin cậy Vision để đặt ngưỡng hiện nhãn mắt. Ngưỡng và số đo ghi lại vào §6.

**Fixture khuôn mặt** (người dùng 2026-10-17 cho phép tải ảnh mạng về test — ngoại lệ có chủ đích của luật "không ảnh
mặt người trong test"): chỉ ảnh có giấy phép mở (CC0 / public domain, ghi nguồn + giấy phép từng file), lưu **ngoài repo**
ở `~/Library/Caches/ShotDexFixtures/faces/` như fixture RAW, không commit, không đưa lên simulator dùng chung, không xuất
hiện trong ảnh chụp màn hình hay board. Test dùng chúng tự bỏ qua khi thư mục vắng. Mỗi lần tải: hỏi người dùng trước,
nêu tên file, nguồn, dung lượng.

## 13. Tiêu chí nghiệm thu

Dấu xoá, xoá, thừa hưởng, màn rộng: [06b §5](06b-duplicates-marks-merge-delete.md#5-tiêu-chí-nghiệm-thu). Ảnh dùng làm
fixture: tự sinh (mảng màu, chữ, nhiễu, mờ Gaussian); riêng AC-Q4 dùng fixture khuôn mặt giấy phép mở ngoài repo (§12).

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-G1 | (D4) A,B (cùng hash, 4032×3024, cùng giây); C (lệch 3 bit với A, 1600×1200, thiếu ngày EXIF); G,H (cùng hash, 3000×2000, cùng giây, khác cảnh); D,E,F (cách nhau 2 s, lệch 12–15 bit) | gom nhóm | {A,B,C} một nhóm Smaller copies; {G,H} Copies; {D,E,F} Same moment; không ảnh nào ở hai nhóm | `DuplicateGrouperTests.everyPhotoLandsInExactlyOneKind` ✅ |
| AC-G2 | (D4) 20 ảnh cùng hash, cùng kích thước, chụp cách nhau 3 s (tripod) | gom nhóm | **không** có nhóm Copies; 20 ảnh là một nhóm Same moment | `DuplicateGrouperTests.tripodSequenceIsNotCopies` ✅ |
| AC-G3 | (D4) hai ảnh lệch 4 bit, tiêu cự 24mm và 35mm | gom nhóm | không nhóm nào chứa cả hai | `DuplicateGrouperTests.differentFocalLengthNeverGroups` ✅ |
| AC-G4 | (D5) 5 khung cách nhau 0.3 s, cùng 50mm, bù sáng −2/−1/0/+1/+2 | gom nhóm, mở danh sách | nhóm là Bracket: thẻ *Bracket · 5 frames · ±2 EV*, có *Merge to HDR* và *Not duplicates*, không có nút đỏ; "~GB to free" ở dải trên và màn tóm tắt không tính 5 khung | `DuplicateSourceSetTests.bracketIsSourceFrames` ✅ + ảnh sim `duplicates-v3-source.json` ⚠️ chưa có |
| AC-G5 | (D5) như AC-G4 | chạm *Merge to HDR* | màn HDR (FS-01.11) mở với đúng 5 id; huỷ ở đó → thẻ Bracket không đổi, 0 dấu | ⚠️ chưa có — route `duplicates-v3-source.json` |
| AC-Q1 | (D1) nhóm Look-alikes 3 ảnh tự sinh cùng nội dung: P nét, Q mờ Gaussian σ=3, R mờ σ=1.5; Q là file lớn nhất | chấm xong, mở thẻ | bản giữ là P với chip *Sharpest*; Q có chú thích *Soft*; không chip nào ghi *Biggest file* | `DuplicateQualityTests.sharpestBeatsBiggestFile` ✅ |
| AC-Q2 | (D1) như AC-Q1 nhưng chưa chấm (đang *Checking sharpness…*) | mở thẻ | bản giữ theo D3 (Q), chip *Biggest file*; không chỗ nào có *Sharpest* | `DuplicateReviewTests.unscoredGroupSaysBiggestFile` ✅ |
| AC-Q3 | (D1) ảnh có 4% điểm ảnh 255 và bản giữ 0.2% | mở thẻ | ảnh đó có chú thích *Blown highlights* | `DuplicateQualityTests.clippingCaption` ✅ |
| AC-Q4 | (D1) bộ fixture 20 khung có người (ảnh tải từ nguồn giấy phép mở, xem §12), 3 khung mắt nhắm | chấm xong, mở màn chọn khung | 3 khung có chấm đỏ trên dải phim và chip *Eyes closed*; bản giữ đề xuất có *Eyes open* | `DuplicateQualityTests.eyesClosedOnLicensedFaceFixtures` (bỏ qua khi thiếu fixture) + `DuplicateReviewTests.eyesClosedRanksBelowEyesOpen` (điểm giả lập) ✅; fixture ⚠️ chưa có |
| AC-Q5 | (D1, NF-01) 1.000 ảnh trong nhóm, đang chấm | người dùng cuộn danh sách / chạm Cancel | pass chấm nhường khi cuộn (không khung nào > 16 ms do pass này); Cancel dừng trong ≤ 0.5 s, điểm đã chấm được giữ | `DuplicateQualityPassTests.cancelKeepsWhatWasScored` ✅ (huỷ ≤ 0.5 s, điểm giữ); nhường khi cuộn ⚠️ chưa có — Instruments trên máy thật |
| AC-S1 | (D2) cache: 212 nhóm Copies/Smaller copies (1.2 GB), 100 nhóm cần chọn (3.0 GB), 6 bracket | mở Duplicates | màn tóm tắt: *~4.2 GB to free*, thẻ *Quick clean 212 copies · 1.2 GB*, thẻ *Choose yourself 100 groups · 3.0 GB*, thẻ *Source frames 6 brackets*; đúng một nút nền accent (*Review 212…*); 0 dấu | ⚠️ chưa có — `duplicates-v3-summary.json` |
| AC-S2 | (D2, A2) như AC-S1; 212 nhóm Quick clean có 230 bản có thể xoá, 3 bản trong đó là favorite / đã chỉnh / trong album "Client" | *Review 212…* → bỏ tick 5 nhóm (chứa 6 bản khác) → *Select …* | nút chân sheet ghi *Select 221 photos* (230 − 6 − 3 ảnh A2); sau khi chạm: đúng 221 ảnh mang dấu, 3 ảnh A2 không mang dấu, dòng của chúng ghi *1 kept: favorite* / *edited* / *in album Client*; chưa ảnh nào vào Recently Deleted | `DuplicateReviewTests.quickCleanNeverPicksProtectedPhotos` ⚠️ + route ⚠️ chưa có |
| AC-S3 | (D2) như AC-S1 | *Review 212…* → Cancel | 0 dấu, không thanh xoá | ⚠️ chưa có |
| AC-L1 | (D4, A6) danh sách có Copies 3, Look-alikes 5, Same moment 2, không Screenshot | mở *Choose yourself* | hàng lọc *All · Copies · Look-alikes · Same moment* (không Screenshots); chạm từng viên thì các viên còn lại không đổi vị trí x (±1pt) | ⚠️ chưa có — dump `duplicates-v3-filter.json` |
| AC-L2 | (A7) 3 nhóm với khoảng cách điểm 0.6 / 0.1 / 0.3 | sort *Easiest first* | thứ tự 0.6, 0.3, 0.1; Back rồi vào lại vẫn *Easiest first* | `DuplicateReviewTests.easiestFirstOrdersByScoreGap` ⚠️ chưa có |
| AC-C1 | (D7) thẻ 5 ảnh chưa dấu | chạm giữa một bản sao | viewer của nhóm mở tại ảnh đó; 0 dấu | ⚠️ chưa có |
| AC-C2 | (D7) như AC-C1 | chạm vòng góc trên phải của một bản sao | ảnh đó mang dấu, thanh xoá *1 marked*; vùng chạm vòng ≥ 44×44pt trong dump | ⚠️ chưa có |
| AC-C3 | (D7) viewer nhóm mở ở bản sao X | chạm *Keep this* | về thẻ, X là bản giữ (2×2) với nhãn Keep; bản giữ cũ thành bản sao | ⚠️ chưa có |
| AC-C4 | (D9) nhóm 52 ảnh, iPhone 17 | mở danh sách | thẻ cao ≤ 1 màn hình: bản giữ + 1 hàng + *Show all 51*; *Remove the other 51*, *Keep all*, *Compare* nằm trong viewport khi bản giữ ở giữa màn | ⚠️ chưa có — `duplicates-v3-large.json` |
| AC-C5 | (D9) thẻ 9 ảnh | chạm *Remove the other 8* | 8 ô viền đỏ hiện ≥ 0.5 s trước khi thẻ thu thành *Keeping 1 · deleting 8*; thẻ kế không nhảy quá 1pt so với trước khi thu (đo vị trí) | ⚠️ chưa có |
| AC-C6 | (D10) nhóm: K gốc 6240px; C1 bản WhatsApp 1600px thiếu EXIF; C2 bản xuất Lightroom 2048px (Software=Lightroom); C3 trong album "Client" | mở thẻ | C2 là **bản giữ** (bản xuất đã chỉnh); K có *Not edited*; C1 *Smaller copy* / *WhatsApp*; C3 dòng 2 *In album: Client*; không ô nào có chữ dạng `6240×4160` | `DuplicateReviewTests.exportOfAnEditIsTheKeeper`, `.captionSaysWhatTheCopyLacksInWords` ⚠️ chưa có |
| AC-C7 | (D10) nhóm 3 ảnh khác bù sáng (−1, 0, +1) nhưng không đủ luật bracket (cách nhau 40 s) | mở thẻ | mỗi bản sao có thông số khác nhau *−1 EV* / *+1 EV*; không thông số nào giống nhau trong nhóm được ghi | ⚠️ chưa có |
| AC-F1 | (D8) Same moment 24 khung | chạm *Choose frames*, zoom 3× vào góc trên trái, vuốt sang khung 5 | khung 5 hiện ở 3×, cùng vùng (lệch ≤ 2% bề rộng); khung lớn cao ≥ 520pt trên iPhone 17; thumbnail 56pt | ⚠️ chưa có — `duplicates-v3-frames.json` |
| AC-F2 | (D8) như AC-F1, giữ 3 khung | chạm *Keep 3, remove 21*, xác nhận hệ thống | đúng 21 ảnh vào Recently Deleted; thẻ nhóm biến mất (còn 3 ảnh vẫn là Same moment thì thẻ còn 3) | ⚠️ chưa có |
| AC-F3 | (D8) chưa chọn khung nào | nhìn đáy màn | nút đỏ mờ + *Choose at least one frame to keep*; không có nút X ở 1/3 trên màn | ⚠️ chưa có |
| AC-F4 | (D8) iPad 1376×1032 | mở màn chọn khung, bật Survey 4 khung, zoom | 4 khung cùng zoom/vùng | ⚠️ chưa có |
| AC-F5 | (D8) burst PhotoKit 6 khung (`-ShotDexFakeBursts`) | mở từ viewer ⋯ ▸ *Choose Frames…* | cùng màn chọn khung như từ Duplicates | ⚠️ chưa có |
| AC-N1 | (A1) nhóm Look-alikes 2 ảnh | *Not duplicates* → tắt app → mở → *Check Again* | nhóm không hiện; ⋯ ▸ *Ignored (1)* có nhóm đó; *Show again* → nhóm về danh sách | `DuplicateReviewStoreTests.dismissalSurvivesRegroup` ⚠️ chưa có |
| AC-N2 | (A1) như AC-N1, sau đó thêm ảnh thứ 3 giống hai ảnh kia | *Check Again* | nhóm hiện lại 3 ảnh với dòng *New photo since you marked these as not duplicates*; 0 dấu | ⚠️ chưa có |
| AC-P1 | (A5) quyền `.limited`, thấy 1.240 ảnh | mở Duplicates | banner *ShotDex can see 1,240 of your photos* + *Settings* | ⚠️ chưa có |
| AC-P2 | (A5) quyền bị từ chối | mở Duplicates | banner *ShotDex can't see your photos* + *Settings*; *Check Again* mờ kèm lý do; không lượt quét nào chạy | ⚠️ chưa có |
| AC-P3 | (A4) quét 38.000 ảnh, sau lô đầu đã có 40 nhóm | nhìn màn trong lúc quét | *Scanning 1,200 of 38,000 · 40 found so far*; 40 nhóm đã mở được; *Cancel* màu accent | ⚠️ chưa có |
| AC-P4 | (A4) máy tắt mạng, 148 ảnh chỉ có trên iCloud | quét xong | dòng *148 photos only in iCloud — will check on Wi-Fi*; không yêu cầu mạng nào | ⚠️ chưa có |
