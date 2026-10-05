# FS-01.08 — Compare

`FS-01.08` · `Features/Library/CompareScreen.swift` · `Domain/Grid/CompareLayout.swift`
· test `CompareLayoutTests` · cập nhật 2026-10-02

**Một câu:** xem nhiều ảnh cạnh nhau ở **cùng một mức phóng**, và chạm để đánh dấu tấm sẽ xoá.

## 1. Quy tắc

- **Chạm ảnh = đánh dấu xoá, và đó là việc duy nhất một cú chạm ở đây làm.** Không có "chọn" trung tính —
  đứng trước 8 khung với một hàng vòng tròn rỗng thì câu hỏi đầu tiên là *"tôi đang tick cái được giữ hay
  cái bị xoá"*, và không cách xếp nút nào trả lời câu đó tốt bằng việc **không có câu đó**.
- Cùng cử chỉ, cùng màu đỏ, cùng biểu tượng thùng rác với lưới Duplicates — màn này thường mở ra từ đó.
- **Phóng và kéo luôn đồng bộ giữa mọi khung**, không có công tắc: nó là cách nhìn của cả phép so sánh.
- Khung **cao theo đúng tỉ lệ ảnh** — cắt theo một chiều cao chung tức là so sánh hai bản crop khác nhau.
- Chỉ cần ảnh tồn tại trong thư viện, **không cần có row metadata** — đòi metadata thì chọn video sẽ ra danh
  sách rỗng và màn hình đen.

## 2. Lối vào

- Chế độ chọn khi có **≥ 2 mục** (ảnh hoặc video), **không giới hạn trên**; thứ tự khung = thứ tự chọn.
- Từ Duplicates: dấu ghi thẳng về màn đó và nút đỏ gọi ngược lại nó
  ([FS-06.06](../FS-06-collections/06-duplicates.md)).
- Từ Duplicates, **mỗi nhóm luôn còn ít nhất một khung không bị đánh dấu** (D2): chạm khung chưa đánh dấu cuối
  cùng thì khung không đổi, máy rung cảnh báo và hiện *"Keep at least one photo in this group."*
  ([FS-06.06b §1](../FS-06-collections/06b-duplicates-marks-merge-delete.md)).
- Từ chế độ chọn thường: màn tự giữ dấu và tự xoá.

## 3. Bố cục

- **Một cách nhìn duy nhất**, tự co theo màn. Ba chế độ cũ (Survey, và Compare hai khung) **đã gỡ** — một
  cách nhìn tự co còn hơn ba cách người dùng phải chọn trước khi bắt đầu được; việc chúng làm nay do **nhiều
  cột + chạm-để-đánh-dấu** làm.
- **Số cột theo bề ngang** (toán thuần, có test): khung hẹp nhất **330pt**, tối đa **3 cột**, và **không
  bao giờ nhiều cột hơn số ảnh**. Thực tế: iPhone và Duo cover = 1 cột; iPad dọc = 2; iPad ngang = 3.
- **Mỗi cột là một chồng riêng, không phải một lưới**: lưới căn mọi hàng theo khung cao nhất nên dưới mỗi
  khung thấp là một khoảng trống. Khung được chia vào **cột đang ngắn nhất** nên mép dưới các cột xấp xỉ
  bằng nhau, và thứ tự chọn vẫn đọc xuôi.
- **Khung không có nút nào** — dưới ảnh chỉ một dòng `camera · tiêu cự · khẩu · tốc độ · ISO · dung lượng`.
  Nút trên từng khung tốn một dòng chiều cao mỗi khung, trên phone là gần một phần ba khung ảnh người ta mở
  màn này ra để nhìn.

## 4. Đánh dấu và xoá

- **Chưa đánh dấu**: một vòng tròn rỗng ở góc trên-phải — **chính nó là thứ nói khung bấm được**, vì màn
  không còn nút nào khác. **Đã đánh dấu**: biểu tượng thùng rác trắng trên đỏ + viền đỏ 3pt + ảnh mờ.
