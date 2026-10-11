# FS-06.06b — Duplicates: dấu xoá, Merge, Delete, màn rộng

`FS-06.06b` · `Features/Duplicates/DuplicatesModel.swift` · `DuplicateReviewSession` · `DuplicatesScreen` · cập nhật 2026-10-04

**Một câu:** công sức đánh dấu không mất vì đổi tab, không nhóm nào bị xoá hết bản, và không gì được ghi vào
Photos trước khi người dùng xác nhận. Phần đầu (hash, ba mức, màn hình): [FS-06.06](06-duplicates.md).

Board: `PH_Duplicates` · `PH_DuplicatesPinched` · `IP_Duplicates` · `DI_Duplicates` · `DC_Duplicates` (v2).

## 1. Dấu xoá

- **Dấu sống trong bộ nhớ suốt phiên app** (D2): qua đổi mức, Back rồi vào lại, đổi tab, app ra nền rồi về. Mất
  khi app bị tắt hẳn (kể cả hệ thống tắt lúc nền). **Không ghi xuống đĩa.** Cùng sống như vậy: nhóm đã Keep all, nhóm
  đã thu gọn, bản giữ người dùng chọn bằng Keep Only This (`DuplicateReviewSession`, giữ ở `AppDependencies`).
- Nạp lại cache **không cắt** dấu. Dấu của ảnh đã biến khỏi thư viện chỉ bị bỏ lúc đếm và lúc xoá.
- Thanh dưới đếm và xoá **chỉ dấu thuộc các nhóm của mức đang xem**; dấu ở mức khác vẫn giữ nguyên sau khi
  xoá. *Vì con số trên nút phải khớp đúng những ô đang thấy.*
- **Chặn đánh dấu ô cuối cùng** của một nhóm: chạm ô chưa đánh dấu duy nhất còn lại thì ô không đổi, máy rung
  cảnh báo, dưới thẻ hiện *"Keep at least one photo in this group."* trong 3 s; mục Mark for Deletion của ô đó mờ.
  *Mark the other N* không bao giờ đánh dấu bản giữ, nên không chạm cổng này.
- Một ảnh có thể nằm trong nhóm của hai mức, nên dấu đặt ở mức kia có thể làm đầy một nhóm ở mức này. Thẻ đó
  ghi *"All copies marked — nothing will be kept"*; bấm Delete thì hiện alert nói số nhóm như vậy, **không** mở
  hộp xoá của hệ thống, không xoá ảnh nào.
- Compare mở từ Duplicates giữ cùng cổng chặn: nút **Reject** của ảnh chưa Reject cuối cùng mờ, bấm thì rung cảnh báo +
  *"Keep at least one photo in this group."* (FS-01.08c AC-15). Reject ở đó là cờ thật của FS-01.12: mở Compare thì dấu
  của nhóm thành Reject, đóng lại thì ô của nhóm theo cờ — Reject = đã đánh dấu, bỏ Reject = bỏ dấu (plan K2).

## 2. Merge

- **Merge chỉ có ở Exact** (D1). Ở Similar, Series và Bursts menu ⋯ **không có** mục này (ẩn, không mờ).
  *Vì ở Similar/Series bản giữ không cùng khoảnh khắc với bản sao, chép ngày chụp sang là sai.*
- Mục menu ghi *"Merge N Groups…"* (N = số nhóm Exact). Chạm → **alert hai nút** (không dùng action sheet: iOS 26
  ẩn Cancel ở đó): tiêu đề *"Merge N Groups?"*, lời *"Keeps one copy in each group and marks M photos for
  deletion. The kept copy takes the favorite, location and earliest date of its copies — saved to Photos now.
  Nothing is deleted until you tap Delete."* · **Merge** · **Cancel**. Cancel: không ghi, không đánh dấu.
- **Bản giữ** (D3): bản **đã chỉnh** → bản **favorite** → **file lớn hơn** → **nhiều pixel hơn**. Trước khi chọn,
  app đọc cờ đã chỉnh của mọi ảnh trong các nhóm Exact; lúc đọc và lúc ghi, dải chọn, Rescan, Merge, Delete mờ.
