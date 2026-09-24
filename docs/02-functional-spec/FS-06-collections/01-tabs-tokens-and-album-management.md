# FS-06.01 — Bố cục tab Collections

`FS-06.01` · `Features/Albums/AlbumsScreen.swift` · `AlbumsModel` · `Features/Shared/AlbumCoverTile.swift`
· cập nhật 2026-09-22

**Một câu:** tab liệt kê **album** — cover để duyệt ở trên, danh sách điểm-đến ở dưới, và mỗi mục đều ẩn
hoặc sắp lại được.

Quản lý album, Creations, sắp xếp và kéo thả: [FS-06.01b](01b-album-management-and-creations.md).

## 1. Quy tắc

- Tab này liệt kê **album**. **Không vẽ Folder** — một tầng hộp phải mở ra trước khi thấy album là một tầng
  chẳng chứa thông tin gì. Album nằm trong folder của Photos hiện thẳng ở "My Albums".
- **Không vẽ số đếm** ở bất kỳ tile nào — VoiceOver vẫn đọc được qua nhãn trợ năng.
- Album rỗng bị loại khỏi danh sách: thư viện không có ảnh chụp màn hình thì không có mục Screenshots.
- **Cover để duyệt, hàng để chọn**: thứ người ta nhận ra bằng ảnh thì làm tile; thứ chọn từ một danh sách
  biết trước thì làm hàng.

## 2. Thứ tự tab

1. **Hàng hero** — thẻ On This Day co giãn bên trái, cột Recents bên phải
2. **Pinned**
3. Memories · People and Pets · Smart Albums · My Albums · Shared Albums (tile cover)
4. **Media Types**
5. **Utilities**

Nút **"+"** đứng riêng ở góc trên-phải (để có viên kính riêng trên iOS 26) và là một menu:
New Album / New Smart Album / **Customize**.

## 3. Hàng hero

Cao **150pt**, và phép đo co theo cỡ chữ đặt ở **hàng**, không ở từng thẻ, để hai bên luôn bằng nhau.

- Thẻ On This Day co giãn bên trái; cột Recents rộng **150** (điện thoại) / **240** (màn rộng) bên phải.
- Mục "Recents" riêng **đã bỏ**: nhiều nhất hai dòng, nói về *phiên này* — một tiêu đề và một dải riêng tốn
  hơn thứ nó nói.
- Hai mục (Recently Viewed, Recently Shared) **chia đôi chiều cao hàng**, không thêm cột thứ hai: điện thoại
  chỉ có ~370pt bề ngang, hai thẻ 150 cạnh hero sẽ để hero còn 60.
- Thẻ Recents xếp **glyph trên, chữ dưới** — để cạnh nhau thì glyph và lề ăn 40 trong 150pt và "Recently
  Viewed" bị cắt.

**Recents** lưu danh sách id ảnh trong cài đặt của app, mới nhất trước, trần 100.

- **Hệ thống không ghi thứ nào trong hai thứ này** — nó biết ảnh tạo lúc nào và sửa lúc nào, không biết ai
  đã xem.
- Mở lại một ảnh thì **đẩy lên đầu**, không thêm bản trùng.
- Ghi nhận "đã chia sẻ" xảy ra lúc **dựng bảng chia sẻ**, không phải lúc chia sẻ xong: hệ thống không báo
  người dùng đã làm gì với bảng đó, mà câu hỏi danh sách trả lời là "vừa nãy mình chia sẻ cái gì".
- Mục nào không có dữ liệu thì không hiện — một "Recently Viewed" rỗng mời một cú chạm dẫn tới hư không.

## 4. Tile cover

Mọi nhóm album dùng **một** loại tile: cover vuông **132pt** (điện thoại) / **192pt** (màn rộng), **tên đè
lên đáy cover** (tối đa 2 dòng), **một hàng cuộn ngang**.

- Không còn chú thích dưới tile, và bỏ cách xếp tối đa ba hàng — ba hàng 168pt là 600pt cho một tiêu đề.
- Ảnh bìa xin theo **đúng cỡ tile**, không xin 44pt rồi phóng to.
- **Lớp làm tối sau tên được đo chứ không đặt sẵn**: đo độ sáng trung bình của dải đáy (42% chiều cao) bằng
  một lần vẽ thu về một điểm ảnh lúc cover về; sáng thì bật lớp tối, **đọc không được thì cứ bật** (có test).
- Thẻ **Memory** to theo (360×208) vì nó là cùng một loại thứ.
- Cover được phép to ra ở màn rộng dù luật chung cấm phóng to — ba điều kiện phải thoả nằm ở `DESIGN.md`.

**Smart Albums** là một mục duy nhất: smart album **do người dùng tạo** (glyph cái phễu khi chưa có cover)
đứng trước, rồi tới smart album **hệ thống** gợi ý (Recently Added, Favorites).

## 5. Media Types và Utilities

Hai mục cuối tab, **hàng full-width cao đúng một dòng chữ (52pt)**: glyph 28pt màu accent · tên · số ở cuối
· mũi tên. Media Types đứng **ngay trên** Utilities, đúng cách Photos của iOS 26 xếp.

