# FS-04.01 — Mixer và Point Color

`FS-04.01` · `Features/Editing/EditorColorPanel.swift` · `EditorColorLoupe` · cập nhật 2026-09-24

**Một câu:** 24 slider theo băng màu, và tám điểm màu lấy trực tiếp từ ảnh bằng một kính lúp soi từng pixel.

## 1. Quy tắc

- Mixer trên phone có dải **All + 8 băng màu** (9 swatch chia đều): All là danh sách 24 slider, một băng là ba
  slider của băng đó ([FS-03.12 §4](../FS-03-photo-editor/12-phone-panel-grid.md#4-chip-và-dải-chọn)).
- Trọng số của **mọi** điểm màu tính từ **màu gốc của pixel** rồi cộng dồn và áp **một lần** — nên thứ tự
  các điểm không ảnh hưởng kết quả.
- Màu tham chiếu lưu **tại thời điểm lấy mẫu, từ bản xem trước đã chỉnh** (đúng cách Lightroom làm: chọn màu
  đang thấy), và **không** lấy mẫu lại khi phần chỉnh phía trước đổi.
- Rời tab là tự tắt ống hút màu.

## 2. Mixer

Một danh sách cuộn với ba mục dính **HUE / SATURATION / LUMINANCE**, mỗi mục 8 hàng cho 8 băng màu:
Red · Orange · Yellow · Green · Aqua · Blue · Purple · Magenta.

- Dải màu của rãnh mỗi hàng **sinh từ chính tâm băng màu đó**, cùng hằng số với phần render — nên màu của
  rãnh **chính là nhãn của kênh**. Hue vẽ dải quanh tâm ±30°, saturation chạy từ xám sang màu của băng,
  luminance chạy từ tối sang sáng.
- Tiêu đề mục chỉ còn chữ, không icon.

**Cách trộn**: mỗi pixel được quy về hue–saturation–độ sáng, rồi tính **trọng số băng màu** bằng một hình
tam giác mềm giữa hai tâm kề nhau trên vòng tròn màu — luôn đúng **hai** băng khác 0, tổng bằng 1, **không
có vùng chết**. Từ đó: dịch hue tối đa ±30° nhân trọng số, nhân saturation, và dịch độ sáng theo một công
thức **tự giới hạn** ở hai đầu. Một **ngưỡng độ tinh khiết mềm** giữ cho vùng gần trung tính **không bị nhuộm**.

## 3. Point Color — panel

- Dải chọn: swatch 20pt màu tham chiếu (vòng trắng cho điểm đang chọn) + chip ống hút ở cuối dải.
- **Nút ống hút co giãn theo việc đã có màu nào chưa** — vẫn là **một** nút, chỉ nhãn và bề rộng đổi, nên cú
  thu lại đọc như nút *nhường chỗ* chứ không phải bị thay bằng nút khác:
  - chưa có điểm nào → không có dải; giữa vùng thông số là đĩa ống hút 40pt + dòng *"Tap the photo to pick a
    color, then adjust only that color"*, và ảnh đã ở sẵn chế độ lấy mẫu;
  - có điểm → chip ống hút cuối dải, **nền trắng 20% khi đang chờ lấy mẫu**, kèm pill trên ảnh.
- Tắt khi đủ **8 điểm**.
- **Giữ lâu một chip là ra menu `Delete Point Color`**: chip là một chấm 28pt, ngoài chọn ra thì việc duy
  nhất làm với nó là vứt đi — nên giữ lâu đi thẳng tới đó. Nút Delete ở cuối các slider vẫn còn.
- Dưới là 4 slider của điểm đang chọn: **Hue / Saturation / Luminance** (dải màu quanh hue đã lấy mẫu) +
  **Range 0…100**.

## 4. Ống hút màu trên ảnh

Khi đang chờ lấy mẫu, **mọi cử chỉ mức ảnh bị tắt** (đúng như khi cắt ảnh), và một lớp lấy mẫu nằm **trong
lớp đã phóng, cùng chỗ với lớp vẽ**.

Chạm → hiện kính lúp · kéo để tinh chỉnh · **nhả tay là lấy mẫu**, tự tắt ống hút, kèm haptic. Dưới đáy ảnh
có dòng nhắc "DRAG ON THE PHOTO · LIFT TO PICK".

## 5. Kính lúp

**Không phải một ô màu**: ô màu nói *màu gì đang ở dưới ngón* nhưng không nói *phải di đi đâu*, mà chính
ngón tay lại che mất vùng pixel cần ngắm.

| Thuộc tính | Giá trị |
|---|---|
| Đĩa | 84pt, **không nội suy**, mỗi ô lưới đúng **một pixel ảnh** |
| Mật độ | 10 pixel ngang đĩa = 8,4pt mỗi pixel |
| Ô đang lấy mẫu | viền trắng-trên-đen ở chính giữa |
| Vành đĩa | tô đúng màu vừa đọc |
| Dưới đĩa | viên nang mã màu `#RRGGBB` — màu và mã lấy trong **một** lần đọc pixel |

- Ảnh trong đĩa phóng **quanh tâm của pixel** dưới ngón, không quanh chính điểm ngón, nên ô đang đọc nằm
  chính giữa chứ không cưỡi lên vạch ngắm.
- Kính treo thẳng trên đầu ngón và **không bị kẹp trong khung ảnh** — ra ngoài mép cũng được. Kẹp vào khung
  nghĩa là đúng chỗ khó ngắm nhất thì kính lại bị kéo ra khỏi tay.
- Vì thế kính nhận **hai điểm**: đầu ngón thật (đặt kính và vạch ngắm) và điểm đã ghim vào ảnh (pixel đang
  đọc và tâm phóng). Hai điểm chỉ tách nhau khi ngón đã ra ngoài mép.
- Kính sống trong lớp đã phóng nên **mọi số đo của nó chia cho mức phóng** — nó là chrome, phải giữ nguyên
  cỡ ở 100% lẫn 800%; chỉ ảnh bên trong mới phóng.
- Điểm chạm được **ghim vào khung ảnh** trước khi đọc: ngón lạc ra vùng đen thì lấy pixel gần nhất — đúng
  cái kính đang hiện — thay vì rơi mất mẫu. Phép kiểm "nằm trong khung" của hệ thống loại cả mép phải và mép
  dưới, nên phải ghim chứ không kiểm.

## 6. Cách các điểm màu áp vào ảnh

**Một lượt chạy duy nhất với 8 chỗ cố định** (chỗ trống thì tắt). Chạy 8 lượt nối tiếp là **sai ngữ nghĩa**
— điểm sau sẽ so trên kết quả của điểm trước.

- Độ lệch màu tính bằng khoảng cách ba chiều, trong đó **hue nặng gấp 2,5 lần** — hue là thứ quyết định.
- Bán kính ăn màu chạy từ **0,10 đến 0,55** theo slider Range.
- **Không có ngưỡng độ tinh khiết** ở đây — một điểm lấy mẫu gần trung tính vẫn phải ăn.

## 7. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
