# Kế hoạch — Collage, Combine Photos, Create Video trên ảnh server (FS-17.06 đợt 2)

| Trường | Giá trị |
|---|---|
| Đặc tả | `docs/02-functional-spec/FS-17-import-from-server/06-edit-and-export.md` §5b, §6b (AC-67, AC-76…84, AC-70) |
| Intent | [2026-09-29-network-folder-edit](../_intents/2026-09-29-network-folder-edit.md) |
| Đợt 1 | [2026-09-30-network-folder-edit](2026-09-30-network-folder-edit.md) |
| Ngày | 2026-09-30 |
| Trạng thái | gần xong (2026-09-30) — 9/9 task; còn ảnh Duo và iPad ngang |

## 1. Hiểu đúng chưa

Ba lệnh còn lại của ⋯ album — Combine Photos (Focus Stack, Panorama, Stack Exposures), Create Collage, Create Video —
chạy được trên ảnh server. Ảnh tải về thư mục tạm như đợt 1. Công cụ mở như với ảnh library, được thêm ảnh library
qua picker, nhưng không nhận kéo thả. Nút lưu thành Export…: render ra một file trong thư mục tạm, rồi mở sheet xuất
ở chế độ một file gộp, có ô Name mặc định theo ảnh đầu. Không có gì vào Photos trừ khi chọn đích Photos Library.

Người dùng chốt 2026-09-30: ô Name (mặc định `<ảnh đầu>_collage` …), cho trộn ảnh library.

## 2. Chỗ nào trong code

| File | Đụng gì | Mới / sửa |
|---|---|---|
| `Domain/ServerImport/ServerEditExport.swift` | `Job.output: .perPhoto / .composed(ComposedOutput)`; gửi một file, report khoá `"composed"`; Photos nhận ảnh hoặc video | sửa |
| `Domain/ServerImport/ServerComposedName.swift` | tên mặc định theo ảnh đầu + hậu tố công cụ; làm sạch tên | mới |
| `Features/ServerImport/ServerExportModel.swift` | `makeComposed`, `name`, `canExport` | sửa |
| `Features/ServerImport/ServerExportSheet.swift` | section Name; ẩn placement/format/size ở chế độ gộp | sửa |
| `Data/Sources/PhotoOriginImages.swift` | ảnh preview, thumbnail, bytes gốc, EXIF, ngày chụp, tên file theo `PhotoEditOrigin` | mới |
| `Features/Editing/PhotoEditOrigin.swift` | thêm `filename`, `captureDate` nếu cần | sửa |
| `Features/Collage/*` | `[PhotoEditOrigin]`, loader, export tách ở chỗ đã có `Data`, tắt drop | sửa |
| `Features/Editing/PhotoStack*` | `[PhotoEditOrigin]`, loader, thứ tự theo EXIF file, lưu ra file | sửa |
| `Features/Editing/PanoramaMerge*`, `Data/Sources/PanoramaStitchService.swift` | `loadFrame` / `saveFile` cho file; ngày chụp từ loader | sửa |
| `Features/VideoStudio/*`, `Data/Sources/VideoFrameCompositor.swift`, `VideoStudioService.swift` | bảng id → origin, resolver URL cho `StillFrameStore`, thumbnail qua loader, export dừng ở URL | sửa |
| `Features/ServerImport/ServerPhotoCommands.swift` | `.collage`, `.video`, `.combine(purpose)`; host mở cover công cụ | sửa |
| `Features/Shared/PhotoCommand.swift`, `ServerBrowserScreen.swift` | `serverSelectionMenu` thêm ba lệnh, submenu Combine | sửa |
| Caller library (Library, AlbumDetail, SmartAlbumDetail, OnThisDay, PhotoList, Creations) | bọc `.asset(...)` | sửa |

Logic tên file và job gộp ở Domain (thuần, test được). Loader ở Data. View chỉ đổi nhãn nút và bật/tắt drop.
Id trong recipe giữ `String` — không đổi Codable.

## 3. Thứ tự task

