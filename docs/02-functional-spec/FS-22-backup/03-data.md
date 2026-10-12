# FS-22.03 — Dữ liệu

`FS-22.03` · đề xuất `Data/Database/AppDatabase+Backup.swift` (migration mới sau `v32-cloudPlaceholders`),
`Data/Database/BackupStore.swift` · cập nhật 2026-10-12

**Một câu:** job và sổ là dữ liệu người dùng — bảng riêng, không cột nào trong `photo_metadata`, không bị Clear Local
Metadata Index xoá; sổ là thứ duy nhất quyết định "đã chép chưa".

## 1. Bảng

| Bảng | Một dòng là | Cột chính |
|---|---|---|
| Job backup | một job | id · nguồn (Photos hoặc id nguồn FS-19) · id connection FS-15 · folder đích · Organize (mức, kiểu Year/Month/Day, Custom, chỗ Videos) · tên file · What to Copy · Include Edited · Only on Wi‑Fi · Only While Charging · Keep Screen On · thứ tự · tạo lúc |
| Trạng thái job | trạng thái chạy của một job | id job · mốc thay đổi Photos · lần so cuối · trạng thái + lý do + số (cho dòng `Paused …`) · lượt đầu đã xong chưa |
| Sổ backup | một file của một mục đã xử lý | id job · khoá mục · loại tài nguyên (gốc, RAW, video đi kèm, bản sửa) · dấu nguồn (cỡ + ngày sửa) · đường dẫn ở đích · số byte · SHA-256 (rỗng khi `found`) · kết quả `uploaded` / `found` / `failed` · số lần thử · lỗi cuối · lúc ghi |

- Khoá mục: Photos → id ảnh của Photos; FS-19 → id bản sao trong bảng bản sao. Duy nhất theo (job, khoá mục, loại
  tài nguyên, dấu nguồn).
- Mỗi file `uploaded` **của job nguồn Photos** cũng thêm một dòng vào bảng lịch sử upload FS-15 trong cùng transaction —
  để Photo Detail hiện **Uploaded to Server** và Free Up Space (FS-15.02c) tính được. `found` không thêm (không kiểm
  SHA-256); job nguồn FS-19 không thêm (lịch sử FS-15 tính theo ảnh Photos, bản sao FS-19 đã có chỗ của nó).
- File đã chép xong xoá các dòng `failed` cũ (dấu nguồn khác) của chính nó.
- Settings không đọc được cả khối → job đó dùng mặc định; các job khác vẫn tải.
- Xoá job: xoá trạng thái + sổ của job (khoá ngoại xoá theo). Dòng lịch sử upload FS-15 giữ nguyên.
- Xoá connection FS-15: job của nó xoá theo, sau hộp xác nhận nói số job.
- Xoá nguồn FS-19: job của nó xoá theo ở lần đọc danh sách job kế (không sửa code FS-19).

## 2. Luật

- Clear Local Metadata Index, đọc lại index, khởi động lại: ba bảng trên **không đổi một dòng**.
- So nguồn với sổ: một truy vấn theo job trả tập khoá mục đã có; 55.000 mục ≤ 3 s (README §3).
- Đổi Organize/tên file/folder đích: không sửa sổ; mục đã có trong sổ không chép lại.
- Mật khẩu vẫn ở Keychain theo connection FS-15; bảng job chỉ giữ id connection.
- Decode cài đặt Organize khoan dung: giá trị không đọc được rơi về mặc định của mục đó, không làm hỏng cả job.
