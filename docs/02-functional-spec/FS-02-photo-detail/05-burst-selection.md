# FS-02.05 — Chọn khung trong burst

`FS-02.05` · tier D · `Features/Library/PhotoDetailScreen.swift` · `Data/Sources/PhotoLibraryService+Assets.swift`
· `Features/Library/CompareScreen.swift` · nguồn intent [user-wishes-research](../../_intents/2026-09-30-user-wishes-research.md)
mục 12 · cập nhật 2026-10-01

**Một câu:** từ tab Bursts của Duplicates hoặc từ một ảnh burst trong viewer, lướt mọi khung trên một màn kiểu
Photos, chạm chọn khung giữ, và đưa phần còn lại vào Recently Deleted bằng **một** lần xác nhận của hệ thống.

## 1. Người dùng cần gì

Một pha chạy chụp burst ra 24 khung, người chụp cần 1–2 tấm. Hôm nay ⋯ → Show All Frames chỉ mở danh sách
xem; bỏ 22 khung là 22 lần xoá lẻ. Photos có nút Select… trên burst, ShotDex thì chưa.

## 2. PhotoKit cho phép gì

Đọc SDK iOS 27.1 và tài liệu Apple ngày 2026-10-01.

| Việc | Được không | Hệ quả |
|---|---|---|
| Lấy mọi khung của một burst | có, phải xin rõ "mọi khung" | code hôm nay đã làm, cho danh sách xem |
| Biết khung **Photos gợi ý** và khung **người dùng đã chọn trong Photos** | có, **chỉ đọc** | gợi ý có sẵn, không phải tự tính |
| Đánh dấu một khung là "người dùng đã chọn" | **không**, không có lệnh ghi nào | không làm được đúng "Keep Only N Favorites" của Photos |
| Xoá từng khung | lệnh xoá chung nhận mọi ảnh; **chưa đo trên burst thật** | xem §9 |
| Lưới và index thấy gì | khung đại diện + khung người dùng đã chọn trong Photos | khung còn lại không có row index, không có dấu vân tay |

Vì vậy bước "chọn" của Photos không làm được. Đường trung thực gần nhất: chọn khung giữ **trong app**, rồi
xoá những khung còn lại.

**"Giữ" nghĩa là gì sau khi xoá:**
- **Chỉ xoá khung không chọn.** Khung giữ vẫn thuộc burst: không tải gì, giữ album, favorite, chỉnh sửa.
- **Đường chép, chỉ khi số đo §9 bắt buộc:** khung giữ nào đo được là bị ẩn khỏi lưới sau khi xoá thì được chép
  ra thành ảnh độc lập (đường Duplicate có sẵn), rồi khung gốc đó đi cùng lệnh xoá.
  - Cái giá của đường chép: tải bản gốc iCloud, mất album và chỉnh sửa của khung đó.
  - Vì khung giữ mà biến khỏi lưới là mất ảnh trong mắt người dùng — tệ hơn mất album.
- Chưa có số đo §9 thì không chạy `/plan`.

## 3. Phạm vi

**Có:**
- Lối chính: tab **Bursts** trong Duplicates, liệt kê mọi burst của thư viện ([FS-06.06 §7b](../FS-06-collections/06-duplicates.md)).
- Lối thứ hai: mục ⋯ **Select Frames…** trong viewer, khi ảnh thuộc một burst mà app thấy được ≥ 2 khung. Nó
  **thay** Show All Frames ([FS-02.04 §2](04-actions-and-extras.md)): màn chọn cũng hiện mọi khung.
- Màn chọn khung tier D: mọi khung theo thứ tự chụp, có gợi ý của Photos, một nút đỏ xoá phần còn lại.

**Cố ý không có:**
- Ghi lựa chọn lên Photos — hệ thống không mở lệnh đó.
- Dấu "burst" trên ô lưới — lưới phải hỏi PhotoKit từng ô mới biết, trái luật 1 của
  [NF-01](../../04-non-functional-design/NF-01-performance.md).
- Chấm theo khuôn mặt hay mắt nhắm — gợi ý của Photos đã tính phần đó; app không test được mà không dùng ảnh
  có mặt người.
- Chấm độ nét trong app — v1 chỉ dùng gợi ý của Photos; burst không có gợi ý thì không có gợi ý.
- Undo trong app — ảnh đã xoá nằm ở Recently Deleted của Photos 30 ngày, và app bên thứ ba không đọc được album đó.
- Hộp thoại xác nhận tự dựng — hộp thoại xoá của hệ thống là bước xác nhận ([FS-02.04 §1](04-actions-and-extras.md)).

## 4. Màn hình

Màn mới, giống màn chọn burst của Photos: **một khung lớn + dải thumbnail ở đáy**.
- Chạm hay vuốt dải thumbnail = đổi khung lớn. Chạm khung lớn = **chọn giữ / bỏ giữ** khung đó; khung giữ có
  dấu tick ở khung lớn và ở thumbnail.
