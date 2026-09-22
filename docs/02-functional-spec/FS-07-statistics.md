# FS-07 — Statistics

`FS-07` · tier B · `Features/Statistics/` · `Data/Database/StatisticsQueries.swift` · `ChartStore`
· bảng `stat_charts` · cập nhật 2026-09-22

**Một câu:** một bảng điều khiển biểu đồ **do người dùng tự dựng** — mỗi thẻ là một đặc tả biểu đồ, có
khoảng thời gian riêng.

## 1. Quy tắc

- **Tên cột chỉ đến từ một danh sách đóng trong mã, không bao giờ từ chữ người dùng gõ** → câu truy vấn
  dựng bằng chuỗi vẫn **không có bề mặt tấn công**; chỉ giá trị được truyền vào dạng tham số.
- **Tổng hợp chạy trong database**, không gom trong Swift (trừ việc chia nhóm cho biểu đồ phân bố).
- Mọi truy vấn chạy **ngoài luồng chính**, áp kết quả trên luồng giao diện.
- **Khoảng thời gian thuộc về từng biểu đồ** — không còn một nút chọn chung cho cả màn.
- Điều kiện lọc của biểu đồ **dịch bằng chính bộ dịch của smart album**.

## 2. Một biểu đồ mô tả bằng gì

Loại biểu đồ · **trục X** (nhóm theo) · **trục Y** (đo cái gì) · **điều kiện lọc** · tách chuỗi (chỉ biểu đồ
đường) · giới hạn N mục đầu · **khoảng thời gian**.

| Thành phần | Giá trị |
|---|---|
| Loại | cột ngang · vành khuyên · đường theo thời gian · **một con số** |
| Trục X | nhóm rời rạc (thân máy, hãng, ống kính, khổ cảm biến, favorite) · nhóm theo dải số (ISO, khẩu, tốc độ, tiêu cự thật, tiêu cự tương đương) · theo thời gian (ngày, tháng, năm) |
| Trục Y | **số ảnh** (mặc định) + trung bình / trung vị / tổng / nhỏ nhất / lớn nhất trên một trường số |

- Mỗi loại biểu đồ **tự khai** trục X và phép đo nào hợp lệ với nó — cùng một khuôn với chỗ khai phép so
  sánh hợp lệ của từng trường điều kiện.
- **Trung vị chỉ hợp lệ với biểu đồ một-con-số** — trung vị theo từng nhóm không có cách viết rẻ trong SQL;
  bảng hợp lệ chặn ngay ở giao diện.
- Nhóm theo dải số **dùng lại đúng các mốc chia** mà bộ lọc của Library đang dùng. Lọc theo định dạng file
  thì **hoãn** vì chưa có cột riêng.
- Mỗi trục X ứng với **một cột cố định** và một cách dựng bộ lọc để **bấm vào là mở Library đã lọc sẵn**.

## 3. Lưu trữ

Mỗi biểu đồ là một dòng gồm id, **đặc tả dạng JSON** và vị trí. Mã hoá và giải mã JSON **tự viết** (giống
smart album) để tránh bẫy lồng kiểu dữ liệu của thư viện database.

Lần cài đầu gieo **hai** biểu đồ: **Top Camera** (cột theo thân máy) và **Total Photos & Videos** (một con
số). Cả hai sửa và xoá được. Việc gieo chỉ chạy **một lần duy nhất** — bảng người dùng cố ý xoá sạch không
được tự mọc lại.

## 4. Thẻ và ô soạn

- Mỗi thẻ là một hàng **có nền bo góc riêng**; danh sách bỏ đường kẻ và thêm lề, nên các biểu đồ là những
  khối rời chứ không dính thành một mảng — mà vẫn kéo sắp xếp và vuốt xoá được.
- Tiêu đề thẻ: tên + **khoảng thời gian của chính nó** + menu Edit / Duplicate / Delete.
- Kiểu vẽ: cột ngang (nhãn ở trục Y, mỗi hàng ~28pt, bo góc, dải màu) · vành khuyên (lỗ giữa 0,6) · bảng
  màu dùng chung.
- Chạm một cột, một lát hay một hàng **rời rạc hoặc theo dải** thì mở Library đã lọc sẵn. Biểu đồ **theo
  thời gian không mở được** — bộ lọc đơn giản không có trường ngày.
- Nhóm **"Unknown" bị ẩn khỏi biểu đồ**, và thay bằng một dòng chú "N photos without this info".
- **Ô soạn** soi gương ô soạn smart album: chọn loại · trục X · trục Y · tách chuỗi và N mục đầu · mục
  **Conditions** nhúng **bộ dựng điều kiện dùng chung** · mục **Date Range**. Có **xem trước sống** vẽ bằng
  dữ liệu thật của bản nháp.

## 5. Khoảng thời gian

Mỗi biểu đồ mang khoảng của riêng nó, lưu trong đặc tả; khoảng tuỳ chọn lưu bằng hai mốc thời gian **trọn
ngày**.

- Có sẵn All Time / This Year / This Month + **Custom Range…** mở một bảng chọn khoảng dạng lịch (các tháng
  xếp dọc, chạy từ ảnh cũ nhất tới nay).
- Ảnh **không có ngày chụp** không lọt vào bất kỳ khoảng nào → chỉ xuất hiện ở biểu đồ để All Time.

## 6. Bố cục

| Bề rộng | Bố cục |
|---|---|
| Hẹp | một cột |
| Rộng | **các cột độc lập kiểu masonry** |

- **Không dùng lưới**: lưới ép mọi ô trong một hàng cao bằng ô cao nhất, nên một thẻ một-con-số đứng cạnh
  một biểu đồ cột để lại đúng một lỗ bằng chiều cao biểu đồ cột.
- Thẻ chia vòng tròn vào các cột để giữ thứ tự đọc. Số cột tính theo bề rộng với **bề rộng thẻ tối thiểu
  320pt**, chặn trong **2…3** — ra **2 cột** ở iPad 11" dọc và màn trong Duo, **3 cột** ở iPad 13" dọc và
  iPad ngang.
- **Chế độ sửa quay về một cột ở mọi bề rộng** — kéo đổi thứ tự và nút xoá đỏ là ngôn ngữ của danh sách;
  sửa, nhân bản và xoá vẫn có trong menu của từng thẻ nên bố cục nhiều cột không mất chức năng nào.
- **Chừa 48pt dưới thẻ cuối**, cộng thêm chỗ cho thanh chrome tự vẽ ở bản iOS trước 26 — vùng cuộn dừng
  đúng ở tab bar nổi nên không chừa thì thẻ cuối dính vào nó.
- Màn rỗng: chưa index → "No Indexed Photos"; chưa có biểu đồ nào → "No Charts".

## 7. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../README.md#6-việc-còn-nợ).
