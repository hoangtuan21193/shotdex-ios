# FS-03.10 — Copy / Paste edits

`FS-03.10` · `Domain/Editing/EditClipboard.swift` · cập nhật 2026-09-22

**Một câu:** chép "cái nhìn" của một tấm sang tấm khác — và cố ý **không** chép những thứ chỉ đúng với một
khung hình.

## 1. Quy tắc

| Chép | Không chép |
|---|---|
| tone · màu · curve · look phim / LUT · cường độ look | crop · mask · nét vẽ · overlay · **vết heal/clone** |

**Vì sao**: dán crop là cắt lại một tấm ảnh người ta chưa từng cắt; dán mask là làm sáng một vùng mà trên
ảnh này là mặt người; dán một vết heal là vá một chỗ mà trên ảnh này không có bụi. Photos và Lightroom cũng
chia đúng chỗ này, cùng một lý do.

Chép là **danh sách cho phép** (`EditClipboard.look(of:)`, `paste(onto:)`, `EditorSyncScope.look`): một
trường mới của recipe không tự đi theo; muốn nó được chép thì phải thêm tên vào đó. `PhotoHealingTests.
healingIsNeverCopied` khoá điều này cho healing.

## 2. Hành vi

- Menu ⋯ của editor: **Copy Edits** (mờ khi chưa có gì để chép) và **Paste Edits** (chỉ hiện khi clipboard
  có nội dung).
- Clipboard giữ **một** recipe và **sống qua cả lần mở app sau**.
- **Paste là một bước history** — undo một phát là xong.
- Cùng lát cắt này được dùng cho Sync Look khi sửa nhiều ảnh
  ([FS-03.09](09-wide-screen-and-batch-editing.md)) và cho preset My Looks
  ([FS-03.02](02-film-simulation-and-presets.md)).

## 3. Tiêu chí nghiệm thu

**Chưa viết.** Xem [README — Việc còn nợ](../../README.md#6-việc-còn-nợ).
