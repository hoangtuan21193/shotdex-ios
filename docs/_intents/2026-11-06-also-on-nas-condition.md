# Intent: Điều kiện "Also on Server" — tách khỏi Source để không bị hiểu là "ảnh trên NAS"

| Trường | Giá trị |
|---|---|
| Tác giả | Hoang Tuan (người dùng) · Claude soạn |
| Ngày | 2026-11-06 |
| Trạng thái | accepted (2026-11-06) |
| Tiến độ | **đang làm** (2026-11-06) — spec FS-19.07 §7, 14 AC (07b AC-246…259); board vẽ (`74008bba`); plan [2026-11-06-also-on-server-keep-in-photos](../_plans/2026-11-06-also-on-server-keep-in-photos.md), task 0/11 |
| Nguồn | phản hồi người dùng (2026-11-06): "khó hiểu quá… để là source thì dễ bị hiểu là hiển thị ảnh ở NAS, không phải ở iCloud" |
| Spec sinh ra từ đây | [FS-19.07 §7](../02-functional-spec/FS-19-photo-sources/07-on-server-check.md) · [07b §5](../02-functional-spec/FS-19-photo-sources/07b-on-server-check-ac.md) · [FS-06.08 §2](../02-functional-spec/FS-06-collections/08-smart-albums.md) |

Intent anh em: [2026-11-06-photos-album-from-smart-album](2026-11-06-photos-album-from-smart-album.md) (đưa album này
sang Photos để Move to Shared Library). Gốc: [2026-10-24-smart-album-on-nas](2026-10-24-smart-album-on-nas.md).

## Problem — vấn đề

Smart album "ảnh iCloud đã có bản trên NAS" (FS-19.07) đã có code, nhưng **người dùng — chính người đặt ra tính năng —
không tìm ra nó** và khi được chỉ thì thấy khó hiểu.

- Điều kiện nằm trong field **Source**: chọn nguồn NAS → dòng **Folder** → `is` / `is not`. Chip đọc
  `Source is NAS Home › Shared`. Câu đó đọc như "hiện ảnh **nằm ở** NAS", trong khi kết quả là ảnh **trong Photos/iCloud**
  có bản giống hệt trên NAS. Hai nghĩa ngược nhau về chỗ ảnh nằm.
- Cùng field Source mang hai nghĩa tuỳ loại nguồn (`SmartAlbumSQLBuilder.swift:205-232`): nguồn server = "mục Photos có
  đủ file gốc trên folder đó" (so SHA-256); nguồn khác = "có bản sao ở nguồn đó". Người dùng không thấy được sự khác nhau
  ấy trên màn hình.
- Dòng Folder chỉ hiện khi đã chọn đúng một nguồn server (`SmartAlbumRuleRow.swift:178`); không có gì gợi ý rằng Source
  là lối vào tính năng "đã có trên NAS".
- `is` / `is not` không nói ra rằng ảnh chưa kiểm xong không thuộc bên nào.

Mức độ: tính năng dùng để quyết định **xoá ảnh** khỏi iCloud. Hiểu nhầm album đang hiện gì là rủi ro xoá nhầm, và hôm
nay nó làm người dùng không dùng được tính năng.

## Proposed outcome — kết quả mong muốn

1. Smart Album editor có điều kiện riêng tên **Also on Server**, đứng cạnh các điều kiện khác trong danh sách field: chọn
   NAS (connection/nguồn server) + folder (trống = cả NAS, gồm folder con) + **Yes / No**.
2. Đọc chip là hiểu ngay: ảnh trong thư viện của mình **và** có bản trên NAS, ví dụ `Also on Server: Yes · NAS Home › Shared`.
3. **Source** không còn cho chọn nguồn server: lọc theo NAS/server chỉ qua Also on Server. Source chỉ còn các nguồn thư mục/ổ đĩa và Photos.
4. Hành vi so khớp giữ nguyên FS-19.07: SHA-256, đủ mọi file gốc, ảnh chưa kiểm xong không vào Yes lẫn No, dòng tiến độ ở
   đầu album, cổng kiểm lại NAS trước khi xoá.
5. Tên này dùng thống nhất ở mọi chỗ cùng ý: thanh tìm nâng cao của Library, dấu "On NAS" trên lưới, Photo Info
   (chỗ nào giữ chữ khác thì spec nói lý do).

## Affected users and systems — phạm vi ảnh hưởng

- **Màn:** Smart Album editor (`SmartAlbumEditorSheet`, `SmartAlbumRuleRow`), chip smart album, thanh tìm nâng cao
  Library, có thể dấu lưới + Photo Info (FS-02).
- **Thiết bị:** iPhone · iPad · Duo trong/ngoài. Mac: smart album có board `MAC_SmartAlbum`, phần On Server trên Mac
  chưa làm (FS-19.07 §11) — cần quyết có theo tên mới luôn không.
- **Tầng:** Domain (`SmartAlbumRule`/`RuleField` — field mới), Data (`SmartAlbumSQLBuilder`: tách nhánh server khỏi
  `sourceClause`), Features (editor, chip). Không đổi bảng kết quả kiểm.
- **Dữ liệu đã lưu:** smart album đang lưu rule `Source is <server>`. App chưa release → không migration (CLAUDE.md);
  decode vẫn khoan dung.
- **Design canvas:** board smart album editor trên iPhone/iPad/Duo (và Mac nếu làm) phải vẽ lại trước khi code.

## Constraints — ràng buộc

- Người dùng chốt (2026-11-06): tên **Also on Server** cho mọi nguồn server (lúc đầu chọn "Also on NAS", rồi đổi vì server không phải lúc nào cũng là NAS — ShotDex không phân biệt được NAS với SMB/WebDAV khác). Bỏ nguồn server khỏi Source.
- Không đổi cách so khớp, lịch kiểm, cổng xoá của FS-19.07 — đây chỉ là cách trình bày điều kiện.
- Chữ UI tiếng Anh kiểu Mỹ, qua String Catalog.
- Nhánh iOS 26 / trước 26 như các màn khác.
- Không test bằng ảnh có mặt người.

## Open questions — câu hỏi còn treo

Đã trả lời 2026-11-06: tên dùng chung cho mọi server = **Also on Server**; Source **bỏ** nguồn server.

| # | Câu hỏi | Ai trả lời | Đề xuất mặc định |
|---|---|---|---|
| Q3 | Dấu lưới "On NAS" và mục Photo Info "On Server" có đổi chữ theo không? | người dùng | dấu lưới đổi "On Server"; Photo Info đổi "Also on Server" |
| Q4 | Mac làm cùng lượt hay để khi làm FS-19.07 §11? | người dùng | để cùng §11 nhưng spec dùng tên mới ngay |
| Q5 | Bỏ nguồn server khỏi Source thì không còn cách lọc "file trên NAS chưa có trong Photos" — chấp nhận? | người dùng | chấp nhận; việc đó thuộc On Server screen (FS-17.01) |

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
