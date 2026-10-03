# FS-12.18 — Lưu nháp video

`FS-12.18` · tier D · `Features/VideoStudio/VideoStudioModel.swift` · `Core/Models/Creation.swift` ·
`Data/Database/CreationStore.swift` · `Features/Creations/` (Video Projects) · cập nhật 2026-10-03
· nguồn intent [video-studio-canvas-chrome](../../_intents/2026-10-03-video-studio-canvas-chrome.md)

**Một câu:** dựng phim mất thời gian, nên project video **tự lưu thành nháp** liên tục như CapCut và iMovie —
không có nút Save, Back không bao giờ hỏi "Discard this video?", và mở lại là sửa tiếp đúng chỗ.

Danh sách Video Projects: [FS-06.01b §5](../FS-06-collections/01b-album-management-and-creations.md). Model:
[08 §2](08-model-and-v1-limits.md). Mô hình chọn khi Back: [04 §5](04-tools-and-inspector.md).

## 1. Người dùng cần gì

Một bản dựng 30 clip là cả buổi tối. Hôm nay project chỉ được ghi khi **xuất**; Back mà chưa xuất thì hỏi Discard
rồi mất hết, app bị hệ thống tắt ở nền cũng mất hết. Người dùng chốt 2026-10-03: "project phải được lưu trước khi
export — sửa mất thời gian".

## 2. Quy tắc

- **Tự lưu, không nút Save.** Mỗi thay đổi của project (mọi thứ đi vào undo, cộng các trường ngoài undo như đích xuất,
  In–Out) hẹn một lần ghi sau **~1 s** không có thay đổi mới; thay đổi dồn dập chỉ ra một lần ghi.
- **Ghi ngay, không chờ 1 s**, khi: bấm Back · app xuống nền · scene đổi (gập/mở Duo, đóng cửa sổ Stage Manager).
- **Back không hỏi.** Back = ✓ cho phiên đang mở (04 §5), ghi ngay, đóng Video Studio. Hộp thoại "Discard this
  video?" không còn ở Video Studio.
- **Project mới không sửa gì vẫn được lưu**: chọn ảnh → Video Studio mở → Back ngay thì Video Projects có một nháp
  với đúng các clip vừa chọn. *Vì "không mất gì" đơn giản hơn "đoán xem người dùng có muốn giữ không"; nháp thừa
  xoá được bằng một lần giữ.*
- **Nháp và bản đã xuất là cùng một dòng.** Export ghi file vào Photos và đánh dấu dòng đã xuất; sửa tiếp sau đó vẫn
  tự lưu vào **đúng dòng ấy**, Export lần nữa cập nhật dòng ấy (FS-06.01b §6), không đẻ dòng thứ hai.
- **Undo không lưu**: mở lại thì Undo/Redo tắt. Phiên chọn, panel đang mở, tập chọn nhiều, chế độ so sánh không lưu.
- **Ngoại lệ — project từ ảnh server** ([FS-17.06](../FS-17-import-from-server/06-edit-and-export.md) §5): file
  nguồn là bản tạm của phiên nên không có nháp; Back khi đã sửa vẫn hỏi như FS-17.06 nói.
- Collage không đổi: vẫn chỉ lưu khi xuất (FS-11b) — ngoài phạm vi tài liệu này.

## 3. Mở lại

- Chạm một dòng ở Video Projects mở Video Studio với **đúng công thức đã lưu**: clip, cắt, chữ, nhạc, look,
  Video Settings, đích xuất, In–Out, và **vị trí playhead** lúc rời. Không item nào được chọn, không panel nào mở,
  khung và timeline về bố cục mặc định của thiết bị.
- Ảnh/video nguồn lấy lại theo id; thiếu nguồn thì theo luật sẵn có của FS-06.01b §6 và FS-12 README AC-13.

## 4. Video Projects

- **Một danh sách** cho nháp và bản đã xuất, mới sửa nhất ở trên.
- Dòng **nháp** (chưa xuất lần nào): ảnh bìa là thumbnail clip đầu · nhãn **Draft** (viên nang trắng 14%, chữ 11) ·
  dòng phụ **"Edited 5 min ago"** (thời gian tương đối) · số clip.
