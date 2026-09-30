# FS-17.06 — Sửa và xuất ảnh trên server — plan thực thi

> Chốt ngày 2026-09-30, sau 1 vòng · nguồn: .planboard/network-folder-edit/plan.json

Bản plan của repo (bảng đối chiếu AC ↔ code, file, rủi ro): `docs/_plans/2026-09-30-network-folder-edit.md`.
File này chỉ là checklist; hai file lệch nhau thì tin `docs/_plans`.

## Nguyên tắc
- Làm theo thứ tự; một AC = một commit `feat(FS-17.06): AC-xx …`; build sau mỗi commit; UI thì `/screens`.
- Cần đi chệch một quyết định đã chốt (DECISIONS.md): dừng lại, hỏi người dùng.

## Việc cần làm (đợt 1)
- [x] **1. Tiền tố tạm + sweep** (AC-59)
  - Theo: D3
  - Xong khi: AC-59 xanh, cột Chứng minh bằng của FS-17.06 đã điền
  - Kiểm tra: `/test TemporaryWorkspaceTests`
- [x] **2. Fetch + verify dùng chung; kiểm chỗ trống** (AC-55)
  - Theo: D3
  - Xong khi: AC-55 xanh, cột Chứng minh bằng của FS-17.06 đã điền
  - Kiểm tra: `/test ServerEditSessionTests/spaceCheckBeforeDownload`
- [x] **3. Cancel phiên bản tạm** (AC-56)
  - Theo: D3,D10
  - Xong khi: AC-56 xanh, cột Chứng minh bằng của FS-17.06 đã điền
  - Kiểm tra: `/test ServerEditSessionTests/cancelRemovesTemp`
- [x] **4. Phiên sửa ảnh nguồn file; Edit mở editor** (AC-54)
  - Theo: D1
  - Xong khi: AC-54 xanh, cột Chứng minh bằng của FS-17.06 đã điền
  - Kiểm tra: `/test ServerEditSessionTests/downloadsOriginalOnly`
- [x] **5. Discard edits?** (AC-57)
  - Theo: D11
  - Xong khi: AC-57 xanh, cột Chứng minh bằng của FS-17.06 đã điền
  - Kiểm tra: `/test ServerEditSessionTests/discardDropsDraft`
- [x] **6. Rời không sửa: không hỏi** (AC-58)
  - Theo: D11
  - Xong khi: AC-58 xanh, cột Chứng minh bằng của FS-17.06 đã điền
  - Kiểm tra: `/test ServerEditSessionTests/cleanLeaveNoPrompt`
- [x] **7. Bộ ghi: file mới cạnh bản gốc** (AC-60)
  - Theo: D5
  - Xong khi: AC-60 xanh, cột Chứng minh bằng của FS-17.06 đã điền
  - Kiểm tra: `/test ServerEditExportTests/newFileBesideOriginal`
- [x] **8. Trùng tên → (2)** (AC-61)
  - Theo: D5
  - Xong khi: AC-61 xanh, cột Chứng minh bằng của FS-17.06 đã điền
  - Kiểm tra: `/test ServerEditExportTests/nameCollisionNumbers`
- [x] **9. Replace Original + xác nhận** (AC-62)
  - Theo: D5
  - Xong khi: AC-62 xanh, cột Chứng minh bằng của FS-17.06 đã điền
  - Kiểm tra: `/test ServerEditExportTests/replaceNeedsConfirm`
- [x] **10. RAW không thay được** (AC-63)
  - Theo: D5
  - Xong khi: AC-63 xanh, cột Chứng minh bằng của FS-17.06 đã điền
  - Kiểm tra: `/test ServerEditExportTests/rawCannotBeReplaced`
- [x] **11. Sheet xuất nhiều đích** (AC-64)
  - Theo: D4,D8,D12
  - Xong khi: AC-64 xanh, cột Chứng minh bằng của FS-17.06 đã điền
  - Kiểm tra: `/test ServerEditExportTests/multipleDestinations`
- [x] **12. Đích lỗi giữ nháp, Retry Failed** (AC-69)
  - Theo: D5
  - Xong khi: AC-69 xanh, cột Chứng minh bằng của FS-17.06 đã điền
  - Kiểm tra: `/test ServerEditExportTests/failedDestinationKeepsDraft`
- [x] **13. Lỗi quyền + Choose Another Folder** (AC-65)
  - Theo: D7
  - Xong khi: AC-65 xanh, cột Chứng minh bằng của FS-17.06 đã điền
  - Kiểm tra: `/test ServerEditExportTests/permissionDeniedOffersAnotherFolder`
- [x] **14. Batch chỉ xuất ảnh đã sửa** (AC-66)
  - Theo: D1,D11
  - Xong khi: AC-66 xanh, cột Chứng minh bằng của FS-17.06 đã điền
  - Kiểm tra: `/test ServerEditExportTests/batchExportsEditedOnly`
- [x] **15. Định nghĩa lệnh chung; ⋯ chế độ chọn** (AC-53)
  - Theo: D9
  - Xong khi: AC-53 xanh, cột Chứng minh bằng của FS-17.06 đã điền
  - Kiểm tra: `/test ServerEditMenuTests/matchesAlbumMenu`
- [x] **16. Menu nhấn giữ + viewer** (AC-52)
  - Theo: D9
  - Xong khi: AC-52 có ảnh đã xem
  - Kiểm tra: `Tools/ui-drive … scripts/server-edit.json`
- [x] **17. Paste Edits → sheet xuất** (AC-72)
  - Theo: D1
  - Xong khi: AC-72 xanh, cột Chứng minh bằng của FS-17.06 đã điền
  - Kiểm tra: `/test ServerEditSessionTests/pasteEditsGoesToExportSheet`
- [x] **18. Resize trên nguồn file** (AC-73)
  - Theo: D1
  - Xong khi: AC-73 xanh, cột Chứng minh bằng của FS-17.06 đã điền
  - Kiểm tra: `/test ServerEditExportTests/resizeExportsThroughSheet`
- [x] **19. Share file tạm** (AC-74)
  - Theo: D12
  - Xong khi: AC-74 xanh, cột Chứng minh bằng của FS-17.06 đã điền
  - Kiểm tra: `/test ServerEditSessionTests/shareHandsOriginalAndCleansUp`
- [x] **20. Copy** (AC-75)
  - Theo: D12
  - Xong khi: AC-75 xanh, cột Chứng minh bằng của FS-17.06 đã điền
  - Kiểm tra: `/test ServerEditSessionTests/copyBoundsAndCleansUp`
- [x] **21. Export EXIF chỉ đọc đầu file** (AC-68)
  - Theo: D3
  - Xong khi: AC-68 xanh, cột Chứng minh bằng của FS-17.06 đã điền
  - Kiểm tra: `/test ServerEditExifTests/readsHeadOnly`
- [ ] **22. Ảnh 4 thiết bị × 26.5/18.6** (AC-70)
  - Theo: D9
  - Xong khi: AC-70 có ảnh đã xem
  - Kiểm tra: `/screens server-edit`

## Ngoài phạm vi
- Đợt 2: Create Collage, Create Video, Combine Photos (AC-67) — plan riêng.
- Lịch sử upload cho file xuất (D6), thử ghi trước khi mở sheet (D7).
