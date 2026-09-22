# FS-01.02 — Nav bar và thanh điều kiện

`FS-01.02` · `Features/Library/LibraryScreen.swift` · `FilterTokenBar` · `AdvancedSearchBar`
· cập nhật 2026-09-22

**Một câu:** chrome của Library là kính nổi trên ảnh — không dải nền, không tiêu đề — và lưới phải được trả
lại đúng số pt mà chrome che.

## 1. Quy tắc

- Nav bar **mỏng, trong suốt, không tiêu đề**; ảnh chạy sát mép và trôi dưới chrome.
- **Thanh điều kiện không có nền** — từng chip tự mang viên kính của nó.
- Ô tìm kiếm **không** nằm trong nav bar; nó là nút tròn ở thanh chrome nổi phía dưới.
- Chrome ghim vào vùng an toàn phía trên, **không** đặt trong một cột dọc — lưới phải là vùng cuộn gốc.

## 2. Nav bar

| Vị trí | Control |
|---|---|
| Trái | nút gear mở Settings; token index ([BD-03.04](../../01-basic-design/BD-03-metadata-indexing-flow/04-progress-and-background.md)) |
| Giữa | ngày của ảnh đang ở mép trên vùng nhìn, đổi số bằng hiệu ứng đếm |
| Phải | Filter · **Select** |

- **Không còn nút Filter nhanh kiểu cũ** — Advanced Search đảm nhận lọc ad-hoc. Bộ lọc đơn giản vẫn tồn tại
  cho đường drill-down từ Statistics và cho chip đang bật.
- **Import không còn ở toolbar** — nó nằm trong Settings ([FS-10](../FS-10-import.md)).

## 3. Thanh điều kiện

- Chip điều kiện và cụm `Edit`/`Clear` tự mang viên kính như nút Select. Bản cũ tô nền đục, ra một dải mép
  cứng cắt ngang ảnh, cộng một đường nối thứ hai với nav bar trong suốt phía trên.
- **Chip `Match all` là nút, không phải nhãn chết**: chạm đổi giữa "khớp tất cả" và "khớp bất kỳ" rồi chạy
  lại truy vấn ngay. Vẽ **nhạt hơn** chip điều kiện — nó là *thiết lập về* các điều kiện, không phải một
  điều kiện.
- **Mép phải dải chip mờ dần** (28pt): dải cuộn ngang không có thanh cuộn, nên chip bị cắt thẳng cạnh cụm
  Edit/Clear đọc ra như **bị nút che**. Nội dung chừa sẵn 28pt đuôi; chip vừa đủ chỗ thì không thấy gì.

## 4. Trả lại chỗ cho hàng ảnh đầu

Lưới cố ý tràn qua vùng an toàn dọc để ảnh trôi dưới nav bar trong suốt — nên nó **không tự biết** thanh
điều kiện đang che bao nhiêu, và hàng ảnh đầu bị che.

Khối banner + chip **tự đo chiều cao thật** rồi đưa con số đó cho lưới: lúc đứng yên hàng đầu nằm trọn dưới
chip, cuộn lên thì ảnh mới chui xuống dưới. Đổi con số lúc lưới đang ở đỉnh thì **kéo chỗ cuộn theo**, nếu
không hàng đầu lại chui xuống dưới thanh vừa xuất hiện.

## 5. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
