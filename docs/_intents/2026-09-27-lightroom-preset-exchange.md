# Intent: Nhập / xuất preset Lightroom và chia sẻ look qua iOS

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan |
| Ngày | 2026-09-27 |
| Trạng thái | accepted |
| Tiến độ | **chưa làm** (2026-09-27) — chưa có spec |
| Nguồn | phản hồi người dùng (chủ sở hữu sản phẩm) — phiên thiết kế 2026-09-27 |
| Spec sinh ra từ đây | (điền khi sang Design) |

Canvas, hàng "Presets" (màn PR1–PR9): <https://claude.ai/artifact/T4tEUQrJtxBbi48HokiL9F>.
Liên quan: [editor-iphone-layout](2026-09-27-editor-iphone-layout.md) (chỗ đặt các nút) ·
[lightroom-parameter-parity](2026-09-27-lightroom-parameter-parity.md) (thông số để preset nhập vào có chỗ
đặt) · trả lời câu treo số 2 của [editor-lightroom-feature-parity](2026-09-22-editor-lightroom-feature-parity.md).

## Problem — vấn đề

- **Người dùng Lightroom không mang được preset sang.** ShotDex chỉ nhập được LUT `.cube`
  ([EditorToolPanels.swift:115](../../ShotDex/Features/Editing/EditorToolPanels.swift)). Preset `.xmp`,
  `.lrtemplate` hay preset nhúng trong DNG (cách Lightroom Mobile chia sẻ) đều không đọc được — đây là rào cản
  lớn nhất khi đổi app, vì thư viện preset là thứ người chụp tích luỹ nhiều năm.
- **Look của mình không mang đi đâu được.** My Looks chỉ có "Save Current"
  ([EditorToolPanels.swift:107](../../ShotDex/Features/Editing/EditorToolPanels.swift)) và giữ lâu để xoá;
  không đổi tên, không sắp xếp, không xuất file, không gửi cho máy khác hay cho người khác.
- **Nhận look từ người khác không có đường**: gửi qua AirDrop / Messages thì iOS không biết mở bằng app nào.

## Proposed outcome — kết quả mong muốn

- **Import** (ô Import trong My Looks, chọn file trong Files): nhận `.xmp`, `.lrtemplate`, DNG có preset,
  `.shotdexlook`, và `.cube` (tự vào tab LUTs). Nhận nhiều file / zip một lần. Xong hiện **báo cáo từng
  preset**: ✓ khớp · ≈ gần đúng kèm lý do ("Texture dùng như Clarity") · ✕ bỏ qua kèm lý do ("Camera profiles
  can't be imported"). Look nhập từ Lightroom mang nhãn "(LR)".
- **Camera profile trong preset** map theo tên sang film look gần nhất (Camera PROVIA/Velvia/Astia/Classic
  Chrome/Pro Neg/Classic Neg/Nostalgic Neg/Eterna/ACROS → look cùng tên; Monochrome → Mono; Vivid → Vivid;
  còn lại → Original). Creative profile có RGBTable → LUT nếu đọc được.
- **Export As**: `.shotdexlook` (đúng 100%), `.xmp` cho Lightroom (gần đúng, film look riêng bị mất; lens
  profile ghi `Enable + Auto`), `.cube` (nướng thành LUT, chỉ phần màu).
- **Quản lý look**: Rename · Share · Export As · Delete (giữ lâu); Manage Looks — chọn nhiều, kéo sắp xếp,
  Share / Delete. Không có Duplicate.
- **Chia sẻ**: Share… → `Tên.shotdexlook` (tuỳ chọn kèm ảnh xem trước); nhiều look → **một file gói**.
- **Nhận**: AirDrop hoặc chạm file trong Files → iOS mở (hoặc khởi động) ShotDex → look **tự vào My Looks**,
  banner ~4s có Undo. Từ Messages/Mail: "Open in ShotDex" (như trên) hoặc **"Add to ShotDex"** qua share
  extension — lưu mà không mở app; lần sau mở app banner báo "N looks added".
- **Save Current** giữ như hôm nay: đặt tên, lưu tone · màu · curve · film look, không crop/mask/markup.

## Affected users and systems — phạm vi ảnh hưởng

- **Màn**: Presets (My Looks), Manage Looks, sheet báo cáo import, banner nhận look; share extension
  `ShotDexShare` (thêm đường nhận look).
- **Thiết bị**: mọi thiết bị (phần dữ liệu); bố cục phone theo intent layout, iPad dùng lại luồng.
- **Code**: bộ đọc XMP (`crs:`) / `.lrtemplate` (bảng Lua dạng text) / XMP trong DNG — tự viết, trong
  `ShotDexKit` nếu extension cần đọc; bộ ghi `.xmp` / `.cube`; định dạng `.shotdexlook` (JSON có version);
  kho look (`lookPresets` — thêm thứ tự, đổi tên, gói nhiều look); Info.plist của app (khai báo loại file
  exported `.shotdexlook`, imported `.xmp`/`.lrtemplate`, document types, `LSSupportsOpeningDocumentsInPlace`
  hoặc copy-in); share extension ghi vào App Group, app nhập lúc khởi động.
- **Dữ liệu đã lưu**: kho My Looks thêm trường thứ tự và nguồn ("(LR)"); look là dữ liệu người dùng — nằm
  riêng, không trong `photo_metadata`.

## Constraints — ràng buộc

- **Pháp lý** (đánh giá kỹ thuật, không phải tư vấn pháp lý — cần người có chuyên môn xem trước khi phát
  hành):
  - Tự viết bộ đọc/ghi; không dùng code hay SDK của Adobe. XMP là chuẩn mở (ISO 16684-1), DNG có đặc tả công
    khai.
  - **Không đóng gói** preset, profile (DCP), `.lcp` hay bất kỳ dữ liệu nào của Adobe.
  - "Lightroom" chỉ dùng để mô tả chức năng (nhãn hiệu của Adobe) — không logo, không câu ngụ ý Adobe bảo trợ.
  - Điều khoản sử dụng thêm một dòng: chỉ chia sẻ look bạn có quyền chia sẻ.
- **Dữ liệu từ ngoài là không tin được**: file nhập vào đọc phòng thủ (giới hạn kích thước, schema có
  version, một preset hỏng không làm hỏng cả gói — cùng tinh thần `LossyArray`).
- Share extension giữ dưới trần bộ nhớ extension; không render ảnh trong extension ngoài thumbnail nhỏ.
- Không cần mạng; không gửi dữ liệu ra khỏi máy ngoài cái người dùng tự chia sẻ.

## Open questions — câu hỏi còn treo

1. **Độ giống màu** sau quy đổi `.xmp` → ShotDex: chỉ biết sau khi thử nghiệm (xử lý cùng bộ ảnh ở cả hai
   app, đo ΔE). Kết quả quyết định hệ số quy đổi từng slider. → thử nghiệm trước `/spec` (xem
   [lightroom-parameter-parity](2026-09-27-lightroom-parameter-parity.md) Open questions).
2. **RGBTable** của creative profile có giải mã được thành LUT không. → thử nghiệm với vài profile bên thứ ba.
3. Danh sách thẻ `crs:` đầy đủ và cách Lightroom hiện tại ghi preset (Lightroom 13–15). → agent
   `lightroom-parity` trong `/spec`.
4. Người có chuyên môn pháp lý xem mục Constraints trước khi phát hành. → người dùng sắp xếp.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
