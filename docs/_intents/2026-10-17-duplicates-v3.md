# Intent: Duplicates v3 — help a photographer decide which near-identical shot to keep

| Trường | Giá trị |
|---|---|
| Tác giả | Hoang Tuan + Claude |
| Ngày | 2026-10-17 |
| Trạng thái | accepted (2026-10-17) |
| Tiến độ | **đang làm** (2026-10-17) — task 6/27 (board 4 canvas, store, session trên đĩa, loại nhóm + veto tiêu cự, bracket/focus stack, độ nét/cháy sáng), 8/50 AC xanh + AC-G4 phần domain (plan [2026-10-17-fs0606-duplicates-v3](../_plans/2026-10-17-fs0606-duplicates-v3.md)) |
| Nguồn | phản hồi người dùng ("một trong những tính năng quan trọng") + review 7 agent: 3 persona, 2 UX, khảo sát 13 app, ý kiến người dùng app khác |
| Spec sinh ra từ đây | [FS-06.06](../02-functional-spec/FS-06-collections/06-duplicates.md) + [FS-06.06b](../02-functional-spec/FS-06-collections/06b-duplicates-marks-merge-delete.md) (v3); ghi chú đảo phạm vi ở [FS-02.05](../02-functional-spec/FS-02-photo-detail/05-burst-selection.md) |

Quyết định hướng đi đã chốt trên planboard (1 vòng, cả 10 mặc định được đồng ý):
`.planboard/duplicates-v3/DECISIONS.md`, thứ tự việc ở `.planboard/duplicates-v3/PLAN.md`.
Ảnh chụp app hiện tại trên iPhone 17 (iOS 26.5): `build/ux-dup/` (không commit).

## Problem — vấn đề

Người chụp có rất nhiều ảnh gần giống nhau: burst 10–30 khung, chụp 5–15 tấm mỗi khoảnh khắc, bracket, bản xuất Lightroom nằm cạnh bản gốc, bản gửi lại qua WhatsApp/Zalo. Họ **không biết nên giữ tấm nào** và sợ xoá nhầm tấm duy nhất tốt. Màn Duplicates hôm nay không trả lời được câu hỏi đó.

- **Gợi ý giữ lại dựa vào file, không dựa vào ảnh.** Thứ tự là đã sửa, yêu thích, file lớn nhất, nhiều pixel nhất (`Domain/Duplicates/DuplicateReview.swift:56-81`). Chip lý do chỉ có Edited / RAW / Favorite / Live / Largest (`:33-45`). Không đo độ nét, mắt nhắm hay cháy sáng.
  - Với burst, "file lớn nhất" có thể là khung cô dâu nhắm mắt.
  - Với bracket, đó là khung +2 EV cháy sáng.
  - Nút đỏ "Mark the other 24" vẫn tin theo gợi ý đó (`Features/Duplicates/DuplicatesScreen.swift:827-838`).
- **Chạm vào ảnh là đánh dấu xoá** (`DuplicatesScreen.swift:761`). Muốn xem kỹ thì phải nhấn giữ hoặc vào Compare. Cả persona phụ huynh lẫn thợ cưới đều bị bất ngờ.
- **Không so được chi tiết nhỏ trên iPhone.**
  - Ô ảnh 83pt.
  - Compare chỉ hai khung chồng nhau, vuốt 24 lần cho một burst.
  - Màn chọn burst có dải phim 44pt và hơn nửa màn hình đen (`build/ux-dup/runD/21-frames.png`).
- **Ảnh nguyên liệu bị coi là rác.** Grouper chỉ dùng dHash 9×8 xám cộng kích thước (`DuplicateGrouper.swift:146-148`), không đọc EV hay tiêu cự. Bracket ±2 EV, focus stack, chuỗi ảnh tripod rơi vào Exact. Ở đó Merge đề nghị xoá cả loạt.
- **Bốn tab Exact · Similar · Series · Bursts.**
  - Người không chuyên không phân biệt được bốn tab.
  - Cùng một cụm nằm ở hai tab, với lựa chọn riêng theo tab.
  - Burst từ máy ảnh (Sony 10 fps) không vào được màn chọn burst, vì màn đó chỉ nhận burst của PhotoKit.
- **Không có lối nhanh.** 600 nhóm là 600 thẻ, không có gì được chọn sẵn, và Merge nằm ẩn dưới ⋯. Persona thợ cưới có 40 phút mà chỉ dọn được 15 nhóm.
- **Mất công khi app bị tắt.** Lựa chọn chỉ sống trong phiên (06b §1 D2). Chuyển sang trả lời tin nhắn, iOS tắt app, mất cả giờ chọn.
- **Xoá xong im lặng.**
  - `DuplicatesModel.swift:683-713` không có thông báo, không nói ảnh đi đâu.
  - Album mà bản bị xoá đang nằm trong thì mất ảnh âm thầm. Merge chỉ chép favorite, vị trí và ngày (06b §2).
- **Chữ trên ô không giúp chọn.**
  - Ô ghi "4032×3024 / 2.1 MB".
  - Dòng "bản này thiếu gì" (Not edited, JPEG only) chỉ trình đọc màn hình đọc được (`DuplicatesScreen.swift:792-806`).
  - Bản xuất Lightroom đã giao khách trông như một bản sao nhỏ hơn.
- **Không có "Not duplicates".** Hai ảnh khác nhau bị gộp sẽ hiện lại sau mỗi lần quét. Đây là lời than hàng đầu về Apple Photos và Gemini.

Mức độ: tính năng được coi là quan trọng; ba persona đều bỏ cuộc giữa chừng; rủi ro xoá nhầm ảnh không lấy lại được sau 30 ngày.

