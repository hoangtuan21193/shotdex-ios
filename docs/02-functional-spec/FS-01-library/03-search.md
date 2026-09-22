# FS-01.03 — Tìm kiếm

`FS-01.03` · `Domain/Filtering/SearchIntentParser.swift` · `SearchIntentMapper` · `AISearchTranslator`
· `Features/Library/SearchSuggestionsScreen.swift` · test `SearchParserTests` · `SearchIntentParserTests`
· cập nhật 2026-09-22

**Một câu:** gõ câu tiếng Việt hoặc tiếng Anh, ra chip điều kiện sửa được — bộ phân tích trước, model sau,
tìm chữ tự do cuối.

## 1. Quy tắc

- **Một cửa duy nhất** cho mọi đường tìm kiếm. Thứ tự thử: **bộ phân tích → model → tìm chữ tự do**.
- Kết quả của bộ phân tích là **điều kiện dạng rule**, không phải bộ lọc đơn giản — bộ lọc đơn giản không
  có phép so sánh đầy đủ và không có ngày.
- **Model không sinh điều kiện và không thấy SQL**: nó chỉ điền một cấu trúc chữ-và-số, rồi một lớp chặn
  thuần (có test đầy đủ) mới quyết định cái đó thành gì.
- Lưới nhận **một trong hai** nguồn điều kiện, không nhận cả hai.
- Chạy trên database đã index, **không quét lại file**.

## 2. Tìm được theo gì

Địa điểm · tên file · thân máy · ống kính · tiêu cự · ISO · khẩu · tốc độ · khổ cảm biến · ngày · favorite.

Ví dụ: `Fukuoka` · `f > 1.2` · `ISO trên 3200` · `trước 2020` · `nhanh hơn 1/500` · `IMG_1234` ·
`Canon R6` · `85mm`.

## 3. Bộ hiểu câu

| Nhận dạng | Ví dụ |
|---|---|
| So sánh số | `f > 1.2` · `f lớn hơn 1.2` · `khẩu độ trên 1.2` · `aperture over 1.2` |
| Khoảng | `iso 100-400` · `tiêu cự từ 24 đến 70` |
| **Tốc độ theo nghĩa người dùng** | `nhanh hơn 1/500` → tốc độ **nhỏ hơn** 0,002 giây. Nhanh = số bé, **chỗ duy nhất trong app nói ngược với số**, có test riêng |
| Ngày | `trước 2020` = trước mốc **đầu** năm; `sau 2023` = sau mốc **cuối** năm (dùng mốc thô là mất 12 tháng ảnh); `năm 2023`, `hôm qua`, `tháng trước`, `7 ngày qua`, `last 30 days` |
| Khác | favorite · định dạng file · khổ cảm biến · tên (địa điểm, máy, ống kính) |

- **Tiếng Việt không có bộ ngữ pháp riêng**: cụm nhiều từ được quy về đúng ký hiệu mà tiếng Anh sinh ra
  (`lớn hơn` → `>`, `khẩu độ` → `f`), rồi một bộ đọc duy nhất xử lý. Thêm một cách nói = thêm một dòng bảng.
- **Khớp cụm theo nguyên từ, không theo chuỗi con**: bản chuỗi con sai thật — chữ "tu" (trong "từ") nằm
  trong "aperture", nên `aperture over 1.2` bị biến thành một câu vô nghĩa.
- **`fukuoka` là địa điểm vì database nói vậy**, không vì hình dạng chữ: phần chữ còn lại được đối chiếu với
  danh mục gợi ý thật (địa điểm, thân máy, ống kính, hãng). Không khớp gì thì rơi về tìm chữ tự do — nên
  `85mm`, `ISO 3200`, `f/1.8`, `Canon R6`, `IMG_1234` giữ nguyên hành vi cũ (có test chống hồi quy).
- **Từ đệm bị loại** (`chụp`, `ảnh`, `ở`, `photo`, `taken`…) — chúng không nằm trong cột nào nên sẽ làm lưới
  trắng.
