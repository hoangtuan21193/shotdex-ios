# FS-18.01 — Cửa sổ và điều hướng

`FS-18.01` · board `Main` · `MAC_EmptyLibrary` · `MAC_VideoStudioCompact` · luật vẽ ở
[MAC_STYLE.md](../../design/mac/MAC_STYLE.md) · cập nhật 2026-10-04

**Một câu:** một cửa sổ chính gồm sidebar nguồn ảnh, toolbar và inspector; Viewer và Editor mở ngay trong nó, cửa
sổ riêng là tuỳ chọn.

## 1. Cấu trúc cửa sổ chính

| Vùng | Số đo |
|---|---|
| Sidebar | panel kính nổi, cách mép cửa sổ 8, rộng **228**, bo 18; đèn giao thông ở (14, 16) bên trong nó |
| Toolbar | không có thanh tiêu đề; một hàng 44 ở y 8, từ x 256 tới mép phải trừ 16; capsule kính cao **36** |
| Nội dung | bắt đầu ở x 244, cuộn **dưới** toolbar, vùng mờ mép trên 64 |
| Inspector | **300** (Library, Viewer), **320** (Editor); cao hết cửa sổ, nét 1 bên trái |
| Chữ | thân 13, phụ 11–12, tiêu đề mục 15 đậm vừa, tiêu đề lớn tối đa 22; **sàn 10** ở mọi chỗ |

- Không có tab bar, không có chế độ Select, không có nút tròn nổi trên ảnh. Hover có trạng thái riêng.
- Khoảng cách 4/8/12/16/20/24; số thay đổi (EXIF, đếm, %) dùng chữ số đều bề rộng.

- Token Mac (bo 18/10/14, nút 28, nền menu/sheet/scrim/hàng xen, accent đậm) nằm ở **mục Mac của
  [DESIGN.md](../../../DESIGN.md)**, viết trước `/plan`. MAC_STYLE là luật vẽ board, không phải nguồn token.
- **macOS 15–25**: sidebar và toolbar là bản hệ thống của macOS đó, không vẽ giả kính; cùng vùng, cùng lệnh,
  cùng phím như macOS 26 ([05](05-platform-and-distribution.md) §1).

## 2. Sidebar chuẩn

- Bốn nhóm, tối đa 2 cấp: (không tiêu đề) All Photos · Favorites · Videos · RAW · Recently Added ·
  **Sources** `[+]` · **Collections** `[+]` (On This Day, Albums ›, smart album, Hidden — FS-19) · **Utilities**.
- Utilities: Statistics · Places · Trips · Duplicates · Collages · Video Projects · On Server.
- Albums luôn có chevron, đóng mặc định; mở ra là danh sách phẳng, không thư mục (D19).
- Đếm có ở Library, Sources, Collections, Trips, Duplicates (số nhóm), Collages, Video Projects, On Server;
  Statistics, Places, On This Day, Recently Added không có số.
- Hàng chọn = nền xám, icon accent. Icon hàng luôn amber (D11).
- Chân sidebar: nghỉ thì "Up to date · indexed 2 min ago"; đang index thì "Indexing ‹nguồn› 41%" + thanh tiến độ.
- Bốn trạng thái hàng nguồn (gắn ngoài, offline, đang thêm, cần cấp quyền) do FS-19 định nghĩa.

## 3. Toolbar

- Tối đa **3 nhóm capsule** + ô search. Đầu: nút sidebar, ◀ ▶, tiêu đề 15 + dòng phụ 11.
- Cuối: nút inspector (ô cuối của capsule icon ngoài cùng), search, rồi **một** nút nổi bật ở mép phải.
- Nút nổi bật chỉ dành cho lệnh chốt của cửa sổ (Done, Export…, Resize N Photos); không bao giờ là lệnh xoá.
- Nút chữ trên toolbar cao 36. Segmented chỉ chữ hoặc chỉ symbol.
- Nhãn đổi theo hành động: "Show Inspector" / "Hide Inspector", "Show Sidebar" / "Hide Sidebar".
- Dòng phụ: không chọn "54,027 photos · 1,204 videos"; có chọn "6 selected · 214.8 MB";
  đang lọc "212 of 55,231 photos" — lưới và bảng ghi giống nhau.
- **60pt đáy cửa sổ không có gì bấm được**, trừ filmstrip và timeline; thanh đáy chỉ mang chữ trạng thái.

## 4. Cỡ tối thiểu và thu gọn

| Cửa sổ | Tối thiểu | Thu gọn |
|---|---|---|
| Library / cửa sổ chính | **1024×700** | sidebar tự ẩn dưới **1100** rộng (**1280** khi inspector mở); nút sidebar vẫn ở toolbar |
| Editor | như cửa sổ chính, **1024×700** | dưới **1100**: segmented công cụ thành icon + tooltip; inspector 320 mở ra thì **đè lên mép phải ảnh**, ảnh không co |
| Video Studio | **1180×760** | media browser và inspector tự ẩn dưới 1280; timeline cao ≥ 180, kéo đổi được |

