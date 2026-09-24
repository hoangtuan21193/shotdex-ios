# FS-01.06 — Chế độ chọn nhiều ảnh

`FS-01.06` · `App/AssetActionsCoordinator.swift` · `Features/Shared/SelectionBarViews.swift`
· `PhotoTileContextMenu` · `Domain/Selection/SwipeSelection.swift` · cập nhật 2026-09-22

**Một câu:** một lớp phủ toàn màn do màn gốc dựng, dùng chung cho bốn lưới, và **một** bộ điều phối cầm mọi
hành động lên thư viện.

## 1. Quy tắc

- **Giữ lâu không vào chế độ chọn** — giữ một tile mở menu ngữ cảnh kiểu Photos. Vào chế độ chọn bằng nút
  **Select**.
- Vào chế độ chọn → **chỉ ẩn tab bar, nav bar ở lại**: tiêu đề và ngày **đứng nguyên chỗ**.
- **Lớp phủ không vẽ nền đặc** — chỉ ba control kính ở đáy bắt chạm, phần còn lại cho chạm xuyên xuống lưới,
  nếu không lưới không cuộn và không chọn được nữa.
- **Thứ tự chọn được giữ** — nó quyết định thứ tự khung khi Compare.

## 2. Vào và ra

- Nút **`Select`** là chữ, không icon, và ẩn khi đang chọn. Nút **Filter** đứng riêng và **vẫn hiện** khi
  đang chọn.
- Hai cử chỉ giữ-lâu trên cùng một lưới sẽ tranh nhau → cử chỉ giữ-lâu để quét chọn **chỉ bật** khi màn
  không có menu ngữ cảnh, hoặc khi **đang** ở chế độ chọn (lúc đó giữ-rồi-kéo vẫn quét cả dải không cần nhả tay).
- Tile được chọn: **dấu tick trắng trên đĩa accent** + **viền accent 3pt** + ảnh mờ nhẹ; tile chưa chọn là
  một vòng tròn viền trắng.

## 3. Lớp phủ

Màn đang chọn công bố một mô tả thanh chọn lên trạng thái điều hướng; **màn gốc** vẽ lớp phủ đó lên trên cả
hai nhánh iOS, mờ dần theo việc có đang chọn hay không.

| Vùng | Nội dung |
|---|---|
| Nav bar | **Compare** và **Edit** là hai nút chữ bên trái (Compare mờ khi chưa đủ số ảnh, Edit mờ khi không có ảnh nào) · **⋯** · rồi **×** đứng riêng một viên kính |
| Thanh đáy | `[ Share tròn 48 · pill đếm · Delete tròn 48 ]` |

- **Menu ⋯**: Paste Edits (chỉ khi có bản sửa đã copy) · **Combine Photos ▸** (menu con Focus Stack ·
  Panorama · Stack Exposures, [FS-01.09](09-photo-stacking.md)) · Create Collage (bật khi số ảnh nằm trong tập
  template hỗ trợ) · Create Video · Resize · Add to Collection · Export EXIF (CSV) · **Upload to Server**
  ([FS-15](../FS-15-server-upload/README.md)) · Duplicate. Màn không cấp
  hành động nào thì dòng đó **không hiện**; ngoài khoảng hợp lệ thì **mờ** — ở Combine Photos là từng dòng con
  mờ, dòng cha vẫn mở được.
- Compare và Edit **không** nằm trong menu — hai thứ người ta chọn ảnh *để làm*, còn menu là chỗ tìm những
  thứ còn lại.
- Share đổi thành vòng quay khi đang gom ảnh. Delete **không tô đỏ** (hệ thống đã hỏi xác nhận). Không dùng
  được thì **mờ, không ẩn**.
- **Pill đếm là nút**: `N selected・{dung lượng}`; chưa chọn gì thì `Select Items` và mờ. Dung lượng tính
  ngoài luồng chính; chưa index đủ thì thêm dấu `~`.
- Chạm pill mở **sheet danh sách ảnh đã chọn**: lưới ô vuông, **chạm một ô là bỏ chọn ô đó**, `Done` ở
  toolbar, pill **Deselect All** ghim đáy; bỏ hết thì sheet tự đóng. Sheet do lớp phủ dựng nên dùng chung
  cho cả bốn màn.
- Lưới chừa **100pt** ở đáy cho thanh này, cả hai nhánh iOS.
- Nền kính của pill và hai nút tròn đi qua **một** hàm dùng chung — kính hệ thống trên iOS 26, vật liệu mờ
  + viền + bóng ở bản trước.

## 4. Chọn bằng vuốt

- 8pt đầu quyết định hướng: ngang là chọn, dọc là nhường cuộn.
- Dải chọn tính theo **vị trí trong danh sách phẳng** giữa ô bắt đầu và ô dưới ngón, áp lên **bản chụp lựa
  chọn lúc bắt đầu kéo** nên kéo lùi tự hoàn tác. Bắt đầu trên ô đã chọn → kéo là **bỏ chọn** cả dải.
