# FS-02 — Photo Detail

`FS-02` · tier C · `Features/Library/PhotoDetailScreen.swift` · `MetadataPanel.swift`
· test `MetadataFormatterTests` · `VideoTransportMathTests` · `VideoTrimMathTests` · cập nhật 2026-09-22

**Một câu:** màn xem một ảnh hoặc một clip — lật trang, phóng, đọc thông số, và mọi hành động trên tấm ảnh đó.

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 01 | [Pager và tải ảnh](01-pager-and-image-loading.md) | lật trang, phóng, thang chất lượng ảnh, iCloud, nhường băng thông |
| 02 | [Video](02-video-playback.md) | trạng thái phát, transport, cử chỉ, tua, lưu khung, toàn màn |
| 03 | [Bảng thông tin](03-info-panel-and-metadata.md) | hai dòng trên chrome, sheet đầy đủ, shutter count, dữ liệu thô |
| 04 | [Hành động và phụ trợ](04-actions-and-extras.md) | menu ⋯, slideshow, Live Photo, Live Text, panorama, cắt video |

## Quy tắc

- **Mở viewer theo id của ảnh, không theo vị trí bắt được từ lưới.** Vị trí bắt đầu được hỏi lại từ chính
  nguồn mà viewer dùng. Giữ một số thứ tự sẽ **mở nhầm ảnh** sau khi một ảnh bị xoá khỏi danh sách, còn tra
  lại vị trí ở mỗi lần vẽ sẽ cho **màn hình đen** khi xoá đúng ảnh đang xem.
- **Không hiển thị giá trị không tồn tại.**
- Mọi thứ đắt (giải mã, tải) chỉ chạy cho **trang đang hiện**, không chạy cho trang nạp trước.
- **Viewer có bộ điều phối hành động riêng**: nó là một lớp phủ toàn màn, mà hai nơi cùng bám một trạng thái
  trình bày thì cả hai đều mở — và sheet của màn gốc thắng bằng cách gỡ luôn lớp phủ.
- **Đóng viewer không được làm Library nạp lại** — xem [01](01-pager-and-image-loading.md).

## Chrome

| Vị trí | Nội dung |
|---|---|
| Trên-trái | nút **X** cao 52pt, và **bảng thông tin ngay bên phải, cùng hàng** |
| Đáy | ba vùng kiểu Photos: **Share** tròn trái · viên kính giữa · **Delete** tròn phải |
| Viên kính giữa | Favorite · Info · (ảnh: Edit) · ⋯ — video ẩn Edit và Resize |

- Toàn bộ chrome ẩn khi: đang phóng, video đang xem toàn màn, hoặc video đang phát và đã 3 giây không chạm.
- **Một hàng ngang, không phải viên kính căn giữa bằng cách xếp chồng**: viên kính nở theo số hành động của
  tấm ảnh; xếp chồng thì nó đè lên Share và Delete — bảy control đòi 288pt trong khe 234pt của máy 402pt.
- Icon trong viên kính **40×40, padding 4**, kèm bề rộng tối thiểu để máy hẹp bóp lại thay vì tràn.
- Chiều cao thanh đáy được **đo thật**; với video cộng thêm vùng an toàn và **40pt** chừa để transport nằm
  hẳn trên nó.
- **Status bar đi theo chrome**: bình thường vẫn hiện với chữ trắng, chỉ ẩn cùng toàn bộ chrome.

## Cử chỉ

| Cử chỉ | Kết quả |
|---|---|
| Vuốt ngang | lật ảnh |
| Pinch / chạm đôi | phóng; vượt 1,01 lần mới bật kéo bên trong |
| Vuốt xuống | đóng viewer — chỉ nhận khi **hướng xuống rõ ràng** và **chưa phóng** |
| Vuốt lên | mở bảng thông tin đầy đủ, giống bấm nút Info |
| Giữ tay (ảnh đã chỉnh) | hiện **bản gốc** + nhãn "Original" ([04](04-actions-and-extras.md)) |

## Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
