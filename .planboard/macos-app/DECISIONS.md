# ShotDex Mac — các quyết định

Chốt 2026-10-04 sau 1 vòng · nguồn: `.planboard/macos-app/plan.json` · review: `build/design/mac/review/*.md`

| ID | Quyết định | Kết quả | Lựa chọn |
|---|---|---|---|
| D1 | Phân phối | OK | Mac App Store, sandbox |
| D2 | Phát hành | OK | **Đủ tính năng trong một lần phát hành** (khác đề xuất) |
| D3 | Rating/keyword/recipe của ảnh thư mục | OK | Đọc + ghi sidecar `.xmp`, mặc định bật |
| D4 | Nhận diện ảnh thư mục | OK | **Hash nội dung** (khác đề xuất) |
| D5 | Server | OK | Nguồn được index |
| D6 | Xoá file | OK | Thùng rác cho file cục bộ, không xoá trên NAS |
| D7 | Bản sao ở hai nguồn | OK | Đếm một lần; Duplicates chỉ trong từng nguồn |
| D8 | Nhập từ thẻ nhớ | OK | **Màn Import có ngay bản đầu** (khác đề xuất) |
| D9 | Viewer/Editor | OK | Mở trong cửa sổ, cửa sổ riêng là tuỳ chọn |
| D10 | Tier D | OK | **Giữ như DESIGN.md: mọi công cụ pixel đều tối** (khác đề xuất) |
| D11 | Màu nhấn | OK | **Luôn amber** (khác đề xuất) |
| D12 | Dải phím tắt | OK | Giữ trên Cull (ẩn được, nhớ lựa chọn); Compare bỏ |
| D13 | Lần mở đầu | OK | Trạng thái trống trong cửa sổ chính, bỏ cửa sổ Onboarding |
| D14 | Màn hình thứ hai | OK | Không có ở bản đầu; có "Open in New Window" |
| D15 | Compare | OK | Gộp vào Viewer: 2-Up/Survey + P/X |
| D16 | Lưu chỉnh sửa | OK | **Ảnh thư mục tự lưu; Done chỉ với ảnh Photos** (khác đề xuất) |
| D17 | Không gian màu khi xuất | OK | Có popup trên Mac |
| D18 | Statistics | OK | Giữ popup Source + biểu đồ giờ/thứ; bỏ popup ngày chung |
| D19 | Album | OK | Theo spec: không thư mục album, không số dưới cover |

## Hệ quả cần chú ý (từ các lựa chọn khác đề xuất)

- **D2 + D8:** bản đầu gánh cả Video Studio, Server, Collage, Ghép ảnh và thêm màn Import thẻ nhớ.
  Spike build macOS cho ShotDexKit + Domain + Data vẫn nên làm trước để ước lượng.
- **D4 (hash) gặp D3, D5, D7:**
  - Hash cả file RAW khi index chậm trên NAS và ổ HDD. `/spec` phải chốt hash nhanh
    (kích thước + vài khối đầu/cuối) hay hash đầy đủ.
  - Hai bản sao giống hệt nhau thành **một ảnh**. Vậy D7 tự đúng: thống kê đếm một lần.
    Nhưng rating của một bản áp cho cả hai, và sidecar `.xmp` phải ghi ra **mọi** bản sao đang
    online — `/spec` chốt cách xử lý bản đang offline.
  - Sửa file (ghi `.xmp` không đổi nội dung ảnh, nên hash ổn định). Ảnh chỉnh rồi xuất ra là file mới.
- **D10 (giữ DESIGN.md):** Resize, Collage, Ghép ảnh vẫn tối. Viewer không phải tier D, nên vùng
  ảnh của Viewer theo nền cửa sổ (bỏ ô xám tối agent sửa đã thêm).
- **D11 (luôn amber):** bỏ hàng Accent Color khỏi Settings General. Icon sidebar giữ amber.
- **D16 (tự lưu với thư mục):** Editor có hai trạng thái toolbar — ảnh thư mục/NAS không có Done
  (chỉ "Edited · saved", Revert); ảnh Photos có Done + Revert. Export bỏ segment "Save Edit".
