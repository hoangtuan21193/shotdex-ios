# FS-08.04 — Photo Widget designs

`FS-08.04` · `Features/Settings/PhotoWidgetDesignsScreen.swift` · `PhotoWidgetSettingsScreen`
· `WidgetShared/` · cập nhật 2026-09-22

**Một câu:** màn sửa widget ảnh — danh sách design, bản xem trước kéo được, và **mỗi dòng chữ đặt riêng**.

Phía widget (payload, dòng thời gian, quyền): [EX-02](../../03-extensions-and-integrations/EX-02-widget.md).

## 1. Quy tắc

- **Một ngón, một việc — quyết ngay lúc chạm xuống.** Trúng một dòng thì chọn và kéo dòng đó; trúng nền thì
  bỏ chọn và kéo ảnh.
- **Cử chỉ giữ trạng thái tạm, chỉ ghi lại khi nhả tay.** Ghi vào kho ở mỗi khung sẽ đẩy một thay đổi ngược
  về chính cái view đang tự đo mình, và giao diện **sập**.
- **Bản xem trước không được cuộn ra khỏi ngón tay** — nó là thứ mọi hàng bên dưới đang sửa.
- Về đúng 100% thì **xoá khỏi file** thay vì lưu số 1.

## 2. Danh sách design

Mỗi hàng là tên + một dòng phụ "widget này mang những gì — lấy ảnh từ đâu".

- **Add Design** đưa thẳng vào màn cài đặt của design vừa tạo, không bắt người dùng đi tìm hàng mới hiện ra.
- Đổi tên và nhân bản qua menu giữ-lâu, xoá bằng vuốt.
- **Xoá cái cuối cùng bị từ chối** — widget đã đặt trên màn hình phải có gì đó để đọc.
- Mục Widgets ở Settings chỉ là **một hàng**: giá trị là tên design khi chỉ có một, "N designs" khi nhiều hơn.

## 3. Màn cài đặt một design

Cấu trúc: **bản xem trước ghim trên cùng → đường kẻ → danh sách tuỳ chọn**. Không phải một danh sách có bản
xem trước nằm trong đó.

| Thành phần | Chi tiết |
|---|---|
| Chuyển cỡ | dải chọn ngay dưới bản xem trước: Small 158×158 · Medium 329×158 · Large 329×345 — đúng số đo iOS dùng trên máy 6,1" |
| Hàng chip thành phần | **Photo** · Time · Date · Weather · Calendar — viên nang cao 32pt nhưng **nút cao 44pt**; quá năm chip hoặc cỡ chữ lớn thì hàng **cuộn ngang** chứ không bị cắt |
| Bàn phím mũi tên | bốn mũi tên bước 5% khoảng trống + nút đưa về giữa |
| Thanh cỡ | **mọi dòng đều đổi cỡ được** (bản cũ chỉ có hai thanh, với tới giờ và dòng phụ, còn khối thời tiết và lịch không có cỡ riêng) |
| Các mục | Background · Time and Date · Calendar · Weather · Typeface · Colour · **Arrangement** |

- **Chip "Photo" chính là "không chọn dòng nào" được đặt tên ra**: luật "không chọn gì thì kéo và phóng ăn
  vào ảnh" đúng nhưng vô hình, và đây cũng là đường quay về ảnh mà không phải mò khe hở giữa hai dòng chữ.
- **Chọn một dòng thì cuộn thẳng tới Arrangement** — nó là mục thứ bảy, nên chọn khối thời tiết trên một
  bản xem trước 158pt xong thì các điều khiển của chính nó nằm dưới năm mục không liên quan, không có gì
  báo là chúng tồn tại. Chỉ cuộn khi đi **từ không-chọn-gì sang có chọn**; bỏ chọn thì không giật danh sách
  đi đâu cả.
- Calendar và Weather **không còn bị khoá theo loại widget** — mỗi mục mở đầu bằng một công tắc, phần còn
  lại hiện theo công tắc đó. Một design mới bật sẵn **giờ và ngày**, tắt hai cái kia — đúng cái người ta
  đặt nhiều nhất, và hai cái kia chỉ cách một công tắc.
- **"Stack Everything Together" và "Reset Photo Framing" là hành động phá huỷ** (xoá mọi vị trí và cỡ đã kéo
  tay, hoặc mọi mức phóng và vị trí ảnh). **Không thêm hộp xác nhận** — kéo lại được trong vài giây, mức mất
  mát thấp hơn hẳn "Remove Photo", mà chính nút đó cũng chỉ đánh dấu là phá huỷ chứ không hỏi lại.

## 4. Đặt từng thành phần

Chạm một dòng trên bản xem trước để **chọn** (viền nét đứt + bốn chấm góc), kéo dòng đó đi **một mình**,
phóng để đổi cỡ **chính dòng đó**.

- Thành phần **cùng vị trí vẫn xếp chồng thành một khối**, nên một widget chưa ai sắp xếp trông y như cũ;
  kéo một cái ra thì những cái còn lại **ghim tại chỗ**, không trôi theo.
