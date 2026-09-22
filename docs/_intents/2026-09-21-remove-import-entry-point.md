# Intent: Bỏ Import ra khỏi Settings

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan@karabiner.tech |
| Ngày | 2026-09-21 |
| Trạng thái | draft |
| Nguồn | phản hồi người dùng (tách ra từ intent layout Settings trên iPad) |
| Spec sinh ra từ đây | (điền khi sang Design) |

## Problem — vấn đề

"Import Photos" đang là một hàng trong nhóm **Photo Library** của Settings
([SettingsScreen.swift:100](ShotDex/Features/Settings/SettingsScreen.swift:100) mở
`ImportScreen` bằng `fullScreenCover`). Đó là chỗ sai: Settings là nơi chỉnh cách app
cư xử, còn Import là một **hành động lên thư viện** — nó đứng cạnh "Use Cellular Data
for Indexing" và "Look Up Place Names", những thứ bật/tắt rồi quên đi.

Người dùng quyết dứt khoát hơn: ShotDex là app **đọc** thư viện ảnh của hệ thống, không
phải app quản lý file. Ảnh vào máy bằng Photos, ShotDex index những gì có sẵn. Một lối
Import riêng trong Settings tạo cảm giác ShotDex có kho ảnh riêng — nó không có.

Bằng chứng về phạm vi: `ImportScreen` **chỉ có đúng một lối vào trong cả app** —
`grep -rn "ImportScreen" ShotDex` ra hai dòng, một là chính định nghĩa
`Features/Import/ImportScreen.swift:11`, một là chỗ gọi ở Settings. Bỏ hàng đó là màn
không còn ai mở.

## Proposed outcome — kết quả mong muốn

Settings không còn hàng Import. Không có lối vào nào khác thay thế: người dùng đưa ảnh
vào bằng Photos (hoặc AirDrop, cáp, iCloud) rồi ShotDex index như bình thường — điều
đang xảy ra sẵn với 100% ảnh hôm nay. Nhóm Photo Library ngắn lại còn đúng những thứ
thuộc về nó: quyền, tiến độ index, và các công tắc điều khiển index.

Không còn code chết nằm lại: `Features/Import/` và phần `importService` của composition
root ra đi cùng, hoặc được nêu rõ lý do giữ lại.

## Affected users and systems — phạm vi ảnh hưởng

- **Màn hình**: `Features/Settings/SettingsScreen` (hàng Import + `fullScreenCover`),
  `Features/Import/ImportScreen` và mọi thứ chỉ nó dùng.
- **Tầng code**: `Features/` và một mục trong `App/AppDependencies.swift`
  (`importService`) — cần kiểm xem service đó còn ai gọi không.
- **Thiết bị**: mọi thiết bị. Không phải chuyện size class.
- **Dữ liệu đã lưu**: ảnh đã import trước đây **vẫn nằm trong thư viện Photos** và vẫn
  được index như mọi ảnh khác — bỏ lối vào không xoá gì. Cần xác nhận lại điều này ở
  giai đoạn Design trước khi gỡ code.
- **Tài liệu**: `docs/02-functional-spec/FS-10-import.md` (6.0K) phải được gỡ hoặc đổi
  thành ghi chú "đã bỏ", và `FS-08-settings/README.md` bỏ mục Import.

## Constraints — ràng buộc

- **Không xoá dữ liệu người dùng**, không đụng tới ảnh đã có trong thư viện.
- Việc gỡ code chỉ làm khi đã chắc không còn ai gọi — Share extension và Shortcuts cũng
  phải được kiểm (`EX-03`, `EX-04`), không chỉ app chính.
- Không thay bằng một lối vào khác (người dùng đã bác cả menu ⋯ của Library lẫn nút ở
  Collections).
- Nếu có chuỗi hiển thị nào trong String Catalog chỉ phục vụ Import thì gỡ cùng, không
  để lại rác dịch thuật.

## Open questions — câu hỏi còn treo

- Có ai từng thực sự dùng Import không (TestFlight chưa phát hành, nên nhiều khả năng
  là không) — nếu app đã ở tay người ngoài thì cần một dòng ghi chú thay đổi.
  *Ai trả lời được*: chính người dùng / lịch sử phát hành.
- `ImportService` có phần nào được tái dùng ở chỗ khác (ví dụ ghi ảnh sau khi sửa) hay
  không. *Trả lời được bằng cách đọc code ở giai đoạn Design.*

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
