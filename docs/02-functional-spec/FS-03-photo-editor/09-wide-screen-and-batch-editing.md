# FS-03.09 — Editor trên màn rộng

`FS-03.09` · `Features/Editing/` (rail, sidebar, filmstrip) · `EditorLayoutMetrics`
· test `EditorPanelLayoutTests` · cập nhật 2026-09-22

**Một câu:** từ 700pt bề rộng **và** cửa sổ ngang, editor đổi sang bố cục kiểu Lightroom desktop —
rail công cụ, panel tham số, canvas.

Sửa nhiều ảnh một lượt: [FS-03.09b](09b-batch-editing-and-reference.md).

## 1. Quy tắc

- **Cổng vào layout rộng đo theo cửa sổ, không theo loại thiết bị**: rộng ≥ 700 **và** cao ≥ 600 **và**
  **rộng > cao**.
- **Panel trả bằng bề rộng** — thứ chỉ cửa sổ ngang mới dư.
- Cột ngắn thì **gập bớt đồ cố định**, không bóp danh sách tham số.
- **Không có nút nổi trên ảnh**: canvas nuốt chạm trong vùng của nó, nên mọi chrome phải là view anh em.
- **Panel không có chiều cao cố định** — mọi section cao đúng bằng nội dung.

## 2. Vì sao dọc không vào layout rộng

iPad 13" dọc (1032×1376) qua cả hai con số rồi tiêu 378pt của 1032 cho panel, còn lại ảnh 3:2 chỉ chiếm
**34% chiều cao canvas** (66% là đen) — so với **70%** khi ngang.

Dọc vì thế giữ panel dán đáy của điện thoại, thứ tiêu **chiều cao** mà ảnh letterbox không dùng tới.
Màn trong Duo (951×669) là ngang nên đi đường rộng.

## 3. Ba cột

```
[ top bar toàn chiều ngang                        ]
[ rail 48 ][ panel 280–420 ][ canvas + filmstrip  ]
```

- Rail và panel **cùng một cạnh**; đổi cạnh trong menu ⋯ (mặc định phải). Kéo mép trong để đổi bề rộng,
  ghi lại **một lần lúc thả tay**.
- **Top bar luôn hiện** ở tier này và **soi gương theo cạnh có panel**: cụm lệnh (undo · redo ·
  before-after · fit/fill · ⋯ · Save) luôn nằm **trên phía có panel**, Back đứng một mình ở cạnh đối diện.
  Không soi gương thì đo được **800pt** từ mép panel tới nút undo, chéo tới Save ~1300pt.
- Bar chỉ được có **một** phần co giãn — hai phần thì cụm lệnh bị đẩy về mốc một phần ba của bar 1376pt.
- Bar lấy 52pt chiều cao của ảnh và **trả lại 88pt** cho danh sách tham số: panel cũ trả cho cùng nhóm
  lệnh đó hai hàng 44pt mà **không cuộn được**.
- Histogram trong bar **tắt khi panel mở** — panel đã vẽ đúng biểu đồ đó.

## 4. Rail công cụ

48pt, cạnh ngoài, **không bao giờ thu gọn**: Edit / Presets / Crop / Mask / Markup ở trên (radio, chạm lại
cái đang bật để về Edit), History + nút ẩn/hiện panel ở dưới.

- Nhóm đang mở là **nguồn duy nhất** quyết định rail sáng chặng nào — mask mở từ menu ngữ cảnh trên ảnh
  cũng đẩy rail theo.
- Rail thay dải 4 tool ngang cũ: nó tiêu **bề rộng** (thứ canvas ngang dư) thay vì 44pt **chiều cao** panel
  (thứ danh sách tham số luôn thiếu), và khi panel thu gọn nó vẫn là đường quay lại công cụ.
- **Chạm lại chặng đang bật thật sự bỏ crop.** Trước đây tài liệu hứa đó là lối ra không áp khung, còn code
  thì áp khung trên **mọi** đường rời Crop — tức là không hề có lối ra nào không áp.
- **Mọi đường ẩn/hiện panel đi qua một hàm** — nút trên rail, ⌘\ và hàng trong menu ⋯; hàng đó từng lật cờ
  thẳng nên ẩn xong mở lại app là panel quay về.

## 5. Panel

Từ trên xuống: **histogram luôn hiện** → hàng tiêu đề mode (+ nút **Auto**) → hàng **Look** (tên film look
+ Browse, chỉ ở mode Edit) → nội dung → chân panel `[Reset ↺] [Save…]`.

- Histogram **cố ý không thả nổi trên ảnh** như Lightroom — biểu đồ mà di chuyển là biểu đồ phải đi tìm lại.
- Mode Edit có **8 section** (Light · Curve · Color · Grade · Effects · Detail · Optics · Geometry), mở
  nhiều cái cùng lúc; chevron nằm **đầu** hàng (bỏ icon group — rail đã mang icon). Mix và Point là segment
  trong Color. Bốn mode còn lại **thay** cả chồng section thay vì chèn lên trên.
- **Slider xếp dọc** (hàng cao 46): tên + số ở dòng trên, track **full-width** ở dưới. Panel 320pt mà xếp
  ngang thì 88pt là nhãn + 44pt là số, track chỉ còn một phần ba — trong khi track là thứ duy nhất ngón
  tay nhắm vào. Điện thoại giữ hàng ngang 34pt.
- Vì thế vùng mở bàn phím số phải chặn **cả theo chiều dọc** — chỉ dòng nhãn. Chặn theo chiều ngang thuần
  thì 54pt cuối hàng, tức **13% trên cùng hành trình của mọi tham số**, trả về "Enter Value…" thay vì chế
  độ tinh chỉnh.
