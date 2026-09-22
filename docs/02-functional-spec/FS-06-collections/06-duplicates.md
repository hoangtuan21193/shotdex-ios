# FS-06.06 — Duplicates

`FS-06.06` · `Features/Duplicates/` · `Domain/Duplicates/` · bảng `perceptual_hash` · `duplicate_groups`
· test `DuplicateSeriesTests` · cập nhật 2026-09-22

**Một câu:** tìm ảnh trùng và gần trùng bằng dấu vân tay hình ảnh, gom nhóm sẵn vào cache, và **để người
dùng tự chọn tấm nào phải đi**.

## 1. Quy tắc

- **Không tự chọn hộ.** App đánh dấu được cả nhóm giúp, nhưng không tự quyết tấm nào bị xoá.
- **Mở màn chỉ đọc cache** — không băm lại, không gom lại.
- **Không tự quét** khi thư viện đổi; chỉ cập nhật số ảnh chưa quét rồi mời Rescan. Ngoại lệ duy nhất: thư
  viện **chưa từng** quét.
- Chỉ ảnh, **không video**.

## 2. Dấu vân tay hình ảnh

Mỗi ảnh xin một bản **96px** (chế độ chất lượng cao để hệ thống gọi lại đúng một lần; dùng mạng theo đúng
chính sách của index), vẽ ép vào lưới xám **9×8** rồi lấy **64 bit**: mỗi bit trả lời "ô này tối hơn ô bên
phải không".

Không lấy được ảnh thì ghi một dòng **rỗng**, và chỉ thử lại ở lượt quét được phép dùng mạng.

## 3. Lượt quét

1. Dọn dòng của những ảnh đã biến mất.
2. Danh sách việc = ảnh **chưa có dấu vân tay**, hoặc **ngày sửa đã lệch** (ảnh vừa chỉnh).
3. Lô **200**, xin **8** ảnh song song, **ghi sau mỗi lô** nên huỷ giữa chừng thì lần sau chạy tiếp.

Tiến độ `Scanning N of M` + Cancel; một lượt tại một thời điểm. Quét yêu cầu thư viện đã index; chưa index
thì màn báo "No Indexed Photos".

## 4. Ba mức

| Mức | Luật |
|---|---|
| **Exact** | dấu vân tay bằng nhau **và** cùng kích thước pixel — bản xuất lại 2000px không gộp với bản gốc 6000px |
| **Similar** | lệch **≤ 10 / 64 bit** — thu nhỏ, xuất lại, cắt nhẹ, ảnh chụp liên tiếp |
| **Series** | cùng khoảnh khắc: cách nhau **≤ 30 giây** và lệch **≤ 20 / 64 bit**, tối thiểu **3** ảnh |

Mức đang dùng được nhớ lại (mặc định Similar), và dải chọn dựng từ **danh sách đầy đủ** nên thêm một mức
không thể quên cập nhật giao diện.

## 5. Gom nhóm

Chạy ngoài luồng chính **sau lượt quét, cho cả hai mức**, mỗi mức ghi cache trong một giao dịch.

- Ảnh trùng dấu vân tay gộp trước bằng một bảng tra; việc tìm "gần giống" chỉ chạy trên **các dấu vân tay
  khác nhau** (một nghìn ảnh chụp màn hình trắng cùng dấu vân tay chỉ còn một đại diện).
- Mẹo lọc: hai dấu vân tay lệch ≤ 10 bit thì **chắc chắn có ít nhất một byte lệch ≤ 1 bit** — nên chỉ cần
  dò 8 byte × 9 biến thể rồi mới đếm chính xác.
- Nhóm là **thành phần liên thông**: a giống b, b giống c thì c vào cùng nhóm dù a và c xa hơn ngưỡng.
- Trong nhóm, ảnh xếp **tốt nhất trước**: nhiều pixel hơn → file lớn hơn → favorite → cũ hơn. Nhóm xếp theo
  ảnh mới nhất trước. Cùng một hàm dựng nhóm cho cả lúc gom mới lẫn lúc đọc cache, nên thứ tự y hệt.
- Đọc cache: ảnh mất dòng dữ liệu hoặc mất khỏi thư viện thì bị bỏ; nhóm còn một ảnh thì biến mất.

## 6. Series — vì sao không dùng lại cách gom kia

Series **không phải một nấc lỏng hơn trên cùng cái thang**: nó hỏi câu khác — *"đây có phải một loạt ảnh của
cùng một khoảnh khắc không"* — và trả lời bằng **thời gian cộng độ giống**. Đúng thứ hai mức kia được xây để
bỏ đi: các khung **cố tình khác nhau** — cùng bối cảnh, đổi tư thế.

