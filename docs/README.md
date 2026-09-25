# Tài liệu thiết kế ShotDex

App iOS native (Swift/SwiftUI) cho người chụp ảnh: duyệt cả thư viện, lọc theo body/lens/thông số
chụp, xem thống kê thiết bị. Ba tab **Library · Collections · Statistics**, Settings mở toàn màn hình
từ nút gear góc trên trái.

## 1. Đọc gì trước

| Muốn | Đọc |
|---|---|
| Quy trình làm việc | [PROCESS.md](PROCESS.md) — Plan → Design → Build → Test → Deploy → Maintain |
| App làm gì, cho ai | [OV-01](00-overview/OV-01-product-goals-and-scope.md) |
| Code xếp ở đâu | [BD-01](01-basic-design/BD-01-system-architecture.md) |
| Sửa một màn hình | `FS-*` của màn đó |
| Đụng database | [BD-02](01-basic-design/BD-02-database-design.md) — đọc trước, luôn |
| Đụng index / PhotoKit | [BD-03](01-basic-design/BD-03-metadata-indexing-flow/README.md) |
| Ràng buộc hiệu năng, bộ nhớ, thiết bị | `NF-*` |
| Cái gì đã được test | [QA-01](05-testing-and-conventions/QA-01-test-strategy.md) |

Không nằm ở đây: **token thiết kế** (màu, bo góc, khoảng cách, 4 tier) ở `DESIGN.md` gốc repo;
**quy ước code, skill, agent** ở `CLAUDE.md`.

## 2. Mã tài liệu

| Tiền tố | Nghĩa |
|---|---|
| `OV-*` | Tổng quan (概要) |
| `BD-*` | Thiết kế cơ bản (基本設計書) |
| `FS-*` | Đặc tả chức năng — một màn / một tính năng (機能仕様書) |
| `EX-*` | Extension và tích hợp hệ thống |
| `NF-*` | Thiết kế phi chức năng (非機能設計書) |
| `QA-*` | Kiểm thử và quy ước code (試験仕様書) |

Tên file và thư mục tiếng Anh, nội dung tiếng Việt. Tài liệu lớn chia phần (`FS-01.03`): phần nằm
trong thư mục cùng tên, `README.md` làm mục lục.

## 3. Cây tài liệu

```
docs/
├── README.md                 mục lục (file này)
├── PROCESS.md                quy trình AI-native SDLC — 6 giai đoạn
├── 00-overview/              OV-01 mục tiêu · OV-02 công nghệ · OV-03 lộ trình
├── 01-basic-design/          BD-01 kiến trúc · BD-02 database · BD-03 index (4 phần)
│                             BD-04 ngôn ngữ thiết kế · BD-05 quy tắc nghiệp vụ
├── 02-functional-spec/       FS-01 Library (11) · FS-02 Photo Detail (4) · FS-03 Editor (12)
│                             FS-04 Màu (3) · FS-05 Markup (3) · FS-06 Collections (10)
│                             FS-07 Statistics · FS-08 Settings (5) · FS-09 Onboarding
│                             FS-10 Import (đã bỏ) · FS-11 Collage · FS-12 Video Studio (9) · FS-13 Support
│                             FS-14 Panorama (2) · FS-15 Upload lên file server (3)
│                             FS-16 Kernel render bằng Metal
├── 03-extensions-and-integrations/  EX-01 Kit · EX-02 Widget · EX-03 Share · EX-04 Shortcuts · EX-05 Edit action
├── 04-non-functional-design/ NF-01 hiệu năng · NF-02 bộ nhớ · NF-03 riêng tư
│                             NF-04 trạng thái lỗi · NF-05 thiết bị · NF-06 truy cập & ngôn ngữ
├── 05-testing-and-conventions/  QA-01 kiểm thử · QA-02 quy ước code
├── _intents/                 giai đoạn Plan — ý định, có version
├── _plans/                   giai đoạn Build — kế hoạch từng tính năng
└── _templates/               intent · functional-spec · design-note · plan
```

Ngoài `docs/`: `REVIEW.md` (chính sách review), `bands.yaml` (control band), `evals/`,
`Tools/gate` · `Tools/evals` · `Tools/bands-check`, `.claude/hooks/` (cổng duyệt).

## 4. Luật viết tài liệu

Mục tiêu: **đọc hết một tài liệu trong 5 phút, và sửa một section mà không phải đọc cả file.**

- **Khoảng 120 dòng mỗi file.** Vượt nhiều thì chia phần thành thư mục, đừng để lớn lại thành một `spec.md`
  thứ hai.
- **Bullet tối đa 2 dòng.** Dài hơn thì tách bullet con hoặc đưa vào bảng.
- **Không đoạn văn quá 3 dòng.** Bảng khi so sánh, code block cho schema.
- **Không kể lịch sử bug.** Viết luật hiện tại. Lý do chỉ giữ khi nó ngăn được lần sửa sai tiếp theo,
  và viết một dòng: *Vì …*.
- **Tính năng đã bỏ thì xoá khỏi tài liệu**, không giữ làm ghi chú lịch sử.
- **Thì hiện tại, câu khẳng định.** "Grid tải 200 row mỗi lượt", không phải "sẽ nên tải".
- **Số đo được thay vì tính từ.** "246pt", không phải "panel thấp".
- **Không viết code vào tài liệu.** Không tên hàm, tên property, tên modifier, tên enum case, cú pháp API.
  Viết cái quyết định và hệ quả của nó: *"Pan của scroll view bị huỷ ngay khi pinch bắt đầu — không huỷ
  thì lưới giật qua lại."* Tên file/kiểu chỉ xuất hiện **một lần ở dòng đầu** làm con trỏ tới mã nguồn.
- **Tên framework được phép** khi bản thân việc chọn nó là quyết định (Core Image, PencilKit, GRDB).
- **Mỗi `FS-*` phải có tiêu chí nghiệm thu** dạng Cho / Khi / Thì, cột chứng minh trỏ tới test thật
  hoặc script `Tools/ui-drive` thật. AC chưa chứng minh được thì ghi ra, không xoá.
- Template ở `_templates/` là điểm khởi đầu: bỏ section thừa, thêm section riêng, không cần xin phép.

## 5. Giữ tài liệu sống

- Đổi hành vi hoặc kiến trúc → sửa `FS-*`/`BD-*` tương ứng **trong cùng lượt làm việc**.
- Thêm màn hình mới → thêm một `FS-*`, đăng ký ở mục 3.
- Không tạo token thiết kế ở đây — `DESIGN.md` là nguồn duy nhất.

## 6. Việc còn nợ

| # | Việc | Giai đoạn |
|---|---|---|
| 1 | Tiêu chí nghiệm thu cho `FS-12`, rồi `FS-03` | Design |
| 2 | Test cho model Video Studio + smoke test export | Build/Test |
| 3 | Nâng bộ eval từ 5 lên 20–50 ca | Test |
| 4 | Đối chiếu số trong `NF-01`/`NF-02` với code, bỏ nhãn *(cần xác nhận)* | Design |
| 5 | Chạy `Tools/gate` đủ 8 lần để `bands.yaml` có baseline | Maintain |
| 6 | Viết `intent.md` cho việc đang làm dở | Plan |
