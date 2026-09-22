# EX-01 — ShotDexKit và ShotDexEdit

`EX-01` · `ShotDexKit/` · `ShotDexEdit/` · cập nhật 2026-09-22

**Một câu:** cái gì thuộc framework render dùng chung, cái gì ở lại app, và extension sửa ảnh trong Photos
được phép làm gì.

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
| Render (9 file) | renderer ảnh và các phần mở rộng của nó, kho ảnh overlay, bộ đọc bản đồ độ sâu |
| Toán thuần (7 file) | mô phỏng film, tone curve, toán màu, đặt chữ, hình học hình vẽ, quy đổi token, raster nét cọ |

App, target test và extension **đều dùng** framework này. **Ở lại app**: panel, danh mục slider, số đo bố
cục, lịch sử, clipboard.

Hai chỗ đã phải **gỡ phụ thuộc ngược** để framework đứng một mình:

- Hằng số quy đổi độ mềm của nét cọ chuyển **từ lớp bố cục vào framework** — renderer mới là bên phải khớp
  với con số đó; lớp bố cục giờ hỏi ngược lại.
- Phép dựng giá trị token từ metadata tách sang một file **ở app**, vì metadata thuộc tầng database.

Test dùng cách nhập module cho phép chạm vào phần nội bộ — chúng vốn đã chạm vào phần nội bộ của app.

## 3. Extension sửa ảnh

Mở ShotDex **ngay trong app Photos**.

- Giao diện **cố ý nhỏ hơn editor**: dải film look + Strength + bốn thanh tone (Exposure / Contrast /
  Highlights / Shadows). Extension chạy trong một tiến trình chật bộ nhớ ngay cạnh Photos; bê cả editor vào
  là nuôi thêm một app thứ hai chứ không phải đi tắt.
- **Dữ liệu chỉnh sửa chính là công thức của app**, dưới đúng định danh của app — nên vòng quay khép kín:
  mở lại trong extension thì slider hiện nguyên trạng, mở trong ShotDex thì editor đầy đủ thấy cùng một bản sửa.
- Giao diện là một view, **không dựng từ storyboard** — một file storyboard chỉ để khởi tạo một view là file
  chỉ có thể mục nát.
- **Chỉ ảnh tĩnh**: renderer làm việc trên ảnh, còn video cần cả pipeline của Video Studio.

## 4. Hai luật bộ nhớ của extension

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

## 6. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../README.md#6-việc-còn-nợ).
