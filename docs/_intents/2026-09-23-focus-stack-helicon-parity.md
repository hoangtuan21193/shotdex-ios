# Intent: Focus stack ngang Helicon Focus

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan@karabiner.tech |
| Ngày | 2026-09-23 |
| Trạng thái | accepted |
| Tiến độ | **chưa làm** (2026-09-24) — spec FS-01.10, 14 AC; plan [2026-09-24-fs-01-10-focus-stack](../_plans/2026-09-24-fs-01-10-focus-stack.md), 9 task |
| Nguồn | phản hồi người dùng — *"tôi chỉ cần focus stack thôi, tôi muốn làm như app Helicon Focus"* |
| Spec sinh ra từ đây | [FS-01.10](../02-functional-spec/FS-01-library/10-focus-stack.md) |

## Problem — vấn đề

Người chụp macro, và người chụp phong cảnh muốn nét từ tiền cảnh tới vô cực, bấm một chuỗi 10–200 khung
bằng tính năng focus bracketing của máy hoặc bằng ray trượt. Hôm nay họ ghép chuỗi đó bằng Helicon Focus
hoặc Zerene trên máy tính. Mode Focus Stack của ShotDex chưa thay thế được hai app đó:

- **Căn khung chỉ theo phép dịch**
  ([PhotoStackRenderer.swift:240](ShotDexKit/Render/PhotoStackRenderer.swift:240); FS-01.09 §3 ghi đây là
  chủ ý). Ống macro khi đổi điểm nét thì đổi luôn độ phóng (focus breathing). Căn chỉ theo phép dịch thì
  mép vật thể bị nhoè hoặc có quầng ở những khung xa khung gốc.
- **Chỉ có một cách ghép**: mỗi điểm lấy khung nét nhất, bản đồ độ nét dựng bằng Laplacian 3×3 rồi làm
  mờ bằng box blur bán kính cố định 6
  ([PhotoStackRenderer.swift:178](ShotDexKit/Render/PhotoStackRenderer.swift:178)). Không có tham số nào
  cho người dùng chỉnh, không có cách ghép thứ hai cho vùng tóc, lông, vật chồng lên nhau, không có cách
  sửa tay một vùng bị ghép sai.
- **Không nói ra khung bị bỏ**: khung nào tải bản xem trước hỏng thì bị bỏ qua, không báo
  ([PhotoStackScreen.swift:152](ShotDex/Features/Editing/PhotoStackScreen.swift:152)).
- **Chuỗi dài chưa được đo**: preview giữ mọi khung ở 1600pt trong RAM. Lúc lưu, app nạp dữ liệu gốc
  của mọi khung rồi mới ghép
  ([PhotoStackScreen.swift:186](ShotDex/Features/Editing/PhotoStackScreen.swift:186)). Với 100 khung
  45 MP, chưa ai đo bộ nhớ và thời gian. Tiêu chí nghiệm thu của FS-01.09 cũng còn **chưa viết**.

Mức độ: tính năng có, nhưng chưa đủ tin để giao cho người chụp macro nghiêm túc — đúng nhóm người
dùng tự nêu ra.

## Proposed outcome — kết quả mong muốn

- Một chuỗi focus bracketing chụp bằng ống macro thật ra một ảnh nét suốt chiều sâu. Mép vật thể không
  có quầng, và không có bóng ma do ống kính đổi độ phóng giữa các khung.
- Có đủ cách ghép và tham số mà người quen Helicon Focus tìm đến. Xem được kết quả trước khi lưu, đổi
  cách ghép mà không phải nạp lại khung.
- Sửa được vùng ghép sai bằng cách chỉ ra khung nào nét đúng ở vùng đó.
- Chuỗi dài (tới hàng trăm khung) chạy được mà bộ nhớ không tăng theo số khung. Khung nào không dùng
  được thì được nói ra.

## Affected users and systems — phạm vi ảnh hưởng

- **Màn hình**: màn Focus Stack (hiện là `PhotoStackScreen` ở mode Focus Stack); lối vào theo intent
  menu mục đích.