- **Số vô lý bị từ chối** thay vì thành điều kiện (`iso 1.4`, `f 3200`): một điều kiện như thế cho ra chip
  tự tin trên lưới rỗng, còn tìm chữ tự do thì ít nhất còn tìm.
- Phần không hiểu khi *đã* có điều kiện thì thành một chip "tên file chứa …" — một chip nhìn thấy và xoá
  được hơn là một từ bị âm thầm bỏ.

## 4. Model trên iOS 26

Dùng model ngôn ngữ chạy trên máy của hệ thống.

- Chỉ chạy khi model **có sẵn và hỗ trợ ngôn ngữ đang dùng**, hạn **2 giây**, và **chỉ khi bộ phân tích
  không hiểu hết** — hỏi model để đọc lại `85mm` chỉ thêm độ trễ.
- Phần hướng dẫn cho model kèm **vốn từ thật** của thư viện (địa điểm, máy, ống kính) nên nó không bịa tên máy.
- Lớp chặn bỏ trường lạ, bỏ số ngoài khoảng, phân biệt "N ngày qua" với mốc thời gian tuyệt đối, bỏ khoảng
  thiếu đầu mút.
- Máy không đủ điều kiện thì **giao diện không đổi gì** — không có huy hiệu nào để hụt hẫng.
- Gợi ý lúc đang gõ chỉ chạy bộ phân tích (mỗi phím một lần nên phải rẻ); model chỉ chạy **một lần lúc áp**.

## 5. Màn tìm kiếm

**Chồng capsule nổi trên ô tìm kiếm, kiểu Photos** — **không phải một danh sách**. Danh sách trải hết bề
ngang đọc ra như giao diện chính, làm ô tìm kiếm trông như đường vào thứ yếu; ở đây **ô tìm kiếm là giao diện**.

- Tối đa 5 capsule nhưng **cắt bớt cho vừa chỗ**: màn đo chiều cao thật của khối tiêu đề + Recents và chỗ
  còn lại, rồi chia cho chiều cao một capsule. Thiếu chỗ thì bỏ bớt gợi ý, **không bao giờ dưới 1** —
  capsule **không được che thẻ Recents**, vì nửa thẻ Recents đọc ra như lỗi layout còn mỗi capsule là một
  truy vấn độc lập.
- Chồng capsule nằm **ở phía có ô tìm kiếm**: iOS 26 trên máy hẹp đặt ô ở đáy (và vẽ **đè lên** nội dung,
  nên phải chừa thêm chỗ); các trường hợp còn lại — trước iOS 26, và iOS 26 ở màn rộng — ô ở trên. Điều
  kiện phải đọc **cả bề rộng**, nhìn mỗi phiên bản iOS thì iPad để tiêu đề một mình trên đỉnh màn 1376pt
  rồi capsule lơ lửng trên bàn phím.
- Bàn phím không cần xử lý gì: vùng an toàn của nó tự nâng cả chồng nên capsule **nảy theo ô tìm kiếm**.
- **Tiêu đề `Search` do màn tự vẽ**, không dùng tiêu đề của nav bar — ô tìm kiếm đang bật thì iOS 26 ẩn
  tiêu đề, còn trước 26 cả nav bar bị ô chiếm.
- **Ô tự mở kèm bàn phím** khi vào màn. Vào lại tab lần thứ hai thì màn không "xuất hiện" lần nữa, nên phải
  bắt theo tab đang chọn: đã mở sẵn thì đặt lại tiêu điểm, chưa thì mở. Lúc rời tab, hệ thống **xoá chữ trên
  ô mà không báo lại**, nên phải tự xoá truy vấn — không thì phím Search gửi lại câu cũ.

## 6. Nội dung capsule và Recents

- Đang gõ → **cách hiểu của bộ phân tích đứng trước** (chữ đúng bằng chip mà thanh kết quả sẽ hiện; chạm
  chạy **chính câu đã gõ**, không chạy chuỗi rút gọn), rồi tới tên khớp trong thư viện.
