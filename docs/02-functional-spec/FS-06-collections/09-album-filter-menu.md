# FS-06.09 — Menu Filter trong album

`FS-06.09` · tier B · `Features/Albums/AlbumDetailScreen.swift` · `SmartAlbumDetailScreen` · cập nhật 2026-09-25

**Một câu:** Album Detail (album người dùng, album hệ thống, Media Types) và Smart Album có **cùng một
menu Filter như Library**, thay cho nút Sort riêng. On This Day và Memories **giữ nguyên**.

## 1. Người dùng cần gì

Mở album "Đà Lạt 2025" gồm 400 ảnh rồi chỉ muốn xem những tấm đã đánh dấu yêu thích, hoặc chỉ video để
dựng clip. Hiện tại muốn làm vậy phải quay về Library và dựng lại điều kiện từ đầu.
Nút Filter đã có ở Library thì phải có ở mọi lưới ảnh, và các dòng trong menu phải giống nhau.

## 2. Phạm vi

**Có:**
- Menu Filter ở vị trí nút Sort cũ, cạnh `Select`. Vẫn hiện khi đang chọn, như Library. Khi đang chọn thì
  **ẩn nút Back** (thoát bằng ×, như Photos): có Back thì thanh 402pt không còn chỗ cho ×.
- Phần `Filter:`: All Items · Favorites · Photos Only / Videos Only (loại trừ nhau) · **Capture Kind ▸** ·
  **Advanced Filter…** (chỉ lọc trong album, §4).
- `Sort By ▸`: album người dùng **Album Order** · Newest First · Oldest First. Album không có thứ tự riêng
  (album hệ thống, smart album) thì không có Album Order.
- `Aspect Ratio Grid`: **cùng một thiết lập chung** với Library, bật ở đâu cũng áp cho mọi lưới.
- Smart Album có thêm **Sort By** (hiện chỉ xếp mới nhất trước). Thứ tự nhớ theo từng album, như FS-06.01b §3.

**Cố ý không có:**
- On This Day, Memories, People and Pets, Trips, Duplicates — các màn này có luật riêng; người dùng yêu cầu
  để yên.
- Sắp theo thông số chụp (ISO, tiêu cự…) — Library cũng không đưa lên menu.

## 3. Trạng thái màn hình

| Trạng thái | Điều kiện | Hiển thị |
|---|---|---|
| không lọc | All Items | như hiện nay, không có hàng chip |
| đang lọc | có lọc nhanh hoặc Advanced | hàng chip dưới thanh trên; chân lưới ghi `12 of 40 Items` |
| lọc ra rỗng | 0 ảnh khớp | câu `No photos match these filters.` + nút `Clear Filters` (xoá lọc, giữ Sort), đúng chữ của Library |
| album rỗng | album 0 ảnh | ẩn nút Filter, như ẩn Sort hiện nay |
| quyền giới hạn | `.limited` | biểu ngữ Limited Access + Manage của Library ở trên cùng; chỉ lọc trong số ảnh được cấp |

## 4. Hành vi

- Bật hoặc tắt một mục thì lưới nạp lại từ đầu và **cuộn về đỉnh**. Không giữ vị trí cuộn, vì danh sách
  đã khác.
- Photos Only và Videos Only loại trừ nhau; tắt mục đang bật thì trở về All Items. Luật y như
  [FS-01.05 §5](../FS-01-library/05-filtering-and-sorting.md).
- Capture Kind dùng **cùng định nghĩa** với Library, gồm cả Panoramas do ShotDex ghép (đọc từ index).
- **Hàng chip** giống thanh điều kiện của Library ([FS-01.02 §3](../FS-01-library/02-navigation-and-condition-bar.md)):
  mỗi mục đang bật là một chip có `x`, cùng nút **Clear** ghim mép phải.
  - Hàng chỉ có khi đang lọc. Lưới được trả lại đúng chiều cao hàng chip, như Library §4.
  - Smart Album: chip lọc nhanh **nối vào cùng hàng với thanh điều kiện chỉ đọc đã có**. Điều kiện đã lưu
    giữ kiểu chip nền phẳng, không có `x`; chip lọc là kính, có `x`. Hai kiểu trên một dòng là **cố ý**:
    nhìn là biết cái nào thuộc album, cái nào là bộ lọc tạm.