- Bản giữ **thừa hưởng** thứ nó thiếu: cờ favorite, toạ độ, **ngày chụp sớm nhất** (bản lưu lại mang ngày lúc lưu
  lại). Theo từng nhóm: ghi vào Photos xong **mới** đánh dấu các bản còn lại.
  *Vì hỏng giữa chừng phải để lại thư viện còn trùng, không để lại bản giữ mất dữ liệu.*
- **Lỗi không bị nuốt**: nhóm ghi hỏng thì không bị đánh dấu, các nhóm khác chạy tiếp; xong hiện alert *"Couldn't
  Merge K Groups"* với lý do của lỗi đầu tiên và câu *"Their photos are not marked."* Ca thường gặp: quyền
  `.limited` mà bản giữ nằm ngoài tập đã chọn.
- Merge xong mỗi nhóm thành công: bản giữ (D3) thành bản giữ của thẻ, các bản kia mang dấu, thẻ **thu gọn** ("Keeping 1 ·
  deleting N", FS-06.06 §7.4).
- Clear Selection (⋯) bỏ dấu và quyết định của mức đang xem, **không** hoàn tác phần đã ghi vào Photos — alert đã nói
  "saved to Photos now".
- Ngoài ba thứ thừa hưởng, **không có bước hợp nhất album hay metadata nào khác**. "Nằm trong album nào" chưa làm.

## 3. Delete

- Thanh dưới nổi (FS-06.06 §7.6): viên kính *"N marked · X MB"* / *"Recently Deleted for 30 days"* + viên đỏ cao 48
  *"Delete N"* (VoiceOver: "Delete N photos").
- Hệ thống hỏi xác nhận; huỷ thì **giữ dấu**. Xong thì xoá dòng dữ liệu tương ứng, cập nhật nhóm tại chỗ (nhóm
  còn một ảnh thì biến mất) và cập nhật số nhóm đã lưu. Phạm vi và cổng chặn: §1.

## 4. Màn rộng

- Regular width: thẻ xếp **cột co giãn, tối thiểu 400pt**, khe 16, kiểu **xếp gạch** (mỗi thẻ vào cột đang ngắn nhất
  theo thứ tự sắp xếp, nên dòng đã thu gọn không để lỗ bên cạnh thẻ đầy) (Z2). Bề rộng nội dung 1344 (iPad ngang) → 3
  cột 437pt; 1000 (iPad dọc) → 2 cột 492pt; 835 (Duo inner, sau rail 84) → 2 cột ~410pt.
- Compact (iPhone, Duo cover): một cột.
- Bản sao mỗi hàng mặc định 3 ở regular, 2 ở compact; pinch đổi (FS-06.06 §7.5).
- Thanh dưới: regular là một cụm đứng giữa (viên kính vừa chữ + Delete), compact trải hết bề ngang nội dung. Thanh dưới
  nằm trên tab bar? Không — tab bar ẩn khi có dấu, ở cả iOS 26 và tab bar tự vẽ trước 26.

## 5. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | (D1) cache có 12 nhóm Exact, 30 nhóm Similar, 8 Series | mở ⋯ lần lượt ở Exact, Similar, Series, Bursts | Exact có *Merge 12 Groups…*; ba mức kia không có mục Merge nào (kể cả mờ) | ⚠️ chưa có — đề xuất script `duplicates-merge.json` |
| AC-2 | (D1) như AC-1, ở Exact; 12 bản giữ có favorite/toạ độ/ngày ghi lại trước | chạm *Merge 12 Groups…* | alert *Merge 12 Groups?* với lời ở §2, nút Merge + Cancel; favorite, toạ độ, ngày của 12 bản giữ trong Photos chưa đổi | ⚠️ chưa có |
| AC-3 | (D1) alert của AC-2 đang mở | chạm Cancel | 0 ảnh được đánh dấu, không có thanh dưới; 12 bản giữ không đổi gì trong Photos | ⚠️ chưa có |
| AC-4 | (D1) nhóm Exact {A 4,1 MB, không favorite, không toạ độ, ngày 2024-05-02; B 3,9 MB, favorite, có toạ độ, ngày 2024-05-01}, không bản nào đã chỉnh | Merge → chạm Merge trong alert | A được giữ: favorite bật, toạ độ của B, ngày 2024-05-01; B mang dấu; thẻ thu gọn *Keeping 1 · deleting 1*; thanh dưới *Delete 1*; chưa ảnh nào vào Recently Deleted | ⚠️ chưa có |
| AC-5 | (D3) nhóm {A đã chỉnh 3,2 MB; B favorite 4,0 MB; C 4,5 MB}; biến thể 2: A không chỉnh; biến thể 3: thêm B không favorite | chọn bản giữ | lần lượt giữ A, rồi B, rồi C | `DuplicateReviewTests.keeperIsEditedThenFavoriteThenLargerFile` ✅ |
| AC-6 | (D1) quyền `.limited`, 12 nhóm Exact, bản giữ của 1 nhóm nằm ngoài tập đã chọn | Merge → Merge | 11 nhóm mang dấu, nhóm kia không; alert *Couldn't Merge 1 Group* có lý do và *Their photos are not marked.* | ⚠️ chưa có |
| AC-7 | (D2) Similar, 6 ảnh đánh dấu trong 4 nhóm | chuyển sang Exact rồi về Similar | vẫn 6 ô mang dấu, thanh dưới *6 marked* + *Delete 6* | ⚠️ chưa có |
| AC-8 | (D2) như AC-7 | Back về Collections, sang tab Library, cho app ra nền 30 s, vào lại Duplicates | vẫn 6 ô mang dấu ở Similar | ⚠️ chưa có |
| AC-9 | (D2) như AC-7 | tắt hẳn app rồi mở lại Duplicates | 0 dấu, không có thanh dưới | ⚠️ chưa có |
| AC-10 | (D2) như AC-7, 1 trong 6 ảnh bị xoá bằng app Photos | quay lại Duplicates | thanh dưới *5 marked* + *Delete 5*; MB không tính ảnh đã mất | ⚠️ chưa có |
| AC-11 | (D2) nhóm 3 ảnh, 2 đã đánh dấu | chạm ô thứ 3 | ô không mang dấu; dưới thẻ hiện *Keep at least one photo in this group.*; thanh dưới vẫn *Delete 2*; giữ lâu ô đó thì Mark for Deletion mờ | ⚠️ chưa có |
| AC-12 | (D2) A, B cùng nhóm Exact và cùng một nhóm Similar 3 ảnh; ở Similar đánh dấu A, B | chuyển sang Exact, chạm Delete | thẻ Exact ghi *All copies marked — nothing will be kept*; alert nói 1 nhóm; hộp xoá hệ thống không mở; 0 ảnh bị xoá | ⚠️ chưa có |
| AC-13 | (D3) nhóm 3 ảnh: A favorite + đã chỉnh, B RAW+JPEG, C Live Photo | mở thẻ | A có tim + glyph đã chỉnh, B có RAW, C có Live; glyph cao 12pt, ba ô cùng hàng thẳng đáy; VoiceOver của A đọc "favorite, edited" | ⚠️ chưa có |
| AC-14 | (D3) như AC-13, máy tắt mạng, A chỉ có trên iCloud (Optimize Storage) | mở thẻ | glyph của A giống AC-13; không có yêu cầu mạng nào | ⚠️ chưa có |
| AC-15 | (Q8) lượt quét đang ở *Scanning 400 of 1000* | nhìn thanh tiến độ, rồi chạm Cancel | Cancel màu accent, không đỏ; thanh biến mất, dòng trạng thái *600 photos not scanned yet.* | ⚠️ chưa có |
| AC-16 | (F2) index đang chạy ở 34% | mở Duplicates | dưới dải chọn có *Still reading photo info · 34%*; không chỗ nào có chữ *Index your library* | ⚠️ chưa có |
| AC-17 | (F2) như AC-16, màn đang mở | index chạy xong | dòng tiến độ biến mất; số ảnh chưa quét cập nhật mà không cần rời màn | ⚠️ chưa có |
| AC-18 | (Z2) 6 nhóm, 2 ảnh mang dấu; iOS 26.5 và 18.6 | mở Duplicates trên iPad 1376×1032, 1032×1376, Duo inner 951×669 | thẻ ra 3 cột 437pt / 2 cột 492pt / 2 cột ~410pt (±1pt), 3 bản sao mỗi hàng; thanh dưới là cụm giữa màn; tab bar ẩn (cả tab bar tự vẽ pre-26) | ⚠️ chưa có — đề xuất `Tools/design-board compare` trên `IP_Duplicates`, `DI_Duplicates` |
| AC-19 | (Z2) như AC-18 | mở trên iPhone 402×874 và Duo cover 466×678 | thẻ một cột, 2 bản sao mỗi hàng; thanh dưới trải hết bề ngang nội dung (370pt / 350pt) | ⚠️ chưa có — `PH_Duplicates`, `DC_Duplicates` |
| AC-20 | (D2) ở Similar đánh dấu 6 ảnh, 2 trong số đó cũng nằm trong nhóm Exact | chuyển sang Exact, chạm Delete, xác nhận hộp xoá của hệ thống | thanh dưới trước khi xoá ghi *Delete 2*; đúng 2 ảnh vào Recently Deleted; về Similar còn 4 ô mang dấu, *Delete 4* | ⚠️ chưa có |
| AC-21 | (V2, Q2) nhóm Similar 4 ảnh mở trong Compare, 1 khung mang dấu | chạm nút đỏ, xác nhận | Compare ở lại với 3 khung; về Duplicates thẻ còn 3 ảnh. Biến thể quyền `.limited`, ảnh ngoài tập đã chọn: Compare tự hiện alert lỗi, khung còn dấu, 0 ảnh bị xoá | ⚠️ chưa có |

### Thẻ quyết định v2 (FS-06.06 §7)

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-V1 | nhóm Similar 5 ảnh: K đã chỉnh + RAW 18,9 MB; bản sao không chỉnh / JPEG / 3120×2080 / 1920×1280 | mở Duplicates trên iPhone 17 | K lớn bên trái có *Keep*, chip *Edited* · *RAW*; bản sao ghi *Not edited*, *JPEG only*, *3120×2080*, *1920×1280*; đầu thẻ *5 photos* · *~X MB to free* | `DuplicateReviewTests.reasonsOnlyNameWhatTheCopiesLack`, `.differenceSaysWhatTheCopyLacksFirst` ✅ + ảnh ⚠️ chưa có (sim không có ảnh đã chỉnh+RAW) |
| AC-V2 | thẻ 5 ảnh chưa dấu | chạm *Mark the other 4* | 4 bản sao mang dấu, bản giữ không; thẻ thu thành dòng 56pt *Keeping 1 · deleting 4*; dải trên *Reviewed 1 of N groups*; thanh dưới *4 marked* + *Delete 4* | ⚠️ chưa có — ảnh `duplicates-v2` |
| AC-V3 | dòng thu gọn của AC-V2 | chạm dòng | thẻ mở lại, nút trái đọc *Unmark*; chạm *Unmark* → 0 dấu, thanh dưới biến mất, *Reviewed 0 of N* | ⚠️ chưa có |
| AC-V4 | thẻ 2 ảnh | chạm *Keep all* | thẻ thu thành *Keeping all 2* · *nothing to delete*; không có dấu nào; *Reviewed* tăng 1 | ⚠️ chưa có |
| AC-V5 | 12 nhóm, sort *Most space first* | đổi sang *Oldest first*, Back, vào lại | thẻ đầu là nhóm có ảnh mới nhất cũ nhất; menu vẫn *Oldest first* | `DuplicateReviewTests.sortOrdersBySpaceThenDate` ✅ (thứ tự) + ảnh ⚠️ chưa có |
| AC-V6 | iPhone, 2 bản sao mỗi hàng | pinch chụm vào một bậc | 3 bản sao mỗi hàng, HUD *3 per row* hiện rồi tắt sau 1 s; Back rồi vào lại vẫn 3 | `DuplicateReviewTests.cardMetricsMatchTheBoards` ✅ (hình học) + thao tác ⚠️ chưa có (sim không pinch được bằng ui-drive) |
| AC-V7 | nhóm Series 4 khung | mở mức Series | không có *Keep*, chip, *Mark the other*, *~MB to free*; 4 khung một lưới, caption *+0 s* … | ⚠️ chưa có |
| AC-V8 | danh sách cuộn xuống 2000pt | nhìn dải trên | dải chọn, sắp xếp, *Reviewed*, Rescan vẫn ở trên cùng, thẻ cuộn bên dưới | ⚠️ chưa có |
| AC-V9 | 2 ảnh mang dấu, iOS 26.5 | nhìn đáy màn | tab bar ẩn; viên đỏ *Delete 2* cao 48; bỏ hết dấu → tab bar hiện lại | ⚠️ chưa có |

