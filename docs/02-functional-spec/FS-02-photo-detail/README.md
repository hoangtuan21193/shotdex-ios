# FS-02 — Photo Detail

`FS-02` · tier C · `Features/Library/PhotoDetailScreen.swift` · `MetadataPanel.swift`
· test `MetadataFormatterTests` · `VideoTransportMathTests` · `VideoTrimMathTests` · cập nhật 2026-09-22

**Một câu:** màn xem một ảnh hoặc một clip — lật trang, phóng, đọc thông số, và mọi hành động trên tấm ảnh đó.

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 01 | [Pager và tải ảnh](01-pager-and-image-loading.md) | lật trang, phóng, thang chất lượng ảnh, iCloud, nhường băng thông |
| 01b | [Đóng viewer và bàn phím](01b-closing-and-keyboard.md) | đóng thì lưới tới ảnh vừa xem, Esc, ← / → |
| 02 | [Video](02-video-playback.md) | trạng thái phát, transport, cử chỉ, tua, lưu khung, toàn màn |
| 03 | [Bảng thông tin](03-info-panel-and-metadata.md) | hai dòng trên chrome, sheet đầy đủ, shutter count, dữ liệu thô |
| 03b | [Photo Info ở màn rộng](03b-info-inspector.md) | cột bên phải trên iPad ngang và Duo trong, khi nào là cột khi nào là sheet |
| 04 | [Hành động và phụ trợ](04-actions-and-extras.md) | menu ⋯, slideshow, Live Photo, Live Text, panorama, cắt video |
| 05 | [Chọn khung trong burst](05-burst-selection.md) | chọn khung giữ, xoá phần còn lại, gợi ý khung, PhotoKit cho phép gì |
| 06 | [Bản gốc trên iCloud](06-icloud-originals.md) | bản gốc có trên máy chưa, tải có %, chuẩn bị bản gốc trước khi sửa hàng loạt/xuất/Resize/Share, không xuất bản xem trước |
| 07 | [Caption và keyword](07-caption-and-keywords.md) | iOS 27: sửa caption/keyword ở đầu Info và hàng loạt từ chế độ chọn, lọc/tìm/smart album theo keyword Photos, không theo Share |

## Quy tắc

- **Mở viewer theo id của ảnh, không theo vị trí bắt được từ lưới.** Vị trí bắt đầu được hỏi lại từ chính
  nguồn mà viewer dùng. Giữ một số thứ tự sẽ **mở nhầm ảnh** sau khi một ảnh bị xoá khỏi danh sách, còn tra
  lại vị trí ở mỗi lần vẽ sẽ cho **màn hình đen** khi xoá đúng ảnh đang xem.
- **Không hiển thị giá trị không tồn tại.**
- Mọi thứ đắt (giải mã, tải) chỉ chạy cho **trang đang hiện**, không chạy cho trang nạp trước.
- **Viewer có bộ điều phối hành động riêng**: nó là một lớp phủ toàn màn, mà hai nơi cùng bám một trạng thái
  trình bày thì cả hai đều mở — và sheet của màn gốc thắng bằng cách gỡ luôn lớp phủ.
- **Đóng viewer không được làm Library nạp lại** — xem [01](01-pager-and-image-loading.md).
- **Đóng viewer thì lưới tới ảnh vừa xem**; Esc đóng, ← / → lật ảnh — xem [01b](01b-closing-and-keyboard.md).

## Chrome

| Vị trí | Nội dung |
|---|---|
| Trên-trái | nút **X** cao 52pt, và **bảng thông tin ngay bên phải, cùng hàng** (regular width: rộng tối đa 520pt) |
| Đáy | ba vùng kiểu Photos: **Share** tròn trái · viên kính giữa · **Delete** tròn phải |
| Viên kính giữa | Favorite · Info · (ảnh: Edit) · ⋯ — video ẩn Edit và Resize |

