# FS-02.07 — Caption và keyword

`FS-02.07` · tier A (Info sheet, sheet sửa hàng loạt) + B/C (lưới, thanh chọn) · `Features/Library/MetadataPanel.swift`
· `Data/Sources/AssetMetadataReader.swift` · `App/AssetActionsCoordinator.swift` · `Domain/Indexing/IndexPipeline.swift`
· `Core/Models/SmartAlbumQuery.swift` · `Domain/Filtering/SearchIntentParser.swift` · cập nhật 2026-10-02

**Một câu:** trên iOS 27, sửa caption và keyword của một ảnh trong Info, của nhiều ảnh từ chế độ chọn; lọc,
tìm và smart album theo keyword. Dưới iOS 27 mọi thứ như hôm nay: chỉ đọc keyword nằm trong file.

Nguồn intent: [2026-09-30-user-wishes-research](../../_intents/2026-09-30-user-wishes-research.md) mục 14.
Bảng Info: [03](03-info-panel-and-metadata.md). Chế độ chọn: [FS-01.06](../FS-01-library/06-multi-select.md).

## 1. Người dùng cần gì

Sau buổi chụp, người chụp gắn `Hoi An`, `client-Lan`, `portfolio` cho 300 tấm rồi lọc lại theo đó. Hôm nay
ShotDex chỉ hiện keyword nằm sẵn trong file (ảnh xuất từ Lightroom), không sửa được và không lọc được.
Photos đã làm được việc này, còn một app quản lý thư viện thì chưa.

## 2. PhotoKit cho phép gì

Đọc header SDK iOS 27.1 ngày 2026-10-02. Mọi API dưới đây chỉ có từ iOS 27.

| Việc | Được không | Hệ quả |
|---|---|---|
| Đọc caption, keyword, tên file gốc | có, qua khối "metadata mở rộng" của asset | mặc định tải lười theo **từng asset**; có cờ tải sẵn khi fetch |
| Ghi caption | có; rỗng hoặc không giá trị = xoá | một change request mỗi asset, gộp trong **một** lần ghi |
| Thêm / bớt keyword | có, từng keyword; thêm cái đã có hay bớt cái không có thì **bỏ qua im lặng** | Undo an toàn khi chạy lặp |
| Lọc fetch theo keyword | **không** có predicate | lọc phải đi qua database của app |
| Quyền sửa | kiểm theo loại "thuộc tính" của asset | asset từ chối thì bỏ qua và nói ra (§6) |

- Keyword và caption **nằm trong thư viện Photos, không nằm trong file**. Ghi chúng không tải gì, không đổi
  pixel, không tạo phiên bản chỉnh sửa.
- Dưới iOS 27 không có đường đọc lẫn ghi: caption và keyword Photos **vô hình** với app.

## 3. Phạm vi

**Có (iOS 27):**
- Info của một ảnh hoặc clip: sửa caption, thêm/bớt keyword, gợi ý từ keyword đã có trong thư viện.
- Chế độ chọn → ⋯ → **Caption & Keywords…**: thêm, bớt keyword và đặt hay xoá caption cho cả mẻ, có Undo.
- Lọc: trường **Keyword** và **Caption** trong bộ dựng điều kiện (Advanced Search và Smart Album).
- Tìm: `keyword:` trong ô tìm kiếm, từ trùng tên một keyword thành chip keyword, chữ tự do khớp cả caption.

**Cố ý không có:**
- Sửa keyword/caption **trong file** (IPTC/XMP) — file gốc trong Photos không ghi lại được nếu không tạo
  phiên bản chỉnh sửa.
- Màn danh sách keyword kiểu Lightroom (đổi tên, gộp, cây cha-con) — v1 dùng gợi ý; đổi tên một keyword
  trên 5.000 ảnh là một việc riêng.
- Menu con keyword trong menu lọc nhanh — danh sách keyword dài vài trăm dòng; lọc qua Advanced Filter và tìm.
- Duplicate chép caption/keyword sang bản sao — Duplicate hôm nay không chép cả favorite; làm chung một lần.
- Cột caption/keyword trong Export EXIF (CSV) — giữ cột cũ, thêm là việc riêng.
- Lọc theo keyword **trong file** (IPTC/XMP) — chỉ keyword Photos lọc được (§8).
- Caption/keyword Photos đi theo ảnh khi Share hay xuất (§8).

## 4. Một ảnh: Info

