# FS-06.04 — People and Pets

`FS-06.04` · `Data/Sources/SubjectVisionReader.swift` · `Domain/Indexing/SubjectScanPipeline.swift`
· bảng `subject_scan` · cập nhật 2026-09-22

**Một câu:** một lượt quét **người dùng tự bấm**, chỉ **đếm** người và thú — nó không biết ai là ai, và nói
thẳng điều đó.

## 1. Quy tắc

- **Không bao giờ tự chạy, và tuyệt đối không nằm trong lượt index.** Index chỉ đọc phần đầu file, không
  giải mã ảnh; nhét việc nhận dạng vào đó là biến một cú đọc header thành giải mã toàn bộ thư viện.
- Đây là **chỗ duy nhất trong app giải mã ảnh hàng loạt**.
- **Chỉ đếm, không nhận diện.** Bộ thị giác của hệ thống **không công bố** bất kỳ cách lấy đặc trưng khuôn
  mặt nào (đã tra tài liệu SDK) — app **không thể** phân biệt người này với người kia, càng không đặt tên.
- Đọc không ra ảnh → **không ghi gì**. Ghi một dòng "0 người" ở đây sẽ thành câu "trong ảnh này không có ai"
  mà thật ra **chưa ai nhìn**.

## 2. Lượt quét

| Tham số | Giá trị |
|---|---|
| Ảnh xin về | cạnh **512px**, ở **chế độ chất lượng cao** |
| Số lượt phân tích | **một** lượt chạy cả hai việc: tìm khuôn mặt và nhận chó/mèo |
| Lô | 100 ảnh |
| Đọc song song | **4** |

- Chế độ chất lượng cao để hệ thống gọi lại **đúng một lần** — cặp "bản thô rồi bản nét" làm luồng chờ bị
  đánh thức hai lần.
- Một lượt phân tích cho cả hai việc nên ảnh chỉ giải mã và chuẩn bị **một** lần.
- Bốn luồng thấp hơn lượt quét ảnh trùng: bên kia nghẽn ở đường hỏi hệ thống, bên này nghẽn ở CPU.
- Huỷ thì lô đang bay vẫn **ghi xong rồi mới dừng**, nên lần sau chạy tiếp từ danh sách việc chứ không làm lại.
- Danh sách việc = mọi ảnh **chưa có dòng nào** trong bảng kết quả
  ([BD-02](../../01-basic-design/BD-02-database-design.md)).

## 3. Trên màn hình

- Tile **People / Pets** ở tab Collections **chỉ hiện khi đã tìm được**: một tile "People" trống đọc ra như
  "bạn không có ảnh ai cả", trong khi sự thật là "chưa có gì nhìn qua". Lời mời quét nằm ở Settings.
- **Không có màn People kiểu Apple** (lưới từng khuôn mặt có tên) — xem quy tắc §1.
- Settings hiện `Scanned N of M`, nút **Find People and Pets** / **Scan Again**, dòng tiến độ + **Cancel**
  lúc đang chạy, và **Clear Results** — thứ người dùng cần để rút lại quyết định.

## 4. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
