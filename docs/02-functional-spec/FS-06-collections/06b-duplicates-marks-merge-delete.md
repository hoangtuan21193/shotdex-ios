# FS-06.06b — Duplicates: dấu xoá, xoá, thừa hưởng, màn rộng

`FS-06.06b` · `Features/Duplicates/DuplicatesModel.swift` · `DuplicateReviewSession` · `DuplicateReviewStore` · `DuplicatesScreen`
· cập nhật 2026-10-17 (v3)

**Một câu:** công sức chọn không mất kể cả khi app bị tắt, không nhóm nào bị xoá hết bản, người dùng thấy đúng những gì
sắp xoá, và ảnh được giữ nhận lại những gì bản bị xoá đang có. Phần đầu (quét, loại nhóm, chấm điểm, màn hình):
[FS-06.06](06-duplicates.md).

Board: `PH_Duplicates` · `PH_DuplicatesSummary` · `PH_DuplicatesPinched` · `IP_*` · `DI_*` · `DC_*` (v3, 2026-10-17).

## 1. Dấu xoá

- **Dấu được lưu trên máy** (D12, thay D2 của v2 ngày 2026-10-04): sống qua Back, đổi tab, app ra nền **và app bị tắt**,
  tới khi người dùng xoá hoặc bỏ dấu. Cùng sống như vậy: nhóm Keep all, bản giữ người dùng chọn (Keep this / Keep just
  this one), nhóm đã thu gọn, Not duplicates. Bảng `duplicate_review` ([FS-06.06 §10](06-duplicates.md)); không ghi vào
  `photo_metadata`.
- Ảnh bị xoá ở nơi khác (app Photos) thì dấu của nó **tự rơi** khi PhotoKit báo, và không bao giờ được đếm hay xoá.
- Check Again (gom lại) **không cắt** dấu: dấu theo id ảnh, không theo nhóm.
- v3 không còn ba mức nên **một ảnh chỉ ở một nhóm**; thanh xoá đếm **mọi** dấu, ở mọi loại. Hàng lọc đang chọn chỉ đổi
  thẻ nào hiện, không đổi số trên nút. Viên kính ghi *"37 selected · 210 MB"* và chạm được (§3).
- **Chặn đánh dấu ô cuối cùng** của một nhóm (giữ v2): ô không đổi, rung cảnh báo, dưới thẻ *"Keep at least one photo in
  this group."* 3 s; mục Remove của ô đó mờ. Màn chọn khung và Compare giữ cùng cổng.
- **Ảnh được bảo vệ** (favorite, đã chỉnh, trong album người dùng tạo — [FS-06.06 §1](06-duplicates.md)): Remove the other N
  và Quick clean bỏ qua chúng; người dùng tự chạm vòng thì được đánh dấu như ảnh khác.

## 2. Thừa hưởng (thay Merge của v2)

v2 có ⋯ ▸ *Merge N Groups…* ghi favorite/toạ độ/ngày vào Photos **ngay** khi bấm, trước khi xoá. v3 bỏ mục đó: Quick clean
([FS-06.06 §7.2](06-duplicates.md)) thay phần "đánh dấu cả loạt", và việc thừa hưởng chuyển vào **chính lần xoá** (D11):

- Khi xoá, với mỗi nhóm có bản bị xoá, **bản giữ** của nhóm (bản không mang dấu đứng đầu theo thứ hạng) nhận:
  - **album**: được thêm vào mọi album người dùng tạo mà một bản bị xoá đang ở (album thông minh, album hệ thống, album
    chia sẻ: bỏ qua);
  - **favorite**: bật nếu một bản bị xoá là favorite;
  - **toạ độ**: nếu bản giữ không có và một bản bị xoá có;
  - **ngày chụp sớm nhất**: **chỉ ở Copies và Smaller copies** (cùng khoảnh khắc thật); Look-alikes / Same moment không
    chép ngày.
- Nhóm còn ≥ 2 bản không mang dấu: không có "bản giữ" duy nhất → không thừa hưởng gì (người dùng đang giữ nhiều khung).
- Thừa hưởng và xoá đi **trong cùng một khối thay đổi** của thư viện, sau **một** hộp xác nhận của hệ thống: người dùng huỷ
  → không có gì được ghi, không album nào đổi. Hỏng → không gì đổi, alert *"Couldn't delete N photos"* + lý do của lỗi
  đầu tiên, dấu được giữ.
  **Chưa đo** PhotoKit có huỷ cả khối khi người dùng bấm Don't Allow không. Nếu không nguyên tử: **xoá trước, thừa hưởng
  sau** khi xoá thành công (người dùng 2026-10-17) — huỷ xoá thì không gì đổi; thừa hưởng lỗi thì alert, ảnh đã xoá vẫn
  nằm trong Recently Deleted. Đo ở bước Build, ghi kết quả vào đây.
