# Intent: Settings trên iPad vẫn là layout điện thoại bị kéo rộng

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan@karabiner.tech |
| Ngày | 2026-09-21 |
| Trạng thái | draft |
| Nguồn | phản hồi người dùng (quan sát trực tiếp trên iPad) |
| Spec sinh ra từ đây | (điền khi sang Design) |

## Problem — vấn đề

Mở Settings trên iPad và người dùng đọc một màn điện thoại bị thổi ra 1376pt: mỗi dòng
là một hàng trải hết bề ngang, nhãn dính mép trái còn giá trị/công tắc dính mép phải,
ở giữa là một vùng trống dài gần một mét ảo. Không phải cảm giác — đo trên ảnh chụp
`iPad Pro 13-inch (M5)` / iOS 26.5, ngang 1376×1032pt
([assets/2026-09-21-ipad-settings-13in-landscape.png](docs/_intents/assets/2026-09-21-ipad-settings-13in-landscape.png),
chụp bằng `Tools/sim-shot` trong lúc `Tools/ui-drive` giữ màn):

- Hàng **Access**: nhãn ở x≈40pt, giá trị "Full Access" kết thúc ở x≈1339pt — hai thứ
  thuộc về nhau đứng cách nhau **~1250pt**.
- Hàng **Use Cellular Data for Indexing**: chữ hết ở x≈255pt, công tắc bắt đầu ở
  x≈1280pt — **~1025pt** trống giữa nhãn và control mà nó điều khiển.
- Footer giải thích ("Indexing reads the camera, lens and exposure info…") chạy **một
  dòng dài ~1310pt**, gấp hơn ba lần chiều dài dòng đọc được.
- Toàn màn là **một cột 12 section** (`photoLibrary` → `privacy`), không có gì ở nửa
  còn lại của màn hình; muốn tới Privacy phải cuộn qua cả 12 section dù màn cao 1032pt
  vẫn dư chỗ.

Nguyên nhân ở code, không phải ở SwiftUI: [SettingsScreen.swift:74](ShotDex/Features/Settings/SettingsScreen.swift:74)
là một `List` `.insetGrouped` phẳng, và **cả thư mục `Features/Settings/` không có
một chỗ nào đọc `horizontalSizeClass`** trừ hai chỗ trong `PhotoWidgetPickers.swift`
(tile size). Cả app **không dùng `NavigationSplitView`** ở đâu cả. Settings được mở
bằng `fullScreenCover` + `NavigationStack` ([SettingsSheet.swift:29](ShotDex/App/SettingsSheet.swift:29)),
nên trên iPad nó chiếm trọn 1376pt thay vì một container hẹp lại.