- Nghĩa của cú chạm ngược với Compare và Duplicates (chạm = đánh dấu xoá, [FS-01.08 §1](../FS-01-library/08-compare.md)).
  Vì người dùng Photos đã quen màn này; hình dạng khác hẳn Compare, và nút đỏ đếm khung **không** giữ.

Luật của màn:
- **Nút đóng nhìn thấy** ở trái thanh trên, chỗ Cancel của mọi màn tầng D (Q1): đóng mà không xoá gì, dấu giữ
  bị bỏ. Màn mở dạng sheet thì vẫn có nút này, không trông vào vuốt xuống.
- Khung xếp theo thứ tự chụp, cũ trước; mở ra **không khung nào được giữ**. Không tự chọn hộ, cùng luật
  với Duplicates.
- Khung đã chọn trong Photos mang nhãn **Picked in Photos**; khung được gợi ý mang nhãn **Suggested**.
- **Keep Only Suggested** ở thanh trên: một chạm giữ đúng các khung gợi ý, bỏ giữ mọi khung khác. Không có gợi ý
  thì mục này ẩn. **Keep Only This** ở menu giữ-lâu của khung lớn.
- Nút đỏ **Delete N Photos** (N = số khung không giữ) + dòng phụ "Photos move to Recently Deleted.", cùng nhãn
  với Duplicates.
- **Phải giữ ít nhất một khung:** chưa giữ khung nào thì nút tắt, và dòng phụ là "Keep at least one frame. To
  delete the whole burst, use Delete in the viewer."

Board: chưa có board màn chọn khung trên canvas ShotDex App Screens — vẽ `PH_`/`IP_`/`DI_`/`DC_` trước khi code.

## 5. Gợi ý khung

- **Nguồn duy nhất:** các khung Photos đã gợi ý. Đọc một cờ, không tốn gì, không tải gì.
- Burst không có khung gợi ý nào thì không có nhãn Suggested và không có Keep Only Suggested.
- Chưa đo được tỉ lệ burst từ Camera iPhone có sẵn gợi ý — đo cùng spike §9.

## 6. Xoá và sau khi xoá

- **Một** lệnh xoá cho cả mẻ, rồi hệ thống hỏi "Delete 22 Photos?". Huỷ ở đó thì không đổi gì và giữ nguyên dấu.
- Có khung đi đường chép (§2): bản chép được tạo **trước** lệnh xoá; chép hỏng thì không xoá gì.
- Xong: đóng màn. Mở từ viewer thì viewer đứng ở khung giữ đầu tiên; mở từ tab Bursts thì về tab đó. Banner: "22 frames moved to Recently Deleted. Recover them
  in Photos within 30 days." — không có nút Undo, vì app không làm được việc đó.
- Row index của khung đã xoá bị gỡ. Khung giữ mà thành ảnh hiện trong thư viện thì được index một row, theo
  đường index-một-ảnh của viewer ([FS-02.01 §6](01-pager-and-image-loading.md)).
- Cache Duplicates tự bỏ ảnh đã mất ([FS-06.06 §5](../FS-06-collections/06-duplicates.md)), không cần làm gì thêm.
- Xoá khung chỉ có trên iCloud **không cần tải** ảnh về.
- Lệnh xoá lỗi: PhotoKit làm cả mẻ hoặc không làm gì, nên không khung nào mất. Dấu giữ nguyên, kèm lỗi và
  nút **Try Again** ([NF-04](../../04-non-functional-design/NF-04-empty-and-error-states.md)).

## 7. Quyền giới hạn, Series, thiết bị

- **Quyền `.limited`:** PhotoKit chỉ trả những khung người dùng đã chia sẻ, và app **không biết** burst có
  tổng bao nhiêu khung.
  - Màn ghi "ShotDex can see N frames of this burst. Frames you haven't shared stay as they are."
  - Thấy < 2 khung thì không có mục ⋯. Lệnh xoá chỉ đụng khung thấy được.
- **Series của Duplicates** là loạt chụp nhanh nhưng không phải burst thật; nó giữ nguyên, xoá qua Compare.
  Khung burst bị ẩn không có trong Series, vì không có dấu vân tay. Burst thật nằm ở tab Bursts.
- **Thiết bị:** cùng chức năng trên iPhone 402×874, iPad 1376×1032, Duo trong 951×669, Duo ngoài 466×678.
  Duo ngoài có rail 84pt bên phải, nên nút đỏ và thanh trên phải nằm ngoài rail.
- **iOS 26 vs trước:** màn tier D không rẽ nhánh. Mục ⋯ nằm trong cùng một menu ở cả hai nhánh.
- **VoiceOver:** khung lớn đọc "Frame 3 of 24, Suggested, kept" (hoặc "not kept"); chạm đúp = chọn/bỏ giữ.
  Keep Only This là action.

