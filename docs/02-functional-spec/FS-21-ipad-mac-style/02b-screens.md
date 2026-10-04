# FS-21.02b — Từng màn iPad (2): Settings, công cụ tầng D, lần mở đầu, server, Video Studio

`FS-21.02b` · nhánh màn rộng của `Features/Settings`, `Collage`, `Compression`, `Onboarding`, `ServerUpload`,
`ServerImport` · cập nhật 2026-10-04

**Một câu:** phần còn lại của các màn iPad — cái gì dời lên toolbar, cái gì vào inspector 360, và lần mở đầu mới.

## 1. Settings — `IP_Settings`, `IP_WidgetSettings`, `IP_CompressionPresets`, `IP_CameraDatabase`, `IP_Support*`, `IP_ServerList`, `IP_ServerForm`

- Gear ở đầu sidebar (hoặc ⌘,) → Settings chiếm cả cửa sổ: sidebar 320 riêng của Settings (Hide Sidebar · **Done**),
  tiêu đề Settings 28 + dòng phụ, ô Search Settings, rồi các mục — hàng 44, ô biểu tượng 28, giá trị ngắn bên phải.
- Mục trên board: **Sources** · Display · Playback · People and Pets "76%" · Camera Database "6 unknown" · Sharing and
  Export · Widgets "3 designs" · Notifications "9:00 AM" · Support.
- Pane **Sources**: danh sách nguồn (tên, nhãn loại, đường dẫn · số mục, chấm trạng thái) với Manage Access… /
  Re-index / Remove… / Grant Access…; Add Folder or Drive… · Connect to Server…; nhóm Metadata (công tắc `.xmp`) và
  Drives and Indexing. Nội dung và hành vi: FS-19.
- File Servers nằm trong Sharing and Export (Back "Sharing and Export"): bảng kết nối hàng 44 có trạng thái, Thumbnail
  Cache + Clear, Cache Size Limit, Add Connection trên toolbar → form sheet 700×640.
- **Màu**: nút viền xám chữ màu chính, nút chữ trần màu tint hệ thống, công tắc xanh hệ thống, ô biểu tượng màu hệ
  thống theo mục; **không amber nào** (FS-08.01b AC-9). Bố cục split view giữ DESIGN §10.1f.

- Mục 1 tên **Sources ở mọi thiết bị** (iPhone, iPad, Duo; Mac là pane Sources) — một danh sách cho hai bố cục
  (DESIGN §10.1f), và iPhone cũng có nguồn thư mục, ổ, server (FS-19). Không còn mục nào tên Photo Library.
- Pane Sources theo board: không có thẻ Your library ở đầu; số ảnh và trạng thái quyền nằm trên hàng của từng nguồn.

## 2. Công cụ tầng D — `IP_Collage`, `IP_CollageExport`, `IP_Compress`, `IP_FocusStack`, `IP_StackExposures`, `IP_Panorama`, `IP_VideoTrim`, `IP15_Cull`

| Màn | Toolbar | Inspector 360 |
|---|---|---|
| Collage | Back · `[Undo · Redo]` `[Before and After · ⋯]` · Hide Inspector · **Export…** | Number of Photos − + · Save Preset · Aspect Ratio ▾ · Layout lưới 4 cột ô 76 · Border/Gap/Corner · Background 5 ô · Polaroid · Title |
| Xuất collage | Back · Share… · **Save to Photos** | Size Fit/2K/4K/Max · Quality · Format JPEG/HEIC · Keep EXIF of first photo · dung lượng ước tính |
| Resize | Cancel · Hide Inspector · **Resize 8 Photos** | Size 4 ô 159×60 · Quality · Format ▾ · Metadata ▾ · Delete Originals |
| Combine Photos | Hide Inspector · Cancel · **Save** | tuỳ chọn của từng kiểu (Depth Map / Weighted, Retouch …) |
| Cắt video | Cancel · Reset · **Save** | — (tay cắt 24×72 trên dải khung) |
| Cull | Back · Reject · 1–5 sao · Pick · Undo, mỗi nút 44 | — (FS-01.12b) |

