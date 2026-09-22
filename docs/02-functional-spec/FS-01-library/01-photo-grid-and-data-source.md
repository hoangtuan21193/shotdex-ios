# FS-01.01 — Nguồn dữ liệu của lưới

`FS-01.01` · `Features/Shared/PhotoGridCollectionView.swift` · `Domain/Grid/` · cập nhật 2026-09-22

**Một câu:** lưới nạp cả thư viện một lần bằng row gầy, hiện ảnh ngay từ thư viện hệ thống, và không bao
giờ nhảy chỗ đọc của người dùng.

Engine lưới, pinch, section và nhãn tile: [FS-01.01b](01b-grid-engine-and-gestures.md).

## 1. Quy tắc

- **Không phân trang ở Library.** Một truy vấn trả toàn bộ thư viện đã lọc và sắp dưới dạng **row gầy**
  (~200 KB cho 1.000 ảnh); ô lưới được tái dùng nên bộ nhớ phẳng dù cuộn tới đâu.
- **Ảnh hiện trước, metadata điền sau.**
- **Không truy vấn database trên mỗi ô.**
- **Lưới không được nhảy**: mọi lần nạp lại phải giữ chỗ đọc, trừ bốn ca ở §5.
- **Chỉ hiển thị giá trị có thật** — không có placeholder kiểu `ISO -- · --mm · f/--`.

## 2. Ảnh ở đâu ra

| Điều kiện | Nguồn |
|---|---|
| Không lọc gì **và** đang sắp theo ngày | hỏi thẳng thư viện hệ thống, ghép với row đã index để có dòng thông số; ảnh chưa index thì tile chỉ có thumbnail |
| Có lọc bất kỳ, hoặc sắp theo thông số | truy vấn database — **chỉ ảnh đã index** |

- Số ảnh khớp là **độ dài danh sách**, không phải một câu đếm riêng; số video đếm **một lần** khi danh sách
  đổi, không đếm lại mỗi lần vẽ.
- **Chân lưới luôn có dòng đếm** — "478 Photos, 2 Videos", cỡ nhỏ và mờ, vế nào bằng 0 thì bỏ. Nó lấp
  khoảng trống giữa hàng cuối và tab bar, đúng như Photos.
- Metadata đầy đủ chỉ lấy **khi cần** theo từng ảnh (viewer, Compare). Ảnh chưa index dùng bản rỗng dựng từ
  dữ kiện hệ thống, nên favorite/share/info vẫn chạy.
- **Dòng thông số điền dần khi cuộn tới**: ô nào thiếu toàn bộ thông số thì hỏi riêng ngoài luồng chính, và
  kết quả chỉ cập nhật **đúng ô đó**. Kết quả được cache khi nó là câu trả lời cuối cùng (đã index, hoặc
  chắc chắn không có EXIF); trạng thái còn dở (chờ đọc, chờ iCloud, lỗi) **không** cache để lần sau còn thử lại.
- **Video hiện ở mọi màn**, và được index thành row **không có EXIF** kèm dữ kiện của hệ thống. Tile hiện
  khung đại diện + nhãn thời lượng. Video đếm vào tổng số, nhưng vì không có thông số gear nên biểu đồ gom
  chúng vào nhóm **"Unknown"**.

## 3. Chống bão nạp lại

Trong lúc tải ảnh từ iCloud, hệ thống bắn thông báo thay đổi thư viện **liên tục** — mỗi thông báo một lần
nạp lại là hai lần giải mã toàn bộ row và hai lần duyệt cả thư viện.

- Thông báo được gộp lại, **nhiều nhất một lần mỗi giây**.
- Tách **hai** loại tín hiệu: "có ảnh thêm/bớt/đổi chỗ" và "có thay đổi bất kỳ". Lưới và pipeline index chỉ
  nghe loại đầu.
- Đang index thì thay đổi được **ghi nhớ** và gộp vào lần nạp lại cuối cùng của run, cộng một lượt index
  bù ngay sau đó.

## 4. Lần vẽ đầu chia hai pha

Chỉ chạy **khi lưới đang trống**.

| Pha | Làm gì |
|---|---|
| 1 | lấy **600** ảnh đầu theo thứ tự sắp → lưới hiện gần như tức thì |
| 2 | duyệt đủ cả thư viện rồi thay danh sách |

