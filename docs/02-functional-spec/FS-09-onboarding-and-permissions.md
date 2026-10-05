# FS-09 — Onboarding và quyền

`FS-09` · tier A · `ShotDex/Features/Onboarding/` · `Data/Sources/PhotoLibraryService.swift`
· cập nhật 2026-10-02

**Một câu:** bốn câu giới thiệu trước khi hỏi quyền, một dòng báo trước hộp quyền, và mọi trạng thái quyền
đều có lối đi tiếp.

## 1. Quy tắc

- **Không xin quyền ngay khi mở app** — onboarding ngắn trước prompt; hộp quyền chỉ mở khi chạm Continue.
- Xin quyền đọc-ghi (cần cho toggle favorite), không phải chỉ-đọc.
- **Báo trước hộp quyền** (F1): người dùng biết iOS sắp hỏi gì và nên chọn gì *trước* khi hộp hiện ra.
  *Vì chọn Limited theo thói quen làm Search, Statistics, Duplicates trả thiếu mà chỉ Library báo.*
- **Không màn nào được chết ở trạng thái quyền**: mỗi trạng thái có câu giải thích và một nút.
- App **không bao giờ tự hỏi** quyền lịch/vị trí ([EX-02](../03-extensions-and-integrations/EX-02-widget.md)).

## 2. Màn onboarding

Bốn câu, theo thứ tự:

1. Find photos by camera and lens
2. Explore your most-used gear
3. Compare focal lengths across sensor sizes
4. Your photos stay on your device

- Bốn câu cuộn được; dòng báo trước và nút **Continue** ghim ở đáy, luôn thấy.
- **Dòng báo trước** nằm ngay trên Continue, cỡ footnote, màu chữ phụ, căn giữa:
  "Next, iOS asks for access — choose Allow Full Access so ShotDex can read every photo's camera info."
  - Xuống dòng ở mọi cỡ chữ, không bao giờ cắt "…". Cách Continue ≤ 16pt.
- **Continue**: compact width rộng bằng cột nội dung trừ lề 28pt mỗi bên (346pt ở 402); regular width **tối
  đa 480pt**, căn giữa (đang 1320pt ở iPad 13"). Dòng báo trước cùng bề rộng tối đa với nút.
- Duo ngoài: nút và dòng báo trước nằm trong vùng an toàn, không lấn dải hệ thống 84pt bên phải.
- Duo trong 951×669: dòng báo trước + Continue thấy trọn khi chưa cuộn; bốn câu cuộn nếu thiếu chỗ.

Board: `PH_Onboarding` · `IP_Onboarding` · `DI_Onboarding` · `DC_Onboarding` (thêm dòng báo trước, Continue 480pt ở IP/DI).

## 3. Trạng thái quyền

| Trạng thái | Màn hiện gì |
|---|---|
| Not Determined | onboarding, rồi mới xin quyền **đọc và ghi** thư viện ảnh |
| Authorized | full access, vào thẳng Library |
| **Limited** | Library và Statistics: banner **Limited Access** — "ShotDex only analyzes the photos you selected." + **Manage** mở bộ chọn ảnh của hệ thống |
| Denied | Library và Statistics: "No Access to Photos", giải thích vì sao cần quyền, nút **Open Settings** |
| Restricted | Library và Statistics: "Photos Access Restricted", không nút |

- Quyền đổi trong Settings lúc app ở nền → về foreground là màn đổi theo, không cần mở lại app.
- Denied / Restricted ẩn cả dữ liệu đã index từ trước: Statistics không vẽ số của ảnh app không còn đọc được.
- Chi tiết từng màn ở mỗi thiết bị, và ca chờ iCloud: [NF-04 §3](../04-non-functional-design/NF-04-empty-and-error-states.md);
  Statistics: [FS-07.01b §5](FS-07-statistics/01b-cards-editor-and-states.md).

`Info.plist`: chuỗi giải thích vì sao app cần thư viện ảnh.

## 4. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | (F1) cài mới, quyền Not Determined, iPhone 402×874, iOS 26.5 và 18.6 | mở app | onboarding hiện; chưa có hộp quyền; dòng "Next, iOS asks for access — choose Allow Full Access so ShotDex can read every photo's camera info." ngay trên Continue, cách ≤ 16pt; Continue rộng 346pt ±1 | ⚠️ chưa có (đề xuất `onboarding-layout.json`, dump `staticText` + `button`) |
| AC-2 | (F1) như AC-1, iPad 13" ngang 1376×1032 và 11" dọc | mở app | Continue rộng 480pt ±1, tâm trùng tâm màn ±1; dòng báo trước rộng ≤ 480pt | ⚠️ chưa có (đề xuất `onboarding-layout-ipad.json`) |
| AC-3 | (F1) như AC-1, Duo trong 951×669 | mở app | Continue rộng 480pt; dòng báo trước và Continue thấy trọn khi chưa cuộn, đáy Continue trên mép vùng an toàn dưới | ⚠️ chưa có — sim Duo khởi động gập, phải mở tay |
| AC-4 | (F1) như AC-1, Duo ngoài 466×678 | mở app | mép phải Continue và dòng báo trước ≤ 466 − 84 − 28 = 354pt | ⚠️ chưa có |
| AC-5 | (F1) như AC-1, cỡ chữ AX5 | mở app | dòng báo trước đủ chữ, không "…"; bốn câu cuộn được; Continue vẫn thấy | ⚠️ chưa có |
| AC-6 | (F1) màn của AC-1 | chạm Continue | hộp quyền ảnh của hệ thống hiện, có lựa chọn "Allow Full Access" | ⚠️ chưa có — hộp hệ thống chỉ chụp được, ui-drive không đọc được |
| AC-7 | (F3) quyền Denied | mở tab Library | "No Access to Photos" + Open Settings; không lưới | ⚠️ chưa có (đề xuất `permission-denied.json` sau `xcrun simctl privacy revoke photos`) |
| AC-8 | (F3) màn của AC-7 | chạm Open Settings | app Settings mở trang của ShotDex | ⚠️ chưa có |
| AC-9 | (F3) quyền Limited, 312 ảnh được cấp | mở tab Library | banner Limited Access + Manage trên lưới; lưới ghi "312 Photos" | ⚠️ chưa có — sim không cấp được Limited bằng lệnh; cần máy thật |
| AC-10 | (F3) màn của AC-9 | chạm Manage | bộ chọn ảnh của hệ thống mở | ⚠️ chưa có — cần máy thật |
| AC-11 | (F3) quyền Restricted | mở tab Library rồi tab Statistics | cả hai: "Photos Access Restricted", không nút nào | ⚠️ chưa có — sim không đặt được Restricted |
| AC-12 | (F3) quyền đầy đủ, 5.000 ảnh đã index, app ở nền; đổi quyền Photos sang None trong Settings | đưa app về foreground | Library và Statistics cùng hiện "No Access to Photos" mà không mở lại app | ⚠️ chưa có |
| AC-13 | (F3) Denied, Limited, chờ iCloud × iPhone, iPad, Duo trong, Duo ngoài | `Tools/design-board compare` trên dump Library của từng ca | 12 board Library có trên canvas; không phần tử nào thiếu, thừa hay lệch > 2pt | ⚠️ chưa có — board chưa vẽ |

AC phía Statistics của cùng các trạng thái: [FS-07.03](FS-07-statistics/03-acceptance-criteria.md) AC-50…58.
