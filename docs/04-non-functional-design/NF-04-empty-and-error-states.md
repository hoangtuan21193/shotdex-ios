# NF-04 — Trạng thái rỗng và trạng thái lỗi

`NF-04` · cập nhật 2026-10-02

**Một câu:** danh mục empty/error state toàn app, luật viết chúng, và ba trạng thái thiếu dữ liệu
(Limited, Denied, chờ iCloud) trên Library + Statistics ở cả bốn thiết bị.

## 1. Luật

- Empty state ngắn, nói **việc đang xảy ra** và **hành động tiếp theo**, không nói thuật ngữ.
- Mọi lỗi phải kèm lối ra: nút, hoặc câu chỉ đúng chỗ cần mở.
- Không có trạng thái im lặng: thứ gì đang chạy lâu phải nhìn thấy được.
- **Dữ liệu thiếu thì nói ở chính màn đang trả thiếu**, không chỉ ở Library: Statistics tính trên tập được cấp
  hay trên phần đã đọc thì phải ghi ra điều đó ([FS-07.01b §5](../02-functional-spec/FS-07-statistics/01b-cards-editor-and-states.md)).

## 2. Danh mục

| Trạng thái | Nội dung |
|---|---|
| Chưa cấp quyền | giải thích + nút mở Settings |
| Limited Photos Access | giải thích + nút **Manage** chọn thêm ảnh |
| Không có ảnh | câu ngắn, không hành động bắt buộc |
| Đang index | dòng tiến độ "… · N%", không chặn thao tác khác; Statistics: "Still reading photo info · N%" |
| Không khớp filter | "No photos match these filters." + nút **Clear Filters** |
| Không có EXIF | hiện dữ kiện `PHAsset` thuần thay vì ô trống |
| Camera chưa xác định cảm biến | lối vào Unknown Cameras trong Settings |
| Index bị lỗi | nói lỗi + nút thử lại |
| Ảnh iCloud chưa tải về | trạng thái tải, và khi iCloud không phản hồi thì nói rõ ([BD-03.04](../01-basic-design/BD-03-metadata-indexing-flow/04-progress-and-background.md)) |

## 3. Limited, Denied, chờ iCloud trên Library và Statistics

| Trạng thái | Library | Statistics |
|---|---|---|
| Limited | banner Limited Access + Manage trên lưới; lưới chỉ có ảnh được cấp | cùng banner ở đầu màn; số liệu trên tập được cấp |
| Denied | "No Access to Photos" + Open Settings, không lưới | cùng empty state; không biểu đồ, không Insights |
| Chờ iCloud | thẻ "iCloud not responding" với đếm ngược, Retry Now, Use Cellular trong bảng index | dải "iCloud isn't responding · N photos not read yet" + Retry Now |

| Thiết bị | Luật bố cục chung cho ba trạng thái |
|---|---|
| iPhone 402×874 | banner / dải trải bề rộng nội dung, lề 16pt; empty state căn giữa vùng giữa nav bar và tab bar |
| iPad 1376×1032 · 1032×1376 | banner / dải trải hết bề rộng nội dung, **trên** các cột; empty state của hệ thống căn giữa |
| Duo trong 951×669 | như iPad; banner + dải cộng lại ≤ 1/4 chiều cao cửa sổ (167pt) |
| Duo ngoài 466×678 | như iPhone, trong vùng an toàn — không lấn dải hệ thống 84pt bên phải |

- Chữ và nút **giống hệt nhau** giữa Library và Statistics cho cùng một trạng thái — một banner, một empty state.
- Duplicates và Search ngoài phạm vi bảng này; mỗi màn tự ghi khi được đặc tả.
- Board (mới, chưa vẽ — F3): `Main` · `Main` (iPad) · `Main` (Duo) · `DC_Library` và `PH_Statistics` ·
  `IP_Statistics` · `DI_Statistics` · `DC_Statistics`, mỗi board ba trạng thái — 24 artboard. Vẽ xong thì chạy
  agent `ux-reviewer` trên chúng trước khi code.
