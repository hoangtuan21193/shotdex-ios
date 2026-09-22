# EX-05 — Action Extension "Edit in ShotDex"

`EX-05` · `ShotDexEditAction/` (chưa dựng) · deep link `shotdex://` · cập nhật 2026-09-22

**Một câu:** một dòng **Edit in ShotDex** trong share sheet, bấm là mở app tại đúng tấm ảnh đó, trong editor.

Thay cho extension sửa ảnh tại chỗ đã bỏ — xem [EX-01 §3](EX-01-shotdexkit-and-edit-extension.md).

## 1. Quy tắc

- Extension **không sửa ảnh**. Nó chỉ nhận ảnh, tìm ra `assetId` nếu tìm được, rồi mở app. Mọi việc render
  nằm trong app, nơi không có trần bộ nhớ của tiến trình extension.
- **Một target riêng** (`com.apple.ui-services`), tách khỏi `ShotDexShare` ("Save to ShotDex") — hai việc
  khác nhau thì hai dòng khác nhau trong share sheet, không nhét một dòng bấm vào mới biết có hai nút.
- Deep link dùng **cùng một tuyến** widget đang dùng (`shotdex://`, `WidgetDeepLink`), không đẻ tuyến thứ hai.

## 2. Đường đi

1. Người dùng ở Photos (hoặc app bất kỳ) → Share → **Edit in ShotDex**.
2. Extension đọc item provider, lấy file ảnh và `PHAssetResource` của nó.
3. **Dò ngược ra asset trong thư viện** bằng tên file gốc + ngày chụp + kích thước pixel.
4. Mở `shotdex://photo?id=<assetId>&edit=1` — app vào thẳng editor của ảnh đó.
5. Dò không ra thì vẫn mở editor trên ảnh vừa nhận, nhưng **chỉ có Save Copy** (xem §3).

## 3. Khi không dò ra ảnh gốc

**Chỉ hiện Save Copy.** Không hiện Save Changes, và **không hiện dòng giải thích nào** — một câu về
"không tìm thấy ảnh gốc trong thư viện" là thứ người dùng không làm gì được với nó. Lưu xong là một ảnh mới
trong thư viện, đúng như mọi lần Save Copy khác.

## 4. Cái mất so với extension sửa tại chỗ

Extension cũ nhận **định danh thật** từ Photos nên ghi đè không phá huỷ luôn đúng. Đường share là **dò**,
nên có trường hợp trượt (ảnh trùng tên, ảnh vừa sửa). Đổi lại: không còn trần bộ nhớ ~120MB, không còn luật
từ chối ảnh có mask/markup, và editor người dùng gặp là editor thật chứ không phải bốn slider.

## 5. Tiêu chí nghiệm thu

**Chưa viết** — cần một `/spec` riêng khi bắt tay dựng target.