- Dòng **đã xuất**: ảnh bìa của video đã xuất như hôm nay; mở ra vẫn sửa được.
- Giữ một dòng nháp → menu **Delete Draft** → xác nhận "Delete Draft?" · "The photos and videos stay in your
  library." · **Delete** (đỏ) · **Cancel**. Xoá dòng không bao giờ đụng ảnh hay video trong thư viện. Dòng đã xuất
  giữ menu gỡ khỏi danh sách như FS-06.01b §5.

## 5. Dữ liệu

| | |
|---|---|
| Ghi vào | bảng `creations` sẵn có — **cùng** dòng cho nháp và bản xuất; thêm một trạng thái "đã xuất lúc nào" (rỗng = nháp). Id ảnh đã xuất rỗng **không** có nghĩa là nháp: nó cũng rỗng khi người dùng xoá video đã xuất |
| Dòng có từ trước | mọi dòng cũ đều sinh ra từ một lần xuất → coi là đã xuất (lấy ngày sửa). App chưa phát hành: không cần tương thích, nhưng bước đổi bảng phải chạy được trên database đang có |
| Công thức | JSON như hôm nay + vị trí playhead (tuỳ chọn, ngoài undo) |
| Đọc khoan dung | bắt buộc: nháp cũ thiếu khoá mới vẫn mở; một clip/overlay/bản nhạc hỏng chỉ mất phần đó |
| `photo_metadata` | không đụng (BD-02) |

## 6. Đường hỏng

- **Ghi hỏng** (hết chỗ, lỗi database): banner không chặn **"Couldn't save your video draft"** + **Try Again**;
  project trong bộ nhớ giữ nguyên, sửa tiếp được; lần ghi kế (tự động hay Try Again) thành công thì banner tắt.
- **Back khi lần ghi ngay bị hỏng**: Video Studio **không đóng**; alert "Couldn't save your video draft" ·
  **Try Again** · **Leave Without Saving** (đỏ). *Vì đóng im lặng là mất cả buổi; đây là lần duy nhất Back hỏi.*
- **App bị tắt trước khi kịp ghi**: mất tối đa ~1 s thay đổi cuối; lần xuống nền đã ghi ngay nên thực tế không mất.
- **Nháp không đọc được cả cục** (JSON hỏng hẳn): dòng vẫn hiện, mở ra báo "This draft can't be opened." — không xoá
  tự động.

## 7. Tiêu chí nghiệm thu

Project mẫu: 5 clip 24,0 s từ 5 ảnh/video của thư viện, không ảnh server.