- **Thiết bị**: iPhone, iPad, Duo — cùng bộ chức năng.
- **Tầng code**: phần ghép trong ShotDexKit; màn hình trong Features. Dùng lại được các mảnh của FS-14:
  đọc khung qua ánh xạ file, ghi JPEG theo luồng, render theo dải.
- **Dữ liệu đã lưu**: không. Ảnh ra là một asset mới, như hiện nay.

## Constraints — ràng buộc

- Local-only, **không thêm dependency**: chỉ Vision, Core Image, Accelerate, Metal.
- Bộ nhớ phẳng theo số khung và kích thước ảnh (bài học từ spike panorama: HEIC giữ cả ảnh trong RAM,
  JPEG ghi được theo luồng).
- Kit purity: không SwiftUI/GRDB trong ShotDexKit.
- Không làm hỏng ba mode còn lại (Average, Lighten, Darken) đang dùng chung renderer.
- Mọi so sánh với Helicon/Zerene dẫn nguồn trang tài liệu thật (câu 1); không lấy từ trí nhớ.
- Tô sửa cần nhớ **khung nào thắng ở từng điểm ảnh** mà vẫn giữ bộ nhớ phẳng — spike phải chứng minh.

## Open questions — câu hỏi còn treo

1. ~~Tính năng v1~~ — **chốt 2026-09-23**, sau khi tra Helicon Focus 8 User Guide
   (heliconsoft.com/focus/help/english/HeliconFocus.html) và Zerene Stacker (zerenesystems.com/cms/stacker/docs/howtouseit):
   - **căn khung có co giãn + xoay** — co giãn là thứ Helicon dùng cho focus breathing; xoay là thành phần nhỏ;
   - **hai cách ghép**: cách hiện có (kiểu Helicon B / Zerene DMap — mượt, giữ màu, hợp chuỗi dài) và **trung
     bình có trọng số độ nét** (kiểu Helicon A / Zerene PMax — lông, tóc, chi tiết đan chéo);
   - **Radius và Smoothing** thành tham số người dùng chỉnh; mặc định lấy từ spike (không hãng nào công bố số);
   - **tô sửa từ một khung**: chỉ ra khung nét đúng cho một vùng.
   - Không làm ở v1: cách ghép kiểu pyramid (Helicon C), xuất bản đồ độ sâu, 3D, batch, Dust Map, DNG.
   - Trang Photoshop và Affinity không tải được (403) — không so với hai app đó.
2. ~~Trần số khung~~ — **chốt 2026-09-23: không trần**; trên một ngưỡng thì báo ước lượng thời gian trước
   khi ghép, như FS-14.
3. ~~Định dạng ảnh ra~~ — **chốt 2026-09-23: JPEG**, ghi theo luồng như panorama.
4. **Dữ liệu thử**: panorama dựng được khung ảo có đáp án từ ảnh 360°. Focus stack cần một chuỗi có độ
   sâu thật. Mặc định đề xuất: dựng khung ảo từ một ảnh CC0 kèm bản đồ độ sâu (làm mờ theo độ sâu từng
   khung + co giãn giả lập focus breathing), cộng một chuỗi thật có giấy phép mở nếu tìm được. → spike.
   **2026-09-24:** chỉ có khung ảo; chưa tìm được chuỗi thật có giấy phép mở — ghi ở §6 của spike.
5. ~~Spike~~ — **chốt 2026-09-23: có, chặn trước `/spec`** — đo căn khung có co giãn, các cách ghép đã chốt
   ở câu 1, và bộ nhớ ở 100 khung. Dữ liệu theo câu 4.
   **Kết quả 2026-09-24:** [2026-09-24-focus-stack-spike.md](2026-09-24-focus-stack-spike.md) — căn có co giãn là bắt
   buộc (chỉ dịch: 17,7 dB, kém khung đơn; có co giãn: 35 dB ở breathing 2%); hai cách ghép và bộ nhớ phẳng theo số khung làm được.
6. ~~Thứ tự với intent menu mục đích~~ — **chốt 2026-09-23: menu làm trước**
   ([2026-09-23-combine-photos-purpose-menu.md](2026-09-23-combine-photos-purpose-menu.md)).

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