- Quyền `.limited` mà bản giữ hoặc album nằm ngoài tập đã chọn: nhóm đó **không** thừa hưởng phần không ghi được, phần
  còn lại vẫn chạy; sau khi xoá, thông báo thêm dòng *"Albums couldn't be updated for 2 photos"*.

## 3. Xoá (D11)

- **Thanh dưới nổi** (giữ hình học v2: viên kính + viên đỏ cao 48, tab bar ẩn khi có dấu):
  - viên kính dòng 1 *"37 selected · 210 MB ›"*, dòng 2 khi có: *"2 are in albums · kept photo joins them"*, ngược lại
    *"Recently Deleted keeps them 30 days"*;
  - viên đỏ *"Delete 37"* (VoiceOver: "Delete 37 photos").
- **Chạm viên kính** → sheet *"37 Selected"*: lưới ảnh sắp xoá nhóm theo nhóm, mỗi ảnh có vòng để bỏ dấu; đầu mỗi nhóm
  là bản giữ nhỏ + *"keeps 1"*. Chân sheet **Delete 37** (cùng hành động với viên đỏ). Số trên viên đỏ, trong sheet và
  trong hộp xác nhận của hệ thống **luôn bằng nhau** (người dùng app khác than đúng chỗ này).
- Chạm Delete → hộp xác nhận của hệ thống; huỷ → **giữ dấu**, không gì đổi.
- Xong:
  - thông báo nổi ở đáy 5 s (thay thanh xoá): *"37 photos moved to Recently Deleted"* / *"210 MB freed · kept for 30
    days"* + nút **Open Photos** (mở app Photos); rung `.success`;
  - nhóm cập nhật tại chỗ, nhóm còn một ảnh biến mất, dòng của ảnh đã xoá khỏi cache và `duplicate_review`;
  - **không có Undo**: app bên thứ ba không khôi phục được từ Recently Deleted; thông báo nói ảnh nằm đâu thay vì hứa.
- **Hết nhóm** ở một loại: màn tóm tắt / hàng lọc cập nhật; hết mọi nhóm → *"All reviewed · 1.4 GB freed today"* + gợi ý loại
  còn nhóm (nếu có).

## 4. Màn rộng và Duo

- Danh sách: regular width giữ v2 — cột co giãn tối thiểu 400pt, khe 16, xếp gạch (Z2): iPad ngang 3 cột 437pt, dọc 2 cột
  492pt, Duo trong (835 sau rail) 2 cột ~410pt. Compact (iPhone, Duo ngoài): một cột.
- **Màn tóm tắt**: regular width hai thẻ Quick clean / Choose yourself **cạnh nhau**, tối đa 720pt giữa màn; compact xếp dọc.
- Hàng lọc: regular width hiện đủ các viên không cuộn; compact cuộn ngang.
- Thanh dưới: regular là cụm giữa màn; compact trải hết bề ngang nội dung.
- Sheet *Selected*: regular là form sheet 720pt; compact là sheet `large`.
- **Duo màn ngoài** (466×678, rail 84 bên phải): **đủ chức năng như iPhone** (người dùng 2026-10-17) — tóm tắt, danh sách,
  thẻ, viewer nhóm, màn chọn khung (FS-06.06 §8). Bề ngang nội dung 350pt (16 mỗi bên trong 382).