| # | Cho | Khi | Thì | Chứng minh bằng |
|---|---|---|---|---|
| AC-1 | project mẫu đang mở | đổi Speed clip 2 sang 2×, rồi chờ | dòng `creations` có Speed 2× sau 1,0 s ±0,3 s; ba thay đổi trong 0,5 s chỉ ra **một** lần ghi | ✅ `VideoDraftAutosaveTests.savesOneSecondAfterTheLastChange` (đồng hồ thật, 0,7–1,3 s), `threeQuickChangesWriteOnce` |
| AC-2 | project mẫu, đã sửa, chưa xuất lần nào | bấm Back | Video Studio đóng ngay, **không** có alert nào; Video Projects có dòng Draft mang thay đổi đó | ✅ `VideoDraftBackTests.backSavesWithoutAsking`, `serverProjectHasNoDraft` (ảnh server vẫn hỏi theo FS-17.06); sim iPhone 17: Back đóng ngay, không alert, Video Projects có dòng Draft (2026-10-04) |
| AC-3 | đổi Speed rồi trong 0,3 s về Home; tắt hẳn app | mở lại app → Video Projects → chạm dòng | thay đổi còn (đã ghi lúc xuống nền, trước hẹn 1 s) | ✅ `VideoDraftBackgroundTests.backgroundingSavesImmediately` (thông báo xuống nền → dòng có Speed 2× trong 0,4 s, trước hẹn 1 s) |
| AC-4 | Duo, project đang mở ở màn trong | đổi Speed rồi gập máy trong 0,3 s | dòng đã có thay đổi trước khi bố cục màn ngoài dựng xong | ⚠️ một phần — `VideoDraftSceneTests.sceneChangeSavesImmediately` (đổi scene → ghi ngay, trước hẹn 1 s); view gọi khi `scenePhase` rời active và khi size class đổi (gập/mở Duo). Còn đo tay gập Duo trong Simulator.app (simctl không có lệnh gập) |
| AC-5 | playhead 8,4 s, clip 2 đang chọn, panel Music mở | Back, rồi mở lại từ Video Projects | playhead 8,4 s; không item nào chọn; không panel nào mở; Undo và Redo tắt | ✅ `VideoDraftReopenTests.reopenRestoresPlayheadOnly` (8,4 s; không chọn, không panel; Undo/Redo tắt) |
| AC-6 | một nháp sửa 5 phút trước và một project đã xuất | mở Video Projects | một danh sách, nháp ở trên; dòng nháp có nhãn "Draft", "Edited 5 min ago", bìa là clip đầu; dòng đã xuất không có nhãn | ✅ `VideoProjectsListTests.videoProjectsListsDraftsAndExportsNewestFirst`, `rowsSayDraftAgeAndClipCount`; sim iPhone 17 (26.5) sáng + tối: dòng Draft "Edited 16 sec. ago · 1 clip", bìa clip đầu, 2026-10-04 (route drafts.json: Studio → Back không alert → Video Projects). `design-board compare` PH_VideoProjects: dòng 370×88 đúng, lệch y +10 do thanh điều hướng hệ thống (chung mọi danh sách Collections) |
| AC-7 | dòng nháp 5 clip | giữ → Delete Draft → Delete | dòng mất; số ảnh/video trong Library không đổi; Cancel thì dòng còn | ✅ `VideoDraftDeleteTests.deleteDraftRemovesOnlyTheRow` (chỉ xoá dòng; store không chạm thư viện); sim iPhone 17: giữ dòng → Delete Draft → "Delete Draft?" (`.alert`, Cancel + Delete đỏ) → Cancel giữ dòng (2026-10-04) |
| AC-8 | lần ghi ném lỗi hết chỗ (tiêm trong test) | sửa một thay đổi | banner "Couldn't save your video draft" + Try Again; sửa tiếp được; Try Again sau khi hết lỗi → banner tắt, dòng có mọi thay đổi | ⚠️ chưa có |
| AC-9 | lần ghi vẫn hỏng | bấm Back | Video Studio còn mở; alert Try Again · Leave Without Saving; Leave Without Saving thì đóng, dòng giữ bản ghi được gần nhất | ⚠️ chưa có |
| AC-10 | nháp JSON thiếu mọi khoá mới và có một clip hỏng | mở từ Video Projects | project mở với các clip còn lại; không báo lỗi cả project | ✅ `VideoDraftStoreTests.oldDraftMissingNewKeysOpens`, `oneBrokenClipKeepsTheDraft` (+ `VideoRecipeDecodingTests`); dòng có sẵn thành đã xuất: `existingRowsBecomeExported` |
| AC-11 | New Video Project, chọn 3 ảnh | Video Studio mở, bấm Back ngay | Video Projects có một dòng Draft 3 clip | ✅ `VideoDraftSaveNowTests.aNewProjectWithNoEditsIsKept` (3 ảnh, không sửa → một dòng Draft 3 clip); Back gọi đúng lệnh ghi này: FS-12.18 AC-2 |
| AC-12 | project đã xuất một lần | mở lại, đổi Speed, Back; rồi Export | dòng đó mang Speed mới, không có dòng thứ hai, không nhãn Draft; Export cập nhật đúng dòng ấy | ✅ `VideoDraftExportTests.editAfterExportKeepsOneRow` (một dòng, Speed mới, không Draft; Export lại cập nhật dòng ấy), `exportMarksTheDraftRowExported` |

**Chưa chứng minh được:** AC-4, AC-8, AC-9.

## 8. Rủi ro đã biết

| Rủi ro | Xử lý |
|---|---|
| Ghi JSON mỗi giây khi kéo slider liên tục | hẹn ghi chỉ chạy khi ngừng 1 s; ghi ở nền, bản mới nhất thắng; đo trên project 200 clip |
| Ghi lúc xuống nền bị hệ thống cắt | ghi trong thời gian nền hệ thống cho; JSON nhỏ (vài trăm KB) |
| Nháp rác tích lại (mở rồi Back) | chấp nhận ở v1 — nhãn Draft + Delete Draft; không tự xoá |
| Board Video Studio còn vẽ alert Discard; Video Projects chưa có dòng Draft | sửa canvas Video Studio và canvas App Screens (Video Projects) trước khi code phần list |
