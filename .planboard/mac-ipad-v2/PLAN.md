# ShotDex trên iPad, Mac và ảnh ở nhiều nơi — plan thực thi

> Chốt 2026-10-04, sau 1 vòng · nguồn: `.planboard/mac-ipad-v2/plan.json` · lý do: [DECISIONS.md](DECISIONS.md)

## Nguyên tắc

- **Một AC = một commit** (`feat(FS-xx): AC-n …`); `/build` sau mỗi commit, `/test <Class>` cho test của task, đụng UI
  thì `/screens` + `design-parity`. Full suite một lần khi xong intent.
- **Mỗi commit sửa dòng `Tiến độ`** của intent sở hữu: [macos-app](../../docs/_intents/2026-10-04-macos-app.md) (FS-19,
  FS-20, 08c, FS-18) hoặc [ipad-mac-style](../../docs/_intents/2026-10-04-ipad-mac-style.md) (FS-21).
- Task và tiêu chí "xong" nằm trong plan của từng FS — file này chỉ là thứ tự. Cần đi chệch một quyết định đã chốt:
  dừng lại, hỏi người dùng.
- AC cần máy thật ghi "chưa kiểm (cần máy thật)" và không chặn "xong" (Q10).

## Thứ tự

| # | Plan | Task | Ghi chú |
|---|---|---|---|
| 1 | [FS-19 nguồn ảnh](../../docs/_plans/2026-10-04-fs19-photo-sources.md) | 77 | đi đầu: nền dữ liệu (nguồn, bản sao, hash, sidecar, xoá theo đích) |
| 2 | [FS-20 nhập thẻ](../../docs/_plans/2026-10-04-fs20-card-ingest.md) | 28 | task 1–12 làm được ngay; 13 trở đi chờ FS-19 |
| — | [FS-01.08c Compare](../../docs/_plans/2026-10-04-fs0108c-compare-viewer-mode.md) | 26 | bắt đầu bất cứ lúc nào; task 21–26 chờ FS-19/FS-18 |
| 3 | [FS-21 iPad kiểu Mac](../../docs/_plans/2026-10-04-fs21-ipad-mac-style.md) | 59 | task 1–12 không chờ ai; sidebar Sources chờ FS-19 |
| 4 | [FS-18 app Mac](../../docs/_plans/2026-10-04-fs18-mac-app.md) | 94 | P1, A1, S1–S3 làm được ngay; T1 trở đi sau cả bốn plan trên |

## Bắt đầu với (FS-19, khoá phần đã đúng trước)

- [ ] **L1 — auth bị từ chối dừng lô, không hộp mật khẩu** (AC-36, phần ✅)
  - Xong khi: test xanh trên code hôm nay, không sửa code
  - Kiểm tra: `/test ServerSourceIndexTests/passwordRejectedNoPrompts`
- [ ] **L2 — Cancel hộp hệ thống → phần Photos không đổi** (AC-41, phần ✅; luật huỷ theo A7)
  - Kiểm tra: `/test MixedDeletionTests/photosCancelKeepsPhotosPart`
- [ ] **L3 — asset Photos không đọc sao trong file** (AC-52, phần ✅)
  - Kiểm tra: `/test SidecarReaderTests/cameraRatingFilesOnly`
- [ ] **L4 — Clear Local Metadata Index giữ sao/cờ** (AC-31, phần ✅)
  - Kiểm tra: `/test SidecarSettingTests/offKeepsMarksInDatabaseOnly`
- [ ] **W1 — `PreviewCache` ở Application Support, loại khỏi backup, trần 5 GB iOS; gộp `RemoteThumbnailCache`** (AC-47; A6)
  - Xong khi: test xanh, NF-02 + FS-08 sửa cùng commit, `/build` sạch
  - Kiểm tra: `/test PreviewCacheTests/locationAndDefaults`

Sau đó: W2, W3, rồi khối A (A1 migration `v30-photoSources` — chốt hình schema trước khi cài lên máy có dữ liệu).

## Ngoài phạm vi

- Kiểm trên máy thật: Mac macOS 15 (FS-18 AC-14), Mac + iPhone + iCloud/T7 (AC-44, 62, 63, 65), thẻ/đầu đọc thật
  (FS-20 AC-20, phần thật của AC-10, AC-27), phép đo M1–M3 của FS-19 — ghi "chưa kiểm (cần máy thật)" (Q10).
- Task cho màn chưa có AC: FS-21 (Trips, Places, trang album, Duplicates, Combine, Cull, cắt video, phím . và Space) và
  FS-18 Activity/Support — thêm sau `/spec` (A25, A30).