- Chạm khung ảnh đi qua cử chỉ của UIKit (nhường cho chạm-đôi để phóng) chứ không phải cử chỉ của SwiftUI —
  nội dung nằm trong một scroll view nên cử chỉ SwiftUI không bao giờ bắn. Dòng thông số là vùng chạm thứ
  hai (cho tấm đang phóng mà người dùng đang kéo).
- **Góc trên-phải là một chỗ trả lời "giờ làm gì"**: chưa đánh dấu gì thì là dòng chữ *"Tap a photo to mark
  it for deletion"*; có dấu thì là **một nút đỏ `Delete N Photos`** ngay chỗ đó. Hai thứ không bao giờ cùng lúc.
- **`Keep Only This`** nằm trong menu giữ-lâu của khung, đúng chỗ lưới Duplicates để lệnh cùng tên: đánh dấu
  mọi tấm *khác*, bỏ dấu chính nó.
- **Gợi ý giữ-lâu** (V2, K5): có ít nhất một dấu thì **ngay dưới nút Delete**, cùng góc, có một dòng *"Touch and
  hold to keep only this one"* (chữ caption, trắng 75%, căn phải), cùng kiểu với dòng hướng dẫn đầu; hết dấu thì
  mất cùng nút. Trước dấu đầu tiên chỉ có dòng hướng dẫn đầu.
- **Xác nhận**: đường chọn thường **không tự dựng hộp thoại** — một lệnh xoá cho cả mẻ và hộp thoại của hệ
  thống ("Delete 7 Photos?") *là* bước xác nhận. Đường Duplicates trả về **đúng id của nhóm đang mở**,
  không phải mọi dấu trên màn đó.
- **Xoá xong vẫn ở lại** (V2), cả hai đường: khung đã xoá rời bố cục, khung còn lại xếp lại theo §3. Còn
  **≥ 2 khung** thì màn ở lại, hết dấu nên góc trên-phải về dòng hướng dẫn; còn dưới 2 thì màn đóng.
- **Huỷ** trong hộp thoại hệ thống → không đổi gì: dấu giữ nguyên, không cảnh báo (Q2).
- **Hỏng** (Q2) → cảnh báo **"Couldn't Update Photos"** + lý do + OK, do **chính màn này** trình bày ở cả hai
  đường; mọi khung và dấu giữ nguyên. *Vì cảnh báo của Duplicates nằm dưới lớp phủ toàn màn và không bao
  giờ hiện.*

## 5. Đồng bộ phóng và kéo

- Bộ đồng bộ giữ các khung bằng **tham chiếu yếu** — khung cuộn khuất bị huỷ thì rụng khỏi nhóm thay vì bị
  đồng bộ mãi — và nhớ **trạng thái cuối của cử chỉ** (mức phóng + độ lệch **dạng tỉ lệ** của nội dung).
- Khung dựng sau phát lại trạng thái đó **sau một nhịp**, vì lúc mới dựng nó chưa có kích thước để nhân tỉ
  lệ. Nhờ vậy khung cuộn vào giữa lúc đang phóng hiện ra đã khớp sẵn.
- **Tách theo số ngón**: kéo **một ngón luôn cuộn cột khung**, **hai ngón mới phóng và kéo ảnh** (chỉ bật ở
  màn này; viewer vẫn một ngón). Bản cũ chỉ tắt kéo ở mức 1× rồi bật lại khi phóng — nghĩa là phóng vào để
  soi chi tiết cũng chính là lúc **danh sách hết cuộn được**.

## 6. Video và tải ảnh (V1)

- **Khung video** phát bằng player của hệ thống trong cùng khuôn cuộn như ảnh, nên video **phóng, kéo và
  tham gia đồng bộ** như ảnh. **Không tự phát, tắt tiếng mặc định** (hai video cạnh nhau không chọi tiếng);
  nút play/pause kính nhỏ ở góc dưới-phải; hết clip tự tua về đầu; dừng khi đóng màn.
