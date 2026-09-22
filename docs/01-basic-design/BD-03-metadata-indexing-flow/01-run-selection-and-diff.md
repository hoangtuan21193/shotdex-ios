# BD-03.01 — Chọn việc và chạy tiếp

`BD-03.01` · `Domain/Indexing/IndexPipeline.swift` · `Data/Database/MetadataStore.swift`
· test `IndexDiffTests` · cập nhật 2026-09-22

**Một câu:** lượt nào được chạy, ảnh nào phải đọc lại, và điểm nào cho phép chạy tiếp mà không đọc lại từ đầu.

## 1. Quy tắc

- Mọi lượt **không phải đọc-lại-toàn-bộ** đều thử **đường nhanh** trước: hỏi thư viện xem có gì đổi.
- Mốc "đã hỏi tới đâu" **chỉ được lưu khi lượt chạy đi hết và không bị huỷ**.
- Cả hai đường dùng **chung một phép quyết định "ảnh này có cần đọc lại không"** (thuần, có test).
- Huỷ giữa chừng thì **chỉ lưu phần đầu liên tục** — điểm chạy tiếp không bao giờ vượt qua một ảnh chưa đọc.

## 2. Phiên bản của bộ index — điền bù trường mới lên dòng cũ

- Mỗi dòng ghi lại **phiên bản bộ index** lúc viết.
- Bản mới trích thêm dữ liệu (trường EXIF mới, đổi cách chuẩn hoá tên) thì **tăng số phiên bản**.
- Dòng có phiên bản thấp hơn bị coi là **cũ** và được đọc lại, kể cả khi ảnh không đổi gì. Nhờ vậy dòng cũ
  **tự điền bù ở lượt index tăng dần kế tiếp**.
- **Đánh đổi**: tăng phiên bản = đọc lại **toàn thư viện**, chi phí iCloud ngang lần index đầu.

## 3. Đường nhanh — hỏi thư viện thay vì tự quét

- Tập ứng viên = danh sách **thêm / sửa / xoá** mà thư viện trả về kể từ mốc trước, **cộng** những dòng chưa
  đọc xong (một câu hỏi thẳng vào database; thường là rỗng).
- Chỉ đọc lại trạng thái của **đúng các ảnh đó**, theo lô 500 (giới hạn tham số của database), rồi lọc bằng
  **cùng** phép quyết định — nên ngữ nghĩa không đổi, chỉ tập ứng viên nhỏ đi.
- Ảnh mới được ghi một dòng giữ chỗ trước, rồi vào lô đọc EXIF như thường; ảnh bị xoá thì xoá dòng.
- Mốc được **chụp trước khi so sánh, và chỉ lưu khi lượt chạy xong sạch**: thay đổi đến giữa chừng sẽ được
  lượt sau phát lại, và phát lại trùng thì vô hại vì phép quyết định bỏ qua dòng đã xong.
- Chưa có mốc, hoặc thư viện báo mốc **đã quá cũ** (lịch sử thay đổi chỉ giữ một cửa sổ), thì xoá mốc và rơi
  về quét đủ — và chính lượt quét đủ đó lập lại mốc.

**Vì sao cần đường nhanh**: quét đủ phải dựng từng ảnh **hai lượt** chỉ để kết luận "không có gì mới" —
**6,8 giây mỗi lần mở app** trên 54.968 ảnh đã index xong.

## 4. Đường nhanh tự nhường khi việc tồn quá nhiều

| Điều kiện | Ngưỡng | Hành vi |
|---|---|---|
| Việc tồn quá nhiều | **5.000** ảnh chưa xong | bỏ đường nhanh, giao lại cho quét đủ |
| Tập ứng viên có việc thật | **200** ảnh | **bật chỉ báo trước** khi đi hỏi và sắp xếp |

- Phép kiểm việc tồn **phải chạy trước** khi đụng vào lịch sử thay đổi, và phải là **một câu đếm**, không
  phải dựng ra hàng chục nghìn dòng. Lý do: mốc chỉ được lưu khi một lượt chạy xong, nên **việc tồn nhiều
  đồng nghĩa mốc đã cũ**, mà duyệt lịch sử thay đổi từ một mốc cũ đo được **4–10 phút** — toàn bộ công đó
  sẽ bị chính phép kiểm này vứt đi.
- Quá ngưỡng thì đường nhanh **chậm hơn** quét đủ: nó phải hỏi và sắp xếp toàn bộ id chưa đọc (đo: **69,7
  giây cho 42.544 ảnh**, so với **6,8 giây** quét đủ 55.000 ảnh).
- Việc duyệt lịch sử thay đổi **huỷ được** giữa chừng, và có **một dòng log đo thời gian** — khoảng lặng dài
  nhất của đường nhanh giờ luôn có một dòng nói nó vừa tốn bao lâu.
- Ngưỡng 200 là **ca duy nhất** một lượt "không tìm thấy việc" được phép đã bật chỉ báo: 70 giây lập kế
  hoạch mà chỉ báo tắt thì app trông như đã bỏ qua cú mở app. Thà thừa nhận nó đang làm việc còn hơn im lặng.

## 5. Khi nào một ảnh phải đọc lại

| Điều kiện | Giới hạn |
|---|---|
| Ngày sửa của ảnh mới hơn dòng đã ghi | — |
| Dòng đang ở trạng thái **chưa đọc** | vô hạn |
| Dòng **lỗi vì tải được mà đọc không ra** | tối đa 5 lần, rồi kết luận "không có EXIF" |
| Dòng **lỗi vì lý do không phải mạng** | như trên |
| Dòng **chờ iCloud** | vô hạn, nhưng chỉ khi lượt đó được dùng mạng |
| Dòng ghi bởi bản index cũ hơn | — |

"Đã đọc xong" và "chắc chắn không có EXIF" là hai trạng thái **kết thúc**. Lượt tăng dần cũng chạy khi thư
viện báo có thay đổi.

## 6. Thử lại phải nhắm đúng tập

Có hai đường chạy tiếp, và chọn sai đường là hỏng:

- Đường **rẻ** (chỉ đọc lại những dòng lỗi và chờ iCloud) **chỉ đúng khi mọi dòng chưa xong đều thuộc hai
  loại đó**.
- Còn lại — có dòng **chưa đọc**, có dòng ghi bởi bản index cũ — thì phải chạy **lượt tăng dần đầy đủ**.

**Vì sao**: lịch thử lại từng đặt theo "số ảnh đang chờ iCloud", nên một đống 42.544 dòng **chưa đọc** không
kích hoạt được gì cả — mà kể cả có kích hoạt thì đường rẻ cũng **không hề đọc tới chúng**. Đó là một trạng
thái chết thật sự: đo trên máy, 12.495 / 54.971 đứng im qua nhiều lần mở app.

## 7. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