- Cuộn tắt trong lúc kéo; giữ ngón ở mép thì lưới tự cuộn; pinch đổi mật độ vẫn dùng được.
- Toán thuần (khoá hướng, tốc độ tự cuộn) nằm ở tầng logic và có test. Chi tiết cử chỉ:
  [FS-01.01b](01b-grid-engine-and-gestures.md).

## 5. Menu ngữ cảnh trên tile

Giữ một tile khi **không** ở chế độ chọn → hệ thống nhấc **chính ô đó** lên làm bản xem trước (không dựng
một bản riêng), rồi mở menu ba nhóm:

1. Favorite/Unfavorite · Share · **Copy** (chỉ ảnh — video không đưa lên clipboard được)
2. Add to Album · Duplicate · Adjust Date & Time · Adjust Location
3. Hide · Delete — riêng Album Detail có thêm **Remove from Album**; cả nhóm là hành động phá huỷ

Menu dựng **một lần** cho cả bốn lưới.

## 6. Một bộ điều phối cho mọi hành động

Một nơi duy nhất giữ cả trạng thái trình bày (yêu cầu sửa ngày, sửa vị trí, thêm vào album, thông báo lỗi,
toast), nên bốn màn lưới không phải cài lại từng cái.

Sheet được gắn ở chỗ **có thể trình bày** lên màn người dùng đang xem, mỗi chỗ một bộ điều phối riêng:

- **Màn gốc của mỗi cửa sổ** — phủ mọi lưới trong cửa sổ đó. Mỗi cửa sổ (iPad nhiều scene) có bộ riêng: dùng
  chung một bộ thì sheet mở ở cửa sổ này bị cửa sổ kia cũng giành trình bày.
- **Màn xem ảnh** — viewer là lớp phủ toàn màn nên sheet từ gốc không với tới
  ([FS-02](../FS-02-photo-detail/README.md)).
- **Sheet Burst mở từ viewer** — cả gốc lẫn viewer đều không trình bày chồng lên được sheet đang mở, nên danh
  sách Burst có bộ riêng.

Màn lưới **lấy bộ điều phối của nơi gắn sheet phía trên nó** (qua environment), không lấy bộ dùng chung trong
`AppDependencies` — gửi hành động vào bộ không ai gắn sheet thì Adjust Date & Time / Adjust Location / Add to
Collection bấm xong **không mở gì**, lỗi và toast cũng không hiện.

| Hành động | Chi tiết |
|---|---|
| Share | gom mọi asset đã chọn (ảnh thành dữ liệu, video thành file, cho tải bản chỉ-có-trên-iCloud) |
| Delete | hệ thống hỏi xác nhận; huỷ thì **giữ nguyên lựa chọn** |
| Add to Collection | sheet liệt kê album người dùng (loại smart và shared) + "New Album…"; xong thì thoát chế độ chọn |
| Export EXIF (CSV) | dựng CSV đúng chuẩn escape, ghi file tạm rồi mở sheet chia sẻ |
| Duplicate | sao **mọi** phần của ảnh (RAW+JPEG, đoạn video của Live Photo, giữ tên file), **không nén lại** |
| Adjust Date & Time | ghi thẳng lên ảnh, **không viết lại EXIF trong file gốc** (giống Photos). Nhiều ảnh thì picker sửa ảnh **sớm nhất** và cả khối dịch theo **cùng một khoảng**, giữ nguyên khoảng cách giữa các tấm |
| Adjust Location | xoá toạ độ |
| Hide | ghi được nhưng **không đọc lại được** — từ iOS 16 hệ thống giấu ảnh ẩn khỏi mọi app trừ Photos (đo trên iOS 26: album ảnh ẩn trả về 0). Nên app có Hide, **không có** album Hidden và **không có** Unhide |

- **Duplicate giữ nguyên lựa chọn**: nhân bản là một bước giữa chừng của một việc (copy xong rồi cho vào
  album, hoặc sửa) — thoát chế độ chọn bắt người dùng quét chọn lại đúng từng ấy ảnh.
- Phần nào ghi không được thì **bị bỏ qua chứ không ném lỗi**, nên "không copy được tấm nào" về đây là **số
  0 chứ không phải lỗi** — và phải nói ra (*"Those photos couldn't be copied."*), nếu không lệnh trông như
  bị lờ đi.
- Lỗi của các hành động trong menu hiện cảnh báo riêng, không đụng cảnh báo của Delete.
- Áp cho **Library, album thường, smart album**; **On This Day** giữ gọn — chỉ Share, Compare, Resize,
  Delete; không có Create, không có ⋯.

## 7. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