Việc này đi ngược đúng luật của dự án: `DESIGN.md` §10.1c — "màn rộng hơn = **nhiều nội
dung hơn**, không phải nội dung to hơn" — và §13 đã áp luật đó cho danh sách điểm-đến
(`LazyVGrid` `.adaptive(minimum: 320)`, "một hàng trải hết 1032pt là layout điện thoại
bị phóng to: số đứng cách tên nó 800pt"). Statistics, lưới ảnh, Collections, editor đều
đã có nhánh regular width; Settings là màn sót lại. `docs/02-functional-spec/FS-08-settings/README.md`
**không nhắc một chữ nào** về iPad hay size class — đặc tả im lặng nên code im lặng theo.

Ai bị ảnh hưởng: mọi người dùng iPad (11" và 13", dọc lẫn ngang) và **màn trong iPhone
Duo** (951×669, regular width). Mức độ: không chặn tính năng nào — mọi thứ vẫn bấm được
— nhưng là màn duy nhất trong app còn đọc ra như một bản phóng to, và nó là màn khách
mở ra đầu tiên khi muốn hiểu app làm gì.

## Proposed outcome — kết quả mong muốn

Mở Settings trên iPad và nó đọc ra như một màn iPad: nhãn và giá trị của cùng một hàng
nằm gần nhau đủ để mắt nối được, dòng chữ giải thích dài bằng một dòng đọc được, và
không phải cuộn qua 12 section để tới mục cuối — màn rộng cho thấy **nhiều mục cùng
lúc**, không phải mục to hơn. Các màn con (Camera Database, Photo Widget designs,
Compression Presets) cũng phải theo cùng cách, chứ không mỗi màn một kiểu.

Trên iPhone không đổi gì: vẫn đúng `List` `.insetGrouped` một cột như hôm nay.

## Affected users and systems — phạm vi ảnh hưởng

- **Màn hình**: `Features/Settings/` — `SettingsScreen` (655 dòng, 12 section) và bốn
  màn con push từ nó: `CameraDatabaseScreen`, `PhotoWidgetDesignsScreen`,
  `PhotoWidgetSettingsScreen` (934 dòng, có preview kéo/pinch), `CompressionPresetsScreen`.
  Cộng `Features/Support/SupportScreen` (và `SupportThreadScreen`, `SupportComposeScreen`
  push tiếp từ nó) vì Support vào cùng cấu trúc, và lối vào
  `App/SettingsSheet.swift` (`fullScreenCover` + `NavigationStack`).
- **Thiết bị**: iPad 11"/13" dọc và ngang (và Split View/Stage Manager ở bề rộng hẹp —
  phải rơi về layout compact), màn trong iPhone Duo 951×669. iPhone và màn ngoài Duo:
  **không đổi**.
- **Tầng code**: chỉ `Features/` (view layer). Không đụng Domain, Data, ShotDexKit hay
  extension nào.
- **Dữ liệu đã lưu**: không. Mọi setting nằm ở `@AppStorage`/`SettingsKeys`; đây thuần
  là bố cục. Không cần migration.
- **Tài liệu**: `docs/02-functional-spec/FS-08-settings/README.md` phải thêm phần regular width;
  `DESIGN.md` §10.1a (đang ghi Settings = `NavigationStack` → `List` `.insetGrouped`)
  phải nói rõ nhánh màn rộng.

## Constraints — ràng buộc

- **Không thêm dependency**, không thêm setting mới cho người dùng chọn layout ("bớt một
  quyết định hơn là thêm một setting").
- **Không phóng to layout hiện có** — luật `DESIGN.md` §10.1c. Cũng không được chỉ bóp
  nội dung vào giữa rồi coi là xong nếu cách đó vẫn để 12 section trong một cột dài.
- **Điện thoại có đủ mọi chức năng của iPad** (NF-05 §37): nhánh mới không được làm rơi
  mất hàng nào ở compact — dựng danh sách section từ một nguồn chung, không viết tay hai
  lần.
- **Giữ cả hai nhánh iOS 26 và pre-26** chạy được; iPad iOS 18.6 vẫn đi nhánh tab bar
  custom.
- Ngưỡng bố cục đo theo **bề rộng cửa sổ thật** chứ không chỉ size class, để iPad Split
  View hẹp giữ layout điện thoại (cùng cách `EditorLayoutMetrics` đang làm).
- `PhotoWidgetSettingsScreen` có preview kéo và pinch — lý do Settings bỏ sheet đổi sang
  full screen ngay từ đầu; bố cục mới không được đẩy nó về một container kéo-để-đóng.
- Không đổi thứ tự hay tên section (đó là việc của copy/UX, không phải intent này).

## Decisions — đã chốt (2026-09-21, người dùng)

1. **Hình dạng: `NavigationSplitView`** — sidebar liệt kê các nhóm setting, detail hiện
   nhóm đang chọn, như Settings của Apple trên iPad. (Bỏ phương án chia cột kiểu
   Statistics và phương án chỉ giới hạn bề rộng.)
2. **Màn con nằm trong detail pane**, kể cả `PhotoWidgetSettingsScreen` — preview kéo và
   pinch lấy trọn pane, không push chồng lên toàn màn.
3. ~~**Ngưỡng vào layout rộng: ≥900pt** bề rộng cửa sổ thật.~~ **Đã đổi ở giai đoạn
   Design (2026-09-21)**: ngưỡng là **`horizontalSizeClass == .regular`**, giống hệt
   Settings của iPadOS — đo trên máy ảo thấy iPadOS đã split ngay ở iPad 11" dọc (834pt),
   nên 900pt sẽ để đúng máy đó ở lại layout điện thoại. Xem
   [FS-08 — Bố cục theo bề rộng cửa sổ](../02-functional-spec/FS-08-settings/README.md).
4. **Support kéo vào cùng cấu trúc** — thành một mục trong sidebar chứ không còn là
   `NavigationLink` cuối danh sách. **Import bị bỏ hẳn khỏi Settings** — xem mục dưới.

## Import — tách ra intent riêng

Người dùng quyết **bỏ hẳn lối vào Import**, không dời sang chỗ khác: `ImportScreen` chỉ
có đúng một lối vào là hàng "Import Photos" trong Settings
([SettingsScreen.swift:100](ShotDex/Features/Settings/SettingsScreen.swift:100)), bỏ hàng
đó là màn thành code chết.

Đó là **đổi tính năng, không phải đổi bố cục**, nên theo luật `/intent` (hai vấn đề = hai
file) nó đi ra intent riêng: `docs/_intents/2026-09-21-remove-import-entry-point.md`.
Intent này chỉ lo layout iPad. Nếu intent Import được duyệt trước thì hàng Import biến
mất khỏi cả hai layout; nếu chưa, nó vẫn nằm trong nhóm Photo Library như hôm nay.

## Open questions — câu hỏi còn treo

Không còn câu nào chặn sang Design. Hai thứ để lại cho `/spec` chốt bằng số đo, không
phải bằng ý kiến:

- Sidebar mặc định chọn nhóm nào khi mở Settings lần đầu (đề xuất: Photo Library, nhóm
  đầu tiên), và có nhớ nhóm đã chọn giữa các lần mở không (đề xuất: không nhớ).
- Bề rộng sidebar và sàn còn lại cho detail pane ở 900pt — đo để detail không hẹp hơn
  bề rộng nội dung của một chiếc điện thoại (320pt).

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