| # | Task | AC tương ứng | Test kèm theo |
|---|---|---|---|
| 0 | Spec §5b/§6b + AC, plan này, intent Tiến độ | — | — |
| 1 | Job gộp, tên file, làm sạch tên | AC-77 | `ServerEditExportTests.composedNamesFromFirstPhoto`, `composedCollisionNumbers`, `composedNeverReplaces`, `composedVideoGoesToPhotosAsVideo` |
| 2 | Sheet chế độ gộp + ô Name | AC-77, AC-78 | `ServerEditExportTests.composedEmptyNameDisablesExport` |
| 3 | `PhotoOriginImages` | AC-84 | `ServerComposeSourceTests` (downsample, ngày EXIF, tên file) |
| 4 | Collage | AC-67, AC-82, AC-83 | `ServerComposeToolTests.collage*` + test Collage hiện có |
| 5 | Focus Stack / Stack Exposures | AC-79 | `ServerComposeToolTests.focusStackOrdersByEXIF` |
| 6 | Panorama | AC-80 | `ServerComposeToolTests.panoramaReadsFiles` |
| 7 | Video Studio | AC-81, AC-84 | `ServerComposeToolTests.video*` + test Video hiện có |
| 8 | Menu + định tuyến | AC-76 | `ServerEditMenuTests.matchesAlbumMenu` (đợt 2) |
| 9 | Ảnh chụp, proof, full suite | AC-70 | — |

## 4. Rủi ro và đánh đổi

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| Video Studio 12–14 file, 25–35 call site đọc `assetID` | cao | giữ `String` id, chỉ thêm resolver; chạy lại test Video sau task 7 |
| Đường library bị đổi hành vi | trung bình | nhánh `.asset` của loader gọi đúng hàm cũ; test Collage/PhotoStack/Panorama hiện có phải xanh |
| Bộ nhớ: 20 RAW full-res trong focus stack, still video | trung bình | focus stack đi đường URL-streaming sẵn có; still video downsample tới cỡ render (AC-84) |
| Đĩa đầy (còn ~6 GB) | cao | kiểm `df` trước build/test; video tạm nằm trong thư mục tạm của lượt |
| Hai agent chung checkout | — | `git commit -- <paths>`, `/usr/bin/git` |

## 5. Phản biện

| Phản đối | Trả lời / thay đổi |
|---|---|
| Sao không tạo asset tạm trong Photos rồi dùng công cụ nguyên trạng? | đợt 1 đã chốt D1: không để bản sao trong library |
| Ô Name thêm một hàng vào sheet | người dùng yêu cầu (2026-09-30); tên theo ảnh đầu là mặc định nên không phải gõ |

## 6. Cách chứng minh là xong

- Test: các test ở §3, cùng suite Collage, PhotoStack, Panorama, VideoStudio hiện có; full suite một lần cuối.
- Màn hình phải chụp: sheet gộp (Name, không Replace), Collage/Focus Stack/Panorama/Video với nút Export…, hộp
  Discard — iPhone 17 Pro 26.5, iPhone 16 Pro 18.6; iPad, Duo trong bằng `Tools/sim-shot`.
- Chạy thật trên SMB (impacket): file ra trên share, `shasum` khớp.
- Tài liệu phải cập nhật: FS-17.06 cột "Chứng minh bằng", intent Tiến độ, FS-05 (Collage) / FS-14 (Combine) / Video
  Studio một dòng về lượt server.

## 7. Kết quả (2026-09-30)

- Commit: 8c005dc (spec/plan), 0c4615f, 8267383, 1f1e8ca, f458f3c, 7d7e3d8, 7a8a965, 6fb4af8, b7e7dcf, 60d0331 (2 lỗi
  thấy trên ảnh: nền màn Export của collage làm cả màn rộng ~870pt — có từ trước, cả với collage library; và nhãn
  `JPG` → `JPEG`).
- Chạy thật trên SMB (impacket, iPhone 17 Pro 26.5): Collage → `DSCF1000_collage.jpg`, trộn ảnh library →
  `DSCF1000_collage (2).jpg`, Video → `DSCF1000_video.mp4` + 1 video trong Photos, Focus Stack và Panorama tới sheet.
  Mọi đường ra để lại 0 thư mục `ShotDexServerEdit-*`.
- iPhone 16 Pro 18.6: menu, sheet gộp (sáng, theo hệ thống — trên 26.5 sheet thừa hưởng nền tối của màn công cụ, như
  đợt 1), hộp Discard của collage. iPad Pro 13 dọc: toolbar chế độ chọn, menu, collage có sidebar, sheet gộp dạng form.
- Còn mở: Duo (công cụ MCP bấm sai màn ngoài, `ui-drive` cài lại app làm mất connection đã seed), iPad ngang.
- Ghi nhận ngoài phạm vi (không sửa): màn Export của collage trên iPad kéo nút Export hết chiều ngang 1376pt; công tắc
  Keep EXIF tắt trên 18.6 gần như không thấy rãnh.