## 5. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-M1 | (D12) 6 ảnh mang dấu trong 4 nhóm | tắt hẳn app (kill), mở lại Duplicates ▸ Choose yourself | vẫn 6 ô mang dấu; thanh dưới *6 selected* + *Delete 6* | `DuplicateReviewStoreTests.marksSurviveRelaunch` ✅ + route `duplicates-v3-persist.json` ✅ (50 dấu còn sau khi app bị tắt và mở lại, iPhone 17 26.5) |
| AC-M2 | (D12) như AC-M1, 1 trong 6 ảnh bị xoá bằng app Photos | quay lại Duplicates | *5 selected* + *Delete 5*; MB không tính ảnh đã mất; dòng của ảnh đó không còn trong `duplicate_review` | `DuplicateReviewStoreTests.deletedPhotoDropsItsMark` ✅ |
| AC-M3 | (D12) Keep all trên nhóm A, bản giữ người dùng chọn ở nhóm B | kill app, mở lại | A vẫn thu gọn *Keeping all 2*; B vẫn có bản giữ người dùng chọn | `DuplicateReviewStoreTests.keepAllAndKeeperOverrideSurviveRelaunch` ✅ |
| AC-M4 | (giữ v2) nhóm 3 ảnh, 2 đã đánh dấu | chạm vòng của ô thứ 3 | ô không mang dấu; *Keep at least one photo in this group.*; *Delete 2* không đổi; giữ lâu ô đó thì Remove mờ | ⚠️ chưa có |
| AC-M5 | (D4) dấu: 3 ở Copies, 2 ở Look-alikes | hàng lọc chọn Look-alikes | thanh dưới vẫn *5 selected* + *Delete 5* (đếm mọi dấu) | ⚠️ chưa có |
| AC-M6 | (A2) nhóm 4 ảnh: K bản giữ, C1 favorite, C2 trong album "Client", C3 thường | chạm *Remove the other …* | nút ghi *Remove the other 1*; chỉ C3 mang dấu; dưới thẻ *2 kept: favorite, in album* | `DuplicateReviewTests.removeOtherSkipsProtected` ✅ |
| AC-D1 | (D11) 37 ảnh mang dấu, 2 trong album "Client" | nhìn thanh dưới | *37 selected · 210 MB ›* / *2 are in albums · kept photo joins them* / *Delete 37* | ⚠️ chưa có |
| AC-D2 | (D11) như AC-D1 | chạm viên kính, bỏ dấu 2 ảnh trong sheet | sheet và viên đỏ cùng ghi *Delete 35*; đóng sheet → thẻ của 2 ảnh đó không còn dấu | ⚠️ chưa có |
| AC-D3 | (D11) như AC-D2 | *Delete 35* → xác nhận hệ thống | hộp hệ thống nói 35 ảnh; đúng 35 ảnh vào Recently Deleted; thông báo *35 photos moved to Recently Deleted* + MB + *Open Photos* trong ≥ 4 s; rung success | ⚠️ chưa có — route `duplicates-v3-delete.json` + đếm Recently Deleted bằng `PHAssetCollection` smart album trên sim |
| AC-D4 | (D11) như AC-D1 | *Delete 37* → Don't Allow | 37 ảnh vẫn mang dấu; không album nào đổi; không thông báo | ⚠️ chưa có |
| AC-D5 | (D11) nhóm Copies {K không favorite, không album; C favorite, trong album "Client", có toạ độ, ngày sớm hơn} | đánh dấu C, Delete, xác nhận | K favorite, trong "Client", có toạ độ của C, ngày của C; C trong Recently Deleted | ⚠️ chưa có — test trên sim với album tự tạo |
| AC-D6 | (D11) nhóm Look-alikes cùng dữ liệu như AC-D5 | như AC-D5 | K favorite, trong "Client", có toạ độ; **ngày của K không đổi** | ⚠️ chưa có |
| AC-D7 | (D11) quyền `.limited`, album "Client" ngoài tập đã chọn | như AC-D5 | C vào Recently Deleted; K không vào "Client"; thông báo thêm *Albums couldn't be updated for 1 photo* | ⚠️ chưa có |
| AC-D8 | (D11) xoá hết nhóm của mọi loại | xoá xong | *All reviewed · X freed today* | ⚠️ chưa có |
| AC-W1 | (Z2, giữ v2) 6 nhóm, 2 dấu; iOS 26.5 và 18.6 | mở danh sách trên iPad 1376×1032, 1032×1376, Duo trong 951×669 | 3 cột 437pt / 2 cột 492pt / 2 cột ~410pt (±1pt); thanh dưới cụm giữa; tab bar ẩn (cả pre-26) | ⚠️ chưa có — `Tools/design-board compare` trên `IP_Duplicates`, `DI_Duplicates` |
| AC-W2 | (D2) có kết quả quét | mở Duplicates trên iPad ngang | hai thẻ Quick clean / Choose yourself cạnh nhau, khối ≤ 720pt giữa màn | ⚠️ chưa có — `IP_DuplicatesSummary` |
| AC-W3 | (người dùng 2026-10-17) Duo màn ngoài 466×678 | đi hết tóm tắt → danh sách → thẻ → màn chọn khung → xoá | mọi nút nằm trong 382pt bên trái rail; vùng chạm ≥ 44pt; không nút nào trong 40pt quanh góc bo trên | ⚠️ chưa có — `DC_Duplicates*`, `Tools/sim-shot … cover` |
