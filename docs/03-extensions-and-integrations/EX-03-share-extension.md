# EX-03 — Share Extension (Save to ShotDex)

`EX-03` · `ShotDexShare/` · cập nhật 2026-09-22

**Một câu:** nhận ảnh từ app khác, xin đúng mức quyền tối thiểu, ghi vào thư viện rồi đóng.

## 1. Quy tắc

- Xin **quyền chỉ-thêm-ảnh** — vừa đủ để thêm, và là mức ít nhất người dùng phải cấp.
- Hệ thống **xoá file tạm ngay khi trả xong**, nên phải **chép sang thư mục riêng trước** khi ghi vào thư viện.
- Ảnh nào đọc không được thì **tính là thất bại, không bỏ cả mẻ**.
- **Quyền khai mà không dùng là bề mặt thừa**: extension này **không** khai vùng chia sẻ với app, vì nó chỉ
  ghi ảnh vào thư viện ([NF-03](../04-non-functional-design/NF-03-privacy-and-security.md)).

## 2. Cấu hình

| Mục | Giá trị |
|---|---|
| Tên hiển thị | "Save to ShotDex" |
| Số ảnh nhận tối đa một lần | **40** |
| Giao diện | dựng bằng mã, **không storyboard** |

Dùng một màn thường chứ **không** dùng khung soạn nội dung của hệ thống: ở đây **không có gì để soạn** —
sheet nói sẽ làm gì, làm, rồi đóng.

## 3. Trạng thái

sẵn sàng → đang lưu (N trên M) → xong (đã lưu / thất bại), cộng hai nhánh: **không có gì để lưu** và **bị
từ chối quyền**.

App index metadata cho ảnh mới ở lần mở sau.

## 4. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../README.md#6-việc-còn-nợ).
