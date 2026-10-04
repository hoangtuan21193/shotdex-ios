# Intent: iPad theo kiểu app Mac

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan@karabiner.tech |
| Ngày | 2026-10-04 |
| Trạng thái | accepted — người dùng 2026-10-04: "Duyệt cả hai, sang /spec" |
| Tiến độ | **chưa làm** (2026-10-04) — plan đã duyệt (planboard mac-ipad-v2), 59 task ([FS-21](../_plans/2026-10-04-fs21-ipad-mac-style.md)); dùng chung plan FS-19/20/08c |
| Nguồn | phản hồi người dùng 2026-10-04: "giao diện macos đẹp quá, làm cho ipad kiểu như vậy" (sau khi xem canvas Mac) |
| Spec sinh ra từ đây | [FS-21](../02-functional-spec/FS-21-ipad-mac-style/README.md) (62 AC) · dùng chung [FS-19](../02-functional-spec/FS-19-photo-sources/README.md), [FS-20](../02-functional-spec/FS-20-card-ingest/README.md), [FS-01.08c](../02-functional-spec/FS-01-library/08c-compare-viewer-mode.md) |

## Problem — vấn đề

- Trên iPad 13", ShotDex vẫn là bố cục điện thoại nới rộng: thanh tab nổi ở đáy, nút tròn kính nổi trên ảnh,
  chế độ Select, mỗi màn đẩy toàn màn hình. Board hiện tại: `IP_*` trên canvas iPad (`docs/design/ipad/`).
- Màn rộng 1376pt mà không có sidebar nguồn/album, không có inspector EXIF cạnh lưới, không có thanh công cụ:
  muốn lọc, xem thông số, đổi album đều phải mở sheet rồi đóng.
- Bản Mac vừa vẽ (canvas Mac, `docs/design/mac/`) cho thấy cùng nội dung xếp kiểu sidebar · nội dung · inspector
  dùng màn lớn tốt hơn hẳn — người dùng muốn iPad như vậy.

## Proposed outcome — kết quả mong muốn

- iPad dùng ngôn ngữ của bản Mac: sidebar kính nổi (thư viện, nguồn, album, tiện ích), toolbar kính ở trên,
  inspector bên phải, lưới dày; Editor/Video Studio dạng cột inspector như Mac.
- Vẫn là app cảm ứng: vùng chạm ≥ 44pt, chữ cỡ iPad, nhấn giữ thay chuột phải, không phụ thuộc hover; bàn phím,
  trackpad, Pencil là phần thêm.
- Dọc 1032×1376: sidebar thu thành lớp phủ, inspector thành sheet; không mất chức năng nào.
- Đủ mọi màn iPad hiện có (app, Editor ngang + dọc, Video Studio ngang + dọc).

## Affected users and systems — phạm vi ảnh hưởng

- Thiết bị: iPad (mọi cỡ, ngang và dọc, Split View/Stage Manager). iPhone và Duo nhận phần chung (nguồn, nhập thẻ, Compare,
  Viewer sáng/tối, lệnh ⋯ thêm) — chốt ở `/spec` 2026-10-04.
- Features: gần như mọi màn ở `Features/` có nhánh regular width; `RootTabView` (tab bar → sidebar), Editor,
  Video Studio. Không đụng dữ liệu đã lưu.
- Liên quan: DESIGN.md §10.1c (màn rộng), §10.1f (Settings split view), intent Mac `2026-10-04-macos-app.md`
  (dùng chung ngôn ngữ, có thể chung view).

## Constraints — ràng buộc

- Phone has every iPad feature — đổi bố cục iPad không được làm mất chức năng ở iPhone, và ngược lại.
- Nhánh iOS 26 / trước 26 vẫn chạy (iPad trước 26 không có Liquid Glass).
- Tier D, amber, kiểu biểu đồ C giữ như DESIGN.md.
- Design trước code: canvas iPad vẽ xong và được duyệt trước khi sửa màn nào.

## Open questions — câu hỏi còn treo

| Câu hỏi | Mặc định đề xuất | Ai trả lời |
|---|---|---|
| Có bỏ thanh tab nổi ở đáy trên iPad không? | **chốt: bỏ**, sidebar thay tab bar (board đã vẽ vậy) | người dùng |
| iPad có thêm nguồn thư mục (Files/ổ ngoài) như Mac không? | **chốt 2026-10-04: có, cùng lúc với Mac** (cùng mô hình hash + .xmp + nhập thẻ) | người dùng |
| Split View 1/3 màn hình dùng bố cục nào? | bố cục iPhone | /spec |
| Dùng chung view SwiftUI với bản Mac? | có, khi intent Mac sang /plan | /plan |

## Spec phải sửa khi sang /spec (người dùng chốt 2026-10-04: "theo board, sửa spec")

- FS-01.08 Compare: thành chế độ 2-Up/Survey của Viewer trên **mọi thiết bị**, Pick/Reject, không còn tầng D.
- FS-11b: iPad xuất collage dùng inspector 360 và Share… / Save to Photos trên toolbar (thay cột 400 + nút ghim đáy).
- FS-12.03/03b/16: số Video Studio iPad mới (pool 320, inspector 360, đầu track 200, sheet xuất 700) — phiên Video Studio nhận làm.
- FS-08: Settings iPad là split view mới; công tắc **không** amber (giữ AC-9).
- Thêm nguồn thư mục/ổ ngoài + nhập thẻ cho iPad (dùng chung FS của intent Mac).
- Server trên iPad là **nguồn được index** như Mac (chốt 2026-10-04) — FS-15/FS-17 phần iPad đổi theo; iPhone giữ duyệt rồi nhập.
- Settings iPad: nút chữ dùng **tint hệ thống**, không amber (giữ AC-9); công tắc xanh hệ thống.
- Lần mở đầu trên iPad: **Onboarding rồi tới thư viện trống** có 3 cách thêm nguồn (FS-09 phần iPad).

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