Caption và keyword là **section đầu** của Info sheet, **trên Location**, như Photos. Sửa ngay tại chỗ.
*Vì mọi chỗ khác tốn thêm một chạm cho việc làm trên từng tấm.*
- Ô nhiều dòng, placeholder *Add a Caption*: 1 dòng, nở tới 4 dòng rồi cuộn.
- Dưới là hàng capsule keyword cao 32pt, mỗi cái có ×, cuối hàng là capsule *+ Add Keyword*; vừa nấc medium.

Luật:
- **Ghi ngay, không có nút Save**: caption ghi khi rời ô hoặc bấm Done trên bàn phím; keyword ghi ở mỗi lần
  thêm hay chạm ×. Mỗi lần là một lần ghi Photos; database cập nhật **sau khi** Photos báo xong.
- Ô Add Keyword: gõ là hiện tối đa **8** gợi ý (dòng chọn, kèm số ảnh), xếp theo số ảnh giảm dần, khớp không
  phân biệt hoa thường và dấu. Return hoặc chạm gợi ý là thêm.
- **Dấu phẩy tách keyword** (`beach, family` = hai keyword), bỏ khoảng trắng hai đầu, bỏ mảnh rỗng.
- **Không tạo keyword trùng khác hoa thường**: gõ `sunset` khi thư viện đã có `Sunset` thì ghi `Sunset`.
  Dấu thì giữ đúng như gõ (`Đà Lạt` và `Da Lat` là hai keyword).
- Info **luôn đọc caption/keyword sống từ Photos** cho ảnh đang mở và sửa database nếu lệch — một asset,
  không tốn gì, và là lưới an toàn cho thay đổi lịch sử thay đổi không báo (§8).
- Keyword **trong file** vẫn ở dòng *Keywords* của *Rights & Description* như hôm nay, chỉ đọc
  ([03](03-info-panel-and-metadata.md) §3). Caption trong file cũng vậy.
- Thanh tóm tắt hai dòng trên chrome **không** có caption — luật 52pt của [03](03-info-panel-and-metadata.md) §1.

## 5. Nhiều ảnh: Caption & Keywords…

Mục mới trong ⋯ của chế độ chọn, ngay sau **Add to Collection**, icon `tag`. Có ở Library, album, smart album;
On This Day giữ menu gọn ([FS-01.06 §6](../FS-01-library/06-multi-select.md)). Mờ khi chưa chọn ảnh nào.

Một sheet tier A `[.medium, .large]`, tiêu đề *Caption & Keywords* và dòng phụ *30 Photos*, Cancel trái,
**Apply** phải. Ba section:
1. **Add Keywords** — ô token có gợi ý (cùng ô của §4), keyword chờ thêm là dòng có nút xoá;
2. **On These Photos** — mỗi keyword đang có trong mẻ một dòng: tên · `12 of 30` xám · nút ⊖ ở mép phải xoay
   *giữ nguyên → gỡ khỏi cả 30* (dòng gạch ngang, chữ đỏ);
3. **Caption** — ô nhiều dòng; mẻ cùng một caption thì hiện caption đó, khác nhau thì placeholder
   *Multiple Captions*; dưới ô có nút đỏ **Clear Captions**.

Luật:
- **Apply là một lần ghi Photos** cho cả mẻ: mọi asset, mọi keyword thêm/bớt, caption nếu có đụng tới.
- **Không đụng ô Caption thì không ghi caption nào**, kể cả khi mẻ có nhiều caption khác nhau.
- Gỡ keyword gom **không phân biệt hoa thường**: `Sunset` trên 5 ảnh + `sunset` trên 2 ảnh là một dòng `7 of 30`,
  gỡ là gỡ cả hai cách viết.
- Xong: banner *Added 2 keywords to 30 photos* (hoặc *Updated 30 photos*) với **Undo** trong 4 giây, chế độ chọn
  **giữ nguyên** — gắn keyword thường là một bước giữa chừng, như Duplicate.
- **Undo** ghi ngược đúng phần đã đổi: chỉ gỡ keyword khỏi ảnh **trước đó chưa có** nó, trả caption cũ từng
  ảnh. Cũng là một lần ghi. Undo trong Info (§4) không có — gắn lại là một chạm, gợi ý đứng đầu.
- Mẻ trên 1 giây ghi thì có modal *Updating 5,000 photos…* không có Cancel: lần ghi là nguyên khối.

## 6. Đường hỏng