- **Ảnh kéo ngay lúc mở**: mỗi khung xin song song một bản local nhanh và một bản chất lượng cao cỡ màn
  hình, cho phép mạng — iCloud giao bản cỡ màn hình chứ không phải file gốc. Ở 1× bản đó đủ nét.
- **Phóng vượt 1,5× → bản phân giải cao cho đúng khung đang chạm.** Khung nhận cử chỉ phóng xin một bản có
  cạnh dài = nhỏ hơn của (cạnh dài ảnh, **3000px**). Khung không có bản cao vẫn phóng đồng bộ (§5) trên bản cỡ màn.
  *Vì bản cỡ màn (~1206px trên iPhone) phóng 5× là nội suy: hai tấm gần giống nhau nhoè như nhau.*
- **Không giải mã bản gốc đầy đủ**: bản cao được giải mã thẳng xuống cỡ đích. *Vì 4 khung × ảnh 45MP ≈ 4 ×
  180 MB.* Bản 3000×2000 tốn ~24 MB.
- **Local trước, mạng theo Optimize Storage**: hỏi trước với mạng tắt; bản trên máy không đủ pixel (≥ 90% của
  cỡ đích, [FS-02.06](../FS-02-photo-detail/06-icloud-originals.md) §3) thì hỏi lại cho phép mạng, kể cả mạng di động.
- Đang tải: vòng 22pt **không số** ở góc trên-phải khung đó, như viewer; 0% trọn 15 giây thì thành glyph
  iCloud cam ở cùng chỗ. Mất mạng: khung giữ bản cỡ màn, không vòng quay vô hạn.
- Bản về chỉ thay ảnh đang vẽ khi **nhiều pixel hơn**; không bản nhỏ nào ghi đè bản cao.
- **Nhả bản cao** khi khung thu về 1×, khi khung cuộn khuất và bị huỷ, khi đóng màn, khi hệ thống báo thiếu bộ
  nhớ ([NF-02](../../04-non-functional-design/NF-02-memory-and-resources.md)); khung về bản cỡ màn đã có.
  Yêu cầu đang bay bị huỷ cùng lúc.
- **Giữ tối đa 2 bản cao** (K6), ~48 MB: chạm phóng sang khung B khi A đã có bản cao thì A **giữ** bản của nó,
  để hai tấm được so ở cùng độ nét. Sang khung C thì nhả bản của khung chạm **lâu nhất** trước đó (A), giữ B và C.
- Khung video không áp luật này.

Board: `PH_Compare`, `IP_Compare`, `DI_Compare`, `DC_Compare` — vòng tải ở góc khung, dòng gợi ý giữ-lâu, trạng
thái sau khi xoá một khung.

## 7. Bàn phím (Z5)

- **Esc** đóng Compare, như nút X. Đường Duplicates: dấu đã ghi thẳng về Duplicates nên còn nguyên ở đó; đường
  chọn thường: dấu bỏ đi như khi bấm X. Không có phím mũi tên ở màn này.
- Đang xoá (hộp thoại hệ thống mở) thì Esc thuộc về hộp thoại đó.

## 8. Tiêu chí nghiệm thu