- **Advanced Filter…** mở đúng sheet Advanced Search của Library. Nút xác nhận là **Apply** thay cho
  Search; kết quả **chỉ tính trong album** và ở lại màn album, không chuyển sang tab Library.
  - Advanced và lọc nhanh **loại trừ nhau trong một album**, như luật một nguồn của Library.
  - Số ảnh khớp trong sheet đếm **trong album**, không đếm cả thư viện.
- **Smart Album: lọc chồng lên điều kiện đã lưu** — lọc nhanh hoặc Advanced đều **thu hẹp thêm** (VÀ) và
  **không sửa** album. Đây là ngoại lệ ghi rõ của luật "hai nguồn loại trừ nhau" trong FS-01.05 §1, vì ở đây
  điều kiện đã lưu là album chứ không phải một nguồn lọc.
- **Không nhớ bộ lọc**: mỗi lần mở album là All Items. *Vì* mở album ra thấy thiếu ảnh mà quên là đang
  lọc là lỗi khó nhận ra nhất. Sort vẫn nhớ theo từng album.
- **Đang chọn ảnh mà bật lọc**: ảnh đã chọn nhưng bị lọc ẩn **bị bỏ khỏi lựa chọn**, pill đếm cập nhật ngay.
  Delete và Share không bao giờ tác động lên ảnh người dùng không nhìn thấy. Library cũng theo luật này
  ([FS-01.06 §2](../FS-01-library/06-multi-select.md)).

## 5. Dữ liệu

| | |
|---|---|
| Đọc từ | album người dùng và hệ thống: danh sách của Photos, lọc theo favorite / loại media / kiểu chụp của hệ thống. Panoramas do ShotDex ghép và Advanced thì hỏi index, giới hạn trong tập id của album. Smart album: index |
| Ghi vào | Sort: bộ nhớ thứ tự theo album hiện có. Filter: không ghi gì |
| Người dùng tự nhập? | điều kiện Advanced chỉ sống trong phiên, không lưu; muốn giữ thì dùng Save as Smart Album như Library |

## 6. Ràng buộc

| Mặt | Ràng buộc |
|---|---|
| Hiệu năng | đổi lọc trên album 5.000 ảnh: trang đầu 120 ảnh hiện ra ≤ 300ms, như khi đổi Sort hiện nay ([NF-01](../../04-non-functional-design/NF-01-performance.md)) |
| Thiết bị | hàng chip tốn khoảng 44pt khi đang lọc. Trên Duo trong (669pt) và Duo ngoài phải chụp kiểm tra hàng ảnh đầu không bị che |
| iOS 26 vs trước | cùng tập mục menu và cùng hàng chip trên 26.5 và 18.6 |
| Truy cập | nút có nhãn `Filter and sort` như Library; chip đọc `Remove Favorites filter` |

