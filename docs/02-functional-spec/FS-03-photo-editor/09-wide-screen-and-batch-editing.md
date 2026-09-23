# FS-03.09 — Editor trên màn rộng

`FS-03.09` · `Features/Editing/` (rail, sidebar, filmstrip) · `EditorLayoutMetrics`
· test `EditorPanelLayoutTests` · cập nhật 2026-09-22 (bản Design: 17 AC + 4 mục cần quyết)

**Một câu:** từ 700pt bề rộng **và** cửa sổ ngang, editor đổi sang bố cục kiểu Lightroom desktop —
rail công cụ, panel tham số, canvas.

Sửa nhiều ảnh một lượt: [FS-03.09b](09b-batch-editing-and-reference.md).

## 1. Quy tắc

- **Cổng vào layout rộng đo theo cửa sổ, không theo loại thiết bị**: rộng ≥ 700 **và** cao ≥ 600.
  **Bỏ vế "rộng > cao" (2026-09-22)** — iPad xoay dọc giờ cũng đi đường rộng, xem §2.
- **Panel trả bằng bề rộng** — thứ chỉ cửa sổ ngang mới dư.
- Cột ngắn thì **gập bớt đồ cố định**, không bóp danh sách tham số.
- **Không có nút nổi trên ảnh**: canvas nuốt chạm trong vùng của nó, nên mọi chrome phải là view anh em.
- **Panel không có chiều cao cố định** — mọi section cao đúng bằng nội dung.

## 2. iPad dọc cũng đi đường rộng — và cái giá của nó

Trước 2026-09-22 cổng vào còn vế **rộng > cao**, nên iPad xoay dọc rơi về giao diện điện thoại: panel 246pt
dán đáy và bánh xe chip. Bỏ vế đó vì **xoay máy không được đổi từ vựng của editor**: cùng một cái iPad,
ngang thì 5 thẻ gập, dọc thì 14 chip — người dùng phải học hai lần.

Cái giá đã đo, không giấu — ảnh 3:2 **ngang**, chiều cao ảnh trên chiều cao canvas:

| Cửa sổ | Panel bên (mới) | Panel đáy (cũ) |
|---|---|---|
| iPad 11" dọc 834×1194 | canvas rộng 466 → ảnh **311pt = 27%** | 834 → ảnh 556pt = 62% |
| iPad 13" dọc 1032×1376 | canvas rộng 664 → ảnh **443pt = 34%** | 1032 → ảnh 688pt = 64% |
| iPad 11" ngang 1210×834 | 842 → ảnh **553pt = 71%** | — |

Tức là ở dọc, panel bên **cắt hơn nửa** chiều cao ảnh so với panel đáy. Người dùng chấp nhận đánh đổi này để
đổi lấy một editor duy nhất ở mọi hướng xoay.

Đường thoát khi cần ngắm ảnh to: nút **Hide Tools** trên rail đã có sẵn — gập panel còn lại rail 48pt, canvas
dọc quay về 786pt rộng (11") và 984pt (13"). Trạng thái gập panel nhớ theo `SettingsKeys.editorSidebarHidden`
như hiện nay.

Vẫn **không** vào layout rộng: iPhone mọi hướng (rộng < 700), Duo màn ngoài 466×678, và Split View hẹp.

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

Từ trên xuống: **histogram luôn hiện** → hàng tiêu đề mode → nội dung. **Mode Edit và Presets không có chân
panel** — thu hồi **74pt**. Ba mode dựng hình (Crop & Geometry · Mask · Markup) có chân panel riêng, xem
§5b2.

Ba thứ **bỏ khỏi panel** (chốt 2026-09-22):

- **Nút `Auto`** — bỏ, và bỏ luôn dòng *Auto Enhance* trong menu ⋯: `EditorAutoTone` chỉ đọc histogram rồi
  đặt ba slider (trọng tâm tone → Exposure, khoảng dư sáng → Whites, bề rộng histogram → Contrast), không
  đụng màu hay cân bằng trắng. Xoá cả `Domain/Editing/EditorAutoTone.swift` và test của nó.
- **Hàng `Look`** (tên film look + Browse) — bỏ hẳn ở mọi khổ màn, không chỉ cột ngắn: film look có đúng
  một lối vào là chặng **Presets** trên rail. Thu hồi **52pt**.
- **`Save…`** rời chân panel, lên **hàng lệnh trên** cùng cụm đã dồn một bên (§5b) — pill nền accent, chữ
  đen, đặt cuối cụm cạnh ⋯.
