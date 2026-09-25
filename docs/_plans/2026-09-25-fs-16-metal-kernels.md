# Kế hoạch — FS-16 Kernel render bằng Metal

| Trường | Giá trị |
|---|---|
| Đặc tả | `docs/02-functional-spec/FS-16-metal-kernels.md` |
| Intent | `docs/_intents/2026-09-25-metal-ci-kernels.md` |
| Ngày | 2026-09-25 |
| Trạng thái | đã duyệt — người dùng: "plan xong thì auto accept rồi code luôn" |


## 1. Hiểu đúng chưa

40 kernel Core Image hôm nay viết bằng chuỗi Kernel Language (deprecated). Chuỗi sai thì kernel `nil`
và tính năng tắt âm thầm. Chuyển cả 40 sang file Metal biên dịch lúc build, nạp qua một bộ nạp dùng chung.
Ảnh ra khớp golden chụp **trước** khi port, lệch ≤ 1/255. Làm theo nhóm, mỗi nhóm một commit, thứ tự:
Mask → Color/Optics/Detail → Heal → Stack/Focus → Panorama → Video. Cuối cùng gỡ define tắt warning.

## 2. Đối chiếu AC ↔ code

| AC | Trạng thái | Bằng chứng | Việc |
|---|---|---|---|
| AC-1 golden | ❌ | không có golden/record nào; không test nào dùng `#filePath` | harness + chụp ở T1 |
| AC-2 so pixel 40 kernel | ❌ | — | mỗi task nhóm bật so golden cho nhóm đó |
| AC-3 vùng con | ❌ | memory `coreimage-color-kernel-region-trap`; `PhotoHealingRenderer` ghi chú CI tính kernel màu ngoài extent | test mới, T3 |
| AC-4 build đỏ | ❌ | không có file `.metal` nào | thử phá 1 lần ở T2, log vào `/verify` |
| AC-5 nạp đủ 40 | ❌ | — | test liệt kê 40 kernel, lớn dần theo nhóm |
| AC-6 bundle framework | ❌ | kit nhúng vào app qua Embed Frameworks (pbxproj 88–98); không extension nào link kit | test T2 |
| AC-7 release trả ảnh vào | ✅ một nửa | nơi gọi đã `guard … else return input`: `+Optics.swift:29`, `+Color.swift:175/190/228`, `LensProfileLibrary.swift:200`, `PhotoStackRenderer.swift:410` | giữ nguyên các guard; test bộ nạp trả nil khi tên sai |
| AC-8 point color 8 điểm | ⚠️ lệch chữ | spec nói "8 slot… làm tham số", nhưng số slot là **chữ ký** kernel Metal (16 tham số `float4`), không truyền được | tự chốt (người dùng miễn duyệt): số slot cố định 8 trong kernel, test khoá `PointColorAdjustment.maximumCount == 8` (`PhotoColorModels.swift:201`); sửa câu §3 spec |
| AC-9 toàn pipeline | ❌ | — | golden 512×512 PNG trên `kernel-reference.jpg`, T3 |
| AC-10 video | ❌ | `VideoMaskRenderer.swift:128/150` dựng kernel mỗi lần gọi | T1 đưa lên `static let` (vẫn chuỗi), T7 port |
| AC-11 test cũ xanh | ✅ | PanoramaCIBlenderTests, PanoramaSeamBlendTests, PhotoHealingTests, PhotoStackRendererTests, FocusStack*Tests, LensProfileTests, MaskKindParityTests, EditorParityTests | chạy `/test` sau mỗi task, không sửa assertion |
| AC-12 footprint | ✅ | `FocusStackExportTests.swift:178` (≤ few×1.10+64 MB), `:192` (≤ 500 MB) | chạy sau T5, T6 |
| AC-13 golden thiếu → đỏ | ❌ | — | harness `#require` file, T1 |
| AC-14 0 chuỗi, 0 define | ❌ | define ở project Debug/Release `project.pbxproj:733/790` | T7 |

