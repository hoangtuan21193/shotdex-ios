# FS-11 — Collage

`FS-11` · tier D · `Features/Collage/` · `Domain/Collage/` · test `CollageTemplateCatalogTests`
· `CollageGeometryTests` · `CollageLayoutTests` · cập nhật 2026-09-22

**Một câu:** ghép 2–9 ảnh thành một ảnh mới theo khung mẫu, rồi xuất ra thư viện như một ảnh thật.

## 1. Quy tắc

- **Khung từng ô tính bằng một bộ toán duy nhất, dùng chung với lúc xuất** — nên cái nhìn thấy đúng bằng
  cái xuất ra.
- Giảm số ô **không xoá ảnh** — ảnh bay vào khay.
- **Ba cử chỉ tách bạch**, và **không phải chọn trước rồi mới làm**.
- Công thức collage sống **trong bộ nhớ**; nó chỉ được lưu khi người dùng xuất
  ([FS-06.01b](FS-06-collections/01b-album-management-and-creations.md)).

## 2. Lối vào

Chế độ chọn ở Library, album hay smart album → tile **Collage** trên thanh chọn (2–9 **ảnh**) → mở toàn màn
với đúng danh sách ảnh đó.

Từ Library thì sau khi lưu sẽ **mở ảnh mới** trong viewer; từ album thì chỉ đóng màn.

## 3. Bố cục

Tier D, **không có hàng Cancel/Save ở trên**.

| Vùng | Chi tiết |
|---|---|
| Hàng lệnh nổi | ngang tai thỏ — trái: Undo · Redo · giữ-xem-bản-gốc (ba nút tròn 34); phải: ô trạng thái `N of M · tỉ lệ` + ⋯ (menu Discard) |
| Khay ảnh chưa đặt | ảnh mang sang chưa xếp vào ô nào; **ẩn khi rỗng**; cao 48, nở **56** khi đang giữ ảnh (viền đứt vàng, thumbnail mờ, chữ `Drop here to set aside`) |
| Khung dựng | rộng tối đa **353** ở điện thoại, căn giữa vùng trống; không có khay thì dịch lên |
| Panel | cao đúng **216** ở cả ba tab = 152 nội dung + 54 thanh dưới (ba tab + nút Export) + 10 vùng an toàn |

**Từ 700pt bề rộng cửa sổ: panel đáy thành inspector cạnh phải.**

- Rộng **320pt**, gồm hàng tab **ở trên cùng** kèm nút Back, nội dung cuộn ở giữa, và **Export ghim đáy**.
  Khung dựng lấy toàn bộ chiều cao.
- Tab nằm **trên** (không phải dưới như bản điện thoại) vì trong một cột dọc, tab ở đáy là tab **xa nhất**
  khỏi phần nó điều khiển.
- 216pt dán dưới một khung dựng 900pt trên iPad đọc như một sheet của điện thoại bị đóng đinh vào màn to.
- Cột nội dung dùng **chung một bộ dựng** cho cả hai bố cục nên khung dựng, khay và hàng lệnh chỉ có một bản.
- **Bỏ trần 353 ở màn rộng**: 353 là bề rộng nội dung của iPhone viết ra thành số, để nguyên trên một khung
  1032pt thì collage thành con tem giữa màn đen.
- **Ngưỡng đo theo bề rộng cửa sổ, không theo loại thiết bị**: nửa màn iPad vẫn được hệ thống coi là "rộng"
  ở ~500pt, mà ở đó một inspector 320pt để khung dựng hẹp hơn cả trên điện thoại.
- **Chrome nở ở màn rộng**: ô khung mẫu 52 → **68** (ô đó là *hình vẽ một bố cục*, 52pt thì không đọc được
  nó đang mời gì) · bộ đếm và nút lưu preset 32 → **44** · nút Export 38 → **48** · nút lệnh tròn 34 → **44**.
  Chip tỉ lệ giữ 28pt về hình nhưng **vùng chạm nở 44** (hàng chỉ cao 34 nên đóng khung 44 thật sẽ đẩy ba
  tầng panel ra). Ở điện thoại, hai nút ± giữ hàng 32pt nhưng vùng chạm vẫn nở lên 44.

## 4. Khung dựng và cử chỉ

| Cử chỉ | Kết quả |
|---|---|
| Kéo thẳng trên ảnh | **dời ảnh trong ô** (pinch để phóng, có nhãn phần trăm) — **không** cần chọn trước |
| Giữ 0,3 giây rồi kéo | **nhấc cả ô** (bản chụp nổi lên, hơi to, hơi nghiêng, viền vàng) |
| Thả lên ô khác | **đổi chỗ hai ô** (ô đích phủ accent + mũi tên) |
| Thả lên khay | cất ảnh sang một bên |
| Kéo từ khay xuống ô | thay ảnh trong ô |

Ô trống là **nền giấy có viền** kèm chữ `Add photo`, chạm để mở ô chọn ảnh. Có haptic khi chọn và khi thả.

**Bộ đếm ảnh** `[− N +]` (2–9): tăng là thêm **ô trống**; giảm là ảnh cuối **bay vào khay** (không xoá) kèm
một thông báo hoàn tác; nút `−` mờ khi còn 2 ô.

**Nhận ảnh thả từ app khác**: ảnh đầu vào đúng ô được thả, phần còn lại vào khay (không đè ô người dùng
không nhắm); có nhãn "Adding to your library…" trong lúc chạy, và app **nói ra** đã thêm bao nhiêu ảnh vào
thư viện.

