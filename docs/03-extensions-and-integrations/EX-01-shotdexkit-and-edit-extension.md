# EX-01 — ShotDexKit (và ShotDexEdit, đã bỏ)

`EX-01` · `ShotDexKit/` · `ShotDexEdit/` · cập nhật 2026-09-22

**Một câu:** cái gì thuộc framework render dùng chung, cái gì ở lại app.

> **2026-09-22 — bỏ `ShotDexEdit`.** Extension sửa ảnh tại chỗ trong Photos bị gỡ khỏi dự án. Thay bằng một
> dòng **Edit in ShotDex** trong share sheet, mở thẳng app tại ảnh đó: [EX-05](EX-05-edit-action-extension.md).
> Lý do: bề mặt bốn slider ấy không phải thứ người dùng cần, mà nó kéo theo trần bộ nhớ ~120MB và luật
> **từ chối mọi ảnh có mask / nét vẽ / markup** — càng dùng mask nhiều thì Photos càng hay hiện "Revert"
> thay vì "ShotDex". §3 và §4 dưới đây giữ lại làm **hồ sơ**, không còn là đặc tả của thứ đang chạy.
>
> **Ranh giới của framework không đổi**: `ShotDexKit` vẫn không được đụng SwiftUI và GRDB, vì widget, share
> extension và action extension mới vẫn link vào nó.

## 1. Quy tắc

- **Framework không dùng SwiftUI, không dùng database.** Nó là **lõi render**, không phải cả editor.
- Đưa một kiểu dữ liệu vào framework = phải **mở công khai nó và toàn bộ thành phần bên trong** — đó là giá
  của ranh giới module.
- Kiểu dữ liệu trong framework phải **khai hàm khởi tạo công khai tường minh** (hàm khởi tạo mặc định của
  Swift chỉ dùng được trong cùng module).
- Extension **chỉ nhận đúng định danh chỉnh sửa của chính nó** — nhận bừa dữ liệu chỉnh sửa của app khác là
  vứt công sức của họ lúc lưu.

## 2. Framework có gì

| Nhóm | Nội dung |
|---|---|
| Model công thức (5 file) | công thức sửa ảnh, bộ thông số chỉnh, lớp markup, màu, curve, nét vẽ |
| Render | renderer ảnh và các phần mở rộng của nó, kho ảnh overlay, bộ đọc bản đồ độ sâu, bộ nạp kernel và các file kernel Metal ([FS-16](../02-functional-spec/FS-16-metal-kernels.md)) |
| Toán thuần (7 file) | mô phỏng film, tone curve, toán màu, đặt chữ, hình học hình vẽ, quy đổi token, raster nét cọ |

App, target test và extension **đều dùng** framework này. **Ở lại app**: panel, danh mục slider, số đo bố
cục, lịch sử, clipboard.

Hai chỗ đã phải **gỡ phụ thuộc ngược** để framework đứng một mình:

- Hằng số quy đổi độ mềm của nét cọ chuyển **từ lớp bố cục vào framework** — renderer mới là bên phải khớp
  với con số đó; lớp bố cục giờ hỏi ngược lại.
- Phép dựng giá trị token từ metadata tách sang một file **ở app**, vì metadata thuộc tầng database.

Test dùng cách nhập module cho phép chạm vào phần nội bộ — chúng vốn đã chạm vào phần nội bộ của app.

## 3. Extension sửa ảnh — hồ sơ (đã bỏ 2026-09-22)

Mở ShotDex **ngay trong app Photos**.

- Giao diện **cố ý nhỏ hơn editor**: dải film look + Strength + bốn thanh tone (Exposure / Contrast /
  Highlights / Shadows). Extension chạy trong một tiến trình chật bộ nhớ ngay cạnh Photos; bê cả editor vào
  là nuôi thêm một app thứ hai chứ không phải đi tắt.
- **Dữ liệu chỉnh sửa chính là công thức của app**, dưới đúng định danh của app — nên vòng quay khép kín:
  mở lại trong extension thì slider hiện nguyên trạng, mở trong ShotDex thì editor đầy đủ thấy cùng một bản sửa.
- Giao diện là một view, **không dựng từ storyboard** — một file storyboard chỉ để khởi tạo một view là file
  chỉ có thể mục nát.
- **Chỉ ảnh tĩnh**: renderer làm việc trên ảnh, còn video cần cả pipeline của Video Studio.

## 4. Hai luật bộ nhớ của extension — hồ sơ (đã bỏ 2026-09-22)

- **Ghi file nén thẳng ra đĩa**, không dựng cả khối dữ liệu trong bộ nhớ rồi mới ghi: bản cũ giữ **cả ảnh
  nén trong bộ nhớ cạnh ảnh đã render** — ở app là lãng phí, ở một extension đang render nguồn 48MP thì là
  khác biệt giữa **lưu được** và **bị hệ thống giết đúng lúc lưu**.
- **Từ chối tiếp tục một công thức có lớp phủ toàn khung** (mask, nét vẽ, markup), và kiểm **hai lần**: lúc
  Photos hỏi "mở được không", và lần nữa lúc bắt đầu phiên sửa. Mỗi lớp đó phải vẽ vào một bộ đệm **bằng cả
  khung ảnh**: ảnh 48MP là **~195MB cho một lớp**, trước cả khi giải mã ảnh gốc. Nói không thì Photos hiện
  "Revert" thay vì "Edit in ShotDex", và ảnh mở trong app đầy đủ với bản sửa còn nguyên — đúng bản chất: bề
  mặt này là bốn slider với một film look, chỉ nên nhận đúng phần nó dựng nổi.

## 5. Bẫy build đã biết

| Triệu chứng | Nguyên nhân | Cách làm đúng |
|---|---|---|
| Extension mở lên trắng trơn, log báo không tìm thấy lớp ngữ cảnh | thư viện giao diện ảnh của hệ thống **không tự được kéo vào** | khai link tường minh |
| Build lỗi "hai lệnh cùng tạo ra Info.plist" | file đó vừa được sinh tự động vừa bị chép như tài nguyên | khai nó là ngoại lệ của nhóm file đồng bộ |
| Shader Metal thường thêm vào kit không build hoặc không chạy | target kit biên dịch **mọi** file Metal thành kernel Core Image, và tắt fast math để khớp golden | shader thường đặt ở target khác |
| Kernel kit nạp nil trong app | tìm metallib ở bundle của app thay vì bundle của framework | bộ nạp của kit đọc bundle framework; app có metallib riêng |

## 6. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../README.md#6-việc-còn-nợ).
