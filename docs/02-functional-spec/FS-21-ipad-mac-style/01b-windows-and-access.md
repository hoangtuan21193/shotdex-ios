# FS-21.01b — Bề rộng cửa sổ, dọc, iOS trước 26, truy cập

`FS-21.01b` · phần tiếp của [01](01-shell.md) · gốc app · cập nhật 2026-10-04

**Một câu:** khi nào iPad dùng khung sidebar, khi nào rơi về bố cục iPhone, màn dọc thu gì lại, nhánh trước iOS 26
trông ra sao, và luật truy cập cho các control mới.

## 1. Bề rộng cửa sổ

Bố cục chọn theo **bề rộng cửa sổ, ba mốc cố định** — không theo size class, không theo hướng xoay:

| Bề rộng | Bố cục | Sidebar | Inspector |
|---|---|---|---|
| < 700 | bố cục iPhone (tab bar, nav bar, sheet) | không có | sheet như iPhone |
| 700 – 1099 | khung FS-21 | **phủ** (ẩn sẵn, Show Sidebar mở) | sheet dưới có Done |
| ≥ 1100 | khung FS-21 | **ghim** (hiện sẵn, Hide Sidebar ẩn) | cột 360 |

| Cửa sổ | Ra |
|---|---|
| iPad 13" ngang 1376 · iPad 11" ngang 1210 | ghim |
| iPad 13" dọc 1032 · iPad 11" dọc 834 | phủ |
| Split View 1/2 iPad 13" 688 · Split View 1/3 · Slide Over | bố cục iPhone |
| Stage Manager | theo bề rộng hiện tại, đổi ngay khi kéo qua mốc |

- *Vì* sidebar ghim 320 + inspector 360 + nội dung đủ dùng cần ~1100pt; dưới 700 sidebar phủ che gần hết nội dung.
- Đổi bố cục giữ trạng thái: hàng sidebar ↔ tab tương ứng, chỗ cuộn, lựa chọn, ảnh đang xem ([FS-01.07](../FS-01-library/07-state-restoration.md)).
- Editor là ngoại lệ đã có: dọc vẫn giữ cột inspector ([02 §5](02-screens.md)); công cụ tầng D dọc cũng vậy ([02b §2](02b-screens.md)).

**Số cột lưới** theo **mật độ đã lưu** như DESIGN §10.1c, pinch đổi mật độ như iPhone; không cố định theo bố cục.
Board vẽ **mật độ mặc định**: 7 cột ở 1016pt (ô 143), 6 cột khi mở inspector ở 656pt (ô 107). Mở/đóng inspector
không đổi mật độ — chỉ chuyển giữa cặp số cột của mật độ đó (mặc định 7 ↔ 6).

## 2. Dọc và cửa sổ 700–1099

- Sidebar ẩn; Show Sidebar trên toolbar mở nó **phủ** lên nội dung (320, nền mờ sau, chạm ngoài để đóng).
- Inspector thành **sheet dưới** có Done (board `IPP16_InfoKeywords`: cao 576, đáy màn), trừ Editor và công cụ tầng D giữ cột.
- Không mất lệnh nào: cụm toolbar có thể gom bớt vào ⋯ nhưng mọi lệnh còn đó.
- Nút toolbar dọc **44×44**, như ngang — board `IPP*` sửa từ 36 về 44.
- **Tiến độ index khi sidebar ẩn** (mọi bề rộng, kể cả ngang sau Hide Sidebar): đang index thì dòng phụ toolbar thay
  dòng đếm bằng tiến độ của BD-03.04; xong thì về dòng đếm. Sidebar hiện thì tiến độ chỉ ở chân sidebar.

## 3. iOS 26 và trước 26

- iOS 26: sidebar và toolbar là của hệ thống; iPadOS 26 tự vẽ sidebar kính nổi và gom nút toolbar thành viên kính,
  nên app không thêm lối vào kính mới (DESIGN §2 tầng C).
- **Trước 26 (iPadOS 17/18): sidebar và toolbar hệ thống của bản đó** — sidebar đục cao hết cửa sổ sát mép trái, nav
  bar thường, không viên kính. Cùng hình học: sidebar 320, hàng 44, nút 44. App **không** tự vẽ panel mờ giả kính
  (DESIGN §1.5: một hệ thống chất liệu).
- Hai nhánh có **cùng tập lệnh, cùng chỗ** ([NF-05](../../04-non-functional-design/NF-05-device-and-os-compatibility.md) luật 6).

## 4. Truy cập

- Hàng sidebar đọc "tên, số đếm", hàng đang chọn có trạng thái "đã chọn"; Albums đọc "thu gọn/mở rộng"; nguồn đọc
  thêm loại và trạng thái ("offline"). Eject, `+` là phần tử riêng có nhãn.
- Vùng chạm ≥ 44×44 ở mọi nút, kể cả khi board vẽ nhỏ hơn (Add Source 44×32, Show Albums 28, Remove Keyword 28).
- Cỡ chữ accessibility: hàng sidebar và inspector cao theo chữ (không chiều cao cứng), nhãn xuống dòng, không cắt;
  sidebar giữ 320. Nút toolbar giữ cỡ, giữ lâu hiện bảng phóng to của hệ thống.

## 5. Phone có mọi chức năng iPad

- Mọi lệnh của sidebar, toolbar, inspector, menu bar phải có đường trên iPhone (tab, ⋯, menu nhấn giữ, sheet).
  Phím tắt và kéo bằng con trỏ là đường tắt, không phải chức năng.
- Lệnh board iPad có mà iPhone chưa có — **thêm cho iPhone qua menu ⋯** (chỗ cụ thể: [03 §4](03-spec-deltas.md)):

| Lệnh | Chỗ trên iPhone |
|---|---|
| Chế độ List (bảng cột sắp được) | ⋯ của Library: Grid / List |
| Go to Date… | ⋯ của Library |
| Print… | ⋯ của Viewer và ⋯ của lựa chọn |
| Rotate Counterclockwise / Clockwise | ⋯ của Viewer |
| Keep All N Photos | ⋯ của nhóm ở Duplicates |
| Đổi kiểu biểu đồ (donut/cột, cột/đường) | ⋯ của thẻ Statistics |

- View › Show Filter Bar là đường tắt menu bar cho thanh điều kiện mà iPhone đã có (FS-01.02 §3) — không phải lệnh mới.
- **Ngoại lệ nền tảng** (ghi vào NF-05 luật 1): Open in New Window / New Window và cửa sổ Activity — iPhone chỉ có một
  cửa sổ. Tiến độ trong Activity vẫn thấy trên iPhone ở chỗ của BD-03.04 và màn nhập.
- Nguồn thư mục, ổ ngoài, server-là-nguồn và nhập thẻ có ở cả iPhone và Duo (FS-19, FS-20) — không là ngoại lệ.