- Sắp theo ngày chụp rồi **cắt chuỗi** ở chỗ tấm kế cách tấm **ngay trước nó** quá 30 giây hoặc lệch quá 20
  bit. Nối *hàng xóm với hàng xóm* nên một loạt được phép **trôi**: tấm đầu và tấm cuối có thể rất khác nhau
  miễn mỗi bước ở giữa đều nhỏ.
- Cách gom theo thành phần liên thông sẽ vui vẻ nối hai loạt cách nhau mấy tiếng chỉ vì trông giống nhau.
- Ngưỡng 20 bit rộng hơn mức Similar **có chủ đích** — chủ thể phải cử động thì mới là một loạt; vẫn thấp xa
  mức ~32 bit của hai ảnh không liên quan, và cái siết thật sự là **30 giây**.
- Tối thiểu 3 ảnh: hai tấm cách nhau 20 giây là chuyện chụp bình thường.
- Ảnh **không có ngày chụp bị loại** chứ không đoán — không có thời gian thì không có gì để nối.
- Trong một loạt, ảnh xếp **theo thứ tự chụp**, không phải tốt-nhất-trước: thứ đang xem xét là tư thế đổi
  thế nào từ khung này sang khung kế, mà một loạt sắp theo dung lượng thì không còn là một loạt.
- Ở mức này, dòng tóm tắt là "N series · M photos" và **bỏ** phần "tiết kiệm được bao nhiêu nếu giữ một tấm
  mỗi nhóm" (ở một loạt tư thế, câu trả lời thường là giữ vài tấm), đồng thời **tắt nhãn "Largest"** — tile
  dẫn đầu là khung **đầu tiên**, gắn nhãn đó vào là nói dối về lý do nó đứng đầu. Có màn rỗng riêng.

## 7. Màn hình

Tier A. Dải chọn Exact / Similar / Series + dòng tóm tắt "N groups · M photos · ~X MB if one is kept per
group".

- Mỗi nhóm là một **thẻ**: tiêu đề "N Photos" + nút **Compare** (khi ≥ 2 ảnh) + lưới thumbnail, mỗi ô ghi
  kích thước, dung lượng và ngày.
- Dòng trạng thái: "N photos not scanned yet" / "Library up to date", "Last scan {thời gian}", và nút
  **Rescan** ngay cạnh (menu ⋯ cũng có).
- **Chạm thumbnail = đánh dấu xoá** (biểu tượng thùng rác trắng trên đỏ + viền đỏ 3pt + ảnh mờ — đỏ là phá
  huỷ, phân biệt với dấu tick accent "đang chọn" của lưới), chạm lại thì bỏ. Dấu ghi theo id ảnh nên sống
  qua các lần nạp lại.
- Menu giữ-lâu: **Keep Only This** (đánh dấu mọi ảnh *khác* trong nhóm) · Mark/Unmark · Compare. Thẻ có
  "Clear Selection" khi nhóm có dấu; menu ⋯ có bản cho cả màn.
- **Compare là đường chính** vì thumbnail nhỏ khó phân biệt: nút Compare mở màn so sánh và chia sẻ luôn tập
  dấu; nút đỏ ở đó chỉ xoá **đúng id của nhóm đang mở**
  ([FS-01.08](../FS-01-library/08-compare.md)).

## 8. Merge và Delete

- **Merge All Groups** (menu ⋯): bản giữ lại là **file lớn nhất**, hoà thì **nhiều pixel hơn** — cả hai đều
  là dấu hiệu của "bản ít bị nén lại nhất". Nó **thừa hưởng** những gì bản sao có mà nó thiếu: cờ favorite,
  toạ độ, và **ngày chụp sớm nhất** (bản lưu lại mang ngày lúc lưu lại; khoảnh khắc gốc mới đáng giữ). Chép
  xong **mới** đánh dấu xoá, nên hỏng giữa chừng để lại thư viện còn trùng chứ không để lại bản giữ bị mất
  dữ liệu. Merge **không tự xoá** — nó chỉ đánh dấu.
- **Delete**: thanh đáy nút đỏ cao 50 "Delete N Photos" + dòng phụ "~X MB · Photos move to Recently
  Deleted." Hệ thống hỏi xác nhận; huỷ thì **giữ dấu**. Xong thì xoá dòng dữ liệu tương ứng, cập nhật nhóm
  tại chỗ (nhóm còn một ảnh thì biến mất) và cập nhật số nhóm đã lưu.
- **Không có bước hợp nhất album hay metadata nào khác** — chỉ xoá những ảnh người dùng đánh dấu.

## 9. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
