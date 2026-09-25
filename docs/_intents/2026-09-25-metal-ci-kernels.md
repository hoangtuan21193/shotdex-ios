# Intent: Chuyển kernel Core Image sang Metal

| Trường | Giá trị |
|---|---|
| Tác giả | hat.tuan |
| Ngày | 2026-09-25 |
| Trạng thái | draft |
| Tiến độ | **chưa làm** (2026-09-25) — chưa có spec |
| Nguồn | Issue navigator của Xcode (45 warning `init(source:)` deprecated) + hook `build-check.py` |
| Spec sinh ra từ đây | |

## Problem — vấn đề

Phần lớn những gì người chụp thấy khi sửa ảnh đi qua 40 kernel Core Image tự viết: cộng/trừ/đảo mask,
mask theo độ sáng và theo màu, HSL mixer, point color, color grading, vignette, lens warp, tách nhiễu,
healing, ghép panorama, focus stack, mask video. Cả 40 kernel viết bằng **Core Image Kernel Language**,
dạng chuỗi, mà Apple đã deprecated từ iOS 12:

| Kiểu | Số lượng |
|---|---|
| `CIColorKernel(source:)` | 36 |
| `CIKernel(source:)` | 2 |
| `CIWarpKernel(source:)` | 2 |

Các file có kernel: `ShotDexKit/Render/PhotoRenderService.swift` (8), `+Color` (3), `+Optics` (1),
`PhotoStackRenderer` (6), `PhotoHealingRenderer` (3), `FocusStackStreaming` (2), `LensProfileLibrary` (1),
`Panorama/PanoramaCIBlender` (13), `Panorama/PanoramaBoundaryWarp` (1), và
`ShotDex/Data/Sources/VideoMaskRenderer.swift` (2).

Hôm nay người dùng chưa thấy lỗi gì. Rủi ro nằm ở hai chỗ:

1. **Lỗi âm thầm.** Kernel dạng chuỗi được biên dịch lúc chạy. Chuỗi nào sai thì constructor trả về
   `nil`, và code đang làm đúng việc được bảo: bỏ qua, trả nguyên ảnh vào (ví dụ
   `guard let kernel = vignetteKernel else { return input }` ở `PhotoRenderService+Optics.swift:29`,
   cùng cách ở `+Color.swift:175/190/228`, `LensProfileLibrary.swift:200`, `PhotoStackRenderer.swift:316/356/361`).
   Người chụp kéo slider, không thấy gì đổi, và không có thông báo nào. Build vẫn xanh.
2. **Tương lai.** Apple có thể gỡ Kernel Language ở một bản iOS nào đó. Khi đó 40 tính năng tắt cùng lúc,
   và vì lỗi (1), sẽ tắt **âm thầm**.

45 warning hiện đã được tắt bằng `-Xcc -DCI_SILENCE_GL_DEPRECATION` (build setting cấp project) để hook
build không chặn mãi. Tắt được warning chứ không bớt được rủi ro nào ở trên.

Hai rủi ro trên đủ để phải chuyển sang Metal. Kernel dạng chuỗi còn được biên dịch lúc chạy, ở lần
dùng đầu mỗi phiên; Metal biên dịch lúc build nên bỏ luôn bước đó. Có khựng hay không không đổi quyết
định, nên không đo.

## Proposed outcome — kết quả mong muốn

- Kernel viết sai thì **build đỏ**, không để tới lúc người chụp kéo slider mới lặng lẽ không có gì xảy ra.
- Kernel biên dịch lúc build, không còn bước biên dịch chuỗi lúc chạy.
- Mọi filter đang có cho ra **đúng ảnh như hôm nay**, pixel khớp trong một ngưỡng sai số đặt trước.
- Không còn phụ thuộc API deprecated, và bỏ được define tắt warning.

## Affected users and systems — phạm vi ảnh hưởng

- **Tính năng**: editor ảnh (Adjust, Color, Optics, Detail/Noise, Mask, Heal), Panorama, Focus Stack /
  Photo Stack, Video Studio (mask video). Mọi nơi render qua `PhotoRenderService`, kể cả widget và
  share/edit extension.
- **Thiết bị**: mọi thiết bị. Render không phụ thuộc kích thước màn.
- **Tầng code**: chủ yếu `ShotDexKit/Render/` (framework), cộng một file ở `ShotDex/Data/Sources/`. Thêm
  bước build Metal cho Core Image (build rule / cờ `-fcikernel`, metallib đóng gói trong framework).
- **Dữ liệu đã lưu**: không đụng. Recipe giữ nguyên nghĩa. Nếu có khác biệt thì chỉ là sai số làm tròn
  của GPU; app chưa release nên không cần migration (CLAUDE.md, quyết định 2026-09-23).

## Constraints — ràng buộc

- **Không đổi ảnh ra.** Mỗi kernel phải có test so pixel trước/sau, chạy trên ảnh thật và ảnh biên
  (đen, trắng, bão hoà, alpha). Nhớ bẫy vùng con của `CIColorKernel`: phải thử cả pixel xa vùng sửa, với
  2 edit trở lên (memory `coreimage-color-kernel-region-trap`).
- **Kit vẫn thuần** (`extension-boundary`): không SwiftUI/GRDB. Metallib phải nạp được từ bundle của
  framework trong cả app lẫn extension.
- **Trần bộ nhớ extension (~120 MB)** không được tăng.
- Không thêm dependency. Deployment target vẫn iOS 17.
- Làm theo từng nhóm, mỗi nhóm một commit có test so ảnh. Không đổi cả 40 kernel một lượt.

## Open questions — câu hỏi còn treo

1. **Có kernel nào thay được bằng filter có sẵn của Apple không?** (ví dụ cộng/trừ mask so với
   `CIAdditionCompositing` / `CIMinimumCompositing`). Bớt được kernel nào thì đỡ phải port. *Ai:* spike.
2. **Thứ tự ưu tiên:** đề xuất mặc định là mask trước (dùng nhiều nhất, đang có `MaskKindParityTests`),
   rồi Color/Optics, rồi Panorama/Stack/Heal, cuối cùng là Video. *Ai:* hat.tuan.
3. **Ngưỡng sai số pixel** coi là "giống": đề xuất mặc định ≤ 1/255 mỗi kênh trên ảnh 8-bit. *Ai:* hat.tuan.
4. **Share/edit extension** nạp metallib của framework có vướng gì không (bundle lookup trong extension)?
   *Ai:* spike, kèm agent `extension-boundary`.

---

_Khi được duyệt: commit riêng một commit, rồi chạy `/spec` để sang giai đoạn Design._
