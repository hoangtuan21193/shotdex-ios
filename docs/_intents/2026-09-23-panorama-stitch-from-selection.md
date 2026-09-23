# Intent: Ghép panorama từ nhiều ảnh đang chọn

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan@karabiner.tech |
| Ngày | 2026-09-23 |
| Trạng thái | accepted |
| Nguồn | tự nghĩ ra (người dùng yêu cầu trực tiếp) |
| Spec sinh ra từ đây | [FS-14](../02-functional-spec/FS-14-panorama/README.md) |

## Problem — vấn đề

Người chụp bằng máy ảnh rời (mirrorless, DSLR) chụp panorama theo cách cổ điển: xoay máy, bấm
một loạt 3–15 khung chồng mép nhau, về nhà ghép. Máy ảnh không ghép hộ, còn chế độ Pano của
Camera iPhone chỉ ghép khi quét ngay trên iPhone. Hôm nay chuỗi khung đó nằm trong thư viện
ShotDex như những ảnh rời, và **không có cách nào trong app biến chúng thành một tấm** — người
dùng phải mang sang máy tính (Lightroom Classic Photo Merge, PTGui, Hugin) rồi đưa ngược về Photos.

Bằng chứng về khoảng trống:

- Menu ⋯ của selection đã có **Combine Photos**
  ([SelectionBarViews.swift:212](ShotDex/Features/Library/SelectionBarViews.swift:212)) mở
  `PhotoStackScreen`, nhưng `PhotoStackMode` chỉ có bốn mode `average · lighten · darken ·
  focusStack` ([PhotoStackRenderer.swift:7](ShotDexKit/Render/PhotoStackRenderer.swift:7)). Tất cả
  đều giả định các khung **trùng khung hình** — chồng lên nhau, không nối cạnh nhau.
- Căn ảnh duy nhất hiện có là `VNTranslationalImageRegistrationRequest`
  ([PhotoStackRenderer.swift:240](ShotDexKit/Render/PhotoStackRenderer.swift:240)), cố ý **chỉ
  tịnh tiến** (FS-01.09 §3). Panorama xoay máy cần phép chiếu (homography / trụ / cầu), trộn mép,
  bù phơi sáng giữa các khung — không có mảnh nào trong số đó tồn tại.
- Intent Lightroom parity đã ghi nhận đây là chỗ thiếu và để treo: *"Không ghép HDR, không ghép
  panorama"* và *"panorama còn là cả một hệ thống con mới"*
  ([2026-09-22-editor-lightroom-feature-parity.md:39, :131](docs/_intents/2026-09-22-editor-lightroom-feature-parity.md)).
- ShotDex đã **xem** được panorama (`PanoramaScreen`, ⋯ → View Panorama), nhưng lối đó chỉ mở khi
  asset mang `mediaSubtypes.photoPanorama`
  ([PhotoDetailScreen.swift:757](ShotDex/Features/Library/PhotoDetailScreen.swift:757)) — cờ do
  hệ thống đặt cho ảnh Pano của Camera. Một tấm do app ghép ra sẽ không có cờ đó.

Mức độ: tính năng mới, không phải lỗi. Ảnh hưởng nhóm người chụp phong cảnh/kiến trúc bằng máy
rời — đúng đối tượng ShotDex nhắm tới (lọc theo máy/ống kính), nhưng chưa có lời phàn nàn nào ngoài
yêu cầu này.

## Proposed outcome — kết quả mong muốn

- Chọn một chuỗi khung chồng mép trong lưới (Library, album, smart album…), chọn một lệnh ghép,
  và nhận lại **một ảnh panorama mới** trong thư viện; các ảnh gốc không bị đụng tới.
- Trước khi lưu thấy được bản xem trước của kết quả, đủ để biết ghép có đúng không (khung lạc
  chỗ, đường nối lộ, mép răng cưa).
- Khi chuỗi không ghép được (khung không chồng mép, ảnh không liên quan, quá ít điểm chung) người
  dùng được nói rõ **vì sao** và phải làm gì, không phải một ảnh méo hay một lần Save im lặng.
- Ghép được cả chuỗi một hàng (ngang/dọc) lẫn lưới nhiều hàng, với chất lượng ngang Lightroom
  Photo Merge: chọn phép chiếu, kéo mép cong về chữ nhật (Boundary Warp) hoặc tự crop, không lộ đường
  nối hay chênh sáng giữa các khung.
- Tấm ghép ra được đối xử như một panorama ở những chỗ ShotDex quan tâm: mở được bằng viewer
  panorama, và vẫn gắn được với máy/ống kính đã chụp để lọc và thống kê không lạc mất nó.

## Affected users and systems — phạm vi ảnh hưởng

- **Màn hình / tính năng**: selection overlay (menu ⋯, dùng chung bốn màn qua `RootTabView`);
  một màn tier D mới cạnh `PhotoStackScreen` (không sửa màn đó); `PhotoDetailScreen` (lối View Panorama);
  `PanoramaScreen`.
- **Thiết bị**: iPhone, iPad, Duo trong và ngoài — luật "phone có mọi tính năng iPad" giữ nguyên,
  nên không có bản nào bị cắt bớt theo thiết bị.
- **Tầng code**: render thuần (căn ảnh, chiếu, trộn) thuộc **ShotDexKit** như `PhotoStackRenderer`;
  màn hình ở `Features/`; lưu asset mới qua đường lưu ảnh mới đã có. Không đụng Domain/indexer
  ngoài việc tấm mới được index như mọi ảnh khác.
- **Dữ liệu đã lưu**: không đổi schema dự kiến. Tấm ghép là một `PHAsset` mới; không đụng
  `photo_metadata` của ảnh gốc, không đụng `PhotoEditRecipe`.

