# FS-05.01 — Các loại lớp, Draw và dải lớp

`FS-05.01` · `Domain/Editing/ShapeOverlayGeometry.swift` · `Features/Editing/EditorDrawingCanvas.swift`
· cập nhật 2026-09-24

**Một câu:** hình và kính lúp hoạt động thế nào, vẽ tay chạy trong panel ra sao, và dải lớp sắp xếp mọi thứ.

## 1. Quy tắc

- Hình học của hình vẽ là **một bộ toán thuần**, dùng chung cho renderer và cho bản vẽ sống trên ảnh.
- **Kính lúp ghép trước, vành vẽ sau** — nó là lớp duy nhất mà hình dạng phụ thuộc ảnh bên dưới.
- Vẽ tay dùng **khung vẽ của PencilKit**, nhưng công cụ, cỡ, độ mờ và màu nằm **trong panel ShotDex** — bảng
  công cụ của hệ thống không bao giờ hiện.

## 2. Hình

Năm kiểu: **chữ nhật · elip · bong bóng thoại · mũi tên · đường thẳng**.

- **Mũi tên và đường thẳng không tô được**: tô một mũi tên là tô cái tam giác tạo ra nó, không phải làm mũi
  tên dày hơn.
- **Đổi kiểu được sau khi tạo** — lỡ đặt hình vuông mà muốn hình tròn thì không phải xoá lớp rồi đặt lại.

## 3. Kính lúp

- Phần phóng được **ghép vào ảnh trước** bộ lớp còn lại: phóng ảnh quanh tâm vòng tròn rồi trộn theo một
  mặt nạ đĩa. Nếu cắt thẳng, mép vòng sẽ răng cưa ở độ phân giải xuất.
- **Vành** thì vẽ cùng chỗ với mọi lớp khác.
- **Luôn tròn, không bóp méo được** — kính lúp méo thì làm mờ đúng thứ nó phải làm rõ.
- Phóng 1× thì coi như không có tác dụng.
- **Kính lúp không được chọn vẫn phải nướng vào ảnh** khi đang sửa lớp khác: bản vẽ sống nằm trên một lớp
  trong suốt, không có pixel nào để phóng — bỏ chúng ra là mất trắng kính lúp suốt thời gian có lớp đang chọn.
- Riêng kính lúp **đang chọn** thì nhường chỗ như mọi lớp khác, nếu không vành sẽ hiện **hai vòng** lúc kéo:
  một chỗ đã nướng, một dưới ngón tay. Đối xứng lại, bản vẽ sống chỉ vẽ vành của kính lúp đang chọn.

## 4. Draw

Chip **Pen** hoặc **Marker** trong màn "Add a layer" tạo **một lớp nét vẽ mới** và bắt đầu vẽ ngay. Chọn lại
một lớp nét vẽ rồi vẽ thì nét vào **chính lớp đó**.

| Hàng (thứ tự) | Nội dung |
|---|---|
| 1 | chip **Draw · Erase · Select** + nút **Ruler** |
| 2 | chip loại mực, cuộn: Pen · Marker · Pencil · Fountain · Monoline · Watercolor · Crayon |
| 3–5 | Size (trong khoảng cỡ của loại mực đó) · Opacity · Color |
| cuối | Rotate · Across · Down như mọi lớp |

- Erase có hai kiểu: xoá **cả nét** hoặc xoá **theo điểm**. Select là lasso: chọn · dời · xoá nét **trong lớp
  đang chọn**.
- Double-tap / bóp Apple Pencil đổi sang Erase như ở app hệ thống. Nhận cả ngón tay lẫn Pencil như hôm nay.
- Đang ở một lớp nét vẽ với Draw / Erase / Select: **một ngón trên ảnh là vẽ**; chọn lớp khác qua dải.
  Khung vẽ vừa khít ảnh, không phóng (v1); chọn lớp nét vẽ là đặt lại mức phóng.