| Ca | Hành vi |
|---|---|
| Ảnh chỉ có trên iCloud, máy mất mạng | ghi bình thường, **không tải** bản gốc; Photos tự đồng bộ lên iCloud sau |
| Asset từ chối sửa thuộc tính (thư viện chia sẻ, album chia sẻ) | phần còn lại vẫn ghi; banner *4 photos can't be changed.*; 4 ảnh đó không đổi |
| Cả mẻ bị từ chối | không ghi gì, alert *Caption & Keywords* với lý do |
| Lần ghi lỗi | PhotoKit làm cả mẻ hoặc không làm gì; database không đổi; alert kèm **Try Again** ([NF-04](../../04-non-functional-design/NF-04-empty-and-error-states.md)) |
| Quyền `.limited` | chỉ ảnh đã chia sẻ cho app có trong lưới, trong database và trong **gợi ý** — keyword chỉ nằm trên ảnh không chia sẻ thì không lộ ra |
| Huỷ | Cancel trước Apply: không ghi gì. Sau Apply không huỷ giữa chừng được, chỉ Undo |
| iOS 17–26 | không có mục ⋯, không có section sửa trong Info, không có trường Keyword/Caption trong bộ dựng điều kiện; `keyword:x` là chữ tự do. Ẩn, không mờ: control không bao giờ bật được trên máy đó |

## 7. Lọc và tìm

- **Bộ dựng điều kiện** thêm hai trường (cả Advanced Search và Smart Album, [FS-06.08 §2](../FS-06-collections/08-smart-albums.md)):
  - **Keyword**: *has* · *doesn't have* (ô nhập có gợi ý như hãng máy) · *has any keyword* · *has no keywords*
    (hai cái sau không cần giá trị — tìm ảnh chưa gắn gì sau buổi chụp);
  - **Caption**: *contains* · *doesn't contain*, theo luật loại chữ hiện có.
- Khớp keyword **không phân biệt hoa thường và dấu**, cùng cách cột địa điểm ([FS-01.04](../FS-01-library/04-place-search.md)).
- **Ô tìm kiếm** ([FS-01.03](../FS-01-library/03-search.md)):
  - `keyword:sunset`, `keyword:"golden hour"`, và tiếng Việt `từ khoá:` quy về cùng ký hiệu;
  - một từ trùng **đúng** tên một keyword có trong thư viện thành chip keyword, như địa điểm — vì database nói vậy;
  - chữ tự do khớp thêm caption và keyword (chứa), sau máy, ống kính, tên file.
- Chip: `keyword: Sunset`, `no keywords`, `caption contains "wedding"`.

## 8. Dữ liệu và đồng bộ

| | |
|---|---|
| Nguồn thật | thư viện Photos. App không giữ bản nào Photos không có |
| Ghi vào | Photos trước; xong mới ghi **hai bảng vệ tinh mới**: một dòng mỗi (ảnh, keyword) kèm khoá đã gấp hoa thường + dấu; một dòng mỗi ảnh có caption kèm bản gấp để tìm |
| Người dùng tự nhập? | có, nhưng bản gốc nằm ở Photos; hai bảng chỉ là **gương** để lọc. Không cột nào trong bảng metadata chính ([BD-02 §1](../../01-basic-design/BD-02-database-design.md)) |

- **Lượt index ghi đè dòng metadata không bao giờ đụng hai bảng này** — chúng có lượt đọc riêng. Mất bảng thì
  dựng lại từ Photos, không mất chữ nào.
- **Lượt đọc đầy**: lần đầu chạy trên iOS 27, và mỗi khi lịch sử thay đổi của Photos hết hạn.
  - fetch theo trang **1.000 asset có bật tải sẵn metadata mở rộng**, một transaction mỗi trang; không bao giờ hỏi lười từng asset;
  - tiếp tục được, nhường như mọi lượt chậm ([NF-01](../../04-non-functional-design/NF-01-performance.md) luật 5).
- **Giữ tươi**: tập id **"updated"** của lịch sử thay đổi được đọc lại metadata mở rộng **dù ngày sửa không
  đổi** — lượt index bỏ qua các id đó vì nó so ngày sửa. Asset bị xoá thì dòng đi theo.
- Gợi ý lấy từ bảng keyword: đếm theo khoá đã gấp, lấy cách viết nhiều ảnh nhất, có chỉ mục trên khoá.

- **Keyword trong file** (IPTC/XMP, ảnh xuất từ Lightroom) **không** lọc được. Lọc, tìm và smart album chỉ
  theo keyword Photos; keyword trong file vẫn hiện chỉ đọc ở Info (§4). *Vì đọc chúng vào gương phải đọc lại
  cả 55k file, ảnh chỉ trên iCloud tốn ~1 MB/ảnh.* Nếu Photos tự nhập IPTC lúc thêm ảnh (§10 câu 2) thì ảnh
  Lightroom đã có sẵn keyword Photos.