Các luật khác của file chưa có AC — xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | (V1) iPhone 402×874, Compare 2 ảnh 6000×4000 có trên máy | pinch khung 1 lên 5× | ≤ 2 s sau khung 1 vẽ bản cạnh dài 3000px; khung 2 phóng đồng bộ 5× trên bản cỡ màn (≈ 1206px) | ⚠️ chưa có |
| AC-2 | (V1) như AC-1 | pinch khung 1 lên 1,4× | không có yêu cầu bản cao nào | ⚠️ chưa có |
| AC-3 | (V1) ảnh 4000×3000 | phóng 5× | bản cao có cạnh dài 3000px; ảnh 2400×1600 thì bản cao 2400px (không phóng to hơn gốc) | ⚠️ chưa có |
| AC-4 | (V1) khung 1 là ảnh chỉ có trên iCloud (bản xem trước 1536px), Wi-Fi | phóng 5× | vòng 22pt không số ở góc trên-phải khung 1; xong thì vòng mất, khung vẽ bản 3000px | ⚠️ chưa có — `-ShotDexFakeICloud` như `icloud-viewer-zoom.json` |
| AC-5 | (V1) như AC-4, Airplane Mode | phóng 5× | khung 1 giữ bản cỡ màn; ≤ 15 s sau có glyph iCloud cam; không vòng quay vô hạn | ⚠️ chưa có |
| AC-6 | (V1, K6, NF-02) iPad 1376×1032, Compare 4 ảnh 8256×5504 (45MP) | phóng 5× lần lượt trên khung 1, 2, 3, 4 | sau mỗi bước có tối đa 2 bản cao (cuối cùng: khung 3 và 4); bộ nhớ app tăng ≤ 55 MB so với lúc mở; không bản nào có cạnh dài > 3000px; cảnh báo thiếu bộ nhớ giả lập thì mọi khung về bản cỡ màn | ⚠️ chưa có — NF-02 chưa có test bộ nhớ |
| AC-7 | (V1) khung 1 đang có bản cao ở 5× | thu về 1× | bản cao bị nhả, khung vẽ bản cỡ màn | ⚠️ chưa có |
| AC-8 | (V2) từ Duplicates, nhóm 4 ảnh, đánh dấu 1 | Delete rồi xác nhận | màn ở lại với 3 khung; không khung nào có dấu; góc trên-phải là dòng hướng dẫn; nhóm ở Duplicates còn 3 ảnh | ⚠️ chưa có |
| AC-9 | (V2) chế độ chọn thường, Compare 3 ảnh, đánh dấu 2 | Delete rồi xác nhận | còn 1 khung nên màn đóng; lưới không còn 2 ảnh đã xoá | ⚠️ chưa có |
| AC-10 | (V2, K5) Compare 3 ảnh, chưa dấu nào, góc trên-phải chỉ có dòng "Tap a photo to mark it for deletion" | chạm khung 2 | khung 2 có dấu; góc trên-phải có Delete 1 Photo và **ngay dưới** nó dòng "Touch and hold to keep only this one"; trên Duo ngoài cả hai nằm ngoài rail 84pt | ⚠️ chưa có |
| AC-11 | (Q2) Compare 3 ảnh, 1 dấu | Delete rồi Cancel trong hộp thoại hệ thống | 0 cảnh báo; 3 khung, dấu giữ nguyên | ⚠️ chưa có |
| AC-12 | (Q2) từ Duplicates, 1 dấu, lệnh xoá trả lỗi (giả lập) | Delete rồi xác nhận | cảnh báo "Couldn't Update Photos" hiện **trên** Compare; 3 khung, dấu giữ nguyên | ⚠️ chưa có |
| AC-13 | (Z5) iPad có bàn phím, từ Duplicates, 2 dấu | bấm Esc | Compare đóng; nhóm ở Duplicates vẫn có đúng 2 dấu đó | ⚠️ chưa có |
| AC-14 | (Z5) chế độ chọn thường, iPad iOS 18.6, 1 dấu | bấm Esc | Compare đóng, 0 ảnh bị xoá | ⚠️ chưa có |
| AC-15 | (K6) khung 1 đã có bản cao ở 5× | chạm và phóng khung 2 lên 5× | khung 1 **vẫn** vẽ bản 3000px; khung 2 có bản 3000px; 0 yêu cầu mới cho khung 1 | ⚠️ chưa có |
| AC-16 | (K5) như AC-10 sau khi chạm | chạm lại khung 2 (bỏ dấu) | nút Delete và dòng gợi ý cùng mất; góc trên-phải về "Tap a photo to mark it for deletion" | ⚠️ chưa có |