- **Vì sao là hàng, không phải tile**: đây là điểm đến chọn từ một danh sách biết trước. Tile tiêu một thẻ
  60×190 kèm thumbnail cho mỗi mục, cuộn ngang giấu mất một nửa, mà tên dài vẫn bị cắt.
- Thẻ **rộng cố định 215** (điện thoại) / **270** (màn rộng), xếp tối đa **3 hàng rồi cuộn ngang**. Không
  full-width: một thẻ trải hết 1032pt đặt con số cách tên nó 800pt.
- **215 là con số đo được**: thẻ tốn 64pt cho lề và glyph, nên tên chỉ còn bề rộng trừ 64. Ở cỡ chữ đang
  dùng, tên dài nhất là **"Screen Recordings" 135pt**; ở bề rộng 190 thì tên chỉ có 126 nên nó bị cắt.
  215 cho 151. Kèm **mức co chữ 0,85** — bề rộng chọn theo tên **tiếng Anh** dài nhất không thể chứa mọi bản
  dịch của nó.
- **Không dùng ô cover 44pt**: ở dạng một-hàng-một-mục thì glyph là **dấu nhận biết**, còn một ô vuông 44pt
  cạnh một dòng chữ đọc ra là thumbnail tải hỏng.

**Media Types** = mọi album hệ thống có phân loại công khai, khai trong **một danh mục duy nhất** (mỗi mục
gồm phân loại, thuộc nhóm nào, glyph và tên đè tuỳ chọn; thứ tự trong danh mục là thứ tự hiển thị): Videos ·
Selfies · Live Photos · Portrait · Time-lapse · Slo-mo · Cinematic · Bursts · Screenshots ·
Screen Recordings · Animated · Long Exposures · RAW · Spatial (iOS 18 trở lên).

**Panoramas là ngoại lệ, và không nằm trong danh mục đó.** Album Panoramas của Photos không bao giờ chứa
một tấm ShotDex ghép ra — tấm đó không mang cờ panorama của hệ thống — nên mục này lấy từ **index của
ShotDex**, dùng đúng điều kiện mà bộ lọc Capture Kind dùng ([FS-14 §7](../FS-14-panorama/01-screen-and-flow.md)).
Nó vẫn đứng nguyên chỗ cũ trong hàng Media Types, vẫn mở ra màn album quen thuộc kèm Select, sắp xếp và
menu ⋯. Hệ quả đã chấp nhận: trên một thư viện **chưa index xong** mục này rỗng, nên bị ẩn, trong khi các
mục cạnh nó do PhotoKit cấp đã có số.

**Utilities** = Places · Trips · Duplicates (kèm số nhóm của lần gom cuối, **số nhiều dịch đúng trong bộ
chuỗi**) · **Collages** · **Video Projects** · **On Server** (chỉ hiện khi đã có ít nhất một ảnh lên
server, [FS-15.02 §8](../FS-15-server-upload/02-upload-flow.md)) · và các smart album nhóm tiện ích (hiện chỉ
Unable to Upload).

**Không có album Hidden và không có Recently Deleted**: từ iOS 16 hệ thống không cho app bên thứ ba đọc ảnh
ẩn (đo trên iOS 26: album đó trả về 0 ảnh); còn Recently Deleted **không phải bị chặn quyền mà là không có
API** — bảng phân loại album của hệ thống không có mục nào cho nó, và cũng không có đường mở Photos ở album
đó.

## 6. Customize và Pinned

- **Customize** (trong menu `+`): chạm một dòng để **hiện/ẩn** một mục, nút **Edit** để kéo đổi thứ tự, và
  **Reset to Default Order** khi đã tuỳ biến.
- **Pinned và Utilities không ẩn được**: Pinned là thứ người dùng đã tự tay bảo "giữ trong tầm với", còn
  Utilities là công cụ — app mà giấu được công cụ của chính nó là một bài toán hỗ trợ.
- Mỗi dòng là **một nút trải hết hàng, không phải một công tắc**: công tắc đặt trong một danh sách kéo được
  **không nhận được chạm**. Cũng **không** ép danh sách vào chế độ sửa — lúc đó hệ thống giữ chạm cho việc
  kéo, nên mọi control trong hàng chết theo.
- Trộn thứ tự **khoan dung**: mục lạ trong danh sách đã lưu thì **bỏ qua**, mục mới của bản sau thì **nối
  vào cuối**.
- **Pinned** lưu một danh sách **chuỗi có tiền tố** (`album:…`, `smart:…`, `utility:…`) để chứa được cả
  album, smart album lẫn công cụ đúng thứ tự người dùng ghim. Ghim không tìm thấy thì **bỏ qua im lặng**
  (album có thể đã bị xoá trong Photos). Mục Pinned nằm trên cùng, trên cả Memories; mọi tile đều có
  "Pin to Top" / "Unpin" trong menu giữ-lâu.

## 7. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
