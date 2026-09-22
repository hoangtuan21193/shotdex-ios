# FS-03.09b — Sửa nhiều ảnh và Reference View

`FS-03.09b` · `Features/Editing/EditorSession.swift` · `EditorFilmstrip` · `EditorReferencePane`
· cập nhật 2026-09-22

**Một câu:** một phiên sửa nhiều ảnh giữ **bản nháp theo từng ảnh**, không giữ pixel — và trên màn rộng có
một khung mẫu ghim cạnh ảnh đang sửa.

Bố cục màn rộng: [FS-03.09](09-wide-screen-and-batch-editing.md).

## 1. Quy tắc

- Phiên giữ **danh sách ảnh + recipe nháp theo id**, **không giữ ảnh đã decode**: editor vẫn mỗi lần một
  ảnh, nhân lên 20 ảnh là 20 bản gốc mở cùng lúc.
- Sync chỉ ghi vào **nháp** — không đụng đĩa, không ghi đè ảnh nguồn.
- **Lưu trong phiên nhiều ảnh KHÔNG đóng editor.**
- Lưu cả mẻ chạy **không dựng giao diện**: một ảnh lỗi không dừng mẻ.
- Pane tham chiếu là thứ **để nhìn**, không phải thứ đang sửa.

## 2. Vào và chuyển ảnh

- Lối vào: chế độ chọn → ⋯ → **Edit**, có ở Library, Album, Smart Album, On This Day. Video bị loại vì
  editor ảnh không mở được.
- Đổi ảnh: chốt crop → lưu nháp → đóng ảnh cũ → mở ảnh mới → **áp nháp đè lên recipe đọc từ ảnh** (nháp
  mới hơn).
- **Filmstrip** dưới canvas ở cả hai layout (124pt/thumbnail 96 trên điện thoại; **72/56** ở màn rộng —
  panel đã tiêu bề rộng, dải không nên tiêu thêm một phần mười chiều cao). Ẩn khi xem tràn viền và khi
  đang vẽ.
- Badge trên thumbnail: viền accent = đang sửa · biểu tượng slider = **có nháp chưa lưu** · dấu tick = đã lưu.
- Thumbnail tải theo thang **local → iCloud**, có placeholder và spinner. Máy bật Optimize Storage (đa số
  thư viện đầy) thì request local-only trả rỗng cho phần lớn khung, và dải ảnh trước đây là một hàng ô xám
  không phân biệt được đang tải hay hỏng.

## 3. Sync

⋯ → **Sync to N Photos**, hai mức:

| Mức | Chép gì |
|---|---|
| **Sync Look** | tone · màu · curve · film look — đúng lát cắt của Copy Edits |
| **Sync Everything** | thêm crop, mask, markup |

Bản đầu bê nguyên recipe, tức dán crop 4:5 và mask khuôn mặt của một tấm chân dung lên 39 tấm phong cảnh —
đúng thứ Copy Edits cố tình từ chối ([FS-03.10](10-copy-paste-edits.md)).

- **Auto Sync**: bật thì mọi thay đổi đã chốt tự rải sang phần còn lại theo mức đang chọn. Hiện dưới dạng
  **toggle sáng trong menu ⋯, không phải chế độ ẩn** — Lightroom giấu nó sau ⌥-click và người dùng bỏng
  tay suốt mười lăm năm; iPad thì không có ⌥-click để lộ ra.
- **Apply Previous**: nhớ ảnh vừa rời, áp recipe của nó lên ảnh hiện tại theo mức đang dùng.
- **Paste Edits thẳng từ lưới**: chọn ảnh → ⋯ → Paste Edits, dán look đang có trong clipboard lên cả loạt
  bằng cùng vòng lặp không giao diện, **không mở editor**. Chỉ hiện khi clipboard có nội dung.

## 4. Lưu

- Lưu một ảnh xong thì **nhảy sang ảnh kế còn nháp** (quét xuôi rồi vòng lại), chỉ đóng khi hết. Bản đầu
  đóng ngay sau mỗi lần lưu nên sync 20 ảnh chỉ lưu được 1, và badge "đã lưu" là code không bao giờ chạy tới.
- **Save All**: sheet lưu có thêm `Save Changes to N Photos` / `Save N Copies` khi phiên có từ 2 ảnh mang
  nháp. Vòng lặp chạy **không dựng editor** — editor tồn tại để nuôi preview tương tác, 40 cái trong một
  vòng lặp là vẽ ảnh không ai nhìn.
- Một ảnh lỗi thì **gom lại, báo cuối**, và ảnh đó **giữ nháp** để thử lại.
- Token `{camera}` trong markup giãn **theo từng ảnh**, không phải một lần cho cả mẻ.
- Tiến trình là **modal giữa màn có scrim**.

## 5. Reference View

Chỉ ở layout rộng. Giữ một thumbnail trong filmstrip → **Use as Reference** → khung đó ghim cạnh canvas,
ảnh đang sửa ở phần còn lại.

**Đây là lý do màn to tồn tại**: việc thật của một phiên sửa nhiều ảnh là kéo 40 khung về giống một khung
mẫu, mà "làm giống tấm kia" thì không thể làm khi chỉ thấy một tấm.

- Cũng có hàng **Use as Reference / Clear Reference** trong menu ⋯ khi phiên nhiều ảnh — không chỉ trong
  menu ngữ cảnh trên thumbnail 56pt. Ghim bị **xoá khi cửa sổ hẹp lại**, nếu không badge sẽ còn lại mà
  không gì xoá được.
- **Hướng chia canvas do hình học quyết định, không cố định** (thuần, 7 test): so diện tích ảnh thật sự
  phủ được khi chia dọc và khi chia ngang, chọn cái lớn hơn.
  - Ảnh ngang trong canvas cao thì **xếp chồng** — chia dọc là cắt đúng chiều mà ảnh đang cần.
  - Ảnh dọc trong canvas rộng thì **cạnh nhau**. Hoà thì ưu tiên cạnh nhau (mắt đi theo một đường ngang dễ
    hơn cắt ngang).
  - Đo trên iPad dọc: chuyển từ cạnh-nhau sang xếp-chồng làm ảnh rộng gấp đôi (215pt → 425pt). Ảnh 3:2 giữ
    ưu thế xếp chồng lâu hơn trực giác — canvas 1300×900 vẫn nên chồng, phải tới cỡ 1800×700 cạnh nhau mới
    thắng.
- Pane tham chiếu hiển thị ảnh **như nó đang nằm trong thư viện** (kèm edit đã lưu), **không render lại
  qua một editor thứ hai** — nhân đôi bộ nhớ editor cho một tấm không ai động vào.
- Nhãn "Reference" **nổi lên trên** ảnh chứ không chiếm một hàng: xếp thành hàng thì ảnh mẫu tụt thấp hơn
  ảnh đang sửa 44pt, đúng thứ phá hỏng việc so sánh.
- **Khoá zoom/pan giữa hai pane** (mặc định bật, nút link trong header pane): hai pane bằng kích thước và
  ảnh đều fit trong đó, nên cùng mức phóng + cùng offset rơi đúng cùng vùng của mỗi ảnh. Pane tham chiếu
  **không tự pan được** — kéo nó rời khỏi ảnh đang sửa thì mất nghĩa so sánh.

## 6. Chưa có

- **Undo theo từng ảnh** — lịch sử nằm trên editor nên đổi ảnh là mất.
- Flag / rating.

## 7. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
