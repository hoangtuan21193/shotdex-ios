# FS-08.02 — Photo Library và index

`FS-08.02` · `Features/Settings/SettingsScreen.swift` · `App/ScreenAwakeCoordinator.swift`
· `Data/Sources/PowerMonitor.swift` · cập nhật 2026-09-25

**Một câu:** mục điều khiển việc đọc thư viện — quyền, chạy tiếp, mạng, giữ màn sáng, và chế độ tiết kiệm pin.

## 1. Quy tắc

- Nút **Continue Indexing** hiện theo **số ảnh chưa đọc xong**, không theo "số ảnh thử lại được".
- Hàng "đã index bao nhiêu" **không được đếm theo số dòng trong database**.
- **Mỗi nút index là một hàng riêng**, và bị **làm mờ** khi đang chạy chứ không bị ẩn.
- App **không bao giờ** giữ màn sáng cho lượt index tự động khi máy đang ở chế độ tiết kiệm pin.

## 2. Các hàng

| Hàng | Ghi chú |
|---|---|
| Access | trạng thái quyền + **Manage photo access** |
| **Continue Indexing (N)** | chỉ hiện khi còn ảnh chưa đọc xong; chạy qua chính model Library nên tiến độ và nút huỷ dùng chung giao diện với mọi lượt index |
| Re-index library | đọc lại từ đầu |
| **Use Cellular Data for Indexing** | mặc định **tắt**; dòng phụ nói rõ mỗi ảnh chỉ tải vài trăm KB, và Wi-Fi thì luôn được phép |
| **Keep Screen Awake While Indexing** | mặc định **tắt** |
| Tiến độ | một hàng riêng, **không chạy hoạt ảnh** |
| Lần index gần nhất | — |
| **Indexed Photos and Videos** | `12,495 of 54,971`, gọn lại còn một số khi đã đọc hết; đang chạy thì lấy số sống từ tiến độ |
| Library Size | tổng dung lượng đã biết; chưa biết hết thì in kèm `~` vì con số mới là **sàn** |
| Privacy | giải thích xử lý cục bộ + **Clear local metadata index** (phá huỷ, có hộp xác nhận) |

- **Không có hàng Import** (bỏ 2026-09-24, [FS-10](../FS-10-import.md)): ShotDex đọc thư viện Photos, không
  nhập file.

- **Vì sao không đếm theo số dòng**: lượt index nhanh ghi một dòng giữ chỗ cho **mọi** ảnh trong vài giây,
  nên số dòng bằng cỡ thư viện ngay từ lần chạy đầu — hàng cũ vì thế luôn đọc thành 100% dù mới index 23%.
- **Vì sao Continue Indexing đếm theo "chưa đọc xong"**: một lượt bị dừng giữa chừng để phần còn lại ở trạng
  thái *chưa đọc*, nên số "thử lại được" bằng 0 và Settings chỉ còn mỗi Re-index Library — tức là vứt hàng
  chục nghìn lượt đọc đã xong đúng lúc người dùng chỉ cần "chạy tiếp". Nút này làm mới số đếm rồi chọn
  **đường rẻ nhất còn đúng** ([BD-03.01](../../01-basic-design/BD-03-metadata-indexing-flow/01-run-selection-and-diff.md)).
- **Vì sao mỗi nút một hàng**: thay nút bằng khối tiến độ làm **tập hàng của mục đổi**, mà danh sách thì
  chạy hoạt ảnh cho thay đổi đó — bấm Re-index là thấy cả màn trượt, trong khi gộp cả khối vào một hàng thì
  hai nút dính chung một dòng. **Làm mờ thay vì ẩn cũng chính là phản hồi cho cú bấm**: lượt chạy thủ công
  bật cờ **đồng bộ** nên hàng xám ngay khung hình đó, và một hàng đã mờ thì không bị bấm dồn để chạy hai lượt.

## 3. Keep Screen Awake While Indexing

Bật **và** đang index thì màn không tự tắt.

- **App không bao giờ đổi độ sáng màn** — giữ nguyên độ sáng người dùng đã chọn suốt lúc index.
- **Bỏ tự hạ sáng** (2026-09-25): bản cũ hạ độ sáng về 0.15 sau 1 phút không chạm. "Không chạm" không có
  nghĩa là "không dùng": gõ phím, share sheet (chạy ở process khác), video đang phát, slideshow đều bị tính
  là nhàn rỗi, nên màn tối ngay lúc người dùng đang nhìn. Ai muốn tiết kiệm pin thì tắt thiết lập này — màn
  sẽ ngủ theo Auto-Lock của hệ thống.
- Một lượt lưu người dùng đang chờ (FS-14.01 §6) vẫn giữ màn sáng bất kể thiết lập, như trước.

## 4. Chế độ tiết kiệm pin

App theo dõi cả trạng thái tiết kiệm pin lẫn trạng thái sạc.

| Tình huống | Hành vi |
|---|---|
| Vào chế độ tiết kiệm pin | **dừng** lượt index đang chạy và **chặn mọi lượt tự động** |
| Lượt tự động trong chế độ đó | không giữ màn sáng — để màn ngủ theo hệ thống |
| Người dùng tự bấm chạy | vẫn chạy và vẫn giữ màn sáng |
| Cắm sạc khi đang tiết kiệm pin | **tự chạy tiếp** — ngoại lệ tự-chạy duy nhất, và chạy không giữ màn sáng |

## 5. Tiêu chí nghiệm thu

Xem [05](05-acceptance-criteria.md).
