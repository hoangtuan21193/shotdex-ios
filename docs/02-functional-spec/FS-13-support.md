# FS-13 — Support

`FS-13` · tier A · `Features/Support/` · backend ở repo `shotdex-web` · cập nhật 2026-09-22

**Một câu:** kênh liên hệ duy nhất giữa người dùng và người làm app, **ẩn danh**, mở từ **Settings › Support**.

Apple không cho app nhắn tin với người dùng: trả lời đánh giá phải đợi họ viết đánh giá trước, phản hồi
TestFlight không tới được người dùng App Store, và không có đường nào khác. Nên ShotDex tự dựng — chạy trên
hạ tầng serverless gói miễn phí.

## 1. Quy tắc

- **Ẩn danh**: không tài khoản, không email, không mật khẩu. Danh tính là **khoá chứng thực của bản cài**;
  gỡ app là mất khoá, và mọi báo cáo cũ không còn liên kết với máy.
- **Không ảnh, không tên, không email, không định danh quảng cáo.**
- **Không để lại nút bấm im lặng**: mọi nhánh không dùng được cổng hỗ trợ đều đổi sang soạn mail.
- Token dùng để bỏ qua xác thực khi phát triển đọc từ **biến môi trường**, không bao giờ nhúng trong app —
  token nhúng trong app là token công khai.
- Đây là **ngoại lệ duy nhất** của cam kết xử lý cục bộ
  ([NF-03](../04-non-functional-design/NF-03-privacy-and-security.md)).

## 2. Xác thực bằng chứng thực thiết bị

- App tạo một khoá trong vùng bảo mật của máy; máy chủ xác minh chứng thực về tận gốc của Apple rồi lưu
  khoá công khai. Mỗi lời gọi sau mang một chữ ký lên **phương thức, đường dẫn, mốc thời gian và mã băm của
  nội dung**.
- Bộ đếm trong vùng bảo mật **tăng mỗi lần ký**, nên **ký song song là hỏng** — lớp ký phải xếp hàng tuần tự.
- **Phải tự hồi phục lúc chạy, không được tin cờ "máy có hỗ trợ"**: cờ đó vẫn báo có trên máy thật dù bản
  build ký thiếu quyền, và **chỉ tới lúc tạo khoá mới hỏng**. Nên mọi lỗi từ vùng bảo mật được quy về một
  lỗi duy nhất, cổng hỗ trợ bị hạ xuống, và màn hình đổi **cả nút lẫn phần chữ mô tả** sang luồng email.
- Khoá khai **môi trường chứng thực chỉ có tác dụng với bản cài từ Xcode**; TestFlight và App Store luôn
  chứng thực vào môi trường thật. Nên máy chủ dev nhận **cả hai** môi trường, còn máy chủ thật chỉ nhận
  môi trường thật.
- Máy ảo không chạy được chứng thực → bản phát triển dùng token bỏ qua.

## 3. Hai môi trường

| Máy chủ | Cơ sở dữ liệu | Phục vụ |
|---|---|---|
| `api.shotdex.app` | bản thật | build App Store |
| `dev-api.shotdex.app` | bản dev | build từ Xcode và TestFlight |

- Tên là `dev-api` chứ **không phải** `api.dev`: chứng chỉ miễn phí của nhà cung cấp chỉ phủ tên miền gốc
  và **một cấp** con — tên hai cấp thì phải mua chứng chỉ.
- Bản phát hành phân biệt bằng **biên nhận**: biên nhận mang tên môi trường thử nghĩa là TestFlight. Nhờ vậy
  báo lỗi của người thử beta **không rơi vào hàng đợi thật**.
- Token bỏ qua xác thực chỉ đặt trên máy chủ dev, **không bao giờ** trên máy chủ thật.

## 4. Ký hai kiểu quyền

Tài khoản Apple miễn phí **không tạo được hồ sơ ký mang quyền chứng thực** — Xcode nói thẳng điều đó. Nên
project có hai file quyền:

| Cấu hình | File quyền |
|---|---|
| Phát triển | **không** có quyền chứng thực — tài khoản miễn phí ký được |
| Phát hành | có quyền chứng thực |

Khi chưa có tài khoản nhà phát triển trả phí, bản phát triển trên máy thật vẫn chạy — chỉ là màn Support
đổi sang gửi mail.

## 5. Màn hình

Danh sách nhóm, tier A:

| Mục | Nội dung |
|---|---|
| Report a Bug / Request a Feature | sheet soạn: tiêu đề, nội dung, công tắc gửi kèm log |
| Your Messages | luồng tin của chính bản cài này + nhãn số tin chưa đọc; mở là đánh dấu đã đọc |
| What People Asked For | lộ trình công khai, **một máy một phiếu**. Chỉ ticket được đánh dấu công khai mới lên đây, và **chỉ hiện tiêu đề** — lời người báo lỗi viết ra không bị công khai |

## 6. Gửi kèm gì

Nội dung người dùng gõ · phiên bản app và build · phiên bản iOS · model máy · ngôn ngữ · và **số ảnh trong
thư viện đã làm tròn còn hai chữ số có nghĩa** (55.213 → 55.000) vì con số chính xác là một dấu vân tay.

**Log**: đọc kho log của **tiến trình đang chạy**, lọc đúng phân hệ của app, **15 phút gần nhất**, cắt còn
**48 KB** và nói rõ đã bỏ bao nhiêu dòng.

- Mặc định **bật cho báo lỗi, tắt cho đề xuất tính năng**; người dùng **đọc được đúng văn bản sẽ gửi** trước
  khi gửi.
- Giới hạn của iOS: chỉ lấy được log của tiến trình đang chạy (đọc log toàn hệ thống cần quyền Apple không
  cấp) — nên **log của lần chạy bị crash đã mất**, phải tái hiện lỗi rồi mới gửi.

## 7. Cố ý không có

**Đính kèm ảnh** ở phiên bản đầu — kho lưu file phải gắn thẻ thanh toán mới bật được, mà hạ tầng đang giữ
trong gói miễn phí.

## 8. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../README.md#6-việc-còn-nợ).