Thêm cách so (tự chốt, sửa §4 spec ở T1): giá trị trong [0,1] so 8-bit ≤ 1/255; giá trị ngoài [0,1]
(kernel cộng dồn, hiệu có dấu) so float, lệch ≤ 1/255 × max(1, |golden|).

## 3. Tái dùng

- Cách đọc pixel: context `NSNull` + `workingFormat .RGBAf` + `render(_:toBitmap:)` như
  `PanoramaCIBlenderTests.swift:20/96`, `PhotoHealingTests.swift:43`. Gom một bản vào support file mới.
- `expectClose(… tolerance: 2.0/255)` ở `PhotoStackRendererTests.swift` — cùng ý, bản mới dùng 1/255.
- Nơi gọi giữ nguyên chữ ký và nhánh `nil`; chỉ đổi dòng tạo kernel.
- Swift Testing (`@Test`, `#expect`, `#require`) — toàn bộ 140 file test dùng kiểu này.

## 4. File đổi

| Tầng | File | Mới / sửa |
|---|---|---|
| Kit | `ShotDexKit/Render/CoreImageKernelLibrary.swift` — nạp metallib một lần mỗi bundle, trả kernel theo tên, `assertionFailure` + `nil` khi thiếu | mới |
| Kit | `ShotDexKit/Render/Kernels/{Mask,Color,Detail,Optics,Healing,Stack,Panorama}Kernels.ci.metal` + `ColorHelpers.h` (hsv dùng chung) | mới |
| Kit | 9 file Swift ở §2 phạm vi spec: dòng `CI…Kernel(source:)` → bộ nạp | sửa |
| App | `ShotDex/Data/Sources/VideoMaskKernels.ci.metal`; `VideoMaskRenderer.swift` | mới / sửa |
| Build | `project.pbxproj`: target ShotDexKit + ShotDex thêm `MTL_COMPILER_FLAGS = -fcikernel`, `MTLLINKER_FLAGS = -cikernel`, `MTL_FAST_MATH = NO`; T7 gỡ `-Xcc -DCI_SILENCE_GL_DEPRECATION` | sửa |
| Test | `ShotDexTests/KernelGoldenSupport.swift` (ảnh vào, codec, so, record), `KernelGoldenTests.swift`, `KernelLibraryTests.swift`, `Fixtures/KernelGolden/*`, `Fixtures/kernel-reference.jpg` | mới |
| Docs | FS-16 (cột chứng minh, §3/§4), EX-01 (kit có kernel Metal + luật cờ `-fcikernel`), QA-01 (golden) | sửa |

**Harness golden:**
- Mỗi kernel có một ca: tên, nhóm, closure áp kernel lên ảnh vào (qua `static let` của nó; 5 kernel
  `private` — vignette, noiseResidual, noiseDetail, edgeMask, laplacian — hạ xuống `internal` ở T1).
- Ảnh vào 48×48 dựng bằng code: "patches" (lưới 4×4 ô: đen, trắng, 6 màu bão hoà, alpha 0, alpha 0,5,
  dải xám…) và "photo" (thu nhỏ `kernel-reference.jpg`). Kernel nhiều đầu vào nhận các ảnh lệch pha.
- Golden lưu RGBA half-float + zlib: `Fixtures/KernelGolden/<kernel>-<ca>.rgbah.zlib`. Ước tổng ~1,5 MB.
- Đọc/ghi qua `#filePath` (test chạy trên simulator, thấy ổ host). Có file đánh dấu
  `build/record-kernel-golden` (thư mục `build/` đã gitignore) thì ghi golden rồi **cố ý đỏ**, để chế độ
  ghi không bao giờ lọt qua gate.

## 5. Thứ tự task (một task = một commit)

