# FS-03.10 — Copy / Paste edits

`FS-03.10` · `Domain/Editing/EditClipboard.swift` · cập nhật 2026-09-22

**Một câu:** chép "cái nhìn" của một tấm sang tấm khác — và cố ý **không** chép những thứ chỉ đúng với một
khung hình.

## 1. Quy tắc

| Chép | Không chép |
|---|---|
| tone · màu · curve · look phim · cường độ look | crop · mask · nét vẽ · overlay |

**Vì sao**: dán crop là cắt lại một tấm ảnh người ta chưa từng cắt; dán mask là làm sáng một vùng mà trên
ảnh này là mặt người. Photos và Lightroom cũng chia đúng chỗ này, cùng một lý do.

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
