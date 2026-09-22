# FS-01.01b — Engine lưới, pinch và cử chỉ

`FS-01.01b` · `Features/Shared/PhotoGridCollectionView.swift` · `PhotoGridLayout.swift` · `Domain/Grid/`
· test `GridDensityTests` · `JustifiedGridRowsTests` · cập nhật 2026-09-22

**Một câu:** lưới tự tính layout bằng số học, nên pinch đổi mật độ chạy liên tục ở thư viện 100.000 ảnh.

Nguồn dữ liệu và luật neo: [FS-01.01](01-photo-grid-and-data-source.md).

## 1. Engine

Lưới là collection view của UIKit với một layout tự viết: **vị trí mỗi ô tính bằng số học từ chỉ số**, nên
chiều cao nội dung và khung của bất kỳ ô nào đều lấy ra tức thì, dù thư viện 100.000 ảnh.

- Ô lưới vẽ bằng UIKit; header nhóm là một ô phụ dựng bằng SwiftUI.
- **Đổi nội dung đi đường rẻ**: chủ sở hữu tăng một số hiệu cho mọi thay đổi về thành phần hay thứ tự khi
  số lượng không đổi — lưới không phải so sánh cả mảng id mỗi lần giao diện cập nhật.
- Công tắc hiển thị (ISO, khẩu, tốc độ…) đọc **một bản chụp** giữ sẵn, làm mới khi cài đặt đổi — không đọc
  lại cài đặt năm lần cho mỗi ô mỗi lần dựng.
- **Vì sao không dùng lưới lười của SwiftUI**: neo đáy buộc nó ước lượng tổng chiều cao (mở app đen lâu, ô
  không vẽ tới khi chạm), mọi thay đổi layout huỷ cả vùng chứa (pinch giật), và chỗ cuộn sau khi đổi số cột
  trỏ sai vùng.

## 2. Pinch — zoom liên tục

- Số cột được phép là **số thực**: ở giữa hai số nguyên thì mọi khung ô là **pha trộn tuyến tính** giữa
  layout của hai mức — không có bước nhảy, không có cổng chờ.
- **Ảnh dưới tâm pinch bị ghim vào ngón tay**: lưới nhớ ô nào và điểm nào trong ô, rồi mỗi khung đặt lại
  chỗ cuộn theo khung đã pha trộn của ô đó.
- **Pan của scroll view bị huỷ ngay khi pinch bắt đầu**, và chỗ cuộn được đặt không kèm hoạt ảnh để dập
  quán tính còn lại — không huỷ thì lưới giật qua lại.
- Thả tay: chiếu theo vận tốc, chọn **mật độ đã lưu** gần nhất rồi chạy một hoạt ảnh ngắn (~0,25s, **không
  vọt quá** để khỏi dựng lại hai lần). Chốt xong mới lưu mật độ, dựng lại nhóm ngày nếu cấp độ đổi, và xin
  thumbnail đúng cỡ **một lần** — trong lúc pinch chỉ phóng bản đang có, không xin mới, nên không nháy.
- **Mật độ lưu là mật độ ở bề rộng điện thoại (393pt), không phải số cột tuyệt đối**: mỗi màn quy đổi lại
  theo bề rộng thật. Màn rộng còn bị siết thêm hệ số **0,7** — rộng hơn phải cho **nhiều ảnh hơn**, không
  phải ảnh to hơn. Đo được: cùng mật độ 3 ra **9 cột** ở iPad 11" dọc và Duo trong, **13 cột** ở iPad 11"
  ngang; ô ảnh giữ 85–105pt ở mọi bề rộng. Pinch chạm tới 1…8 cột, quy đổi cho phép tới 20.
- **Mức 1 cột giữ tỉ lệ gốc** của từng ảnh, và chuyển mượt từ vuông sang tỉ lệ gốc khi tiến về 1 cột; ô xin
  ảnh đúng hình của nó nên không bị cắt.
- **Pinch vẫn dùng được trong chế độ chọn** — quét chọn là một ngón, pinch là hai ngón.

## 3. Lưới theo tỉ lệ ảnh

Công tắc **Aspect Ratio Grid** nằm trong menu filter, cùng chỗ với Sort By — cả hai đều là "lưới trông thế
nào", không phải "lưới chứa ảnh nào". Công tắc đọc **ngay trong lưới dùng chung** nên cả năm màn có lưới
cùng đổi theo một nguồn.

- **Hàng được căn đều kiểu Photos**, không letterbox trong ô vuông: mỗi hàng lấp đúng bề rộng, mỗi ảnh giữ
  đúng hình của nó, nên **chiều cao hàng là hệ quả**.
- Toán thuần, có test: đóng hàng ngay khi thêm một ảnh nữa sẽ kéo hàng thấp hơn mục tiêu; **hàng cuối giữ
  đúng chiều cao mục tiêu** thay vì kéo giãn (hai ảnh ngang kéo hết 1032pt sẽ cao vống lên trên các hàng
  trên); tỉ lệ bị **kẹp trong 1:3…3:1** — panorama 8:1 để nguyên thì thành một hàng riêng cao 40pt, ảnh
  scan 1:5 thì đẩy hàng cao quá màn hình.