- **Chạm trúng từng dòng, không phải cả khối**: mỗi dòng tự báo khung của nó, và phép chọn (thuần, có test)
  lấy dòng **nhỏ hơn** khi hai dòng chồng nhau, lấy dòng gần nhất trong **10pt** khi chạm hụt, xa hơn thì
  bỏ chọn. Bản cũ chọn theo *khối* và trả về dòng đầu, nên chạm vào ngày lại chọn đồng hồ và không cách nào
  với tới dòng dưới.
- **Đường gióng khi kéo** (thuần, có test): hút vào **giữa**, vào **mép**, và vào **thẳng hàng với thành
  phần khác**; ngưỡng 6% khoảng trống. Giữa và thẳng hàng thì vẽ đường vàng, mép thì không — biên widget đã
  tự thấy.
- Vị trí lưu bằng **một phân số của khoảng trống**, thay hẳn năm vị trí góc cũ. File cũ chỉ được **đọc,
  không bao giờ ghi lại**, nên ai từng đặt chữ ở góc nào thì lần kéo đầu bắt đầu từ đó.
- **Widget và bản xem trước dùng chung một phép đặt** — một dòng không thể nằm hai chỗ khác nhau giữa hai bên.

## 5. Ảnh nền

- **Bám tay kể cả ở mức 1×**: phần thừa tính **theo tỉ lệ ảnh thật**, không chỉ theo mức phóng — một ảnh 3:2
  trong ô vuông đã bị cắt ~39pt mỗi bên trước khi phóng, và đó chính là phần hai ngón kéo ra xem được. Bản
  cũ kéo ở 1× không làm gì cả.
- Phóng khi **không có dòng nào đang chọn** thì phóng ảnh, tối đa **3×**. Trong lúc phóng thì việc kéo dòng
  chữ **tạm ngưng** — tâm hai ngón luôn trôi, mà một dòng vừa đổi cỡ vừa trượt đi đúng là cái "hai việc một
  lúc" vừa bỏ. Riêng ảnh nền thì **giữ cả hai**, vì phóng ảnh và chọn phần ảnh còn lại vốn là một động tác.
- **Chọn nguồn ảnh**: "Photo" mở ô chọn ảnh của hệ thống; "Album" mở **lưới cover dùng chung với tab
  Collections** — cùng câu hỏi "cái nào đây" thì cùng câu trả lời: tên nằm **trên** ảnh, lớp tối đo theo độ
  sáng dải dưới, và ô tìm kiếm khớp **bỏ dấu, bỏ hoa thường** đúng như ô chọn album ngoài màn hình chính.

## 6. Màu chữ "Smart"

Lưu bằng một giá trị riêng thay cho mã màu, vì **màu chưa quyết được cho tới khi đo xong ảnh dưới chữ**.

- Một lưới độ sáng **16×16** dựng bằng cách vẽ ảnh **một lần** rồi đọc độ sáng từng ô (thuần, có test) —
  đúng kỹ thuật đã dùng cho lớp tối sau tên album, nhưng là **lưới** thay vì một điểm, vì widget đặt chữ ở
  đâu là do người dùng kéo nên một dải đáy cố định không còn trả lời được.
- Phép quy đổi từ vị trí chữ về vùng ảnh là **phép nghịch** của chính lớp vẽ ảnh ra, nên biết ô chữ đang nằm
  lên phần nào của ảnh thật.
- **Mỗi khối hỏi riêng** — đồng hồ kéo lên trời sáng và ngày để trên vách đá tối cần hai câu trả lời ngược
  nhau; một màu cho cả hai chính là chỗ ô màu cố định thua.
- Ngưỡng chuyển trắng/đen là **0,62**, **không** phải điểm hoà 0,18 của tương phản thuần: chữ luôn có bóng
  hoặc lớp tối nên màu trắng đi xa hơn nhiều. Độ tối của ảnh nhân vào phép đo (ảnh dim 60% là nền tối dù
  pixel gốc sáng). Không có ảnh thì Smart = trắng.
- **Lưới độ sáng chỉ dựng khi người dùng chọn Smart** — widget trả giá cho mọi lượt nó không cần, mà ô màu
  cố định thì không bao giờ hỏi câu này.
- **Hàng ô màu: 9 ô, lưới 3 cột**, ô Smart là một đĩa chẻ chéo trắng/đen bằng hai chặng cứng — **không
  blend**, vì ô đó đại diện một *lựa chọn giữa hai màu*, còn dải xám ở giữa đọc thành màu thứ ba. 4 cột thì
  màu tím đứng lẻ một hàng, nên 3 cột × 3 hàng.
- Nút ô màu từng đo được **38pt** dù đã đặt chiều cao tối thiểu 44: chiều cao đặt **ngoài** nút, mà kiểu nút
  phẳng chỉ nhận chạm ở chỗ nhãn vẽ — nên khung và vùng chạm phải nằm **bên trong** nhãn.

## 7. Lưu

Kho cấu hình widget ghi **JSON trong vùng chia sẻ giữa app và widget**, chờ 400ms rồi mới ghi, và **ghi
ngay** khi rời màn. Đổi nguồn ảnh thì vẽ lại và bảo widget nạp lại.

## 8. Tiêu chí nghiệm thu

Xem [05](05-acceptance-criteria.md).