- **Share và xuất không mang caption/keyword Photos** ([FS-08.06](../FS-08-settings/06-share-metadata-privacy.md)).
  All Metadata vẫn là **nguyên byte** file gốc; caption Photos là ghi chú riêng. Caption/keyword **trong file**
  theo luật hiện có: No Location giữ, No Metadata bỏ (IPTC, XMP).

## 9. Thiết bị và truy cập

- Cùng chức năng trên iPhone 402×874, iPad 1376×1032, Duo trong 951×669, Duo ngoài 466×678.
- **Duo trong** cao 669pt, bàn phím chiếm gần nửa: ô đang gõ cuộn lên trên bàn phím, danh sách gợi ý cuộn
  dưới ô, không đẩy nút Apply khỏi thanh trên. **Duo ngoài**: Cancel/Apply nằm ngoài rail 84pt bên phải.
- iOS 26 và trước 26: sheet và menu ⋯ giống nhau, không rẽ nhánh.
- VoiceOver: capsule đọc *Sunset, keyword*, action **Remove**; dòng §5 đọc *Sunset, on 12 of 30 photos,
  unchanged* / *will be removed*; ô caption đọc *Caption*.
- DESIGN.md §8 thêm một dòng từ điển icon: Caption & Keywords = `tag`.

**Design canvas:** hai canvas hiện có (editor, Video Studio) không vẽ Info sheet hay chế độ chọn, nên không board
nào bị đổi. Section Info (§4) và sheet hàng loạt (§5) cần board mới (hàng iPhone, iPad, Duo trong, Duo ngoài)
trước khi code.

## 10. Phải đo trước `/plan`

Đo trên simulator iPhone 17 iOS 27.0 (đủ cho 1–5) và máy thật 55k (cho 6).

| Câu hỏi | Quyết định nó lái |
|---|---|
| 1. Sửa caption/keyword (trong Photos hay từ app) có vào tập "updated" của lịch sử thay đổi, có đổi ngày sửa không | không vào → Info là lưới an toàn duy nhất; cần thêm lượt đọc lại định kỳ |
| 2. Photos có tự nhập keyword/caption IPTC khi thêm file (`addmedia` một JPEG kiểu Lightroom) | có nhập → ảnh Lightroom lọc được ngay qua keyword Photos; không → chúng chỉ hiện ở Info (§8) |
| 3. Ghi thuộc tính cho 1.000 asset có bật hộp thoại hệ thống không, mất bao lâu | ngưỡng modal §5; nếu > 10 s thì chia lô 1.000 |
| 4. Asset thư viện chia sẻ có từ chối sửa thuộc tính không | §6 |
| 5. Photos có giới hạn độ dài caption, keyword không | cắt hay báo lỗi |
| 6. Lượt đọc đầy 55k với tải sẵn: tổng thời gian, bộ nhớ đỉnh | ngân sách AC-15; vượt 60 s thì dời ra sau lượt EXIF |

## 11. Tiêu chí nghiệm thu