- **Color Mix chọn dải trước** ở tier này: hàng 8 swatch tròn 22pt + chốt "All", rồi Hue/Saturation/
  Luminance của dải đó. 8 dải × 3 thuộc tính = 24 hàng, cao hơn panel; chọn dải trước còn 3 hàng nhìn thấy
  cùng lúc. Danh sách 24 hàng vẫn nằm sau swatch "All".
- Track có màu: Temp · Tint · **Saturation và Vibrance** — xám ở trái chạy sang đủ màu ở phải, đúng định
  nghĩa của hai slider đó.
- **Curve vẽ trong panel**, không đè lên ảnh — và vì nó nằm trong vùng cuộn nên luật chạm khác hẳn: kéo chỉ
  nắn khi **bắt đầu đúng trên một điểm**, điểm mới đến từ **một cú chạm**, và lúc nắn thì khoá cuộn danh
  sách. Trước đó plot nhận mọi cú kéo và chèn điểm ngay ở sự kiện đầu tiên — cuộn danh sách qua mục Curve
  là đổi tương phản của ảnh.

## 6. Cột ngắn

`canvasHeight < 800` thì panel **gập hai hàng** — khối histogram (112pt) và hàng Look (53pt) — trả lại
**165pt**; pill histogram trên bar bật lại để bù.

Số học trên màn trong Duo: cột chỉ còn 593pt, đồ cố định 293 (**49%**), mà riêng nhóm Light đã là 412pt —
tràn 112pt; đóng hết 8 header vẫn 352pt. Sau khi gập: đồ cố định 128 (22%), vùng nhìn 465pt. Có test.

## 7. History là cột trong panel, không phải sheet

Chặng History trên rail là một mode bật/tắt như năm mode trên nó; header panel đổi thành `HISTORY` + `Done`.

Hai lý do:

1. Chọn một bước history là **nhìn tấm ảnh nó tạo ra**, mà sheet thì che ảnh.
2. Trên cửa sổ regular-width/compact-height — màn trong Duo 951×669 — hệ thống **bỏ qua detent của
   sheet**, nên cả nửa màn lẫn toàn màn đều thành full-screen và ảnh biến mất hẳn.

Điện thoại giữ sheet: ở đó không có panel nào để nhét danh sách. Cả ba lối vào đi qua **một** hàm nên chỉ
có một câu trả lời cho "sheet hay panel".

**Ba sheet còn lại giữ nguyên là sheet** — Save, New Mask, Mask Picker: cùng vấn đề chiều cao, nhưng cả ba
là *chọn xong rồi thôi*, không cần nhìn ảnh trong lúc chọn. Ghi ở đây để lần sau khỏi coi là sót.

## 8. Vòng sửa sau review UI/UX

- **Bánh xe nhóm đổi panel khi *dừng*, không phải khi đi qua** — debounce 140ms. Một cú vẩy trước đó chạy
  trọn một lần đổi nhóm (commit crop, đổi tool, render lại) **cho mỗi chip đi qua**, kèm một haptic.
- **Đổi ảnh trong filmstrip không tháo editor nữa**: controller mới được gắn trong một bước rồi mới đóng
  cái cũ. Trước đó band, filmstrip vừa bấm và panel đều biến mất một nhịp.
- **Mở editor có ảnh giữ chỗ**: xin một khung local 1024px không mạng ngay đầu, vẽ mờ 0.35 dưới spinner;
  ảnh chỉ có trên iCloud thì chữ đổi thành *"Downloading from iCloud…"*.
- **Undo tới được bằng một tay**: hai ngón chạm lên ảnh = Undo (chỉ ở compact width), cộng hàng Undo/Redo
  có tên trong menu ⋯. Đĩa undo nằm góc trên-trái, cách slider đang cầm 800pt.
- **Toast undo đậu trên panel**, không đè bánh xe — căn đáy 24pt thì nó chồng đúng dải bánh xe, mà toast
  có nút Undo riêng nên nuốt tap.
- **Esc tháo một tầng** chứ không thoát: đang ở Crop/Mask/Markup/Presets thì về Edit (và ra khỏi Crop
  **không** áp khung); chỉ từ Edit mới rời editor.
- **Zoom chỉ reset khi vào hoặc rời Crop** — trước đó nó nằm trên đường của mọi tap rail, mọi header và mọi
  lần đổi segment Color: pinch 400% soi sharpening rồi với sang Detail là mất chỗ đang soi.
- **Fade hai đầu bánh xe rộng bằng một chip** (58, trước 26): bánh xe chỉ có ~286pt = 4,3 chip nên chip
  biên luôn nửa vời; fade hẹp hơn phần bị cắt thì vết cắt rơi vào chữ.
- **Track gradient không trung tính ở mốc thì giữ vệt trắng 2pt**: Temp/Tint xám ở giữa nên bỏ fill vẫn
  đọc được, còn Sat/Vibrance sáng nhất ở giữa nên bỏ fill thì 0 và +40 nhìn như nhau.
- **Menu ⋯ của điện thoại có hàng Fit Photo / Fill Screen**: chạm đôi đổi nghĩa giữa hai layout, mà trên
  Duo một người gặp cả hai trong một phiên — nên mỗi nghĩa phải có một control có tên.
- **Fit ⇄ Fill**: chạm đôi lên ảnh, hoặc nút zoom trong hàng lệnh. Phần tràn do canvas cắt, **recipe không
  đổi**. Điện thoại giữ chạm đôi = xem tràn viền.

## 9. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
