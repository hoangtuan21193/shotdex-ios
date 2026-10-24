# Intent: bỏ chế độ so sánh Single / 2-Up / Survey của viewer

| Trường | Giá trị |
|---|---|
| Tác giả | Hoang Tuan + Claude |
| Ngày | 2026-10-24 |
| Trạng thái | accepted (2026-10-24) |
| Nguồn | comment của người dùng trên canvas Duo (`DI_Viewer`: "bỏ chức năng 2-up các kiểu đi, khó hiểu, quá phức tạp trên ios"; `DI_CompareSurvey`: "bỏ chức năng này luôn") và câu trả lời phạm vi trong thread đó |
| Spec bị ảnh hưởng | [FS-01.08c](../02-functional-spec/FS-01-library/08c-compare-viewer-mode.md) (bỏ), [FS-01.08](../02-functional-spec/FS-01-library/08-compare.md) (viết lại), FS-06.06 §7.6 (màn so sánh của Duplicates thành màn dùng chung), FS-18 / FS-21 (Mac, iPad) |

## Problem — vấn đề

Viewer có nút chọn **Single · 2-Up · Survey** (FS-01.08c, landed 2026-10-12). Người dùng thấy nó khó hiểu và quá phức tạp trên iOS:

- Ba chế độ trong một viewer, mỗi chế độ một bố cục, một bộ phím, một kiểu đánh dấu (Make Select, candidate, Picked/Rejected, Remove from Survey, Delete N).
- Cùng việc "so mấy tấm gần giống rồi bỏ bớt" đã có một màn khác, gọn hơn, ở Duplicates: hai ô A/B, mỗi ảnh một Keep | Delete, dải ảnh ở dưới.
- Hai cách so sánh cho cùng một việc là hai thứ phải học.

## Quyết định (người dùng chốt 2026-10-24)

1. Bỏ Single / 2-Up / Survey trên **mọi thiết bị** (iPhone, iPad, Duo, Mac): nút chọn trong viewer, màn 2-Up, màn Survey với Picked/Rejected, "Move N Photos…", "Delete N".
2. Nút **Compare** khi chọn 2–6 ảnh (Library, Album, Smart Album, On This Day) mở **cùng kiểu màn so sánh của Duplicates**: hai ô A/B, Keep | Delete từng ảnh, dải ảnh.
3. Ở màn đó từ Library, ảnh chọn Delete được xoá bằng nút **Delete N** trên thanh trên cùng (vào Recently Deleted, như Duplicates). Đóng màn mà chưa bấm thì không xoá gì.
4. Màn so sánh của Duplicates giữ nguyên.

## Không thuộc phạm vi

- Cull (Pick/Reject, sao) giữ nguyên — người dùng không nhắc tới.
- Màn chọn khung burst có Single/Survey riêng (`BurstFramesScreen`) — không phải chế độ của viewer, giữ nguyên.
- Video Studio "Compare" (trước/sau) là tính năng khác.

## Thành công là gì

- Viewer không còn nút chọn chế độ ở bất kỳ kích thước nào.
- Chọn 2–6 ảnh → Compare → màn A/B; đánh dấu Delete, bấm Delete N → ảnh vào Recently Deleted, màn đóng hoặc thu còn ảnh giữ lại.
- Không còn code, chuỗi, board hay spec nào nói về 2-Up/Survey của viewer.
