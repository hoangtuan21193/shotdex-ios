# BD-04 — Ngôn ngữ thiết kế và chrome toàn app

`BD-04` · `ShotDex/App/Glass/` · `ShotDex/App/Theme/` · cập nhật 2026-09-22

**Một câu:** phong cách chung và phần chrome dùng lại ở mọi màn. Token cụ thể (màu, bo góc, khoảng cách,
bốn tầng) nằm ở `DESIGN.md` — **không định nghĩa token ở đây**.

## 1. Quy tắc

- Phong cách iOS thuần, lấy cảm hứng từ Photos, **không sao chép**.
- Tối giản, nhiều chỗ cho ảnh, ít màu trang trí, ưu tiên chữ và thứ bậc.
- Không dựng bảng điều khiển kiểu web, không lạm dụng thẻ, **không dùng nút to khi một control hệ thống làm
  được việc**. **Ngoại lệ có chủ đích**: màn Statistics là một bảng biểu đồ tuỳ biến, nhưng dựng bằng
  control hệ thống.
- **Không màn nào đọc màu accent từ kho tài nguyên** — giá trị đó bị cố định lúc build.
- Xác nhận hành động phá huỷ dùng **hộp thoại có nút Huỷ**, không dùng bảng chọn trượt lên.

## 2. Chrome

| Thành phần | Cách làm |
|---|---|
| Điều hướng | ngăn xếp tiêu chuẩn + vuốt-để-quay-lại của hệ thống; màn gốc của tab **không** có tiêu đề, màn con thì có |
| Tab bar | thanh nổi kiểu kính — một viên nang chứa các tab cộng một nút tìm kiếm tròn tách riêng; iOS 26 dùng hiệu ứng kính của hệ thống |
| Ba tab | Library · Collections · Statistics |
| Tìm kiếm | nút tròn trong thanh nổi, **không** nằm ở thanh trên |
| Settings | **không phải tab** — nút bánh răng góc trên trái của cả ba tab, mở **toàn màn** kèm tiêu đề nhỏ và nút **Done** |
| Bảng lọc, bảng thông tin | bảng trượt lên có hai nấc và tay nắm kéo |
| Sắp xếp | menu thả xuống |
| Danh sách | kiểu nhóm có lề của hệ thống |
| Control | công tắc, bộ chọn, dải chọn, hộp thoại |
| Biểu tượng · chữ | bộ biểu tượng hệ thống · font hệ thống, có hỗ trợ cỡ chữ lớn |

- **Trước iOS 26, chỉ dựng tab Library lúc mở app**; Collections và Statistics dựng ở lần chọn đầu tiên rồi
  **giữ sống** — vừa tránh việc truy vấn của tab đang ẩn tranh khung hình đầu, vừa giữ chỗ người dùng đang
  đứng.
- **Chạm lại tab Library thì lưới nhảy về đáy** (ảnh mới nhất). Tín hiệu đi từ **cả hai** nhánh tab bar, và
  việc nhảy về đáy là một phép đặt vị trí trực tiếp nên rẻ.
- **Một dòng thiết lập giữ tab tìm kiếm vẽ giống nhau trên iOS 26 và 27**: mặc định iOS 27 biến nó thành tab
  thứ tư trong viên nang, còn dòng đó kéo nó về thành nút tròn ở mép phải. Dòng này có từ iOS 26 nên đặt
  chung, không cần rẽ nhánh theo phiên bản.

## 3. Màu và accent

- Màu nền và màu chữ dùng **bộ màu ngữ nghĩa của hệ thống** nên tự thích nghi sáng/tối.
- **Chrome là màu mặc định của iOS**: app **không** đặt màu nhấn toàn cục. Thanh điều hướng, menu, bảng
  trượt, công tắc, tab đang chọn đều là control hệ thống nguyên bản; nút chrome tự vẽ thì dùng màu chữ chính.
- **Accent là một hằng số, không phải một thiết lập**: màu hổ phách của mặt trời trong biểu tượng app, và
  bản dùng cho nền sáng đậm hơn (bản gốc trên nền trắng quá nhạt để đọc như màu của một control). Bộ chọn
  bốn màu accent và mục Appearance trong Settings **đã xoá**.
- Accent **chỉ dành cho phần app tự vẽ** — nhãn chọn ảnh trên lưới, trạng thái đang bật của editor, biểu đồ.
  Lớp giao diện đọc nó qua môi trường; lớp vẽ bằng UIKit (ô lưới) đọc trực tiếp.
- Kiểu nút **không đọc được giá trị từ môi trường**, nên phải truyền accent vào cho nó.

## 4. Luật HIG đang áp

- **Xác nhận phá huỷ phải là hộp thoại có nút Huỷ**: iOS 26 vẽ bảng chọn trượt lên thành một ô nổi và
  **giấu mất nút huỷ**, để lại đúng một nút đỏ. Gom các hộp thoại đó lại **một chỗ** — nhiều hộp thoại viết
  rải rác làm trình biên dịch bỏ cuộc.
- **Bảng trượt lên phải có lối ra nhìn thấy được** (nút Done): vuốt xuống là lối tắt, không phải một control;
  trên iPad tay nắm kéo còn dễ không thấy — một bảng có thanh trên mà không có lối ra thì đọc như bị kẹt.
- **Hành động "Ẩn ảnh" phải hỏi trước**: từ iOS 16 hệ thống lấy album ảnh ẩn khỏi mọi app trừ Photos, nên
  ShotDex ghi được cờ mà **không bao giờ thấy lại ảnh để bỏ ẩn**. Câu thông báo nói thẳng là phải mở Photos.
- **Hai nút chữ đứng liền nhau phải có vách ngăn**: iOS 26 gộp chúng vào một viên kính và mất ranh giới.
- **Menu nói trạng thái hiện tại**: dòng đang được áp thì **làm mờ**, thay vì mời chọn lại chính nó.
- Biểu tượng và tên gọi theo **một từ điển chung** cho cả app.
- **Trợ năng**: mọi chrome tự vẽ (tab bar, nút kính, thẻ album, ô lưới) phải có nhãn và trạng thái đúng.
- Có haptic ở các thao tác quan trọng.

## 5. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../README.md#6-việc-còn-nợ).
