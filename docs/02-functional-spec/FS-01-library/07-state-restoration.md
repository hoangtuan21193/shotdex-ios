# FS-01.07 — Khôi phục trạng thái

`FS-01.07` · `App/RootTabView.swift` · `Features/Library/LibraryModel.swift` · cập nhật 2026-09-22

**Một câu:** cái gì thuộc về **cửa sổ** thì lưu theo cửa sổ, cái gì thuộc về **người dùng** thì lưu theo app.

## 1. Quy tắc

| Thứ | Lưu theo | Vì sao |
|---|---|---|
| Tab đang mở | **cửa sổ** | trên iPad hai cửa sổ có thể ở hai tab khác nhau và hệ thống khôi phục từng cái một |
| Thứ tự sắp xếp của lưới | **app** | người cull theo rating mong ngày mai mở lên lưới vẫn ở thứ tự đó, **ở bất kỳ cửa sổ nào** |
| Mật độ lưới | **app** | như trên, dùng chung Library và Album Detail |

## 2. Chi tiết

- **Tab tìm kiếm không bao giờ được khôi phục**: mở lại app thấy ô tìm kiếm rỗng và không kết quả đọc như
  app hỏng — và đó cũng không phải nơi người dùng *đang xem*, chỉ là nơi họ gõ.
- Việc đọc/ghi trạng thái được bọc **một lần cho cả hai nhánh iOS**, không gắn riêng từng nhánh: hai nhánh
  đó đã lệch nhau nhiều lần, và một tính năng chạy đúng trên một phiên bản còn im lặng trên phiên bản kia là
  phiên bản tệ nhất của nó. Nó chạy **đúng một lần mỗi cửa sổ**.
- Giá trị sắp xếp lạ (bản cũ có kiểu nay đã bỏ) rơi về mặc định, không để lưới ở một trạng thái mà menu sắp
  xếp không hiển thị được.

## 3. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