| # | Task | AC | Test |
|---|---|---|---|
| C0 | Commit spec + README + intent (docs, riêng); commit plan này vào `docs/_plans/` | — | — |
| T1 | Harness golden, ảnh vào, chụp golden 40 kernel **bằng kernel chuỗi hiện tại**; kernel video lên `static let`; 5 kernel private → internal; sửa §3/§4 spec | AC-1, AC-13 | `KernelGoldenTests` xanh trên kernel chuỗi |
| T2 | Build Metal + bộ nạp + nhóm Mask (6) | AC-2 (mask), AC-4, AC-5, AC-6, AC-7 | golden mask, `KernelLibraryTests` |
| T3 | Color/Optics/Detail (7); biên dải hue HSL thành tham số lấy từ `ColorMixerBand.centerDegrees` | AC-2, AC-3, AC-8, AC-9 | golden + vùng con + pipeline |
| T4 | Heal (3); `healRingWeight` thành hàm dùng chung trong file Metal | AC-2 | golden + PhotoHealingTests |
| T5 | Photo Stack + Focus Stack (8) | AC-2, AC-12 | golden + FocusStack*Tests |
| T6 | Panorama (14) | AC-2, AC-12 | golden + Panorama*Tests |
| T7 | Video (2); gỡ define; grep 0 chuỗi kernel; Issue navigator 0 warning | AC-10, AC-14 | golden video 3 khung 1920×1080 (PNG 8-bit) |
| T8 | `/verify FS-16` + `Tools/gate` | tất cả | — |

Mỗi task: `/build`, `/test` cả bộ, sửa cột chứng minh của FS-16 và dòng `Tiến độ` của intent trong cùng
commit. Filter có sẵn của Apple chỉ thử cho đảo mask (`CIColorInvert`), giữ khi qua golden.

## 6. Rủi ro

| Rủi ro | Xác suất | Xử lý |
|---|---|---|
| **Checkout dùng chung**: `project.pbxproj` (239 dòng) và `PhotoRenderService.swift` (2 dòng) đang có thay đổi chưa commit của agent khác | chắc chắn | không `git add` cả file; lấy đúng hunk của mình qua `git diff … \| lọc \| git apply --cached`; kiểm `git diff --cached` trước mỗi commit |
| `MTL_FAST_MATH = YES` cấp project làm lệch phép chia | vừa | tắt cho Kit + app |
| CI Metal kernel không chạy trên simulator | thấp | T2 kiểm ngay kernel đầu tiên; hỏng thì dừng, báo |
| Kernel cộng dồn dựa vào working format half (`PhotoStackRenderer.swift:374`); context test dùng RGBAf | vừa | golden chụp và so trên cùng context test; pipeline AC-9 dùng renderer thật |
| Warp dùng lệch nửa pixel, lật y, điểm canh `(-1e5,-1e5)`; ROI của warp biên panorama bỏ qua chỉ số sampler | vừa | port nguyên hàm ROI; golden có ca biên ảnh |
| Ghi chú cũ: kernel màu lồng nhau bị gộp sai trên máy thật | thấp | giữ nguyên cách tách kernel như hôm nay; mở editor trên máy thật sau T3, T6 |
| Hook `build-check.py` chặn mọi warning của `.metal` | chắc chắn | sửa hết warning trong task, không thêm cờ tắt |
| Hai simulator cùng tên "iPhone 17" | đã biết | build/test bằng `id=` |

Agent chạy ở Deploy: `extension-boundary` (kit + bundle), `test-coverage` (harness), `perf-profiler`
(key video không còn dựng kernel mỗi khung).

## 7. Cách chứng minh là xong

- Test: `KernelGoldenTests` (40 kernel × 2 ca, vùng con, pipeline, video), `KernelLibraryTests`, cả bộ
  test cũ không sửa assertion, `Tools/gate` xanh.
- Màn hình: không đổi UI. Chụp editor một lần sau T3 (mask + HSL + vignette trên ảnh mẫu) để thấy hiệu
  ứng còn tác dụng.
- Tài liệu: FS-16 cột chứng minh, EX-01, QA-01; dòng `Tiến độ` của intent qua từng task.
