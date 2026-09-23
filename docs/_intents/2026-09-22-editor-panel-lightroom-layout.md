# Intent: Panel editor trên màn rộng (iPad · Duo mở) dựng lại theo Lightroom iPad

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan |
| Ngày | 2026-09-22 |
| Trạng thái | accepted |
| Tiến độ | **đang làm** (2026-09-23) — FS-03.09: 10 commit; cột chứng minh mới có AC-16, 17, 20, chưa cập nhật theo code |
| Nguồn | phản hồi người dùng (chủ sở hữu sản phẩm) |
| Spec sinh ra từ đây | [FS-03.09](../02-functional-spec/FS-03-photo-editor/09-wide-screen-and-batch-editing.md) |

**Phạm vi thiết bị: iPad và iPhone Duo màn trong (lúc mở). iPhone nằm ngoài intent này** — panel 246pt và
bánh xe chip của phone giữ nguyên, không đụng tới trong lượt này.

## Problem — vấn đề

Trên màn rộng, editor đã có đúng hình hài Lightroom — rail dọc 48pt, panel bên, histogram đầu panel, danh
sách nhóm gập được — nhưng người dùng mở lên thì **không thấy histogram trên Duo, không thấy tool sổ ra, và
tổng thể trông xấu**.

Bằng chứng trong code:

- **Duo màn trong bị lấy mất histogram.** Ngưỡng `sidebarShortColumnHeight = 800`
  ([EditorLayoutMetrics.swift:105](ShotDex/Domain/Editing/EditorLayoutMetrics.swift:105)); Duo trong cao
  **669pt** nên luôn rơi vào nhánh "cột ngắn"
  ([PhotoEditorScreen.swift:836](ShotDex/Features/Editing/PhotoEditorScreen.swift:836)), và nhánh đó **bỏ
  luôn khối histogram** cùng hàng Look ([PhotoEditorScreen.swift:1187,1210](ShotDex/Features/Editing/PhotoEditorScreen.swift:1187)).
  Histogram rơi ngược về viên thuốc trên băng lệnh — tức là **đúng thiết bị người dùng đang phàn nàn thì
  histogram lại không ở đầu panel**. Lập luận trong comment là đúng về mặt số học (fixed furniture chiếm 49%
  của 593pt), nhưng kết luận sai: thứ bị cắt phải là thứ khác, không phải cái đồ thị người ta đọc liên tục.
- **Tool không "sổ hết ra từ đầu".** Sidebar có 8 nhóm dạng section gập được
  ([PhotoEditorScreen.swift:1493](ShotDex/Features/Editing/PhotoEditorScreen.swift:1493)) nhưng mặc định
  **chỉ `.light` mở** ([EditorChromeModel.swift:37](ShotDex/Features/Editing/EditorChromeModel.swift:37)).
  Mở editor lên là một nhóm mở và bảy tiêu đề đóng — vẫn phải bấm từng cái mới biết bên trong có gì.
- **Danh sách nhóm không phải là toàn bộ editor.** Mix và Point Color bị gộp làm segment bên trong Color
  ([PhotoEditorScreen.swift:1499](ShotDex/Features/Editing/PhotoEditorScreen.swift:1499)); Crop · Mask ·
  Markup · Presets nằm trên rail. Nên "nhìn một phát thấy app làm được gì" vẫn không đạt: cùng một editor
  đang kể chuyện của mình ở ba chỗ khác nhau (rail · section · segment trong section).
- **Trên cột ngắn, hàng Look cũng bị cắt** — Duo mở ra mất thêm một lối vào preset.
- **"ui xấu"** là nhận xét về chất lượng thị giác, chưa có ảnh chụp kèm. Cần chụp iPad 1376×1032 và Duo
  trong 951×669 (bằng `Tools/sim-shot`, vì không có cách khác lấy đúng khung của Duo) rồi đính vào
  `docs/_intents/assets/` trước khi sang Design — xem Open questions.

## Bằng chứng đo được — 2026-09-22

Ảnh thật, iPad 11" landscape **1210×834pt** (sim iOS 26.5) và Lightroom trên iPad thật **1194×834pt**.
Ảnh ShotDex: `assets/2026-09-22-editor-ipad-landscape.png`, `…-curve-color.png`, `…-crop.png`.
Ảnh Lightroom tham chiếu (người dùng tự chụp): `assets/lightroom-ref/lr-01…17.png`.

**ShotDex hôm nay**

| Đo được | Số |
|---|---|
| Băng lệnh trên | 5 nút dồn trái (x 20…277), ⋯ ở x=1146 → **869pt trống ở giữa** |
| Panel | x=842, rộng **320pt**; rail 48pt ngoài cùng |
| Chỉ Light mở | Light chiếm **441pt** (y 258→699) |
| Nhóm ngoài màn | Color y=744 **nằm dưới hàng Save (y=764)**; Grade 789 · Effects 834 · Detail 879 · Optics 924 · Geometry 969 → **6/8 nhóm phải cuộn** |
| Gập hết | cả 8 nhóm vừa trong **359pt** (258→617), dư 147pt |
| Mở hết | nội dung chạy tới y=**1264**, vượt mép dưới **430pt** |
| Chip bị cắt | Crop mất "16:9", Curve mất "Da[rken]" — cụt ở mép panel, không có dấu hiệu cuộn |
| Panel rỗng | Crop bỏ trống ~490pt; Mask (chưa có mask) ~420pt |

