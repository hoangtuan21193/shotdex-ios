# Quy trình phát triển — AI-native SDLC cho ShotDex

Trả lời đúng một câu: **tôi gõ gì, và sau đó chuyện gì xảy ra.**

Nền lý thuyết: [AI-Native SDLC Playbook](https://claude.com/blog/the-ai-native-sdlc-playbook) —
sáu giai đoạn Plan → Design → Build → Test → Deploy → Maintain. Ánh xạ sang repo ở mục 7.

## 1. Ý chính trong 30 giây

Một thay đổi đi qua **bốn hiện vật**, không nhảy thẳng từ ý tưởng sang code:

```
intent.md    →    FS-*.md     →    plan.md      →    code + test
"vấn đề gì"      "đúng là gì"     "làm thế nào"      "làm rồi"
  bạn duyệt ✋     bạn duyệt ✋      bạn duyệt ✋        gate chặn 🚦
```

Claude viết cả bốn, bạn **duyệt ở ba chỗ**. Không có ba chỗ duyệt đó thì vẫn là vibe coding, chỉ thêm
giấy tờ. Mỗi hiện vật là **một commit riêng**, để `git diff` nói được "yêu cầu đã đổi cái gì".

## 2. Năm lệnh

| Lệnh | Gõ gì | Cần có sẵn | Ra file | Không đụng |
|---|---|---|---|---|
| `/intent` | kể vấn đề bằng lời thường | — | `docs/_intents/<ngày>-<slug>.md` — Problem · Outcome · Affected · Constraints · Open questions | `.swift`, spec, tiêu chí |
| `/spec` | `/spec FS-12` hoặc `/spec <đường dẫn intent>` | intent đã `accepted` | `docs/02-functional-spec/FS-xx…` — quan trọng nhất là **bảng tiêu chí nghiệm thu** | `.swift` |
| `/plan` | `/plan FS-12` | FS có bảng tiêu chí đã duyệt | `docs/_plans/<ngày>-<slug>.md` — bảng đối chiếu + thứ tự task + rủi ro | `.swift` |
| *(làm thật)* | `làm AC-1` | kế hoạch đã duyệt | một commit `feat(FS-12): AC-1 …` kèm test; cột "Chứng minh bằng" được cập nhật | — |
| `/verify` | `/verify FS-12` | — | bảng kết quả từng tiêu chí + ảnh chụp + **danh sách tiêu chí chưa chứng minh** | — |

- Mã FS mới: Claude tự cấp mã kế tiếp và tự đăng ký vào [README mục 3](README.md#3-cây-tài-liệu).
- `/spec` đánh dấu **`⚠️ CẦN QUYẾT:`** ở mọi chỗ phải đoán; bạn trả lời từng cái trước khi commit.
- `/verify` còn dòng chưa chứng minh được thì **chưa xong** — quay lại `/plan` cho phần thiếu.

Bảng đối chiếu của `/plan` có bốn trạng thái:

| | Nghĩa | Việc phải làm |
|---|---|---|
| ✅ | code đã đúng như tiêu chí | **không sửa code**, chỉ viết test khoá lại |
| ⚠️ | code làm khác tiêu chí | hỏi trước, rồi sửa một trong hai bên |
| ❌ | chưa có gì | viết mới kèm test |
| ❓ | chưa đọc đủ để kết luận | nói thẳng, cấm đoán |

## 3. Một vòng, rút gọn

```
/intent video studio hay lỗi, sửa chỗ này hỏng chỗ kia
        → docs/_intents/2026-09-21-video-studio-khong-co-luoi-an-toan.md → bạn sửa, accepted, commit
/spec FS-12
        → FS-12 có bảng tiêu chí + 2 dòng ⚠️ CẦN QUYẾT → bạn trả lời, commit
/plan FS-12
        → AC-1 ✅ VideoStudioModel.swift:412 · AC-2 ⚠️ undo gộp 2 bước · AC-6 ❌
        → đến đây CHƯA có dòng code nào bị sửa → bạn duyệt, commit
làm AC-1 → làm AC-2 → …   mỗi cái một commit kèm test
/verify FS-12 → xanh hết thì git push, hook chạy Tools/gate
```

## 4. Khi nào **không** cần đi hết vòng

| Việc | Đường đi |
|---|---|
| Sửa chữ, đổi màu, đổi icon | làm thẳng; build + chụp màn hình là đủ |
| Sửa bug | bỏ `/intent` và `/spec`. **Viết test đỏ trước**, bật `SHOTDEX_FREEZE_TESTS=1`, sửa code, rồi thêm bug đó thành một tiêu chí trong FS |
| Đổi hành vi đã có | bắt đầu từ `/spec` |
| Refactor không đổi hành vi | test hiện có chính là lưới an toàn |
| Tính năng mới, hoặc việc lớn không rõ | đi đủ bốn hiện vật |

**Càng không chắc thì càng nên đi đủ vòng.** Vòng đầy đủ tốn thêm ~30 phút giấy tờ, rẻ hơn nhiều so với
viết nhầm 31 file.

## 5. Cổng chặn — chạy tại máy, không CI

```bash
Tools/install-hooks
```

Từ đó mỗi `git push` chạy `Tools/gate` = build + toàn bộ unit test. Đỏ thì không push được.

| Lệnh | Khi nào | Thấy gì |
|---|---|---|
| `Tools/gate` | trước khi push (tự động), hoặc gõ tay | `gate: xanh (92s)` hoặc danh sách lỗi |
| `Tools/evals` | khi đụng `CLAUDE.md` hoặc `.claude/**` | `4/5 eval xanh` — chạy từ terminal đã đăng nhập `claude` |
| `Tools/bands-check` | định kỳ, hoặc khi thấy chậm/đỏ bất thường | bảng metric + cảnh báo khi vượt band |

Ba hook chặn tự động (`.claude/hooks/`):

| Hook chặn | Vì sao |
|---|---|
| `git push --no-verify` | đó là cách đi vòng qua gate |
| `xcodebuild archive`, `altool`, `notarytool` khi thiếu `RELEASE_APPROVAL` | nộp App Store phải có người chấp thuận |
| sửa file trong `ShotDexTests/` khi `SHOTDEX_FREEZE_TESTS=1` | sửa bug thì không được làm test xanh bằng cách sửa test |

## 6. Tiêu chí nghiệm thu viết thế nào

Dạng **Cho / Khi / Thì**:

> **AC-3.** **Cho** timeline 1 clip dài 10,0 s, playhead tại 4,0 s
> **Khi** bấm Split
> **Thì** có 2 clip `[0,0–4,0]` và `[4,0–10,0]`, tổng thời lượng không đổi, clip phải được chọn;
> một lần Undo trả về đúng 1 clip dài 10,0 s.
> _Chứng minh:_ `VideoStudioModelTests.splitAtPlayheadThenUndo`

Bốn yêu cầu:

1. đầu vào **có số**;
2. đúng **một** thao tác;
3. kết quả **quan sát được** — đọc ra từ test, hoặc nhìn ra trên ảnh chụp;
4. ghi rõ **chứng minh bằng gì**; chưa có thì ghi `⚠️ chưa có`, cấm để trống.

Sai: *"Split phải mượt và trực quan."* Từ cấm: mượt, trực quan, hợp lý, đẹp, nhanh (không kèm số).

Phải phủ cả **đường hỏng**: không mạng, ảnh chỉ có trên iCloud, quyền `.limited`, huỷ giữa chừng, undo,
hết bộ nhớ. Một màn bình thường cần 5–15 tiêu chí; dưới 5 là chưa nghĩ đủ.

## 7. File nào để ở đâu

| File | Ở đâu | Ai viết | Dùng để |
|---|---|---|---|
| `intent.md` | `docs/_intents/` | Claude, bạn duyệt | vấn đề và lý do |
| đặc tả `FS-*` | `docs/02-functional-spec/` | Claude, bạn duyệt | đúng là gì + tiêu chí nghiệm thu |
| `plan.md` | `docs/_plans/` | Claude, bạn duyệt | làm thế nào |
| mẫu | `docs/_templates/` | — | khung cho ba cái trên |
| `CLAUDE.md` · `REVIEW.md` · `bands.yaml` | gốc repo | bạn | quy ước · chính sách review · ngưỡng cảnh báo |
| eval · hook | `evals/` · `.claude/hooks/` | bạn | test cho cấu hình agent · cổng chặn |

## 8. Sáu giai đoạn ánh xạ sang repo

| Giai đoạn | Ở repo này |
|---|---|
| **Plan** | `/intent` → `docs/_intents/` |
| **Design** | `/spec` → `FS-*`, ràng buộc lấy từ `DESIGN.md` + `docs/04-non-functional-design/` |
| **Build** | `/plan` → `docs/_plans/`, rồi một AC một commit |
| **Test** | `/verify` + `Tools/gate` + `Tools/evals` |
| **Deploy** | `REVIEW.md` 3 lớp + hook + pre-push gate |
| **Maintain** | `bands.yaml` + `Tools/bands-check --intent` |

Vòng khép kín: `bands-check` phát hiện bất thường → sinh `intent.md` → chạy lại từ Plan. Phát hiện là
**định đoạt** (script tính bằng số học); model chỉ được gọi sau khi đã vượt ngưỡng, và bậc 1σ/2σ/3σ quy
định nó được phép làm gì.

## 9. Ba con số xem lại mỗi tháng

| Con số | Ý nghĩa |
|---|---|
| tiêu chí đã có chứng minh / tổng tiêu chí | độ phủ của định nghĩa "xong" |
| lỗi bị `Tools/gate` hoặc test bắt / tổng số lỗi | gần 1 là tốt; gần 0 nghĩa là vẫn bắt lỗi bằng mắt |
| số mục còn tồn trong `REVIEW_QUEUE.md` | nợ phát hiện muộn, phải giảm |