- **Lát cắt phải lấy theo vị trí, tuyệt đối không dùng giới hạn số lượng của hệ thống**: đi cùng thứ tự sắp
  tự chọn, giới hạn đó **không đảm bảo** trả về đúng phần đầu — nên lát cắt không còn là phần đuôi của danh
  sách đầy đủ, và pha 2 làm **đáy mọc thêm ảnh mới hơn rồi nháy**.
- **Lát cắt phải kết thúc đúng biên một nhóm ngày**: ô xếp thành hàng tính từ **đầu nhóm**, nên cắt giữa
  một nhóm làm cả layout hàng của nhóm đó dịch khi phần còn lại về. Cách xử lý: **nới rộng** tới hết tháng
  đang bị cắt, và có trần để một tháng khổng lồ không biến lần vẽ đầu thành duyệt cả thư viện.
- **Pha 2 đi đường database khi index đã phủ hết**: duyệt 55.000 ảnh của hệ thống tốn ~930ms, còn giải mã
  cùng số row từ database chỉ ~350ms. Nhưng điều kiện phải **chứng minh được** là hai bên khớp nhau: cùng
  số lượng, **và** tập id ở đầu neo đúng bằng tập của lát vừa vẽ. Giữ **nguyên row của lát** ở đầu neo, vì
  hệ thống và SQL phá thế hoà ngày chụp theo hai cách khác nhau. Đo được: danh sách đầy đủ sẵn sàng ở
  **+536ms** thay vì +1.265ms.
- **Lưới đã có ảnh thì bỏ pha 1** — hiện 600 ảnh trước rồi thay là đổi nội dung hai lần, đúng triệu chứng
  "index xong lưới nhảy xuống đáy rồi nháy".
- Danh sách mới **cùng id cùng thứ tự** thì không gieo lại cache tra cứu; và cache giữ lại giá trị đã có
  **theo id**, không theo vị trí — thêm 54.000 id vào đầu danh sách đẩy mọi ô đang hiện sang chỗ khác, giữ
  theo vị trí là vô dụng.

## 5. Neo đáy và giữ chỗ đọc

- **Neo đáy kiểu Photos** (chỉ Library; Album Detail vẫn neo đỉnh): ảnh mới nhất ở **đáy**, mở tab là đứng
  sẵn ở đáy. Truy vấn giữ nguyên, **danh sách được đảo một lần sau khi nạp** — đảo trong Swift chứ không
  trong SQL, để nhóm "No Date" vẫn nằm đúng chỗ.
- **Tắt cử chỉ "lên đầu" của hệ thống**: ở đây nó sẽ ném người dùng về ảnh **cũ nhất**. Chạm lại tab Library
  đi đường riêng để về đáy.
- **Neo lúc mở màn phải áp lại tới lần chạm đầu tiên**, không phải một lần: vùng an toàn của màn chỉ tới
  sau khung hình đầu. Chỉ chỉnh khi lệch quá nửa point, và bỏ neo ngay khi người dùng kéo, giữ lâu **hoặc
  pinch** — vào chế độ chọn làm lề đáy đổi, còn giữ cờ thì lưới tự nhảy về đáy giữa lúc người ta đang đứng
  ở giữa.
- **Danh sách y hệt** (index xong, huỷ index) → chỉ vẽ lại các ô đang hiện, **giữ nguyên chỗ cuộn**.
- **Danh sách khác thật** → nhớ **mọi** ô đang hiện cùng vị trí ô trên cùng; ô đầu còn sống thì thắng, cả
  cụm bị xoá thì đứng vào ô đang chiếm chỗ đó.
- **Xoá tại chỗ**: model báo "danh sách mới = danh sách cũ trừ đúng các id này" trong **cùng một lần cập
  nhật** với mảng đã cắt; lưới kiểm chứng rồi chạy hoạt ảnh xoá — ô bay ra kiểu Photos, chỗ cuộn giữ
  nguyên, không xin lại thumbnail. Kiểm chứng trượt thì rơi về đường nạp lại.
- **Chỉ neo lại về đầu** khi: lần layout đầu · chạm lại tab · danh sách mới rỗng · hoặc người dùng **đang
  đứng sẵn ở đầu neo** (Library: trong một màn hình tính từ đáy; lưới neo đỉnh: đúng ở đỉnh).

## 6. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