## 5. Khung mẫu, tỉ lệ, ô chọn ảnh, preset

- **Khung mẫu là một cây chia đôi**: mỗi mẫu là một cây gồm trục chia, tỉ lệ và các nhánh con; lá là một ô.
  Danh mục sinh ra **33 mẫu** cho 2–9 ảnh.
- **Đường chia giữa hai nhánh kéo được**: một dải nắm 24pt nằm đè lên các ô; kéo thì tỉ lệ đổi nhưng **tổng
  không đổi và các nhánh khác đứng yên**, có **sàn 15%** và **hút nhẹ về 1/3, 1/2, 2/3** khi thả; chạm đôi
  để trả về mặc định. Tỉ lệ đã chỉnh lưu theo từng nút của cây và **bị xoá khi đổi mẫu hoặc đổi số ô**.
  Đường đang kéo vẽ dày 3pt màu accent kèm tay nắm 14×46, **không hiện số**.
- **Tỉ lệ khung**: `Custom` đứng đầu (một bảng nhỏ nhập rộng×cao, đảo chiều, có xem trước ngay khi gõ), rồi
  1:1 · 4:5 · 5:4 · 2:3 · 3:2 · 9:16 · 16:9 · A4 · Letter · 5:7 · 21:9. Công thức giữ **tỉ lệ thật** cộng
  tên preset (rỗng nghĩa là tự nhập).
- **Ô chọn ảnh**: sheet lớn đè lên collage đã mờ, có các tab Recents / Favorites / Selected N / Screenshots,
  lưới 3 cột, vòng số vàng, chân sheet ghi `N selected · M slots left`. **Chọn tối đa bằng số ô trống**, và
  ảnh lấp ô vừa chạm trước rồi tới các ô trống còn lại.
- **Preset** lưu **khung và kiểu, không lưu chữ hay ảnh**: chip preset đứng đầu dải khung mẫu, vẽ **trung
  tính kèm dấu sao** (accent chỉ dành cho mẫu đang áp); chạm để áp (mẫu chỉ áp khi số ô khớp), giữ để đổi
  tên hoặc xoá; nút lưu preset nằm ở hàng bộ đếm.

## 6. Kiểu và chữ

- **Tab Style**: hàng `Border · Gap · Corner` (tính theo phần của cạnh ngắn); dải nền 34×28 (trắng / đen /
  xám / tự chọn màu / **ảnh làm mờ**) — nền mờ lấy từ **ảnh đang chọn**, có slider độ mờ và độ tối; công tắc
  **Polaroid** (tấm trắng + bóng đổ + chú thích).
- **Tab Text**: **Title** là một dòng chữ tự do (không có token EXIF) **tách khỏi** **Captions** (mỗi ô một
  dòng, chỉ có khi bật Polaroid; tự gõ, không tự điền EXIF).
- **Vẽ viền khung dựng**: phần thừa được tô bằng màu nền (mặc định đen) mà khung dựng cũng đen, nên một ảnh
  3:2 trong khung 16:9 trông **đúng như một collage 3:2** — người dùng không nhìn thấy cái khung mình sắp
  xuất. Một nét mảnh 1pt vẽ đúng vùng nội dung giải quyết việc đó.

## 7. Công thức và render

Công thức giữ: mẫu · tỉ lệ khung và tên preset tỉ lệ · khe hở · bo góc · viền và màu viền · nền (màu, chế
độ, độ mờ, độ tối, ảnh nguồn) · cờ Polaroid · danh sách ô (ảnh, mức phóng, độ lệch, chú thích) · lớp chữ ·
và các tỉ lệ chia đã kéo tay.

- **Sống trong bộ nhớ**; ô không có ảnh nghĩa là ô trống. Model giữ thêm kho ảnh của phiên (mở rộng dần khi
  thêm ảnh), khay, và ngăn xếp hoàn tác.
- Bộ ghép vẽ bằng lớp đồ hoạ nền: viền, chú thích, và làm mờ nền. Polaroid vẽ tấm trắng + bóng + ảnh thụt
  vào + chú thích. Ô thiếu ảnh **để hở nền**. Lớp chữ vẽ sau cùng.

## 8. Xuất

Màn xuất toàn màn: nền là chính ảnh ghép đã làm mờ và tối, bản xem trước thật ở trên, và một thẻ kính chứa
5 hàng — **Size (Fit/2K/4K/Max) · Quality 0–100 · Format JPEG/HEIC · Keep EXIF of first photo · dung lượng
ước tính**. Nút `Save to Photos` cao 50.

Lưu → index → thêm vào album người dùng **`ShotDex Collages`** (tạo nếu chưa có) → báo cho lưới → màn gọi
lại nơi mở nó và đóng.

Tên album là `ShotDex Collages` chứ không phải `Collages`: tab Collections đã có một hàng Utilities tên
`Collages` là *project mở lại được*, nên một album người dùng cùng tên trên cùng màn là một cái tên hai
nghĩa. Album `Collages` do bản cũ tạo vẫn được nhận và ghi tiếp nếu còn.

## 9. Lệch so với thiết kế đã ghi

- Hiệu ứng ảnh bay theo đường cong khi giảm số ô rút gọn thành chèn + nháy.
- Chú thích ghi thẳng vào công thức (không đánh dấu "đã sửa").
- Bo góc của thẻ Export dùng mức 16 theo tỉ lệ thay vì 20.

## 10. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../README.md#6-việc-còn-nợ).
