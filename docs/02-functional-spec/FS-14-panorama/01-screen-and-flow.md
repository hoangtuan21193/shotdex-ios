# FS-14.01 — Màn hình và luồng

`FS-14.01` · tier D · cập nhật 2026-09-23

**Một câu:** từ lúc chọn Combine Photos ▸ Panorama tới lúc ảnh mới nằm trong thư viện — màn trông ra sao,
người dùng chỉnh được gì, và mọi đường hỏng nói gì.

## 1. Lối vào

- Chế độ chọn → ⋯ → **Combine Photos ▸ Panorama** — dòng thứ hai của menu con đặt tên theo mục đích
  ([intent menu](../../_intents/2026-09-23-combine-photos-purpose-menu.md)). Màn riêng, không phải mode của
  màn stack: các việc stack chồng những khung trùng nhau, panorama nối những khung cạnh nhau.
- Bật khi chọn **≥ 2 ảnh**; video trong lựa chọn bị bỏ qua, không chặn lệnh.
- Thứ tự khung **không** lấy từ lưới hay thứ tự chạm — app tự dò.
- **Không trần số khung.** Trên **50 khung**, trước khi ghép màn hiện ước lượng thời gian ("About 4 minutes
  for 120 photos") với Continue / Cancel; dưới 50 thì ghép ngay. Ước lượng tính từ số khung và số megapixel,
  ghi rõ là ước lượng.

## 2. Trạng thái

| Trạng thái | Điều kiện | Hiển thị |
|---|---|---|
| đang tải khung | lấy bản xem trước của từng khung | stage đen, đếm `Loading 3 of 10…`, Cancel |
| đang ghép | tìm chỗ chồng, căn, trộn bản xem trước | `Finding overlaps…` → `Aligning…` → `Blending…` |
| bình thường | ≥ 2 khung nối được | preview + panel |
| thiếu khung | có khung không nối được | preview của nhóm lớn nhất + dải **Not Placed (N)** |
| không ghép được | không cặp nào chồng nhau | thông báo khung phải chồng ~30% · Save mờ · Cancel |
| iCloud lỗi | khung chỉ trên iCloud, tải hỏng | "N photos couldn't be downloaded" + Retry · Cancel |
| đang lưu | sau Save | modal khoá màn (DESIGN §10.3): tiến trình, bước hiện tại, Cancel đỏ |

Không bao giờ **lặng lẽ bỏ khung**: khung nào không vào ảnh cuối thì hoặc nằm ở Not Placed, hoặc có tên
trong thông báo lỗi.

## 3. Bố cục

Khung tầng D như Combine Photos (DESIGN §10.3, §10.3b): top bar `Cancel` · tiêu đề `Panorama` · `Save`,
stage đen, một panel đáy `panelSolid`. Không token mới.

Panel, từ trên xuống:
1. **Projection** — ba lựa chọn Spherical · Cylindrical · Perspective, dưới là **một câu nói phép chiếu
   đó hợp với cảnh nào** (không mô tả phép toán). Lựa chọn không dựng được thì mờ và câu đó nói vì sao.
2. **Boundary Warp** — slider 0–100, mặc định 0.
3. **Auto Crop** — công tắc, mặc định bật.
4. **Size** — slider **25–100%** của độ phân giải gốc, bước 5, **hít ở 100%**, mặc định 100%. Không phóng quá
   100% — pixel phóng to là pixel bịa. Dưới track **một dòng** ước lượng, cập nhật khi đổi bất kỳ mục nào ở trên:
   `24,847 × 6,120 px · 152 MP · ~34 MB · ~1 min 40 s`. (§4b)
5. **Arrange** — nút vào chế độ sắp khung (§5).

Size đứng sau Projection, Warp, Crop vì kích thước ra phụ thuộc cả ba — thứ tự panel là thứ tự đường ghép.
Panel dùng slider và kiểu dòng ước lượng có sẵn của tầng D (như màn Resize), không component mới.

- **Màn rộng** (cùng điều kiện với editor, DESIGN §10.3: rộng ≥ 700, cao ≥ 600, rộng > cao): panel thành
  **cột phải 280–320pt**, cùng bốn mục, cùng thứ tự; Not Placed thành dải dưới stage. Điện thoại và iPad dọc
  giữ panel đáy. *Vì* panorama là thứ dẹt nhất app từng hiện — chiều cao là thứ nó thiếu, bề rộng thì dư.

## 4. Preview

Mọi thay đổi setting hiện lên preview **ngay**, chất lượng thấp trước, nét sau. Căn ảnh và giải camera chạy
**một lần** khi mở màn (và khi Arrange đổi khung); đổi setting không bao giờ chạy lại hai bước đó.

| Tầng | Khi nào | Dựng thế nào | Mục tiêu (iPhone 17) |
|---|---|---|---|
| **nháp** | trong lúc kéo slider, ngay khi chạm một lựa chọn | cạnh dài ≤ 1536 px, trộn mềm một tầng, không tìm đường nối | ≥ 15 khung/giây khi kéo; ≤ 150 ms sau khi chạm |
| **nét** | ngừng kéo ~300 ms | cạnh dài ≤ 4096 px, trộn đa dải, đường nối tránh vật chuyển động | ≤ 1,5 s |

- Đang dựng bản nét thì bản nháp vẫn hiện, kèm chỉ báo nhỏ ở góc stage; kéo tiếp thì huỷ bản nét đang dựng,
  không xếp hàng.
- **Size không đổi hình**, chỉ đổi dòng ước lượng (§4b) — preview đứng yên.
- **Auto Crop**: viền vùng bị cắt vẽ mờ trên preview, bật/tắt là thấy ngay, không dựng lại ảnh.
- **Projection**: đổi là dựng lại cả hai tầng; bản nháp ra trước.
- Bản nháp và bản nét khác nhau ở độ nét và đường nối, **không** khác nhau ở hình học: khung, mép, vùng cắt
  trùng khít — để thứ người dùng chỉnh trên bản nháp đúng là thứ sẽ lưu.
- Chạm hai lần: fit ⇄ cao bằng stage, kéo ngang để xem dọc panorama. Phóng to hơn độ nét preview thì ảnh mờ —
  xem 100% là việc của viewer sau khi lưu.

## 4b. Ước lượng kích thước

- **Pixel và MP**: tính đúng từ hình học đã giải và Size — con số này là kích thước sẽ lưu, không ước.
- **Dung lượng**: nén bản preview đang có ra JPEG cùng chất lượng lưu, chia theo số pixel, nhân lên số pixel
  đích — cách màn Resize đang làm. Ghi `~`.
- **Thời gian**: từ số khung và số MP đầu ra, hệ số đo trên máy thật ở `/verify`. Ghi `~`.
- Vượt 65535 px một cạnh ở mức Size đang chọn: phần pixel đổi thành `Will save at 65,535 × 9,120` (§6 của 02).
- **Không đủ dung lượng trống** cho file tạm + ảnh ra: cả dòng đổi thành `~34 MB — not enough free space
  (need 1.2 GB more)`, Save mờ. Người dùng thấy trước, không phải bấm Save rồi mới biết.
- Cập nhật sau khi ngừng kéo ~150 ms; không chạy lại đường ghép, chỉ tính lại con số.
  **Bản dựng không cần hoãn**: pixel và MP là số học trên hình học đã giải, byte và thời gian là hệ số
  đo sẵn từ bản nét, nên dòng này tính lại trong cùng một khung hình và đi thẳng theo tay kéo.

## 5. Sắp khung tay (Arrange)

- Stage hiện **viền từng khung** trên preview; dải **Not Placed** (dùng filmstrip của editor, không
  component mới) giữ những khung chưa nối được.
- **Kéo một khung** trên stage hoặc từ Not Placed thả vào gần chỗ đúng → app căn lại khung đó với
  các khung chạm nó, dùng chỗ thả làm điểm xuất phát. Căn không được thì khung trở về chỗ cũ và báo.
- **Kéo khung ra khỏi stage** vào Not Placed → khung bị loại khỏi ảnh cuối.
- Không lưu gì: rời màn là mất cách sắp.
- VoiceOver: mỗi khung là một phần tử "Photo 3 of 10, placed" / "not placed", có hành động Remove.

## 6. Lưu

- Save chạy đường full-res ([02](02-stitching-pipeline.md)): tải bản gốc cỡ đầy đủ, ghép theo dải, ghi
  file, tạo asset mới. Dung lượng trống đã kiểm từ lúc chỉnh (§4b); kiểm lại một lần khi bấm Save.
- Cancel lúc đang lưu: không asset nào được tạo, thư mục tạm của phiên bị xoá.
- Cancel trên top bar (chưa lưu): về lưới, **giữ nguyên lựa chọn** — như mọi việc trong menu Combine Photos
  ([FS-01.09 §3](../FS-01-library/09-photo-stacking.md)).
- **Lưu xong**: đóng màn, thoát chế độ chọn, **mở ảnh vừa lưu trong viewer** — ảnh mới nằm theo ngày chụp
  của khung đầu, có thể cách chỗ đang cuộn hàng nghìn ảnh; không mở ra thì người dùng phải đi tìm nó.
  Mở từ album thì theo đúng luật của menu con ([FS-01.09 §3](../FS-01-library/09-photo-stacking.md)):
  album người dùng tạo → thêm ảnh vào album rồi mở tại chỗ; Smart Album / On This Day → sang tab Library.
- **Màn hình luôn sáng** suốt lúc lưu (tắt khoá tự động), bật lại ngay khi xong, lỗi hoặc Cancel.
- **Vào nền vẫn lưu tiếp**, mọi bản iOS:
  - iOS 26: xin chạy tiếp ở nền, tiến trình hiện trong giao diện của hệ thống.
  - Trước 26: dùng hết thời gian nền hệ thống cấp (~30 s); hệ thống tạm dừng app thì việc dừng theo, và
    **chạy tiếp đúng chỗ dở** khi người dùng quay lại — không làm lại từ đầu.
  - Hệ thống giết app lúc ở nền: không asset nào được tạo; lần mở sau báo "Saving was interrupted" và
    cho mở lại đúng bộ khung để Save lại.
  - Vì: trước iOS 26 không có API nào cho app chạy nền quá giới hạn đó — hai nhánh cùng *hành vi* với
    người dùng (không mất việc), khác nhau ở chỗ việc có dừng tạm hay không.

## 7. Viewer

**Một định nghĩa "panorama" cho cả app:** ảnh mang cờ panorama của hệ thống (Pano của Camera) **hoặc**
ảnh mang thẻ panorama của ShotDex trong file ([02 §7](02-stitching-pipeline.md)). Không theo tỉ lệ: ảnh
crop 21:9 không phải panorama.

- ⋯ → **View Panorama** hiện cho mọi ảnh theo định nghĩa trên ([FS-02.04 §8](../FS-02-photo-detail/04-actions-and-extras.md)).
- Bộ lọc **Capture Kind → Panoramas** ([FS-01.05](../FS-01-library/05-filtering-and-sorting.md)) và bộ
  sưu tập **Panoramas** ([FS-06.01](../FS-06-collections/01-tabs-tokens-and-album-management.md)) dùng cùng
  định nghĩa. Hệ quả: bộ sưu tập Panoramas **thôi lấy từ album Panoramas của Photos** (album đó không bao
  giờ chứa ảnh app tạo) mà lấy từ index của ShotDex — nó sẽ khác album của Photos đúng ở các ảnh ghép.
- Ảnh vừa lưu được **index ngay lúc lưu**, không chờ lượt index kế — không thì viewer mở ra (AC-19) chưa
  có View Panorama và bộ lọc chưa thấy nó.

## 8. Chữ

Dòng menu `Panorama` (trong Combine Photos ▸), tiêu đề `Panorama`, nút `Save`.
Chuỗi đi qua String Catalog, số khung dùng plural ([NF-06](../../04-non-functional-design/NF-06-accessibility-and-localization.md)).
