# Intent: Menu Combine Photos đặt tên theo mục đích

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan@karabiner.tech |
| Ngày | 2026-09-23 |
| Trạng thái | accepted |
| Tiến độ | **đang làm** (2026-09-23) — task 6/9, 1/15 AC xanh (AC-4), AC-12 một nửa; Library: Cancel giữ chọn, Save mở viewer — chưa chụp màn |
| Nguồn | phản hồi người dùng (trong lúc soạn FS-14 panorama) |
| Spec sinh ra từ đây | [FS-01.09](../02-functional-spec/FS-01-library/09-photo-stacking.md) |

## Problem — vấn đề

Người chụp muốn làm một việc cụ thể: lấy nét toàn cảnh cho ảnh macro, xoá người qua đường, vẽ vệt
sao, ghép panorama. App lại gọi tên theo **phép toán**, nên người đó phải đoán việc mình cần nằm
dưới chữ nào:

- Menu ⋯ của chế độ chọn có một dòng **Combine Photos**
  ([SelectionBarViews.swift:211](ShotDex/Features/Library/SelectionBarViews.swift:211)). Tên không nói
  nó làm được gì.
- Vào trong thì bộ chọn mode ghi `Average` · `Lighten` · `Darken` · `Focus Stack`
  ([PhotoStackRenderer.swift:25](ShotDexKit/Render/PhotoStackRenderer.swift:25)). Đó là tên chế độ hoà
  trộn, không phải tên việc cần làm. Muốn xoá người qua đường mà chọn `Darken` là điều không ai tự đoán
  ra. Chỉ sau khi chọn mode, dòng giải thích bên dưới mới nói nó dùng vào việc gì
  ([PhotoStackRenderer.swift:36](ShotDexKit/Render/PhotoStackRenderer.swift:36)).
- FS-14 sắp thêm **Create Panorama** thành một dòng riêng nữa. Thêm nó vào thì menu ⋯, vốn đã có
  9 dòng hành động trước nhóm thư viện và nhóm xoá, lại có hai dòng "ghép nhiều ảnh" nằm tách nhau.

Người dùng tự nói ra vấn đề: *"dùng tên menu là Darken hay Lighten thì không ai hiểu cả"*.

Mức độ: không phải lỗi, chức năng vẫn chạy. Nhưng thao tác nào không tìm thấy thì cũng như không có.

## Proposed outcome — kết quả mong muốn

- Menu ⋯ có **một** dòng **Combine Photos ▸**. Mở ra là danh sách việc người chụp muốn làm (lấy nét
  toàn cảnh, xoá người qua đường, vệt sáng, giảm nhiễu, panorama…). Mỗi dòng mang tên **việc** đó,
  không mang tên phép toán.
- Chọn một dòng là vào thẳng công cụ đã đặt sẵn cho việc đó, không phải chọn mode lần nữa.
- Dòng nào không làm được với lựa chọn hiện tại (ví dụ chưa đủ ảnh) thì hiện mờ, không ẩn đi.

## Affected users and systems — phạm vi ảnh hưởng

- **Màn hình**: menu ⋯ của chế độ chọn (dùng chung cho 4 lưới qua `RootTabView`); màn Combine
  (`PhotoStackScreen`, phần bộ chọn mode và tiêu đề); lối vào của FS-14 panorama.
- **Thiết bị**: iPhone, iPad, Duo. Cả nhánh iOS 26 lẫn trước 26 đều phải mở được menu con.
- **Tầng code**: Features (menu, màn hình), String Catalog. Không đụng render, không đụng Domain.
- **Dữ liệu đã lưu**: không có.
- **Tài liệu**: FS-01.06 (menu ⋯), FS-01.09 (Combine), FS-14 §1 lối vào, DESIGN §10.3b.

## Constraints — ràng buộc

- **Không đổi hình ảnh ra**: cùng một mục đích thì cho ra đúng ảnh như mode tương ứng hiện nay.
- **Menu con chỉ một cấp**, không lồng menu trong menu.
- Chữ theo giọng Apple, câu ngắn, đi qua String Catalog.
- Điện thoại có đủ mọi dòng mà iPad có.
- Việc đổi Darken sang Median để xoá người qua đường đã được người dùng **bỏ qua**, không nằm trong
  intent này.

## Open questions — câu hỏi còn treo

1. ~~Các dòng~~ — **chốt 2026-09-23**, theo thứ tự: `Focus Stack` · `Panorama` · `Remove Moving People`
   (Darken) · `Light Trails` (Lighten) · `Reduce Noise` (Average).
2. ~~Average ba việc~~ — **chốt theo câu 1: một dòng `Reduce Noise`**; câu giải thích trong màn nhắc thêm
   việc giả phơi sáng dài.
3. ~~Bộ chọn mode trong màn~~ — **chốt 2026-09-23: không.** Mỗi màn một việc, tiêu đề là tên mục đích;
   muốn việc khác thì quay lại menu.
   **Đổi lại 2026-09-23, sau khi viết spec:** menu con còn ba dòng Focus Stack · Panorama · **Stack Exposures**.
   Stack Exposures mở một màn có bộ chọn `Average · Lighten · Darken` (mặc định Average), mỗi mode kèm câu nói
   dùng để làm gì. Menu vẫn không mang tên phép toán; tên phép toán chỉ nằm trong màn, luôn đi kèm câu giải thích.
4. ~~Tên dòng mở menu con~~ — **chốt 2026-09-23: giữ `Combine Photos`.**
5. ~~Thứ tự~~ — **chốt 2026-09-23: intent này làm trước**, intent focus stack thay phần bên trong sau.
   FS-14 đổi lối vào từ dòng riêng `Create Panorama` sang dòng `Panorama` trong menu con.

Không còn câu treo.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