## Proposed outcome — kết quả mong muốn

- **Mở ra là biết làm gì.** "~4.2 GB có thể giải phóng" chia làm hai phần:
  - **Dọn nhanh, an toàn:** bản sao giống hệt và bản nhỏ hơn, dọn bằng một nút sau khi xem trước.
  - **Cần bạn chọn:** từng nhóm ảnh gần giống.
- **Mỗi nhóm nói ảnh nào tốt hơn và vì sao.** Ảnh giữ ghi lý do ("Sharpest · eyes open"). Mỗi bản còn lại ghi điểm yếu ("Eyes closed", "Smaller copy · WhatsApp", "Not edited", "In album: Mai & Huy"). Gợi ý vẫn chỉ là gợi ý: app không tự chọn xoá ảnh yêu thích, ảnh đã sửa hay ảnh nằm trong album.
- **Soi được mắt và độ nét trên iPhone bằng một tay.** Màn chọn khung có khung lớn và dải phim. Zoom giữ nguyên chỗ khi vuốt sang khung khác, có nút nhảy tới khuôn mặt. Màn này dùng chung cho burst iPhone và chụp liên tiếp từ máy ảnh.
- **Bracket, focus stack, bộ panorama được gọi đúng tên.** Thẻ có nút ghép HDR / Panorama / Focus Stack, không có nút xoá đỏ.
- **Một danh sách, lọc theo loại** (Copies · Smaller copies · Look-alikes · Same moment), mỗi cụm chỉ ở một chỗ.
- **Chạm ảnh là xem to; đánh dấu bằng vòng ở góc.**
- **Lựa chọn, "Keep all" và "Not duplicates" còn nguyên** sau khi app bị tắt hoặc quét lại.
- **Xoá minh bạch.**
  - Trước khi xoá, xem lại danh sách ảnh sắp xoá.
  - Ảnh giữ được nhận album, yêu thích và vị trí của các bản bị xoá.
  - Sau khi xoá có thông báo "moved to Recently Deleted · freed · kept 30 days", kèm nút mở Photos.

## Affected users and systems — phạm vi ảnh hưởng

- **Màn hình:** Duplicates (toàn bộ), Bursts (gộp vào Duplicates, màn chọn khung dùng chung), dòng Duplicates trong Collections/Utilities, lối tới HDR merge (FS-01.11) và Panorama (FS-14).
- **Thiết bị:** iPhone, iPad, Duo trong, Duo ngoài. Board của cả ba canvas (PH_/IP_/DI_/DC_ Duplicates, BurstFrames) phải vẽ lại.
- **Tầng code:**
  - Domain: `DuplicateGrouper`, `DuplicateReview`, `DuplicateScanPipeline`, thêm phần chấm chất lượng bằng Vision.
  - Data: bảng mới cho lựa chọn, bỏ qua và điểm chất lượng.
  - Features: `Features/Duplicates/`, `Features/Bursts/`.
  - Không đụng ShotDexKit hay extension.
- **Dữ liệu người dùng:** có. Lựa chọn và danh sách "Not duplicates" là dữ liệu người dùng tạo ra, nên nằm ở bảng riêng, không trong `photo_metadata`. Merge ghi vào thư viện Photos (album, favorite, vị trí).

## Constraints — ràng buộc

- Mọi phân tích ảnh chạy trên máy. Không gửi ảnh đi đâu, không thêm dependency, chỉ dùng Vision / Core Image / Accelerate.
- Chấm chất lượng chỉ trên ảnh đã vào nhóm, không chấm cả thư viện 55k. Phải hủy được. Không làm chậm lưới Library.
- App không bao giờ tự xoá hay tự đánh dấu xoá mà người dùng chưa xem. Mọi lần xoá đi qua hộp xác nhận của hệ thống.
- Không hứa Undo sau khi xoá: PhotoKit không cho app khôi phục từ Recently Deleted.
- Dữ liệu người dùng gõ hoặc chọn không nằm trong `photo_metadata`. Decode vẫn khoan dung với dữ liệu hỏng.
- Không cần tương thích ngược với dữ liệu lựa chọn cũ, vì app chưa phát hành và lựa chọn cũ chỉ sống trong phiên.
- Giữ cả nhánh iOS 26 và trước 26.
- Test và ảnh chụp không dùng ảnh có mặt người. Fixture cho phần đo mắt phải tự sinh, hoặc kiểm bằng Vision trước khi dùng.
- Chữ trên app bằng tiếng Anh (Mỹ), dùng từ thường, không dùng thuật ngữ (asset, keeper, hash).

## Open questions — câu hỏi còn treo

Đã trả lời (2026-10-17):

- **Đo mắt nhắm, tốc độ chấm:** spike trên iPhone thật trước bước chấm điểm (PLAN bước 4), dùng ảnh của người dùng, không commit ảnh.
  - Ngân sách: dưới 20ms một ảnh trên thumbnail 512px.
  - Sai nhiều thì chỉ hiện "Eyes closed" khi độ tin cậy cao; độ nét vẫn là tiêu chí chính.
- **Duo màn ngoài:** đầy đủ như iPhone, cả duyệt nhóm và chọn khung, trong vùng 466×678 trừ rail 84pt. Cần board DC_ riêng.
- **iPad:** màn chọn khung có thêm chế độ Survey, dùng lại từ Compare (FS-01.08c). iPhone không có Survey.

Còn treo, Claude trả lời khi viết spec:

1. **Có đọc được dấu hiệu "ảnh xuất từ Lightroom" từ dữ liệu đã index không** (Software tag, tên file)? Kiểm tra `ExifReader`.
   - Mặc định: nếu chưa có thì đọc thêm khi index nhóm, không index lại cả thư viện.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
