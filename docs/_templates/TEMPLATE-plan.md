# Kế hoạch — <tên tính năng>

| Trường | Giá trị |
|---|---|
| Đặc tả | `docs/02-functional-spec/FS-xx-…` |
| Ngày | YYYY-MM-DD |
| Trạng thái | nháp / đã duyệt / đang làm / xong |

## 1. Hiểu đúng chưa

Tóm tắt lại yêu cầu bằng lời của mình, 3–5 dòng. Nếu tóm tắt lệch với đặc tả → dừng, hỏi lại.

## 2. Chỗ nào trong code

| File | Đụng gì | Mới / sửa |
|---|---|---|
| … | … | … |

Tầng nào nhận logic: Domain (thuần, test được) / Data (store, service) / Features (view + model).
Logic **không** được nằm trong View.

## 3. Thứ tự task

| # | Task | AC tương ứng | Test kèm theo |
|---|---|---|---|
| 1 | … | AC-1 | … |
| 2 | … | AC-2, AC-3 | … |

Mỗi task là một commit. Task nào không map được sang AC nào → task đó thừa hoặc AC đang thiếu.

## 4. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| … | … | … |

## 5. Phản biện (điền sau khi chạy `challenger`)

| Phản đối | Trả lời / thay đổi |
|---|---|
| … | … |

## 6. Cách chứng minh là xong

- Test: …
- Màn hình phải chụp: … (mỗi state, cả hai nhánh iOS 26, mỗi loại thiết bị)
- Tài liệu phải cập nhật: …
