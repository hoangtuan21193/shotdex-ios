# FS-18.05 — Nền tảng, phát hành, phạm vi

`FS-18.05` · target app macOS mới · `ShotDexKit` · `ShotDex/Domain/` · `ShotDex/Data/` · cập nhật 2026-10-04

**Một câu:** một app macOS SwiftUI riêng dùng chung lõi render, logic và tầng dữ liệu với iOS, phát hành một lần đủ
tính năng qua Mac App Store, trong sandbox.

## 1. Target và phần dùng chung

- **Native macOS SwiftUI** — không Catalyst, không "Designed for iPad" (người dùng chốt 2026-10-04).
- Dùng chung nguyên: `ShotDexKit` (render, recipe, kernel Metal [FS-16](../FS-16-metal-kernels.md)), `Domain` (logic thuần).
- Dùng chung có sửa: `Data` — GRDB, ImageIO, PhotoKit đều có trên macOS; thêm nguồn thư mục/server theo FS-19.
- Viết riêng: lớp view Mac. Đo 2026-10-04 (spike plan FS-18 §2): **70** file app `import UIKit` (+ 1 file kit,
  + 3 extension), **127** file dùng kiểu `UI*`, **26** file bọc view UIKit, PencilKit ở **3** file app + **1** file kit.
  Kit đã build cho macOS (arm64, macOS 15) từ P1. Model trạng thái dùng lại được khi nó không chạm UIKit.
- Mỗi app một gốc ghép phụ thuộc, dựng từ cùng các mảnh ([BD-01](../../01-basic-design/BD-01-system-architecture.md) §1).
- **Spike trước mọi màn** (PLAN 3.1): build Kit + Domain + Data cho macOS, đếm lỗi, đưa con số vào `/plan`.
- Không thêm dependency ngoài GRDB và hai thư viện server đã có của [FS-15](../FS-15-server-upload/README.md) §3.

- **macOS 15 trở lên, chỉ Apple silicon** (bản build chỉ có arm64). Board vẽ macOS 26 với Liquid Glass.
- macOS 15–25 chạy **nhánh trước Liquid Glass**, như iOS trước 26: sidebar, toolbar, popover là bản hệ thống của
  macOS đó, không vẽ giả kính; cùng lệnh, cùng phím, cùng bố cục số đo ([01](01-window-and-navigation.md) §1).
- Hai nhánh cùng build; mỗi nhánh có bộ ảnh chụp kiểm tra riêng (§6).

## 2. Phân phối: Mac App Store, sandbox (D1)

| Quyền sandbox | Dùng cho |
|---|---|
| đọc-ghi file người dùng tự chọn | thêm thư mục, ổ ngoài, thẻ nhớ; ghi sidecar `.xmp` và file xuất |
| bookmark có phạm vi app (security-scoped) | giữ quyền vào thư mục/ổ đã thêm qua các lần mở app |
| thư viện Photos | nguồn Photos Library |
| kết nối mạng ra ngoài + mạng cục bộ | server SMB/SFTP/WebDAV, tìm server trong mạng, Support |

- Mỗi thư mục/ổ thêm vào lưu một bookmark; mở lại app không hỏi lại. Bookmark hỏng hay hết quyền → hàng nguồn
  sang trạng thái "cần cấp quyền" với nút Grant Access (FS-19).
- Mật khẩu server trong Keychain, như iOS. Bản kê quyền riêng tư (privacy manifest) riêng cho target Mac, gồm
  lý do đọc ngày file và dung lượng trống; usage string cho Photos và mạng cục bộ.
- Riêng tư như [NF-03](../../04-non-functional-design/NF-03-privacy-and-security.md): không telemetry, không cloud riêng;
  hai ngoại lệ vẫn là Support và server người dùng tự khai.

## 3. Một lần phát hành đủ tính năng (D2)

- Bản 1.0 có mọi màn của FS-18, FS-19, FS-20, cộng Video Studio, server, Collage, Combine Photos, Resize, Duplicates,
  Places. Không ẩn tính năng sau cờ, không "coming soon".
- Thứ tự làm do `/plan` chốt; tiêu chí phát hành là mọi AC ở [06](06-acceptance-criteria.md) và các FS kia có chứng minh.

## 4. Recipe và dữ liệu

- **Cùng một recipe**, render bằng cùng `ShotDexKit`: cùng recipe ra cùng ảnh trên Mac và iPhone.
- Ảnh Photos: recipe nằm trong adjustment data của Photos ([FS-03.06](../FS-03-photo-editor/06-saving-recipe-and-live-photo.md))
  nên qua iCloud Photos sang iPhone vẫn mở đúng slider.
- Ảnh thư mục/server: recipe nằm trong database theo id ảnh và trong vùng ShotDex của sidecar (FS-19). iPhone, iPad,
  Duo cũng có nguồn thư mục/ổ USB-C và server được index, nên mở cùng ổ hay NAS là thấy cùng slider.