- Toàn bộ chrome ẩn khi: **chạm 1 lần** (§8), đang phóng, video đang xem toàn màn, hoặc video đang phát và đã 3 giây không chạm.
- **Một hàng ngang, không phải viên kính căn giữa bằng cách xếp chồng**: viên kính nở theo số hành động của
  tấm ảnh; xếp chồng thì nó đè lên Share và Delete — bảy control đòi 288pt trong khe 234pt của máy 402pt.
- Icon trong viên kính **40×40, padding 4**, kèm bề rộng tối thiểu để máy hẹp bóp lại thay vì tràn.
- Chiều cao thanh đáy được **đo thật**; với video cộng thêm vùng an toàn và **40pt** chừa để transport nằm
  hẳn trên nó.
- **Status bar đi theo chrome**: bình thường vẫn hiện với chữ trắng, chỉ ẩn cùng toàn bộ chrome.

## Cử chỉ

| Cử chỉ | Kết quả |
|---|---|
| Vuốt ngang | lật ảnh |
| Pinch / chạm đôi | phóng; vượt 1,01 lần mới bật kéo bên trong |
| Vuốt xuống | đóng viewer — chỉ nhận khi **hướng xuống rõ ràng** và **chưa phóng** |
| Vuốt lên | mở Photo Info, giống bấm nút Info — sheet, hoặc cột bên phải ở cửa sổ ngang ≥ 700pt ([03b](03b-info-inspector.md)) |
| Giữ tay (ảnh đã chỉnh) | hiện **bản gốc** + nhãn "Original" ([04](04-actions-and-extras.md)) |

## 8. Đợt giống Photos (2026-11-13)

Nguồn: [intent](../../_intents/2026-11-13-viewer-like-photos.md) · bằng chứng
[Photos RE](../../_research/2026-11-13-photos-viewer-loading-re.md) · quyết định `.planboard/viewer-photos`. Thay các dòng
mâu thuẫn ở *Chrome* và *Cử chỉ* phía trên.

**Chạm để ẩn chrome** (D1, D3, D4):
- **Một cờ `chromeHidden` cho cả viewer.** Chạm 1 lần (ảnh hoặc video) đảo cờ. Ẩn: nút X, bảng thông tin, thanh đáy,
  transport video, nhãn Live/Original, status bar, vạch home. **Giữ** vòng tải iCloud nhỏ ở góc khi đang tải.
- Chạm 1 lần đợi nhấn đúp hỏng (≈0,25 s) — nhấn đúp vẫn phóng (ảnh) / tua ±10 s (video).
- Cờ **giữ khi vuốt sang ảnh khác**; mở viewer lần sau thì hiện chrome.
- Phóng to vẫn ẩn chrome như cũ; về 1× thì chrome theo lại cờ.
- Video: chạm **không còn dừng video**; dừng/phát bằng nút ở giữa; đang phát thì chrome tự ẩn sau 3 s như cũ (đặt cờ).
- Thao tác cần chrome (vuốt lên mở Info, phím `i`, menu) vẫn chạy khi đang ẩn; mở Info thì chrome hiện lại.

**Nền** (D2): chrome hiện → nền theo sáng/tối hệ thống (`systemBackground`); chrome ẩn → đen. Chuyển 0,25 s.
Video phát trên nền đen ở cả hai trạng thái (transport của nó vẽ cho nền tối).
Nút kính và bảng thông tin đọc được trên cả hai nền. Vuốt xuống đóng: nền mờ dần theo khoảng kéo.

**Mở / đóng** (D5): mở từ lưới là ảnh **phóng ra từ ô**; đóng (X hoặc vuốt xuống) thì ảnh **thu về ô của ảnh đang xem**;
ô đó ngoài màn thì lưới cuộn tới trước khi thu (FS-02.01b §1). Mọi màn dùng lưới chung (Library, album, smart album,
On This Day, Hidden, On This iPhone). iOS 17 dự phòng: chuyển cảnh mặc định, vẫn cuộn tới ảnh.

