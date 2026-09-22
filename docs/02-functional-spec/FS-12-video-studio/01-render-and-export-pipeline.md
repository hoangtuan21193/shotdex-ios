# FS-12.01 — Pipeline render và export

`FS-12.01` · `Data/Sources/VideoCompositionBuilder.swift` · `VideoFrameCompositor.swift`
· `VideoExportWriter.swift` · `Domain/Video/VideoGeometry.swift` · `VideoEffectMath.swift`
· cập nhật 2026-09-22

**Một câu:** một đường dựng duy nhất cho cả preview lẫn export, với một compositor tự viết — vì crossfade
cần thấy hai clip cùng lúc.

## 1. Quy tắc

- **Preview và export dùng chung một đường dựng.** Khác nhau đúng ở kích thước khung và ở đầu ra.
- **Không tin kích thước tự nhiên của track**: mọi phép biến hình đi qua một lớp hình học thuần, có test
  đủ bốn hướng xoay. Đây là nguồn bug số một của mã composition.
- Mốc thời gian dựng bằng **số nguyên ở biên giới builder** — hệ thống từ chối mọi khe hở hay chồng lấn,
  và cộng dồn số thực là crash kinh điển.
- **Ảnh cũng phải có một đoạn video thật làm xương sống** (xem §5).

## 2. Hai lối vào

| Lối vào | Mở ra |
|---|---|
| **Nhiều clip** — chế độ chọn → Create → **Video** (≥1 asset, nhận cả ảnh lẫn video, giữ thứ tự chọn) | Video Studio đầy đủ |
| **Một video** — nút Edit trên video ở Photo Detail | cùng màn với 1 clip; nhóm "Clips" đổi nhãn thành **Trim** và thêm Rotate |

Lưu xong đi qua đúng đường hiện-ảnh-vừa-lưu của viewer
([FS-02.01](../FS-02-photo-detail/01-pager-and-image-loading.md)).

## 3. Vì sao compositor tự viết

- Crossfade cần **thấy hai track cùng lúc**; bộ lọc theo-khung có sẵn của hệ thống là **một nguồn**, không
  bao giờ làm được.
- Có compositor rồi thì filter, chỉnh màu, overlay, xoay chỉ là thêm dòng trong phần vẽ mỗi khung — copy
  đúng chuỗi mà renderer Live Photo đã chứng minh chạy được ở tốc độ video.
- **Không tự ghi bằng writer từ đầu**: chỉ hơn ở điều khiển bitrate (ngoài phạm vi), mà mất live preview và
  phải tự trộn âm thanh — hàng trăm dòng và một mô hình thời gian thứ hai để sai.

## 4. Sắp track

- Video xếp **A/B xen kẽ** để hai clip cạnh nhau cùng tồn tại trong cửa sổ chuyển cảnh; âm thanh clip đi
  kèm A/B tương ứng.
- **Nhạc: mỗi bản một track riêng** — một track không insert chồng lên chính nó được. Đặt vị trí qua math
  thuần (clamp mốc vào ≥ 0, cắt đuôi ở hết video, **bỏ hẳn** bản bắt đầu ngoài video hoặc trim rỗng).
  Fade in/out và âm lượng **theo từng bản**, tính trong cửa sổ riêng của nó rồi dời theo mốc vào.
- **Không loop** — nhiều track đã thay việc đó.

## 5. Ảnh cần một xương sống video

Chèn một khoảng trống **không cộng thời lượng** cho track chưa có đoạn thật → project toàn ảnh ra thời
lượng 0 và player dừng ngay lập tức.

Cách làm: ghi **một clip đen 1280×720, 1 giây, 30fps** một lần mỗi phiên, chèn rồi giãn đúng thời lượng
ảnh — **chỉ khi project có clip ảnh**.

- Phải là clip **well-formed đủ GOP**, không phải stub 2 khung: bộ kiểm tra media lúc export từ chối stub.
- Chỉ dẫn render vẫn khai đây là khung tĩnh và **không** khai track đen là nguồn, nên hệ thống không decode
  nó; compositor vẽ từ kho khung tĩnh riêng (khoá, **LRU 4** — một khung BGRA cạnh dài 3840 ≈ **33MB**;
  nạp ngoài main và downsample theo kích thước khung).

## 6. Cắt đoạn và chuyển cảnh

- **Cắt theo MỌI mốc đặt clip**, không chỉ mép fade: danh sách mốc = 0 và tổng, cộng điểm đầu/cuối của mọi
  clip; mỗi cặp mốc kề thành một đoạn fade (nếu điểm giữa rơi trong cửa sổ fade) hoặc một đoạn thường.
  Chỉ cắt theo fade là bug đã dính: 3 clip nối liền dồn thành **một** đoạn và cả video chiếu clip giữa.