- Database cùng schema ([BD-02](../../01-basic-design/BD-02-database-design.md)) cộng bảng nguồn/định danh của FS-19 —
  `data-migration` duyệt. Database nằm trong container của app Mac; không đồng bộ với database iOS.

## 5. Ngoài phạm vi bản đầu · chức năng giữa các thiết bị

- Màn hình thứ hai / Secondary Viewer (D14) — chỉ có Open in New Window.
- Widget, Share extension, Edit action extension trên Mac (intent: để sau). Settings Mac không có mục Widgets.
- Đồng bộ recipe, cờ, album của ShotDex giữa Mac và iPhone ngoài hai đường: Photos/iCloud và sidecar trên cùng ổ/NAS.
- Catalyst, bản iPad chạy trên Mac.

**Luật chức năng giữa các thiết bị** ([NF-05](../../04-non-functional-design/NF-05-device-and-os-compatibility.md) §1):
Mac được có **cách thao tác** riêng — menu bar, phím, nhiều cửa sổ, Activity, kéo thả, con trỏ — miễn **mọi việc**
vẫn làm được trên iPhone và iPad. Vì vậy các phần Mac thêm đi sang iOS cùng đợt:

| Phần | Sang iOS ở |
|---|---|
| popup Color Space khi xuất (D17) | FS-03.04, FS-03.07b — mọi thiết bị |
| trục giờ trong ngày, thứ trong tuần (D18) | FS-07.01 §2 — mọi thiết bị |
| công tắc Advance After của Cull | FS-01.12b |
| ô tick theo nhóm trong Sync | FS-03.09b |
| đầu nhóm ngày trong lưới | DESIGN.md §10.2 — ngoại lệ màn rộng (iPad, Duo trong), iPhone giữ lưới phẳng |

## 6. Kiểm thử

- Domain và Data dùng chung: test hiện có của `ShotDexTests` vẫn chạy trên simulator iOS và vẫn là chứng minh.
- Build iOS không được hỏng: `Tools/gate` (build + unit test iOS) phải xanh sau mọi commit có target Mac.
- Thêm **target unit test macOS** (test riêng của view model và lệnh Mac) và **target UI test macOS** có driver JSON:
  `Tools/ui-drive` mở rộng cho Mac — chạm theo nhãn, phím, kéo thả, dump khung phần tử, chụp cửa sổ.
- Script UI ở `ShotDexMacUITests/scripts/`. `Tools/gate` build cả Mac và chạy unit test Mac; `design-board compare`
  đối chiếu dump Mac với board như iOS.
- Luật "build, chạy, chụp, xem" của CLAUDE.md có bản Mac: chụp cả macOS 26 và một máy macOS 15.
- Hôm nay chưa có cả hai target lẫn driver Mac — mọi AC Mac ở [06](06-acceptance-criteria.md) ghi `⚠️ chưa có`.

## 7. Ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Hiệu năng | ngân sách [NF-01](../../04-non-functional-design/NF-01-performance.md) trên thư viện 55,231 mục, mọi nguồn cộng lại |
| Bộ nhớ | [NF-02](../../04-non-functional-design/NF-02-memory-and-resources.md); preview cache trên đĩa, chỗ đặt đổi được (FS-19) |
| Cỡ cửa sổ | cửa sổ chính (Library, Editor, công cụ) ≥ 1024×700 · Video Studio ≥ 1180×760 ([01](01-window-and-navigation.md) §4) |
| Bàn phím | mọi lệnh tới được không cần chuột; Full Keyboard Access của macOS đi được hết toolbar và sidebar |
| Vùng bấm | ≥ 20×16 theo chuẩn con trỏ — ngoại lệ Mac của NF-06 §1 ([01](01-window-and-navigation.md) §9) |
| Truy cập | VoiceOver đọc mọi control tự vẽ (ô lưới, slider editor, timeline) với trạng thái hiện tại ([NF-06](../../04-non-functional-design/NF-06-accessibility-and-localization.md)) |
| Ngôn ngữ | cùng String Catalog; số, ngày, đơn vị qua bộ định dạng hệ thống; đồng hồ 12 giờ ở en-US |
| iOS | không đổi hành vi iPhone/iPad/Duo ngoài các phần §5 đưa sang; cả nhánh iOS 26 và trước 26 vẫn build |
| macOS | 15 trở lên, Apple silicon; nhánh 26 và trước 26 cùng lệnh (§1) |

## 8. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Bề mặt vẽ của PencilKit có thể không dùng được trên macOS cho mask/markup (3 file) | spike kiểm trước; không được thì vẽ bằng con trỏ trên canvas tự dựng |
| PhotoKit trên Mac: thư viện trên ổ ngoài, Optimize Mac Storage | áp các luật bản gốc iCloud đã có (FS-02.06); đo trên Mac thật |
| Hai thư viện server (SMB, SFTP) chưa từng build cho macOS sandbox | đưa vào spike; lỗi thì ghi số vào `/plan` |
| D2 dồn mọi màn vào 1.0 | spike đo trước; `/plan` chia việc theo AC, không cắt tính năng |
