# FS-08.01 — Bố cục theo bề rộng và tìm kiếm

`FS-08.01` · `Features/Settings/SettingsLayout.swift` · `SettingsSearchIndex`
· test `SettingsLayoutTests` · `SettingsSearchTests` · cập nhật 2026-09-22

**Một câu:** một cột ở màn hẹp, hai cột ở màn rộng, và một ô tìm kiếm chạy **theo từng hàng** ở cả hai.

## 1. Quy tắc

- **Ngưỡng là bề rộng hệ thống báo, không phải một con số pt.** Phép quyết định là một **hàm thuần có test**,
  không phải một câu `if` nằm trong phần vẽ.
- Bề rộng chưa xác định thì **rơi về một cột**, không đoán.
- Hai bố cục dựng từ **cùng một danh sách mục**.
- **Bố cục hẹp không đổi một dòng nào** so với trước khi có hai cột.

## 2. Hai bố cục

| | Hẹp | Rộng |
|---|---|---|
| Vật chứa | một danh sách nhóm | **hai cột** — mục bên trái, nội dung bên phải |
| Màn con | chồng lên nhau | mở **trong cột nội dung** |
| Thiết bị | mọi iPhone, màn ngoài Duo, iPad ở chế độ cửa sổ nhỏ | iPad từ 834pt dọc trở lên, iPad chia đôi màn, **màn trong Duo 951×669** |

**Vì sao không dùng mốc 900pt** (ý định ban đầu chốt con số này): 900pt sẽ để iPad 11" dọc ở lại bố cục điện
thoại, trong khi Settings của chính iPadOS ở đúng bề rộng đó đang chạy hai cột. Đổi lại, iPad chia đôi màn
(688pt) cũng vào hai cột — cũng đúng điều hệ thống làm.

## 3. Cột mục — 9 mục

| # | Mục | Gom mục nào của bố cục hẹp |
|---|---|---|
| 1 | Photo Library | Photo Library + Library Size + Privacy |
| 2 | Notifications | Notifications |
| 3 | Widgets | Widgets |
| 4 | Display | Thumbnail Metadata |
| 5 | Playback | Playback |
| 6 | People and Pets | Subject Scan |
| 7 | Sharing and Export | Sharing + Export |
| 8 | Camera Database | Camera Database |
| 9 | Support | Support |

- **Chỉ cột mục mới có biểu tượng**; bố cục hẹp vẫn là các nhóm có tiêu đề chữ. Biểu tượng vẽ theo kiểu phân
  tầng, màu accent, **không** có nền bo tròn kiểu Settings hệ thống — app không có bộ icon màu riêng cho
  từng mục, và một dãy chín ô xám sẽ ồn hơn là giúp.
- Library Size và Privacy **không** là mục riêng: cái đầu là hai hàng số đọc xong là thôi, cái sau là một
  đoạn giải thích cộng một nút phá huỷ — cả hai nằm cuối **Photo Library**.
- Chín mục gom lại để **vừa một màn 669pt** (màn trong Duo) mà không phải cuộn.

## 4. Số đo

| Mục | Giá trị |
|---|---|
| Bề rộng cột mục | **320** (dải cho phép 280…360) |
| Đo thật iPad 11" dọc, iOS 18.6 | đúng **320pt** |
| Đo thật iPad 13" ngang, iOS 26.5 | **350pt** — ở iOS 26 cột đó là một tấm kính nổi thụt vào khỏi mép |
| Bề rộng nội dung | tối đa **840**, căn giữa |
| Cột nội dung hẹp nhất còn vào hai cột | 368pt (iPad chia đôi màn 13") — vẫn trên sàn 320pt |

**Danh sách nhóm của hệ thống KHÔNG tự chừa lề trong một cột rộng** — đo trên iPad 13" ngang: hàng rộng
1006pt và nhãn "Access" đứng cách giá trị "Full Access" khoảng 900pt. Phải tự giới hạn bề rộng nội dung và
trả nền xám lại cho cả cột; đo lại còn 800pt.

Bề rộng cột mục **đặt tên trong bảng token**, không gõ số rời trong màn — `DESIGN.md` cấm hằng số rời, và
tài liệu đó cũng ghi luật "màn cài đặt ở bề rộng lớn dùng hai cột".

## 5. Tìm kiếm

Có ở **cả hai bố cục** — trên cột mục khi rộng, trên danh sách khi hẹp.

- **Tìm theo hàng, không theo mục.** Chín cái tên mục thì lọc chín cái tên là vô dụng: người ta gõ "ISO",
  "cellular", "HDR" — tên của **một hàng** nằm sâu bên trong. Nguồn đối chiếu là một **chỉ mục khai riêng**:
  mỗi mục liệt kê nhãn các hàng nó chứa, khai ngay cạnh danh sách mục.
- **Bỏ dấu, bỏ hoa thường** — "hdr" khớp "View Full HDR".
- Kết quả là **danh sách hàng**: nhãn hàng + tên mục ở dòng phụ. Chạm một kết quả thì mở mục đó, **cuộn tới
  hàng**, rồi **nháy nền hàng 1,2 giây** để mắt bắt được nó trong một màn dài.
- Không khớp gì thì hiện **màn rỗng chuẩn của hệ thống**, không phải một danh sách trống.
- Tìm kiếm **không nhớ** câu đã gõ giữa hai lần mở Settings.
- **Giá phải trả**: chỉ mục là **bản sao thứ hai** của nhãn hàng — đổi chữ ở một hàng mà quên sửa chỉ mục
  thì tìm không ra. Giảm rủi ro bằng cách để hàng và chỉ mục **dùng chung một hằng chuỗi**, và có một tiêu
  chí nghiệm thu đối chiếu số lượng.

## 6. Hành vi

- **Mục mặc định khi mở**: Photo Library. **Không nhớ** mục đã chọn — không thêm một khoá cài đặt cho một
  trạng thái điều hướng.
- **Done** nằm ở thanh trên của **cột mục**, đóng toàn bộ Settings từ bất kỳ mục nào — màn này không vuốt để
  đóng được nên Done là lối ra duy nhất.
- Mỗi cột nội dung là **một ngăn xếp riêng**: Back quay về màn trước **của chính mục đó**, không nhảy về cột
  mục.
- Màn sửa widget **lấy trọn cột nội dung** và giữ nguyên cấu trúc cùng luật cử chỉ của nó
  ([04](04-photo-widget-designs.md)).
- **Đổi bề rộng lúc đang mở** (xoay máy, đổi cỡ cửa sổ, gập/mở Duo): bố cục đổi ngay và **mục đang xem được
  giữ** — rơi về hẹp thì nó là màn đang mở, lên rộng thì nó là mục đang chọn.

## 7. Tiêu chí nghiệm thu

Xem [05](05-acceptance-criteria.md).
