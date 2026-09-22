# QA-02 — Quy ước viết code

`QA-02` · cập nhật 2026-09-22

**Một câu:** ràng buộc bắt buộc khi viết code trong repo này.

## 1. Kiến trúc

- **Không để logic trong View** — tách presentation / domain / data ([BD-01](../01-basic-design/BD-01-system-architecture.md)).
- PhotoKit, ImageIO, GRDB cô lập trong tầng service/store, không rò lên UI.
- Swift Concurrency đúng cách: ràng buộc luồng giao diện cho UI state, `actor` cho pipeline, không block main thread.
- Không mock UI — logic thật.
- Optional xử lý đúng, không force unwrap khi không cần. Error và loading state đầy đủ.

## 2. Đặt tên

| Loại | Quy ước |
|---|---|
| State holder `@Observable` | `*Model` — **không** `*Controller` (từ đó là tên một lớp giao diện của UIKit trên iOS) |
| Tầng dữ liệu đọc **và** ghi | `*Store` |
| Tầng dữ liệu chỉ đọc | `*Queries` — không `DAO`, không `Repository` |
| Bool | đọc như một khẳng định: `showsISO`, không `showISO` |
| Cờ latch | `has*`, không `did*` |

- **Không dùng từ vựng Flutter/Material**: `Scaffold`, `Widget`, `Drawer`, `Chip`, `Surface`, `Route`.
- Không viết tắt. Không method `set*` che một property.
- Ngoài các mục trên: theo Swift API Design Guidelines.

## 3. Công cụ

- SwiftLint (tuỳ chọn) giữ style nhất quán.
- Mọi thay đổi code kết thúc bằng một lần build (`/build`) — không bàn giao thay đổi chưa build.