**Tốc độ** (D6, A1–A5):
- Chuẩn bị sẵn **±2** ảnh quanh ảnh đang xem, cỡ màn hình, **đã giải mã** (không giải mã lúc vẽ).
- Ảnh gốc khi phóng to **không vào** cache ảnh màn hình.
- Ảnh về sau khi request đã huỷ vẫn được giữ trong cache → vuốt lại hiện ngay.
- iOS báo thiếu bộ nhớ → xoá ba cache ảnh (viewer, lưới, bìa album).
- Lưới: preheat phía trước theo hướng cuộn — **đã có** qua `UICollectionViewDataSourcePrefetching` của lưới (UIKit báo đúng các ô sắp hiện theo hướng cuộn, warm đúng kích thước ô); không thêm lớp thứ hai (2026-11-14, khi code A5).

**Spec có mà code thiếu** (A6): Esc đóng viewer; *Caption & Keywords…* trong menu ⋯ (iOS 27).

## Tiêu chí nghiệm thu

Phần cũ chưa có AC — xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ). Đợt §8:

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | ảnh bất kỳ, chrome hiện | chạm 1 lần giữa ảnh | sau ≤ 0,4 s không còn X, bảng thông tin, thanh đáy, status bar; nền đen | ⚠️ ui-drive dump + screenshot |
| AC-2 | như AC-1, chrome ẩn | chạm 1 lần | mọi control hiện lại; nền theo sáng/tối | ✅ iPad 26.5 v3→v4 |
| AC-3 | chrome ẩn | vuốt sang ảnh kế | ảnh kế vẫn ẩn chrome | ✅ iPad 26.5 v2→v3 |
| AC-4 | ảnh | nhấn đúp | phóng ×2,5, chrome không bật lên giữa chừng | ⚠️ ui-drive |
| AC-5 | video đang phát | chạm 1 lần | video vẫn phát; chrome đảo | ⚠️ ui-drive |
| AC-6 | ảnh iCloud đang tải, chrome ẩn | nhìn góc | vòng tải vẫn hiện | ⚠️ screenshot |
| AC-7 | giao diện sáng | mở viewer | nền trắng, nút kính đọc được; tối → nền đen | ✅ iPad 26.5 sáng + tối |
| AC-8 | lưới, ô thứ 30 | chạm ô | ảnh phóng ra từ khung ô (iOS 18+) | ⚠️ screenshot burst |
| AC-9 | mở ô 5, vuốt tới ảnh 40 (ngoài màn) | đóng | lưới cuộn để ô 40 thấy trọn, ảnh thu về ô 40 | ⚠️ ui-drive dump |
| AC-10 | iOS 17/18.6 | mở/đóng | không crash, đóng vẫn cuộn tới ảnh | ⚠️ sim 18.6 |
| AC-11 | `requestDetailImage` với `PHImageManagerMaximumSize` | xong | không có mục nào vào `detailImageCache` | ✅ `ViewerLoadingTests.maximumSizeIsNotACacheableDisplaySize` |
| AC-12 | viewer ở ảnh n | — | ảnh n±1, n±2 đã được yêu cầu preheat cỡ màn hình | ✅ `ViewerLoadingTests.preheatsTwoEachSideNearestFirst` |
| AC-13 | ảnh đã về sau khi request huỷ | mở lại ảnh đó | hiện từ cache, không request mới | ⚠️ unit test |
| AC-14 | cache có ảnh | gửi memory warning | ba cache rỗng | ⚠️ unit test |
| AC-15 | lưới cuộn xuống | — | ô sắp hiện được warm trước (prefetch UIKit có sẵn) | đã có — `prefetchItemsAt` |
| AC-16 | viewer, bàn phím | Esc | viewer đóng | ⚠️ ui-drive `key` |