- `⋯` của lớp nét vẽ có **Clear Strokes** (thay nút Clear của chế độ chiếm màn cũ).
- **Mỗi nét là một bước hoàn tác**: Undo trên băng lùi từng nét, như Photos (thay "một phiên vẽ = một bước").
- Lớp nét vẽ **không được chọn** hiển thị bằng bản raster đã cache; chỉ lớp đang chọn có khung vẽ sống.
- Công thức lưu mỗi lớp nét vẽ một khối vector riêng. Công thức cũ chỉ có một khối nét vẽ không được đọc (app
  chưa phát hành, không migration).

## 5. Render nét vẽ

Mỗi lớp nét vẽ ghép **theo thứ tự của nó trong dải lớp**, như mọi lớp khác.

- Có trong đường render chính và trong **bản chỉ để hiển thị** của bản xem trước; bản sạch dùng cho ống hút
  màu và histogram thì **bỏ qua nét** (như với mọi lớp khác); thumbnail và mặt nạ mask cũng sạch.
- Live Photo raster **một lần** rồi ghép cho mọi khung.
- Raster theo đúng tỉ lệ giữa khung xuất và khung lúc vẽ, vẽ theo chiều bottom-up đúng quy ước của lớp ảnh,
  và **cache** theo từng lớp, theo nội dung + kích thước — lớp không đổi thì không raster lại.
- Chỉ raster **khung bao của nét**, không cả khung ảnh. Khung bao lớn hơn 24MB ở kích thước xuất (nét phủ gần
  cả ảnh 48MP) thì raster **theo dải ngang** ≤ 24MB, vẽ xong dải nào bỏ dải đó — không bao giờ có bitmap thứ hai
  cỡ cả khung bên cạnh bitmap lớp phủ; dải không vào cache (cache 192MB tính theo byte).
- Bản xem trước khi đang cắt ảnh **bỏ cả lớp markup lẫn nét vẽ**.

## 6. Dải lớp trong panel

- **"Add a layer"** (chưa có lớp, hoặc vừa chạm `+`; có `‹` khi đã có lớp) — ba hàng chip, mỗi hàng cuộn ngang:
  Text · Image · Sign / Pen · Marker / Rectangle · Oval · Speech bubble · Arrow · Line · Magnifier.
  **Sign** mở thư viện chữ ký như hôm nay.
- **Có lớp**: dải 40pt — thumbnail 40×30 mỗi lớp (nền tối + icon loại lớp, lớp chữ tô theo màu chữ; lớp ẩn mờ
  35%) · `+` · tên lớp · `⋯`. **Giữ rồi kéo** thumbnail thả lên thumbnail khác để đổi thứ tự (lớp kéo lấy chỗ lớp bị thả lên; một bước Undo — `MarkupPhonePanelTests.dragOntoATileRestacksTheLayer`, ảnh iPhone 17 26.5, 2026-09-25).
- `⋯`: Rename · Duplicate · Hide / Show · Bring Forward · Send Backward · Save as Preset · Delete · Remove All
  Layers (+ Clear Strokes với lớp nét vẽ, Replace Image với lớp ảnh).
- Hàng thuộc tính của từng loại, theo thứ tự:

| Loại | Hàng |
|---|---|
| chữ | Font · Size · Color · Bold / Italic / Align (một hàng chip) · Opacity · Outline · Shadow · Width · Leading · Tracking |
| hình | chip kiểu hình · Color · Filled · Thickness · Height · Opacity |
| ảnh | chip Choose Image · Opacity |
| kính lúp | Zoom · Rim Color · Rim Width · Opacity |
| mọi lớp | cuối cùng: Rotate · Across · Down |

## 7. Tiêu chí nghiệm thu panel phone

