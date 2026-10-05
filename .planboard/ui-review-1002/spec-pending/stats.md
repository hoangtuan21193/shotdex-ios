# Pending spec edits — slug `stats` (Q4, Q5, C1–C4, C6, S4, F1–F3, Z3)

Áp khi file đích không còn thay đổi chưa commit của phiên khác, hoặc do agent sở hữu file đó. Mỗi mục: file · section · chữ thay · ID.

## DESIGN.md

1. **§10.6, bullet "Accent cố định là amber…"** (C3) — thay đoạn
   > accent chỉ dùng cho phần ShotDex tự vẽ: badge chọn ảnh trong lưới, trạng thái active của editor (`EditorTheme.accent`), chart.

   bằng
   > accent chỉ dùng cho phần ShotDex tự vẽ: badge chọn ảnh trong lưới, trạng thái active của editor (`EditorTheme.accent`).
   > **Biểu đồ không dùng accent**: series theo `ChartPalette.colors`, mở đầu bằng indigo; cột một chuỗi tô dải indigo (2026-10-02).

   Kèm (cho /plan, là code): comment ở `ShotDex/App/Theme/AppAccentTheme.swift:9` bỏ chữ "charts".
2. **§3.4 Biểu đồ** (C3) — thêm sau câu hiện có:
   > Series đầu và cột một chuỗi là **indigo** hệ thống; accent amber không xuất hiện trong thẻ biểu đồ.
3. **§7.3 Số liệu** (Q4) — thêm bullet:
   > Số đếm và phần trăm định dạng theo vùng của máy ("22,640", "34%"; de-DE "22.640", "34 %"). Năm, tháng, ISO,
   > khẩu, tốc độ, tiêu cự không nhóm hàng nghìn ("2026", "ISO 3200").
4. **§10.1c, cuối mục** (Z3) — thêm:
   > **669pt (Duo trong) là cửa sổ regular-width thấp nhất app ship.** Cửa sổ dưới 720pt là *cửa sổ thấp*
   > ([NF-05 §4](docs/04-non-functional-design/NF-05-device-and-os-compatibility.md)): bề rộng vẫn chọn số cột,
   > nhưng mọi số đo theo chiều cao lấy bản thấp; các khối không cuộn ≤ 50% chiều cao cửa sổ.

5. **§10.1e, bullet hero** (Z3) — thay "**180 (compact) → 260 (regular)**" bằng
   > **180 (compact) → 260 (regular)**; cửa sổ thấp + regular: **0,28 × chiều cao cửa sổ, sàn 180, trần 260** (187pt ở 669).

## docs/02-functional-spec/FS-06-collections/01-tabs-tokens-and-album-management.md

1. **§3 Hàng hero** (Z3) — đã có ở `main.md` mục 3; ngưỡng "cửa sổ thấp" là **< 720pt** theo NF-05 §4.
2. **Tile album** (Z3) — thêm bullet ở chỗ ghi cạnh tile 132 / 192:
   > Cửa sổ thấp + regular (Duo trong 669pt): cạnh tile **132pt** (số compact) thay 192pt; số tile mỗi hàng vẫn theo bề rộng.
3. **AC thêm:**
   | # | Cho | Khi | Thì | Chứng minh bằng |
   |---|---|---|---|---|
   | AC-Z3b | (Z3) Duo trong 951×669, tab Collections, ≥ 8 smart album | mở tab | tile Smart Albums cạnh 132pt ±1; dưới hero thấy trọn ≥ 1 hàng tile mà không cuộn | ⚠️ chưa có |
   | AC-Z3c | (Z3) iPad 13" ngang 1376×1032 | mở tab Collections | tile 192pt, hero 260pt — không đổi | ⚠️ chưa có |

## docs/02-functional-spec/FS-07-statistics/02-insights.md

1. **§6 bảng Bề rộng / Bố cục** (Z3) — thêm hàng:
   > | Rộng + cửa sổ thấp (Duo trong 669pt) | các câu xếp **một hàng**, mỗi câu một cột (tối đa 3, cột ≥ 280pt); quá bề rộng thì về số cột của dashboard |

   ⚠️ CẦN QUYẾT: dạng Insights trên cửa sổ thấp — phương án a một hàng câu như trên (thẻ ~120pt ở 669, không cắt chữ) /
   b dải 64pt cuộn ngang (đề xuất gốc M-52, giấu câu thứ 2–3) / c giữ như nay; đề xuất **a**.
2. **§6 bảng trạng thái** (F2, F3) — tuỳ ⚠️ CẦN QUYẾT ở FS-07.01b §5. Nếu chọn **b** (dải đầu màn nói một lần):
   - hàng "đang index": thay "chân thẻ "Updating as your library is indexed."" bằng "câu tính trên phần đã index; không chân thẻ — dải "Still reading photo info · N%" của dashboard nói thay ([FS-07.01b §5](01b-cards-editor-and-states.md))";
   - hàng "quyền `.limited`": thay chân thẻ bằng "câu tính trên tập được cấp; banner Limited Access của dashboard nói thay";
   - sửa theo: FS-07.03 AC-14 (bỏ phần chân thẻ, giữ câu 85%).

## docs/02-functional-spec/FS-07-statistics/README.md

1. **§Các phần, hàng 03** (Q5 + AC mới) — "AC-1…18" → "AC-1…58".
2. **§2 Phạm vi, bullet đầu** (Q5) — "lần đầu gieo 6 biểu đồ trả lời các câu ở §1" → "lần đầu gieo 7 biểu đồ (thêm Top Lens) trả lời các câu ở §1".
3. **§4 Rủi ro, hàng "Máy đã có cờ…"** (Q5) — cột Xử lý thay bằng: "bộ gieo có số thế hệ, hiện là 3; máy ở thế hệ cũ được thêm các biểu đồ còn thiếu vào cuối, một lần ([01](01-dashboard.md) §3)".

## docs/03-extensions-and-integrations/EX-02-widget.md (chủ Z4)

1. Chỗ ghi preview của Widget editor (Z4): "màn thấp" nghĩa là **cửa sổ thấp** của [NF-05 §4](../04-non-functional-design/NF-05-device-and-os-compatibility.md) — < 720pt, gồm Duo trong 669 và Duo ngoài 678.

## FS-01.03 (Advanced Search) · FS-06.08 (Smart Album editor) — chủ S4

1. Hàng Media Type + Match: Chart editor (FS-07.01b §4) dùng đúng hàng của bộ dựng điều kiện dùng chung — 44pt, hai nhãn VoiceOver "Media Type", "Match", câu giải thích thành chú thích dưới hàng. Giữ hai doc kia cùng chữ.
2. Phần ghim (số ảnh khớp + Search) theo ngân sách cửa sổ thấp NF-05 §4: khối không cuộn ≤ 50% chiều cao cửa sổ.

## FS-03.07 (Compress) · FS-11b (Collage Export) — chủ Z1

1. Cửa sổ thấp (NF-05 §4) không bỏ hai pane ở regular; preview không cao cố định; nút chính ghim đáy pane phải, thấy mà không cuộn ở 669pt.