- Chiều cao mục tiêu **chính là cạnh ô vuông ở mức cột đang dùng**, nên pinch vẫn đổi mật độ như cũ. **Chỉ
  áp từ 2 cột trở lên** — 1 cột vốn đã là ảnh full-width theo tỉ lệ gốc.
- Layout lưu bằng **năm mảng số nhỏ thay vì một khung cho mỗi ảnh**: 55.000 ảnh tốn ~1 MB thay vì gấp ba;
  tìm vùng nhìn là một phép tìm nhị phân. **Cache bị siết ở chế độ này** — chỉ giữ mức hiện tại và hai đầu
  của lần pha trộn, vì mỗi mức mang ba mảng dài bằng thư viện. Đo: dựng hàng cho 55.000 ảnh mất ~23ms.
- Ô xin ảnh **theo đúng hình ô** — xin ảnh vuông rồi nhét vào ô ngang thì hệ thống đã cắt vuông sẵn, đặt
  vào ô rộng là méo.

## 4. Ngày, nhóm và thanh cuộn

- **Ngày nằm ở tiêu đề, không nằm trong lưới**: mọi lưới chạy phẳng, không chèn dòng ngày dính. Lưới báo ra
  ngày của ảnh nằm ngay dưới mép trên vùng nhìn; Library hiện nó ở giữa thanh trên cùng với hiệu ứng đổi số.
- **Cấp độ ngày lấy theo mật độ đã lưu, không theo số cột đã quy đổi** — nếu không, một màn rộng tự nhảy
  sang gom theo năm dù người dùng không pinch. Một thang duy nhất: 1–3 cột theo **ngày**, 4–6 theo
  **tháng**, 7–8 theo **năm**.
- Ba chế độ nhóm: tự chia theo ngày · một khối phẳng · **màn tự cấp nhóm**. Chế độ cuối chỉ đi qua, nên
  pinch **không** nhóm lại — nhóm theo năm của On This Day là ngữ nghĩa, không phải hàm của mật độ.
- **Thanh cuộn ngày**: tay nắm 8pt ở mép phải, kéo thì phình 1,6× và hiện bong bóng kính ghi ngày. Ba bẫy:
  1. Cử chỉ kéo của SwiftUI **không nhận chạm** trên lưới UIKit → vùng chạm phải là một lớp UIKit, còn tay
     nắm vẽ bằng SwiftUI thì phải **không nhận chạm**, nếu không nó nuốt trước.
  2. Vật liệu mờ trên nền đen là **vô hình** → tay nắm phải tô màu đặc mờ.
  3. Nhảy tới một vị trí phải **tắt theo dõi neo trước**, vì Library neo ở ảnh mới nhất và sẽ kéo tuột về đáy.

## 5. Chọn bằng vuốt

- Hướng chốt ở **8pt đầu**: ngang thắng dọc rõ ràng (**> 1,15×**) thì là chọn, chéo thì nhường cuộn.
- **Chọn hay bỏ chọn chốt đúng một lần ở đầu cử chỉ**, không tính lại từ trạng thái sống — tính lại thì lần
  gọi kế thấy ô đầu đã được chọn và đảo thành bỏ chọn liên tục.
- Lưới giữ tập id đang chọn và **chỉ vẽ lại những ô đổi trạng thái** — không dựng lại mọi ô đang hiện nên
  ảnh không nháy.
- Giữ ngón trong dải **72pt** mép trên/dưới thì lưới tự cuộn, tăng tốc dần (tối đa 14pt mỗi khung).
- **Giữ lâu rồi kéo tiếp không cần nhả tay**: chính cử chỉ giữ-lâu mồi luôn máy trạng thái quét chọn. Cử chỉ
  kéo thường không làm được — nó chỉ được bật **sau khi** giao diện cập nhật sang chế độ chọn, lúc đó cú
  chạm đã đang bay và hệ thống không giao một touch đang chạy cho cử chỉ vừa bật. Đường này **không khoá
  hướng** (giữ 0,35s đã là chủ ý), và chỉ áp dụng cho cú giữ **đưa vào** chế độ chọn.

## 6. Nhãn thông số trên tile

- Mặc định `ISO 400 · 85mm · f/1.8`; bật thêm tốc độ, **megapixel**, **dung lượng** trong Settings (hai cái
  sau mặc định tắt) → `ISO 400 · 85mm · f/1.8 · 1/500s · 24.2 MP · 12.4 MB`.
- **Ẩn khi ô hẹp hơn ~90pt.**
- Thumbnail xin theo bề rộng ô ở **độ phân giải thật của màn**; ô to lên quá 1,4 lần thì xin bản nét hơn và
  **giữ ảnh cũ tới khi bản mới về**.

## 7. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