Tiếp số của [FS-03.12](../FS-03-photo-editor/12-phone-panel-grid.md). Máy: iPhone 17, iOS 26.5 và 18.6.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-26 | ảnh chưa có lớp | mở Markup | "Add a layer" + ba hàng chip; panel 264 | `MarkupPhonePanelTests.noLayerShowsTheChooser` + ảnh iPhone 17 26.5, 2026-09-24 |
| AC-27 | như AC-26 | chạm Text | có 1 lớp chữ, bàn phím mở, dải hiện 1 thumbnail | `MarkupPhonePanelTests.textMakesOneSelectedLayer` + ảnh iPhone 17 26.5, 2026-09-24 |
| AC-28 | ảnh chưa có lớp | chạm Pen, vẽ 1 nét, chạm `+`, chạm Pen, vẽ 1 nét | 2 lớp nét vẽ, mỗi lớp 1 nét; bảng công cụ hệ thống không hiện lần nào | `EditorDrawLayerTests.twoPenSessionsMakeTwoLayers` + ảnh iPhone 17 26.5, 2026-09-24 (không có bảng công cụ hệ thống) |
| AC-29 | lớp nét vẽ, Marker, Size 20, Opacity 50% | vẽ 1 nét | nét ghi loại mực marker, bề rộng 20, alpha 0,5 | `EditorDrawLayerTests.thePanelBuildsTheInkingTool` |
| AC-30 | lớp nét vẽ có 3 nét | Undo một lần | còn 2 nét, lớp vẫn còn và vẫn chọn | `EditorDrawLayerTests.eachStrokeIsOneUndoStep` + ảnh iPhone 17 26.5, 2026-09-24 |
| AC-31 | 2 lớp: chữ trên, nét vẽ dưới | `⋯` của nét vẽ → Bring Forward | nét vẽ ghép trên chữ ở bản xuất | `PhotoDrawingModelsTests.aDrawingLayerComposesInStackOrder` |
| AC-32 | lớp chữ đang chọn | chạm vùng trống trên ảnh | khung chọn trên ảnh mất; panel vẫn là hàng của lớp chữ đó | `MarkupPhonePanelTests.tapOnEmptyPhotoKeepsThePanelLayer` |
| AC-33 | lớp chữ, hàng Color | dump hàng | 6 ô màu = 4 mức xám + 2 màu như hôm nay, cộng ô custom | ảnh iPhone 17 26.5, 2026-09-24 (hàng màu); ⚠️ chưa có dump |
| AC-34 | lớp chữ, hàng Color | chạm ô custom, rồi `‹` | bảng màu hiện rồi đóng; panel 264 suốt hai bước | ảnh iPhone 17 26.5, 2026-09-24 (bảng màu + ống hút); `MarkupPhonePanelTests.recentColorsAreNewestFirstAndCapped` |
| AC-35 | 8 lớp, dải cuộn ở đầu | chạm lớp thứ 8 trên ảnh | lớp 8 được chọn, thumbnail của nó nằm trọn trong dải | ⚠️ chưa có |
| AC-36 | 1 lớp | chạm `+` rồi `‹` | vẫn 1 lớp, lớp cũ vẫn chọn | `MarkupPhonePanelTests.plusThenBackMakesNothing` |
| AC-37 | 1 lớp | `⋯` → Delete | 0 lớp, panel về "Add a layer", không có `‹` | `MarkupPhonePanelTests.deletingTheLastLayerShowsTheChooser` |
| AC-38 | ảnh 48MP, 10 lớp nét vẽ, mỗi lớp 50 nét | lưu bản full-res | lưu xong; bộ nhớ đỉnh của lượt render nét vẽ < 400MB | `PhotoDrawingModelsTests.aDrawingRastersOnlyItsBoundingBox` (khung bao nhỏ < 8MB), `aFullFrameDrawingIsPlannedInBoundedBands` (lớp phủ cả khung 48MP vẽ theo dải ≤ 24MB, không tạo bitmap thứ hai cả khung), `bandedDrawingHasNoSeams`; ⚠️ chưa đo bộ nhớ đỉnh cả lượt lưu trên máy |

**Chưa chứng minh được:** AC-33 (dump hàng), AC-35 (dải cuộn theo lớp chọn trên ảnh), AC-38 (bộ nhớ đỉnh cả lượt lưu).
