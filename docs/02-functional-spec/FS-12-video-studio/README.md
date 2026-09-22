# FS-12 — Video Studio

`FS-12` · tier D · `ShotDex/Features/VideoStudio/` · `Data/Sources/Video*.swift` · `Domain/Video/`
· test `Video{Timeline,Geometry,Effect,Split,Trim,Transport,Scope,LUTRenderer}Tests`
· `VideoStudio{Layout,DeskLayout}Tests` · cập nhật 2026-09-22

**Một câu:** dựng một cuốn phim ngắn từ ảnh và video của chính mình — timeline nhiều lane, chuyển cảnh,
nhạc, chữ, và một tầng màu đủ để grade.

## Các phần

| # | Phần | Trả lời |
|---|---|---|
| 01 | [Render và export](01-render-and-export-pipeline.md) | một đường dựng cho cả preview lẫn export, compositor tự viết, xương sống cho ảnh |
| 02 | [Năng lực biên tập](02-editing-capabilities.md) | speed, freeze, split, tỉ lệ khung, nền, nhạc nhiều bản, sticker |
| 03 | [Timeline và bàn dựng](03-timeline-and-desk-layout.md) | chia preview/timeline, năm băng của màn rộng, meter, track header |
| 04 | [Công cụ và inspector](04-tools-and-inspector.md) | bỏ cột công cụ, lệnh chèn về thư viện, Quick Adjust |
| 05 | [Cắt, marker, fade](05-cutting-markers-and-fades.md) | độ dài transition, trim to playhead, snapping |
| 06 | [Tầng màu](06-color-layer.md) | de-log, primaries, power window, node chain |
| 06b | [Scope, LUT, tracker](06b-scopes-luts-and-tracking.md) | bốn máy đo, LUT nhập từ Files, bám window theo khung |
| 07 | [Bố cục điện thoại](07-phone-layout.md) | lane động, overlay trên preview, transport hẹp |
| 08 | [Model và giới hạn v1](08-model-and-v1-limits.md) | project giữ gì, nhạc từ đâu, cố ý chưa làm gì |

## Quy tắc chung

- **Preview và export đi chung một đường dựng** — khác nhau đúng ở kích thước khung và ở đầu ra.
- **Điện thoại có đủ mọi chức năng của iPad**; danh sách công cụ dựng từ một nguồn duy nhất.
- **Phần dư của màn thuộc về quanh khung hình**, không thuộc về dưới các track.
- Mọi toán quyết định (timeline, split, hiệu ứng, hình học, scope, tracker) nằm ở Domain và **có test**.
- Nhạc **chỉ** đến từ file người dùng có quyền ([08](08-model-and-v1-limits.md)).

## Tiêu chí nghiệm thu

> **Đây là ví dụ mẫu cho toàn bộ tài liệu** — các `FS-*` khác chưa viết mục này.
> Dạng: **Cho** trạng thái có số → **Khi** một thao tác → **Thì** kết quả quan sát được.
> Cột cuối phải là một test thật hoặc một script `Tools/ui-drive` thật; chưa có thì ghi **chưa có**.

### Biên tập clip

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | timeline 1 clip dài 10,0 s; playhead tại 4,0 s | bấm **Split** | có 2 clip `[0,0–4,0]` và `[4,0–10,0]`; tổng thời lượng không đổi; clip phải được chọn | ⚠️ **chưa có** — cần test cho Split tại playhead |
| AC-2 | vừa thực hiện AC-1 | bấm **Undo** một lần | về đúng 1 clip dài 10,0 s, playhead vẫn ở 4,0 s | ⚠️ **chưa có** |
| AC-3 | playhead trùng **mép** một clip | bấm **Split** | không tạo clip rỗng, không đổi số clip | ⚠️ **chưa có** |
| AC-4 | clip dài 10,0 s, Speed = 2× | đọc thời lượng trên timeline | clip chiếm 5,0 s; tổng project giảm đúng 5,0 s | ⚠️ một phần — math có test, tầng model chưa |
| AC-5 | 3 clip liên tiếp; xoá clip giữa | xoá | hai clip còn lại **liền nhau**, không để khoảng trống; transition dính clip đã xoá bị gỡ | ⚠️ **chưa có** |

### Xuất video

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-6 | project 2 clip + 1 transition + 1 track nhạc, tỉ lệ 9:16 | Export | ra file đọc được bằng `AVAsset`; `naturalSize` đúng tỉ lệ 9:16; thời lượng lệch < 1 frame so với timeline | ⚠️ **chưa có** — cần smoke test export |
| AC-7 | project có clip ảnh tĩnh (blank backbone) | Export | track video hợp lệ, không có segment rỗng; không lọt audio track rỗng | ⚠️ **chưa có** |
| AC-8 | đang export, người dùng bấm Cancel | Cancel | dừng trong ≤ 1 s, không để lại file dở trong thư viện | ⚠️ **chưa có** |

### Giao diện, từng kích thước

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-9 | iPhone 402×874, project 5 clip | mở Video Studio | mọi công cụ toàn cục đều có mặt trong hàng công cụ; không mục nào bị cắt | `ui-drive` + dump phần tử |
| AC-10 | iPhone Duo màn trong 951×669 | mở Video Studio | timeline và inspector cùng hiện; không control nào nằm dưới mép dưới; góc bo không nuốt control | `Tools/sim-shot` (khung có mask) |
| AC-11 | iPad 1376×1032 | mở Video Studio | dùng bố cục bàn dựng (media pool trái, inspector phải), không phóng to bố cục điện thoại | ảnh chụp + dump |
| AC-12 | iOS 26 và iOS 18 | so sánh bộ action trên cùng màn | hai bên có **cùng** tập action | agent `ios26-parity` |

### Đường hỏng

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-13 | clip là video chỉ có trên iCloud, máy không mạng | mở project | hiện trạng thái `failed` có chữ, không phải khung đen kèm spinner quay mãi | ⚠️ **chưa có** |
| AC-14 | project 20 clip 4K trong extension sửa ảnh | export | không vượt trần bộ nhớ extension | ⚠️ **chưa có** |

**Tổng: 14 AC, 12 chưa chứng minh được.** Đây chính là lỗ hổng đã báo — xem
[README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
