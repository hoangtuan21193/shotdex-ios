# FS-09 — Onboarding và quyền

`FS-09` · tier A · `ShotDex/Features/Onboarding/` · `Data/Sources/PhotoLibraryService.swift`
· cập nhật 2026-09-22

**Một câu:** bốn màn giới thiệu trước khi hỏi quyền, và mọi trạng thái quyền đều có lối đi tiếp.

## 1. Quy tắc

- **Không xin quyền ngay khi mở app** — onboarding ngắn trước prompt.
- Xin quyền đọc-ghi (cần cho toggle favorite), không phải chỉ-đọc.
- **Không màn nào được chết ở trạng thái quyền**: mỗi trạng thái có câu giải thích và một nút.
- App **không bao giờ tự hỏi** quyền lịch/vị trí ([EX-02](../03-extensions-and-integrations/EX-02-widget.md)).

## 2. Bốn câu onboarding

1. Find photos by camera and lens
2. Explore your most-used gear
3. Compare focal lengths across sensor sizes
4. Your photos stay on your device

## 3. Trạng thái quyền

| Trạng thái | Màn hiện gì |
|---|---|
| Not Determined | onboarding, rồi mới xin quyền **đọc và ghi** thư viện ảnh |
| Authorized | full access, vào thẳng Library |
| **Limited** | nói rõ app chỉ phân tích ảnh được cấp + nút **Manage Selected Photos** |
| Denied | empty state, giải thích vì sao cần quyền, nút mở Settings |
| Restricted | empty state tương ứng |

`Info.plist`: chuỗi giải thích vì sao app cần thư viện ảnh.

## 4. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../README.md#6-việc-còn-nợ).
