# FS-12.06b — Scope, LUT và tracker

`FS-12.06b` · `Domain/Video/VideoScopeMath.swift` · `CubeLUTParser` · `MaskTrackMath`
· test `VideoScopeMathTests` · `CubeLUTParserTests` · `MaskTrackMathTests` · cập nhật 2026-09-22

**Một câu:** ba thứ khiến grade video **đo được, mang look ngoài vào được, và bám theo chủ thể được**.

## 1. Quy tắc

- **Scope đo ảnh đã grade**, không đo ảnh gốc — scope đọc ảnh chưa grade thì đang kể về máy quay chứ không
  phải về grade.
- **LUT chỉ đến từ Files-import**, đúng ranh giới pháp lý đã dựng cho nhạc.
- LUT lỗi báo **ngay lúc import**, khi người dùng còn đang nhìn picker và chọn lại được — không im lặng rồi
  grade sai.
- Tracker nói thẳng **nó chỉ theo được gì**.

## 2. Bốn máy đo

Ở **đầu** panel Color: **Waveform** (luma theo vị trí ngang) · **Parade** (R/G/B cạnh nhau — chân lệch là
ám màu) · **Vectorscope** (hue/saturation, có vòng graticule + đường da người 123°) · **Histogram**.

| Mục | Cách làm |
|---|---|
| Nguồn | thumbnail của clip dưới playhead, giữ lại theo id nên đổi grade **không** gọi lại thư viện ảnh |
| Chuỗi grade | tách ra khỏi compositor và **định nghĩa một chỗ**, scope chạy đúng chuỗi đó |
| Lấy mẫu | render xuống **240×135**, đếm vào lưới |
| Vẽ | **ghi thẳng ra bitmap**, không vẽ từng ô — waveform là 256×128 ô, ba vạn lời gọi vẽ mỗi lần refresh không phải là cách vẽ |
| Cộng dồn | hai vệt chồng nhau đọc ra tổng, như máy đo thật |
| Refresh | khi clip dưới playhead đổi **hoặc** khi bất kỳ phần nào của grade đổi |
| Ngưỡng sáng của vệt | 1/6 chiều cao mẫu — lấy nguyên chiều cao thì chỉ trời phẳng mới sáng |

- **Mỗi lần một scope, full width** (cao 140): bật cả bốn nổi trên viewer thì trên cột 300pt đó là bốn con
  tem.
- **Có ở cả hai layout**, chỉ khác chiều cao (140 ở cột, **96** ở panel của điện thoại): 140 trên panel thì
  chiếm gần hết, còn bỏ hẳn thì phép đo mà cả cái grade dựa vào lại chỉ có trên một loại máy.
- Test khoá: mảng phẳng rơi đúng một mức · đen nằm **đáy** lưới · mọi pixel được đếm **đúng một lần** · ba
  kênh độc lập · xám trung tính rơi đúng tâm vectorscope ở mọi độ sáng · đỏ lệch phải, lam lệch xuống ·
  buffer thiếu byte thì đếm ra rỗng.

## 3. LUT nhập từ Files

Đọc `.cube` chuẩn Adobe: kích thước 2…64, tiêu đề, miền giá trị (**chuẩn hoá về 0…1** — file khai 0…255 mà
không chuẩn hoá thì cháy trắng hết), bỏ qua comment/dòng trống/tab/CRLF, từ khoá không phân biệt hoa thường.

- **LUT một chiều được nở thành khối** (mỗi trục tra chính nó) thay vì từ chối: file 1D là export hợp lệ,
  chỉ là không nói gì về tương tác giữa các kênh.
- **Từ chối dứt khoát** khi: thiếu kích thước · số dòng không khớp · kích thước quá lớn · một dòng không
  phải số.
- Bảng dựng đúng thứ tự mà GPU cần nên đi thẳng từ file lên GPU.
- **Đặt cuối chuỗi**: look pack được viết để là **lời cuối** trên một ảnh đã hiệu chỉnh — đúng chỗ
  colourist đặt nó. Chạy trong sRGB, cùng lý do với film cube và de-log.
- **Strength 0…1** = trộn bản đã LUT lên bản gốc: 60% là cách người ta thực sự dùng một print emulation.
- Recipe chỉ giữ **tham chiếu** (id + tên + strength), bảng nằm trên đĩa: project nhỏ, và LUT đã xoá thì
  thoái hoá về *không có LUT* chứ không thành grade hỏng.
- Cache **4 bảng** để 30 khung/giây không đọc lại file text.

## 4. Tracker cho power window

Dùng bộ theo dõi đối tượng của Vision, mồi bằng đúng khung bao của window.

| Tham số | Giá trị | Vì sao |
|---|---|---|
| Tần suất | **12 mẫu/giây** | đủ để nội suy cho một gradient mép mềm, và giữ một shot 20 giây ở vài trăm lượt thay vì vài nghìn |
| Dừng | 30 giây, hoặc khi độ tin cậy < 0,3 | — |
| Keyframe | lưu **delta** (dịch + tỉ lệ), không phải toạ độ tuyệt đối | người dùng vẫn kéo window sau khi track; delta đi theo chỉnh sửa đó thay vì vứt nó đi |
| Ngoài khoảng đã track | **giữ nguyên hai đầu** | không bật về chỗ vẽ ban đầu |

- Window tròn theo dịch + tỉ lệ; window tuyến tính scale quanh **trung điểm hai tay nắm** — điểm duy nhất
  trên nó có nghĩa.
- **Chỉ theo được vị trí và kích thước**: bộ theo dõi trả về khung trục thẳng, không có xoay/phối
  cảnh/shear. Panel nói thẳng câu đó thay vì để người dùng phát hiện trên một shot nghiêng máy.
- **Qualifier không có nút track** — nó chọn theo giá trị chứ không theo chỗ.
- Cần clip **video** dưới playhead; track chạy **từ playhead** chứ không từ đầu clip (colourist đỗ lại đúng
  khung window vừa khớp rồi mới track tới).
- Test khoá đúng những chỗ sai trông giống "tracker tệ" mà thật ra là dấu hoặc trục: trục y của bộ theo dõi
  chạy ngược trục y của window · tỉ lệ · kẹp khung mồi trong ô đơn vị · nội suy · giữ hai đầu.

## 5. Tiêu chí nghiệm thu

Xem [README](README.md).
