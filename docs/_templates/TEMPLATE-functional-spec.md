# FS-xx — <Tên màn hình / tính năng>

`FS-xx` · tier <A|B|C|D> · `ShotDex/Features/<Tên>/` · `ShotDexTests/<Tên>Tests.swift` · cập nhật YYYY-MM-DD

**Một câu:** <màn nào, người dùng làm được gì ở đó>.

> Luật viết: trần 120 dòng · mỗi bullet tối đa 2 dòng · không kể lịch sử bug ·
> **không viết code** (tên hàm, property, modifier, enum case) — viết quyết định và hệ quả.
> Section nào không hợp thì bỏ, cần thì thêm — template là điểm khởi đầu, không phải luật.

## 1. Người dùng cần gì

2–4 dòng, viết từ phía người chụp ảnh. Không viết được đoạn này thì tính năng chưa đáng làm.

## 2. Phạm vi

**Có:**
- …

**Cố ý không có:**
- … — vì …

## 3. Trạng thái màn hình

| Trạng thái | Điều kiện | Hiển thị |
|---|---|---|
| rỗng | chưa có dữ liệu | … |
| đang tải | … | … |
| bình thường | … | … |
| lỗi | … | thông báo + hành động tiếp theo |
| quyền giới hạn | `.limited` | … |

## 4. Hành vi

- …

## 5. Dữ liệu

| | |
|---|---|
| Đọc từ | … |
| Ghi vào | … |
| Người dùng tự nhập? | có → **bảng riêng**, không thêm cột `photo_metadata` ([BD-02](../01-basic-design/BD-02-database-design.md)) |

## 6. Ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Hiệu năng | … ([NF-01](../04-non-functional-design/NF-01-performance.md)) |
| Bộ nhớ | … |
| Thiết bị | iPhone 402×874 · iPad 1376×1032 · Duo trong 951×669 · Duo ngoài 466×678 |
| iOS 26 vs trước | cả hai nhánh làm được cùng một việc |
| Truy cập | nhãn VoiceOver cho mọi control tự vẽ |

## 7. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | … | … | … | `XxxTests.yyy` |
| AC-2 | … | … | … | `ShotDexUITests/scripts/xxx.json` + ảnh |

**Chưa chứng minh được:** AC-… — không xoá mục này để làm nó trống.

## 8. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| … | … |
