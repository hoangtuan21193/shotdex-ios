# Pending spec edits — files busy in another session (main ledger)

Áp khi `FS-06.01` / `DESIGN.md` không còn thay đổi chưa commit của phiên khác. Mỗi mục: file · section · thay đổi · ID.

## docs/02-functional-spec/FS-06-collections/01-tabs-tokens-and-album-management.md

1. **§ thứ tự section (dòng ~24, "People and Pets · Smart Albums · My Albums · Shared Albums")** — thêm bullet (C5):
   > - Tiêu đề mỗi nhóm có cover (Smart Albums, My Albums, Shared Albums) là một nút: "My Albums ›" mở màn **All Albums**
   >   — lưới dọc 2 cột trên compact, adaptive 160–200pt trên regular, sort Name / Date Created / Most Photos.
   >   Hàng cuộn ngang giữ nguyên; người có 80 album thấy đủ ở màn kia.
2. **§ tên gọi** — thêm luật (C6): một tên cho album người dùng tạo: **My Albums** (thay "Your Albums" ở sheet thêm vào album);
   lệnh trong menu chọn nhiều là **Add to Album**; "Collections" chỉ là tên tab.
3. **§3 Hàng hero** — chiều cao hero ở cửa sổ thấp (Z3): giữ 180 compact / 260 regular, nhưng cửa sổ thấp
   (định nghĩa ở NF-05) cao 0,28 × chiều cao cửa sổ, sàn 180, trần 260. Duo inner 669pt → 187pt.
4. **Tiêu chí nghiệm thu thêm vào FS-06.01:**
   | # | Cho | Khi | Thì | Chứng minh bằng |
   |---|---|---|---|---|
   | AC-C5a | 80 album người dùng, iPhone 17 | chạm "My Albums ›" | màn All Albums 2 cột, cuộn tới album thứ 80; sort Most Photos đặt album nhiều ảnh nhất lên đầu | ⚠️ chưa có |
   | AC-C5b | cùng thư viện, iPad 13" ngang | chạm "My Albums ›" | lưới adaptive ≥ 6 cột, tile 160–200pt, không tile nào > 200pt | ⚠️ chưa có |
   | AC-C6 | chọn 3 ảnh trong Library | mở ⋯ | dòng ghi "Add to Album"; sheet mở ra có section "My Albums"; không chỗ nào còn chữ "Your Albums" | ⚠️ chưa có |
   | AC-Z3 | Duo inner 951×669, tab Collections | mở tab | hero cao 187pt (±1), nhìn thấy trọn ≥ 1 hàng tile Smart Albums dưới hero | ⚠️ chưa có |

## DESIGN.md

1. **§10.4 Sheet** — thêm (Q1): "Mọi sheet có nút đóng nhìn thấy được (Done/Cancel). Ở regular width + compact height
   (Duo inner) UIKit bỏ detent, sheet thành toàn màn; không có nút thì người không biết vuốt xuống là kẹt."
2. **§10.1d** — thêm "See All" (C5): tiêu đề nhóm có cover là nút mở lưới đầy đủ.
3. **§8 từ điển icon** — thêm hàng (C6, K32): "Ô Cloud Folders trong Utilities | `cloud`".
4. Các mục khác do agent spec ghi trong `spec-pending/<slug>.md` (C3 §10.6, Q6 §11, Z3 "669pt là cửa sổ thấp nhất", icon Cloud Folders §8).

## Không phải spec (ghi để /plan nhặt)
- **Q8** dòng `/release-check` (`.claude/skills/release-check/`): là cấu hình agent → chạy `Tools/evals` sau khi sửa.
- **P1** review bản tối + a11y-voiceover; **P2** board chấm sao / Pick / Reject / Cull; **P3** script `ShotDexUITests/scripts/core-loop.json`: việc của Build/Test, không có AC chức năng.