- **`Reset All`** — bỏ. Thay bằng **nút ↺ riêng trên tiêu đề từng thẻ**, chỉ hiện khi nhóm đó có giá trị
  khác mặc định, và chỉ đặt lại nhóm đó. Không còn một nút xoá sạch cả ảnh trong tầm tay.

  Trả **cả bức ảnh** về gốc vẫn còn một đường: dòng **`Reset All Adjustments`** trong menu ⋯ — mờ khi chưa
  sửa gì, có hộp xác nhận. Khác *Revert to Original* cùng menu (thứ vứt cả bản sửa đã lưu và đóng editor).

- Histogram **cố ý không thả nổi trên ảnh** như Lightroom — biểu đồ mà di chuyển là biểu đồ phải đi tìm lại.
- Mode Edit có **5 section** — **Light · Color · Effects · Detail · Optics** — mở nhiều cái cùng lúc;
  chevron nằm **đầu** hàng (bỏ icon group — rail đã mang icon). Bốn mode còn lại **thay** cả chồng section
  thay vì chèn lên trên.

  Gom lại theo đúng cách Lightroom iPad gom (đo trên máy thật, `docs/_intents/assets/lightroom-ref/`):

  | Nằm ở đâu | Gồm |
  |---|---|
  | **Light** | 8 slider tone, rồi hàng kênh `RGB · R · G · B` và **đồ thị curve ~300pt** ở cuối thẻ |
  | **Color** | Basic (Temp/Tint/Vibrance/Saturation/B&W) · **Mix** · **Point** · **Grade** — bốn tab trong một section |
  | **Effects** · **Detail** · **Optics** | như cũ |
  | **Crop & Geometry** (mode trên rail) | khung cắt, tỷ lệ, xoay, lật — rồi một nét `panelDivider` — rồi sáu slider hình học và Upright, **trong cùng một danh sách cuộn**, không tab |
  | **Heal** (mode trên rail, giữa Crop và Mask như Lightroom; thêm 2026-09-23, FS-03.11 §2) | Heal · Clone, Size, Feather, "Spot n of m" + Delete Spot; chạm ảnh để thêm vết, kéo vòng nét đứt để đổi nguồn; có thanh ↺ · Cancel · Apply như Crop/Mask/Markup |

  **Curve vẫn vẽ trong panel**, không bao giờ là lớp phủ trên ảnh, và **không nấp sau một nút** — mở thẻ
  Light ra là thấy cả tone lẫn curve. Luật chạm của plot ở cuối §5 giữ nguyên.

  **Curve nằm trong thẻ Light, không nút mở, không lớp phủ trên ảnh** — cuối thẻ là hàng kênh
  `RGB · R · G · B` rồi đồ thị **vuông ~300pt** (cạnh bằng bề rộng vùng nội dung của panel). Mở thẻ Light
  ra là cuộn qua 8 slider rồi tới curve.

  Thẻ Light mở khi đó ≈ 44 (tiêu đề) + 368 (8 slider) + 36 (hàng kênh) + 300 (đồ thị) = **748pt**, so với
  vùng cuộn 504pt (iPad 11") và 430pt (Duo) — **luôn phải cuộn trong thẻ Light**, và đó là đánh đổi đã
  chấp nhận để không có gì che ảnh và không có trạng thái nở/thu của panel.

- **Mọi section gập sẵn khi mở editor.** Người dùng nhìn một lần là thấy editor có những gì, thay vì một
  nhóm mở và phần còn lại nằm dưới mép màn. Trạng thái gập/mở là **state của phiên sửa**, không ghi vào
  recipe và không vào History.

- **Mở một section thì section đó cuộn lên đầu vùng cuộn**, các section còn lại vẫn nhìn thấy — thứ tự
  không đổi, chỉ vị trí cuộn đổi.

- **Slider phụ mờ cho tới khi slider cha khác 0**: Midpoint · Roundness · Feather · Highlights chờ
  **Vignette**; Size · Roughness chờ **Grain**. Mờ theo đúng luật tầng D của `DESIGN.md` (hành động không
  khả dụng thì làm mờ, không ẩn) và **không nhận chạm**. Các cụm trong một section ngăn nhau bằng
  `panelDivider`.

  Opacity dùng **`EditorTheme.rowDisabled = 0.35`** (tên mới, đặt trong `EditorTheme` đúng luật "thiếu thì
  đặt tên, không gõ số trong file feature"): nhãn, số và track cùng nhân giá trị này. Không dùng lại 0.28
  của glyph — track chỉ dày 2pt nên ở 0.28 nó biến mất, hàng trông như chỗ trống.
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

- **Mỗi section là một thẻ**, không phải một khúc của danh sách phẳng: nền `EditorTheme.control`, bo
  `AppTheme.Radius.lg`, cách nhau **8pt** — cùng ngôn ngữ với thẻ histogram đang có ở đầu panel. Nét
  `panelDivider` chỉ còn dùng **bên trong** một thẻ để ngăn các cụm (ví dụ Vignette với Grain).

  **Cột ngắn (`canvasHeight < 800`) dùng 6pt** thay vì 8 — cả khoảng cách giữa hai thẻ lẫn padding trong.
  Số học: mỗi thẻ ăn thêm ~16pt ở 8pt và ~12pt ở 6pt; năm thẻ gập = 300pt (8pt) hoặc 280pt (6pt), còn Light
  mở = 428pt (8pt) hoặc **412pt (6pt)** so với vùng cuộn 430pt của Duo. Cùng một kiểu điều kiện đã dùng cho
  histogram 56pt, nên cột ngắn có **một** bộ số, không phải hai luật rời.

- **Vùng bắt chạm của núm nới lên 44pt, hình dạng giữ nguyên là vạch.** Người dùng nêu đúng vấn đề: bấm dễ
  trượt, và Pencil hoặc trỏ chuột nhắm vào một vạch 2pt là nhắm vào cái không có bề ngang. Nhưng
  `EditorSliderRow.swift:12` đã chốt từ trước *"There is no round knob and no system Slider"*, và **cả
  editor** — mixer, grading, point colour, straighten — đi qua đúng slider đó, kể cả bản điện thoại với
  hàng 34pt không chứa nổi núm 28pt. Nên chỉ đổi **vùng chạm**, không đổi diện mạo.

### 5b. Hàng lệnh dồn về phía panel

Trên màn rộng, hàng lệnh trên **dồn hết về phía có panel**; đầu kia chỉ còn **Back**.

Đo được hôm nay trên iPad 11" ngang (1210pt): năm nút nằm x 20…277 còn ⋯ ở x=1146 — **869pt trống ở giữa**,
và mỗi lần Undo là một quãng với tay 800pt từ slider đang cầm. Lightroom dồn hết về phải, trái chỉ có Back.

Hướng dồn **đi theo `sidebarEdge`** (tuỳ chọn *Tools Panel: Left/Right* đã có trong menu ⋯): panel bên phải
thì lệnh bên phải, panel bên trái thì lệnh bên trái. Đây là luật đã có trong code (`mirrored:`), spec chỉ
ghi lại cho đúng.

### 5b2. Rail đóng mở panel, và bar cam kết của ba mode dựng hình

- **Chạm lại icon đang mở thì panel trượt đi**, chỉ còn rail 48pt — đúng cách Lightroom làm. Chạm lần nữa
  mở lại **đúng mode đó**.
- **Icon chỉ sáng khi panel của nó đang mở.** Panel đóng thì cả rail xám: trạng thái sáng nói "panel này
  đang mở", không phải "mode này đang được chọn". Một dấu hiệu, một nghĩa.
- **Bỏ nút `Hide Tools`** ở đáy rail — thu hồi 48pt và bỏ được cảnh hai control cho một việc.

**Ba mode dựng hình — Crop & Geometry · Mask · Markup — có chân panel riêng `[↺] [Cancel] [Apply]`.**
Chân panel này **chỉ có ở ba mode đó**; mode Edit và Presets vẫn không có chân panel (§5).

| Nút | Làm gì |
|---|---|
| `Apply` | chốt khung cắt / mask / lớp markup đang dựng, rồi về mode Edit |
| `Cancel` | bỏ mọi thứ dựng trong phiên mode này, về mode Edit — **thay cho luật cũ "chạm lại Crop là thoát mà không áp khung"**, thứ vừa mất vì chạm lại giờ là đóng panel |
| `↺` | trả riêng mode đó về mặc định (khung cắt về nguyên ảnh, xoá hết mask, xoá hết layer) — có hộp xác nhận, một bước Undo |

**Kiểu dáng — nhỏ, phân biệt bằng màu, không phải bằng kích thước** (theo Lightroom, `lr-11`/`lr-12`):

| Nút | Kiểu | Số |
|---|---|---|
| `Apply` | pill **nền accent, chữ đen** — nút chính duy nhất của chân panel | cao **32pt**, rộng vừa chữ + 14pt mỗi bên (tối thiểu 72pt). **Không** kéo ngang panel |
| `Cancel` | **chữ trần**, không nền, `Color.white.opacity(0.9)` | cùng chiều cao 32pt để hai nhãn nằm trên một đường |
| `↺` | đĩa tròn `editorGlass`, glyph trắng, tách sang **đầu kia** của chân panel | **32pt** |

Chân panel vì thế cao **48pt** (32 + 8 trên + 8 dưới), không phải 74pt như chân panel cũ.

Cùng luật đó áp cho pill **`Save`** trên hàng lệnh: nền accent, chữ đen, cao **32pt**, rộng vừa chữ — thay
cho nút 240×50 hôm nay, thứ đang là mảng màu lớn nhất màn hình ngay cạnh ảnh đang chỉnh màu.

⚠️ **Đánh đổi phải ghi:** chân panel ăn **48pt** đúng ở ba mode mà panel đang dài nhất. Trên Duo (vùng cuộn
~430pt) mode **Crop & Geometry** vừa nhận thêm sáu slider Geometry vừa mất 48pt — `/plan` phải đo, và nếu
không vừa thì Geometry gập mặc định.

Việc này **đảo hai quyết định trước đó cùng ngày**: "bỏ hẳn chân panel" (giờ còn ở ba mode) và "Mask không
có Cancel/Apply" (giờ có). Ghi lại để lần sau không ai tưởng là sót.

### 5c. Chrome mới không được lấy thêm chỗ của ảnh

Đo bằng pixel trên ảnh chụp thật (2026-09-22, iPad 11" ngang, `assets/2026-09-22-editor-ipad-landscape.png`):
một ảnh 3:2 ngang chiếm **553 trên 782pt chiều cao canvas = 71%** (và 66% chiều cao màn hình). Ngưỡng kiểu
"ảnh phải chiếm ≥60% canvas" vì thế **không bắt được gì** — nó đã đạt từ trước.

Chỗ đen mà mắt nhìn thấy là **hai dải trên–dưới của một ảnh ngang nằm trong một canvas gần vuông**
(842×782pt). Thứ duy nhất làm nó nhỏ đi là cho canvas thêm **bề rộng**, tức panel hoặc rail phải hẹp lại —
một chuyện khác hẳn, và không nằm trong lượt này.

Luật của lượt này vì thế là luật **không lùi**: sau khi thêm thẻ, bỏ chân panel và dời Save, canvas phải
**rộng ≥ 842pt** và **cao ≥ 782pt** trên iPad 11" ngang — không hẹp hơn hôm nay một pt nào. Panel giữ dải
280–420pt như cũ.

Không đụng hai luật cũ: preview **không** hạ độ phân giải ([FS-03.04](04-raw-and-render-graph.md)), và
Fit ⇄ Fill vẫn là chạm đôi / nút zoom, phần tràn do canvas cắt chứ recipe không đổi.

### 5d. Mask: panel mờ cho tới khi có mask

Vào mode **Mask**: header panel đổi thành `MASK`, và **năm thẻ mờ** (`EditorTheme.rowDisabled`) không nhận
chạm cho tới khi có ít nhất một mask — kèm một dòng hướng dẫn và nút `+`. Nói rõ "phải tạo vùng trước, rồi
mới chỉnh" mà không cần một câu lỗi nào.

Chân panel của mode này là `[↺] [Cancel] [Apply]` như hai mode dựng hình còn lại (§5b2). Nội dung từng loại
mask và thẻ giải thích: [FS-03.05](05-local-masks.md).

**Thẻ giải thích dùng chính ảnh đang mở**: chọn *Select sky* thì thẻ vẽ thumbnail của bức ảnh đó với vùng
trời tô overlay, chứ không phải ảnh mẫu lạ như Lightroom. Loại không tính trước được (Brush, Linear,
Radial) thì vẽ hình khối trên cùng thumbnail đó.

### 5d2. Markup trên màn rộng

Markup ăn theo mọi thay đổi vỏ panel (không chân panel, `Save` trên hàng lệnh, panel dồn một bên), cộng
bốn luật riêng — nội dung từng loại layer vẫn ở [FS-05](../FS-05-markup/README.md):

- **Một thẻ `Layers`** chứa danh sách layer, không biến mỗi layer thành một thẻ rời. Hàng nút thêm nằm
  **ngoài** thẻ.
- **Thêm layer bằng một nút `+`** mở danh sách có tên đầy đủ và biểu tượng — cùng cử chỉ với `+` của Mask.
  Thay hàng bốn nút `Add Text · Add Image · Add shape or magnifier · Add Draw` (mỗi nút 67×28, chật trên
  Duo và dưới ngưỡng chạm 44pt).
- **Nút ↺ trên thẻ `Layers` xoá hết layer**, có hộp xác nhận vì là hành động phá huỷ, và vẫn là **một** bước
  Undo. Từng layer vẫn xoá riêng được.
- **Đang vẽ thì công cụ nằm trong panel bên**, không phải thanh nổi đè lên ảnh: cọ, cỡ, màu, opacity vào
  panel 320pt đã có sẵn. Đây là chỗ màn rộng **khác** điện thoại — điện thoại không có panel nào để chứa,
  nên giữ thanh nổi.

### 5e. Không còn extension sửa ảnh

`ShotDexEdit` **bị bỏ** (2026-09-22): bố cục mới không phải nhét vừa một tiến trình chật bộ nhớ, và không
phải public hoá view section lên `ShotDexKit`. Lối vào từ Photos giờ là một dòng **Edit in ShotDex** trong
share sheet mở thẳng app — [EX-05](../../03-extensions-and-integrations/EX-05-edit-action-extension.md).

Mở qua đường đó mà **không dò ra ảnh gốc** trong thư viện thì editor chỉ có **Save Copy**, không có
Save Changes, và không hiện dòng giải thích nào.

## 6. Cột ngắn

`canvasHeight < 800` thì panel **thu khối histogram xuống 56pt** (chỉ dải đồ thị, bỏ padding và nhãn) và
**gập hàng Look** (53pt) — trả lại **109pt**. **Histogram không bao giờ rời panel nữa**: pill histogram trên
hàng lệnh **không** bật lại, vì đọc histogram là việc làm liên tục trong lúc kéo slider và một cú chạm cho
mỗi lần liếc là cái giá sai.

Đo hiện trạng trước khi sửa (Duo màn trong, `docs/_intents/assets/2026-09-22-editor-duo-inner.png`):
histogram bị đẩy lên band thành một dải **600×44pt**, nhóm Light mở chiếm **441pt trên 669pt (66%)**, và
Grade nằm dưới hàng Save còn Effects/Detail/Optics/Geometry ở ngoài màn.

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

Nguồn: intent `docs/_intents/2026-09-22-editor-panel-lightroom-layout.md` (người dùng chốt 2026-09-22:
gập hết section · gom còn 5 nhóm · histogram 56pt trên cột ngắn · nhận bốn thói quen của Lightroom).

Đo hiện trạng trên **iPad 13" ngang 1376×1032** (2026-09-22, panel rộng 280pt): Light mở chiếm 258→697,
và **Geometry (y=955…999) chui xuống dưới hàng `Save…` (y=962)** — ngay cả trên màn cao nhất chúng ta ship,
nhóm cuối vẫn bị chân panel đè 37pt.

Ký hiệu: **W** = cửa sổ qua cổng layout rộng. Ba khổ dùng để đo: **iPad 11" ngang 1210×834**,
**iPad 13" ngang 1376×1032**, **Duo màn trong 951×669**.

| # | Cho / Khi / Thì | Chứng minh |
|---|---|---|
| AC-1 | **Cho** một ảnh JPG và cửa sổ 1210×834 · **Khi** mở editor · **Thì** panel hiện đủ **5** tên section (Light · Color · Effects · Detail · Optics), tất cả **gập**, và header cuối cùng nằm **trên** mép trên của hàng `[Reset] [Save…]` — không phải cuộn để thấy tên nào | ⚠️ chưa có — `EditorPanelLayoutTests` (case mới) + `Tools/ui-drive ipad-editor-panel.json` dump |
| AC-2 | **Cho** cửa sổ Duo màn trong 951×669 · **Khi** mở editor · **Thì** histogram nằm **trong panel, ở trên cùng**, cao **56pt**, và hàng lệnh trên **không** có pill histogram | ⚠️ chưa có — test + `duo-editor-panel.json` dump (so với ảnh hiện trạng `assets/2026-09-22-editor-duo-inner.png`: pill 600×44 trên band) |
| AC-3 | **Cho** Duo màn trong · **Khi** panel ở trạng thái mặc định · **Thì** đồ cố định (histogram 56 + mode header 40 + chân panel 74 + đường kẻ) ≤ **180pt**, vùng cuộn ≥ **430pt**, và **5 header gập (5×44 = 220pt) vừa trọn** trong vùng cuộn | ⚠️ chưa có — `EditorPanelLayoutTests` (số học thuần, không cần sim) |
| AC-4 | **Cho** Duo màn trong, panel mặc định · **Khi** mở section **Light** (8 slider) · **Thì** toàn bộ section cao **412pt** vừa trong vùng cuộn, và tên **Color** vẫn nhìn thấy | ⚠️ chưa có — test + dump |
| AC-5 | **Cho** panel đang cuộn ở giữa danh sách · **Khi** chạm header **Detail** · **Thì** Detail mở và **cuộn lên sát đầu vùng cuộn** trong một lần, các header còn lại vẫn ở đúng thứ tự cũ | ⚠️ chưa có — `ui-drive` dump trước/sau (so `y` của header Detail) |
| AC-6 | **Cho** Vignette = 0 · **Khi** nhìn section Effects · **Thì** Midpoint · Roundness · Feather · Highlights **mờ** theo `EditorTheme.rowDisabled` và **không nhận chạm** (kéo vào track không đổi giá trị) | ⚠️ chưa có — unit test trên trạng thái + `ui-drive` (dump `enabled=false`) |
| AC-7 | **Cho** Vignette = 0 · **Khi** kéo Vignette lên **+20** · **Thì** bốn slider phụ sáng lại và nhận chạm ngay, không cần đóng/mở section | ⚠️ chưa có — `ui-drive` |
| AC-8 | **Cho** Grain = 0 · **Khi** nhìn Effects · **Thì** Size và Roughness mờ; đặt Grain = 25 thì sáng | ⚠️ chưa có — test |
| AC-9 | **Cho** `sidebarEdge = trailing` và cửa sổ 1210×834 · **Khi** mở editor · **Thì** mọi nút của hàng lệnh trừ **Back** nằm trong **340pt** sát mép panel, và Back nằm ở mép đối diện (hiện trạng: 869pt trống ở giữa) | ⚠️ chưa có — `ui-drive` dump (đo `x` của nút xa nhất) |
| AC-10 | **Cho** `sidebarEdge = leading` · **Khi** mở editor · **Thì** cụm lệnh lật sang trái cùng panel, Back sang phải — cùng một quy tắc, không có nhánh riêng | ⚠️ chưa có — `ui-drive` trên sim đã đặt `editor.sidebarEdge = leading` |
| AC-11 | **Cho** thẻ **Light** đang mở · **Khi** cuộn xuống cuối thẻ · **Thì** thấy hàng kênh `RGB · R · G · B` và đồ thị curve **vuông ~300pt** vẽ trong panel; **không** có lớp phủ nào trên ảnh, và cuộn danh sách trong lúc ngón tay bắt đầu ngoài một điểm thì **không** chèn điểm mới | `EditorHistoryAndSummaryTests` (phần curve) + ⚠️ chưa có cho luật chạm |
| AC-12 | **Cho** section Color · **Khi** mở nó · **Thì** có đúng bốn tab **Basic · Mix · Point · Grade**, và không còn section `Grade` riêng ở danh sách | ⚠️ chưa có — dump (đếm header) |
| AC-13 | **Cho** mode **Crop** · **Khi** mở nó · **Thì** panel chứa cả sáu slider Geometry, và rời Crop **không** áp khung cắt (luật cũ của §8 giữ nguyên) | ⚠️ chưa có |
| AC-14 | **Cho** ảnh chỉ có trên iCloud, máy **không mạng** · **Khi** mở editor trên cửa sổ rộng · **Thì** panel vẫn dựng đủ 5 section gập và histogram trống, ảnh hiện chữ *"Downloading from iCloud…"* — không có panel rỗng, không crash | ⚠️ chưa có |
| AC-15 | **Cho** quyền ảnh `.limited` và ảnh đang sửa nằm ngoài tập được chọn · **Khi** mở editor · **Thì** hiện lý do và lối vào Settings, panel không dựng nửa vời | ⚠️ chưa có |
| AC-16 | **Cho** đã mở/gập vài section · **Khi** bấm **Undo** · **Thì** chỉ giá trị chỉnh sửa lùi một bước; trạng thái gập/mở **không** nằm trong History và không đổi | ✅ `EditorPanelLayoutTests.openSectionsNeverReachTheRecipe` |
| AC-17 | **Cho** iPad đang mở editor với Light và Color mở · **Khi** xoay dọc rồi xoay lại ngang · **Thì** trạng thái gập/mở của từng section **giữ nguyên** | ✅ đo 2026-09-22, `ShotDexUITests/scripts/ipad-rotation-state.json` — header về đúng y cũ (Light 258 · Curve 699 · Color 744 · Grade 1112) |

| AC-18 | **Cho** cửa sổ bất kỳ qua cổng rộng · **Khi** nhìn panel · **Thì** mỗi section là một thẻ nền `EditorTheme.control` bo `Radius.lg`, khoảng cách giữa hai thẻ **8pt**, và không còn nét `panelDivider` **giữa** hai section | ⚠️ chưa có — `ui-drive` dump (đo `y` hai header liên tiếp khi gập) |
| AC-19 | **Cho** một hàng slider bất kỳ · **Khi** chạm cách vạch **20pt** theo chiều ngang · **Thì** cú chạm vẫn thuộc về slider đó (vùng bắt chạm ≥ 44pt), hình dạng vẫn là **vạch** chứ không phải núm tròn, và kéo từ mép vùng chạm đổi giá trị đúng bằng khoảng cách di chuyển (không nhảy) | ⚠️ chưa có — test toán + `ui-drive` |
| AC-20 | **Cho** iPad 11" ngang 1210×834 sau khi đã có thẻ, bỏ chân panel và dời Save · **Khi** đo canvas · **Thì** canvas **rộng ≥ 842pt và cao ≥ 782pt** — không hẹp hơn mốc đo ngày 2026-09-22 một pt nào (ảnh 3:2 khi đó chiếm 553/782 = 71%, đã vượt mọi ngưỡng kiểu "≥60%") | ✅ `EditorPanelLayoutTests.theCanvasDoesNotShrinkBelowTheMeasuredBaseline` |
| AC-21 | **Cho** mode Mask và chưa có mask nào · **Khi** nhìn panel · **Thì** năm thẻ **mờ** (`rowDisabled`) và không nhận chạm, kèm một dòng hướng dẫn và nút `+`; **không** có `Cancel/Apply` — mask áp ngay như Crop và Markup | ⚠️ chưa có |
| AC-22 | **Cho** panel ở mode Edit · **Khi** nhìn chân panel · **Thì** **không có** chân panel: không `Save…`, không `Reset All`, và vùng cuộn dài thêm **74pt** so với hôm nay | ⚠️ chưa có — dump (đo đáy vùng cuộn) |
| AC-28 | **Cho** mode **Markup** chưa có layer nào · **Khi** nhìn panel · **Thì** có một nút `+` (không phải bốn nút Add) và một thẻ `Layers` ở trạng thái rỗng | ⚠️ chưa có |
| AC-29 | **Cho** đã có 3 layer · **Khi** chạm **↺** trên thẻ `Layers` và xác nhận · **Thì** cả ba biến mất trong **một** bước Undo, và Undo một lần đưa cả ba trở lại | ⚠️ chưa có |
| AC-30 | **Cho** cửa sổ rộng và đang vẽ một nét · **Khi** nhìn màn hình · **Thì** cọ/cỡ/màu/opacity nằm trong panel bên và **không** có thanh công cụ nào đè lên ảnh; trên cửa sổ hẹp thì vẫn là thanh nổi | ⚠️ chưa có |
| AC-25 | **Cho** một ảnh chưa sửa gì · **Khi** nhìn hàng lệnh trên · **Thì** có pill **`Save`** nền accent chữ đen, **cao 32pt và rộng ≤ 96pt** (hôm nay: 240×50), và trong menu ⋯ dòng **`Reset All Adjustments`** đang **mờ** | ⚠️ chưa có — `ui-drive` dump (`width`/`height` của nút) |
| AC-37 | **Cho** mode Crop & Geometry · **Khi** đo chân panel · **Thì** `Apply` là pill accent cao **32pt** rộng ≤ 96pt, `Cancel` là **chữ trần** không nền, `↺` là đĩa 32pt ở đầu kia, và cả chân panel cao **48pt** | ⚠️ chưa có — dump |
| AC-26 | **Cho** đã kéo Exposure trong thẻ Light · **Khi** chạm nút **↺** trên tiêu đề thẻ Light · **Thì** chỉ các giá trị của Light về mặc định, các thẻ khác giữ nguyên, và đó là **một** bước Undo | ⚠️ chưa có |
| AC-27 | **Cho** bản dựng bất kỳ · **Khi** tìm `Auto` trong editor · **Thì** không còn nút Auto ở panel, không còn dòng *Auto Enhance* trong menu ⋯, và `EditorAutoTone.swift` cùng test của nó đã bị xoá | `grep` trong `Tools/gate` + build |
| AC-23 | **Cho** chọn *Select sky* trong danh sách tạo mask · **Khi** thẻ giải thích hiện ra · **Thì** thẻ vẽ **thumbnail của chính bức ảnh đang mở** với vùng trời tô overlay, không phải ảnh mẫu đóng gói sẵn | ⚠️ chưa có |
| AC-24 | **Cho** một ảnh trong Photos · **Khi** Share → **Edit in ShotDex** · **Thì** app mở thẳng editor đúng tấm ảnh đó; dò không ra asset thì editor chỉ có **Save Copy** và không hiện dòng giải thích nào | ⚠️ chưa có — thuộc [EX-05](../../03-extensions-and-integrations/EX-05-edit-action-extension.md) |

| AC-33 | **Cho** panel đang mở ở mode **Detail** · **Khi** chạm lại icon Detail trên rail · **Thì** panel trượt đi còn rail 48pt, icon Detail **tắt sáng**, và chạm lần nữa mở lại đúng mode Detail | ⚠️ chưa có — `ui-drive` dump ba nhịp |
| AC-34 | **Cho** rail bất kỳ · **Khi** panel đang đóng · **Thì** **không** icon nào sáng, và **không** còn nút `Hide Tools` ở đáy rail | ⚠️ chưa có |
| AC-35 | **Cho** mode **Crop & Geometry** đã kéo khung cắt · **Khi** chạm `Cancel` · **Thì** khung về nguyên trạng lúc vào mode, editor về mode Edit, và recipe **không** có bước crop nào | ⚠️ chưa có |
| AC-36 | **Cho** mode Edit hoặc Presets · **Khi** nhìn đáy panel · **Thì** **không** có chân panel; chuyển sang Crop & Geometry / Mask / Markup thì chân panel `[↺] [Cancel] [Apply]` xuất hiện | ⚠️ chưa có |
| AC-31 | **Cho** iPad 11" **dọc** 834×1194 · **Khi** mở editor · **Thì** panel nằm bên cạnh ảnh (theo `sidebarEdge`) với đúng 5 thẻ như lúc ngang — **không** còn panel đáy 246pt và **không** còn bánh xe chip | ⚠️ chưa có — `ui-drive` dump ở cả hai hướng |
| AC-32 | **Cho** iPad dọc đang mở editor · **Khi** chạm **Hide Tools** trên rail · **Thì** panel gập, canvas rộng trở lại ≥ 786pt trên 11", và trạng thái gập đó còn nguyên sau khi xoay ngang rồi xoay về | ⚠️ chưa có |

**Chưa phủ, cố ý:** Split View và Stage Manager (đo riêng ở `ipad-multitasking`), và bộ AC của sửa nhiều
ảnh nằm ở [FS-03.09b](09b-batch-editing-and-reference.md).

## 10. Quyết định và việc còn treo

**Người dùng đã chốt 2026-09-22** (ghi lại để `/plan` không hỏi lại):

| Chuyện | Chốt |
|---|---|
| Gom nhóm | còn **5** như Lightroom; Curve vào Light, Mix/Point/Grade vào Color, Geometry vào Crop |
| Mặc định | **gập hết**, thấy đủ tên nhóm |
| Duo | histogram **56pt trong panel**, bỏ pill trên band |
| Rail | chạm lại icon đang mở = **đóng panel**; icon **chỉ sáng khi panel mở**; bỏ nút `Hide Tools` |
| Chân panel | không có ở Edit/Presets; **có `[↺] [Cancel] [Apply]`** ở Crop & Geometry · Mask · Markup — cao **48pt**, `Apply` pill accent 32pt, `Cancel` chữ trần, `↺` đĩa 32pt |
| Nút chính | phân biệt bằng **màu**, không bằng kích thước: `Save` và `Apply` đều cao 32pt, rộng vừa chữ |
| iPad dọc | **cũng dùng panel bên** — bỏ vế `rộng > cao` ở cổng vào; chấp nhận ảnh 3:2 còn 27% (11") / 34% (13") chiều cao canvas |
| Điện thoại | **không đụng lượt này** — bánh xe 14 chip giữ nguyên, tách một `/intent` riêng cho phone |
| Opacity hàng mờ | `EditorTheme.rowDisabled = 0.35` |
| Thẻ mask | dùng **chính ảnh đang mở** làm minh hoạ |
| Tên mode | **Crop & Geometry**, đổi **cả tên trong code** (`EditorGroup.crop` → `cropGeometry`); Geometry nằm **cùng một danh sách cuộn** với khung cắt, không tab |
| Extension | `ShotDexEdit` **bỏ hẳn**; thay bằng action extension *Edit in ShotDex* (EX-05) |
| Mask | **có** `[↺] [Cancel] [Apply]` ở chân panel (§5b2), và **giữ panel mờ** cho tới khi có mask |
| Film strip luôn hiện | **không nhận** |
| Bỏ khỏi panel | nút **Auto** (và cả *Auto Enhance* trong ⋯ — xoá `EditorAutoTone`), hàng **Look** (Presets trên rail là lối vào duy nhất), **Save…** (lên hàng lệnh, pill accent), **Reset All** (thay bằng ↺ trên từng thẻ) — chân panel biến mất |
| Curve | trong thẻ **Light**, đồ thị ~300pt, **không nút, không đè ảnh** |
| Nhìn | section thành **thẻ nổi** (8pt; **6pt trên cột ngắn**), **vùng chạm slider 44pt** (giữ vạch), canvas **không hẹp hơn 842×782pt** trên iPad 11" |

**Còn treo:**

- ⚠️ Đổi tên trong code `EditorGroup.crop` → `cropGeometry` đụng **khoá `UserDefaults` đã lưu** (nhóm đang
  mở, trạng thái gập) và [FS-03.01b](01b-adjustments-and-crop.md) + String Catalog. Cần một bước đọc giá
  trị cũ và quy đổi, nếu không người dùng cũ mở editor ra thấy trạng thái lạ. `/plan` chỉ ra đúng các khoá.
- ⚠️ Panel **Crop & Geometry** trong một danh sách cuộn sẽ dài gấp đôi panel Crop hôm nay; trên Duo
  (vùng cuộn 430pt) phải đo xem khung cắt + 6 slider + Upright có buộc phải cuộn ngay từ đầu không (§5).
- ⚠️ Bánh xe 14 chip của [FS-03.01](01-scope-and-panel.md) §5 **lệch** với mô hình 5 nhóm cho tới khi intent
  của phone xong. Đã cắm cảnh báo ở đó; đây là **nợ có ghi**, không phải sót.