- Toolbar Library tràn thì bỏ theo thứ tự: thanh zoom → Share → ô search thu thành nút.
- Sidebar tự ẩn rồi cửa sổ rộng lại qua ngưỡng thì sidebar tự hiện lại — trừ khi người dùng đã tự ẩn nó.
- Mở Editor (hay Collage, Resize, Combine Photos) **không bao giờ tự nới cửa sổ**; dưới 1100 là bố cục thu gọn ở trên.

## 5. Viewer, Editor và nhiều cửa sổ (D9, D14)

- Return (hoặc nhấp đúp) mở Viewer **trong cửa sổ chính**: sidebar ẩn, ◀ quay về. Esc hoặc ◀ về lưới đúng chỗ
  cuộn và đúng lựa chọn cũ ([FS-02.01b](../FS-02-photo-detail/01b-closing-and-keyboard.md) §1).
- ⌘E từ lưới hay Viewer mở Editor cũng trong cửa sổ đó; Esc/◀ về nơi đã mở nó.
- **Open in New Window ⌥⌘O** mở Viewer của lựa chọn ở cửa sổ riêng; cửa sổ chính không đổi.
- Settings › General › Open Photos: **In the Same Window** (mặc định) · **In a New Window**.
- File › New Window (không phím tắt) mở thêm một cửa sổ thư viện độc lập.
- **Collage, Resize, Combine Photos** mở trong cửa sổ chính như Editor: panel trái của công cụ thế chỗ sidebar,
  ◀ hoặc Cancel về nơi đã mở nó.
- **⌥⌘O** khi đang ở Editor, Collage, Resize hay Combine Photos: màn đó sang cửa sổ riêng, cửa sổ chính về nơi đã mở nó.
- Cửa sổ riêng: Video Studio (Window › Video Studio ⌥⌘V), Settings ⌘, , Get Info ⌘I (panel), Activity ⌥⌘0,
  Support. Cửa sổ phụ vẽ nút thu nhỏ/phóng to tắt.
- **Activity** gom mọi việc chạy lâu (index, upload, nhập thẻ, xuất, ghép ảnh) — không bao giờ là sheet modal.
- Không có màn hình thứ hai / Secondary Viewer (D14).

## 6. Toàn màn hình

- ⌃⌘F cho mọi cửa sổ chính. Viewer toàn màn (`MAC_ViewerFullScreen`): góc bo 0, toolbar và sidebar ẩn,
  navigator 216×177 góc trên phải, HUD kính ở đáy hiện khi rê chuột.
- HUD: Previous/Next, tên file, Zoom −/mức/+, sao 1–5, Show Inspector. Không có nút thoát tự vẽ.
- Z bật/tắt Fit ↔ 100%. Esc thoát toàn màn trước; Esc lần hai về lưới.

## 7. Lần mở đầu (D13)

- Không có cửa sổ Onboarding. Thư viện chưa có nguồn → cửa sổ chính hiện trạng thái trống `MAC_EmptyLibrary`.
- Tiêu đề "Welcome to ShotDex", một câu giới thiệu, ba thẻ: **Photos Library** · **Folder or Drive** · **Server**,
  nút **Add Photos Library…** · **Add Folder or Drive…** · **Connect to Server…**.
- Vùng thả 672×84 "or drop a folder here": thư mục, ổ đĩa hay thẻ nhớ từ Finder, hoặc thả lên Sources.
- Sidebar vẫn đủ nhóm, Sources ghi "No sources yet"; dòng phụ toolbar "No photos yet".
- Hộp quyền Photos của macOS chỉ hiện **sau** khi bấm Add Photos Library… — không hỏi lúc khởi động.

## 8. Accent (D11)

- Accent luôn là amber của ShotDex, không theo accent hệ thống. Không có hàng Accent Color trong Settings.
- Nút mặc định và highlight menu dùng bản đậm (#A35E0A sáng / #EB9526 tối, chữ trắng / đen); glyph, vòng chọn,
  tiến độ dùng accent thường. Tầng D: highlight menu #EB9526 chữ đen.
- Luật chọn: vòng amber (ô lưới) · nền amber (menu, hàng bảng đang focus) · nền xám (sidebar, bảng không focus) ·
  vòng trắng (filmstrip tầng D) · #57BFD1 chỉ trên timeline Video Studio · đỏ = đánh dấu xoá.

## 9. Vùng bấm

- Mac theo chuẩn con trỏ: mọi control bấm được **≥ 20×16**; nút toolbar 28, nút chữ toolbar cao 36.
- *Chốt 2026-10-04:* đây là ngoại lệ Mac của luật 44×44 ở
  [NF-06](../../04-non-functional-design/NF-06-accessibility-and-localization.md) §1 — *vì không có ngón tay, chỉ con trỏ.*