## 8. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | ảnh A thuộc burst 24 khung, app thấy đủ 24; ảnh B không phải burst | mở ⋯ của A rồi của B | A có mục Select Frames… và không có Show All Frames; B không có mục nào cho burst | ⚠️ chưa có |
| AC-2 | burst 24 khung, Photos gợi ý khung 7 và 15 | mở Select Frames… trên iPhone, iPad, Duo trong, Duo ngoài | cả 4 máy: một khung lớn + dải 24 thumbnail theo thứ tự chụp; khung 7 và 15 mang nhãn Suggested; 0 khung được giữ; nút Delete tắt với dòng "Keep at least one frame…"; có Keep Only Suggested | ⚠️ chưa có |
| AC-3 | như AC-2 | bấm Keep Only Suggested | khung 7 và 15 có tick, 22 khung kia không; nút ghi "Delete 22 Photos" | ⚠️ chưa có |
| AC-4 | khung 7 và 15 được giữ | bấm Delete rồi xác nhận trong hộp thoại hệ thống | lệnh xoá mang đúng 22 id; mở lại Select Frames… thấy 2 khung; lưới không còn ô nào trỏ tới khung đã xoá | ⚠️ chưa có |
| AC-5 | khung 7 và 15 được giữ | bấm Cancel trong hộp thoại hệ thống | 0 ảnh bị xoá, khung 7 và 15 vẫn có tick | ⚠️ chưa có |
| AC-6 | màn đang ở khung 3, chưa giữ khung nào | chạm khung lớn, rồi chạm lại | lần 1: khung 3 có tick ở khung lớn và thumbnail, nút ghi "Delete 23 Photos"; lần 2: tick mất, nút tắt | ⚠️ chưa có |
| AC-7 | burst 24 khung, Photos không gợi ý khung nào | mở Select Frames… | không khung nào mang nhãn Suggested; không có Keep Only Suggested; 0 yêu cầu ảnh ngoài thumbnail và khung lớn | ⚠️ chưa có |
| AC-8 | burst 24 khung, 6 khung chỉ có trên iCloud, máy mất mạng | giữ 18 khung còn lại, xoá | lệnh xoá 6 khung chạy mà không tải gì, 0 yêu cầu mạng | ⚠️ chưa có |
| AC-9 | quyền `.limited`, burst 24 khung, người dùng mới chia sẻ 3 | mở Select Frames… | thấy 3 khung và câu "ShotDex can see 3 frames…"; lệnh xoá chỉ mang id trong 3 khung đó. Chia sẻ 1 khung thì không có mục ⋯ | ⚠️ chưa có |
| AC-10 | khung 7 và 15 được giữ, lệnh xoá trả lỗi (giả lập) | bấm Delete | 0 khung mất, tick giữ nguyên, có lỗi và nút Try Again | ⚠️ chưa có |
| AC-11 | giữ khung 7 và 15, cả hai **không** phải khung đại diện | xoá 22 khung còn lại, về Library | lưới có ô cho **cả** khung 7 và khung 15 (giữ trong burst, hoặc bản chép nếu §9 đo ra bị ẩn); không ô nào trỏ tới khung đã xoá | ⚠️ chưa có — cần máy thật |
| AC-12 | vừa xoá xong 22 khung | nhìn banner | banner nói 22 frames ở Recently Deleted, cứu được trong Photos 30 ngày; không có nút Undo | ⚠️ chưa có |
| AC-13 | (Q1) màn chọn khung mở trên iPhone 402×874, Duo trong 951×669 và Duo ngoài 466×678, đã giữ 2 khung | bấm nút đóng ở trái thanh trên | trước khi bấm nút thấy trên cả 3 máy, trên Duo ngoài nằm ngoài rail 84pt; màn đóng, 0 ảnh bị xoá, 0 hộp thoại hệ thống | ⚠️ chưa có |

**Chưa chứng minh được:** AC-1 → AC-13. Simulator chưa có burst nào (PHOTOS_PARITY B8).

## 9. Rủi ro và phần phải đo trước `/plan`

Cần đo trên một iPhone thật có burst, **trước** `/plan`. Kết quả quyết định có cần đường chép (§2) không.

| Rủi ro | Xử lý |
|---|---|
| Xoá một khung không phải đại diện có hỏng không, có vào Recently Deleted từng tấm không | spike: xoá 1 khung giữa loạt, xem Photos và Recently Deleted |
| Xoá khung đại diện: PhotoKit có chọn đại diện mới không, khung giữ có hiện trong lưới không | spike: giữ 2 khung không phải đại diện, xoá 22 khung còn lại |
| Bản chép khung burst (đường chép) có bị Photos gộp lại thành burst không | spike: Duplicate 1 khung, đọc mã burst của bản chép |
| Simulator có tạo được burst không (nhập file mang mã burst của Apple) | không được thì AC chứng minh qua lớp giả của PhotoKit + ảnh chụp máy thật |