- Ô rỗng → **địa điểm và máy thư viện thật sự có**, không phải ví dụ bịa: một gợi ý trả về 0 ảnh còn tệ hơn
  không có gợi ý. Chưa index gì thì hiện một dòng ví dụ.
- Capsule "cách hiểu" được giữ **kèm câu đã sinh ra nó** — bản xem trước bị huỷ thì không gán gì.
- **Recents kiểu Photos**: tối đa **3 thẻ ảnh**, mỗi thẻ là thumbnail **kết quả đầu tiên** với câu đã gõ
  trong ngoặc kép. **Truy vấn không còn kết quả thì không hiện** — recents rỗng đọc ra như app quên mất ảnh;
  vì thế mỗi mục tốn một truy vấn lấy đúng một ảnh, và chỉ chạy bộ phân tích (ba lần gọi model mỗi lần mở
  màn là không trả nổi).
- Lưu tối đa 10 câu, bỏ trùng không phân biệt hoa thường, mới nhất lên đầu (hàm gộp là hàm thuần, có test).
  Ghi ở **đường áp duy nhất** nên mọi lối tìm kiếm đều được nhớ, và nhớ **đúng câu người dùng gõ** chứ không
  phải cách bộ phân tích hiểu.

## 7. Đường áp

**Chạm capsule = tìm ngay; bấm Search trên bàn phím = tìm ngay.** Hai đường, không đường nào là bước của
đường kia.

- Phím Search được hệ thống giao cho **view sở hữu ô tìm kiếm**, nên phải bắt đúng ở đó — một lần gửi không
  tới đâu chính là cách một hộp tìm kiếm trở thành hỏng.
- iOS 26 và các bản trước dùng **một** màn gợi ý, và việc áp nằm ở **một** hàm, nên ba đường không thể lệch
  nhau.
- Hàm đó trả về **ngay**: màn tìm kiếm đóng cùng cú chạm, kết quả tới sau một nhịp.

## 8. Nút Advanced Search trong ô tìm kiếm

Icon ba thanh trượt **nằm trong ô tìm kiếm, mép phải**, ở cả hai phiên bản. Ô tìm kiếm của hệ thống không
cho gắn gì vào, nên app phải tự tìm ô đó trong cửa sổ (dò lại vì ô sinh muộn và bị dựng lại mỗi lần vào màn)
rồi gắn nút vào.

Hai cái giá đã biết và chấp nhận:

- Ô chỉ vẽ **một trong hai** — nút xoá của hệ thống hoặc nút của app — nên mất nút xoá; xoá bằng **Cancel**.
- **iOS 26 vẽ lặp icon đó ở dải status bar** vì nó nhân bản nội dung vùng chứa lên đó. Đo thật, ở mọi thời
  điểm gắn, và **không có API công khai để tắt**. Bản sao đó không nhận chạm.

Đã thử và loại: đặt nút vào thanh dưới (hệ thống vẽ nó **sau** ô), dùng ô tìm kiếm dựng sẵn ở thanh dưới
(chữ gõ vẽ tràn ra ngoài viên thuốc), và chỗ cạnh trái ô (hệ thống chiếm).

## 9. Truy vấn DSL và chip

- Bộ phân tích tự nhận ISO, khẩu (`f/1.8`), tốc độ (`1/500`), tiêu cự (`85mm`), khổ cảm biến; phần còn lại
  khớp tự do vào máy/ống kính/tên file. Số trần không đơn vị được thử vào **tất cả** các cột đó.
- Trên màn kết quả, truy vấn tách thành chip có nút `x` để xoá từng phần (`Canon R6 portrait` → `Canon`,
  `R6`, `portrait`); cụm có nghĩa như `ISO 100` và `full frame` **giữ chung một chip**.
- Gợi ý lấy từ danh sách máy và ống kính thật sự có trong database.
- **Tên file chỉ được ghi ở lượt đọc EXIF**, nên ảnh mới chỉ có row giữ chỗ và chưa tìm được theo tên cho
  tới khi lượt đó chạy xong.

## 10. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
