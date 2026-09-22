# FS-08 — Settings

`FS-08` · tier A · `ShotDex/Features/Settings/` · `Features/Support/` · `App/SettingsSheet.swift`
· test `SettingsLayoutTests` (10) · `SettingsSearchTests` (12) · `SettingsNavigationTests` (10)
· cập nhật 2026-09-22

**Một câu:** màn cài đặt của app — quyền và index, thông báo, hiển thị, widget, riêng tư — một cột ở
compact và bố cục hai cột của hệ thống ở regular.

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 01 | [Bố cục và tìm kiếm](01-layout-and-search.md) | split view vs một cột, sidebar 9 mục, search theo hàng |
| 02 | [Photo Library và index](02-photo-library-and-index.md) | quyền, Continue Indexing, cellular, keep-awake, Low Power |
| 03 | [Các section còn lại](03-other-sections.md) | Notifications · Display · Playback · Sharing · Export · Camera Database · Privacy · Library Size |
| 04 | [Photo Widget designs](04-photo-widget-designs.md) | danh sách design, preview kéo-pinch, thành phần, màu Smart |
| 05 | [Tiêu chí nghiệm thu](05-acceptance-criteria.md) | 19 AC của bố cục + search, và cái nào chưa chứng minh |

## Quy tắc

- **Lối vào**: nút gear (bánh răng) top-left của Library/Collections/Statistics → lớp phủ toàn màn
 + ngăn xếp điều hướng, tiêu đề nhỏ, nút **Done** bên phải. Không phải bottom sheet: Settings có mười
  section cộng trình sửa widget, mà preview widget là thứ phải kéo và pinch — một sheet mà cùng ngón tay
  đó kéo tuột xuống là sai vật chứa.
- **lớp phủ toàn màn phải gắn TRƯỚC lớp phủ chế độ chọn và hoạt ảnh của màn gốc**
  (cả hai nhánh iOS). Gắn sau thì SwiftUI **crash SIGBUS** ngay lúc present, trong vòng lặp
  vòng lặp đo đạc của giao diện.
- **Danh sách nhóm chỉ có một nguồn**: một danh sách mục duy nhất; cả hai bố cục dựng từ danh sách đầy đủ
  ([NF-05](../../04-non-functional-design/NF-05-device-and-os-compatibility.md) — "điện thoại có đủ mọi
  chức năng của iPad").
- **Hành động phá huỷ nằm cuối section** và dùng hộp thoại có nút Huỷ
  ([BD-04](../../01-basic-design/BD-04-design-language.md)).
- Lưu bằng `UserDefaults` / cài đặt lưu sẵn, key khai trong một chỗ khai khoá duy nhất.

## 12 section (bố cục compact, đúng thứ tự)

Photo Library · Notifications · Display · Widgets · People and Pets · Sharing · Export ·
Camera Database · Support · Privacy · Playback · Library Size.

**Appearance đã bỏ** — dãy swatch accent không còn trong code và không dựng lại
([BD-04 §3](../../01-basic-design/BD-04-design-language.md)).

## Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| bố cục hai cột của hệ thống là cấu trúc điều hướng duy nhất kiểu này trong app | giới hạn ở Settings; chạy tốt mới bàn tới màn khác |
| lớp phủ toàn màn chứa split view có thể đụng lại SIGBUS `HostPreferencesTransform` | giữ nguyên thứ tự modifier ở màn gốc; AC-3/AC-12 mở và đóng ở cả hai nhánh iOS |
| Duo trong chỉ cao 669pt — sidebar 9 mục có thể phải cuộn ở cỡ chữ lớn | cuộn được là chấp nhận ở cỡ accessibility, **không** chấp nhận ở cỡ mặc định (AC-6, AC-13) |
| Split View 1/2 trên iPad 13" (688pt) vào split, detail còn ~368pt | đúng điều Settings hệ thống làm; sàn 320pt vẫn giữ |
| Gom section ở sidebar làm người quen bố cục cũ mất dấu một hàng | bố cục compact không đổi; Search là đường tắt |
| chỉ mục tìm kiếm của Settings là bản sao thứ hai của nhãn hàng | index và hàng dùng chung hằng chuỗi; AC-17 đối chiếu số lượng |