- Nút chính rời đáy cột lên **mép phải toolbar**, luôn thấy, không cần cuộn — kể cả ở cửa sổ thấp (NF-05 §4).
- Chữ nút chính vẫn nói hết việc nó làm: "Resize 8 Photos and Delete Originals" khi bật xoá (FS-03.07 D4).
- Xem trước lấy phần bên trái inspector; Collage khung dựng 800×800 ở 1016pt.

**Collage giữ đủ lệnh của FS-11 §3** (board `IP_Collage` vẽ thêm):
- **Before and After** trên toolbar: giữ để xem bản gốc, thả là về — cùng hành vi nút giữ-xem-gốc của điện thoại.
- **⋯** có **Discard**, cùng hành vi menu Discard của FS-11 §3.
- **Khay ảnh chưa đặt** là panel trái (chỗ sidebar, sidebar ẩn trong tầng D): thumbnail các ảnh chưa xếp ô, kéo ra
  khung dựng để đặt, kéo ô vào panel để cất. Ẩn khi rỗng; hiện thì khung dựng co vào phần còn lại.

**Công cụ tầng D khi dọc** (1032 và 834): giữ **cột inspector 360 bên phải** như Editor dọc, nút chính trên toolbar,
không thành sheet. Board dọc vẽ trước `/plan`: Collage, Xuất collage, Resize, Combine Photos (`IPP21…`, [03 §5](03-spec-deltas.md)).

## 3. Lần mở đầu — `IP_Onboarding`, `IP_EmptyLibrary`

- Chưa có nguồn: cửa sổ đủ khung (sidebar ghi "No sources yet", toolbar "No photos yet"), giữa là thẻ chào: ShotDex
  + 4 câu + **Continue** 320×50 + dòng "Next: add your Photos Library, a folder or drive, or a server".
- Câu 4 của thẻ chào là **"Your photos stay where they are"** ở mọi thiết bị (thay "Your photos stay on your device"
  của FS-09). Continue rộng **320** trên iPad; thiết bị khác giữ số của FS-09.
- Continue **không** mở hộp quyền Photos. Nó đưa tới **thư viện trống**: "Welcome to ShotDex", ba thẻ 249×240 —
  Photos Library (Add Photos Library) · Folder or Drive (Add Folder or Drive) · Server (Connect to Server).
- Dưới ba thẻ: vùng thả 780×84 "or drag a folder here" (từ Files ở Split View/Slide Over), dòng thẻ nhớ (FS-20,
  chạm mới mở), dòng "Photos stay where they are. ShotDex never edits file contents."
- Hộp quyền Photos chỉ mở khi chạm Add Photos Library; dòng báo trước của FS-09 F1 nằm trong thẻ đó ("iPadOS asks
  you to allow access."). Trạng thái quyền và thông báo của từng trạng thái giữ FS-09 §3, áp cho nguồn Photos.


## 4. Server trên iPad — `IP_ServerList`, `IP_ServerForm`, `IP_ServerBrowser`, `IP_ServerUpload`, `IP_UploadedToServer`

- Server là **nguồn được index** (người dùng chốt 2026-10-04): một hàng trong Sources của sidebar; chạm hàng = lưới
  như Library. Luật index, cache, xoá: FS-19. iPhone và Duo cũng có server là nguồn (FS-19, bố cục compact).
- Upload to Server… (⋯ của lựa chọn, ⇧⌘U): sheet cho N ảnh như FS-15.02, dạng form sheet ≤ 700×640.
- On Server (Utilities): hàng Free Up Space "214 photos · about 4.2 GB" + All Uploaded Photos (FS-15.02c).
- iPad **không có Import to Library** từ server; muốn có bản trong Photos thì dùng **Save to Photos** — một lệnh xuất
  (FS-19). Board `IP_ServerBrowser` bỏ glyph "In Library"; `IP_MenuBar` bỏ "Import from Server… ⇧⌘I".

## 5. Video Studio — `IL*`, `IP1_Main` …

- Số đo iPad (pool 320, inspector 360, đầu track 200, sheet xuất 700) do phiên Video Studio viết vào FS-12.03 / 03b / 16.
- Từ FS-21 áp: toolbar kính ở trên, một nút nổi bật (Export) mép phải, inspector 360, menu bar có lệnh Video
  (`F6_IL_Shortcuts`), skim bằng con trỏ chỉ là phần thêm (`F6_IL_HoverScrub`), Pencil cắt khi dọc (`F6_IP_PencilTrim`).