Mọi AC chạy trên iOS 27 trừ AC-14.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | ảnh A chưa có caption | trong Info gõ `Sunrise at Ba Na` rồi bấm Done, trên iPhone, iPad, Duo trong, Duo ngoài | metadata mở rộng của A trả đúng chuỗi đó; đóng và mở lại Info thấy chuỗi; ô gõ không bị bàn phím che ở cả 4 máy | ⚠️ chưa có |
| AC-2 | ảnh A có caption `Sunrise at Ba Na` | xoá hết chữ trong ô, rời ô | caption của A trong Photos rỗng; bảng caption không còn dòng của A; ô hiện *Add a Caption* | ⚠️ chưa có |
| AC-3 | thư viện có `Sunset` trên 40 ảnh; ảnh A không keyword | gõ `sun` → thấy gợi ý `Sunset 40` đứng đầu; gõ tiếp thành `sunset, beach` rồi Return | A có đúng 2 keyword `Sunset` và `beach`; không có `sunset` viết thường | ⚠️ chưa có |
| AC-4 | 30 ảnh được chọn, 12 ảnh đã có `Hoi An` | mở Caption & Keywords…, thêm `Hoi An` và `2026 trip`, bấm Apply | đúng 1 lần ghi Photos; cả 30 ảnh có hai keyword, không ảnh nào có `Hoi An` hai lần; banner *Added 2 keywords to 30 photos* có Undo; chế độ chọn còn 30 ảnh | ⚠️ chưa có |
| AC-5 | vừa xong AC-4 | chạm Undo trong 4 giây | `Hoi An` bị gỡ khỏi đúng 18 ảnh trước đó chưa có, 12 ảnh kia còn; `2026 trip` bị gỡ khỏi cả 30; đúng 1 lần ghi | ⚠️ chưa có |
| AC-6 | 30 ảnh được chọn: `Sunset` trên 5, `sunset` trên 2 | dòng `Sunset · 7 of 30` chuyển sang gỡ, bấm Apply | 0/30 ảnh còn keyword nào gấp ra `sunset`; mọi keyword khác giữ nguyên | ⚠️ chưa có |
| AC-7 | 30 ảnh được chọn mang 3 caption khác nhau | mở sheet, thêm keyword `x`, không đụng ô Caption, bấm Apply | ô Caption hiện *Multiple Captions*; sau Apply cả 30 caption giữ nguyên từng ký tự | ⚠️ chưa có |
| AC-8 | thư viện 200 ảnh: 40 có `Sunset`, 150 không keyword nào | lưu smart album *Keyword has Sunset*, rồi album *Keyword has no keywords* | album 1 đếm 40, album 2 đếm 150; đếm ở chân sheet khớp số trong lưới | ⚠️ chưa có |
| AC-9 | thư viện có keyword `golden hour` trên 9 ảnh, không keyword nào tên `85mm` | tìm `keyword:"golden hour"`, rồi tìm `85mm` | lần 1: chip `keyword: golden hour`, 9 ảnh; lần 2: hành vi cũ, chip tiêu cự (chống hồi quy `SearchParserTests`) | ⚠️ chưa có |
| AC-10 | ảnh B không keyword; lượt index đã xong | thêm `Sunset` cho B trong app Photos, mở lại ShotDex | sau lượt chạy tăng dần kế tiếp, lọc `Sunset` có B; 0 lần đọc file của B | ⚠️ chưa có |
| AC-11 | ảnh A có 2 keyword và caption trong bảng gương | chạy index lại toàn bộ (nâng phiên bản bộ index) | bảng gương vẫn đúng 2 dòng keyword và 1 caption cho A | ⚠️ chưa có |
| AC-12 | 50 ảnh được chọn, 20 chỉ có trên iCloud, máy mất mạng | thêm keyword `trip`, Apply | 50/50 có `trip`; 0 yêu cầu tải bản gốc, 0 yêu cầu mạng | ⚠️ chưa có |
| AC-13 | 30 ảnh được chọn, 4 ảnh từ chối sửa thuộc tính (giả lập) | thêm `trip`, Apply | 26 ảnh có `trip`, 4 ảnh không đổi; banner *4 photos can't be changed.* | ⚠️ chưa có |
| AC-14 | iOS 26.5, ảnh JPEG có IPTC Keywords `Lightroom, test` | mở Info, rồi mở ⋯ của chế độ chọn, rồi menu trường của bộ dựng điều kiện | Info: không ô caption, dòng *Keywords* ở Rights & Description ghi `Lightroom, test` như hôm nay; ⋯ không có Caption & Keywords…; menu trường không có Keyword, Caption | ⚠️ chưa có |
| AC-15 | thư viện 55.000 ảnh trên iOS 27, bảng gương rỗng | mở app, lượt đọc đầy chạy hết | ≤ 55 lần fetch PhotoKit cho lượt này, 0 lần hỏi lười từng asset; thời gian và bộ nhớ đỉnh ghi vào log, nằm trong ngân sách §10 câu 6 | ⚠️ chưa có — cần máy thật |
| AC-16 | quyền `.limited`, chia sẻ 10 ảnh; `Private` chỉ nằm trên ảnh không chia sẻ | gõ `Pri` vào ô Add Keyword | không gợi ý `Private`; bảng gương chỉ có dòng của 10 ảnh đã chia sẻ | ⚠️ chưa có |

**Chưa chứng minh được:** AC-1 → AC-16. Chưa có code.

## 12. Rủi ro

| Rủi ro | Xử lý |
|---|---|
| Lịch sử thay đổi không báo sửa caption/keyword (§10 câu 1) | Info đọc sống và sửa gương; thêm lượt đọc lại gương theo trang khi mở app nếu số đo câu 6 cho phép |
| Lượt đọc đầy 55k chậm hay nặng (§10 câu 6) | trang 1.000, tiếp tục được, nhường khi tương tác; vượt ngân sách thì chạy sau lượt EXIF |
| Một lần ghi rất lớn bị hệ thống hỏi hoặc chậm (§10 câu 3) | chia lô 1.000 có Cancel giữa lô; Undo phủ các lô đã ghi |
| Sao 0–5 (mục 9 của intent) cũng đọc/ghi Photos trên iOS 27 | dùng chung đường "updated dù ngày sửa không đổi" của §8, không dựng lượt thứ hai |
