# Intent: Settings trên Mac có đủ các pane như board

| Trường | Giá trị |
|---|---|
| Tác giả | Hoang Tuan (qua Claude) |
| Ngày | 2026-11-04 |
| Trạng thái | accepted (2026-11-04) |
| Tiến độ | **đang làm** (2026-11-04) — task 5/13, 5/14 AC xanh (AC-67…70, AC-72) |
| Nguồn | phản hồi người dùng (cài bản Debug lên Mac, 2026-11-04) |
| Spec sinh ra từ đây | [FS-18.04 §3](../02-functional-spec/FS-18-mac-app/04-other-screens.md) · AC ở [FS-18.06](../02-functional-spec/FS-18-mac-app/06-acceptance-criteria.md) |

## Problem — vấn đề

Mở ShotDex › Settings… trên Mac chỉ thấy một pane General với hai nhóm (Indexing, Background). Board Mac vẽ sáu pane
(General · AI · Sources · Editing · Servers · Cameras) và gần 90 hàng. Người chụp ảnh không:

- thấy và quản lý nguồn ảnh (Re-index, Remove, Grant Access, thêm folder) ngoài sidebar;
- xem thư viện đã index tới đâu — chân sidebar chỉ ghi "Indexing…", không có số, và bị khung Common Photos che mất;
- tra tên địa điểm, quét People and Pets, chặn ngủ khi index, xoá cache;
- xem, xoá kết nối server; chọn thông tin hiện trên ô ảnh; sửa định dạng cảm biến của máy ảnh.

Phần lớn những thứ này đã có trong code dùng chung (agent dò 2026-11-04: ~25 hàng chỉ cần nối), nhưng chưa có chỗ trên
Mac. Comment trong `MacSettingsWindow.swift` ghi "các pane khác đến cùng tính năng của chúng" — hoãn rồi bị quên.

## Proposed outcome — kết quả mong muốn

Settings Mac nhìn giống board ở cả sáu pane. Hàng nào có tính năng thật thì chạy thật; hàng nào Mac chưa có tính năng
phía sau (Export, AI Search, viewer HDR/Autoplay, Statistics Insights, On This Day Reminder, RAW+JPEG trong editor)
vẫn hiện nhưng mờ, để người dùng biết nó sẽ có. Thư viện đang index thì Sources › Index nói đã đọc bao nhiêu trên tổng.

## Affected users and systems — phạm vi ảnh hưởng

- Mac: cửa sổ Settings (`ShotDexMac/Settings/`), ô lưới Mac (`MacPhotoGrid`), `MacDependencies` (ghép thêm sidecar
  writer, People and Pets).
- Không đụng iPhone/iPad/Duo; key `SettingsKeys` dùng chung giữ nguyên nghĩa.
- Dữ liệu: không đổi schema. Key mới chỉ ở `UserDefaults` của Mac.

## Constraints — ràng buộc

- Board trước, code sau: các hàng mờ phải vẽ mờ trên board trước.
- Không thêm dependency. Không đổi nghĩa key đã có (iOS đang dùng).
- Không có pane Privacy, Widgets, ô tìm, nút Save (FS-18.04 §3 giữ nguyên).
- Không chạy cả bộ test hay `Tools/gate` khi chưa được bảo.

## Open questions — câu hỏi còn treo

Đã chốt với người dùng 2026-11-04: làm Sources, Servers, General, Cameras; hàng chưa có tính năng hiện mờ; theo board
sáu pane (có AI); bỏ Group Photos By và Open Photos khỏi spec. Hai câu CẦN QUYẾT của spec chốt theo đề xuất: hàng mờ ở mọi bản (App Store quyết lúc nộp); Index New and Changed Files mờ, luôn bật. Không còn câu treo.
