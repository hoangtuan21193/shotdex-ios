# FS-02.01b — Đóng viewer và bàn phím

`FS-02.01b` · `Features/Library/PhotoDetailScreen.swift` · `Features/Shared/PhotoGridCollectionView.swift`
· cập nhật 2026-10-02 · nguồn [intent ui-review-1002](../../_intents/2026-10-02-ui-review-1002.md) (Q7, Z5)

**Một câu:** đóng viewer thì lưới đứng ở đúng ảnh vừa xem, và iPad có bàn phím thì Esc đóng, mũi tên lật ảnh.

## 1. Đóng viewer: lưới đứng ở ảnh vừa xem (Q7)

Đóng viewer bằng X, vuốt xuống hay Esc thì lưới đã mở nó — **Library, album thường, smart album, On This Day**
và mọi lưới dùng chung khác — đưa ô của **ảnh đang hiện lúc đóng** vào tầm nhìn.

- Ô đã thấy **trọn** giữa nav bar và tab bar (hoặc thanh chọn) → lưới đứng yên, dịch 0pt.
- Ô khuất một phần hay khuất hẳn → lưới cuộn **một lần, không hoạt ảnh**, cho ô nằm giữa chiều dọc vùng nhìn
  thấy; gần đầu hay cuối danh sách thì kẹp ở mép, không cuộn quá nội dung.
- Cuộn chạy **ngay khi lệnh đóng bắt đầu**, lúc lưới còn nằm dưới lớp phủ. *Vì cuộn sau khi lớp phủ đã trượt đi
  thì người dùng thấy lưới nhảy một nhịp.*
- Ảnh không còn trong lưới (đã ẩn, bộ lọc đã đổi) hoặc viewer tự đóng vì hết ảnh → không cuộn.
- Cuộn này **không** nạp lại lưới ([01](01-pager-and-image-loading.md) §7) và không xin lại thumbnail của ô đã có.
- Với Library neo đáy: ô đích nằm trong một màn hình tính từ đáy thì lưới vẫn coi là đang neo đáy
  ([FS-01.01](../FS-01-library/01-photo-grid-and-data-source.md) §5).
- Luật áp cho **mọi lưới dùng chung mở viewer** (K7): ngoài bốn lưới trên còn Trips, Places, album mở từ
  Collections và Uploaded to Server.

Board: không đổi bố cục; không cần sửa board.

## 2. Bàn phím phần cứng (Z5)

| Phím | Kết quả |
|---|---|
| Esc | đóng viewer, như nút X — cùng luật §1 |
| → / ← | ảnh sau / ảnh trước, như vuốt ngang: đặt lại mức phóng, tắt Live Text; ở ảnh cuối / đầu thì không làm gì. **Video đang dừng: tiến / lùi một khung** |
| `.` · F | favorite (bật/tắt), như nút tim — `.` như Photos cho Mac |
| I · Delete · ⌘S | Info · xoá · share, như nút cùng chức năng (đã có) |

- Phím chạy **cả khi chrome đang ẩn** (đang phóng, video đang phát quá 3 giây). *Vì chrome ẩn đúng lúc phóng —
  phím gắn vào nút đang ẩn là phím chết.*
- Có một lớp đang mở trên viewer (sheet Photo Info, menu ⋯, hộp thoại xoá) thì Esc đóng **lớp đó trước**,
  viewer ở lại. Cột Photo Info ở màn rộng ([03b](03b-info-inspector.md)) không phải một lớp: Esc đóng viewer.
- **Một luật mọi thiết bị** (chốt 2026-10-04, FS-18 01b §3, `ViewerKeyMap`): video **đang dừng** thì → / ← tiến /
  lùi một khung, như hai nút Frame ([02](02-video-playback.md) §9), vẫn trang đó; video **đang phát** thì → / ← lật
  trang như ảnh, video dừng. `,` không gán. Thay luật K8 cũ (→ / ← luôn lật trang, `.` `,` bước khung).
- Không có ⌘A, ⌘F.
- iOS 26 và trước 26 giống nhau: viewer không rẽ nhánh cho phím.

Board: không đổi (phím không có hình).