## 7. Tiêu chí nghiệm thu

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | album người dùng 40 ảnh, 12 favorite | Filter → Favorites | lưới 12 ô, chip `Favorite` hiện, chân lưới `12 of 40 Items`; tắt → 40 ô, hết chip | `AlbumFilterTests.favorites` + chụp tay 26.5 `t2-favorites-26.png` (1 of 5 Items) |
| AC-2 | album 30 ảnh + 10 video | Videos Only | 10 ô; chọn tiếp Photos Only → 30 và Videos Only tự tắt | `AlbumFilterTests.mediaKinds` |
| AC-3 | album 40 ảnh, 5 Live Photo | Capture Kind ▸ Live Photos | 5 ô | `AlbumFilterTests.captureKinds` |
| AC-4 | album người dùng, Sort đang là Album Order | Sort By → Oldest First, thoát rồi mở lại | ô đầu là ảnh chụp sớm nhất; mở lại vẫn Oldest First | ⚠️ chưa có |
| AC-5 | album hệ thống Recently Added | mở Sort By | chỉ có Newest First · Oldest First, không có Album Order | chụp tay 26.5 `t1-recently-added-sort-26.png` |
| AC-6 | smart album ISO ≥ 1600 khớp 20 ảnh, 6 favorite | Favorites | lưới 6 ô; chip điều kiện đã lưu không có `x`, chip `Favorite` có `x` | ⚠️ chưa có |
| AC-7 | smart album bất kỳ | Sort By → Oldest First, thoát, mở lại | ô đầu là ảnh cũ nhất; vẫn Oldest First | ⚠️ chưa có |
| AC-8 | album không có video | Videos Only | câu `No photos match these filters.` + `Clear Filters`; chạm `Clear Filters` → đủ ảnh | chụp tay 26.5 `t5-empty-26.png` (Recently Added, Videos Only) |
| AC-9 | album đang lọc Favorites | quay lại Collections rồi mở lại album | All Items, không có hàng chip; Sort giữ nguyên | chụp tay 26.5: mở lại album sau khi lọc → menu đánh dấu All Items |
| AC-10 | đang chọn 3 ảnh, 1 ảnh không favorite | bật Favorites | pill đếm còn 2 | chụp tay 26.5 `t7-prune-26.png` (2 → 1); Library `t7b-library-prune-26.png` |
| AC-11 | album 40 ảnh, 8 ảnh ISO ≥ 3200; thư viện có 500 ảnh ISO ≥ 3200 | Advanced Filter… → ISO ≥ 3200 → Apply | sheet đếm 8; lưới 8 ô; vẫn ở màn album | ⚠️ chưa có |
| AC-12 | album đang lọc Advanced ISO ≥ 3200 | bật Favorites | điều kiện Advanced bị xoá, chỉ còn chip `Favorite` | ⚠️ chưa có |
| AC-13 | album đang lọc Favorites | chạm `x` trên chip | về All Items, hàng chip biến mất, hàng ảnh đầu không bị thanh trên che | chụp tay 26.5 `t6-chip-removed-26.png` |
| AC-14 | quyền `.limited`, 5 trong 40 ảnh được cấp, 2 favorite | Favorites | 2 ô; biểu ngữ Manage vẫn hiện | ⚠️ chưa có ảnh — sim không đặt được quyền `.limited` bằng lệnh; code dùng chung biểu ngữ của Library |
| AC-15 | Album, Smart Album, On This Day, Memories | chụp thanh trên, cả lúc chọn và không chọn | Album và Smart Album có nút Filter; On This Day và Memories không có | ⚠️ chưa có (ui-drive) |
| AC-16 | iOS 26.5 và 18.6, Duo trong | dump menu Filter và hàng chip của album đang lọc | cùng danh sách mục; hàng ảnh đầu nằm trọn dưới hàng chip | ⚠️ chưa có (`ios26-parity`, `device-layout`) |

**Chưa chứng minh được:** tất cả — spec mới, chưa có code.

## 8. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Advanced và Panoramas hỏi index; ảnh chưa index trong album sẽ không khớp | giống Library; chân lưới nói `~` như pill đếm khi index chưa đủ |
| Album 20.000 ảnh: Advanced phải giới hạn truy vấn index trong 20.000 id | dùng đường "danh sách id có thứ tự" đang phục vụ album kiểu chụp; đo theo NF-01 |
| Sheet Advanced hiện gắn với tab Library (Search rồi chuyển tab) | tách phần "áp ở đâu" ra để dùng lại; không nhân đôi bộ dựng điều kiện (FS-01.05 §1) |
| Favorites trong album Favorites, Videos Only trong album Videos là thừa | vẫn hiện dòng; rỗng thì trạng thái rỗng giải thích — không ẩn dòng theo từng album |