- **Chuyển cảnh gắn theo ranh giới**, số lượng = số clip − 1, tự đồng bộ khi thêm/bớt clip; reorder không
  cần đụng vì ranh giới tính **theo vị trí**.
- Độ chồng lấn bị clamp ba bước: ≥ 0 → ≤ nửa clip ngắn hơn của cặp → và một clip **không bao giờ nằm trong
  hai fade cùng lúc** (giữ được cách xếp A/B).
- Bảy kiểu: **none · crossfade · fadeBlack · slideLeft · slideRight · wipe · zoom**. fadeBlack là hai chặng
  qua đen; slide dịch cả hai khung; wipe dùng một gradient làm mặt nạ, mép mềm 5% bề rộng; zoom phóng khung
  ra 1→1,3 kèm hoà tan. Math thuần, có test.

## 7. Hiệu ứng theo clip

zoomIn/zoomOut (1↔1,12 quanh tâm khung) · panLeft/panRight (phóng sẵn 1,06 + dịch ±2% bề rộng nên đường đi
**không bao giờ hở mép**) · shake (lệch **tất định** theo số khung và chỉ số clip, biên độ 1% cạnh ngắn,
tắt dần trong 0,2s đầu và cuối) · blurIn/blurOut (12→0 trong tối đa 0,8s) · softGlow · vignettePulse.

- Áp **trước khi trộn, độc lập từng bên**: crossfade thấy blurOut của clip ra đấu với blurIn của clip vào,
  mỗi bên chạy trên đồng hồ đặt clip riêng — clip bị cắt qua nhiều đoạn vẫn chạy liên tục.
- Shake tất định nên **preview và export khớp từng khung** (cùng nhịp 1/30).
- **Hiệu ứng không bị đóng băng vào bản dựng**: nó được tra từ recipe tươi theo id clip, nên đổi hiệu ứng
  đi đường rẻ (thay bản dựng khung hình, không dựng lại cả composition).

## 8. Ba tầng dựng lại preview

| Đổi cái gì | Làm gì |
|---|---|
| Âm lượng · mute · fade | chỉ gán lại bản trộn âm thanh |
| Filter · overlay · hiệu ứng · chữ theo thời gian · xoay | chỉ dựng lại bản dựng khung hình |
| Cấu trúc (đổi thứ tự, trim, thời lượng, kiểu/độ dài chuyển cảnh, đổi nhạc, xoá clip, undo/redo) | dựng lại toàn bộ, **debounce 300ms**, giữ playhead |

- Preview giới hạn cạnh dài **1280** (chi phí compositor tỉ lệ số pixel); export dựng lại ở kích thước
  preset. Nhịp khung 1/30.
- **Hai bẫy khi thêm nhạc**: (1) asset nguồn của nhạc phải được **giữ sống qua cả lần dựng** — tham chiếu
  từ track về asset là yếu, asset chết thì chèn thất bại; (2) preview cũng phải **bỏ track âm thanh rỗng**
  như export — project ảnh-không-nhạc chạy im lặng được, nhưng thêm nhạc là bản trộn vào cuộc rồi đọc phải
  track rỗng và hỏng.

## 9. Export

**Đọc rồi ghi bằng tay, không dùng phiên export có sẵn**: phiên đó **từ chối compositor tự viết** — hỏng
với **mọi** preset, và đó là lỗi thật đằng sau triệu chứng người dùng báo *"chọn transition → Video error"*
(thực ra là bấm Export sau khi thêm transition).

- Đọc: một đầu ra video mang bản dựng khung hình (nên chạy đúng compositor) + một đầu ra âm thanh mang bản
  trộn. **Chỉ đưa vào track âm thanh có nội dung thật** — track A/B rỗng của project ảnh-không-nhạc làm
  bản trộn hỏng.
- Ghi: H.264 tại kích thước khung (bitrate ≈ số pixel × 4,8 → ~10 Mbps ở 1080p, ~40 Mbps ở 4K) + AAC 128k.
  Tiến độ = mốc thời gian / tổng. Cancel dừng đầu đọc.
- **Kích thước khung do bản dựng quyết định, không do preset.**
- Ra file tạm rồi nhập vào thư viện, index ngay, và phát tín hiệu để lưới thấy — video mới vào Library như
  asset thường (không có EXIF).

## 10. Tiêu chí nghiệm thu

Xem [README](README.md) — FS-12 là tài liệu duy nhất đã có bảng AC đầy đủ.