**Lightroom iPad cùng khổ màn** (`assets/lightroom-ref/`, iPad 11" 1194×834pt, chụp 2026-09-22)

| # | Lightroom làm | Ảnh | ShotDex hôm nay |
|---|---|---|---|
| 1 | Thanh trên **dồn hết về phải** (undo · redo · help · share · cloud · ⋯), trái chỉ có Back | lr-02 | 5 nút dồn trái + ⋯ tận phải, **869pt trống giữa** |
| 2 | Panel ~**259pt** + rail 48pt; đầu panel là `Edit`+`Auto`, rồi `Profile / Browse` | lr-02 | panel 320pt + rail 48pt; đầu panel là histogram rồi `EDIT`+`Auto`, rồi `Look / Browse` |
| 3 | **Năm nhóm**: Light · Color · Effects · Detail · Optics. Curve là **một nút biểu tượng ngay hàng tiêu đề Light**; Mixer/Grading nằm trong Color; Geometry nằm trong công cụ Crop | lr-02, lr-03 | tám nhóm phẳng: Light · Curve · Color · Grade · Effects · Detail · Optics · Geometry (Mix/Point là segment trong Color) |
| 4 | Mở một nhóm thì nhóm đó **cuộn lên đầu**, các nhóm còn lại vẫn thấy; Light chỉ 6 slider (không Brilliance/Brightness), bước hàng ~52pt | lr-03, lr-05 | Light 8 slider, 441pt, đẩy 6/8 nhóm ra ngoài màn |
| 5 | **Slider phụ mờ đi cho tới khi slider cha khác 0** (Midpoint/Roundness/Feather/Highlights chờ Vignette; Size chờ Grain), và các cụm ngăn nhau bằng nét mảnh | lr-05 | mọi slider sáng như nhau, không phân cụm |
| 6 | Mask là **chế độ có cam kết**: panel đổi thành `Masking`, dùng **lại đúng danh sách nhóm** nhưng **mờ cho tới khi có mask**, một nút `+` nổi, và `Cancel / Apply` ở đáy | lr-11 | Mask là một mục trên rail, panel riêng, không có bước Apply |
| 7 | Mỗi loại mask có **thẻ giải thích kèm ảnh ví dụ** rồi mới `Create` | lr-13 | chọn loại xong là vào thẳng |
| 8 | Chín loại mask: subject · sky · **background** · brush · linear · radial · color range · luminance range · **depth range** (mờ khi ảnh không có độ sâu) | lr-12 | bảy loại (thiếu background, depth range) |
| 9 | **Film strip** ảnh kế bên chạy ngang đáy màn | lr-02 | film strip chỉ có khi sửa nhiều ảnh |
| 10 | **Versions** (tab Auto / Named, có "Current edits" và "Original") | lr-15 | chỉ có History trong phiên |
| 11 | Slider: tên trái, giá trị phải, **track một dòng riêng**, núm tròn rỗng | lr-03 | cùng bố cục, núm là vạch đứng |

## Những chỗ cố ý KHÔNG bắt chước Lightroom

Người dùng chốt 2026-09-22:

1. **Histogram dính ở đầu panel Edit** như ShotDex đang làm — không thả nổi trên ảnh như Lightroom.
2. **Curve nằm trong panel Edit**, không mở thành lớp phủ trên ảnh.
3. **Chọn mask sẽ làm hơn Lightroom**, không chép nguyên cách của họ.

Phần còn lại của bảng trên là **đáng học**: thanh trên dồn phải (#1), mở nhóm thì nhóm đó lên đầu mà không
nuốt các nhóm khác (#4), slider phụ mờ cho tới khi cha khác 0 (#5), thẻ giải thích trước khi tạo mask (#7).
Ba thứ cần cân nhắc riêng vì nó đổi mô hình chứ không chỉ đổi bố cục: gộp Curve vào Light và Grade/Mix vào
Color (#3), mask có bước `Apply` (#6), film strip ở đáy (#9).

## Proposed outcome — kết quả mong muốn

- **Histogram ở đầu panel trên mọi màn rộng, kể cả Duo mở** — không bị nhánh cột ngắn lấy mất. Cái gì phải
  nhường chỗ trên 669pt thì là thứ khác, và phải nói rõ là thứ gì.
- **Mở editor lên là thấy toàn bộ tool**: mọi nhóm sổ sẵn (hoặc thấy được ngay bằng một cử chỉ), không phải
  bấm từng tiêu đề để biết bên trong có gì. Người mới biết ngay app làm được gì; người quen tới thẳng mục
  mình cần.
- **Một chỗ duy nhất kể chuyện editor có gì** — hết cảnh rail nói một phần, section nói một phần, segment
  bên trong section nói phần còn lại.
- Tổng thể **trông hiện đại hơn Lightroom iPad 2026**, không phải giống nó: cùng mô hình thao tác, chi tiết
  sạch hơn (nhịp chữ, khoảng cách, phản hồi khi chạm, chuyển động).
- Người quen Lightroom iPad mở ShotDex **không phải học lại** chỗ nào đặt cái gì.

## Affected users and systems — phạm vi ảnh hưởng

- **Màn hình**: Photo Editor (tier D), nhánh màn rộng — `sidebarColumn` và các hàm quanh nó trong
  `ShotDex/Features/Editing/PhotoEditorScreen.swift` (2819 dòng), `EditorSidebar.swift`,
  `EditorToolPanels.swift`, `EditorChromeModel.swift`.
- **Domain**: `EditorLayoutMetrics.swift` — mục "Wide-screen sidebar" (dòng 56-120): ngưỡng cột ngắn 800,
  rail 48, histogram 92, header 44/40, hàng Look 52, dải rộng sidebar 280…420.
- **Thiết bị**: **iPad 1376×1032 dựng trước**, rồi **Duo trong 951×669** (màn ngắn nhất được ship — mọi
  quyết định về chiều cao sống chết ở đây). iPhone và Duo màn ngoài **không đổi** trong intent này.
- **Dữ liệu đã lưu**: không đụng schema. Có đụng khoá `UserDefaults` về chrome
  (`SettingsKeys.editorSidebarWidth`, `shotdex.edit.histogramCorner`) — khoá nào chết thì dọn.
- **Extension**: ShotDexEdit có UI riêng; cần xác định nó có đi theo không (Open questions).

## Constraints — ràng buộc

- **`DESIGN.md` là luật**: không đẻ token, màu, bo góc, component mới khi đã có cái tương đương. Editor là
  tier D — dùng đúng entry point glass tier D, không dùng `glassBackground` sáng.
- **Ảnh không bao giờ bị chrome đè** (luật chung FS-03) — vẫn giữ.
- **Không đụng nhánh iPhone**: panel 246pt và bánh xe 14 chip giữ nguyên. Sửa cùng file thì phải giữ cả hai
  đường chạy được.
- **Luật "phone có đủ mọi thứ iPad có"**: danh sách nhóm phải dựng bằng cách duyệt catalog/`allCases`, không
  viết tay theo thiết bị — đã mất cả nhóm Color và cả hàng transport theo kiểu đó rồi.
- **Nhánh iOS 26 và pre-26 phải cùng chạy.**
- **Duo trong chỉ có 669pt**: mọi đề xuất "thêm một hàng cố định" phải trả lời bằng số nó lấy đi bao nhiêu
  dòng slider. Comment ở `EditorLayoutMetrics.swift:94-105` đã có sẵn phép tính — dùng lại, đừng đoán.
- **Preview không hạ độ phân giải để chạy mượt** (FS-03.04).
- **Không thêm dependency.** Không rời máy dữ liệu người dùng.

## Open questions — câu hỏi còn treo

1. **Trên Duo trong (669pt), giữ histogram thì cắt gì?** Ứng viên: hàng Look (đã bị cắt sẵn), mode header
   40pt, footer 74pt, hoặc thu histogram từ 92 xuống ~56pt. → `duo-ux-review` + `device-layout` đo, người
   dùng chốt.
2. **"Sổ hết tool" = mọi section mở sẵn, hay mở sẵn + nhớ trạng thái theo ảnh?** Hiện tại là session state
   (`expandedSidebarGroups`). Mở hết trên 669pt thì phải cuộn rất dài — có chấp nhận không? → người dùng.
3. **Mix và Point Color có tách khỏi Color thành section riêng không?** Tách thì danh sách thành 10 nhóm và
   "thấy hết" đúng nghĩa; giữ thì đỡ dài nhưng vẫn giấu hai tool. → `/spec` + `prior-art`.
4. **Crop · Mask · Markup · Presets vẫn chỉ ở rail, hay cũng xuất hiện trong danh sách?** → `/spec`.
5. **Ảnh chụp hiện trạng** iPad + Duo trong đã chụp chưa, và "xấu" cụ thể là xấu ở đâu (khoảng cách? kích
   thước chữ? màu? mật độ?) → chụp bằng `Tools/sim-shot`, đính vào `docs/_intents/assets/`, người dùng chỉ
   mặt từng chỗ.
6. **ShotDexEdit extension có đổi theo không?** → `extension-boundary`.
7. **"Hiện đại hơn Lightroom" đo bằng gì?** Cần tiêu chí kiểm được (số thao tác tới một slider bất kỳ, số pt
   ảnh còn lại ở trạng thái mặc định, số nhóm nhìn thấy mà không cuộn) chứ không phải tính từ. → người dùng
   + `/spec`.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
