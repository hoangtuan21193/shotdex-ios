# Vòng 1 — Viewer và tải ảnh giống Photos

Không còn gì cần sửa: có thể chốt plan.

## Đồng ý mặc định (không bấm gì) (14)

- **D1** Khi ẩn nút, ẩn những gì? — trang chrome
  - Lựa chọn: Ẩn hết, chỉ giữ vòng tải iCloud khi đang tải (all)
- **D2** Lúc đang hiện nút, nền viewer màu gì? — trang chrome
  - Lựa chọn: Theo sáng/tối, ẩn nút thì đen (như Photos, như board) (system)
- **D3** Đã ẩn nút rồi vuốt sang ảnh kế: ảnh kế vẫn ẩn nút? — trang chrome
  - Lựa chọn: Vẫn ẩn (như Photos) (persist)
- **D4** Chạm vào video đang phát thì làm gì? — trang chrome
  - Lựa chọn: Chạm = ẩn/hiện nút (như Photos) (toggle)
- **D5** Mở ảnh từ lưới: ảnh phóng ra từ chính ô đó (như Photos) hay trượt từ dưới lên như hiện nay? — trang open
  - Lựa chọn: Phóng từ ô + thu về đúng ô (zoom)
- **D6** Chuẩn bị sẵn bao nhiêu ảnh hai bên ảnh đang xem? — trang speed
  - Lựa chọn: 2 mỗi bên, giải mã sẵn (two)
- **A1** Sửa lỗi cache khi phóng to — Claude tự quyết
  - Claude đã chọn: Ảnh gốc khi phóng to không còn bị nhét vào bộ nhớ đệm ảnh màn hình (nó đẩy các ảnh khác ra, nên quay lại ảnh trước phải tải lại).
- **A2** Giải mã ảnh ngoài luồng chính — Claude tự quyết
  - Claude đã chọn: Ảnh màn hình và ảnh nhỏ được giải mã trước khi hiện, không giải mã lúc vẽ.
- **A3** Giữ ảnh vừa xem khi lỡ huỷ — Claude tự quyết
  - Claude đã chọn: Vuốt qua rồi vuốt lại ngay: ảnh hiện tức thì, không tải lại.
- **A4** Máy thiếu bộ nhớ thì dọn cache — Claude tự quyết
  - Claude đã chọn: Khi iOS báo thiếu bộ nhớ, ShotDex xoá cache ảnh viewer/lưới/bìa album thay vì để app bị tắt.
- **A5** Lưới chuẩn bị trước theo hướng cuộn — Claude tự quyết
  - Claude đã chọn: Lưới tải sẵn một khoảng hàng phía trước theo hướng cuộn, như Photos, thay vì chỉ nhờ UIKit báo.
- **A6** Thêm vài chỗ spec đã có mà code thiếu — Claude tự quyết
  - Claude đã chọn: Phím Esc đóng viewer; Caption & Keywords trong menu ⋯ (iOS 27).
- **A7** Quy trình — Claude tự quyết
  - Claude đã chọn: Intent + spec FS-02 cập nhật, board PH/IP/DI/DC_Viewer (sáng/tối, trạng thái ẩn nút) trên 4 canvas, rồi code mỗi tiêu chí một commit, build, kiểm trên simulator.
- **A8** Không mất chức năng — Claude tự quyết
  - Claude đã chọn: Giữ mọi nút và thao tác hiện có của viewer: chia sẻ, yêu thích, info, sửa, ⋯ (sao/cờ, cull, thêm vào bộ sưu tập, nhân bản, copy, Live Text, lưu Live thành video, cắt video, resize, export, chỉnh ngày/vị trí, giữ trên iPhone, bản đồ, xem panorama, burst, slideshow, ẩn), xoá, phím tắt, giữ để xem bản gốc, Live Photo, toàn bộ điều khiển video.