## 3. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | (Q7) iPhone 402×874, Library 2.000 ảnh, mở ảnh ở ô 1.950 (thấy trọn), lật 40 trang tới ô 1.910 | bấm X | ô 1.910 thấy trọn giữa nav bar và tab bar, tâm ô lệch tâm vùng nhìn ≤ 1 hàng ô; 0 lượt nạp lại lưới | ⚠️ chưa có |
| AC-2 | (Q7) mở ảnh ở một ô thấy trọn, không lật trang | vuốt xuống đóng | vị trí cuộn của lưới đổi 0pt | ⚠️ chưa có |
| AC-3 | (Q7) album thường 300 ảnh, smart album 300 ảnh, On This Day 3 năm; mỗi nơi mở ô đầu rồi lật 30 trang | bấm X | ở cả ba, ô của ảnh thứ 31 thấy trọn; chạy trên iPad 1376×1032, Duo trong 951×669, Duo ngoài 466×678 | ⚠️ chưa có |
| AC-4 | (Q7) xem ảnh ở ô 40 của album 300 ảnh, xoá ảnh đó, viewer hiện ảnh kế | bấm X | ô của ảnh kế thấy trọn; không ô nào trỏ tới ảnh đã xoá | ⚠️ chưa có |
| AC-5 | (Q7) album 1 ảnh, đang xem ảnh đó | xoá và xác nhận | viewer tự đóng, lưới không cuộn, hiện trạng thái rỗng của album | ⚠️ chưa có |
| AC-6 | (Q7) như AC-1 | bấm X | trong chuỗi ảnh chụp cách nhau 100 ms lúc lớp phủ trượt xuống, không khung nào cho thấy lưới ở vị trí cũ rồi mới tới ô 1.910 | ⚠️ chưa có — burst `Tools/sim-shot` |
| AC-7 | (Z5) iPad 1376×1032 có bàn phím, viewer ở ảnh 10 của 50, đang phóng 3× | bấm → | ảnh 11 ở mức 1×; bấm ← hai lần thì về ảnh 9 | ⚠️ chưa có — `Tools/ui-drive` chưa có bước phím |
| AC-8 | (Z5) viewer ở ảnh 50 của 50 | bấm → | vẫn ảnh 50, mức phóng giữ nguyên, không có cảnh báo | ⚠️ chưa có |
| AC-9 | (Z5) viewer đang phóng 3×, chrome ẩn | bấm Esc | viewer đóng; lưới theo AC-1 | ⚠️ chưa có |
| AC-10 | (Z5) iPad dọc 1032×1376, sheet Photo Info đang mở | bấm Esc | sheet đóng, viewer còn ở cùng ảnh; bấm Esc lần nữa thì viewer đóng | ⚠️ chưa có |
| AC-11 | (Z5) video 30 s đang phát ở 12 s, chrome đã ẩn | bấm → | trang sau hiện, video trang cũ dừng | ⚠️ chưa có |
| AC-12 | (Z5) như AC-7 trên iPad iOS 18.6 | bấm →, rồi Esc | cùng kết quả như trên iOS 26.5 | ⚠️ chưa có |
| AC-13 | video 30 s đang **phát**, trang 5 của 10 | bấm → | trang 6 hiện; video trang 5 dừng | ✅ `ViewerKeyMapTests.arrowsStepAPausedVideoAndPageOtherwise` (luật); lật trang bằng → trên ảnh: ui-drive iPhone 17 26.5 (`Oct 15 7:21` → `Oct 15 8:09` → ← về). ⚠️ video thật trên sim chưa có |
| AC-14 | video 30 fps đang dừng ở khung 360 | bấm → rồi ← hai lần | khung 361 rồi khung 359; vẫn trang đó, vẫn dừng | ✅ luật `ViewerKeyMapTests`; ⚠️ chạy trên video thật chưa có (sim không có video) |
| AC-15 | ảnh hoặc video, chưa Favorite | bấm `.` | Favorite bật, như nút tim; video không tiến khung | ✅ `ViewerKeyMapTests.periodIsFavoriteEverywhere`; ui-drive: nút tim đổi "Favorite" → "Unfavorite" sau `.` |
| AC-16 | (K7) Trips: chuyến 200 ảnh; Places: một ghim 80 ảnh; album mở từ Collections 300 ảnh; Uploaded to Server 150 ảnh — mỗi nơi mở ô đầu rồi lật 30 trang | bấm X | ở cả bốn, ô của ảnh thứ 31 thấy trọn giữa thanh trên và thanh dưới | ⚠️ chưa có |
