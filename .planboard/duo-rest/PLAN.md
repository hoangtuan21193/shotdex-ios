# Duo loop — các hàng còn chờ quyết định — plan thực thi

> Chốt ngày 2026-11-13, sau 1 vòng · nguồn: .planboard/duo-rest/plan.json · DUO_LOOP các hàng blocked

## Nguyên tắc
- Một hàng mỗi lượt theo kiểu loop: code → board (các máy liên quan) → chụp Duo inner (+ máy khác nếu "mọi máy") → commit hunk của mình → ghi hash vào DUO_LOOP.
- Cần đi chệch quyết định: dừng, hỏi.
- File đang có thay đổi chưa commit của phiên khác: không đè, chờ hoặc hỏi.

## Việc cần làm
- [x] **0 A1** chart editor + khoảng ngày — 010a517f
- [x] **1 Q2b** đóng hàng 2b: giữ ở đáy, không đổi code
- [x] **2 Q26b** — b55032a2 · Save Edit: Format · Save Changes · batch · Save as Copy — board DI12_Save (+PH/IP)
- [x] **3 Q30b** — 159a2ecb · File Name rows một dòng — board DI19_FileName
- [x] **4 Q8b** — 958ea604 · On This Day rỗng: một dòng ~56pt, không link — board DI_/PH_/IP_Collections
- [ ] **5 Q10b** (chờ phiên khác commit SmartAlbumConditionsBar) · Smart Album: chạm hàng điều kiện mở SmartAlbumEditorSheet (.formSheet)
- [x] **6 Q3c** — cedb517e · Search Recents: thẻ ~150pt, số thẻ theo bề rộng — board DI_/IP_Search
- [x] **7 Q22b** — 38fa314f · tier-D chip/pill: contentShape 44pt; DESIGN.md một quy tắc
- [x] **8 Q20b** — 38fa314f · editor panel header gọn trên .duoInner — board DI1_Edit
- [x] **9 Q13b** — 3647b827 · Donut/Bars switch trên thẻ Statistics, lưu vào chart; test ChartStore
- [~] **10 A2** (báo lỗi + ảnh tĩnh xong; nguyên nhân gốc còn mở) · Video Studio preview đen: tìm nguyên nhân, placeholder clip đầu
- [ ] **11 Q5** FS-21 §3 (onboarding + thư viện trống): /plan FS-21 rồi làm, cả ba máy
- Kiểm tra mỗi bước: `/build`, `Tools/ui-drive` trên Compare Duo, `Tools/design-board compare`; test khi đổi Data/Domain.

## Ngoài phạm vi
- Hàng 15 (burst) — blocked tới khi có burst từ máy thật (A3).
