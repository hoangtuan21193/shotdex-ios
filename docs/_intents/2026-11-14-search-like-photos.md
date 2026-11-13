# Intent: Search dùng mượt như app Photos

| Trường | Giá trị |
|---|---|
| Tác giả | Hoang Tuan (người dùng) · Claude soạn |
| Ngày | 2026-11-14 |
| Trạng thái | accepted (2026-11-14, planboard `.planboard/search-photos`, 1 vòng, đồng ý mọi đề xuất) |
| Nguồn | yêu cầu người dùng: "Understand how Search works in the Photos app, show me the evidence, and build a similar UI and logic for shotdex. Không được bỏ chức năng nào của shotdex, chỉ update giao diện và logic bên trong để shotdex hoạt động mượt hơn giống Photos. Tìm hiểu cách load ảnh và giao diện để cải thiện tốc độ của shotdex nữa" |
| Bằng chứng | [docs/_research/2026-11-14-photos-search-re.md](../_research/2026-11-14-photos-search-re.md) (Photos 12, macOS 27.2.1) |
| Quyết định | `.planboard/search-photos/DECISIONS.md` (D1–D7, A1–A9) |
| Spec sinh ra từ đây | [FS-01.03c](../02-functional-spec/FS-01-library/03c-search-like-photos.md) |

## Problem — vấn đề

- Gõ chữ chỉ thấy một viên "đọc hiểu" và vài viên tên; viên không có số ảnh, không hình, không nói là máy hay nơi.
- Muốn thấy ảnh phải bấm Search, rồi app chuyển sang tab Library. Sửa câu tìm phải quay lại tab Search.
- Gợi ý chỉ thay chữ: muốn thu hẹp "Sony A7 IV" rồi thêm "ISO cao" phải gõ lại cả câu.
- Ô trống chỉ có Gần đây; thư viện có gì để tìm thì không thấy.
- Gõ "june", "mùa hè", "cuối tuần" ra tìm tên file. Gõ sai "fujiflim" ra 0 ảnh không lý do.
- Chậm ở 55.000 ảnh: mỗi phím dựng lại bộ tên máy/ống/nơi trên luồng chính; mỗi lần tìm quét `LIKE '%…%'` 6 cột
  trên mọi ảnh; mở Search chạy lần lượt 10 truy vấn cho Gần đây và lấy ảnh bìa đồng bộ trên luồng chính.

## Proposed outcome — kết quả mong muốn

Như Photos: gõ ra dòng gợi ý có hình, loại, số ảnh; ảnh khớp hiện ngay bên dưới; chọn gợi ý thành viên lọc, gõ
tiếp để thu hẹp; ô trống gợi ý từ chính thư viện; hiểu ngày tháng tự nhiên; hỏi lại khi gõ sai. Nhanh nhờ một
chỉ mục giá trị tính sẵn (như bảng `groups`/`ga`/`prefix` của Photos), chạy nền và huỷ được.

## Constraints — ràng buộc

- **Không bỏ chức năng nào** (A8): cú pháp ISO/f/mm/tốc độ/khổ cảm biến, Advanced Search, Save as Smart Album,
  AI search, `keyword:`, caption, nơi chụp, chip mời "không hiểu", Recents, Spotlight, nút Advanced trong ô, Mac.
- Lưới Library vẫn nhận kết quả (nút "Mở trong Library") với thanh điều kiện, lọc, sắp xếp như cũ.
- Chỉ mục là dữ liệu suy ra: dựng lại được bất cứ lúc nào; chữ người gõ (caption, keyword) vẫn ở bảng của nó.
- Không chặn luồng chính; 55.000 ảnh: gợi ý ≤ 50 ms sau khi dừng gõ trên iPhone 17 sim.
- iOS 17 (không có viên trong ô tìm của hệ thống) và iOS 26 (tab tìm kiếm) cùng hành vi.
- Không tìm theo nội dung ảnh (cảnh, chữ trong ảnh, người): ShotDex không có nhận dạng — ngoài phạm vi.