## Constraints — ràng buộc

- **Local-only**: mọi bước chạy trên máy, không gửi ảnh đi đâu.
- **Không thêm dependency** (chỉ GRDB) — không OpenCV, không thư viện stitch bên ngoài. Chỉ có
  Vision, Core Image, Accelerate, Metal của hệ thống.
- **Không phá bộ nhớ, không thu nhỏ đầu ra**: panorama rất lớn (10 khung × 24MP có thể ra > 150MP) và
  người dùng đã chốt không trần kích thước. Nên không được giữ mọi khung full-res hay cả ảnh đầu ra trong
  RAM cùng lúc — render theo tile ra đĩa, theo tinh thần "bộ nhớ phẳng" của FS-01.09 §1. Lối vào chỉ ở
  app (selection), không ở Edit extension (trần ~120MB).
- **Không làm hỏng bốn mode Combine đang chạy** và luật "focus stack chỉ tịnh tiến".
- **Kit purity**: phần trong ShotDexKit không import SwiftUI/GRDB.
- **Không ghi ngược ảnh gốc** và không xoá gì — xoá/giữ chuỗi gốc là việc người dùng tự bấm.
- **iOS 17 tối thiểu**, nhánh iOS 26 vẫn chạy; không dựa vào API chỉ có ở iOS 26 cho phần lõi.
- `DESIGN.md` tier D cho màn công cụ; không bịa token mới.

## Open questions — câu hỏi còn treo

Mọi câu đã chốt 2026-09-23. Việc còn chặn `/spec` là **spike** ở câu 4.

1. ~~Lối vào ở đâu?~~ — **chốt 2026-09-23: lệnh riêng "Create Panorama"** trong menu ⋯ của selection,
   màn tier D riêng; không nhét vào picker của Combine Photos.
2. ~~Phạm vi v1~~ — **chốt 2026-09-23: cả lưới nhiều hàng** (ngang, dọc và 2D), không chỉ một hàng.
   Hệ quả: căn ảnh phải là đồ thị nhiều cặp chồng mép, không phải chuỗi tuần tự; số khung tối đa và thời gian
   ghép phải đo ở spike (câu 4); kích thước đầu ra không trần (câu 8).
3. ~~Thứ tự khung~~ — **chốt 2026-09-23: app tự dò vị trí từng khung từ chỗ chồng mép, người dùng sửa
   tay được** (kéo khung về đúng chỗ trên preview) khi dò sai. Không dựa vào thứ tự lưới hiện nay của
   `presentStack` ([LibraryScreen.swift:241](ShotDex/Features/Library/LibraryScreen.swift:241)).
4. ~~Có spike không?~~ — **chốt 2026-09-23: có, và chặn trước `/spec`.** Spike đo trên chuỗi thật: căn
   ảnh bằng Vision (`VNHomographicImageRegistrationRequest`) cho lưới nhiều cặp, ba phép chiếu, Boundary
   Warp, trộn đường nối, bù phơi sáng, bộ nhớ khi render theo tile. Mục nào đã chốt ở câu 6 mà spike
   không làm nổi thì quay lại người dùng trước khi viết AC. **Ảnh thử: bộ dữ liệu panorama giấy phép mở
   (CC0/CC-BY)**, cả một hàng lẫn lưới; ghi nguồn và giấy phép cạnh dữ liệu test.
   **Kết quả 2026-09-23:** [2026-09-23-panorama-stitch-spike.md](2026-09-23-panorama-stitch-spike.md) — khả thi,
   với ba điều kiện: tự viết dò điểm đặc trưng (Vision không dùng được), xuất JPEG (HEIC ngốn RAM), render theo dải.
5. ~~Tấm ghép có được viewer panorama không?~~ — **chốt 2026-09-23: mở lối View Panorama theo tỉ lệ
   khung** (ngưỡng cụ thể, ví dụ ≥ 2:1, để `/spec` chốt), áp cho mọi ảnh rộng chứ không riêng tấm ghép.
6. ~~Chất lượng "đủ tốt"~~ — **chốt 2026-09-23: kiểu Lightroom đầy đủ**: ba phép chiếu (Spherical,
   Cylindrical, Perspective) cho người dùng chọn, Boundary Warp, Auto Crop, trộn mép và bù phơi sáng
   giữa khung. `/spec` biến từng mục thành tiêu chí đo được. Đây là phạm vi lớn nhất có thể chọn — spike
   ở câu 4 là điều kiện chặn trước `/spec`.
7. ~~Metadata~~ — **chốt 2026-09-23: lấy EXIF của khung đầu tiên theo thứ tự ghép** (máy, ống kính,
   ngày, vị trí); bỏ thông số phơi sáng nếu các khung lệch nhau.
8. ~~Giới hạn kích thước~~ — **chốt 2026-09-23: không trần — luôn xuất full-res.** Khi ảnh lớn hơn sức
   chứa bộ nhớ thì **render theo tile, ghi xuống đĩa từng mảnh**, chậm hơn nhưng không mất pixel. Đây là
   yêu cầu cứng cho kiến trúc render (xem Constraints) và là một mục spike phải chứng minh.
9. ~~RAW và Optimize Storage~~ — **chốt 2026-09-23: ghép từ bản render hiện tại của mỗi ảnh** (đã gồm
   edit), tải bản gốc từ iCloud khi máy chỉ có proxy, có tiến trình. `photokit-guard` rà ở `/spec`.
10. ~~Quan hệ với HDR~~ — **chốt theo câu 1**: panorama là lệnh riêng, không chung lối "Merge" với HDR.
    HDR vẫn treo ở câu 4 của intent Lightroom parity, ngoài phạm vi intent này.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
